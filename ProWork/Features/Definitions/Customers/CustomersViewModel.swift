//
//  CustomersViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//
//  CustomersView için domain state ve repository orkestrasyonu (TodosViewModel
//  pattern'inin ikinci uygulayıcısı). View tarafı yalnızca UI state (sheet,
//  confirmation, errorMessage) tutar.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class CustomersViewModel: ObservableObject {
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var customerCurrencies: [String: String] = [:]
    @Published private(set) var vatLabelsById: [String: String] = [:]
    @Published var errorMessage: String?

    private let customerRepository: CustomerRepository
    private let priceListRepository: PriceListRepository
    private let organizationRepository: OrganizationRepository
    private let vatRateRepository: VatRateRepository

    init(services: AppServices = .shared) {
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
        self.vatRateRepository = services.vatRateRepository
    }

    func load(settingsStore: AppSettingsStore) {
        do {
            customers = try customerRepository.fetchAll()
            let organizationCurrency = try organizationRepository.fetchDefault()?.masterCurrency ?? "TRY"
            let priceLists = try priceListRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            let vatRates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            customerCurrencies = Dictionary(
                uniqueKeysWithValues: customers.map { customer in
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
            vatLabelsById = VatRateLabel.nonDefaultSelectionLabels(
                rates: vatRates,
                settingsStore: settingsStore
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `create` başarılıysa `true` döner; View dialog'u kapatma kararını buna göre verir.
    @discardableResult
    func create(_ customer: Customer, settingsStore: AppSettingsStore) -> Bool {
        do {
            try customerRepository.insert(customer)
            load(settingsStore: settingsStore)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ customer: Customer, settingsStore: AppSettingsStore) -> Bool {
        do {
            try customerRepository.update(customer)
            load(settingsStore: settingsStore)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(id: String, settingsStore: AppSettingsStore) {
        do {
            try customerRepository.delete(id: id)
            load(settingsStore: settingsStore)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
