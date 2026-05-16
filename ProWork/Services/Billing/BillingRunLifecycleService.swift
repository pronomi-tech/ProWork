//
//  BillingRunLifecycleService.swift
//  ProWork
//
//   Created by Pronomi.
//

import Foundation

struct BillingRunBundle: Hashable {
    var run: BillingReportRun
    var customer: Customer?
    var companyProfile: CompanyProfile?
    var lines: [BillingReportLine]
    var payments: [Payment]
}

struct BillingDraftPreviewLine: Identifiable, Hashable {
    let line: BillingReportLine
    let blockingRunLabel: String?

    var id: String { line.selectionKey }
    var selectionKey: String { line.selectionKey }
    var isSelectable: Bool { blockingRunLabel == nil }
}

struct BillingDraftPreview: Hashable {
    var lines: [BillingDraftPreviewLine]

    var availableLines: [BillingDraftPreviewLine] {
        lines.filter(\.isSelectable)
    }

    var blockedLineCount: Int {
        lines.count - availableLines.count
    }
}

enum BillingRunLifecycleError: LocalizedError {
    case runNotFound
    case customerNotFound
    case noBillableLinesForPeriod
    case conflictingRunExists(String)
    case draftCannotBeFinalizedWithoutLines
    case finalizedRunCannotRefresh
    case onlyFinalizedRunsCanBeCancelled
    case onlyDraftRunsCanBeDeleted
    case onlyFinalizedRunsCanManagePayments

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    var errorDescription: String? {
        switch self {
        case .runNotFound:
            return localized("billingRuns.error.runNotFound", defaultValue: "Hizmet dökümü kaydı bulunamadı.")
        case .customerNotFound:
            return localized("billingRuns.error.customerNotFound", defaultValue: "Müşteri kaydı bulunamadı.")
        case .noBillableLinesForPeriod:
            return localized("billingRuns.error.noBillableLines", defaultValue: "Seçilen dönem için hesap satırı bulunamadı. Boş kayıt oluşturulmadı.")
        case .conflictingRunExists(let title):
            return String(format: localized("billingRuns.error.conflict", defaultValue: "“%@” kaydı aynı dönemle çakışıyor. Aynı hesap satırları birden fazla hizmet dökümünde kullanılamaz."), title)
        case .draftCannotBeFinalizedWithoutLines:
            return localized("billingRuns.error.finalizeWithoutLines", defaultValue: "Satırı olmayan bir hizmet dökümü kesinleştirilemez.")
        case .finalizedRunCannotRefresh:
            return localized("billingRuns.error.finalizedCannotRefresh", defaultValue: "Kesinleşmiş kayıt canlı hesapla yenilenemez.")
        case .onlyFinalizedRunsCanBeCancelled:
            return localized("billingRuns.error.onlyFinalizedCanCancel", defaultValue: "Yalnızca kesinleşmiş kayıtlar iptal edilebilir.")
        case .onlyDraftRunsCanBeDeleted:
            return localized("billingRuns.error.onlyDraftCanDelete", defaultValue: "Yalnızca kesinleşmemiş taslak kayıtlar silinebilir.")
        case .onlyFinalizedRunsCanManagePayments:
            return localized("billingRuns.error.onlyFinalizedCanManagePayments", defaultValue: "Ödeme işlemleri yalnızca kesinleşmiş hizmet dökümlerinde kullanılabilir.")
        }
    }
}

@MainActor
final class BillingRunLifecycleService {
    private let organizationId: String
    private let userId: String
    private let runRepository: BillingReportRunRepository
    private let lineRepository: BillingReportLineRepository
    private let paymentRepository: PaymentRepository
    private let customerRepository: CustomerRepository
    private let companyProfileRepository: CompanyProfileRepository
    private let computationService: BillingComputationService
    private let exportService: BillingRunExportService
    private let currencyResolver: PricingCurrencyResolver
    private let settingsRepository: AppSettingsRepository

