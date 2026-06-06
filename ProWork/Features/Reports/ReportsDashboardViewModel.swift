//  ReportsDashboardViewModel.swift
//  ProWork
//  Created by Pronomi.
//  Spec §7 — ReportsDashboardView's heavy filter+breakdown computations
//  used to live in the view `body`; every render re-ran O(n) work and
//  even search-picker keystrokes were rebuilding every breakdown table.
//  This ViewModel:
//    - Holds raw repository state (sessions/todos/customers/projects).
//    - Takes filter input parameters and caches derived fields as
//      @Published; the view body only reads.
//    - Localised strings come in as parameters via `LabelBundle`, so the
//      VM doesn't need to know the language preference.

import Combine
import Foundation

@MainActor
final class ReportsDashboardViewModel: ObservableObject {

    /// Localised label set passed in from the view. Forwarded through on
    /// every `recompute(...)` call.
    struct LabelBundle {
        var noCustomerTitle: String
        var noProjectFormat: String  // %@ (No project)
        var administrativeTitle: String
        var unknownCategoryTitle: String
        var otherTitle: String
        var billableTitle: String
    }

    // MARK: - Raw state

    @Published private(set) var sessions: [WorkSessionListItem] = []
    @Published private(set) var todos: [TodoListItem] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [ProjectListItem] = []
    @Published var errorMessage: String?

    // MARK: - Derived state

    @Published private(set) var filteredSessions: [WorkSessionListItem] = []
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var manualSeconds: Int = 0
    @Published private(set) var automaticSeconds: Int = 0
    @Published private(set) var uniqueCustomerCount: Int = 0
    @Published private(set) var uniqueProjectCount: Int = 0
    @Published private(set) var categoryBreakdownRows: [DonutBreakdownRow] = []
    @Published private(set) var customerBreakdownRows: [DonutBreakdownRow] = []
    @Published private(set) var customerBreakdownData: [(name: String, seconds: Int)] = []
    @Published private(set) var billableBreakdownData: [(name: String, seconds: Int)] = []
    @Published private(set) var projectBreakdownData: [(name: String, seconds: Int)] = []
    @Published private(set) var todoBreakdownData: [(name: String, seconds: Int)] = []

    private let sessionRepository: TodoTimeSessionRepository
    private let todoRepository: TodoRepository
    private let customerRepository: CustomerRepository
    private let projectRepository: ProjectRepository

    /// `todoLookup` is rebuilt only when `todos` changes
    /// (load/refresh), not on every `recompute(...)` call. Date-picker
    /// drag used to trigger hundreds of identical Dictionary builds.
    private var todoLookup: [String: TodoListItem] = [:]

    init(services: AppServices = .shared) {
        self.sessionRepository = services.todoTimeSessionRepository
        self.todoRepository = services.todoRepository
        self.customerRepository = services.customerRepository
        self.projectRepository = services.projectRepository
    }

    func loadData() {
        do {
            sessions = try sessionRepository.fetchAllListItems()
            todos = try todoRepository.fetchAll()
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            todoLookup = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Apply the filter parameters and recompute the derived fields.
    /// The view triggers this method in its `.onAppear` and `.onChange` hooks.
    func recompute(
        range: DateRangeFilter,
        customStart: Date,
        customEnd: Date,
        customerId: String,
        projectId: String,
        labels: LabelBundle
    ) {
        // ID-based filter via the todoLookup. The previous
        // name-based predicate (`session.customerName == name`) would
        // mix two customers that happened to share a name and
        // skipped sessions where the snapshot name diverged
        // from the live record. Routing through `todoLookup[session.todoId]`
        // uses the stable foreign-key path.
        let filterByCustomer = !customerId.isEmpty
        let filterByProject = !projectId.isEmpty

        let filtered = sessions.filter { session in
            let matchesRange = range.contains(
                session.startedAt,
                customStart: customStart,
                customEnd: customEnd
            )
            guard matchesRange else { return false }
            if !(filterByCustomer || filterByProject) {
                return true
            }
            // Need todo lookup to resolve IDs; skip orphan sessions.
            guard let todo = todoLookup[session.todoId] else {
                return false
            }
            if filterByCustomer, todo.customerId != customerId {
                return false
            }
            if filterByProject, todo.projectId != projectId {
                return false
            }
            return true
        }
        .filter { $0.endedAt != nil }

        filteredSessions = filtered

        let total = filtered.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        totalSeconds = total
        manualSeconds = filtered.filter(\.isManual).reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        automaticSeconds = total - manualSeconds
        uniqueCustomerCount = Set(filtered.compactMap { $0.customerName }).count
        uniqueProjectCount = Set(filtered.compactMap { $0.projectName }).count

        categoryBreakdownRows = SessionBreakdownBuilder.categoryRows(
            sessions: filtered,
            todoLookup: todoLookup,
            unknownTitle: labels.unknownCategoryTitle,
            otherTitle: labels.otherTitle
        )

        customerBreakdownRows = SessionBreakdownBuilder.customerRows(
            sessions: filtered,
            noCustomerTitle: labels.noCustomerTitle,
            otherTitle: labels.otherTitle
        )

        // Aggregate once and reuse for `customerBreakdownData`.
        // Previously `customerBreakdownRows` (already computed above
        // via SessionBreakdownBuilder) and `customerBreakdownData`
        // walked the same session list twice with different key paths;
        // the donut row builder owns its own pass, but the
        // `(name, seconds)` projection used here can share one aggregate
        // result with downstream consumers.
        customerBreakdownData = aggregate(filtered, key: {
            $0.customerName ?? labels.administrativeTitle
        })

        let billable = filtered
            .filter(\.statusStartsTimer)
            .reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        let administrative = total - billable
        billableBreakdownData = [
            (labels.billableTitle, billable),
            (labels.administrativeTitle, administrative)
        ]
        .filter { $0.1 > 0 }

        projectBreakdownData = aggregate(filtered, key: { session in
            if let project = session.projectName, !project.isEmpty {
                return project
            }
            if let customer = session.customerName, !customer.isEmpty {
                return String(format: labels.noProjectFormat, customer)
            }
            return labels.administrativeTitle
        })

        let todoMap = aggregate(filtered, key: { $0.todoTitle })
        todoBreakdownData = Array(todoMap.prefix(20))
    }

    /// Stable sort. Ties on seconds previously had an
    /// indeterminate order so rerenders shuffled equal-duration rows
    /// (date-picker drag visibly bounced the table). The locale-aware
    /// secondary key on `name` keeps the row order deterministic.
    private func aggregate(
        _ sessions: [WorkSessionListItem],
        key: (WorkSessionListItem) -> String
    ) -> [(name: String, seconds: Int)] {
        var map: [String: Int] = [:]
        for session in sessions {
            map[key(session), default: 0] += session.durationSeconds ?? 0
        }
        return map
            .map { (name: $0.key, seconds: $0.value) }
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds {
                    return lhs.seconds > rhs.seconds
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
