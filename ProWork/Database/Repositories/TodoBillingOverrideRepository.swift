//  TodoBillingOverrideRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

final class TodoBillingOverrideRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetch(todoId: String) throws -> TodoBillingOverride? {
        let sql = """
        SELECT
            id, todoId, overrideType, unitPriceMinor, fixedFeeMinor, currency, note,
            \(RecordMetadataSQL.columns)
        FROM todo_billing_overrides
        WHERE todoId = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { try Self.makeOverride(from: $0) },
            bind: { $0.bindText(todoId, at: 1) }
        ).first
    }

    /// Loads overrides for multiple todos in a single query and returns a
    /// `todoId → override` dictionary. Used to break N+1 in the billing flow.
    func fetch(todoIds: [String]) throws -> [String: TodoBillingOverride] {
        guard !todoIds.isEmpty else { return [:] }

        var map: [String: TodoBillingOverride] = [:]

        let chunkSize = SQLiteParameterLimit.inClauseChunk
        for chunkStart in stride(from: 0, to: todoIds.count, by: chunkSize) {
            let chunk = Array(todoIds[chunkStart..<min(chunkStart + chunkSize, todoIds.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
            SELECT
                id, todoId, overrideType, unitPriceMinor, fixedFeeMinor, currency, note,
                \(RecordMetadataSQL.columns)
            FROM todo_billing_overrides
            WHERE todoId IN (\(placeholders)) AND deletedAt IS NULL;
            """

            let rows = try database.query(
                sql,
                map: { try Self.makeOverride(from: $0) },
                bind: { statement in
                    for (offset, id) in chunk.enumerated() {
                        statement.bindText(id, at: Int32(offset + 1))
                    }
                }
            )

            for override in rows {
                map[override.todoId] = override
            }
        }

        return map
    }

    func upsert(_ override: TodoBillingOverride) throws {
        // ON CONFLICT(todoId): an existing row for the same todo is
        // updated in place; if that row had been soft-deleted, we
        // resurrect it by clearing `deletedAt`. This is intentional —
        // the override is conceptually a single record per todo, so
        // saving a new override after a delete should look like "edit"
        // rather than "insert a duplicate". Callers wanting an explicit
        // gesture should use the future `restore(todoId:)` API rather
        // than racing the upsert path. The flag clear is documented here
        // because it would otherwise read as a silent revival side-effect.
        let sql = """
        INSERT INTO todo_billing_overrides (
            id, organizationId, todoId, overrideType,
            unitPriceMinor, fixedFeeMinor, currency, note,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(todoId) DO UPDATE SET
            overrideType = excluded.overrideType,
            unitPriceMinor = excluded.unitPriceMinor,
            fixedFeeMinor = excluded.fixedFeeMinor,
            currency = excluded.currency,
            note = excluded.note,
            updatedByUserId = excluded.updatedByUserId,
            updatedAt = excluded.updatedAt,
            rowVersion = todo_billing_overrides.rowVersion + 1,
            syncStatus = 'local',
            deletedAt = NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(override.id, at: 1)
            stmt.bindText(override.organizationId, at: 2)
            stmt.bindText(override.todoId, at: 3)
            stmt.bindText(override.overrideType.rawValue, at: 4)
            stmt.bindOptionalInt(override.unitPriceMinor, at: 5)
            stmt.bindOptionalInt(override.fixedFeeMinor, at: 6)
            stmt.bindText(override.currency, at: 7)
            stmt.bindText(override.note, at: 8)
            stmt.bindText(override.createdByUserId, at: 9)
            stmt.bindText(override.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 10)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: override.createdAt), at: 11)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 12)
            stmt.bindText(override.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 13)
            stmt.bindInt(override.rowVersion, at: 14)
            stmt.bindText(override.syncStatus.rawValue, at: 15)
            stmt.bindText(override.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 16)
            stmt.bindText(override.originDeviceId, at: 17)
        }
    }

    func remove(todoId: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE todo_billing_overrides
        SET deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE todoId = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            let now = DateFormatter.proWorkSQLite.string(from: Date())
            stmt.bindText(now, at: 1)
            stmt.bindText(now, at: 2)
            stmt.bindText(userId, at: 3)
            stmt.bindText(todoId, at: 4)
        }
    }

    private static func makeOverride(from statement: SQLiteStatement) throws -> TodoBillingOverride {
        TodoBillingOverride(
            id: statement.text(at: 0) ?? UUID().uuidString,
            todoId: statement.text(at: 1) ?? "",
            overrideType: TodoBillingOverrideType(rawValue: statement.text(at: 2) ?? "unitPrice") ?? .unitPrice,
            unitPriceMinor: statement.optionalInt(at: 3),
            fixedFeeMinor: statement.optionalInt(at: 4),
            currency: statement.text(at: 5) ?? "TRY",
            note: statement.text(at: 6),
            meta: try statement.readMetadata(startingAt: 7)
        )
    }
}
