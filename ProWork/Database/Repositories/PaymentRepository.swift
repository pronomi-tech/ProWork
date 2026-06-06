//  PaymentRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

final class PaymentRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(runId: String) throws -> [Payment] {
        let sql = """
        SELECT
            id, runId, paidAt, amountMinor, currency, method, reference, note,
            \(RecordMetadataSQL.columns)
        FROM payments
        WHERE runId = ? AND deletedAt IS NULL
        ORDER BY paidAt DESC;
        """

        return try database.query(
            sql,
            map: { try Self.makePayment(from: $0) },
            bind: { $0.bindText(runId, at: 1) }
        )
    }

    func fetchAllForOrganization(_ organizationId: String) throws -> [Payment] {
        let sql = """
        SELECT
            id, runId, paidAt, amountMinor, currency, method, reference, note,
            \(RecordMetadataSQL.columns)
        FROM payments
        WHERE organizationId = ? AND deletedAt IS NULL
        ORDER BY paidAt DESC;
        """

        return try database.query(
            sql,
            map: { try Self.makePayment(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    func insert(_ payment: Payment) throws {
        let sql = """
        INSERT INTO payments (
            id, organizationId, runId, paidAt, amountMinor, currency,
            method, reference, note,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql) { stmt in
            stmt.bindText(payment.id, at: 1)
            stmt.bindText(payment.organizationId, at: 2)
            stmt.bindText(payment.runId, at: 3)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: payment.paidAt), at: 4)
            stmt.bindInt(payment.amountMinor, at: 5)
            stmt.bindText(payment.currency, at: 6)
            stmt.bindText(payment.method.rawValue, at: 7)
            stmt.bindText(payment.reference, at: 8)
            stmt.bindText(payment.note, at: 9)
            stmt.bindText(payment.createdByUserId, at: 10)
            stmt.bindText(payment.updatedByUserId, at: 11)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: payment.createdAt), at: 12)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: payment.updatedAt), at: 13)
            stmt.bindText(payment.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 14)
            stmt.bindInt(payment.rowVersion, at: 15)
            stmt.bindText(payment.syncStatus.rawValue, at: 16)
            stmt.bindText(payment.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 17)
            stmt.bindText(payment.originDeviceId, at: 18)
        }
    }

    func update(_ payment: Payment) throws {
        let sql = """
        UPDATE payments
        SET paidAt = ?, amountMinor = ?, currency = ?,
            method = ?, reference = ?, note = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: payment.paidAt), at: 1)
            stmt.bindInt(payment.amountMinor, at: 2)
            stmt.bindText(payment.currency, at: 3)
            stmt.bindText(payment.method.rawValue, at: 4)
            stmt.bindText(payment.reference, at: 5)
            stmt.bindText(payment.note, at: 6)
            stmt.bindText(payment.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 7)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 8)
            stmt.bindText(payment.id, at: 9)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        // delegate to the central helper.
        try database.softDelete(table: "payments", id: id, by: userId)
    }

    private static func makePayment(from statement: SQLiteStatement) throws -> Payment {
        Payment(
            id: statement.text(at: 0) ?? UUID().uuidString,
            runId: statement.text(at: 1) ?? "",
            paidAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 2) ?? "") ?? Date(),
            amountMinor: statement.int(at: 3),
            currency: statement.text(at: 4) ?? "TRY",
            method: PaymentMethod(rawValue: statement.text(at: 5) ?? "bank_transfer") ?? .bankTransfer,
            reference: statement.text(at: 6),
            note: statement.text(at: 7),
            meta: try statement.readMetadata(startingAt: 8)
        )
    }
}
