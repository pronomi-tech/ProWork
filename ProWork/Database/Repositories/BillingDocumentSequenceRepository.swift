//  BillingDocumentSequenceRepository.swift
//  ProWork
//  Created by Pronomi.
//  Provides atomic year-based document number reservation. The increment
//  happens in a single SQLite UPSERT; the whole flow runs inside
//  `inWriteTransaction` so parallel `finalizeRun` calls cannot hand out
//  the same counter value twice.
//  In the previous version the counter was incremented with a
//  read-modify-write against the `app_settings.billingDocumentSequenceByYear`
//  JSON field; that race could produce duplicate invoice numbers.

import Foundation
import SQLite3

final class BillingDocumentSequenceRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Atomically reserves and returns the next counter value for the
    /// given organization + year. Returns 1 on the first call; each
    /// subsequent call returns the previous value + 1.
    /// The flow inside one transaction:
    /// 1. `INSERT OR IGNORE` initialises the row to 0 if it doesn't exist.
    /// 2. `UPDATE ... SET nextValue = nextValue + 1` increment.
    /// 3. `SELECT nextValue` reads the new value.
    /// All steps run inside `AppDatabase.inWriteTransaction`, so
    /// hem in-process (`NSRecursiveLock`) hem SQLite (`BEGIN IMMEDIATE`)
    /// no other reservation can interleave at the SQLite level.
    func reserveNext(organizationId: String, year: Int) throws -> Int {
        try database.inWriteTransaction {
            let now = AppDateFormatters.sqliteTimestamp.string(from: Date())

            try database.execute("""
            INSERT OR IGNORE INTO billing_document_sequences
                (organizationId, year, nextValue, updatedAt)
            VALUES (?, ?, 0, ?);
            """) { statement in
                statement.bindText(organizationId, at: 1)
                statement.bindInt(year, at: 2)
                statement.bindText(now, at: 3)
            }

            try database.execute("""
            UPDATE billing_document_sequences
            SET nextValue = nextValue + 1,
                updatedAt = ?
            WHERE organizationId = ? AND year = ?;
            """) { statement in
                statement.bindText(now, at: 1)
                statement.bindText(organizationId, at: 2)
                statement.bindInt(year, at: 3)
            }

            let rows = try database.query("""
            SELECT nextValue FROM billing_document_sequences
            WHERE organizationId = ? AND year = ?
            LIMIT 1;
            """, map: { statement in
                statement.int(at: 0)
            }, bind: { statement in
                statement.bindText(organizationId, at: 1)
                statement.bindInt(year, at: 2)
            })

            guard let value = rows.first else {
                throw BillingDocumentSequenceError.reservationFailed
            }

            return value
        }
    }

    /// Returns the current counter for the given year (the **most recently
    /// produced value**, NOT the next unconsumed value). nil if absent.
    /// Reporting / testing only.
    func peekCurrent(organizationId: String, year: Int) throws -> Int? {
        let rows = try database.query("""
        SELECT nextValue FROM billing_document_sequences
        WHERE organizationId = ? AND year = ?
        LIMIT 1;
        """, map: { statement in
            statement.int(at: 0)
        }, bind: { statement in
            statement.bindText(organizationId, at: 1)
            statement.bindInt(year, at: 2)
        })

        return rows.first
    }
}

enum BillingDocumentSequenceError: Error, LocalizedError {
    case reservationFailed

    var errorDescription: String? {
        switch self {
        case .reservationFailed:
            return ProWorkLocalizer.shared.string(
                "billingRuns.error.documentSequenceFailed",
                defaultValue: "Belge numarası rezerve edilemedi. Lütfen tekrar deneyin."
            )
        }
    }
}
