//  TodosViewModel.swift
//  ProWork
//  Created by Pronomi.
//  Domain state and repository orchestration for TodosView.
//  Pattern (Item 7 — Architectural Refactor):
//    - Repository access is removed from the View entirely; the View only
//      holds UI state (is the sheet open, which confirmation dialog is shown).
//    - Domain state and mutations were moved to an `@ObservableObject` ViewModel.
//    - Dependencies are injected via `AppServices`; tests can provide an
//      alternative AppServices instance.

import Combine
import Foundation
import SwiftUI

@MainActor
final class TodosViewModel: ObservableObject {
    @Published private(set) var todos: [TodoListItem] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [ProjectListItem] = []
    @Published private(set) var folders: [WorkFolder] = []
    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var statuses: [TodoStatus] = []
    @Published var quickCategoryId: String = ""
    @Published var errorMessage: String?
    @Published private(set) var errorEventID: UUID?

    private let todoRepository: TodoRepository
    private let customerRepository: CustomerRepository
    private let projectRepository: ProjectRepository
    private let workFolderRepository: WorkFolderRepository
    private let categoryRepository: TaskCategoryRepository
    private let statusRepository: TodoStatusRepository
    private let timeSessionRepository: TodoTimeSessionRepository
    private let billingOverrideRepository: TodoBillingOverrideRepository

    init(services: AppServices = .shared) {
        self.todoRepository = services.todoRepository
        self.customerRepository = services.customerRepository
        self.projectRepository = services.projectRepository
        self.workFolderRepository = services.workFolderRepository
        self.categoryRepository = services.categoryRepository
        self.statusRepository = services.statusRepository
        self.timeSessionRepository = services.todoTimeSessionRepository
        self.billingOverrideRepository = services.todoBillingOverrideRepository
    }

    // MARK: - Derived

    var boardStatuses: [TodoStatus] {
        statuses
            .filter { $0.isActive && $0.showInBoard }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var defaultTodoStatusId: String {
        statuses.first(where: { $0.id == BuiltInTodoStatusId.waiting })?.id
            ?? statuses.first(where: { $0.isActive })?.id
            ?? BuiltInTodoStatusId.waiting
    }

    var activeFolders: [WorkFolder] {
        folders.filter { !$0.isArchived }
    }

    func categoryDefaultBillable(categoryId: String) -> Bool {
        categories.first(where: { $0.id == categoryId })?.isBillableDefault ?? true
    }

    func visibleTodos(
        for selection: WorkLocationSelection,
        includeDescendantFolders: Bool,
        showArchivedFolders: Bool = false
    ) -> [TodoListItem] {
        let displayedFolderIds = Set(
            folders.lazy
                .filter { showArchivedFolders || !$0.isArchived }
                .map(\.id)
        )
        switch selection {
        case .all:
            return todos.filter { todo in
                todo.folderId.map { displayedFolderIds.contains($0) } ?? true
            }
        case .project(let projectId):
            return todos.filter {
                guard $0.projectId == projectId else { return false }
                guard includeDescendantFolders else { return $0.folderId == nil }
                return $0.folderId.map { displayedFolderIds.contains($0) } ?? true
            }
        case .folder(let folderId):
            let folderIds = includeDescendantFolders
                ? WorkFolderHierarchy.descendantIds(of: folderId, in: folders)
                : Set([folderId])
            let visibleFolderIds = folderIds.intersection(displayedFolderIds)
            return todos.filter { todo in
                guard let todoFolderId = todo.folderId else { return false }
                return visibleFolderIds.contains(todoFolderId)
            }
        }
    }

    func todosForStatus(
        _ status: TodoStatus,
        selection: WorkLocationSelection,
        includeDescendantFolders: Bool,
        showArchivedFolders: Bool = false
    ) -> [TodoListItem] {
        visibleTodos(
            for: selection,
            includeDescendantFolders: includeDescendantFolders,
            showArchivedFolders: showArchivedFolders
        ).filter { $0.statusId == status.id }
    }

    // MARK: - Load

    func load() {
        do {
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            folders = try workFolderRepository.fetchAll(includeArchived: true)
            categories = try categoryRepository.fetchAll()
            statuses = try statusRepository.fetchAll()
            todos = try todoRepository.fetchAll()

            if quickCategoryId.isEmpty {
                quickCategoryId = categories.first?.id ?? ""
            }

            if !quickCategoryId.isEmpty,
               !categories.contains(where: { $0.id == quickCategoryId }) {
                quickCategoryId = categories.first?.id ?? ""
            }

            errorMessage = nil
        } catch {
            report(error)
        }
    }

    // MARK: - CRUD

    func quickAdd(title: String, location: WorkLocationSelection) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !quickCategoryId.isEmpty else {
            return
        }

        let assignment = location.assignment(projects: projects, folders: folders)
        let todo = Todo(
            customerId: assignment.customerId,
            projectId: assignment.projectId,
            folderId: assignment.folderId,
            categoryId: quickCategoryId,
            title: cleanTitle,
            statusId: defaultTodoStatusId,
            priority: "normal",
            isBillable: categoryDefaultBillable(categoryId: quickCategoryId)
        )

        create(todo)
    }