    init(
        organizationId: String? = nil,
        userId: String? = nil,
        runRepository: BillingReportRunRepository? = nil,
        lineRepository: BillingReportLineRepository? = nil,
        paymentRepository: PaymentRepository? = nil,
        customerRepository: CustomerRepository? = nil,
        companyProfileRepository: CompanyProfileRepository? = nil,
        computationService: BillingComputationService? = nil,
        exportService: BillingRunExportService? = nil,
        currencyResolver: PricingCurrencyResolver? = nil,
        settingsRepository: AppSettingsRepository? = nil
    ) {
        self.organizationId = organizationId ?? BuiltInOrganizationId.default
        self.userId = userId ?? BuiltInUserId.defaultOwner
        self.runRepository = runRepository ?? BillingReportRunRepository()
        self.lineRepository = lineRepository ?? BillingReportLineRepository()
        self.paymentRepository = paymentRepository ?? PaymentRepository()
        self.customerRepository = customerRepository ?? CustomerRepository()
        self.companyProfileRepository = companyProfileRepository ?? CompanyProfileRepository()
        self.computationService = computationService ?? BillingComputationService()
        self.exportService = exportService ?? BillingRunExportService()
        self.currencyResolver = currencyResolver ?? PricingCurrencyResolver()
        self.settingsRepository = settingsRepository ?? AppSettingsRepository()
    }

    func fetchAllRuns() throws -> [BillingReportRun] {
        try runRepository.fetchAll(organizationId: organizationId)
    }

    func createDraft(
        customerId: String,
        periodStart: Date,
        periodEnd: Date,
        title: String? = nil,
        selectedLineKeys: [String]? = nil
    ) throws -> BillingRunBundle {
        guard let firstBundle = try createDrafts(
            customerId: customerId,
            periodStart: periodStart,
            periodEnd: periodEnd,
            title: title,
            selectedLineKeys: selectedLineKeys
        ).first else {
            throw BillingRunLifecycleError.noBillableLinesForPeriod
        }

        return firstBundle
    }

    func createDrafts(
        customerId: String,
        periodStart: Date,
        periodEnd: Date,
        title: String? = nil,
        selectedLineKeys: [String]? = nil
    ) throws -> [BillingRunBundle] {
        guard let customer = try customerRepository.fetch(id: customerId) else {
            throw BillingRunLifecycleError.customerNotFound
        }

        let normalizedStart = Calendar.current.startOfDay(for: periodStart)
        let normalizedEnd = Calendar.current.startOfDay(for: periodEnd)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let baseTitle = trimmedTitle ?? defaultTitle(
            for: customer,
            periodStart: periodStart,
            periodEnd: periodEnd
        )

        let computedLines = try computeDraftLines(
            customerId: customerId,
            periodStart: normalizedStart,
            periodEnd: normalizedEnd,
            runId: "draft-preview"
        )
        let selectionKeys = Set(selectedLineKeys ?? computedLines.map(\.selectionKey))
        let assignments = try lineRepository.fetchSelectionAssignments(
            organizationId: organizationId,
            customerId: customerId
        )

        if let conflicting = assignments.first(where: { selectionKeys.contains($0.selectionKey) }) {
            throw BillingRunLifecycleError.conflictingRunExists(conflicting.runLabel)
        }

        let lines = computedLines.filter { selectionKeys.contains($0.selectionKey) }

        guard !lines.isEmpty else {
            throw BillingRunLifecycleError.noBillableLinesForPeriod
        }

        let currencies = Array(Set(lines.map(\.currency))).sorted()
        var createdRunIds: [String] = []

        do {
            let bundles = try currencies.map { currency in
                let now = Date()
                let runLines = lines
                    .filter { $0.currency == currency }
                    .map { line -> BillingReportLine in
                        var line = line
                        line.runId = ""
                        return line
                    }

                let totals = summarize(lines: runLines, fallbackCurrency: currency)
                var draftRun = BillingReportRun(
                    customerId: customerId,
                    periodStart: Self.dayFormatter.string(from: normalizedStart),
                    periodEnd: Self.dayFormatter.string(from: normalizedEnd),
                    status: .draft,
                    title: draftTitle(
                        baseTitle: baseTitle,
                        currency: currency,
                        totalCurrencyCount: currencies.count
                    ),
                    invoiceNumber: nil,
                    currency: totals.currency,
                    balanceMinor: 0,
                    organizationId: organizationId,
                    createdByUserId: userId,
                    updatedByUserId: userId,
                    createdAt: now,
                    updatedAt: now
                )

                draftRun.subtotalMinor = totals.subtotalMinor
                draftRun.vatMinor = totals.vatMinor
                draftRun.totalMinor = totals.totalMinor
                draftRun.balanceMinor = totals.totalMinor
                draftRun.snapshotJson = encodeDraftSelection(
                    keys: Set(runLines.map(\.selectionKey))
                )

                let persistedLines = runLines.map { line -> BillingReportLine in
                    var line = line
                    line.runId = draftRun.id
                    return line
                }

                try runRepository.insert(draftRun)
                createdRunIds.append(draftRun.id)
                try lineRepository.replace(runId: draftRun.id, lines: persistedLines)
                try runRepository.recalculatePayments(runId: draftRun.id)
                return try loadBundle(runId: draftRun.id)
            }

            return bundles
        } catch {
            for runId in createdRunIds {
                try? lineRepository.deleteAll(runId: runId)
                try? runRepository.softDelete(id: runId, by: userId)
            }
            throw error
        }
    }

