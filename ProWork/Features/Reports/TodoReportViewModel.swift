//  TodoReportViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation

@MainActor
final class TodoReportViewModel: ObservableObject {
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var rows: [TodoReportRow] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let customerRepository: CustomerRepository
    private let computation: BillingComputationService

    /// Debounce so computePeriod isn't fired on every drag/keystroke.
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
        customerFilter: String
    ) {
        pendingComputeTask?.cancel()
        pendingComputeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceInterval ?? 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.performCompute(
                period: period,
                customStart: customStart,
                customEnd: customEnd,
                customerFilter: customerFilter
            )
        }
    }

    private func performCompute(
        period: DateRangeFilter,
        customStart: Date,
        customEnd: Date,
        customerFilter: String
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

            let grouped = Dictionary(grouping: filteredLines) { $0.todoId }

            rows = grouped.map { todoId, lines -> TodoReportRow in
                let first = lines[0]
                let manualSeconds = lines.filter { $0.isManual }.reduce(0) { $0 + $1.actualSeconds }
                let manualLines = lines.filter { $0.isManual }.count
                return TodoReportRow(
                    id: todoId,
                    todoId: todoId,
                    todoTitle: first.todoTitle,
                    customerId: first.customerId,
                    customerName: first.customerName,
                    projectId: first.projectId,
                    projectName: first.projectName,
                    categoryName: first.categoryName,
                    actualSeconds: lines.reduce(0) { $0 + $1.actualSeconds },
                    billableMinutes: lines.reduce(0) { $0 + $1.billableMinutes },
                    manualSeconds: manualSeconds,
                    manualLineCount: manualLines,
                    subtotalMinor: lines.reduce(0) { $0 + $1.amountMinor },
                    vatMinor: lines.reduce(0) { $0 + $1.vatMinor },
                    totalMinor: lines.reduce(0) { $0 + $1.totalMinor },
                    currency: first.currency
                )
            }
            .sorted { $0.todoTitle.localizedCompare($1.todoTitle) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
            rows = []
        }
    }
}
