//  BillingRunsViewModel.swift
//  ProWork
//  Created by Pronomi.
//  Full domain orchestration for BillingRunsView (load/refresh + lifecycle +
//  export). Previously most lifecycle/export calls lived in the view body;
//  they were written into the ViewModel through nonmutating proxy properties,
//  and the "saved notice" was debounced with `DispatchQueue.main.asyncAfter`.
//  This file is now the single authority: the view only holds presentation
//  state (sheets, confirmation dialogs) and calls VM methods.

import Combine
import Foundation

@MainActor
final class BillingRunsViewModel: ObservableObject {
    @Published private(set) var runs: [BillingReportRun] = []
    @Published private(set) var customers: [Customer] = []
    /// Id→Customer cache so each sidebar row doesn't scan O(n) via
    /// `customers.first(where: { $0.id == ... })`. The visible lag caused
    /// by a linear scan on ~200 customers × ~N run sidebar renders is
    /// removed by this cache.
    /// O(1)'e iner.
    @Published private(set) var customerLookup: [String: Customer] = [:]
    @Published private(set) var customerCurrencies: [String: String] = [:]
    @Published private(set) var selectedBundle: BillingRunBundle?
    /// `private(set)`. The previous public `var` allowed a
    /// SwiftUI binding to mutate `selectedRunId` directly, which
    /// skipped `loadBundle(...)` and left `selectedBundle` stale.
    /// External callers must go through `selectRun(id:)` so the
    /// run and its bundle stay in sync; a SwiftUI binding can adopt
    /// `Binding(get:set:)` over this property to invoke `selectRun`.
    @Published private(set) var selectedRunId: String?
    @Published var errorMessage: String?
    @Published var savedNotice: String?

    let lifecycleService: BillingRunLifecycleService
    let exportService: BillingRunExportService

    private let customerRepository: CustomerRepository
    private let priceListRepository: PriceListRepository
    private let organizationRepository: OrganizationRepository
    /// Routed through the shared `NoticeScheduler`
    /// so identical-message races and ExchangeRatesViewModel
    /// inconsistencies are handled by one implementation.
    private let savedNoticeScheduler = NoticeScheduler()

    private let services: AppServices

    /// LifecycleService default now flows through `services`
    /// (matches BillingDraftPickerViewModel) so tests injecting a
    /// custom AppServices actually exercise their mocks.
    init(
        services: AppServices = .shared,
        lifecycleService: BillingRunLifecycleService? = nil,
        exportService: BillingRunExportService? = nil
    ) {
        self.services = services
        self.lifecycleService = lifecycleService ?? BillingRunLifecycleService(services: services)
        self.exportService = exportService ?? BillingRunExportService()
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
    }

    // MARK: - Load / select

