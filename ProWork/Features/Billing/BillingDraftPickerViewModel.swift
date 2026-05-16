//
//  BillingDraftPickerViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//
//  BillingDraftPickerSheet için domain state + repository orkestrasyonu.
//  Sheet, BillingRunsView içinde nested halde yaşıyor; bu yüzden iki view'ın
//  ViewModel'leri kardeş olarak duruyor.
//

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

    init(
        services: AppServices = .shared,
        lifecycleService: BillingRunLifecycleService? = nil,
        tcmbSyncService: TCMBExchangeRateSyncService? = nil,
        globalSyncService: GlobalExchangeRateSyncService? = nil
    ) {
        self.lifecycleService = lifecycleService ?? BillingRunLifecycleService()
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
        self.tcmbSyncService = tcmbSyncService ?? TCMBExchangeRateSyncService()
        self.globalSyncService = globalSyncService ?? GlobalExchangeRateSyncService()
    }

    // MARK: - Loading

    /// Sheet ilk açıldığında çağrılır. Yerel müşteri listesi ve para birimleri
    /// repository'lerden çekilir; hata olursa caller'ın geçtiği fallback
    /// listeleri kullanılır (sheet sundan önce yüklenmiş `customers` /
    /// `customerCurrencies` argümanları).
    func loadCustomers(
        fallback customers: [Customer],
        fallbackCurrencies: [String: String]
    ) {
        do {
            let loadedCustomers = try customerRepository.fetchAll()
            let organizationCurrency = try organizationRepository.fetchDefault()?.masterCurrency ?? "TRY"
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

    /// Belirtilen müşteri / dönem için önizleme satırlarını çeker.
    /// Boş customerId verilirse mevcut preview temizlenir.
    func loadPreview(
        customerId: String,
        periodStart: Date,
        periodEnd: Date
    ) {
        guard !customerId.isEmpty else {
            preview = nil
            previewErrorMessage = nil
            return
        }

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
        preview = nil
        previewErrorMessage = nil
    }

    // MARK: - Rate import

    /// Önizleme için bugünkü kurları çeker. Tercih edilen kaynakta veri yoksa
    /// alternatif kaynak (TCMB ↔ Global) ile yeniden dener.
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
            return (fallbackSource, fallbackResult)
        } catch let primaryError {
            do {
                let fallbackResult = try await syncTodayRates(for: fallbackSource, currencies: currencies)
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
        ((try? organizationRepository.fetchDefault())?.masterCurrency ?? "TRY").uppercased()
    }
}

/// İki kaynak da başarısız olunca üretilen birleşik hata mesajı.
/// Daha önce BillingDraftPickerSheet'in private nested struct'ıydı; ViewModel
/// taşınınca buraya çıkarıldı.
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
