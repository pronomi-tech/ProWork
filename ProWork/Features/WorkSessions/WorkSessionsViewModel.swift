//  WorkSessionsViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation

@MainActor
final class WorkSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkSessionListItem] = []
    @Published private(set) var todos: [TodoListItem] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [ProjectListItem] = []
    @Published private(set) var folders: [WorkFolder] = []
    @Published private(set) var folderPathByTodoId: [String: String] = [:]
    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var statuses: [TodoStatus] = []
    @Published var errorMessage: String?

    private let sessionRepository: TodoTimeSessionRepository
    private let todoRepository: TodoRepository
    private let customerRepository: CustomerRepository
    private let projectRepository: ProjectRepository
    private let workFolderRepository: WorkFolderRepository
    private let categoryRepository: TaskCategoryRepository
    private let statusRepository: TodoStatusRepository

    init(services: AppServices = .shared) {
        self.sessionRepository = services.todoTimeSessionRepository
        self.todoRepository = services.todoRepository
        self.customerRepository = services.customerRepository
        self.projectRepository = services.projectRepository
        self.workFolderRepository = services.workFolderRepository
        self.categoryRepository = services.categoryRepository
        self.statusRepository = services.statusRepository
    }

    var activeFolders: [WorkFolder] {
        folders.filter { !$0.isArchived }
    }

    var activeTodos: [TodoListItem] {
        let activeFolderIds = Set(activeFolders.map(\.id))
        return todos.filter { todo in
            todo.folderId.map { activeFolderIds.contains($0) } ?? true
        }
    }

    // MARK: - Loading

    func loadData() {
        do {
            sessions = try sessionRepository.fetchAllListItems()
            todos = try todoRepository.fetchAll()
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            folders = try workFolderRepository.fetchAll(includeArchived: true)
            folderPathByTodoId = Self.makeFolderPathByTodoId(
                todos: todos,
                folders: folders,
                projects: projects
            )
            categories = try categoryRepository.fetchAll()
            statuses = try statusRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func visibleSessions(
        for selection: WorkLocationSelection,
        includeDescendantFolders: Bool,
        showArchivedFolders: Bool = false
    ) -> [WorkSessionListItem] {
        let todoById = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        let displayedFolderIds = Set(
            folders.lazy
                .filter { showArchivedFolders || !$0.isArchived }
                .map(\.id)
        )
        if selection == .all {
            return sessions.filter { session in
                guard let todo = todoById[session.todoId] else { return false }
                return todo.folderId.map { displayedFolderIds.contains($0) } ?? true
            }
        }

        let folderIds: Set<String>?
        if case .folder(let folderId) = selection {
            let selectedFolderIds = includeDescendantFolders
                ? WorkFolderHierarchy.descendantIds(of: folderId, in: folders)
                : [folderId]
            folderIds = selectedFolderIds.intersection(displayedFolderIds)
        } else {
            folderIds = nil
        }

        return sessions.filter { session in
            guard let todo = todoById[session.todoId] else { return false }
            switch selection {
            case .all:
                return true
            case .project(let projectId):
                guard todo.projectId == projectId else { return false }
                guard includeDescendantFolders else { return todo.folderId == nil }
                return todo.folderId.map { displayedFolderIds.contains($0) } ?? true
            case .folder:
                guard let todoFolderId = todo.folderId else { return false }
                return folderIds?.contains(todoFolderId) == true
            }
        }
    }

    func folderPath(forTodoId todoId: String) -> String? {
        folderPathByTodoId[todoId]
    }

    private static func makeFolderPathByTodoId(
        todos: [TodoListItem],
        folders: [WorkFolder],
        projects: [ProjectListItem]
    ) -> [String: String] {
        var pathByFolderId = Dictionary(
            uniqueKeysWithValues: WorkFolderHierarchy.flattened(folders, projectId: nil)
                .map { ($0.id, $0.path) }
        )
        for project in projects {
            for item in WorkFolderHierarchy.flattened(folders, projectId: project.id) {
                pathByFolderId[item.id] = item.path
            }
        }
        return Dictionary(
            uniqueKeysWithValues: todos.compactMap { todo in
                guard let folderId = todo.folderId,
                      let path = pathByFolderId[folderId] else {
                    return nil
                }
                return (todo.id, path)
            }
        )
    }

    @discardableResult
    func saveFolder(_ folder: WorkFolder, isNew: Bool) -> Bool {
        do {
            if isNew {
                try workFolderRepository.insert(folder)
            } else {
                try workFolderRepository.update(folder)
            }
            loadData()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteFolder(id: String) -> Bool {
        do {
            try workFolderRepository.softDelete(id: id, by: AppServices.currentUserId)
            loadData()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func archiveFolder(id: String) -> Bool {
        do {
            try workFolderRepository.archive(id: id, by: AppServices.currentUserId)
            loadData()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restoreFolder(id: String) -> Bool {
        do {
            try workFolderRepository.restore(id: id, by: AppServices.currentUserId)
            loadData()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - CRUD

    @discardableResult
    func createManualSession(
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?,
        serviceType: ServiceType,
        billingWindowModeOverride: BillingWindowMode?,
        billingTimeTypeOverride: TimeType?,
        billingTimeTypeOverrideReason: String?
    ) -> Bool {
        do {
            try sessionRepository.insertManualSession(
                todoId: todoId,
                startedAt: startedAt,
                endedAt: endedAt,
                note: note,
                serviceType: serviceType,
                billingWindowModeOverride: billingWindowModeOverride,
                billingTimeTypeOverride: billingTimeTypeOverride,
                billingTimeTypeOverrideReason: billingTimeTypeOverrideReason
            )
            loadData()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateSession(
        id: String,
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?,
        isManual: Bool,
        serviceType: ServiceType,
        billingWindowModeOverride: BillingWindowMode?,
        billingTimeTypeOverride: TimeType?,
        billingTimeTypeOverrideReason: String?
    ) -> Bool {
        do {
            try sessionRepository.updateSession(
                id: id,
                todoId: todoId,
                startedAt: startedAt,
                endedAt: endedAt,
                note: note,
                isManual: isManual,
                serviceType: serviceType,
                billingWindowModeOverride: billingWindowModeOverride,
                billingTimeTypeOverride: billingTimeTypeOverride,
                billingTimeTypeOverrideReason: billingTimeTypeOverrideReason
            )
            loadData()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSession(id: String) {
        do {
            try sessionRepository.softDelete(id: id, by: AppServices.currentUserId)
            loadData()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func canResumeRecentlyEndedSession(
        _ session: WorkSessionListItem,
        now: Date = Date()
    ) -> Bool {
        TodoTimeSessionRepository.canResumeRecentlyEndedSession(
            session,
            among: sessions,
            now: now
        )
    }

    @discardableResult
    func resumeRecentlyEndedSession(id: String) -> Bool {
        do {
            try sessionRepository.resumeRecentlyEndedSession(sessionId: id)
            loadData()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Start/stop work

    /// Returns the session if one is active (not paused) and is running on a different todo.
    /// The view uses this to trigger a confirmation dialog.
    func activeSessionConflicting(with todoId: String) -> ActiveTodoTimeSession? {
        do {
            if let active = try sessionRepository.fetchActiveSession(),
               active.session.todoId != todoId {
                return active
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }

    /// Wrap stop + start in a single write transaction (mirrors
    /// `TodosViewModel.startWork`). Partial-fail otherwise loses the
    /// transition: prior session closed, new session never opened.
    func startWork(
        todoId: String,
        targetStatusId: String,
        stoppingActiveSessionId: String?
    ) {
        do {
            try sessionRepository.transactionally {
                if let stoppingActiveSessionId {
                    try sessionRepository.stopSession(
                        sessionId: stoppingActiveSessionId,
                        endStatusId: targetStatusId
                    )
                }
                try sessionRepository.startSession(
                    todoId: todoId,
                    startStatusId: targetStatusId
                )
            }
            loadData()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopWork(for session: WorkSessionListItem) {
        do {
            try sessionRepository.stopOpenSession(
                todoId: session.todoId,
                endStatusId: session.statusId
            )
            loadData()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
