//  BillingCalculator.swift
//  ProWork
//  Created by Pronomi.
//  Spec §4 + §5 + §8 — The correct billing flow:
//   1. Read the work record
//   2. Resolve the todo info (customer/project/category/service type)
//   3. Check whether it's billable
//   4. **First apply the minimum window** (sliding from session start):
//        N = ceil(actualMinutes / windowMinutes)
//        billableMinutes = N * windowMinutes
//        billableEndAt = startedAt + billableMinutes
//   5. **Then** split the billable range (startedAt..billableEndAt) by time type
//      → TimeWindowSplitter
//   6. Resolve the price row for each time-type chunk (PriceListResolver)
//   7. Amount is computed via `Money.fromHourlyRate(unitPrice, billableMinutes:)`
//      — Decimal arithmetic + banker's round. The old integer
//      `(unitPriceMinor * minutes) / 60` formula could lose up to 1
//      minor per row.
//   8. VAT is computed **once** for every line in the session and
//      distributed across lines with `LargestRemainderAllocator`. The
//      old algorithm applied banker's round per segment and summed;
//      multi-segment sessions accumulated ±1-3 minor of drift.
//  Window source priority:
//   - Project.defaultMinBillingMinutes (varsa)
//   - Customer.defaultMinBillingMinutes
//   - PriceListRow.minimumWindowMinutes: deliberately NOT consulted.
//     The column persists in the schema (Migration001 + model + repo
//     bindings) so older runs round-trip cleanly, but session-level
//     window resolution now lives entirely at the project/customer
//     level. The field is kept rather than removed because dropping
//     it would require an immutability-breaking migration; if a future
//     tier wants per-row pencereler back, re-introduce the lookup
//     here and (optionally) remove the project/customer fallback.
// so the dead-but-persisted column is at least
//     explicitly documented.

import Foundation

struct BillingCalculationInput {
    let session: TodoTimeSession
    let todo: Todo
    let customer: Customer
    let project: Project?
    let category: TaskCategory?
    let rule: BillingRule
    let holidays: [Holiday]
    let priceContext: PriceResolutionContext
    let vatCalculator: VATCalculator
    let billingWindowOverride: BillingWindowOverride?

    init(
        session: TodoTimeSession,
        todo: Todo,
        customer: Customer,
        project: Project?,
        category: TaskCategory?,
        rule: BillingRule,
        holidays: [Holiday],
        priceContext: PriceResolutionContext,
        vatCalculator: VATCalculator,
        billingWindowOverride: BillingWindowOverride? = nil
    ) {
        self.session = session
        self.todo = todo
        self.customer = customer
        self.project = project
        self.category = category
        self.rule = rule
        self.holidays = holidays
        self.priceContext = priceContext
        self.vatCalculator = vatCalculator
        self.billingWindowOverride = billingWindowOverride
    }
}

struct BillingWindowOverride: Hashable {
    let billableMinutes: Int
    let splitTo: Date?
}

struct BillingCalculationOutput: Hashable {
    let lines: [BillingReportLine]
    let subtotalMinor: Int
    let vatMinor: Int
    let totalMinor: Int
    let currency: String
}

