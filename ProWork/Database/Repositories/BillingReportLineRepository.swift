//  BillingReportLineRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

struct BillingLineSelectionAssignment: Hashable {
    let runId: String
    let runLabel: String
    let selectionKey: String
}

final class BillingReportLineRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(runId: String) throws -> [BillingReportLine] {
        let sql = """
        \(Self.selectSQL)
        WHERE runId = ? AND deletedAt IS NULL
        ORDER BY sortOrder ASC, startedAt ASC;
        """

        return try database.query(
            sql,
            map: { try Self.makeLine(from: $0) },
            bind: { $0.bindText(runId, at: 1) }
        )
    }

    /// Single-row insert; prefer `executeBatch` (Y2) for the bulk path.
    func insert(_ line: BillingReportLine) throws {
        try database.execute(Self.insertSQL) { stmt in
            Self.bindInsert(stmt, line)
        }
    }

    private static let insertSQL = """
    INSERT INTO billing_report_lines (
        id, organizationId, runId, sessionId,
        todoId, todoTitle, projectId, projectName,
        customerId, customerName, categoryId, categoryName,
        serviceType, timeType, segmentIndex,
        actualSeconds, billableMinutes,
        unitPriceMinor, fixedFeeMinor, amountMinor, currency,
        vatRate, vatMinor, totalMinor, isVatExempt,
        isBillable, isManual, isFixedFee,
        startedAt, endedAt, note, sortOrder,
        createdByUserId, updatedByUserId,
        createdAt, updatedAt, deletedAt, rowVersion,
        syncStatus, lastSyncedAt, originDeviceId
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """

    /// Single bind site — `insert` and `executeBatch` share the same code path.
    private static func bindInsert(_ stmt: SQLiteStatement, _ line: BillingReportLine) {
        stmt.bindText(line.id, at: 1)
        stmt.bindText(line.organizationId, at: 2)
        stmt.bindText(line.runId, at: 3)
        stmt.bindText(line.sessionId, at: 4)
        stmt.bindText(line.todoId, at: 5)
        stmt.bindText(line.todoTitle, at: 6)
        stmt.bindText(line.projectId, at: 7)
        stmt.bindText(line.projectName, at: 8)
        stmt.bindText(line.customerId, at: 9)
        stmt.bindText(line.customerName, at: 10)
        stmt.bindText(line.categoryId, at: 11)
        stmt.bindText(line.categoryName, at: 12)
        stmt.bindText(line.serviceType.rawValue, at: 13)
        stmt.bindText(line.timeType.rawValue, at: 14)
        stmt.bindInt(line.segmentIndex, at: 15)
        stmt.bindInt(line.actualSeconds, at: 16)
        stmt.bindInt(line.billableMinutes, at: 17)
        stmt.bindInt(line.unitPriceMinor, at: 18)
        stmt.bindOptionalInt(line.fixedFeeMinor, at: 19)
        stmt.bindInt(line.amountMinor, at: 20)
        stmt.bindText(line.currency, at: 21)
        stmt.bindText(DecimalPersistence.string(line.vatRate), at: 22)
        stmt.bindInt(line.vatMinor, at: 23)
        stmt.bindInt(line.totalMinor, at: 24)
        stmt.bindInt(line.isVatExempt ? 1 : 0, at: 25)
        stmt.bindInt(line.isBillable ? 1 : 0, at: 26)
        stmt.bindInt(line.isManual ? 1 : 0, at: 27)
        stmt.bindInt(line.isFixedFee ? 1 : 0, at: 28)
        stmt.bindText(line.startedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 29)
        stmt.bindText(line.endedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 30)
        stmt.bindText(line.note, at: 31)
        stmt.bindInt(line.sortOrder, at: 32)
        stmt.bindText(line.createdByUserId, at: 33)
        stmt.bindText(line.updatedByUserId, at: 34)
        stmt.bindText(DateFormatter.proWorkSQLite.string(from: line.createdAt), at: 35)
        stmt.bindText(DateFormatter.proWorkSQLite.string(from: line.updatedAt), at: 36)
        stmt.bindText(line.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 37)
        stmt.bindInt(line.rowVersion, at: 38)
        stmt.bindText(line.syncStatus.rawValue, at: 39)
        stmt.bindText(line.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 40)
        stmt.bindText(line.originDeviceId, at: 41)
    }

    func deleteAll(runId: String) throws {
        let sql = """
        DELETE FROM billing_report_lines
        WHERE runId = ?;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(runId, at: 1)
        }
    }

    /// Deletes every row for the given run and inserts the new ones (draft refresh).
    /// nested-friendly savepoint.
    /// single prepare → N reset+rebind. Eliminates the per-row
    /// prepare/finalize cost on drafts with thousands of rows.
    /// eder.
    func replace(runId: String, lines: [BillingReportLine]) throws {
        try database.inTransaction {
            try deleteAll(runId: runId)
            guard !lines.isEmpty else { return }
            try database.executeBatch(Self.insertSQL, items: lines) { stmt, line in
                Self.bindInsert(stmt, line)
            }
        }
    }

    /// Single SQL covering both "all runs" and "exclude one run" cases via
    /// a nullable-bind predicate (`? IS NULL OR r.id != ?`). The two
    /// near-duplicate queries used to drift independently when filters
    /// changed; the consolidated form is bound twice with the same
    /// `excludingRunId` (NULL when not filtering).
    func fetchSelectionAssignments(
        organizationId: String,
        customerId: String,
        excludingRunId: String? = nil
    ) throws -> [BillingLineSelectionAssignment] {
        let sql = """
        SELECT
            l.sessionId,
            l.todoId,
            l.segmentIndex,
            l.startedAt,
            r.id,
            COALESCE(r.title, r.invoiceNumber, r.id)
        FROM billing_report_lines l
        INNER JOIN billing_report_runs r ON r.id = l.runId
        WHERE l.organizationId = ?
          AND l.customerId = ?
          AND l.deletedAt IS NULL
          AND r.deletedAt IS NULL
          AND r.status != 'cancelled'
          AND (? IS NULL OR r.id != ?);
        """

        return try database.query(sql, map: { statement in
            let sessionId = statement.text(at: 0)
            let todoId = statement.text(at: 1) ?? ""
            let segmentIndex = statement.int(at: 2)
            let startedAt = SQLitePersistedDate.parse(statement.text(at: 3))
            return BillingLineSelectionAssignment(
                runId: statement.text(at: 4) ?? "",
                runLabel: statement.text(at: 5) ?? "",
                selectionKey: BillingReportLine.makeSelectionKey(
                    sessionId: sessionId,
                    todoId: todoId,
                    segmentIndex: segmentIndex,
                    startedAt: startedAt
                )
            )
        }, bind: { statement in
            statement.bindText(organizationId, at: 1)
            statement.bindText(customerId, at: 2)
            statement.bindText(excludingRunId, at: 3)
            statement.bindText(excludingRunId, at: 4)
        })
    }

    // MARK: - Helpers

    private static let selectSQL = """
    SELECT
        id, runId, sessionId,
        todoId, todoTitle, projectId, projectName,
        customerId, customerName, categoryId, categoryName,
        serviceType, timeType, segmentIndex,
        actualSeconds, billableMinutes,
        unitPriceMinor, fixedFeeMinor, amountMinor, currency,
        vatRate, vatMinor, totalMinor, isVatExempt,
        isBillable, isManual, isFixedFee,
        startedAt, endedAt, note, sortOrder,
        organizationId, createdByUserId, updatedByUserId,
        createdAt, updatedAt, deletedAt, rowVersion,
        syncStatus, lastSyncedAt, originDeviceId
    FROM billing_report_lines
    """

    /// Business fields 0..30 (31 columns), metadata 31..40 (10 columns).
    /// Metadata block now goes through the centralised `readMetadata`
    /// helper so throw-on-corruption applies here too.
    private static func makeLine(from statement: SQLiteStatement) throws -> BillingReportLine {
        let vatRate = DecimalPersistence.decimal(from: statement.text(at: 20) ?? "0") ?? 0
        let meta = try statement.readMetadata(startingAt: 31)

        return BillingReportLine(
            id: statement.text(at: 0) ?? UUID().uuidString,
            runId: statement.text(at: 1) ?? "",
            sessionId: statement.text(at: 2),
            todoId: statement.text(at: 3) ?? "",
            todoTitle: statement.text(at: 4) ?? "",
            projectId: statement.text(at: 5),
            projectName: statement.text(at: 6),
            customerId: statement.text(at: 7) ?? "",
            customerName: statement.text(at: 8) ?? "",
            categoryId: statement.text(at: 9),
            categoryName: statement.text(at: 10),
            serviceType: ServiceType(rawValue: statement.text(at: 11) ?? "remote") ?? .remote,
            timeType: TimeType(rawValue: statement.text(at: 12) ?? "regular") ?? .regular,
            segmentIndex: statement.int(at: 13),
            actualSeconds: statement.int(at: 14),
            billableMinutes: statement.int(at: 15),
            unitPriceMinor: statement.int(at: 16),
            fixedFeeMinor: statement.optionalInt(at: 17),
            amountMinor: statement.int(at: 18),
            currency: statement.text(at: 19) ?? "TRY",
            vatRate: vatRate,
            vatMinor: statement.int(at: 21),
            totalMinor: statement.int(at: 22),
            isVatExempt: statement.int(at: 23) == 1,
            isBillable: statement.int(at: 24) == 1,
            isManual: statement.int(at: 25) == 1,
            isFixedFee: statement.int(at: 26) == 1,
            startedAt: SQLitePersistedDate.parse(statement.text(at: 27)),
            endedAt: SQLitePersistedDate.parse(statement.text(at: 28)),
            note: statement.text(at: 29),
            sortOrder: statement.int(at: 30),
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
