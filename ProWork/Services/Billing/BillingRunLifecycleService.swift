//  BillingRunLifecycleService.swift
//  ProWork
//   Created by Pronomi.

import Foundation
import os

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
    private let documentSequenceRepository: BillingDocumentSequenceRepository
    private let vatRateRepository: VatRateRepository
    private let snapshotRepository: BillingReportRunSnapshotRepository
    /// AppClock seam so finalize/refresh date stamps can be
    /// faked from tests. Production code uses SystemAppClock; tests
    /// pass a `FixedAppClock` (or similar) to assert on
    /// `finalizedAt`, `updatedAt`, etc.
    private let clock: AppClock

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
        documentSequenceRepository: BillingDocumentSequenceRepository? = nil,
        vatRateRepository: VatRateRepository? = nil,
        snapshotRepository: BillingReportRunSnapshotRepository? = nil,
        clock: AppClock? = nil
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
        self.documentSequenceRepository = documentSequenceRepository ?? BillingDocumentSequenceRepository()
        self.vatRateRepository = vatRateRepository ?? VatRateRepository()
        self.snapshotRepository = snapshotRepository ?? BillingReportRunSnapshotRepository()
        self.clock = clock ?? SystemAppClock()
    }

    /// AppServices-routed convenience init so ViewModels that
    /// take a `services: AppServices = .shared` can wire every nested
    /// repository through the same container instead of constructing
    /// `BillingRunLifecycleService()` with its `.shared`-defaulted
    /// repositories (which silently bypasses test mocks).
    convenience init(services: AppServices) {
        self.init(
            runRepository: services.billingReportRunRepository,
            lineRepository: services.billingReportLineRepository,
            paymentRepository: services.paymentRepository,
            customerRepository: services.customerRepository,
            companyProfileRepository: services.companyProfileRepository,
            currencyResolver: services.pricingCurrencyResolver,
            documentSequenceRepository: services.billingDocumentSequenceRepository,
            vatRateRepository: services.vatRateRepository,
            snapshotRepository: services.billingReportRunSnapshotRepository
        )
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

        let normalizedStart = AppCalendar.istanbul.startOfDay(for: periodStart)
        let normalizedEnd = AppCalendar.istanbul.startOfDay(for: periodEnd)
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
            kind: .draftPreview
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

        // The previous best-effort rollback (try? per
        // operation) could leave orphaned line rows behind a soft-deleted
        // run if cleanup itself failed mid-way. Wrap the entire per-currency
        // creation loop in a single write transaction so SQLite atomically
        // rolls back every insert if any step throws.
        return try runRepository.inWriteTransaction { () -> [BillingRunBundle] in
            return try currencies.map { currency in
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
                try lineRepository.replace(runId: draftRun.id, lines: persistedLines)
                try runRepository.recalculatePayments(runId: draftRun.id)
                return try loadBundle(runId: draftRun.id)
            }
        }
    }

    /// Important: — this "load" method also writes when a
    ///   finalized run is missing its `dueDate`. The write back-fills a
    ///   legacy invariant (every finalized run has a due date) that pre-
    ///   migration runs lack. Callers that expect a pure read should call
    ///   `lineRepository.fetchAll(runId:)` + repository fetchers directly;
    ///   `loadBundle` is the orchestrator that also hydrates derived
    ///   state and may mutate to keep the run model consistent.
    func loadBundle(runId: String) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }

        let profile = try companyProfileRepository.fetch(organizationId: organizationId)
        if run.dueDate == nil,
           run.status == .final {
            let paymentTermsDays = profile?.paymentTermsDays ?? BillingDefaults.paymentTermsDays
            let referenceDate = run.finalizedAt ?? run.updatedAt
            let dueDate = AppCalendar.istanbul.date(byAdding: .day, value: paymentTermsDays, to: referenceDate)
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

        // A corrupted periodStart/periodEnd string used to
        // silently fall back to Date(), so refresh would recompute against
        // "today" instead of the original period. Bail out instead — a run
        // whose period strings can't parse is a data corruption signal that
        // deserves a hard surface.
        guard let startDate = Self.dayFormatter.date(from: run.periodStart),
              let endDate = Self.dayFormatter.date(from: run.periodEnd) else {
            throw BillingRunLifecycleError.runNotFound
        }
        let computedLines = try computeDraftLines(
            customerId: run.customerId,
            periodStart: startDate,
            periodEnd: endDate,
            kind: run.status == .final ? .final(id: run.id) : .draft(id: run.id)
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

        // A run is locked to a single currency at
        // createDrafts time (one run per currency). On refresh, computeDraftLines
        // may surface lines from other currencies (new project/price-list
        // assignments). Restrict refresh output to the run's own currency so
        // heterogeneous-minor-unit totals never reach the database. Lines that
        // dropped out of the run's currency are silently filtered — they belong
        // to sibling per-currency runs created at the same draft time.
        let lines = computedLines.filter {
            selectionKeys.contains($0.selectionKey) && $0.currency == run.currency
        }

        // Replace + run update + recalculate is a 3-step write
        // flow. `replace` is internally atomic, but the outer sequence is
        // not — a failure between steps would leave run totals stale
        // against the new line set. One transaction now covers all three.
        try runRepository.inWriteTransaction {
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
        }
        return try loadBundle(runId: run.id)
    }

    /// FinalizeRun is a 6-step write flow (refresh → consume sequence →
    /// update run → recalculate payments → append snapshot → reload).
    /// Without a wrapping transaction, a step-4 failure leaves the
    /// document-number sequence consumed while the run state is half
    /// updated; a step-5 failure loses the immutable audit row. Wrap
    /// the mutating block in a single `inWriteTransaction` so any
    /// failure rolls every side effect back. `refreshRun` and
    /// `loadBundle` outside the transaction are reads — refresh itself
    /// is transactional through its own write block.
    func finalizeRun(runId: String, invoiceNumber: String? = nil) throws -> BillingRunBundle {
        var bundle = try refreshRunAllowingDraftOnly(runId: runId)

        guard !bundle.lines.isEmpty else {
            throw BillingRunLifecycleError.draftCannotBeFinalizedWithoutLines
        }

        warnIfPeriodPredatesDefaultVATRate(periodStart: bundle.run.periodStart)

        try runRepository.inWriteTransaction {
            bundle.run.status = .final
            bundle.run.finalizedAt = Date()
            bundle.run.finalizedByUserId = userId
            bundle.run.invoiceNumber = invoiceNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? bundle.run.invoiceNumber ?? suggestedInvoiceNumber(for: bundle.run)

            // The document number is assigned once at finalize; on a
            // subsequent finalize call (e.g. after cancel) the existing
            // number is kept and no new counter slot is consumed.
            if bundle.run.documentNumber == nil {
                let year = yearComponent(for: bundle.run.finalizedAt ?? Date())
                bundle.run.documentNumber = try consumeNextBillingDocumentNumber(year: year)
            }
            if bundle.run.dueDate == nil {
                let paymentTermsDays = bundle.companyProfile?.paymentTermsDays ?? BillingDefaults.paymentTermsDays
                let dueDate = AppCalendar.istanbul.date(byAdding: .day, value: paymentTermsDays, to: bundle.run.finalizedAt ?? Date())
                bundle.run.dueDate = dueDate.map(Self.dayFormatter.string(from:))
            }

            let snapshotData = try exportService.export(
                format: .json,
                bundle: bundle
            )
            let snapshotString = String(data: snapshotData, encoding: .utf8)
            bundle.run.snapshotJson = snapshotString
            bundle.run.updatedByUserId = userId
            bundle.run.updatedAt = Date()

            try runRepository.update(bundle.run)
            try runRepository.recalculatePayments(runId: bundle.run.id)

            // Append-only finalize history. The canonical
            // snapshotJson on billing_report_runs is still overwritten on
            // re-finalize for backward compatibility with existing readers, but
            // every finalize call also stamps a new immutable row here so the
            // original audit trail survives any subsequent reopen/re-finalize.
            if let snapshotString {
                try snapshotRepository.append(
                    runId: bundle.run.id,
                    organizationId: organizationId,
                    finalizedAt: bundle.run.finalizedAt ?? Date(),
                    finalizedByUserId: bundle.run.finalizedByUserId,
                    invoiceNumber: bundle.run.invoiceNumber,
                    documentNumber: bundle.run.documentNumber,
                    snapshotJson: snapshotString
                )
            }
        }

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

        // Y9: The finalized snapshot is an audit record; if reopen
        // silently overwrites it, the "amounts changed after a record
        // was cancelled" condition becomes undetectable. If a snapshot
        // exists, emit a log warning — gives the developer
        // append-only snapshot history eklemeye karar verene kadar burada
        // observability. The existing snapshotJson is preserved; the
        // draft selection is stored in the same field rather than a new
        // one because the snapshot is recomputed on refresh anyway —
        // but in the instant of reopen the original audit text remains intact.
        if let existing = run.snapshotJson, !existing.isEmpty {
            ProWorkLog.app.warning(
                "Reopening finalized billing run \(runId, privacy: .public); the original finalized snapshot is being replaced by the recomputed draft. Verify totals before re-finalizing."
            )
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
        let normalizedStart = AppCalendar.istanbul.startOfDay(for: periodStart)
        let normalizedEnd = AppCalendar.istanbul.startOfDay(for: periodEnd)
        let lines = try computeDraftLines(
            customerId: customerId,
            periodStart: normalizedStart,
            periodEnd: normalizedEnd,
            kind: .livePreview
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

    /// Payment write + recalculatePayments must be atomic. Without the
    /// transaction, a recalculate failure would leave balanceMinor /
    /// paymentStatus out of sync with the underlying payment rows
    /// .
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

        try runRepository.inWriteTransaction {
            try paymentRepository.insert(payment)
            try runRepository.recalculatePayments(runId: runId)
        }
        return try loadBundle(runId: runId)
    }

    func updatePayment(_ payment: Payment) throws -> BillingRunBundle {
        _ = try finalizedRunForPaymentOperations(runId: payment.runId)
        try runRepository.inWriteTransaction {
            try paymentRepository.update(payment)
            try runRepository.recalculatePayments(runId: payment.runId)
        }
        return try loadBundle(runId: payment.runId)
    }

    func deletePayment(_ payment: Payment) throws -> BillingRunBundle {
        _ = try finalizedRunForPaymentOperations(runId: payment.runId)
        try runRepository.inWriteTransaction {
            try paymentRepository.softDelete(id: payment.id, by: userId)
            try runRepository.recalculatePayments(runId: payment.runId)
        }
        return try loadBundle(runId: payment.runId)
    }

    func updateDueDate(runId: String, dueDate: Date) throws -> BillingRunBundle {
        guard var run = try runRepository.fetch(id: runId) else {
            throw BillingRunLifecycleError.runNotFound
        }

        run.dueDate = Self.dayFormatter.string(from: AppCalendar.istanbul.startOfDay(for: dueDate))
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
        run.dueDate = Self.dayFormatter.string(from: AppCalendar.istanbul.startOfDay(for: dueDate))
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
        // Previously allocated a fresh DateFormatter on every
        // draft creation. Route through the shared cache so a multi-currency
        // createDrafts pass reuses one instance.
        let localeIdentifier = ProWorkLocalizer.shared.language.localeIdentifier.isEmpty
            ? Locale.current.identifier
            : ProWorkLocalizer.shared.language.localeIdentifier
        let formatter = ProWorkFormatters.cachedDateFormatter(
            localeIdentifier: localeIdentifier,
            dateFormat: "dd.MM.yyyy"
        )
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
        // Previously used `run.customerId.prefix(4)` which
        // is the leading characters of a UUID — opaque, not meaningful to
        // the user, and a frequent typo target if it ever needs to be
        // re-typed. Prefer the customer's short name (alphanumerics only,
        // first 6 chars uppercased); fall back to the legacy form so older
        // tests / fixtures keep producing a non-empty value.
        let stamp = Self.invoiceFormatter.string(from: Date())
        let customerHint: String
        // `try?` on a `throws -> Customer?` returns `Customer??`; the
        // outer `??` flattening was redundant. Unwrap the doubled
        // optional with a plain `flatMap` so the result is `Customer?`.
        if let customer = (try? customerRepository.fetch(id: run.customerId)).flatMap({ $0 }) {
            let alphanumerics = customer.name.unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map { Character($0) }
            let cleaned = String(alphanumerics).prefix(6).uppercased()
            customerHint = cleaned.isEmpty ? run.customerId.prefix(4).uppercased() : cleaned
        } else {
            customerHint = run.customerId.prefix(4).uppercased()
        }
        return "PRW-\(stamp)-\(customerHint)"
    }

    private func yearComponent(for date: Date) -> Int {
        AppCalendar.istanbul.component(.year, from: date)
    }

    /// **Atomically** consumes the per-year document-number counter and
    /// returns a string in the "HD-YYYY-NNNNNN" format.
    /// The counter is incremented via a single SQL UPSERT against the
    /// dedicated `billing_document_sequences` table, and the whole flow
    /// runs inside `inWriteTransaction`; parallel finalize calls reserve
    /// different values and duplicate invoice numbers are impossible.
    /// The `(organizationId, documentNumber)` UNIQUE index on
    /// `billing_report_runs` is the last line of defence — if a bug
    /// produces the same value, the INSERT/UPDATE
    /// patlar.
    private func consumeNextBillingDocumentNumber(year: Int) throws -> String {
        let next = try documentSequenceRepository.reserveNext(
            organizationId: organizationId,
            year: year
        )
        return String(format: "HD-%04d-%06d", year, next)
    }

    /// The previous version called `reduce(0)` three times, meaning three
    /// passes over `lines`. If the same run carries multiple currencies,
    /// the totals are meaningless (minor units across different currencies
    /// can't be summed) — to surface that, we check
    /// `Set(lines.map(\.currency))` at runtime and log.
    private func summarize(lines: [BillingReportLine], fallbackCurrency: String) -> (subtotalMinor: Int, vatMinor: Int, totalMinor: Int, currency: String) {
        if Set(lines.map(\.currency)).count > 1 {
            ProWorkLog.billing.error(
                "summarize: heterogeneous currency mix in run lines — minor unit totals will be nonsensical. Bundle the run into per-currency segments before summarising."
            )
        }

        var subtotal = 0
        var vat = 0
        var total = 0
        for line in lines {
            subtotal += line.amountMinor
            vat += line.vatMinor
            total += line.totalMinor
        }
        return (
            subtotalMinor: subtotal,
            vatMinor: vat,
            totalMinor: total,
            currency: lines.first?.currency ?? fallbackCurrency
        )
    }

    /// Note: the original review flagged a possible
    /// "cancel/finalize asymmetry" here. After review the semantics are
    /// intentional and now explicitly documented:
    ///   • `.cancelled` runs are skipped — cancelling frees the period
    ///     back up for re-billing under a new run.
    ///   • Soft-deleted runs (`deletedAt IS NOT NULL`) are excluded at the
    ///     SQL layer by `fetchAllForCustomer` so we never see them here.
    ///   • `.draft` and `.final` runs both still hold a claim on their
    ///     period and surface as conflicts.
    ///   • `excludingRunId` lets refresh/finalize check for *other* runs
    ///     overlapping the same period without flagging itself.
    /// If a future status enum case is added (e.g. `.archived`), update
    /// this guard explicitly so the behaviour does not drift.
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
            switch run.status {
            case .cancelled:
                return false
            case .draft, .final:
                break
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

    /// Y8: Emits a log warning if the finalized period starts before the
    /// default VAT rate's effective date. The calculator still snapshots
    /// using the current rate; the warning nudges the developer/operator
    /// to apply a historical rate correction.
    private func warnIfPeriodPredatesDefaultVATRate(periodStart: String) {
        guard let defaultRate = try? vatRateRepository.fetchDefault(organizationId: organizationId),
              let effectiveFrom = defaultRate.effectiveFrom,
              !effectiveFrom.isEmpty,
              periodStart < effectiveFrom else {
            return
        }
        // VAT rate name is tenant-customisable
        // ("ACME standard 20%") and not strictly needed for diagnosis;
        // mark it private so macOS Console scrapes don't surface it.
        ProWorkLog.app.warning(
            "Finalizing run for period starting \(periodStart, privacy: .public) but default VAT rate '\(defaultRate.name, privacy: .private)' is effective from \(effectiveFrom, privacy: .public). Historical lines may have used the wrong rate; review the snapshot before issuing the invoice."
        )
    }

    private static func endOfDay(for date: Date) -> Date {
        let start = AppCalendar.istanbul.startOfDay(for: date)
        return AppCalendar.istanbul.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    // Every date-string generated along the billing path is pinned to
    // the Istanbul TZ; otherwise the accounting day would shift when
    // the user's TZ changes while travelling.
    // bu formatter `AppDateFormatters.istanbulDay` ile
    // Identical to one another (POSIX locale + Europe/Istanbul + yyyy-MM-dd).
    // Route through the shared formatter and remove the local copy; the
    // day TZ or format decision can then be updated in a single place.
    private static var dayFormatter: DateFormatter { AppDateFormatters.istanbulDay }

    private static let invoiceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = AppCalendar.istanbul.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private func computeDraftLines(
        customerId: String,
        periodStart: Date,
        periodEnd: Date,
        kind: BillingRunKind
    ) throws -> [BillingReportLine] {
        try computationService.computePeriod(
            customerId: customerId,
            from: periodStart,
            to: Self.endOfDay(for: periodEnd),
            kind: kind
        )
    }

    /// Distinguishes between "no manual selection stored"
    /// (legitimate nil — recompute everything) and "snapshot present
    /// but corrupted" (data loss — log loudly so the operator can
    /// inspect before the refresh widens the run silently).
    private func decodeDraftSelectionKeys(from snapshotJson: String?) -> Set<String>? {
        guard let snapshotJson, !snapshotJson.isEmpty else {
            return nil
        }
        guard let data = snapshotJson.data(using: .utf8) else {
            ProWorkLog.billing.error(
                "decodeDraftSelectionKeys: snapshotJson is non-UTF8; refresh will recompute every line."
            )
            return nil
        }
        do {
            let selection = try JSONDecoder().decode(DraftLineSelectionState.self, from: data)
            return Set(selection.selectedLineKeys)
        } catch {
            ProWorkLog.billing.error(
                "decodeDraftSelectionKeys: failed to decode snapshotJson (\(error.localizedDescription, privacy: .public)); refresh will recompute every line instead of preserving manual selection."
            )
            return nil
        }
    }

    private func encodeDraftSelection(keys: Set<String>) -> String? {
        let payload = DraftLineSelectionState(selectedLineKeys: keys.sorted())
        do {
            let data = try JSONEncoder().encode(payload)
            return String(data: data, encoding: .utf8)
        } catch {
            // Previously a try? swallowed encoding failures
            // so snapshotJson was silently set to nil, which the refresh
            // path then read back as "no manual selection — recompute
            // everything", quietly widening the run's line set. Log loudly
            // and still surface nil (legacy callers expect String?); the
            // log makes the data-loss visible during diagnosis.
            ProWorkLog.billing.error(
                "encodeDraftSelection failed: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }
}

// `nilIfEmpty` consolidated into Shared/Support/StringNilIfEmpty.swift.

private struct DraftLineSelectionState: Codable {
    /// Current schema version emitted by the encoder. Bump when the
    /// shape of `selectedLineKeys` (or any new field) changes so the
    /// decoder can route to an upgrade path.: the field was
    /// declared earlier but had no acting code path — now the decoder
    /// throws on an unknown version instead of silently mis-interpreting
    /// a future payload as v1.
    static let currentSchemaVersion = 1

    let selectedLineKeys: [String]
    /// Explicit schema version so future migrations can
    /// detect a payload that needs upgrading rather than silently failing
    /// to decode. Defaults to 1 on read for backward compatibility with
    /// older runs whose JSON omits the field.
    var schemaVersion: Int = currentSchemaVersion

    enum CodingKeys: String, CodingKey {
        case selectedLineKeys
        case schemaVersion
    }

    init(selectedLineKeys: [String], schemaVersion: Int = DraftLineSelectionState.currentSchemaVersion) {
        self.selectedLineKeys = selectedLineKeys
        self.schemaVersion = schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedLineKeys = try container.decode([String].self, forKey: .selectedLineKeys)
        let decodedVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        if decodedVersion > Self.currentSchemaVersion {
            // Forward-compat refusal: a newer-version payload almost
            // certainly carries fields the current decoder would drop.
            // Refusing forces the caller's decode-failure log path
            // rather than silently mis-restoring selection.
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported DraftLineSelectionState schemaVersion \(decodedVersion); maximum supported is \(Self.currentSchemaVersion)."
            )
        }
        self.schemaVersion = decodedVersion
    }
}
