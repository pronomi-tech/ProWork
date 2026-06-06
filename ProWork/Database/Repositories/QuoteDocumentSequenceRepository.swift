//  QuoteDocumentSequenceRepository.swift
//  ProWork
//  Created by Pronomi.
//  Atomic per-year quote (Teklif) number reservation.
//  Mirrors `BillingDocumentSequenceRepository` — the previous JSON
//  read-modify-write inside `AppSettingsStore.consumeNextQuoteSequence`
//  raced on parallel saves and could mint duplicate numbers
// .

import Foundation
import SQLite3

final class QuoteDocumentSequenceRepository {
    private let database: AppDatabase

    /// `nonisolated`: stateless forwarder; AppSettingsStore'un MainActor
    /// can be safely called from both the init and a default-argument
    /// nonisolated context (same pattern as AppSettingsRepository).
    nonisolated init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Reserves the next quote number for `(organizationId, year)`
    /// atomically. Returns 1 on the first call for a fresh year, and
    /// monotonically increases on every subsequent call. All three SQL
    /// statements run inside the same `inWriteTransaction` so any other
    /// reservation request blocks at the in-process lock + SQLite BEGIN
    /// IMMEDIATE boundary.
    func reserveNext(organizationId: String, year: Int) throws -> Int {
        try database.inWriteTransaction {
            let now = AppDateFormatters.sqliteTimestamp.string(from: Date())

            try database.execute("""
            INSERT OR IGNORE INTO quote_document_sequences
                (organizationId, year, nextValue, updatedAt)
            VALUES (?, ?, 0, ?);
            """) { statement in
                statement.bindText(organizationId, at: 1)
                statement.bindInt(year, at: 2)
                statement.bindText(now, at: 3)
            }

            try database.execute("""
            UPDATE quote_document_sequences
            SET nextValue = nextValue + 1,
                updatedAt = ?
            WHERE organizationId = ? AND year = ?;
            """) { statement in
                statement.bindText(now, at: 1)
                statement.bindText(organizationId, at: 2)
                statement.bindInt(year, at: 3)
            }

            let rows = try database.query("""
            SELECT nextValue FROM quote_document_sequences
            WHERE organizationId = ? AND year = ?
            LIMIT 1;
            """, map: { statement in
                statement.int(at: 0)
            }, bind: { statement in
                statement.bindText(organizationId, at: 1)
                statement.bindInt(year, at: 2)
            })

            guard let value = rows.first else {
                throw QuoteDocumentSequenceError.reservationFailed
            }

            return value
        }
    }

    /// Returns the last reserved value for `(organizationId, year)`, or
    /// 0 if none. Read-only — does **not** consume a counter slot.
    /// Form previews use this to render a candidate "next number" hint
    /// without burning a number on every keystroke.
    func peekCurrent(organizationId: String, year: Int) throws -> Int {
        let rows = try database.query("""
        SELECT nextValue FROM quote_document_sequences
        WHERE organizationId = ? AND year = ?
        LIMIT 1;
        """, map: { statement in
            statement.int(at: 0)
        }, bind: { statement in
            statement.bindText(organizationId, at: 1)
            statement.bindInt(year, at: 2)
        })

        return rows.first ?? 0
    }
}

enum QuoteDocumentSequenceError: Error, LocalizedError {
    case reservationFailed

    var errorDescription: String? {
        switch self {
        case .reservationFailed:
            return ProWorkLocalizer.shared.string(
                "quote.error.sequenceReservationFailed",
                defaultValue: "Teklif numarası rezerve edilemedi. Lütfen tekrar deneyin."
            )
        }
    }
}