enum BillingCalculator {
    /// Computes billing lines for a single session.
    static func calculate(
        input: BillingCalculationInput,
        runId: String,
        calendar: Calendar = TimeWindowSplitter.istanbulCalendar
    ) -> BillingCalculationOutput {
        let session = input.session
        let todo = input.todo
        let customer = input.customer

        guard let endedAt = session.endedAt, endedAt > session.startedAt else {
            return BillingCalculationOutput(
                lines: [],
                subtotalMinor: 0,
                vatMinor: 0,
                totalMinor: 0,
                currency: input.priceContext.effectiveCurrency()
            )
        }

        // 3. Billable check
        let categoryBillable = input.category?.isBillableDefault ?? true
        let isBillable = todo.isBillable && categoryBillable

        let actualSeconds = Int(endedAt.timeIntervalSince(session.startedAt))

        // Fixed-fee override: a single line independent of duration
        if let override = input.priceContext.todoOverride,
           override.deletedAt == nil,
           override.overrideType == .fixedFee,
           let fee = override.fixedFeeMinor {
            return makeFixedFeeOutput(
                fee: fee,
                currency: override.currency,
                input: input,
                runId: runId,
                isBillable: isBillable,
                actualSeconds: actualSeconds
            )
        }

        let billableMinutes: Int
        let splitTo: Date
        if let override = input.billingWindowOverride {
            billableMinutes = max(0, override.billableMinutes)
            splitTo = override.splitTo ?? endedAt
        } else {
            // 4. Determine the window and billable duration (at session level)
            let projectWindow = input.project?.defaultMinBillingMinutes
            let customerWindow = customer.defaultMinBillingMinutes
            let windowMinutes: Int? = projectWindow ?? customerWindow

            let actualMinutes = (actualSeconds + 59) / 60  // round seconds up
            billableMinutes = isBillable
                ? MinimumWindowApplier.apply(actualMinutes: actualMinutes, windowMinutes: windowMinutes)
                : 0

            // 5. Split the billable range by time type
            let billableEndAt = session.startedAt.addingTimeInterval(TimeInterval(billableMinutes * 60))
            splitTo = isBillable ? billableEndAt : endedAt
        }

        let splitFrom = session.startedAt

        let segments = TimeWindowSplitter.split(
            from: splitFrom,
            to: splitTo,
            rule: input.rule,
            holidays: input.holidays,
            calendar: calendar
        )
        let segmentBillableMinutes = allocateBillableMinutes(
            across: segments,
            totalBillableMinutes: isBillable ? billableMinutes : 0
        )

        let serviceType = ServiceType(rawValue: customer.defaultServiceType) ?? .remote

        // 6-7. Produce a line for each time-type chunk (VAT not yet applied).
        var lines: [BillingReportLine] = []
        var subtotalMinor = 0
        var resultCurrency: String = input.priceContext.effectiveCurrency()

        // Per-segment makeLine used to re-call
        // Holiday.dateFormatter.string(from:) for each segment even when
        // all segments belonged to the same calendar day. Pre-compute a
        // day-keyed cache so consecutive same-day segments share one
        // string conversion. Bounded by the segment count so memory is
        // O(distinct days touched by the session) — typically 1, rarely
        // more than 2.
        var dateStringByDay: [Date: String] = [:]
        for (idx, segment) in segments.enumerated() {
            let segmentSeconds = segment.durationSeconds
            let segmentDay = calendar.startOfDay(for: segment.start)
            let segmentDateString = dateStringByDay[segmentDay] ?? {
                let value = Holiday.dateFormatter.string(from: segment.start)
                dateStringByDay[segmentDay] = value
                return value
            }()

            let (line, lineSubtotal) = makeLine(
                segment: segment,
                dateString: segmentDateString,
                segmentIndex: idx,
                segmentSeconds: segmentSeconds,
                segmentBillableMinutes: segmentBillableMinutes[idx],
                input: input,
                runId: runId,
                isBillable: isBillable,
                serviceType: serviceType,
                calendar: calendar
            )
            lines.append(line)
            subtotalMinor += lineSubtotal
            resultCurrency = line.currency
        }

        // 8. VAT computed once at the session level + distributed per line.
        //    All segments in a session bind to the same customer/project/category,
        //    so the resolved rate is identical; one banker's round over
        //    the total → distribute across lines with largest-remainder.
        let vatMinor = applyVATToLines(
            &lines,
            subtotalMinor: subtotalMinor,
            isBillable: isBillable,
            input: input
        )

        return BillingCalculationOutput(
            lines: lines,
            subtotalMinor: subtotalMinor,
            vatMinor: vatMinor,
            totalMinor: subtotalMinor + vatMinor,
            currency: resultCurrency
        )
    }

