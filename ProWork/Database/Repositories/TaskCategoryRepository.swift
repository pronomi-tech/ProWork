//  TaskCategoryRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

final class TaskCategoryRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll() throws -> [TaskCategory] {
        let sql = """
        SELECT
            id, name, color, isBillableDefault, sortOrder, isSystem, vatRateId,
            \(RecordMetadataSQL.columns)
        FROM task_categories
        WHERE deletedAt IS NULL
        ORDER BY sortOrder ASC, name COLLATE NOCASE ASC;
        """

        return try database.query(sql) { statement in
            try Self.makeCategory(from: statement)
        }
    }

    func fetch(id: String) throws -> TaskCategory? {
        let sql = """
        SELECT
            id, name, color, isBillableDefault, sortOrder, isSystem, vatRateId,
            \(RecordMetadataSQL.columns)
        FROM task_categories
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in try Self.makeCategory(from: statement) },
            bind: { statement in statement.bindText(id, at: 1) }
        ).first
    }

    func insert(_ category: TaskCategory) throws {
        let sql = """
        INSERT INTO task_categories (
            id, name, color, isBillableDefault, sortOrder, isSystem, vatRateId,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(category.id, at: 1)
            statement.bindText(category.name, at: 2)
            statement.bindText(category.color, at: 3)
            statement.bindInt(category.isBillableDefault ? 1 : 0, at: 4)
            statement.bindInt(category.sortOrder, at: 5)
            statement.bindInt(category.isSystem ? 1 : 0, at: 6)
            statement.bindText(category.vatRateId, at: 7)
            statement.bindMetadata(category.meta, startingAt: 8)
        }
    }

    func update(_ category: TaskCategory) throws {
        let sql = """
        UPDATE task_categories
        SET
            name = ?, color = ?, isBillableDefault = ?, sortOrder = ?,
            vatRateId = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(category.name, at: 1)
            statement.bindText(category.color, at: 2)
            statement.bindInt(category.isBillableDefault ? 1 : 0, at: 3)
            statement.bindInt(category.sortOrder, at: 4)
            statement.bindText(category.vatRateId, at: 5)
            statement.bindText(category.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 6)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 7)
            statement.bindText(category.id, at: 8)
        }
    }

    /// Hard delete — test fixtures only. See CustomerRepository._hardDelete.
    func _hardDelete(id: String) throws {
        let sql = """
        DELETE FROM task_categories
        WHERE id = ?
          AND isSystem = 0;
        """

        try database.execute(sql) { statement in
            statement.bindText(id, at: 1)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        let sql = """
        UPDATE task_categories
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

    private static func makeCategory(from statement: SQLiteStatement) throws -> TaskCategory {
        TaskCategory(
            id: statement.text(at: 0) ?? UUID().uuidString,
            name: statement.text(at: 1) ?? "",
            color: statement.text(at: 2),
            isBillableDefault: statement.int(at: 3) == 1,
            sortOrder: statement.int(at: 4),
            isSystem: statement.int(at: 5) == 1,
            vatRateId: statement.text(at: 6),
            meta: try statement.readMetadata(startingAt: 7)
        )
    }
}
