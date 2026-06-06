//  BillingDraftPickerViewModel.swift
//  ProWork
//  Created by Pronomi.
//  Domain state + repository orchestration for BillingDraftPickerSheet.
//  The sheet is nested inside BillingRunsView, so the two views' ViewModels
//  live as siblings.

import Combine
import Foundation

@MainActor
final class BillingDraftPickerViewModel: ObservableObject {
    @Published private(set) var availableCustomers: [Customer] = []
    @Published private(set) var availableCustomerCurrencies: [String: String] = [:]
    @Published private(set) var preview: BillingDraftPreview?
    @Published var previewErrorMessage: String?
    @Published var previewNoticeMessage: String?
    @Published private(set) var isLoadingPreview = false
    @Published private(set) var isImportingTodayRates = false

    let lifecycleService: BillingRunLifecycleService

    private let customerRepository: CustomerRepository
    private let priceListRepository: PriceListRepository
    private let organizationRepository: OrganizationRepository
    private let tcmbSyncService: TCMBExchangeRateSyncService
    private let globalSyncService: GlobalExchangeRateSyncService

    /// LoadPreview is debounced so customer / period drag changes don't
    /// fire a separate `previewDraft` for every tick.
    private var pendingPreviewTask: Task<Void, Never>?
    private let previewDebounceInterval: UInt64 = 300_000_000

    private let services: AppServices

    /// Nested `BillingRunLifecycleService` now wires through
    /// the injected `services` container by default, so test mocks
    /// propagate. Callers that already construct a custom
    /// `BillingRunLifecycleService` can still pass it via the
    /// optional argument and override the convenience routing.
    init(
        services: AppServices = .shared,
        lifecycleService: BillingRunLifecycleService? = nil,
        tcmbSyncService: TCMBExchangeRateSyncService? = nil,
        globalSyncService: GlobalExchangeRateSyncService? = nil
    ) {
        self.services = services
        self.lifecycleService = lifecycleService ?? BillingRunLifecycleService(services: services)
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
        self.tcmbSyncService = tcmbSyncService ?? TCMBExchangeRateSyncService()
        self.globalSyncService = globalSyncService ?? GlobalExchangeRateSyncService()
    }

    // MARK: - Loading

    /// Called when the sheet first opens. The local customer list and
    /// currencies are fetched from the repositories; on error the
    /// fallback lists passed by the caller are used (`customers` /
    /// `customerCurrencies` arguments preloaded before the sheet).
    func loadCustomers(
        fallback customers: [Customer],
        fallbackCurrencies: [String: String]
    ) {
        do {
            let loadedCustomers = try customerRepository.fetchAll()
            // Master currency cached in AppServices.
            let organizationCurrency = services.cachedMasterCurrency()
            let priceLists = try priceListRepository.fetchAll(organizationId: BuiltInOrganizationId.default)

            availableCustomers = loadedCustomers
            availableCustomerCurrencies = Dictionary(
                uniqueKeysWithValues: loadedCustomers.map { customer in
                    (
                        customer.id,
                        PricingCurrencyResolver.resolveCustomerCurrency(
                            customer: customer,
                            priceLists: priceLists,
                            organizationCurrency: organizationCurrency
                        )
                    )
                }
            )
        } catch {
            availableCustomers = customers
            availableCustomerCurrencies = fallbackCurrencies
            previewErrorMessage = error.localizedDescription
        }
    }

    /// Fetches preview lines for the given customer / period.
    /// If an empty customerId is passed, the current preview is cleared.
    func loadPreview(
        customerId: String,
        periodStart: Date,
        periodEnd: Date
    ) {
        guard !customerId.isEmpty else {
            pendingPreviewTask?.cancel()
            pendingPreviewTask = nil
            preview = nil
            previewErrorMessage = nil
            return
        }

        pendingPreviewTask?.cancel()
        pendingPreviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.previewDebounceInterval ?? 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.performLoadPreview(
                customerId: customerId,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
        }
    }

