//
//  TodoRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

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

            t.categoryId,
            tc.name AS categoryName,
            tc.color AS categoryColor,

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

            categoryId: statement.text(at: 5) ?? "",
            categoryName: statement.text(at: 6) ?? "",
            categoryColor: statement.text(at: 7),

            statusId: statement.text(at: 8) ?? BuiltInTodoStatusId.waiting,
            statusName: statement.text(at: 9) ?? "Beklemede",
            statusColor: statement.text(at: 10),
            statusStartsTimer: statement.int(at: 11) == 1,
            statusStopsTimer: statement.int(at: 12) == 1,
            statusMarksOpen: statement.int(at: 13) == 1,
            statusMarksCompleted: statement.int(at: 14) == 1,
            statusMarksCancelled: statement.int(at: 15) == 1,

            title: statement.text(at: 16) ?? "",
            description: statement.text(at: 17),

            priority: statement.text(at: 18) ?? "normal",

            plannedDate: parseDate(statement.text(at: 19)),
            dueDate: parseDate(statement.text(at: 20)),
            estimatedMinutes: statement.optionalInt(at: 21),

            totalTrackedSeconds: statement.int(at: 22),
            activeSessionStartedAt: parseDate(statement.text(at: 23)),

            isBillable: statement.int(at: 24) == 1,

            createdAt: parseDate(statement.text(at: 25)) ?? Date(),
            updatedAt: parseDate(statement.text(at: 26)) ?? Date(),
            completedAt: parseDate(statement.text(at: 27))
        )
    }

    /// Tek bir todo'yu UI list item şeklinde döner (status & kategori join'leri dahil).
    /// `WorkSessionControlService` gibi çalışma akışlarında tüm tabloyu çekmek yerine
    /// id'ye göre SQL filtrelemesi için kullanılır.
    func fetchListItem(id: String) throws -> TodoListItem? {
        let sql = """
        SELECT
            t.id,
            t.customerId,
            c.name AS customerName,
            t.projectId,
            p.name AS projectName,
            t.categoryId,
            tc.name AS categoryName,
            tc.color AS categoryColor,
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

    /// Birden çok id için tek sorguda toplu fetch (raporlama / faturalandırma için).
    /// SQLite parametre limitini (`SQLITE_MAX_VARIABLE_NUMBER`, varsayılan 999) aşmamak
    /// için id listesi 500'lük parçalara bölünüp her parça ayrı statement'ta çalıştırılır.
    func fetch(ids: [String]) throws -> [Todo] {
        guard !ids.isEmpty else { return [] }

        var results: [Todo] = []
        results.reserveCapacity(ids.count)

        let chunkSize = 500
        for chunkStart in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[chunkStart..<min(chunkStart + chunkSize, ids.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
            SELECT
                id, customerId, projectId, categoryId,
                title, description, statusId, priority,
                plannedDate, dueDate, estimatedMinutes, isBillable, completedAt,
                \(RecordMetadataSQL.columns)
            FROM todos
            WHERE id IN (\(placeholders)) AND deletedAt IS NULL;
            """

            let rows = try database.query(
                sql,
                map: { TodoRepository.makeTodo(from: $0) },
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

    /// Düzenleme için tek todo (tüm metadata ile).
    func fetch(id: String) throws -> Todo? {
        let sql = """
        SELECT
            id, customerId, projectId, categoryId,
            title, description, statusId, priority,
            plannedDate, dueDate, estimatedMinutes, isBillable, completedAt,
            \(RecordMetadataSQL.columns)
        FROM todos
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in TodoRepository.makeTodo(from: statement) },
            bind: { statement in statement.bindText(id, at: 1) }
        ).first
    }

    // MARK: - Write

    func insert(_ todo: Todo) throws {
        let sql = """
        INSERT INTO todos (
            id, customerId, projectId, categoryId,
            title, description, statusId, priority,
            plannedDate, dueDate, estimatedMinutes, isBillable, completedAt,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(todo.id, at: 1)
            statement.bindText(todo.customerId, at: 2)
            statement.bindText(todo.projectId, at: 3)
            statement.bindText(todo.categoryId, at: 4)
            statement.bindText(todo.title, at: 5)
            statement.bindText(todo.description, at: 6)
            statement.bindText(todo.statusId, at: 7)
            statement.bindText(todo.priority, at: 8)
            statement.bindText(Self.formatDate(todo.plannedDate), at: 9)
            statement.bindText(Self.formatDate(todo.dueDate), at: 10)
            statement.bindOptionalInt(todo.estimatedMinutes, at: 11)
            statement.bindInt(todo.isBillable ? 1 : 0, at: 12)
            statement.bindText(Self.formatDate(todo.completedAt), at: 13)
            statement.bindMetadata(todo.meta, startingAt: 14)
        }
    }

    func update(_ todo: Todo) throws {
        let sql = """
        UPDATE todos
        SET
            customerId = ?, projectId = ?, categoryId = ?, statusId = ?,
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
            statement.bindText(todo.categoryId, at: 3)
            statement.bindText(todo.statusId, at: 4)
            statement.bindText(todo.title, at: 5)
            statement.bindText(todo.description, at: 6)
            statement.bindText(todo.priority, at: 7)
            statement.bindText(Self.formatDate(todo.plannedDate), at: 8)
            statement.bindText(Self.formatDate(todo.dueDate), at: 9)
            statement.bindOptionalInt(todo.estimatedMinutes, at: 10)
            statement.bindInt(todo.isBillable ? 1 : 0, at: 11)
            statement.bindText(Self.formatDate(todo.completedAt), at: 12)
            statement.bindText(todo.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 13)
            statement.bindText(Self.formatDate(Date()), at: 14)
            statement.bindText(todo.id, at: 15)
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

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE todos
        SET
            deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            let now = Self.formatDate(Date()) ?? ""
            statement.bindText(now, at: 1)
            statement.bindText(now, at: 2)
            statement.bindText(userId, at: 3)
            statement.bindText(id, at: 4)
        }
    }

    // MARK: - Mapping

    private static func makeTodo(from statement: SQLiteStatement) -> Todo {
        Todo(
            id: statement.text(at: 0) ?? UUID().uuidString,
            customerId: statement.text(at: 1),
            projectId: statement.text(at: 2),
            categoryId: statement.text(at: 3) ?? "",
            title: statement.text(at: 4) ?? "",
            description: statement.text(at: 5),
            statusId: statement.text(at: 6) ?? BuiltInTodoStatusId.waiting,
            priority: statement.text(at: 7) ?? "normal",
            plannedDate: parseDate(statement.text(at: 8)),
            dueDate: parseDate(statement.text(at: 9)),
            estimatedMinutes: statement.optionalInt(at: 10),
            isBillable: statement.int(at: 11) == 1,
            completedAt: parseDate(statement.text(at: 12)),
            meta: statement.readMetadata(startingAt: 13)
        )
    }
}

private extension TodoRepository {
    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return DateFormatter.proWorkSQLite.date(from: value)
    }

    static func formatDate(_ value: Date?) -> String? {
        guard let value else {
            return nil
        }
        return DateFormatter.proWorkSQLite.string(from: value)
    }
}
