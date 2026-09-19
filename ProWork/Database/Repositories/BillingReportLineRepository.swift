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
        id, organizationId, runId, sessionId, sourceKind, sourceId,
        todoId, todoTitle, projectId, projectName,
        customerId, customerName, categoryId, categoryName,
        serviceType, timeType, segmentIndex,
        actualSeconds, billableMinutes, billableSeconds,
        unitPriceMinor, fixedFeeMinor, amountMinor, currency,
        vatRate, vatMinor, totalMinor, isVatExempt,
        isBillable, isManual, isFixedFee,
        startedAt, endedAt, note, sortOrder,
        createdByUserId, updatedByUserId,
        createdAt, updatedAt, deletedAt, rowVersion,
        syncStatus, lastSyncedAt, originDeviceId
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """

    /// Single bind site — `insert` and `executeBatch` share the same code path.
    private static func bindInsert(_ stmt: SQLiteStatement, _ line: BillingReportLine) {
        stmt.bindText(line.id, at: 1)
        stmt.bindText(line.organizationId, at: 2)
        stmt.bindText(line.runId, at: 3)
        stmt.bindText(line.sessionId, at: 4)
        stmt.bindText(line.sourceKind?.rawValue, at: 5)
        stmt.bindText(line.sourceId, at: 6)
        stmt.bindText(line.todoId, at: 7)
        stmt.bindText(line.todoTitle, at: 8)
        stmt.bindText(line.projectId, at: 9)
        stmt.bindText(line.projectName, at: 10)
        stmt.bindText(line.customerId, at: 11)
        stmt.bindText(line.customerName, at: 12)
        stmt.bindText(line.categoryId, at: 13)
        stmt.bindText(line.categoryName, at: 14)
        stmt.bindText(line.serviceType.rawValue, at: 15)
        stmt.bindText(line.timeType.rawValue, at: 16)
        stmt.bindInt(line.segmentIndex, at: 17)
        stmt.bindInt(line.actualSeconds, at: 18)
        stmt.bindInt(line.billableMinutes, at: 19)
        stmt.bindInt(line.billableSeconds, at: 20)
        stmt.bindInt(line.unitPriceMinor, at: 21)
        stmt.bindOptionalInt(line.fixedFeeMinor, at: 22)
        stmt.bindInt(line.amountMinor, at: 23)
        stmt.bindText(line.currency, at: 24)
        stmt.bindText(DecimalPersistence.string(line.vatRate), at: 25)
        stmt.bindInt(line.vatMinor, at: 26)
        stmt.bindInt(line.totalMinor, at: 27)
        stmt.bindInt(line.isVatExempt ? 1 : 0, at: 28)
        stmt.bindInt(line.isBillable ? 1 : 0, at: 29)
        stmt.bindInt(line.isManual ? 1 : 0, at: 30)
        stmt.bindInt(line.isFixedFee ? 1 : 0, at: 31)
        stmt.bindText(line.startedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 32)
        stmt.bindText(line.endedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 33)
        stmt.bindText(line.note, at: 34)
        stmt.bindInt(line.sortOrder, at: 35)
        stmt.bindText(line.createdByUserId, at: 36)
        stmt.bindText(line.updatedByUserId, at: 37)
        stmt.bindText(DateFormatter.proWorkSQLite.string(from: line.createdAt), at: 38)
        stmt.bindText(DateFormatter.proWorkSQLite.string(from: line.updatedAt), at: 39)
        stmt.bindText(line.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 40)
        stmt.bindInt(line.rowVersion, at: 41)
        stmt.bindText(line.syncStatus.rawValue, at: 42)
        stmt.bindText(line.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 43)
        stmt.bindText(line.originDeviceId, at: 44)
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
            l.sourceKind,
            l.sourceId,
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
            let sourceKind = statement.text(at: 0).flatMap(BillingLineSourceKind.init(rawValue:))
            let sourceId = statement.text(at: 1)
            let sessionId = statement.text(at: 2)
            let todoId = statement.text(at: 3) ?? ""
            let segmentIndex = statement.int(at: 4)
            let startedAt = SQLitePersistedDate.parse(statement.text(at: 5))
            return BillingLineSelectionAssignment(
                runId: statement.text(at: 6) ?? "",
                runLabel: statement.text(at: 7) ?? "",
                selectionKey: BillingReportLine.makeSelectionKey(
                    sourceKind: sourceKind,
                    sourceId: sourceId,
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
        id, runId, sessionId, sourceKind, sourceId,
        todoId, todoTitle, projectId, projectName,
        customerId, customerName, categoryId, categoryName,
        serviceType, timeType, segmentIndex,
        actualSeconds, billableMinutes, billableSeconds,
        unitPriceMinor, fixedFeeMinor, amountMinor, currency,
        vatRate, vatMinor, totalMinor, isVatExempt,
        isBillable, isManual, isFixedFee,
        startedAt, endedAt, note, sortOrder,
        organizationId, createdByUserId, updatedByUserId,
        createdAt, updatedAt, deletedAt, rowVersion,
        syncStatus, lastSyncedAt, originDeviceId
    FROM billing_report_lines
    """

    /// Business fields 0..33 (34 columns), metadata 34..43 (10 columns).
    /// Metadata block now goes through the centralised `readMetadata`
    /// helper so throw-on-corruption applies here too.
    private static func makeLine(from statement: SQLiteStatement) throws -> BillingReportLine {
        let vatRate = DecimalPersistence.decimal(from: statement.text(at: 23) ?? "0") ?? 0
        let meta = try statement.readMetadata(startingAt: 34)

        return BillingReportLine(
            id: statement.text(at: 0) ?? UUID().uuidString,
            runId: statement.text(at: 1) ?? "",
            sessionId: statement.text(at: 2),
            sourceKind: statement.text(at: 3).flatMap(BillingLineSourceKind.init(rawValue:)),
            sourceId: statement.text(at: 4),
            todoId: statement.text(at: 5) ?? "",
            todoTitle: statement.text(at: 6) ?? "",
            projectId: statement.text(at: 7),
            projectName: statement.text(at: 8),
            customerId: statement.text(at: 9) ?? "",
            customerName: statement.text(at: 10) ?? "",
            categoryId: statement.text(at: 11),
            categoryName: statement.text(at: 12),
            serviceType: ServiceType(rawValue: statement.text(at: 13) ?? "remote") ?? .remote,
            timeType: TimeType(rawValue: statement.text(at: 14) ?? "regular") ?? .regular,
            segmentIndex: statement.int(at: 15),
            actualSeconds: statement.int(at: 16),
            billableMinutes: statement.int(at: 17),
            billableSeconds: statement.int(at: 18),
            unitPriceMinor: statement.int(at: 19),
            fixedFeeMinor: statement.optionalInt(at: 20),
            amountMinor: statement.int(at: 21),
            currency: statement.text(at: 22) ?? "TRY",
            vatRate: vatRate,
            vatMinor: statement.int(at: 24),
            totalMinor: statement.int(at: 25),
            isVatExempt: statement.int(at: 26) == 1,
            isBillable: statement.int(at: 27) == 1,
            isManual: statement.int(at: 28) == 1,
            isFixedFee: statement.int(at: 29) == 1,
            startedAt: SQLitePersistedDate.parse(statement.text(at: 30)),
            endedAt: SQLitePersistedDate.parse(statement.text(at: 31)),
            note: statement.text(at: 32),
            sortOrder: statement.int(at: 33),
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
