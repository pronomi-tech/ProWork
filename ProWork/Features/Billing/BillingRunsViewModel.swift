//
//  BillingRunsViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//
//  BillingRunsView için domain state + load/refresh orkestrasyonu.
//  Asıl yaşam döngüsü mantığı (finalize/cancel/payment CRUD) BillingRunLifecycleService'te
//  zaten yapılandırılmış durumda; bu ViewModel onu sarmalamak yerine View tarafında
//  doğrudan çağırabilsin diye exposes ediyor. Buradaki amaç repository erişimlerini
//  View'dan çıkarmak ve runs/customers/selectedBundle state'ini tek noktada toplamak.
//

import Combine
import Foundation

@MainActor
final class BillingRunsViewModel: ObservableObject {
    @Published private(set) var runs: [BillingReportRun] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var customerCurrencies: [String: String] = [:]
    @Published var selectedBundle: BillingRunBundle?
    @Published var errorMessage: String?
    @Published var savedNotice: String?

    let lifecycleService: BillingRunLifecycleService
    let exportService: BillingRunExportService

    private let customerRepository: CustomerRepository
    private let priceListRepository: PriceListRepository
    private let organizationRepository: OrganizationRepository

    init(
        services: AppServices = .shared,
        lifecycleService: BillingRunLifecycleService? = nil,
        exportService: BillingRunExportService? = nil
    ) {
        self.lifecycleService = lifecycleService ?? BillingRunLifecycleService()
        self.exportService = exportService ?? BillingRunExportService()
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
    }

    /// Tüm referans listelerini (müşteriler, varsayılan para birimi) ve runs'ı çeker.
    /// `selectedRunId` hâlâ runs içinde varsa bundle yeniden yüklenir, yoksa selectedBundle nil olur.
    func load(reselect selectedRunId: String?) {
        do {
            customers = try customerRepository.fetchAll()
            let organizationCurrency = try organizationRepository.fetchDefault()?.masterCurrency ?? "TRY"
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

            if let selectedRunId,
               runs.contains(where: { $0.id == selectedRunId }) {
                selectedBundle = try lifecycleService.loadBundle(runId: selectedRunId)
            } else {
                selectedBundle = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectRun(id: String?) {
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

    /// Organization para birimi (UI etiketlerinde gerekiyor).
    func masterCurrency(for organizationId: String? = nil) -> String {
        if let organizationId {
            return ((try? organizationRepository.fetch(id: organizationId))?.masterCurrency ?? "TRY").uppercased()
        }
        return ((try? organizationRepository.fetchDefault())?.masterCurrency ?? "TRY").uppercased()
    }
}
