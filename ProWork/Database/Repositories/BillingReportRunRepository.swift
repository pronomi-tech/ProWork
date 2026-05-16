//
//  BillingReportRunRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class BillingReportRunRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(organizationId: String) throws -> [BillingReportRun] {
        let sql = """
        \(Self.selectSQL)
        WHERE organizationId = ? AND deletedAt IS NULL
        ORDER BY periodStart DESC, createdAt DESC;
        """

        return try database.query(
            sql,
            map: { Self.makeRun(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    func fetchAllForCustomer(organizationId: String, customerId: String) throws -> [BillingReportRun] {
        let sql = """
        \(Self.selectSQL)
        WHERE organizationId = ? AND customerId = ? AND deletedAt IS NULL
        ORDER BY periodStart DESC;
        """

        return try database.query(
            sql,
            map: { Self.makeRun(from: $0) },
            bind: { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(customerId, at: 2)
            }
        )
    }

    func fetch(id: String) throws -> BillingReportRun? {
        let sql = """
        \(Self.selectSQL)
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { Self.makeRun(from: $0) },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    func fetchUnpaid(organizationId: String) throws -> [BillingReportRun] {
        let sql = """
        \(Self.selectSQL)
        WHERE organizationId = ? AND status = 'final' AND deletedAt IS NULL
          AND paymentStatus IN ('unpaid','partial','overdue')
        ORDER BY dueDate ASC;
        """

        return try database.query(
            sql,
            map: { Self.makeRun(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    func insert(_ run: BillingReportRun) throws {
        let sql = """
        INSERT INTO billing_report_runs (
            id, organizationId, customerId, periodStart, periodEnd, status,
            title, invoiceNumber, documentNumber, currency,
            subtotalMinor, vatMinor, totalMinor, paidMinor, balanceMinor,
            paymentStatus, dueDate, snapshotJson, notes,
            finalizedAt, finalizedByUserId,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql) { stmt in
            stmt.bindText(run.id, at: 1)
            stmt.bindText(run.organizationId, at: 2)
            stmt.bindText(run.customerId, at: 3)
            stmt.bindText(run.periodStart, at: 4)
            stmt.bindText(run.periodEnd, at: 5)
            stmt.bindText(run.status.rawValue, at: 6)
            stmt.bindText(run.title, at: 7)
            stmt.bindText(run.invoiceNumber, at: 8)
            stmt.bindText(run.documentNumber, at: 9)
            stmt.bindText(run.currency, at: 10)
            stmt.bindInt(run.subtotalMinor, at: 11)
            stmt.bindInt(run.vatMinor, at: 12)
            stmt.bindInt(run.totalMinor, at: 13)
            stmt.bindInt(run.paidMinor, at: 14)
            stmt.bindInt(run.balanceMinor, at: 15)
            stmt.bindText(run.paymentStatus.rawValue, at: 16)
            stmt.bindText(run.dueDate, at: 17)
            stmt.bindText(run.snapshotJson, at: 18)
            stmt.bindText(run.notes, at: 19)
            stmt.bindText(run.finalizedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 20)
            stmt.bindText(run.finalizedByUserId, at: 21)
            stmt.bindText(run.createdByUserId, at: 22)
            stmt.bindText(run.updatedByUserId, at: 23)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: run.createdAt), at: 24)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: run.updatedAt), at: 25)
            stmt.bindText(run.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 26)
            stmt.bindInt(run.rowVersion, at: 27)
            stmt.bindText(run.syncStatus.rawValue, at: 28)
            stmt.bindText(run.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 29)
            stmt.bindText(run.originDeviceId, at: 30)
        }
    }

    func update(_ run: BillingReportRun) throws {
        let sql = """
        UPDATE billing_report_runs
        SET periodStart = ?, periodEnd = ?, status = ?,
            title = ?, invoiceNumber = ?, documentNumber = ?, currency = ?,
            subtotalMinor = ?, vatMinor = ?, totalMinor = ?,
            paidMinor = ?, balanceMinor = ?,
            paymentStatus = ?, dueDate = ?, snapshotJson = ?, notes = ?,
            finalizedAt = ?, finalizedByUserId = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(run.periodStart, at: 1)
            stmt.bindText(run.periodEnd, at: 2)
            stmt.bindText(run.status.rawValue, at: 3)
            stmt.bindText(run.title, at: 4)
            stmt.bindText(run.invoiceNumber, at: 5)
            stmt.bindText(run.documentNumber, at: 6)
            stmt.bindText(run.currency, at: 7)
            stmt.bindInt(run.subtotalMinor, at: 8)
            stmt.bindInt(run.vatMinor, at: 9)
            stmt.bindInt(run.totalMinor, at: 10)
            stmt.bindInt(run.paidMinor, at: 11)
            stmt.bindInt(run.balanceMinor, at: 12)
            stmt.bindText(run.paymentStatus.rawValue, at: 13)
            stmt.bindText(run.dueDate, at: 14)
            stmt.bindText(run.snapshotJson, at: 15)
            stmt.bindText(run.notes, at: 16)
            stmt.bindText(run.finalizedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 17)
            stmt.bindText(run.finalizedByUserId, at: 18)
            stmt.bindText(run.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 19)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 20)
            stmt.bindText(run.id, at: 21)
        }
    }

    /// Tahsilatlar değiştiğinde paidMinor/balanceMinor/paymentStatus'ı senkronize eder.
    func recalculatePayments(runId: String) throws {
        let sql = """
        UPDATE billing_report_runs
        SET
            paidMinor = COALESCE((
                SELECT SUM(amountMinor)
                FROM payments
                WHERE runId = billing_report_runs.id AND deletedAt IS NULL
            ), 0),
            balanceMinor = totalMinor - COALESCE((
                SELECT SUM(amountMinor)
                FROM payments
                WHERE runId = billing_report_runs.id AND deletedAt IS NULL
            ), 0),
            paymentStatus = CASE
                WHEN totalMinor <= COALESCE((
                    SELECT SUM(amountMinor)
                    FROM payments
                    WHERE runId = billing_report_runs.id AND deletedAt IS NULL
                ), 0) THEN 'paid'
                WHEN COALESCE((
                    SELECT SUM(amountMinor)
                    FROM payments
                    WHERE runId = billing_report_runs.id AND deletedAt IS NULL
                ), 0) > 0 THEN 'partial'
                WHEN dueDate IS NOT NULL AND date(dueDate) < date('now') THEN 'overdue'
                ELSE 'unpaid'
            END,
            updatedAt = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 1)
            stmt.bindText(runId, at: 2)
        }
    }

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE billing_report_runs
        SET deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            let now = DateFormatter.proWorkSQLite.string(from: Date())
            stmt.bindText(now, at: 1)
            stmt.bindText(now, at: 2)
            stmt.bindText(userId, at: 3)
            stmt.bindText(id, at: 4)
        }
    }

    // MARK: - Helpers

    private static let selectSQL = """
    SELECT
        id, customerId, periodStart, periodEnd, status,
        title, invoiceNumber, documentNumber, currency,
        subtotalMinor, vatMinor, totalMinor, paidMinor, balanceMinor,
        paymentStatus, dueDate, snapshotJson, notes,
        finalizedAt, finalizedByUserId,
        organizationId, createdByUserId, updatedByUserId,
        createdAt, updatedAt, deletedAt, rowVersion,
        syncStatus, lastSyncedAt, originDeviceId
    FROM billing_report_runs
    """

    private static func makeRun(from statement: SQLiteStatement) -> BillingReportRun {
        // 0..19 iş alanları, 20..29 metadata
        BillingReportRun(
            id: statement.text(at: 0) ?? UUID().uuidString,
            customerId: statement.text(at: 1) ?? "",
            periodStart: statement.text(at: 2) ?? "",
            periodEnd: statement.text(at: 3) ?? "",
            status: BillingRunStatus(rawValue: statement.text(at: 4) ?? "draft") ?? .draft,
            title: statement.text(at: 5),
            invoiceNumber: statement.text(at: 6),
            documentNumber: statement.text(at: 7),
            currency: statement.text(at: 8) ?? "TRY",
            subtotalMinor: statement.int(at: 9),
            vatMinor: statement.int(at: 10),
            totalMinor: statement.int(at: 11),
            paidMinor: statement.int(at: 12),
            balanceMinor: statement.int(at: 13),
            paymentStatus: PaymentStatus(rawValue: statement.text(at: 14) ?? "unpaid") ?? .unpaid,
            dueDate: statement.text(at: 15),
            snapshotJson: statement.text(at: 16),
            notes: statement.text(at: 17),
            finalizedAt: statement.text(at: 18).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            finalizedByUserId: statement.text(at: 19),
            organizationId: statement.text(at: 20) ?? BuiltInOrganizationId.default,
            createdByUserId: statement.text(at: 21),
            updatedByUserId: statement.text(at: 22),
            createdAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 23) ?? "") ?? Date(),
            updatedAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 24) ?? "") ?? Date(),
            deletedAt: statement.text(at: 25).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            rowVersion: statement.int(at: 26),
            syncStatus: SyncStatus(rawValue: statement.text(at: 27) ?? "") ?? .local,
            lastSyncedAt: statement.text(at: 28).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            originDeviceId: statement.text(at: 29)
        )
    }
}