    /// Fetches every reference list (customers, default currency) plus runs.
    /// If `selectedRunId` still exists in runs the bundle is reloaded; otherwise
    /// selectedBundle/selectedRunId temizlenir.
    ///
    /// Every mutation today routes back through `load()`, which
    /// re-fetches customers + price lists + currencies + runs + bundle.
    /// The mutation only touched the bundle in 90% of cases — a
    /// granular `reloadAfterMutation` that touches only `runs` +
    /// selected bundle would skip the reference-data rebuild. Deferred
    /// because the current full reload is correct (no stale rows leak
    /// through) and the perf hit is bounded by the customer count;
    /// flagging here so the next perf pass has a clear surface to
    /// optimise.
    func load() {
        let previouslySelected = selectedRunId
        do {
            customers = try customerRepository.fetchAll()
            customerLookup = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0) })
            // The master currency comes from the AppServices cache so
            // each bundle/metric doesn't run a separate `fetchDefault()`.
            let organizationCurrency = services.cachedMasterCurrency()
            let priceLists = try priceListRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            customerCurrencies = Dictionary(uniqueKeysWithValues: customers.map { customer in
                (
                    customer.id,
                    PricingCurrencyResolver.resolveCustomerCurrency(
                        customer: customer,
                        priceLists: priceLists,
                        organizationCurrency: organizationCurrency
                    )
                )
            })
            runs = try lifecycleService.fetchAllRuns()
            errorMessage = nil

            if let previouslySelected,
               runs.contains(where: { $0.id == previouslySelected }) {
                selectedRunId = previouslySelected
                selectedBundle = try lifecycleService.loadBundle(runId: previouslySelected)
            } else if let first = runs.first {
                selectedRunId = first.id
                selectedBundle = try lifecycleService.loadBundle(runId: first.id)
            } else {
                selectedRunId = nil
                selectedBundle = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectRun(id: String?) {
        selectedRunId = id
        guard let id else {
            selectedBundle = nil
            return
        }
        do {
            selectedBundle = try lifecycleService.loadBundle(runId: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Organization para birimi (UI etiketlerinde gerekiyor). Cache'li
    /// Goes through the AppServices channel.
    func masterCurrency(for organizationId: String? = nil) -> String {
        services.cachedMasterCurrency(organizationId: organizationId ?? BuiltInOrganizationId.default)
    }

    // MARK: - Lifecycle

    /// If `selectedLineKeys` is empty, every eligible line is included.
    /// Returns one or more bundles (may split by currency); the first
    /// bundle becomes the active selection.
    @discardableResult
    func createDraft(
        customerId: String,
        startDate: Date,
        endDate: Date,
        title: String?,
        selectedLineKeys: [String],
        savedNoticeFor: @escaping ([BillingRunBundle]) -> String
    ) throws -> [BillingRunBundle] {
        let bundles = try lifecycleService.createDrafts(
            customerId: customerId,
            periodStart: startDate,
            periodEnd: endDate,
            title: title,
            selectedLineKeys: selectedLineKeys
        )

        guard let firstBundle = bundles.first else {
            throw BillingRunLifecycleError.noBillableLinesForPeriod
        }

        selectedRunId = firstBundle.run.id
        selectedBundle = firstBundle
        scheduleSavedNotice(savedNoticeFor(bundles))
        load()
        return bundles
    }

    func refreshSelectedRun(noticeMessage: String) {
        guard let id = selectedRunId else { return }
        do {
            selectedBundle = try lifecycleService.refreshRun(runId: id)
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finalizeSelectedRun(noticeMessage: String) {
        guard let id = selectedRunId else { return }
        do {
            selectedBundle = try lifecycleService.finalizeRun(runId: id)
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelRun(bundle: BillingRunBundle, noticeMessage: String) {
        do {
            selectedBundle = try lifecycleService.cancelRun(runId: bundle.run.id)
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRun(bundle: BillingRunBundle, noticeMessage: String) {
        do {
            try lifecycleService.deleteRun(runId: bundle.run.id)
            if selectedRunId == bundle.run.id {
                selectedRunId = nil
                selectedBundle = nil
            }
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Payments

    func addPayment(
        runId: String,
        paidAt: Date,
        amountMinor: Int,
        currency: String,
        method: PaymentMethod,
        reference: String?,
        note: String?,
        noticeMessage: String
    ) {
        do {
            selectedBundle = try lifecycleService.addPayment(
                runId: runId,
                paidAt: paidAt,
                amountMinor: amountMinor,
                currency: currency,
                method: method,
                reference: reference,
                note: note
            )
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePayment(
        _ payment: Payment,
        paidAt: Date,
        amountMinor: Int,
        currency: String,
        method: PaymentMethod,
        reference: String?,
        note: String?,
        noticeMessage: String
    ) {
        do {
            var updated = payment
            updated.paidAt = paidAt
            updated.amountMinor = amountMinor
            updated.currency = currency
            updated.method = method
            updated.reference = reference
            updated.note = note
            updated.updatedAt = Date()
            selectedBundle = try lifecycleService.updatePayment(updated)
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePayment(_ payment: Payment, noticeMessage: String) {
        do {
            selectedBundle = try lifecycleService.deletePayment(payment)
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveDocumentInfo(runId: String, referenceNumber: String, dueDate: Date, noticeMessage: String) {
        do {
            selectedBundle = try lifecycleService.updateDocumentInfo(
                runId: runId,
                invoiceNumber: referenceNumber,
                dueDate: dueDate
            )
            scheduleSavedNotice(noticeMessage)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export

    /// PDF data generation is async; wraps the export service.
    func makePDFData(
        bundle: BillingRunBundle,
        templateSettings: ServiceDocumentTemplateSettings
    ) async throws -> Data {
        try await exportService.exportPDF(
            bundle: bundle,
            settings: templateSettings
        )
    }

    /// Non-PDF formats are synchronous; use `makePDFData` for PDF.
    func exportNonPDF(format: BillingExportFormat, bundle: BillingRunBundle) throws -> Data {
        try exportService.export(format: format, bundle: bundle)
    }

    func suggestedFilename(format: BillingExportFormat, bundle: BillingRunBundle) -> String {
        exportService.suggestedFilename(format: format, bundle: bundle)
    }

    func reportExportSucceeded(noticeMessage: String) {
        scheduleSavedNotice(noticeMessage)
    }

    func reportError(_ message: String) {
        errorMessage = message
    }

    // MARK: - Saved notice debounce

    private func scheduleSavedNotice(_ message: String) {
        savedNoticeScheduler.show(message) { [weak self] value in
            self?.savedNotice = value
        }
    }
}
