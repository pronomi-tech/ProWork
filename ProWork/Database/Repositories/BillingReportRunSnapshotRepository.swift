//  BillingReportRunSnapshotRepository.swift
//  ProWork
//  Created by Pronomi.
//  Append-only history of finalized billing run snapshots.
//  Previously the canonical `billing_report_runs.snapshotJson` was overwritten
//  whenever a finalized run was reopened and re-finalized — the audit trail
//  was effectively missing because the prior finalized state was lost. Every
//  call to `finalizeRun` now also writes a row here. No UPDATE or DELETE
//  methods are exposed; the table is meant to be tamper-evident at the
//  application layer.

import Foundation
import SQLite3

struct BillingReportRunSnapshot: Equatable {
    let id: String
    let runId: String
    let organizationId: String
    let finalizedAt: Date
    let finalizedByUserId: String?
    let invoiceNumber: String?
    let documentNumber: String?
    let snapshotJson: String
    let createdAt: Date
}

final class BillingReportRunSnapshotRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Insert a new immutable history row. Callers are expected to invoke
    /// this once per finalize operation — including each re-finalize after a
    /// reopen. Order is preserved by `(runId, finalizedAt)`.
    /// - Parameter id: Caller-provided primary key. Defaults to a fresh
    ///   UUID so production callers don't have to think about it; test
    ///   fixtures can pass a stable id to make assertions deterministic.
    func append(
        id: String = UUID().uuidString,
        runId: String,
        organizationId: String,
        finalizedAt: Date,
        finalizedByUserId: String?,
        invoiceNumber: String?,
        documentNumber: String?,
        snapshotJson: String
    ) throws {
        let now = Date()
        try database.execute("""
        INSERT INTO billing_report_run_snapshots (
            id,
            runId,
            organizationId,
            finalizedAt,
            finalizedByUserId,
            invoiceNumber,
            documentNumber,
            snapshotJson,
            createdAt
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """) { statement in
            statement.bindText(id, at: 1)
            statement.bindText(runId, at: 2)
            statement.bindText(organizationId, at: 3)
            statement.bindText(AppDateFormatters.sqliteTimestamp.string(from: finalizedAt), at: 4)
            statement.bindText(finalizedByUserId, at: 5)
            statement.bindText(invoiceNumber, at: 6)
            statement.bindText(documentNumber, at: 7)
            statement.bindText(snapshotJson, at: 8)
            statement.bindText(AppDateFormatters.sqliteTimestamp.string(from: now), at: 9)
        }
    }

    /// Fetch the full ordered history for one run, oldest first. Useful for
    /// audit views and verification tooling.
    func fetchHistory(runId: String) throws -> [BillingReportRunSnapshot] {
        try database.query("""
        SELECT id, runId, organizationId, finalizedAt, finalizedByUserId,
               invoiceNumber, documentNumber, snapshotJson, createdAt
        FROM billing_report_run_snapshots
        WHERE runId = ?
        ORDER BY finalizedAt ASC, createdAt ASC;
        """, map: { statement in
            BillingReportRunSnapshot(
                id: statement.text(at: 0) ?? "",
                runId: statement.text(at: 1) ?? "",
                organizationId: statement.text(at: 2) ?? "",
                finalizedAt: AppDateFormatters.sqliteTimestamp.date(from: statement.text(at: 3) ?? "") ?? Date(),
                finalizedByUserId: statement.text(at: 4),
                invoiceNumber: statement.text(at: 5),
                documentNumber: statement.text(at: 6),
                snapshotJson: statement.text(at: 7) ?? "",
                createdAt: AppDateFormatters.sqliteTimestamp.date(from: statement.text(at: 8) ?? "") ?? Date()
            )
        }, bind: { statement in
            statement.bindText(runId, at: 1)
        })
    }
}