    /// Computes VAT once for the session and distributes the total VAT
    /// across lines weighted by `amountMinor`. Updates every line's
    /// `vatRate` / `isVatExempt` fields with the shared result and
    /// returns the total VAT (minor).
    private static func applyVATToLines(
        _ lines: inout [BillingReportLine],
        subtotalMinor: Int,
        isBillable: Bool,
        input: BillingCalculationInput
    ) -> Int {
        // Refunds/credit notes are represented with a
        // negative subtotal; the previous `> 0` guard zeroed VAT for those
        // rows entirely, leaving the customer with a credit that didn't
        // reverse the VAT they were originally charged. Use `!= 0` so
        // negative subtotals get their proportional negative VAT.
        guard isBillable, subtotalMinor != 0 else {
            return 0
        }

        let firstStart = lines.first?.startedAt ?? input.session.startedAt
        let dateString = Holiday.dateFormatter.string(from: firstStart)

        let vatResult = input.vatCalculator.calculate(
            subtotalMinor: subtotalMinor,
            customerVatRateId: input.customer.vatRateId,
            projectVatRateId: input.project?.vatRateId,
            categoryVatRateId: input.category?.vatRateId,
            dateString: dateString
        )

        let weights = lines.map { $0.amountMinor }
        let perLineVAT = LargestRemainderAllocator.allocate(
            total: vatResult.vatMinor,
            weights: weights
        )

        for index in lines.indices {
            lines[index].vatRate = vatResult.rate
            lines[index].vatMinor = perLineVAT[index]
            lines[index].totalMinor = lines[index].amountMinor + perLineVAT[index]
            lines[index].isVatExempt = vatResult.isExempt
        }

        return vatResult.vatMinor
    }

    /// Distributes billable minutes across segments while preserving the
    /// seconds ratio. Applying `ceil` per segment can inflate the total,
    /// so a floor-minutes + largest-remainder method is used.
    private static func allocateBillableMinutes(
        across segments: [TimeSegment],
        totalBillableMinutes: Int
    ) -> [Int] {
        BillableMinuteAllocator.allocate(
            durationSeconds: segments.map(\.durationSeconds),
            totalBillableMinutes: totalBillableMinutes
        )
    }

    // MARK: - Fixed fee output

    private static func makeFixedFeeOutput(
        fee: Int,
        currency: String,
        input: BillingCalculationInput,
        runId: String,
        isBillable: Bool,
        actualSeconds: Int
    ) -> BillingCalculationOutput {
        let session = input.session
        let dateString = Holiday.dateFormatter.string(from: session.startedAt)

        let vatResult = isBillable
            ? input.vatCalculator.calculate(
                subtotalMinor: fee,
                customerVatRateId: input.customer.vatRateId,
                projectVatRateId: input.project?.vatRateId,
                categoryVatRateId: input.category?.vatRateId,
                dateString: dateString
            )
            : VATCalculationResult(rate: 0, vatMinor: 0, totalMinor: fee, isExempt: false, origin: .none)

        let billingFee = isBillable ? fee : 0
        let billingVat = isBillable ? vatResult.vatMinor : 0

        let line = BillingReportLine(
            runId: runId,
            sessionId: session.id,
            todoId: input.todo.id,
            todoTitle: input.todo.title,
            projectId: input.project?.id,
            projectName: input.project?.name,
            customerId: input.customer.id,
            customerName: input.customer.name,
            categoryId: input.category?.id,
            categoryName: input.category?.name,
            serviceType: ServiceType(rawValue: input.customer.defaultServiceType) ?? .remote,
            timeType: .regular,
            segmentIndex: 0,
            actualSeconds: actualSeconds,
            billableMinutes: 0,
            unitPriceMinor: 0,
            fixedFeeMinor: fee,
            amountMinor: billingFee,
            currency: currency,
            vatRate: vatResult.rate,
            vatMinor: billingVat,
            totalMinor: billingFee + billingVat,
            isVatExempt: isBillable && vatResult.isExempt,
            isBillable: isBillable,
            isManual: session.isManual,
            isFixedFee: true,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            note: session.note,
            sortOrder: 0,
            organizationId: input.todo.organizationId
        )

        return BillingCalculationOutput(
            lines: [line],
            subtotalMinor: billingFee,
            vatMinor: billingVat,
            totalMinor: billingFee + billingVat,
            currency: currency
        )
    }

