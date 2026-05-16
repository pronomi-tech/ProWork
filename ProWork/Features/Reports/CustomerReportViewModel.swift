//
//  CustomerReportViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class CustomerReportViewModel: ObservableObject {
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var report: CustomerReport?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let customerRepository: CustomerRepository
    private let computation: BillingComputationService
    private let currencyResolver: PricingCurrencyResolver

    init(
        services: AppServices = .shared,
        computation: BillingComputationService? = nil,
        currencyResolver: PricingCurrencyResolver? = nil
    ) {
        self.customerRepository = services.customerRepository
        self.computation = computation ?? BillingComputationService()
        self.currencyResolver = currencyResolver ?? PricingCurrencyResolver()
    }

    func loadCustomers() {
        do {
            customers = try customerRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func compute(
        selectedCustomerId: String,
        periodStart: Date,
        periodEnd: Date
    ) {
        guard !selectedCustomerId.isEmpty else {
            report = nil
            return
        }
        guard let customer = customers.first(where: { $0.id == selectedCustomerId }) else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let lines = try computation.computePeriod(
                customerId: selectedCustomerId,
                from: periodStart,
                to: periodEnd
            )
            let currency = try currencyResolver.resolveCustomerCurrency(
                customerId: customer.id,
                organizationId: customer.organizationId
            )
            report = BillingReportBuilder.buildCustomerReport(
                customerId: customer.id,
                customerName: customer.name,
                lines: lines,
                currency: currency
            )
        } catch {
            errorMessage = error.localizedDescription
            report = nil
        }
    }
}
