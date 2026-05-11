//
//  BillingComputationService.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Bir dönem için tüm session'ları BillingCalculator'a vererek BillingReportLine'lar
//  üretir. Repository'leri orkestre eder; raporlama ekranlarının tek giriş noktası.
//

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
        overrideRepository: TodoBillingOverrideRepository? = nil
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
    }

    /// Verilen tarih aralığındaki tüm bitmiş session'lar için satırları üretir.
    /// `runId` "preview" ise önizleme; gerçek BillingReportRun'da kullanılan id verilir.
    func computePeriod(
        from startDate: Date,
        to endDate: Date,
        runId: String = "preview"
    ) throws -> [BillingReportLine] {
        let organization = try organizationRepository.fetch(id: organizationId)
        let organizationBillingWindowMode = organization?.billingWindowMode ?? .timeline
        let organizationCurrency = organization?.masterCurrency ?? "TRY"

        // 1. Tüm referans verileri yükle
        let customers = try customerRepository.fetchAll()
        let categories = try categoryRepository.fetchAll()
        let billingRules = [
            try billingRuleRepository.fetchGlobal(organizationId: organizationId)
        ].compactMap { $0 }
        let holidays = try holidayRepository.fetchAll(organizationId: organizationId)
        let vatRates = try vatRateRepository.fetchAll(organizationId: organizationId)
        let priceLists = try priceListRepository.fetchAll(organizationId: organizationId)

        // Listelere ait satırları cache'le
        var rowsByListId: [String: [PriceListRow]] = [:]
        for list in priceLists {
            rowsByListId[list.id] = (try? priceListRowRepository.fetchAll(priceListId: list.id)) ?? []
        }

        let vatCalculator = VATCalculator(rates: vatRates)

        // 2. Dönem session'ları (UI list item üzerinden filtrele)
        let isPreviewRun = runId == "preview"
        let allListItems = try sessionRepository.fetchAllListItems()
        let periodItems = allListItems.filter { item in
            if let endedAt = item.endedAt {
                return endedAt >= startDate && item.startedAt <= endDate
            }

            return isPreviewRun && item.startedAt <= endDate
        }

        // Map için todoId → Todo, customerName → Customer
        let customersByName: [String: Customer] = Dictionary(
            uniqueKeysWithValues: customers.map { ($0.name, $0) }
        )

        var lines: [BillingReportLine] = []
        var orderIndex = 0
        var calculationItems: [CalculationItem] = []

        for item in periodItems {
            guard let todo = try? todoRepository.fetch(id: item.todoId) else { continue }

            // Müşteri/proje çöz
            let customer: Customer? = todo.customerId.flatMap { id in
                customers.first(where: { $0.id == id })
            } ?? item.customerName.flatMap { customersByName[$0] }

            guard let customer else { continue }

            let project = try? todo.projectId.map { id -> Project? in
                try projectRepository.fetch(id: id)
            }.flatMap { $0 }

            let category = categories.first(where: { $0.id == todo.categoryId })

            // Müşteriye özel mesai kuralı / tatil
            let rule = (try? billingRuleRepository.resolve(
                organizationId: organizationId,
                customerId: customer.id
            )) ?? billingRules.first

            guard let resolvedRule = rule else { continue }

            // Müşteri-spesifik holiday'ler de dahil
            let customerHolidays = holidays.filter {
                $0.scope == .global || ($0.scope == .customer && $0.customerId == customer.id)
            }

            // Fiyat resolver context
            let priceContext = makePriceContext(
                priceLists: priceLists,
                rowsByListId: rowsByListId,
                customer: customer,
                project: project,
                organizationCurrency: organizationCurrency,
                todoId: todo.id
            )

            // Session'ı yükle (gerçek model)
            let sessions = (try? sessionRepository.fetchSessions(todoId: todo.id)) ?? []
            guard let session = sessions.first(where: { $0.id == item.id }) else { continue }
            let isOpenSession = session.endedAt == nil
            let calculationSession: TodoTimeSession
            if isPreviewRun, isOpenSession {
                calculationSession = TodoTimeSession(
                    id: session.id,
                    todoId: session.todoId,
                    startedAt: session.startedAt,
                    runningSinceAt: session.runningSinceAt,
                    pausedAt: session.pausedAt,
                    endedAt: min(Date(), endDate),
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
            let output = BillingCalculator.calculate(
                input: item.input.withBillingWindowOverride(timelineOverrides[item.input.session.id]),
                runId: runId
            )
            for var line in output.lines {
                if isPreviewRun,
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

    /// Tek müşteri için filtreli sürüm.
    func computePeriod(
        customerId: String,
        from startDate: Date,
        to endDate: Date,
        runId: String = "preview"
    ) throws -> [BillingReportLine] {
        let all = try computePeriod(from: startDate, to: endDate, runId: runId)
        return all.filter { $0.customerId == customerId }
    }

    // MARK: - PriceContext

    private func makePriceContext(
        priceLists: [PriceList],
        rowsByListId: [String: [PriceListRow]],
        customer: Customer,
        project: Project?,
        organizationCurrency: String,
        todoId: String
    ) -> PriceResolutionContext {
        let projectLists = priceLists.filter {
            $0.ownerType == .project && $0.ownerId == project?.id
        }
        let customerLists = priceLists.filter {
            $0.ownerType == .customer && $0.ownerId == customer.id
        }
        let globalLists = priceLists.filter { $0.ownerType == .global }

        let override = try? overrideRepository.fetch(todoId: todoId)

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