    private func performLoadPreview(
        customerId: String,
        periodStart: Date,
        periodEnd: Date
    ) {
        isLoadingPreview = true
        defer { isLoadingPreview = false }

        do {
            let loaded = try lifecycleService.previewDraft(
                customerId: customerId,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
            preview = loaded
            previewErrorMessage = nil
            previewNoticeMessage = nil
        } catch {
            preview = nil
            previewErrorMessage = error.localizedDescription
        }
    }

    func clearPreview() {
        pendingPreviewTask?.cancel()
        pendingPreviewTask = nil
        preview = nil
        previewErrorMessage = nil
    }

    // MARK: - Rate import

    /// Fetches today's rates for the preview. If the preferred source has no data,
    /// alternatif kaynak (TCMB ↔ Global) ile yeniden dener.
    ///
    /// When the preferred source returns empty / fails and the
    /// fallback succeeds, surface a notice so the user knows the
    /// fetched rates came from the secondary provider — previously the
    /// fallback ran silently, which surfaced as "Frankfurter rates
    /// pretending to be TCMB" in support tickets.
    func importTodayRates(
        currencies: [String],
        preferredSource: ExchangeRateAutoSource
    ) async -> (source: ExchangeRateAutoSource, result: TCMBExchangeRateSyncResult)? {
        previewErrorMessage = nil
        previewNoticeMessage = nil
        isImportingTodayRates = true
        defer { isImportingTodayRates = false }

        let fallbackSource: ExchangeRateAutoSource = preferredSource == .tcmb ? .global : .tcmb

        do {
            let result = try await syncTodayRates(for: preferredSource, currencies: currencies)
            if result.importedDayCount > 0 {
                return (preferredSource, result)
            }
            let fallbackResult = try await syncTodayRates(for: fallbackSource, currencies: currencies)
            previewNoticeMessage = String(
                format: ProWorkLocalizer.shared.string(
                    "billingDraftPicker.notice.fallbackUsed",
                    defaultValue: "%@ tarafından bugün için veri yok; kurlar %@ kaynağından alındı."
                ),
                preferredSource.title,
                fallbackSource.title
            )
            return (fallbackSource, fallbackResult)
        } catch let primaryError {
            do {
                let fallbackResult = try await syncTodayRates(for: fallbackSource, currencies: currencies)
                previewNoticeMessage = String(
                    format: ProWorkLocalizer.shared.string(
                        "billingDraftPicker.notice.fallbackUsedAfterError",
                        defaultValue: "%@ kaynağı hata verdi; kurlar %@ kaynağından alındı."
                    ),
                    preferredSource.title,
                    fallbackSource.title
                )
                return (fallbackSource, fallbackResult)
            } catch let fallbackError {
                previewErrorMessage = CompositeRateImportError(
                    primarySource: preferredSource,
                    primaryMessage: primaryError.localizedDescription,
                    fallbackSource: fallbackSource,
                    fallbackMessage: fallbackError.localizedDescription
                ).localizedDescription
                return nil
            }
        }
    }

    private func syncTodayRates(
        for source: ExchangeRateAutoSource,
        currencies: [String]
    ) async throws -> TCMBExchangeRateSyncResult {
        switch source {
        case .tcmb:
            return try await tcmbSyncService.sync(day: Date(), currencies: currencies)
        case .global:
            return try await globalSyncService.sync(day: Date(), currencies: currencies)
        }
    }

    // MARK: - Master currency helper

    func masterCurrency() -> String {
        services.cachedMasterCurrency()
    }
}

/// Combined error message produced when both sources fail.
/// Was a private nested struct of BillingDraftPickerSheet; promoted to
/// top-level here when the ViewModel was moved out.
struct CompositeRateImportError: LocalizedError {
    let primarySource: ExchangeRateAutoSource
    let primaryMessage: String
    let fallbackSource: ExchangeRateAutoSource
    let fallbackMessage: String

    var errorDescription: String? {
        String(
            format: ProWorkLocalizer.shared.string(
                "billing.error.rateImportFailed",
                defaultValue: "%@ başarısız: %@\n%@ başarısız: %@"
            ),
            primarySource.title,
            primaryMessage,
            fallbackSource.title,
            fallbackMessage
        )
    }
}
