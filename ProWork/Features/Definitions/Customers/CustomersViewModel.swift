//  CustomersViewModel.swift
//  ProWork
//  Created by Pronomi.
//  Domain state and repository orchestration for CustomersView (second
//  adopter of the TodosViewModel pattern). The view side only holds UI state (sheet,
//  confirmation, errorMessage) tutar.

import Combine
import Foundation
import SwiftUI

@MainActor
final class CustomersViewModel: ObservableObject, CRUDListViewModel {
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var customerCurrencies: [String: String] = [:]
    @Published private(set) var vatLabelsById: [String: String] = [:]
    @Published var errorMessage: String?

    private let customerRepository: CustomerRepository
    private let priceListRepository: PriceListRepository
    private let organizationRepository: OrganizationRepository
    private let vatRateRepository: VatRateRepository

    private let services: AppServices

    init(services: AppServices = .shared) {
        self.services = services
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
        self.vatRateRepository = services.vatRateRepository
    }

    func load() {
        do {
            customers = try customerRepository.fetchAll()
            // Master currency cached in AppServices.
            let organizationCurrency = services.cachedMasterCurrency()
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
            vatLabelsById = VatRateLabel.nonDefaultSelectionLabels(rates: vatRates)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns `true` if `create` succeeded; the View uses this to decide whether to dismiss the dialog.
    @discardableResult
    func create(_ customer: Customer) -> Bool {
        performMutation { try customerRepository.insert(customer) }
    }

    @discardableResult
    func update(_ customer: Customer) -> Bool {
        performMutation { try customerRepository.update(customer) }
    }

    func delete(id: String) {
        performMutation { try customerRepository.softDelete(id: id, by: AppServices.currentUserId) }
    }
}
