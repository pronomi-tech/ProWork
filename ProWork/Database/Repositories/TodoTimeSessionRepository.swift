//  TodoTimeSessionRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

struct ActiveTodoTimeSession: Hashable {
    let session: TodoTimeSession
    let todoTitle: String
}

struct PausedTodoTimeSession: Hashable {
    let session: TodoTimeSession
    let todoTitle: String
}

final class TodoTimeSessionRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    // MARK: - Transaction boundary
    // Work-session lifecycle flows (start/stop/pause/resume) interleave
    // read + write steps; if another thread closes the same session
    // between the two steps, state corruption like "two active sessions"
    // or accidentally pausing a finished session can occur (code review
    // K5). The service layer wraps every such call in a `transactionally(_:)`
    // block; `AppDatabase.inWriteTransaction` blocks the read-then-write
    // race using both `NSRecursiveLock` and `BEGIN IMMEDIATE`.
    // engeller.

    func transactionally<T>(_ block: () throws -> T) throws -> T {
        try database.inWriteTransaction(block)
    }

    // MARK: - Read

    func fetchAllListItems() throws -> [WorkSessionListItem] {
        // SELECT used to include `s.runningSinceAt` and `s.pausedAt`
        // even though the mapper never consumed them — the column
        // reads were wasted and the offset constants made the mapper
        // brittle. Removed.
        let sql = """
        SELECT
            s.id,
            s.todoId,
            t.title AS todoTitle,

            c.name AS customerName,
            p.name AS projectName,

            t.statusId,
            ts.name AS statusName,
            ts.color AS statusColor,
            ts.startsTimer,
            ts.stopsTimer,
            ts.marksCompleted,
            ts.marksCancelled,

            s.startedAt,
            s.endedAt,
            s.durationSeconds,
            s.isManual,
            s.note,

            s.createdAt,
            s.updatedAt
        FROM todo_time_sessions s
        INNER JOIN todos t ON t.id = s.todoId AND t.deletedAt IS NULL
        INNER JOIN todo_statuses ts ON ts.id = t.statusId
        LEFT JOIN customers c ON c.id = t.customerId AND c.deletedAt IS NULL
        LEFT JOIN projects p ON p.id = t.projectId AND p.deletedAt IS NULL
        WHERE s.deletedAt IS NULL
        ORDER BY s.startedAt DESC;
        """

        return try database.query(sql) { statement in
            WorkSessionListItem(
                id: statement.text(at: 0) ?? UUID().uuidString,
                todoId: statement.text(at: 1) ?? "",
                todoTitle: statement.text(at: 2) ?? localized("workSessions.fallback.unknownTodo", defaultValue: "Bilinmeyen iş"),

                customerName: statement.text(at: 3),
                projectName: statement.text(at: 4),

                statusId: statement.text(at: 5) ?? BuiltInTodoStatusId.waiting,
                statusName: statement.text(at: 6) ?? localized("workSessions.status.waiting", defaultValue: "Beklemede"),
                statusColor: statement.text(at: 7),
                statusStartsTimer: statement.int(at: 8) == 1,
                statusStopsTimer: statement.int(at: 9) == 1,
                statusMarksCompleted: statement.int(at: 10) == 1,
                statusMarksCancelled: statement.int(at: 11) == 1,

                startedAt: Self.parseDate(statement.text(at: 12)) ?? Date(),
                endedAt: Self.parseDate(statement.text(at: 13)),
                durationSeconds: statement.optionalInt(at: 14),
                isManual: statement.int(at: 15) == 1,
                note: statement.text(at: 16),

                createdAt: Self.parseDate(statement.text(at: 17)) ?? Date(),
                updatedAt: Self.parseDate(statement.text(at: 18)) ?? Date()
            )
        }
    }

    /// Customer-scoped variant that pushes the filter into SQL
    /// instead of fetching every org session and filtering by
    /// customerName in Swift. Joins `todos.customerId` directly so the
    /// pre-resolved customerIdByName lookup at the caller becomes
    /// unnecessary; the SQL planner can use `idx_todos_customerId`.
    func fetchAllListItems(forCustomerId customerId: String) throws -> [WorkSessionListItem] {
        let sql = """
        SELECT
            s.id,
            s.todoId,
            t.title AS todoTitle,

            c.name AS customerName,
            p.name AS projectName,

            t.statusId,
            ts.name AS statusName,
            ts.color AS statusColor,
            ts.startsTimer,
            ts.stopsTimer,
            ts.marksCompleted,
            ts.marksCancelled,

            s.startedAt,
            s.endedAt,
            s.durationSeconds,
            s.isManual,
            s.note,

            s.createdAt,
            s.updatedAt
        FROM todo_time_sessions s
        INNER JOIN todos t ON t.id = s.todoId AND t.deletedAt IS NULL AND t.customerId = ?
        INNER JOIN todo_statuses ts ON ts.id = t.statusId
        LEFT JOIN customers c ON c.id = t.customerId AND c.deletedAt IS NULL
        LEFT JOIN projects p ON p.id = t.projectId AND p.deletedAt IS NULL
        WHERE s.deletedAt IS NULL
        ORDER BY s.startedAt DESC;
        """

        return try database.query(sql, map: { statement in
            WorkSessionListItem(
                id: statement.text(at: 0) ?? UUID().uuidString,
                todoId: statement.text(at: 1) ?? "",
                todoTitle: statement.text(at: 2) ?? localized("workSessions.fallback.unknownTodo", defaultValue: "Bilinmeyen iş"),
                customerName: statement.text(at: 3),
                projectName: statement.text(at: 4),
                statusId: statement.text(at: 5) ?? BuiltInTodoStatusId.waiting,
                statusName: statement.text(at: 6) ?? localized("workSessions.status.waiting", defaultValue: "Beklemede"),
                statusColor: statement.text(at: 7),
                statusStartsTimer: statement.int(at: 8) == 1,
                statusStopsTimer: statement.int(at: 9) == 1,
                statusMarksCompleted: statement.int(at: 10) == 1,
                statusMarksCancelled: statement.int(at: 11) == 1,
                startedAt: Self.parseDate(statement.text(at: 12)) ?? Date(),
                endedAt: Self.parseDate(statement.text(at: 13)),
                durationSeconds: statement.optionalInt(at: 14),
                isManual: statement.int(at: 15) == 1,
                note: statement.text(at: 16),
                createdAt: Self.parseDate(statement.text(at: 17)) ?? Date(),
                updatedAt: Self.parseDate(statement.text(at: 18)) ?? Date()
            )
        }, bind: { stmt in
            stmt.bindText(customerId, at: 1)
        })
    }

    /// Bulk fetch for given session ids (reporting / billing).
    /// Split into 500-item chunks so we stay under `SQLITE_MAX_VARIABLE_NUMBER`.
    func fetch(ids: [String]) throws -> [TodoTimeSession] {
        guard !ids.isEmpty else { return [] }

        var results: [TodoTimeSession] = []
        results.reserveCapacity(ids.count)

        let chunkSize = SQLiteParameterLimit.inClauseChunk
        for chunkStart in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[chunkStart..<min(chunkStart + chunkSize, ids.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = Self.selectAllColumnsSQL + """
             WHERE id IN (\(placeholders)) AND deletedAt IS NULL;
            """

            let rows = try database.query(
                sql,
                map: { statement in try Self.mapSession(statement) },
                bind: { statement in
                    for (offset, id) in chunk.enumerated() {
                        statement.bindText(id, at: Int32(offset + 1))
                    }
                }
            )
            results.append(contentsOf: rows)
        }

        return results
    }

    func fetchSessions(todoId: String) throws -> [TodoTimeSession] {
        let sql = Self.selectAllColumnsSQL + """
         WHERE todoId = ? AND deletedAt IS NULL
         ORDER BY startedAt DESC;
        """

        return try database.query(
            sql,
            map: { statement in try Self.mapSession(statement) },
            bind: { statement in statement.bindText(todoId, at: 1) }
        )
    }

    func fetchOpenSession(todoId: String) throws -> TodoTimeSession? {
        let sql = Self.selectAllColumnsSQL + """
         WHERE todoId = ? AND endedAt IS NULL AND deletedAt IS NULL
         ORDER BY startedAt DESC
         LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in try Self.mapSession(statement) },
            bind: { statement in statement.bindText(todoId, at: 1) }
        ).first
    }

    func fetchAnyOpenSession() throws -> TodoTimeSession? {
        let sql = Self.selectAllColumnsSQL + """
         WHERE endedAt IS NULL AND deletedAt IS NULL
         ORDER BY startedAt DESC
         LIMIT 1;
        """

        return try database.query(sql) { statement in
            try Self.mapSession(statement)
        }.first
    }

    func fetchActiveSession() throws -> ActiveTodoTimeSession? {
        let sql = """
        SELECT
            s.id, s.todoId, s.startedAt, s.runningSinceAt, s.pausedAt, s.endedAt, s.durationSeconds,
            s.startStatusId, s.endStatusId, s.note, s.isManual,
            s.organizationId, s.createdByUserId, s.updatedByUserId,
            s.createdAt, s.updatedAt, s.deletedAt, s.rowVersion,
            s.syncStatus, s.lastSyncedAt, s.originDeviceId,
            t.title
        FROM todo_time_sessions s
        INNER JOIN todos t ON t.id = s.todoId AND t.deletedAt IS NULL
        WHERE s.endedAt IS NULL AND s.pausedAt IS NULL AND s.deletedAt IS NULL
        ORDER BY COALESCE(s.runningSinceAt, s.startedAt) DESC
        LIMIT 1;
        """

        // Title kolonu en sonda.
        let rows = try database.query(sql) { statement in
            ActiveTodoTimeSession(
                session: try Self.mapSession(statement),
                todoTitle: statement.text(at: 21) ?? localized("workSessions.fallback.unknownSession", defaultValue: "Bilinmeyen çalışma")
            )
        }

        return rows.first
    }

    func fetchPausedSession() throws -> PausedTodoTimeSession? {
        let sql = """
        SELECT
            s.id, s.todoId, s.startedAt, s.runningSinceAt, s.pausedAt, s.endedAt, s.durationSeconds,
            s.startStatusId, s.endStatusId, s.note, s.isManual,
            s.organizationId, s.createdByUserId, s.updatedByUserId,
            s.createdAt, s.updatedAt, s.deletedAt, s.rowVersion,
            s.syncStatus, s.lastSyncedAt, s.originDeviceId,
            t.title
        FROM todo_time_sessions s
        INNER JOIN todos t ON t.id = s.todoId AND t.deletedAt IS NULL
        WHERE s.endedAt IS NULL AND s.pausedAt IS NOT NULL AND s.deletedAt IS NULL
        ORDER BY s.pausedAt DESC
        LIMIT 1;
        """

        let rows = try database.query(sql) { statement in
            PausedTodoTimeSession(
                session: try Self.mapSession(statement),
                todoTitle: statement.text(at: 21) ?? localized("workSessions.fallback.pausedSession", defaultValue: "Duraklatılmış çalışma")
            )
        }

        return rows.first
    }

    // MARK: - Write

    /// Outcome of a `startSession` attempt. Returning a typed result
    /// instead of `Void` lets callers distinguish "session created"
    /// from "another open session already exists" — the previous silent
    /// return surfaced as `success` to the UI even though nothing
    /// changed.
    enum StartOutcome {
        case started
        case alreadyOpen
    }

    @discardableResult
    func startSession(
        todoId: String,
        startStatusId: String
    ) throws -> StartOutcome {
        if try fetchOpenSession(todoId: todoId) != nil {
            return .alreadyOpen
        }

        let now = Date()
        let session = TodoTimeSession(
            todoId: todoId,
            startedAt: now,
            runningSinceAt: now,
            pausedAt: nil,
            durationSeconds: 0,
            startStatusId: startStatusId,
            isManual: false,
            createdAt: now,
            updatedAt: now
        )

        try insert(session)
        return .started
    }

    func insertManualSession(
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?
    ) throws {
        guard endedAt > startedAt else {
            throw TodoTimeSessionRepositoryError.invalidDateRange
        }

        let now = Date()
        let durationSeconds = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        let session = TodoTimeSession(
            todoId: todoId,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            startStatusId: nil,
            endStatusId: nil,
            note: cleanNote?.isEmpty == true ? nil : cleanNote,
            isManual: true,
            createdAt: now,
            updatedAt: now
        )

        try insert(session)
    }

    func updateSession(
        id: String,
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?,
        isManual: Bool,
        by userId: String = BuiltInUserId.defaultOwner
    ) throws {
        guard endedAt > startedAt else {
            throw TodoTimeSessionRepositoryError.invalidDateRange
        }

        let durationSeconds = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        let sql = """
        UPDATE todo_time_sessions
        SET
            todoId = ?, startedAt = ?, runningSinceAt = NULL, pausedAt = NULL, endedAt = ?,
            durationSeconds = ?, note = ?, isManual = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND endedAt IS NOT NULL AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(todoId, at: 1)
            statement.bindText(Self.formatDate(startedAt), at: 2)
            statement.bindText(Self.formatDate(endedAt), at: 3)
            statement.bindInt(durationSeconds, at: 4)
            statement.bindText(cleanNote?.isEmpty == true ? nil : cleanNote, at: 5)
            statement.bindInt(isManual ? 1 : 0, at: 6)
            statement.bindText(userId, at: 7)
            statement.bindText(Self.formatDate(Date()), at: 8)
            statement.bindText(id, at: 9)
        }

        // The WHERE clause requires `endedAt IS NOT NULL` (only closed
        // sessions are editable). When the caller targets an open
        // session the UPDATE matches zero rows and SQLite reports
        // success — without this guard the UI would think the edit
        // succeeded. Throwing `precondition*` lets the caller surface
        // a clearer error.
        guard database.lastChangedRowCount > 0 else {
            throw TodoTimeSessionRepositoryError.preconditionUnmet
        }
    }

    /// Pause is a read-then-write flow: we fetch the currently active
    /// session, compute its accumulated duration, then UPDATE. Without a
    /// write transaction another caller could insert/update an open
    /// session between the read and the update, so the duration we
    /// compute could lag behind reality. `inWriteTransaction` serialises
    /// the read-write pair.
    func pauseSession(
        sessionId: String,
        by userId: String = BuiltInUserId.defaultOwner
    ) throws {
        try database.inWriteTransaction {
            guard let session = try fetchActiveSession()?.session else {
                return
            }
            guard session.id == sessionId else {
                return
            }

            let pausedAt = Date()
            let accumulated = accumulatedDuration(for: session, until: pausedAt)

            let sql = """
            UPDATE todo_time_sessions
            SET
                pausedAt = ?, runningSinceAt = NULL, durationSeconds = ?,
                updatedByUserId = ?, updatedAt = ?,
                rowVersion = rowVersion + 1, syncStatus = 'local'
            WHERE id = ? AND endedAt IS NULL AND pausedAt IS NULL AND deletedAt IS NULL;
            """

            try database.execute(sql) { statement in
                statement.bindText(Self.formatDate(pausedAt), at: 1)
                statement.bindInt(accumulated, at: 2)
                statement.bindText(userId, at: 3)
                statement.bindText(Self.formatDate(pausedAt), at: 4)
                statement.bindText(sessionId, at: 5)
            }
        }
    }

    func resumeSession(
        sessionId: String,
        by userId: String = BuiltInUserId.defaultOwner
    ) throws {
        // Single UPDATE but wrapped for symmetry with pause/stop; the
        // savepoint cost is negligible and a future variant might need
        // to read the previous state first.
        try database.inWriteTransaction {
            let resumedAt = Date()
            let sql = """
            UPDATE todo_time_sessions
            SET
                pausedAt = NULL, runningSinceAt = ?, updatedByUserId = ?, updatedAt = ?,
                rowVersion = rowVersion + 1, syncStatus = 'local'
            WHERE id = ? AND endedAt IS NULL AND pausedAt IS NOT NULL AND deletedAt IS NULL;
            """

            try database.execute(sql) { statement in
                statement.bindText(Self.formatDate(resumedAt), at: 1)
                statement.bindText(userId, at: 2)
                statement.bindText(Self.formatDate(resumedAt), at: 3)
                statement.bindText(sessionId, at: 4)
            }
        }
    }

    func stopOpenSession(
        todoId: String,
        endStatusId: String
    ) throws {
        guard let openSession = try fetchOpenSession(todoId: todoId) else {
            return
        }

        try stopSession(session: openSession, endStatusId: endStatusId)
    }

    func stopSession(
        sessionId: String,
        endStatusId: String
    ) throws {
        let sql = Self.selectAllColumnsSQL + """
         WHERE id = ? AND endedAt IS NULL AND deletedAt IS NULL
         LIMIT 1;
        """

        let sessions = try database.query(
            sql,
            map: { statement in try Self.mapSession(statement) },
            bind: { statement in statement.bindText(sessionId, at: 1) }
        )

        guard let session = sessions.first else {
            return
        }

        try stopSession(session: session, endStatusId: endStatusId)
    }

    /// Hard delete — test fixtures only. See CustomerRepository._hardDelete.
    func _hardDelete(id: String) throws {
        let sql = """
        DELETE FROM todo_time_sessions
        WHERE id = ?;
        """

        try database.execute(sql) { statement in
            statement.bindText(id, at: 1)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        try database.softDelete(table: "todo_time_sessions", id: id, by: userId)
    }

    private func insert(_ session: TodoTimeSession) throws {
        let sql = """
        INSERT INTO todo_time_sessions (
            id, todoId, startedAt, runningSinceAt, pausedAt, endedAt, durationSeconds,
            startStatusId, endStatusId, note, isManual,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(session.id, at: 1)
            statement.bindText(session.todoId, at: 2)
            statement.bindText(Self.formatDate(session.startedAt), at: 3)
            statement.bindText(Self.formatDate(session.runningSinceAt), at: 4)
            statement.bindText(Self.formatDate(session.pausedAt), at: 5)
            statement.bindText(Self.formatDate(session.endedAt), at: 6)
            statement.bindOptionalInt(session.durationSeconds, at: 7)
            statement.bindText(session.startStatusId, at: 8)
            statement.bindText(session.endStatusId, at: 9)
            statement.bindText(session.note, at: 10)
            statement.bindInt(session.isManual ? 1 : 0, at: 11)
            statement.bindMetadata(session.meta, startingAt: 12)
        }
    }

    /// `stopSession` is read-then-write — duration is computed from the
    /// passed-in session snapshot, but the underlying row could be
    /// updated by another caller between the snapshot and the UPDATE.
    /// Serialise the pair through `inWriteTransaction` so the snapshot
    /// we close on matches what we read.
    private func stopSession(
        session: TodoTimeSession,
        endStatusId: String,
        by userId: String = BuiltInUserId.defaultOwner
    ) throws {
        try database.inWriteTransaction {
            let endedAt = Date()
            let durationSeconds = accumulatedDuration(for: session, until: endedAt)

            let sql = """
            UPDATE todo_time_sessions
            SET
                runningSinceAt = NULL, pausedAt = NULL, endedAt = ?, durationSeconds = ?, endStatusId = ?,
                updatedByUserId = ?, updatedAt = ?,
                rowVersion = rowVersion + 1, syncStatus = 'local'
            WHERE id = ?;
            """

            try database.execute(sql) { statement in
                statement.bindText(Self.formatDate(endedAt), at: 1)
                statement.bindInt(durationSeconds, at: 2)
                statement.bindText(endStatusId, at: 3)
                statement.bindText(userId, at: 4)
                statement.bindText(Self.formatDate(Date()), at: 5)
                statement.bindText(session.id, at: 6)
            }
        }
    }

    private func accumulatedDuration(for session: TodoTimeSession, until endDate: Date) -> Int {
        let baseDuration = session.durationSeconds ?? 0
        guard let runningSinceAt = session.runningSinceAt else {
            return max(0, baseDuration)
        }

        return max(0, baseDuration + Int(endDate.timeIntervalSince(runningSinceAt)))
    }
}

enum TodoTimeSessionRepositoryError: LocalizedError {
    case invalidDateRange
    case preconditionUnmet

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return ProWorkLocalizer.shared.string("workSessions.error.invalidDateRange", defaultValue: "Bitiş zamanı başlangıç zamanından sonra olmalıdır.")
        case .preconditionUnmet:
            return ProWorkLocalizer.shared.string(
                "workSessions.error.preconditionUnmet",
                defaultValue: "Bu çalışma kaydı düzenlenemiyor — kayıt açık veya silinmiş olabilir."
            )
        }
    }
}

private extension TodoTimeSessionRepository {
    /// SELECT combining business fields + metadata columns.
    /// Usage: `selectAllColumnsSQL + " WHERE ..."`
    static let selectAllColumnsSQL = """
    SELECT
        id, todoId, startedAt, runningSinceAt, pausedAt, endedAt, durationSeconds,
        startStatusId, endStatusId, note, isManual,
        \(RecordMetadataSQL.columns)
    FROM todo_time_sessions
    """

    static func mapSession(_ statement: SQLiteStatement) throws -> TodoTimeSession {
        TodoTimeSession(
            id: statement.text(at: 0) ?? UUID().uuidString,
            todoId: statement.text(at: 1) ?? "",
            startedAt: parseDate(statement.text(at: 2)) ?? Date(),
            runningSinceAt: parseDate(statement.text(at: 3)),
            pausedAt: parseDate(statement.text(at: 4)),
            endedAt: parseDate(statement.text(at: 5)),
            durationSeconds: statement.optionalInt(at: 6),
            startStatusId: statement.text(at: 7),
            endStatusId: statement.text(at: 8),
            note: statement.text(at: 9),
            isManual: statement.int(at: 10) == 1,
            meta: try statement.readMetadata(startingAt: 11)
        )
    }

    static func parseDate(_ value: String?) -> Date? {
        SQLitePersistedDate.parse(value)
    }

    static func formatDate(_ value: Date?) -> String? {
        SQLitePersistedDate.format(value)
    }
}
