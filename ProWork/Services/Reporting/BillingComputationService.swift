//  BillingComputationService.swift
//  ProWork
//  Created by Pronomi.
//  Produces BillingReportLine's by feeding all sessions for a period to BillingCalculator.
//  Orchestrates the repositories; the single entry point for reporting screens.

import Foundation

final class BillingComputationService {
    private let organizationId: String

    private let organizationRepository: OrganizationRepository
    private let customerRepository: CustomerRepository
    private let projectRepository: ProjectRepository
    private let categoryRepository: TaskCategoryRepository
    private let todoRepository: TodoRepository
    private let sessionRepository: TodoTimeSessionRepository
    private let priceListRepository: PriceListRepository
    private let priceListRowRepository: PriceListRowRepository
    private let billingRuleRepository: BillingRuleRepository
    private let holidayRepository: HolidayRepository
    private let vatRateRepository: VatRateRepository
    private let overrideRepository: TodoBillingOverrideRepository
    /// Clock for test and preview flows that can fake "now".
    /// Production code returns the real `Date()` via the
    /// `SystemAppClock` default; in tests a fixed clock can be injected.
    private let clock: AppClock

    init(
        organizationId: String? = nil,
        organizationRepository: OrganizationRepository? = nil,
        customerRepository: CustomerRepository? = nil,
        projectRepository: ProjectRepository? = nil,
        categoryRepository: TaskCategoryRepository? = nil,
        todoRepository: TodoRepository? = nil,
        sessionRepository: TodoTimeSessionRepository? = nil,
        priceListRepository: PriceListRepository? = nil,
        priceListRowRepository: PriceListRowRepository? = nil,
        billingRuleRepository: BillingRuleRepository? = nil,
        holidayRepository: HolidayRepository? = nil,
        vatRateRepository: VatRateRepository? = nil,
        overrideRepository: TodoBillingOverrideRepository? = nil,
        clock: AppClock? = nil
    ) {
        self.organizationId = organizationId ?? BuiltInOrganizationId.default
        self.organizationRepository = organizationRepository ?? OrganizationRepository()
        self.customerRepository = customerRepository ?? CustomerRepository()
        self.projectRepository = projectRepository ?? ProjectRepository()
        self.categoryRepository = categoryRepository ?? TaskCategoryRepository()
        self.todoRepository = todoRepository ?? TodoRepository()
        self.sessionRepository = sessionRepository ?? TodoTimeSessionRepository()
        self.priceListRepository = priceListRepository ?? PriceListRepository()
        self.priceListRowRepository = priceListRowRepository ?? PriceListRowRepository()
        self.billingRuleRepository = billingRuleRepository ?? BillingRuleRepository()
        self.holidayRepository = holidayRepository ?? HolidayRepository()
        self.vatRateRepository = vatRateRepository ?? VatRateRepository()
        self.overrideRepository = overrideRepository ?? TodoBillingOverrideRepository()
        self.clock = clock ?? SystemAppClock()
    }

    /// Produces lines for all finished sessions in the given date range.
    /// `kind` determines the purpose of the output; a type-safe enum is used
    /// instead of the legacy "preview" / "draft-preview" string constants.
    func computePeriod(
        from startDate: Date,
        to endDate: Date,
        kind: BillingRunKind = .livePreview
    ) throws -> [BillingReportLine] {
        try computePeriodInternal(
            from: startDate,
            to: endDate,
            kind: kind,
            customerIdFilter: nil
        )
    }

    /// Previously computePeriod(customerId:) computed the
    /// full organisation result and filtered in-memory, which is wasteful
    /// for large orgs where a per-customer report is requested. Push the
    /// filter into the iteration so we never construct lines for other
    /// customers.
    func computePeriod(
        customerId: String,
        from startDate: Date,
        to endDate: Date,
        kind: BillingRunKind = .livePreview
    ) throws -> [BillingReportLine] {
        try computePeriodInternal(
            from: startDate,
            to: endDate,
            kind: kind,
            customerIdFilter: customerId
        )
    }