    @discardableResult
    func saveFolder(_ folder: WorkFolder, isNew: Bool) -> Bool {
        do {
            if isNew {
                try workFolderRepository.insert(folder)
            } else {
                try workFolderRepository.update(folder)
            }
            load()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func deleteFolder(id: String) -> Bool {
        do {
            try workFolderRepository.softDelete(id: id, by: AppServices.currentUserId)
            load()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func archiveFolder(id: String) -> Bool {
        do {
            try workFolderRepository.archive(id: id, by: AppServices.currentUserId)
            load()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func restoreFolder(id: String) -> Bool {
        do {
            try workFolderRepository.restore(id: id, by: AppServices.currentUserId)
            load()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Returns `true` if `create` succeeded; the View uses this to decide whether to dismiss the dialog.
    @discardableResult
    func create(_ todo: Todo, billingOverride: TodoBillingOverride? = nil) -> Bool {
        do {
            try todoRepository.transactionally {
                try todoRepository.insert(todo)
                if let billingOverride {
                    try billingOverrideRepository.upsert(billingOverride)
                }
            }
            load()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func update(_ todo: Todo, billingOverride: TodoBillingOverride? = nil) -> Bool {
        do {
            try todoRepository.transactionally {
                try todoRepository.update(todo)
                if let billingOverride {
                    try billingOverrideRepository.upsert(billingOverride)
                } else {
                    try billingOverrideRepository.remove(
                        todoId: todo.id,
                        by: AppServices.currentUserId
                    )
                }
            }
            load()
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    func delete(id: String) {
        do {
            // We use soft delete: if the record has an open work session or
            // finalized billing lines, a hard delete would leave orphan rows.
            // `softDelete` stamps `deletedAt`; reports are not affected.
            try todoRepository.softDelete(id: id, by: AppServices.currentUserId)
            load()
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    // MARK: - Status moves

    /// Called when the user drags a todo to a different status on the board.
    /// If `targetStatus.startsTimer`, the View must start a confirmation flow;
    /// this method only executes the DB side.
    func moveTodo(
        _ todo: TodoListItem,
        to targetStatus: TodoStatus
    ) -> MoveTodoResult {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else {
            return .skipped
        }

        let previousTodo = todos[index]
        guard previousTodo.statusId != targetStatus.id else {
            return .skipped
        }

        let completedAt: Date?
        if targetStatus.marksCompleted {
            completedAt = previousTodo.completedAt ?? Date()
        } else {
            completedAt = nil
        }

        let updatedTodo = makeUpdatedTodo(
            previousTodo,
            targetStatus: targetStatus,
            completedAt: completedAt,
            activeSessionStartedAt: nil
        )

        todos[index] = updatedTodo

        // Wrap the two repository writes in a single
        // `inWriteTransaction` so a failed `updateStatus` rolls back
        // the `stopOpenSession` side effect. Previously the UI rolled
        // back its `todos[index] = updatedTodo` cache but the DB was
        // left in a stopped-session + open-status state.
        do {
            try timeSessionRepository.transactionally {
                if targetStatus.stopsTimer {
                    try timeSessionRepository.stopOpenSession(
                        todoId: previousTodo.id,
                        endStatusId: targetStatus.id
                    )
                }

                try todoRepository.updateStatus(
                    id: previousTodo.id,
                    statusId: targetStatus.id,
                    completedAt: completedAt
                )
            }

            errorMessage = nil
            return targetStatus.startsTimer ? .needsWorkStart : .moved
        } catch {
            todos[index] = previousTodo
            report(error)
            return .failed
        }
    }

    enum MoveTodoResult {
        case moved
        case needsWorkStart
        case failed
        case skipped
    }

    // MARK: - Work session control

    /// Returns the active (non-paused) session if one is running on a different todo.
    /// The View uses this to trigger a confirmation dialog.
    func activeSessionConflicting(with todoId: String) -> ActiveTodoTimeSession? {
        do {
            if let active = try timeSessionRepository.fetchActiveSession(),
               active.session.todoId != todoId {
                return active
            }
        } catch {
            report(error)
        }
        return nil
    }

    /// Stop-then-start sequence runs in one write transaction.
    /// Otherwise a `startSession` failure leaves the previous session
    /// closed with no replacement open — measurable time disappears
    /// and the user must manually create a "lost work" session.
    func startWork(
        todoId: String,
        targetStatus: TodoStatus,
        stoppingActiveSessionId: String?
    ) {
        do {
            try timeSessionRepository.transactionally {
                if let stoppingActiveSessionId {
                    try timeSessionRepository.stopSession(
                        sessionId: stoppingActiveSessionId,
                        endStatusId: targetStatus.id
                    )
                }

                try timeSessionRepository.startSession(
                    todoId: todoId,
                    startStatusId: targetStatus.id
                )
            }

            if let index = todos.firstIndex(where: { $0.id == todoId }) {
                var updatedTodo = todos[index]
                updatedTodo.activeSessionStartedAt = Date()
                updatedTodo.updatedAt = Date()
                todos[index] = updatedTodo
            }

            errorMessage = nil
        } catch {
            report(error)
        }
    }

    func stopWork(for todo: TodoListItem) {
        do {
            try timeSessionRepository.stopOpenSession(
                todoId: todo.id,
                endStatusId: todo.statusId
            )

            if let index = todos.firstIndex(where: { $0.id == todo.id }) {
                var updatedTodo = todos[index]
                updatedTodo.activeSessionStartedAt = nil
                updatedTodo.updatedAt = Date()
                todos[index] = updatedTodo
            }

            errorMessage = nil
        } catch {
            report(error)
        }
    }

    // MARK: - Helpers

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        errorEventID = UUID()
    }

    private func makeUpdatedTodo(
        _ todo: TodoListItem,
        targetStatus: TodoStatus,
        completedAt: Date?,
        activeSessionStartedAt: Date?
    ) -> TodoListItem {
        var updatedTodo = todo
        updatedTodo.statusId = targetStatus.id
        updatedTodo.statusName = targetStatus.name
        updatedTodo.statusColor = targetStatus.color
        updatedTodo.statusStartsTimer = targetStatus.startsTimer
        updatedTodo.statusStopsTimer = targetStatus.stopsTimer
        updatedTodo.statusMarksOpen = targetStatus.marksOpen
        updatedTodo.statusMarksCompleted = targetStatus.marksCompleted
        updatedTodo.statusMarksCancelled = targetStatus.marksCancelled
        updatedTodo.completedAt = completedAt
        updatedTodo.activeSessionStartedAt = activeSessionStartedAt
        updatedTodo.updatedAt = Date()
        return updatedTodo
    }

}