    func loadBundle(runId: String) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }

        let profile = try companyProfileRepository.fetch(organizationId: organizationId)
        if run.dueDate == nil,
           run.status == .final {
            let paymentTermsDays = profile?.paymentTermsDays ?? 30
            let referenceDate = run.finalizedAt ?? run.updatedAt
            let dueDate = Calendar.current.date(byAdding: .day, value: paymentTermsDays, to: referenceDate)
            run.dueDate = dueDate.map(Self.dayFormatter.string(from:))
            try runRepository.update(run)
        }

        let lines = try lineRepository.fetchAll(runId: runId)
        let payments = try paymentRepository.fetchAll(runId: runId)
        let customer = try customerRepository.fetch(id: run.customerId)

        return BillingRunBundle(
            run: run,
            customer: customer,
            companyProfile: profile,
            lines: lines,
            payments: payments
        )
    }

    func refreshRun(runId: String) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }
        guard run.status != .final else {
            throw BillingRunLifecycleError.finalizedRunCannotRefresh
        }

        let draftSelectionKeys = decodeDraftSelectionKeys(from: run.snapshotJson)

        if draftSelectionKeys == nil,
           let startDate = Self.dayFormatter.date(from: run.periodStart),
           let endDate = Self.dayFormatter.date(from: run.periodEnd),
           let conflicting = try findConflictingRun(
                customerId: run.customerId,
                periodStart: startDate,
                periodEnd: endDate,
                excludingRunId: run.id
           ) {
            throw BillingRunLifecycleError.conflictingRunExists(conflicting.title ?? conflicting.invoiceNumber ?? conflicting.id)
        }

        let startDate = Self.dayFormatter.date(from: run.periodStart) ?? Date()
        let endDate = Self.dayFormatter.date(from: run.periodEnd) ?? Date()
        let computedLines = try computeDraftLines(
            customerId: run.customerId,
            periodStart: startDate,
            periodEnd: endDate,
            runId: run.id
        )
        let selectionKeys = draftSelectionKeys ?? Set(computedLines.map(\.selectionKey))

        if draftSelectionKeys != nil {
            let assignments = try lineRepository.fetchSelectionAssignments(
                organizationId: organizationId,
                customerId: run.customerId,
                excludingRunId: run.id
            )

            if let conflicting = assignments.first(where: { selectionKeys.contains($0.selectionKey) }) {
                throw BillingRunLifecycleError.conflictingRunExists(conflicting.runLabel)
            }
        }

        let lines = computedLines.filter { selectionKeys.contains($0.selectionKey) }

        try lineRepository.replace(runId: run.id, lines: lines)

        let totals = summarize(lines: lines, fallbackCurrency: run.currency)
        run.currency = totals.currency
        run.subtotalMinor = totals.subtotalMinor
        run.vatMinor = totals.vatMinor
        run.totalMinor = totals.totalMinor
        run.balanceMinor = max(0, run.totalMinor - run.paidMinor)
        run.updatedByUserId = userId
        run.updatedAt = Date()
        run.snapshotJson = draftSelectionKeys == nil ? nil : encodeDraftSelection(keys: selectionKeys)

        try runRepository.update(run)
        try runRepository.recalculatePayments(runId: run.id)
        return try loadBundle(runId: run.id)
    }

    func finalizeRun(runId: String, invoiceNumber: String? = nil) throws -> BillingRunBundle {
        var bundle = try refreshRunAllowingDraftOnly(runId: runId)

        guard !bundle.lines.isEmpty else {
            throw BillingRunLifecycleError.draftCannotBeFinalizedWithoutLines
        }

        bundle.run.status = .final
        bundle.run.finalizedAt = Date()
        bundle.run.finalizedByUserId = userId
        bundle.run.invoiceNumber = invoiceNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? bundle.run.invoiceNumber ?? suggestedInvoiceNumber(for: bundle.run)

        // Belge numarası finalize anında bir kez atanır; yeniden finalize çağrılırsa
        // (cancel sonrası gibi) mevcut numara korunur, yeni sayaç tüketilmez.
        if bundle.run.documentNumber == nil {
            let year = yearComponent(for: bundle.run.finalizedAt ?? Date())
            bundle.run.documentNumber = try consumeNextBillingDocumentNumber(year: year)
        }
        if bundle.run.dueDate == nil {
            let paymentTermsDays = bundle.companyProfile?.paymentTermsDays ?? 30
            let dueDate = Calendar.current.date(byAdding: .day, value: paymentTermsDays, to: bundle.run.finalizedAt ?? Date())
            bundle.run.dueDate = dueDate.map(Self.dayFormatter.string(from:))
        }

        let snapshotData = try exportService.export(
            format: .json,
            bundle: bundle
        )
        bundle.run.snapshotJson = String(data: snapshotData, encoding: .utf8)
        bundle.run.updatedByUserId = userId
        bundle.run.updatedAt = Date()

        try runRepository.update(bundle.run)
        try runRepository.recalculatePayments(runId: bundle.run.id)

        return try loadBundle(runId: bundle.run.id)
    }

    func cancelRun(runId: String) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }
        guard run.status == .final else {
            throw BillingRunLifecycleError.onlyFinalizedRunsCanBeCancelled
        }

        run.status = .cancelled
        run.updatedByUserId = userId
        run.updatedAt = Date()
        try runRepository.update(run)
        return try loadBundle(runId: run.id)
    }

    func deleteRun(runId: String) throws {
        guard let run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }
        guard run.status == .draft else {
            throw BillingRunLifecycleError.onlyDraftRunsCanBeDeleted
        }

        try runRepository.softDelete(id: runId, by: userId)
    }

    func reopenRun(runId: String) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }

        let currentLines = try lineRepository.fetchAll(runId: runId)
        run.status = .draft
        run.snapshotJson = encodeDraftSelection(keys: Set(currentLines.map(\.selectionKey)))
        run.finalizedAt = nil
        run.finalizedByUserId = nil
        run.updatedByUserId = userId
        run.updatedAt = Date()
        try runRepository.update(run)
        return try refreshRun(runId: run.id)
    }

    func previewDraft(
        customerId: String,
        periodStart: Date,
        periodEnd: Date,
        excludingRunId: String? = nil
    ) throws -> BillingDraftPreview {
        let normalizedStart = Calendar.current.startOfDay(for: periodStart)
        let normalizedEnd = Calendar.current.startOfDay(for: periodEnd)
        let lines = try computeDraftLines(
            customerId: customerId,
            periodStart: normalizedStart,
            periodEnd: normalizedEnd,
            runId: "preview"
        )
        let assignments = try lineRepository.fetchSelectionAssignments(
            organizationId: organizationId,
            customerId: customerId,
            excludingRunId: excludingRunId
        )
        let assignmentByKey = Dictionary(
            assignments.map { ($0.selectionKey, $0.runLabel) },
            uniquingKeysWith: { current, _ in current }
        )
        let previewLines = lines.map { line in
            BillingDraftPreviewLine(
                line: line,
                blockingRunLabel: assignmentByKey[line.selectionKey] ?? (line.endedAt == nil ? ProWorkLocalizer.shared.string("billingRuns.blocking.openSession", defaultValue: "Açık oturum") : nil)
            )
        }
        return BillingDraftPreview(
            lines: previewLines
        )
    }

    func addPayment(
        runId: String,
        paidAt: Date,
        amountMinor: Int,
        currency: String,
        method: PaymentMethod,
        reference: String?,
        note: String?
    ) throws -> BillingRunBundle {
        _ = try finalizedRunForPaymentOperations(runId: runId)

        let payment = Payment(
            runId: runId,
            paidAt: paidAt,
            amountMinor: amountMinor,
            currency: currency,
            method: method,
            reference: reference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            organizationId: organizationId,
            createdByUserId: userId,
            updatedByUserId: userId
        )

        try paymentRepository.insert(payment)
        try runRepository.recalculatePayments(runId: runId)
        return try loadBundle(runId: runId)
    }

    func updatePayment(_ payment: Payment) throws -> BillingRunBundle {
        _ = try finalizedRunForPaymentOperations(runId: payment.runId)
        try paymentRepository.update(payment)
        try runRepository.recalculatePayments(runId: payment.runId)
        return try loadBundle(runId: payment.runId)
    }

    func deletePayment(_ payment: Payment) throws -> BillingRunBundle {
        _ = try finalizedRunForPaymentOperations(runId: payment.runId)
        try paymentRepository.softDelete(id: payment.id, by: userId)
        try runRepository.recalculatePayments(runId: payment.runId)
        return try loadBundle(runId: payment.runId)
    }

    func updateDueDate(runId: String, dueDate: Date) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }

        run.dueDate = Self.dayFormatter.string(from: Calendar.current.startOfDay(for: dueDate))
        run.updatedByUserId = userId
        run.updatedAt = Date()
        try runRepository.update(run)
        return try loadBundle(runId: runId)
    }

    func updateDocumentInfo(
        runId: String,
        invoiceNumber: String?,
        dueDate: Date
    ) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }

        run.invoiceNumber = invoiceNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        run.dueDate = Self.dayFormatter.string(from: Calendar.current.startOfDay(for: dueDate))
        run.updatedByUserId = userId
        run.updatedAt = Date()
        try runRepository.update(run)
        return try loadBundle(runId: runId)
    }

    private func refreshRunAllowingDraftOnly(runId: String) throws -> BillingRunBundle {
        guard let run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }

        if run.status == .final {
            return try loadBundle(runId: runId)
        }

        return try refreshRun(runId: runId)
    }

    private func finalizedRunForPaymentOperations(runId: String) throws -> BillingReportRun {
        guard let run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }
        guard run.status == .final else {
            throw BillingRunLifecycleError.onlyFinalizedRunsCanManagePayments
        }
        return run
    }

    private func defaultTitle(for customer: Customer, periodStart: Date, periodEnd: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = ProWorkLocalizer.shared.language.localeIdentifier.isEmpty
            ? Locale.current
            : Locale(identifier: ProWorkLocalizer.shared.language.localeIdentifier)
        formatter.dateFormat = "dd.MM.yyyy"
        return "\(customer.name) · \(formatter.string(from: periodStart)) – \(formatter.string(from: periodEnd))"
    }

    private func draftTitle(
        baseTitle: String,
        currency: String,
        totalCurrencyCount: Int
    ) -> String {
        guard totalCurrencyCount > 1 else {
            return baseTitle
        }

        return "\(baseTitle) · \(currency)"
    }

    private func suggestedInvoiceNumber(for run: BillingReportRun) -> String {
        let stamp = Self.invoiceFormatter.string(from: Date())
        return "PRW-\(stamp)-\(run.customerId.prefix(4).uppercased())"
    }

    private func yearComponent(for date: Date) -> Int {
        AppCalendar.istanbul.component(.year, from: date)
    }

    /// Yıl bazlı belge numarası sayacını tüketir ve "HD-YYYY-NNNNNN" formatında
    /// dizgi döner. Atomic değil: ayrı bir process aynı anda finalize ederse
    /// sayaçlar yarışabilir. Şimdilik kabul edilebilir; tek kullanıcılı masaüstü
    /// uygulamasında pratik bir risk yok.
    private func consumeNextBillingDocumentNumber(year: Int) throws -> String {
        let key = String(year)
        var current = try settingsRepository.fetch().billingDocumentSequenceByYear
        let next = (current[key] ?? 0) + 1
        current[key] = next

        let encoder = JSONEncoder()
        let data = try encoder.encode(current)
        let json = String(decoding: data, as: UTF8.self)
        try settingsRepository.update(key: "billingDocumentSequenceByYear", value: json)

        return String(format: "HD-%04d-%06d", year, next)
    }

    private func summarize(lines: [BillingReportLine], fallbackCurrency: String) -> (subtotalMinor: Int, vatMinor: Int, totalMinor: Int, currency: String) {
        (
            subtotalMinor: lines.reduce(0) { $0 + $1.amountMinor },
            vatMinor: lines.reduce(0) { $0 + $1.vatMinor },
            totalMinor: lines.reduce(0) { $0 + $1.totalMinor },
            currency: lines.first?.currency ?? fallbackCurrency
        )
    }

    private func findConflictingRun(
        customerId: String,
        periodStart: Date,
        periodEnd: Date,
        excludingRunId: String? = nil
    ) throws -> BillingReportRun? {
        let existingRuns = try runRepository.fetchAllForCustomer(
            organizationId: organizationId,
            customerId: customerId
        )

        return existingRuns.first { run in
            if run.status == .cancelled {
                return false
            }
            if let excludingRunId, run.id == excludingRunId {
                return false
            }
            guard
                let existingStart = Self.dayFormatter.date(from: run.periodStart),
                let existingEnd = Self.dayFormatter.date(from: run.periodEnd)
            else {
                return false
            }

            return Self.rangesOverlap(
                lhsStart: existingStart,
                lhsEnd: existingEnd,
                rhsStart: periodStart,
                rhsEnd: periodEnd
            )
        }
    }

    private static func rangesOverlap(
        lhsStart: Date,
        lhsEnd: Date,
        rhsStart: Date,
        rhsEnd: Date
    ) -> Bool {
        lhsStart <= rhsEnd && rhsStart <= lhsEnd
    }

    private static func endOfDay(for date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let invoiceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private func computeDraftLines(
        customerId: String,
        periodStart: Date,
        periodEnd: Date,
        runId: String
    ) throws -> [BillingReportLine] {
        try computationService.computePeriod(
            customerId: customerId,
            from: periodStart,
            to: Self.endOfDay(for: periodEnd),
            runId: runId
        )
    }

    private func decodeDraftSelectionKeys(from snapshotJson: String?) -> Set<String>? {
        guard let snapshotJson,
              let data = snapshotJson.data(using: .utf8),
              let selection = try? JSONDecoder().decode(DraftLineSelectionState.self, from: data) else {
            return nil
        }

        return Set(selection.selectedLineKeys)
    }

    private func encodeDraftSelection(keys: Set<String>) -> String? {
        let payload = DraftLineSelectionState(selectedLineKeys: keys.sorted())
        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct DraftLineSelectionState: Codable {
    let selectedLineKeys: [String]
}
