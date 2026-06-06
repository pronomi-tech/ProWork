//  WorkSessionControlService.swift
//  ProWork
//   Created by Pronomi.

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

    /// Previously evaluated the same
    /// `normalizedIds.contains(statusId) || activeSessionStartedAt != nil`
    /// predicate twice — once to test for emptiness and once to materialise
    /// the result. Compute it once and reuse the array.
    /// single-pass partitioning. The previous version did two
    /// `all.filter` passes (one for `startableTodos`, one for
    /// `filtered`); on a busy org both walks scan thousands of rows.
    /// One traversal pushes each row into the right bucket and the
    /// fallback uses the already-computed `startable` set.
    func fetchQuickTodos(preferredStatusIds: [String]) throws -> [TodoListItem] {
        let all = try todoRepository.fetchAll()
        let normalizedIds = Set(preferredStatusIds)
        let hasPreferred = !normalizedIds.isEmpty

        var startable: [TodoListItem] = []
        var preferred: [TodoListItem] = []
        for item in all {
            let isStartable = item.statusStartsTimer || item.activeSessionStartedAt != nil
            if isStartable {
                startable.append(item)
            }
            if hasPreferred,
               normalizedIds.contains(item.statusId) || item.activeSessionStartedAt != nil {
                preferred.append(item)
            }
        }

        if !hasPreferred || preferred.isEmpty {
            return sortedQuickTodos(startable)
        }
        return sortedQuickTodos(preferred)
    }

    // All lifecycle entry points (start/stop/pause/resume) wrap their
    // read-then-write sequence in `sessionRepository.transactionally`. The
    // wrapper holds the in-process recursive lock and SQLite's
    // BEGIN IMMEDIATE for the whole flow, so menu-bar + main window
    // double-clicks can't interleave a fetch + insert to produce two open
    // sessions. The partial unique index on
    // `todo_time_sessions(organizationId) WHERE endedAt IS NULL AND
    // deletedAt IS NULL` is the last-resort guard at the DB level.

    func startWork(todoId: String) throws {
        guard let todo = try todoRepository.fetchListItem(id: todoId) else {
            throw WorkSessionControlError.todoNotFound
        }
        guard todo.statusStartsTimer else {
            throw WorkSessionControlError.statusCannotStartTimer
        }

        try sessionRepository.transactionally {
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
    }

    func stopWork(todoId: String) throws {
        let statusId = try resolveCurrentStatusId(todoId: todoId, fallback: BuiltInTodoStatusId.waiting)
        try sessionRepository.transactionally {
            try sessionRepository.stopOpenSession(
                todoId: todoId,
                endStatusId: statusId
            )
        }
    }

    func stopActiveWork() throws {
        try sessionRepository.transactionally {
            guard let active = try sessionRepository.fetchActiveSession() else {
                return
            }

            let statusId = try resolveCurrentStatusId(todoId: active.session.todoId, fallback: active.session.startStatusId)
            try sessionRepository.stopSession(
                sessionId: active.session.id,
                endStatusId: statusId
            )
        }
    }

    func pauseActiveWork() throws {
        try sessionRepository.transactionally {
            guard let active = try sessionRepository.fetchActiveSession() else {
                return
            }

            try sessionRepository.pauseSession(sessionId: active.session.id)
        }
    }

    func resumePausedWork() throws {
        try sessionRepository.transactionally {
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
