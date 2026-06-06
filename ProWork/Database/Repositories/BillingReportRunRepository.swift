//  BillingReportRunRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

final class BillingReportRunRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Lifecycle service needs to wrap multi-statement
    /// flows (e.g. createDrafts inserting N per-currency runs) atomically.
    /// Re-exposing the underlying write transaction here keeps callers from
    /// needing direct AppDatabase access.
    func inWriteTransaction<T>(_ block: () throws -> T) throws -> T {
        try database.inWriteTransaction(block)
    }

    func fetchAll(organizationId: String) throws -> [BillingReportRun] {
        let sql = """
        \(Self.selectSQL)
        WHERE organizationId = ? AND deletedAt IS NULL
        ORDER BY periodStart DESC, createdAt DESC;
        """

        return try database.query(
            sql,
            map: { try Self.makeRun(from: $0) },
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
            map: { try Self.makeRun(from: $0) },
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
            map: { try Self.makeRun(from: $0) },
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
            map: { try Self.makeRun(from: $0) },
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

    /// Syncs paidMinor/balanceMinor/paymentStatus when payments change.
    ///   * In the old version the same `SUM(amountMinor)` subquery was
    ///     repeated in each of the 4 CASE branches. Now the payment total
    ///     is read once from the `payments` table and passed as a
    ///     parameter to the UPDATE.
    ///     olarak bind ediliyor — kod sade, plan deterministik.
    ///   * The overdue check was using `date(dueDate) < date('now')`.
    ///     `dueDate` is stored in "YYYY-MM-DD" format; when `date()`
    ///     can't parse the format it returns NULL and the overdue state
    ///     never triggered. Also, `date('now')` is UTC-based, which
    ///     can shift by a day around midnight in the Türkiye TZ. We now
    ///     produce today's Istanbul date on the Swift side and feed it
    ///     into the comparison.
    ///     parametre olarak veriyoruz; YYYY-MM-DD lexikografik olarak
    ///     comparable lexicographically.
    func recalculatePayments(runId: String) throws {
        let paidMinor = try fetchPaidMinor(runId: runId)
        let todayDayString = Self.istanbulDayFormatter.string(from: Date())
        let updatedAtString = DateFormatter.proWorkSQLite.string(from: Date())

        // Reuse `?1` four times instead of binding `paidMinor` to four
        // distinct positions — drift-proof if the SQL gains/loses one
        // of the references.
        let sql = """
        UPDATE billing_report_runs
        SET
            paidMinor = ?1,
            balanceMinor = totalMinor - ?1,
            paymentStatus = CASE
                WHEN totalMinor <= ?1 THEN 'paid'
                WHEN ?1 > 0 THEN 'partial'
                WHEN dueDate IS NOT NULL AND dueDate < ?2 THEN 'overdue'
                ELSE 'unpaid'
            END,
            updatedAt = ?3,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ?4 AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindInt(paidMinor, at: 1)
            stmt.bindText(todayDayString, at: 2)
            stmt.bindText(updatedAtString, at: 3)
            stmt.bindText(runId, at: 4)
        }
    }

    private func fetchPaidMinor(runId: String) throws -> Int {
        let rows = try database.query("""
        SELECT COALESCE(SUM(amountMinor), 0)
        FROM payments
        WHERE runId = ? AND deletedAt IS NULL;
        """, map: { $0.int(at: 0) }, bind: { stmt in
            stmt.bindText(runId, at: 1)
        })
        return rows.first ?? 0
    }

    /// Shared formatter for binding today's date (Istanbul) into the
    /// overdue comparison. `dueDate` is written in the same format, so
    /// the comparison is lexicographic.
    private static let istanbulDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppCalendar.istanbul.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func softDelete(id: String, by userId: String) throws {
        // Delegate to the central helper.
        try database.softDelete(table: "billing_report_runs", id: id, by: userId)
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

    /// 0..19 business fields, 20..29 metadata. Metadata reader is now the
    /// centralised `readMetadata` so corruption discipline
    /// covers this mapper too.
    private static func makeRun(from statement: SQLiteStatement) throws -> BillingReportRun {
        let meta = try statement.readMetadata(startingAt: 20)
        return BillingReportRun(
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
            finalizedAt: SQLitePersistedDate.parse(statement.text(at: 18)),
            finalizedByUserId: statement.text(at: 19),
            organizationId: meta.organizationId,
            createdByUserId: meta.createdByUserId,
            updatedByUserId: meta.updatedByUserId,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            deletedAt: meta.deletedAt,
            rowVersion: meta.rowVersion,
            syncStatus: meta.syncStatus,
            lastSyncedAt: meta.lastSyncedAt,
            originDeviceId: meta.originDeviceId
        )
    }
}
