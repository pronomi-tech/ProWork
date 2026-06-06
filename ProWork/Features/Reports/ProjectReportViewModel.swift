//  ProjectReportViewModel.swift
//  ProWork
//  Created by Pronomi.
//  ProjectReportView domain state + computation orchestration.
//  Injecting BillingComputationService through AppServices is still not
//  implemented, so we instantiate it directly; the service itself already
//  pulls AppServices.shared repositories with defaults.

import Combine
import Foundation

@MainActor
final class ProjectReportViewModel: ObservableObject {
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var rows: [ProjectReportRow] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let customerRepository: CustomerRepository
    private let computation: BillingComputationService

    /// Debounced so we don't run a separate `computePeriod` for every event
    /// during filter/period dragging.
    private var pendingComputeTask: Task<Void, Never>?
    private let debounceInterval: UInt64 = 300_000_000

    init(
        services: AppServices = .shared,
        computation: BillingComputationService? = nil
    ) {
        self.customerRepository = services.customerRepository
        self.computation = computation ?? BillingComputationService()
    }

    func loadCustomers() {
        do {
            customers = try customerRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func compute(
        period: DateRangeFilter,
        customStart: Date,
        customEnd: Date,
        customerFilter: String,
        noProjectLabel: String
    ) {
        pendingComputeTask?.cancel()
        pendingComputeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceInterval ?? 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.performCompute(
                period: period,
                customStart: customStart,
                customEnd: customEnd,
                customerFilter: customerFilter,
                noProjectLabel: noProjectLabel
            )
        }
    }

    private func performCompute(
        period: DateRangeFilter,
        customStart: Date,
        customEnd: Date,
        customerFilter: String,
        noProjectLabel: String
    ) {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let lines = try computation.computePeriod(
                from: period.startDate(custom: customStart),
                to: period.endDate(custom: customEnd)
            )
            let filteredLines = customerFilter.isEmpty
                ? lines
                : lines.filter { $0.customerId == customerFilter }

            let grouped = Dictionary(grouping: filteredLines) {
                "\($0.customerId)|\($0.projectId ?? "_none")"
            }

            rows = grouped.map { _, lines -> ProjectReportRow in
                let first = lines[0]
                return ProjectReportRow(
                    id: "\(first.customerId)|\(first.projectId ?? "_none")",
                    customerId: first.customerId,
                    customerName: first.customerName,
                    projectId: first.projectId,
                    projectName: first.projectName ?? noProjectLabel,
                    actualSeconds: lines.reduce(0) { $0 + $1.actualSeconds },
                    billableMinutes: lines.reduce(0) { $0 + $1.billableMinutes },
                    subtotalMinor: lines.reduce(0) { $0 + $1.amountMinor },
                    vatMinor: lines.reduce(0) { $0 + $1.vatMinor },
                    totalMinor: lines.reduce(0) { $0 + $1.totalMinor },
                    currency: first.currency
                )
            }
            .sorted {
                if $0.customerName != $1.customerName {
                    return $0.customerName.localizedCompare($1.customerName) == .orderedAscending
                }
                return $0.projectName.localizedCompare($1.projectName) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
            rows = []
        }
    }
}