    private func computePeriodInternal(
        from startDate: Date,
        to endDate: Date,
        kind: BillingRunKind,
        customerIdFilter: String?
    ) throws -> [BillingReportLine] {
        let organization = try organizationRepository.fetch(id: organizationId)
        let organizationBillingWindowMode = organization?.billingWindowMode ?? .timeline
        let organizationCurrency = organization?.masterCurrency ?? BillingDefaults.fallbackCurrency

        // 1. Load all reference data
        let customers = try customerRepository.fetchAll()
        let categories = try categoryRepository.fetchAll()
        let billingRules = [
            try billingRuleRepository.fetchGlobal(organizationId: organizationId)
        ].compactMap { $0 }
        let holidays = try holidayRepository.fetchAll(organizationId: organizationId)
        let vatRates = try vatRateRepository.fetchAll(organizationId: organizationId)
        let priceLists = try priceListRepository.fetchAll(organizationId: organizationId)

        // Bulk fetch instead of N+1. The old loop issued one
        // SQL per price list — a tenant with dozens of customer-scoped
        // lists generated dozens of round-trips on every report. The
        // bulk overload returns the same { listId → rows } shape.
        let rowsByListId = try priceListRowRepository.fetchAll(
            priceListIds: priceLists.map(\.id)
        )

        let vatCalculator = VATCalculator(rates: vatRates)

        // For per-customer reports, push the filter into SQL
        // instead of fetching every org session. For org-wide reports
        // we still use the broad fetcher.
        let includesOpenSessions = kind.includesOpenSessions
        let runId = kind.lineRunId
        let allListItems: [WorkSessionListItem]
        if let customerIdFilter {
            allListItems = try sessionRepository.fetchAllListItems(forCustomerId: customerIdFilter)
        } else {
            allListItems = try sessionRepository.fetchAllListItems()
        }

        let periodItems = allListItems.filter { item in
            // Customer pre-filter is now SQL-side; we only need the
            // date window check here.
            if let endedAt = item.endedAt {
                return endedAt >= startDate && item.startedAt <= endDate
            }
            return includesOpenSessions && item.startedAt <= endDate
        }

        // Customer name is NOT unique in the schema, so
        // `Dictionary(uniqueKeysWithValues:)` would trap on a duplicate.
        // Build the id-keyed map first (id IS unique) and use a
        // collision-tolerant fallback for the name-based lookup that
        // some legacy items rely on.
        let customersById: [String: Customer] = Dictionary(
            uniqueKeysWithValues: customers.map { ($0.id, $0) }
        )
        let customersByName: [String: Customer] = Dictionary(
            customers.map { ($0.name, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        // 3. Bulk-fetch the todo / session / project / override data needed for the period.
        // In the old flow each session triggered 4-6 separate queries (todo, session,
        // project, override, billing rule); an N+1 explosion at 1,000-row periods.
        let todoIds = Array(Set(periodItems.map { $0.todoId }))
        let sessionIds = periodItems.map { $0.id }

        let todosById = Dictionary(
            uniqueKeysWithValues: (try todoRepository.fetch(ids: todoIds)).map { ($0.id, $0) }
        )
        let sessionsById = Dictionary(
            uniqueKeysWithValues: (try sessionRepository.fetch(ids: sessionIds)).map { ($0.id, $0) }
        )
        let projectIds = Array(Set(todosById.values.compactMap { $0.projectId }))
        let projectsById = Dictionary(
            uniqueKeysWithValues: (try projectRepository.fetch(ids: projectIds)).map { ($0.id, $0) }
        )
        let overridesByTodoId = try overrideRepository.fetch(todoIds: todoIds)

        // Y14: Pre-fetch customer-specific rules in a single SELECT. In the old
        // flow `resolve()` was called one-by-one as each new customer was seen —
        // 200 extra queries for a period spanning 200 customers. `customerRulesById`
        // does a single table scan.
        // `(try? …) ?? [:]` previously swallowed every DB error
        // and silently fell back to the global rule for every customer.
        // Propagate so a transient lock / corruption surfaces instead of
        // mis-billing.
        let customerRulesById = try billingRuleRepository.fetchAllCustomerScoped(organizationId: organizationId)
        let globalRule = billingRules.first

        // O(1) per-item lookup tables. Per-iteration
        // `customers.first(where:)` and `categories.first(where:)` made
        // the inner loop O(N²) over the org's customer + category lists.
        let categoriesById: [String: TaskCategory] = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0) }
        )

        // Pre-group holidays by customerId once. Global rows
        // live under the empty-string key so the per-item lookup is two
        // dictionary fetches plus a single concat — no O(holidays.count)
        // filter per session.
        var globalHolidays: [Holiday] = []
        var holidaysByCustomerId: [String: [Holiday]] = [:]
        for holiday in holidays {
            switch holiday.scope {
            case .global:
                globalHolidays.append(holiday)
            case .customer:
                if let customerId = holiday.customerId {
                    holidaysByCustomerId[customerId, default: []].append(holiday)
                }
            }
        }

        var lines: [BillingReportLine] = []
        var orderIndex = 0
        var calculationItems: [CalculationItem] = []

        for item in periodItems {
            guard let todo = todosById[item.todoId] else { continue }

            // Resolve customer/project — id lookup is O(1) via customersById; name
            // fallback covers legacy items that pre-date the FK.
            let customer: Customer? = todo.customerId.flatMap { customersById[$0] }
                ?? item.customerName.flatMap { customersByName[$0] }

            guard let customer else { continue }

            let project = todo.projectId.flatMap { projectsById[$0] }

            let category = categoriesById[todo.categoryId]

            // Apply the customer-specific rule if present, otherwise the global rule.
            // Thanks to the bulk fetch (Y14) we don't hit the DB.
            let rule = customerRulesById[customer.id] ?? globalRule
            guard let resolvedRule = rule else { continue }

            // Customer-specific holidays (pre-grouped).
            let customerHolidays = globalHolidays + (holidaysByCustomerId[customer.id] ?? [])

            // Price resolver context (override was batch-fetched earlier)
            let priceContext = makePriceContext(
                priceLists: priceLists,
                rowsByListId: rowsByListId,
                customer: customer,
                project: project,
                organizationCurrency: organizationCurrency,
                override: overridesByTodoId[todo.id]
            )

            // Pull the session from the pre-loaded map
            guard let session = sessionsById[item.id] else { continue }
            let isOpenSession = session.endedAt == nil
            let calculationSession: TodoTimeSession
            if includesOpenSessions, isOpenSession {
                calculationSession = TodoTimeSession(
                    id: session.id,
                    todoId: session.todoId,
                    startedAt: session.startedAt,
                    runningSinceAt: session.runningSinceAt,
                    pausedAt: session.pausedAt,
                    endedAt: min(clock.now(), endDate),
                    durationSeconds: session.durationSeconds,
                    startStatusId: session.startStatusId,
                    endStatusId: session.endStatusId,
                    note: session.note,
                    isManual: session.isManual,
                    meta: session.meta
                )
            } else {
                calculationSession = session
            }

            let input = BillingCalculationInput(
                session: calculationSession,
                todo: todo,
                customer: customer,
                project: project,
                category: category,
                rule: resolvedRule,
                holidays: customerHolidays,
                priceContext: priceContext,
                vatCalculator: vatCalculator
            )
            calculationItems.append(
                CalculationItem(
                    input: input,
                    isOpenSession: isOpenSession
                )
            )
        }

        let timelineOverrides = makeTimelineOverrides(
            from: calculationItems,
            organizationMode: organizationBillingWindowMode
        )

        for item in calculationItems {
            // Large-period report computations were not
            // cancellable; a long run blocked any subsequent request.
            // Surface cancellation between sessions so a UI dismiss can
            // actually stop work.
            try Task.checkCancellation()
            let output = BillingCalculator.calculate(
                input: item.input.withBillingWindowOverride(timelineOverrides[item.input.session.id]),
                runId: runId
            )
            for var line in output.lines {
                if includesOpenSessions,
                   item.isOpenSession {
                    line.endedAt = nil
                }
                line.sortOrder = orderIndex
                orderIndex += 1
                lines.append(line)
            }
        }

        return lines
    }

