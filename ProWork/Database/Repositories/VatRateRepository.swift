//
//  VatRateRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class VatRateRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Read

    func fetchAll(organizationId: String = BuiltInOrganizationId.default) throws -> [VatRate] {
        let sql = """
        SELECT
            id, name, rate, isDefault, isExempt, isActive, note,
            \(RecordMetadataSQL.columns)
        FROM vat_rates
        WHERE organizationId = ? AND deletedAt IS NULL
        ORDER BY isDefault DESC, isExempt ASC, name COLLATE NOCASE ASC;
        """

        return try database.query(
            sql,
            map: { Self.makeRate(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    func fetch(id: String) throws -> VatRate? {
        let sql = """
        SELECT
            id, name, rate, isDefault, isExempt, isActive, note,
            \(RecordMetadataSQL.columns)
        FROM vat_rates
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { Self.makeRate(from: $0) },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    func fetchDefault(organizationId: String = BuiltInOrganizationId.default) throws -> VatRate? {
        let sql = """
        SELECT
            id, name, rate, isDefault, isExempt, isActive, note,
            \(RecordMetadataSQL.columns)
        FROM vat_rates
        WHERE organizationId = ? AND isDefault = 1 AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { Self.makeRate(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        ).first
    }

    // MARK: - Write

    func insert(_ rate: VatRate) throws {
        try database.execute("BEGIN TRANSACTION;")
        do {
            if rate.isDefault {
                try clearOtherDefaults(except: rate.id, organizationId: rate.organizationId)
            }

            let sql = """
            INSERT INTO vat_rates (
                id, name, rate, isDefault, isExempt, isActive, note,
                \(RecordMetadataSQL.columns)
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
            """

            try database.execute(sql) { stmt in
                stmt.bindText(rate.id, at: 1)
                stmt.bindText(rate.name, at: 2)
                stmt.bindText(NSDecimalNumber(decimal: rate.rate).stringValue, at: 3)
                stmt.bindInt(rate.isDefault ? 1 : 0, at: 4)
                stmt.bindInt(rate.isExempt ? 1 : 0, at: 5)
                stmt.bindInt(rate.isActive ? 1 : 0, at: 6)
                stmt.bindText(rate.note, at: 7)
                stmt.bindMetadata(rate.meta, startingAt: 8)
            }

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    func update(_ rate: VatRate) throws {
        try database.execute("BEGIN TRANSACTION;")
        do {
            if rate.isDefault {
                try clearOtherDefaults(except: rate.id, organizationId: rate.organizationId)
            }

            let sql = """
            UPDATE vat_rates
            SET name = ?, rate = ?, isDefault = ?, isExempt = ?, isActive = ?, note = ?,
                updatedByUserId = ?, updatedAt = ?,
                rowVersion = rowVersion + 1, syncStatus = 'local'
            WHERE id = ? AND deletedAt IS NULL;
            """

            try database.execute(sql) { stmt in
                stmt.bindText(rate.name, at: 1)
                stmt.bindText(NSDecimalNumber(decimal: rate.rate).stringValue, at: 2)
                stmt.bindInt(rate.isDefault ? 1 : 0, at: 3)
                stmt.bindInt(rate.isExempt ? 1 : 0, at: 4)
                stmt.bindInt(rate.isActive ? 1 : 0, at: 5)
                stmt.bindText(rate.note, at: 6)
                stmt.bindText(rate.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 7)
                stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 8)
                stmt.bindText(rate.id, at: 9)
            }

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    /// Soft delete + atamaları temizle.
    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        try database.execute("BEGIN TRANSACTION;")
        do {
            let now = DateFormatter.proWorkSQLite.string(from: Date())

            try database.execute("""
            UPDATE vat_rates
            SET deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
                isDefault = 0,
                rowVersion = rowVersion + 1, syncStatus = 'local'
            WHERE id = ? AND deletedAt IS NULL;
            """) { stmt in
                stmt.bindText(now, at: 1)
                stmt.bindText(now, at: 2)
                stmt.bindText(userId, at: 3)
                stmt.bindText(id, at: 4)
            }

            try database.execute("UPDATE customers SET vatRateId = NULL WHERE vatRateId = ?;") { stmt in
                stmt.bindText(id, at: 1)
            }
            try database.execute("UPDATE projects SET vatRateId = NULL WHERE vatRateId = ?;") { stmt in
                stmt.bindText(id, at: 1)
            }
            try database.execute("UPDATE task_categories SET vatRateId = NULL WHERE vatRateId = ?;") { stmt in
                stmt.bindText(id, at: 1)
            }

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    private func clearOtherDefaults(except keepId: String, organizationId: String) throws {
        try database.execute("""
        UPDATE vat_rates
        SET isDefault = 0, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE organizationId = ? AND id != ? AND isDefault = 1 AND deletedAt IS NULL;
        """) { stmt in
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 1)
            stmt.bindText(organizationId, at: 2)
            stmt.bindText(keepId, at: 3)
        }
    }

    private static func makeRate(from statement: SQLiteStatement) -> VatRate {
        let rateString = statement.text(at: 2) ?? "0"
        return VatRate(
            id: statement.text(at: 0) ?? UUID().uuidString,
            name: statement.text(at: 1) ?? "",
            rate: Decimal(string: rateString) ?? 0,
            isDefault: statement.int(at: 3) == 1,
            isExempt: statement.int(at: 4) == 1,
            isActive: statement.int(at: 5) == 1,
            note: statement.text(at: 6),
            meta: statement.readMetadata(startingAt: 7)
        )
    }
}
