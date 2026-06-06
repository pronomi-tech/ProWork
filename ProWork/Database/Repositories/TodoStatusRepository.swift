//  TodoStatusRepository.swift
//  ProWork
//  Created by Pronomi.
import Foundation
import SQLite3

final class TodoStatusRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll() throws -> [TodoStatus] {
        let sql = """
        SELECT
            id, systemKey, name, color, sortOrder,
            isSystem, isActive, showInBoard,
            startsTimer, stopsTimer, marksOpen, marksCompleted, marksCancelled,
            \(RecordMetadataSQL.columns)
        FROM todo_statuses
        WHERE deletedAt IS NULL
        ORDER BY sortOrder ASC, name COLLATE NOCASE ASC;
        """

        return try database.query(sql) { statement in
            try Self.makeStatus(from: statement)
        }
    }

    func fetch(id: String) throws -> TodoStatus? {
        let sql = """
        SELECT
            id, systemKey, name, color, sortOrder,
            isSystem, isActive, showInBoard,
            startsTimer, stopsTimer, marksOpen, marksCompleted, marksCancelled,
            \(RecordMetadataSQL.columns)
        FROM todo_statuses
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in try Self.makeStatus(from: statement) },
            bind: { statement in statement.bindText(id, at: 1) }
        ).first
    }

    func insert(_ status: TodoStatus) throws {
        let sql = """
        INSERT INTO todo_statuses (
            id, systemKey, name, color, sortOrder,
            isSystem, isActive, showInBoard,
            startsTimer, stopsTimer, marksOpen, marksCompleted, marksCancelled,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(status.id, at: 1)
            statement.bindText(status.systemKey, at: 2)
            statement.bindText(status.name, at: 3)
            statement.bindText(status.color, at: 4)
            statement.bindInt(status.sortOrder, at: 5)
            statement.bindInt(status.isSystem ? 1 : 0, at: 6)
            statement.bindInt(status.isActive ? 1 : 0, at: 7)
            statement.bindInt(status.showInBoard ? 1 : 0, at: 8)
            statement.bindInt(status.startsTimer ? 1 : 0, at: 9)
            statement.bindInt(status.stopsTimer ? 1 : 0, at: 10)
            statement.bindInt(status.marksOpen ? 1 : 0, at: 11)
            statement.bindInt(status.marksCompleted ? 1 : 0, at: 12)
            statement.bindInt(status.marksCancelled ? 1 : 0, at: 13)
            statement.bindMetadata(status.meta, startingAt: 14)
        }
    }

    func update(_ status: TodoStatus) throws {
        let sql = """
        UPDATE todo_statuses
        SET
            name = ?, color = ?, sortOrder = ?, isActive = ?, showInBoard = ?,
            startsTimer = ?, stopsTimer = ?, marksOpen = ?,
            marksCompleted = ?, marksCancelled = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(status.name, at: 1)
            statement.bindText(status.color, at: 2)
            statement.bindInt(status.sortOrder, at: 3)
            statement.bindInt(status.isActive ? 1 : 0, at: 4)
            statement.bindInt(status.showInBoard ? 1 : 0, at: 5)
            statement.bindInt(status.startsTimer ? 1 : 0, at: 6)
            statement.bindInt(status.stopsTimer ? 1 : 0, at: 7)
            statement.bindInt(status.marksOpen ? 1 : 0, at: 8)
            statement.bindInt(status.marksCompleted ? 1 : 0, at: 9)
            statement.bindInt(status.marksCancelled ? 1 : 0, at: 10)
            statement.bindText(status.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 11)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 12)
            statement.bindText(status.id, at: 13)
        }
    }

    /// Hard delete — test fixtures only. See CustomerRepository._hardDelete.
    func _hardDelete(id: String) throws {
        let sql = """
        DELETE FROM todo_statuses
        WHERE id = ?
          AND isSystem = 0;
        """

        try database.execute(sql) { statement in
            statement.bindText(id, at: 1)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        let sql = """
        UPDATE todo_statuses
        SET
            deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND isSystem = 0 AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            let now = DateFormatter.proWorkSQLite.string(from: Date())
            statement.bindText(now, at: 1)
            statement.bindText(now, at: 2)
            statement.bindText(userId, at: 3)
            statement.bindText(id, at: 4)
        }
    }

    private static func makeStatus(from statement: SQLiteStatement) throws -> TodoStatus {
        TodoStatus(
            id: statement.text(at: 0) ?? UUID().uuidString,
            systemKey: statement.text(at: 1),
            name: statement.text(at: 2) ?? "",
            color: statement.text(at: 3),
            sortOrder: statement.int(at: 4),
            isSystem: statement.int(at: 5) == 1,
            isActive: statement.int(at: 6) == 1,
            showInBoard: statement.int(at: 7) == 1,
            startsTimer: statement.int(at: 8) == 1,
            stopsTimer: statement.int(at: 9) == 1,
            marksOpen: statement.int(at: 10) == 1,
            marksCompleted: statement.int(at: 11) == 1,
            marksCancelled: statement.int(at: 12) == 1,
            meta: try statement.readMetadata(startingAt: 13)
        )
    }
}