    // MARK: - PriceContext

    private func makePriceContext(
        priceLists: [PriceList],
        rowsByListId: [String: [PriceListRow]],
        customer: Customer,
        project: Project?,
        organizationCurrency: String,
        override: TodoBillingOverride?
    ) -> PriceResolutionContext {
        let projectLists = priceLists.filter {
            $0.ownerType == .project && $0.ownerId == project?.id
        }
        let customerLists = priceLists.filter {
            $0.ownerType == .customer && $0.ownerId == customer.id
        }
        let globalLists = priceLists.filter { $0.ownerType == .global }

        return PriceResolutionContext(
            todoOverride: override,
            projectPriceLists: projectLists,
            customerPriceLists: customerLists,
            globalPriceLists: globalLists,
            customerDefaultPriceListId: customer.defaultPriceListId,
            organizationCurrency: organizationCurrency,
            rowsByListId: rowsByListId
        )
    }

    private struct CalculationItem {
        let input: BillingCalculationInput
        let isOpenSession: Bool

        var actualSeconds: Int {
            guard let endedAt = input.session.endedAt else { return 0 }
            return max(0, Int(endedAt.timeIntervalSince(input.session.startedAt)))
        }

        var isBillable: Bool {
            let categoryBillable = input.category?.isBillableDefault ?? true
            return input.todo.isBillable && categoryBillable
        }

