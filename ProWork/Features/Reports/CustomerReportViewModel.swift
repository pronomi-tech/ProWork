//  CustomerReportViewModel.swift
//  ProWork
//  Created by Pronomi.

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

    /// A custom-date-range picker drag was producing ~5–10 `compute(...)`
    /// calls per second; this task waits 300 ms so consecutive calls
    /// collapse into a single `computePeriod` run.
    private var pendingComputeTask: Task<Void, Never>?
    private let debounceInterval: UInt64 = 300_000_000

    init(
        services: AppServices = .shared,
        computation: BillingComputationService? = nil,
        currencyResolver: PricingCurrencyResolver? = nil
    ) {
        self.customerRepository = services.customerRepository
        self.computation = computation ?? BillingComputationService()
        self.currencyResolver = currencyResolver ?? services.pricingCurrencyResolver
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
            pendingComputeTask?.cancel()
            pendingComputeTask = nil
            report = nil
            return
        }

        pendingComputeTask?.cancel()
        pendingComputeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceInterval ?? 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.performCompute(
                selectedCustomerId: selectedCustomerId,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
        }
    }

    private func performCompute(
        selectedCustomerId: String,
        periodStart: Date,
        periodEnd: Date
    ) {
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
