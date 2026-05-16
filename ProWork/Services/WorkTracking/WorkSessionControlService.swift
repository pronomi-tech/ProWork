//
//  WorkSessionControlService.swift
//  ProWork
//
//   Created by Pronomi.
//

import Foundation

struct ActiveWorkSessionSummary: Identifiable, Hashable {
    let id: String
    let todoId: String
    let todoTitle: String
    let statusId: String
    let statusName: String
    let startedAt: Date
    let elapsedSeconds: Int
    let isPaused: Bool
}

enum WorkSessionControlError: LocalizedError {
    case todoNotFound
    case statusCannotStartTimer

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    var errorDescription: String? {
        switch self {
        case .todoNotFound:
            return localized("workControl.error.todoNotFound", defaultValue: "İlgili yapılacak iş bulunamadı.")
        case .statusCannotStartTimer:
            return localized("workControl.error.statusCannotStart", defaultValue: "Bu statüden süre başlatılamaz.")
        }
    }
}

@MainActor
final class WorkSessionControlService {
    private let todoRepository: TodoRepository
    private let sessionRepository: TodoTimeSessionRepository

    init(
        todoRepository: TodoRepository? = nil,
        sessionRepository: TodoTimeSessionRepository? = nil
    ) {
        self.todoRepository = todoRepository ?? TodoRepository()
        self.sessionRepository = sessionRepository ?? TodoTimeSessionRepository()
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    func fetchActiveSession() throws -> ActiveWorkSessionSummary? {
        guard let active = try sessionRepository.fetchActiveSession() else {
            return nil
        }

        let todo = try todoRepository.fetchListItem(id: active.session.todoId)
        return ActiveWorkSessionSummary(
            id: active.session.id,
            todoId: active.session.todoId,
            todoTitle: active.todoTitle,
            statusId: todo?.statusId ?? active.session.startStatusId ?? BuiltInTodoStatusId.waiting,
            statusName: todo?.statusName ?? localized("workSessions.status.active", defaultValue: "Aktif"),
            startedAt: active.session.startedAt,
            elapsedSeconds: currentElapsedSeconds(for: active.session),
            isPaused: false
        )
    }

    func fetchPausedSession() throws -> ActiveWorkSessionSummary? {
        guard let paused = try sessionRepository.fetchPausedSession() else {
            return nil
        }

        let todo = try todoRepository.fetchListItem(id: paused.session.todoId)
        return ActiveWorkSessionSummary(
            id: paused.session.id,
            todoId: paused.session.todoId,
            todoTitle: paused.todoTitle,
            statusId: todo?.statusId ?? paused.session.startStatusId ?? BuiltInTodoStatusId.waiting,
            statusName: todo?.statusName ?? localized("menuBar.status.paused", defaultValue: "Duraklatıldı"),
            startedAt: paused.session.startedAt,
            elapsedSeconds: paused.session.durationSeconds ?? 0,
            isPaused: true
        )
    }

    func fetchQuickTodos(preferredStatusIds: [String]) throws -> [TodoListItem] {
        let all = try todoRepository.fetchAll()
        let normalizedIds = Set(preferredStatusIds)
        let startableTodos = all.filter { $0.statusStartsTimer || $0.activeSessionStartedAt != nil }

        if normalizedIds.isEmpty {
            return sortedQuickTodos(startableTodos)
        }

        let filtered = all.filter {
            normalizedIds.contains($0.statusId) || $0.activeSessionStartedAt != nil
        }

        if filtered.isEmpty {
            return sortedQuickTodos(startableTodos)
        }

        return sortedQuickTodos(
            all.filter {
                normalizedIds.contains($0.statusId) || $0.activeSessionStartedAt != nil
            }
        )
    }

    func startWork(todoId: String) throws {
        guard let todo = try todoRepository.fetchListItem(id: todoId) else {
            throw WorkSessionControlError.todoNotFound
        }
        guard todo.statusStartsTimer else {
            throw WorkSessionControlError.statusCannotStartTimer
        }

        if let paused = try sessionRepository.fetchPausedSession(), paused.session.todoId == todoId {
            try sessionRepository.resumeSession(sessionId: paused.session.id)
            return
        }

        if let active = try sessionRepository.fetchActiveSession() {
            if active.session.todoId == todoId {
                return
            }

            let activeStatusId = try resolveCurrentStatusId(todoId: active.session.todoId, fallback: active.session.startStatusId)
            try sessionRepository.stopSession(
                sessionId: active.session.id,
                endStatusId: activeStatusId
            )
        }

        if let paused = try sessionRepository.fetchPausedSession() {
            let pausedStatusId = try resolveCurrentStatusId(todoId: paused.session.todoId, fallback: paused.session.startStatusId)
            try sessionRepository.stopSession(
                sessionId: paused.session.id,
                endStatusId: pausedStatusId
            )
        }

        try sessionRepository.startSession(
            todoId: todoId,
            startStatusId: todo.statusId
        )
    }

    func stopWork(todoId: String) throws {
        let statusId = try resolveCurrentStatusId(todoId: todoId, fallback: BuiltInTodoStatusId.waiting)
        try sessionRepository.stopOpenSession(
            todoId: todoId,
            endStatusId: statusId
        )
    }

    func stopActiveWork() throws {
        guard let active = try sessionRepository.fetchActiveSession() else {
            return
        }

        let statusId = try resolveCurrentStatusId(todoId: active.session.todoId, fallback: active.session.startStatusId)
        try sessionRepository.stopSession(
            sessionId: active.session.id,
            endStatusId: statusId
        )
    }

    func pauseActiveWork() throws {
        guard let active = try sessionRepository.fetchActiveSession() else {
            return
        }

        try sessionRepository.pauseSession(sessionId: active.session.id)
    }

    func resumePausedWork() throws {
        guard let paused = try sessionRepository.fetchPausedSession() else {
            return
        }

        if let active = try sessionRepository.fetchActiveSession(), active.session.id != paused.session.id {
            let statusId = try resolveCurrentStatusId(
                todoId: active.session.todoId,
                fallback: active.session.startStatusId
            )
            try sessionRepository.stopSession(sessionId: active.session.id, endStatusId: statusId)
        }

        try sessionRepository.resumeSession(sessionId: paused.session.id)
    }

    private func resolveCurrentStatusId(todoId: String, fallback: String?) throws -> String {
        if let todo = try todoRepository.fetch(id: todoId) {
            return todo.statusId
        }

        return fallback ?? BuiltInTodoStatusId.waiting
    }

    private func sortedQuickTodos(_ todos: [TodoListItem]) -> [TodoListItem] {
        todos.sorted { lhs, rhs in
            if (lhs.activeSessionStartedAt != nil) != (rhs.activeSessionStartedAt != nil) {
                return lhs.activeSessionStartedAt != nil
            }

            let lhsDue = lhs.dueDate ?? lhs.plannedDate ?? .distantFuture
            let rhsDue = rhs.dueDate ?? rhs.plannedDate ?? .distantFuture
            if lhsDue != rhsDue {
                return lhsDue < rhsDue
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func currentElapsedSeconds(for session: TodoTimeSession) -> Int {
        let base = session.durationSeconds ?? 0
        guard let runningSinceAt = session.runningSinceAt else {
            return max(0, base)
        }

        return max(0, base + Int(Date().timeIntervalSince(runningSinceAt)))
    }
}
