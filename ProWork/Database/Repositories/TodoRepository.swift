//  TodoRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

final class TodoRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Read

    func fetchAll() throws -> [TodoListItem] {
        let sql = """
        SELECT
            t.id,

            t.customerId,
            c.name AS customerName,

            t.projectId,
            p.name AS projectName,

            t.folderId,
            wf.name AS folderName,

            t.categoryId,
            tc.name AS categoryName,
            tc.color AS categoryColor,
            tc.isBillableDefault AS categoryIsBillable,

            t.statusId,
            ts.name AS statusName,
            ts.color AS statusColor,
            ts.startsTimer,
            ts.stopsTimer,
            ts.marksOpen,
            ts.marksCompleted,
            ts.marksCancelled,

            t.title,
            t.description,

            t.priority,

            t.plannedDate,
            t.dueDate,
            t.estimatedMinutes,

            COALESCE((
                SELECT SUM(COALESCE(s.durationSeconds, 0))
                FROM todo_time_sessions s
                WHERE s.todoId = t.id
                  AND s.endedAt IS NOT NULL
                  AND s.deletedAt IS NULL
            ), 0) AS totalTrackedSeconds,

            (
                SELECT COALESCE(s.runningSinceAt, s.startedAt)
                FROM todo_time_sessions s
                WHERE s.todoId = t.id
                  AND s.endedAt IS NULL
                  AND s.pausedAt IS NULL
                  AND s.deletedAt IS NULL
                ORDER BY COALESCE(s.runningSinceAt, s.startedAt) DESC
                LIMIT 1
            ) AS activeSessionStartedAt,

            t.isBillable,

            t.createdAt,
            t.updatedAt,
            t.completedAt
        FROM todos t
        LEFT JOIN customers c ON c.id = t.customerId AND c.deletedAt IS NULL
        LEFT JOIN projects p ON p.id = t.projectId AND p.deletedAt IS NULL
        LEFT JOIN work_folders wf ON wf.id = t.folderId AND wf.deletedAt IS NULL
        INNER JOIN task_categories tc ON tc.id = t.categoryId
        INNER JOIN todo_statuses ts ON ts.id = t.statusId
        WHERE t.deletedAt IS NULL
        ORDER BY
            ts.sortOrder ASC,
            t.createdAt DESC;
        """

        return try database.query(sql) { statement in
            TodoRepository.makeListItem(from: statement)
        }
    }

    private static func makeListItem(from statement: SQLiteStatement) -> TodoListItem {
        TodoListItem(
            id: statement.text(at: 0) ?? UUID().uuidString,

            customerId: statement.text(at: 1),
            customerName: statement.text(at: 2),

            projectId: statement.text(at: 3),
            projectName: statement.text(at: 4),

            folderId: statement.text(at: 5),
            folderName: statement.text(at: 6),

            categoryId: statement.text(at: 7) ?? "",
            categoryName: statement.text(at: 8) ?? "",
            categoryColor: statement.text(at: 9),
            categoryIsBillable: statement.int(at: 10) == 1,

            statusId: statement.text(at: 11) ?? BuiltInTodoStatusId.waiting,
            statusName: statement.text(at: 12) ?? ProWorkLocalizer.shared.string(
                "todoStatus.waiting",
                defaultValue: "Beklemede"
            ),
            statusColor: statement.text(at: 13),
            statusStartsTimer: statement.int(at: 14) == 1,
            statusStopsTimer: statement.int(at: 15) == 1,
            statusMarksOpen: statement.int(at: 16) == 1,
            statusMarksCompleted: statement.int(at: 17) == 1,
            statusMarksCancelled: statement.int(at: 18) == 1,

            title: statement.text(at: 19) ?? "",
            description: statement.text(at: 20),

            priority: statement.text(at: 21) ?? "normal",

            plannedDate: parseDate(statement.text(at: 22)),
            dueDate: parseDate(statement.text(at: 23)),
            estimatedMinutes: statement.optionalInt(at: 24),

            totalTrackedSeconds: statement.int(at: 25),
            activeSessionStartedAt: parseDate(statement.text(at: 26)),

            isBillable: statement.int(at: 27) == 1,

            createdAt: parseDate(statement.text(at: 28)) ?? Date(),
            updatedAt: parseDate(statement.text(at: 29)) ?? Date(),
            completedAt: parseDate(statement.text(at: 30))
        )
    }

    /// Returns a single todo as a UI list item (with status & category joins).
    /// Used by working-session flows like `WorkSessionControlService` so they
    /// can SQL-filter by id instead of fetching the entire table.
    func fetchListItem(id: String) throws -> TodoListItem? {
        let sql = """
        SELECT
            t.id,
            t.customerId,
            c.name AS customerName,
            t.projectId,
            p.name AS projectName,
            t.folderId,
            wf.name AS folderName,
            t.categoryId,
            tc.name AS categoryName,
            tc.color AS categoryColor,
            tc.isBillableDefault AS categoryIsBillable,
            t.statusId,
            ts.name AS statusName,
            ts.color AS statusColor,
            ts.startsTimer,
            ts.stopsTimer,
            ts.marksOpen,
            ts.marksCompleted,
            ts.marksCancelled,
            t.title,
            t.description,
            t.priority,
            t.plannedDate,
            t.dueDate,
            t.estimatedMinutes,
            COALESCE((
                SELECT SUM(COALESCE(s.durationSeconds, 0))
                FROM todo_time_sessions s
                WHERE s.todoId = t.id
                  AND s.endedAt IS NOT NULL
                  AND s.deletedAt IS NULL
            ), 0) AS totalTrackedSeconds,
            (
                SELECT COALESCE(s.runningSinceAt, s.startedAt)
                FROM todo_time_sessions s
                WHERE s.todoId = t.id
                  AND s.endedAt IS NULL
                  AND s.pausedAt IS NULL
                  AND s.deletedAt IS NULL
                ORDER BY COALESCE(s.runningSinceAt, s.startedAt) DESC
                LIMIT 1
            ) AS activeSessionStartedAt,
            t.isBillable,
            t.createdAt,
            t.updatedAt,
            t.completedAt
        FROM todos t
        LEFT JOIN customers c ON c.id = t.customerId AND c.deletedAt IS NULL
        LEFT JOIN projects p ON p.id = t.projectId AND p.deletedAt IS NULL
        LEFT JOIN work_folders wf ON wf.id = t.folderId AND wf.deletedAt IS NULL
        INNER JOIN task_categories tc ON tc.id = t.categoryId
        INNER JOIN todo_statuses ts ON ts.id = t.statusId
        WHERE t.id = ? AND t.deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in TodoRepository.makeListItem(from: statement) },
            bind: { statement in statement.bindText(id, at: 1) }
        ).first
    }

    /// Bulk fetch for multiple ids in a single query (reporting / billing).
    /// The id list is split into 500-item chunks (one statement per chunk)
    /// so we stay under SQLite's parameter limit (`SQLITE_MAX_VARIABLE_NUMBER`,
    /// default 999).
    func fetch(ids: [String]) throws -> [Todo] {
        guard !ids.isEmpty else { return [] }

        var results: [Todo] = []
        results.reserveCapacity(ids.count)

        let chunkSize = SQLiteParameterLimit.inClauseChunk
        for chunkStart in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[chunkStart..<min(chunkStart + chunkSize, ids.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
            SELECT
                id, customerId, projectId, folderId, categoryId,
                title, description, statusId, priority,
                plannedDate, dueDate, estimatedMinutes, isBillable, completedAt,
                \(RecordMetadataSQL.columns)
            FROM todos
            WHERE id IN (\(placeholders)) AND deletedAt IS NULL;
            """

            let rows = try database.query(
                sql,
                map: { try TodoRepository.makeTodo(from: $0) },
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

    /// Single todo for editing (with full metadata).
    func fetch(id: String) throws -> Todo? {
        let sql = """
        SELECT
            id, customerId, projectId, folderId, categoryId,
            title, description, statusId, priority,
            plannedDate, dueDate, estimatedMinutes, isBillable, completedAt,
            \(RecordMetadataSQL.columns)
        FROM todos
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in try TodoRepository.makeTodo(from: statement) },
            bind: { statement in statement.bindText(id, at: 1) }
        ).first
    }

    // MARK: - Write

    func insert(_ todo: Todo) throws {
        let sql = """
        INSERT INTO todos (
            id, customerId, projectId, folderId, categoryId,
            title, description, statusId, priority,
            plannedDate, dueDate, estimatedMinutes, isBillable, completedAt,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(todo.id, at: 1)
            statement.bindText(todo.customerId, at: 2)
            statement.bindText(todo.projectId, at: 3)
            statement.bindText(todo.folderId, at: 4)
            statement.bindText(todo.categoryId, at: 5)
            statement.bindText(todo.title, at: 6)
            statement.bindText(todo.description, at: 7)
            statement.bindText(todo.statusId, at: 8)
            statement.bindText(todo.priority, at: 9)
            statement.bindText(Self.formatDate(todo.plannedDate), at: 10)
            statement.bindText(Self.formatDate(todo.dueDate), at: 11)
            statement.bindOptionalInt(todo.estimatedMinutes, at: 12)
            statement.bindInt(todo.isBillable ? 1 : 0, at: 13)
            statement.bindText(Self.formatDate(todo.completedAt), at: 14)
            statement.bindMetadata(todo.meta, startingAt: 15)
        }
    }

    func update(_ todo: Todo) throws {
        let sql = """
        UPDATE todos
        SET
            customerId = ?, projectId = ?, folderId = ?, categoryId = ?, statusId = ?,
            title = ?, description = ?, priority = ?,
            plannedDate = ?, dueDate = ?, estimatedMinutes = ?, isBillable = ?,
            completedAt = ?,
            updatedByUserId = ?,
            updatedAt = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(todo.customerId, at: 1)
            statement.bindText(todo.projectId, at: 2)
            statement.bindText(todo.folderId, at: 3)
            statement.bindText(todo.categoryId, at: 4)
            statement.bindText(todo.statusId, at: 5)
            statement.bindText(todo.title, at: 6)
            statement.bindText(todo.description, at: 7)
            statement.bindText(todo.priority, at: 8)
            statement.bindText(Self.formatDate(todo.plannedDate), at: 9)
            statement.bindText(Self.formatDate(todo.dueDate), at: 10)
            statement.bindOptionalInt(todo.estimatedMinutes, at: 11)
            statement.bindInt(todo.isBillable ? 1 : 0, at: 12)
            statement.bindText(Self.formatDate(todo.completedAt), at: 13)
            statement.bindText(todo.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 14)
            statement.bindText(Self.formatDate(Date()), at: 15)
            statement.bindText(todo.id, at: 16)
        }
    }

    func updateStatus(
        id: String,
        statusId: String,
        completedAt: Date?,
        by userId: String = BuiltInUserId.defaultOwner
    ) throws {
        let sql = """
        UPDATE todos
        SET
            statusId = ?,
            completedAt = ?,
            updatedByUserId = ?,
            updatedAt = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(statusId, at: 1)
            statement.bindText(Self.formatDate(completedAt), at: 2)
            statement.bindText(userId, at: 3)
            statement.bindText(Self.formatDate(Date()), at: 4)
            statement.bindText(id, at: 5)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        // delegate to the central helper.
        try database.softDelete(table: "todos", id: id, by: userId)
    }

    // MARK: - Mapping

    private static func makeTodo(from statement: SQLiteStatement) throws -> Todo {
        Todo(
            id: statement.text(at: 0) ?? UUID().uuidString,
            customerId: statement.text(at: 1),
            projectId: statement.text(at: 2),
            folderId: statement.text(at: 3),
            categoryId: statement.text(at: 4) ?? "",
            title: statement.text(at: 5) ?? "",
            description: statement.text(at: 6),
            statusId: statement.text(at: 7) ?? BuiltInTodoStatusId.waiting,
            priority: statement.text(at: 8) ?? "normal",
            plannedDate: parseDate(statement.text(at: 9)),
            dueDate: parseDate(statement.text(at: 10)),
            estimatedMinutes: statement.optionalInt(at: 11),
            isBillable: statement.int(at: 12) == 1,
            completedAt: parseDate(statement.text(at: 13)),
            meta: try statement.readMetadata(startingAt: 14)
        )
    }
}

private extension TodoRepository {
    static func parseDate(_ value: String?) -> Date? {
        SQLitePersistedDate.parse(value)
    }

    static func formatDate(_ value: Date?) -> String? {
        SQLitePersistedDate.format(value)
    }
}
