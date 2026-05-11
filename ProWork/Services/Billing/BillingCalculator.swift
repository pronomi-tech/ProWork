//
//  BillingCalculator.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Spec §4 + §5 + §8 — Doğru ücretlendirme akışı:
//
//   1. Çalışma kaydını al
//   2. Todo bilgilerini çöz (müşteri/proje/kategori/hizmet tipi)
//   3. Faturalandırılabilir mi kontrol et
//   4. **Önce minimum pencere uygula** (session başlangıcından kayar):
//        N = ceil(actualMinutes / windowMinutes)
//        billableMinutes = N * windowMinutes
//        billableEndAt = startedAt + billableMinutes
//   5. **Sonra** billable aralığı (startedAt..billableEndAt) zaman tiplerine böl
//      → TimeWindowSplitter
//   6. Her zaman tipi parçası için fiyat satırını çöz (PriceListResolver)
//   7. Tutar = (unitPriceMinor * segmentMinutes) / 60
//   8. KDV her satıra ayrı uygulanır (VATCalculator)
//
//  Pencere kaynağı önceliği:
//   - Project.defaultMinBillingMinutes (varsa)
//   - Customer.defaultMinBillingMinutes
//   - PriceListRow seviyesindeki min pencere ARTIK kullanılmaz (session-level pencere mantığı).
//

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
    /// Tek bir oturum için faturalandırma satırlarını hesaplar.
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

        // 3. Faturalandırılabilirlik
        let categoryBillable = input.category?.isBillableDefault ?? true
        let isBillable = todo.isBillable && categoryBillable

        let actualSeconds = Int(endedAt.timeIntervalSince(session.startedAt))

        // Sabit fee override: süre bağımsız tek satır
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
            // 4. Pencere ve billable süresini belirle (session seviyesinde)
            let projectWindow = input.project?.defaultMinBillingMinutes
            let customerWindow = customer.defaultMinBillingMinutes
            let windowMinutes: Int? = projectWindow ?? customerWindow

            let actualMinutes = (actualSeconds + 59) / 60  // saniyeyi yukarı yuvarla
            billableMinutes = isBillable
                ? MinimumWindowApplier.apply(actualMinutes: actualMinutes, windowMinutes: windowMinutes)
                : 0

            // 5. Billable aralığı zaman tiplerine böl
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

        // 6-7. Her zaman tipi parçası için satır üret
        var lines: [BillingReportLine] = []
        var subtotalMinor = 0
        var vatMinor = 0
        var resultCurrency: String = input.priceContext.effectiveCurrency()

        for (idx, segment) in segments.enumerated() {
            let segmentSeconds = segment.durationSeconds

            let (line, lineSubtotal, lineVat) = makeLine(
                segment: segment,
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
            vatMinor += lineVat
            resultCurrency = line.currency
        }

        return BillingCalculationOutput(
            lines: lines,
            subtotalMinor: subtotalMinor,
            vatMinor: vatMinor,
            totalMinor: subtotalMinor + vatMinor,
            currency: resultCurrency
        )
    }

    /// Billable dakikayı segmentlere saniye oranını koruyarak dağıtır.
    /// Her segmenti ayrı ayrı `ceil` etmek toplamı şişirebildiği için
    /// taban dakika + en büyük kalan yöntemi uygulanır.
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

    /// Verilen zaman tipi parçası için satır üretir.
    /// `segmentBillableMinutes` = session-level billable sürenin bu segmente düşen kısmı.
    private static func makeLine(
        segment: TimeSegment,
        segmentIndex: Int,
        segmentSeconds: Int,
        segmentBillableMinutes: Int,
        input: BillingCalculationInput,
        runId: String,
        isBillable: Bool,
        serviceType: ServiceType,
        calendar: Calendar
    ) -> (line: BillingReportLine, subtotal: Int, vat: Int) {
        let weekday = Weekday.from(date: segment.start, calendar: calendar)
        let timeOfDay = TimeOfDay.from(date: segment.start, calendar: calendar)
        let dateString = Holiday.dateFormatter.string(from: segment.start)

        // Fiyat çözümle (zaman tipine + hizmet + kategori)
        let resolution = PriceListResolver.resolve(
            context: input.priceContext,
            serviceType: serviceType,
            timeType: segment.timeType,
            categoryId: input.category?.id,
            weekday: weekday,
            timeOfDay: timeOfDay,
            dateString: dateString
        )

        // Birim ücret ve currency
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

        // Tutar = saatlik ücret * dakika / 60
        let amountMinor = isBillable ? (unitPriceMinor * segmentBillableMinutes) / 60 : 0

        // KDV
        let vatResult = isBillable && amountMinor > 0
            ? input.vatCalculator.calculate(
                subtotalMinor: amountMinor,
                customerVatRateId: input.customer.vatRateId,
                projectVatRateId: input.project?.vatRateId,
                categoryVatRateId: input.category?.vatRateId,
                dateString: dateString
            )
            : VATCalculationResult(rate: 0, vatMinor: 0, totalMinor: amountMinor, isExempt: false, origin: .none)

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
            vatRate: vatResult.rate,
            vatMinor: vatResult.vatMinor,
            totalMinor: amountMinor + vatResult.vatMinor,
            isVatExempt: isBillable && vatResult.isExempt,
            isBillable: isBillable,
            isManual: input.session.isManual,
            isFixedFee: false,
            startedAt: segment.start,
            endedAt: segment.end,
            note: input.session.note,
            sortOrder: segmentIndex,
            organizationId: input.todo.organizationId
        )

        return (line, amountMinor, vatResult.vatMinor)
    }
}