        var hasFixedFeeOverride: Bool {
            guard let override = input.priceContext.todoOverride,
                  override.deletedAt == nil,
                  override.overrideType == .fixedFee else {
                return false
            }
            return override.fixedFeeMinor != nil
        }

        var effectiveWindowMinutes: Int {
            input.project?.defaultMinBillingMinutes ?? input.customer.defaultMinBillingMinutes
        }

        func effectiveBillingWindowMode(organizationMode: BillingWindowMode) -> BillingWindowMode {
            input.project?.billingWindowMode ?? organizationMode
        }
    }

    private func makeTimelineOverrides(
        from items: [CalculationItem],
        organizationMode: BillingWindowMode
    ) -> [String: BillingWindowOverride] {
        let requests = items.compactMap { item -> BillingTimelineWindowRequest? in
            guard item.isBillable,
                  !item.isOpenSession,
                  !item.hasFixedFeeOverride,
                  item.effectiveBillingWindowMode(organizationMode: organizationMode) == .timeline,
                  item.effectiveWindowMinutes > 0,
                  let endedAt = item.input.session.endedAt,
                  endedAt > item.input.session.startedAt else {
                return nil
            }

            return BillingTimelineWindowRequest(
                sessionId: item.input.session.id,
                groupKey: .init(
                    customerId: item.input.customer.id,
                    windowMinutes: item.effectiveWindowMinutes
                ),
                startedAt: item.input.session.startedAt,
                endedAt: endedAt,
                actualSeconds: item.actualSeconds
            )
        }

        let planned = BillingTimelineWindowPlanner.plan(requests: requests)
        return planned.mapValues { minutes in
            BillingWindowOverride(billableMinutes: minutes, splitTo: nil)
        }
    }
}

private extension BillingCalculationInput {
    func withBillingWindowOverride(_ override: BillingWindowOverride?) -> BillingCalculationInput {
        BillingCalculationInput(
            session: session,
            todo: todo,
            customer: customer,
            project: project,
            category: category,
            rule: rule,
            holidays: holidays,
            priceContext: priceContext,
            vatCalculator: vatCalculator,
            billingWindowOverride: override
        )
    }
}
