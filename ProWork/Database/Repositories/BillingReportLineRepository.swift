//
//  BillingReportLineRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

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
            map: { Self.makeLine(from: $0) },
            bind: { $0.bindText(runId, at: 1) }
        )
    }

    func insert(_ line: BillingReportLine) throws {
        let sql = """
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

        try database.execute(sql) { stmt in
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
            stmt.bindText(NSDecimalNumber(decimal: line.vatRate).stringValue, at: 22)
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

    /// Verilen run için tüm satırları siler ve yenilerini ekler (taslak yenileme).
    func replace(runId: String, lines: [BillingReportLine]) throws {
        try database.execute("BEGIN TRANSACTION;")
        do {
            try deleteAll(runId: runId)
            for line in lines {
                try insert(line)
            }
            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    func fetchSelectionAssignments(
        organizationId: String,
        customerId: String,
        excludingRunId: String? = nil
    ) throws -> [BillingLineSelectionAssignment] {
        let sql: String
        let bind: (SQLiteStatement) -> Void

        if let excludingRunId {
            sql = """
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
              AND r.id != ?;
            """
            bind = { statement in
                statement.bindText(organizationId, at: 1)
                statement.bindText(customerId, at: 2)
                statement.bindText(excludingRunId, at: 3)
            }
        } else {
            sql = """
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
              AND r.status != 'cancelled';
            """
            bind = { statement in
                statement.bindText(organizationId, at: 1)
                statement.bindText(customerId, at: 2)
            }
        }

        return try database.query(sql, map: { statement in
            let sessionId = statement.text(at: 0)
            let todoId = statement.text(at: 1) ?? ""
            let segmentIndex = statement.int(at: 2)
            let startedAt = statement.text(at: 3).flatMap(DateFormatter.proWorkSQLite.date(from:))
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
        }, bind: bind)
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

    private static func makeLine(from statement: SQLiteStatement) -> BillingReportLine {
        let vatRate = Decimal(string: statement.text(at: 20) ?? "0") ?? 0

        // Iş alanları 0..30 (31 kolon), metadata 31..40 (10 kolon)
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
            startedAt: statement.text(at: 27).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            endedAt: statement.text(at: 28).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            note: statement.text(at: 29),
            sortOrder: statement.int(at: 30),
            organizationId: statement.text(at: 31) ?? BuiltInOrganizationId.default,
            createdByUserId: statement.text(at: 32),
            updatedByUserId: statement.text(at: 33),
            createdAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 34) ?? "") ?? Date(),
            updatedAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 35) ?? "") ?? Date(),
            deletedAt: statement.text(at: 36).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            rowVersion: statement.int(at: 37),
            syncStatus: SyncStatus(rawValue: statement.text(at: 38) ?? "") ?? .local,
            lastSyncedAt: statement.text(at: 39).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            originDeviceId: statement.text(at: 40)
        )
    }
}