    // MARK: - Per-segment line

    /// Produces a line for the given time-type chunk.
    /// `segmentBillableMinutes` = the share of the session-level billable
    /// duration that falls into this segment.
    /// VAT fields (`vatRate`, `vatMinor`, `totalMinor`, `isVatExempt`)
    /// are left as 0/false here; after every segment of the session is
    /// produced, `applyVATToLines` computes and distributes them in one pass.
    private static func makeLine(
        segment: TimeSegment,
        dateString: String,
        segmentIndex: Int,
        segmentSeconds: Int,
        segmentBillableMinutes: Int,
        input: BillingCalculationInput,
        runId: String,
        isBillable: Bool,
        serviceType: ServiceType,
        calendar: Calendar
    ) -> (line: BillingReportLine, subtotal: Int) {
        let weekday = Weekday.from(date: segment.start, calendar: calendar)
        let timeOfDay = TimeOfDay.from(date: segment.start, calendar: calendar)

        // Resolve price (by time type + service + category)
        let resolution = PriceListResolver.resolve(
            context: input.priceContext,
            serviceType: serviceType,
            timeType: segment.timeType,
            categoryId: input.category?.id,
            weekday: weekday,
            timeOfDay: timeOfDay,
            dateString: dateString
        )

        // Unit price and currency
        let (unitPriceMinor, currency): (Int, String) = {
            switch resolution {
            case .row(let row, _):
                return (row.unitPriceMinor, row.currency)
            case .todoUnitPriceOverride(let unit, let cur):
                return (unit, cur)
            case .todoFixedFee, .noMatch:
                return (0, input.priceContext.effectiveCurrency(dateString: dateString))
            }
        }()

        // Amount = hourly rate * minutes / 60.
        // We compute with Decimal arithmetic and convert to the minor
        // unit via banker's rounding; integer division would accumulate
        // up to 1 minor of loss per line.
        let amountMinor: Int = {
            guard isBillable else { return 0 }
            let unitPrice = Money(minorUnits: unitPriceMinor, currency: currency)
            return Money.fromHourlyRate(unitPrice, billableMinutes: segmentBillableMinutes).minorUnits
        }()

        let line = BillingReportLine(
            runId: runId,
            sessionId: input.session.id,
            todoId: input.todo.id,
            todoTitle: input.todo.title,
            projectId: input.project?.id,
            projectName: input.project?.name,
            customerId: input.customer.id,
            customerName: input.customer.name,
            categoryId: input.category?.id,
            categoryName: input.category?.name,
            serviceType: serviceType,
            timeType: segment.timeType,
            segmentIndex: segmentIndex,
            actualSeconds: segmentSeconds,
            billableMinutes: segmentBillableMinutes,
            unitPriceMinor: unitPriceMinor,
            fixedFeeMinor: nil,
            amountMinor: amountMinor,
            currency: currency,
            vatRate: 0,
            vatMinor: 0,
            totalMinor: amountMinor,
            isVatExempt: false,
            isBillable: isBillable,
            isManual: input.session.isManual,
            isFixedFee: false,
            startedAt: segment.start,
            endedAt: segment.end,
            note: input.session.note,
            sortOrder: segmentIndex,
            organizationId: input.todo.organizationId
        )

        return (line, amountMinor)
    }
}
