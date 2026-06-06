//  SQLitePersistedDate.swift
//  ProWork
//  Created by Pronomi.
//  ~12 repositories each defined their own
//  `parseDate(_:)` / `formatDate(_:)` private statics on top of
//  `DateFormatter.proWorkSQLite`. Pull the two helpers into a single
//  namespace so a future change to the canonical SQLite date format
//  (e.g. switching to ISO 8601 with fractional seconds) touches one
//  file instead of twelve.

import Foundation

enum SQLitePersistedDate {
    /// Parse the canonical SQLite-format date string into a `Date`. Empty
    /// or nil input maps to nil so optional columns round-trip naturally.
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return DateFormatter.proWorkSQLite.date(from: raw)
    }

    /// Encode a `Date?` into the canonical SQLite-format string. `nil` →
    /// `nil` so callers can pipe optional fields straight into bind sites.
    static func format(_ value: Date?) -> String? {
        guard let value else { return nil }
        return DateFormatter.proWorkSQLite.string(from: value)
    }

    /// Convenience for non-optional dates.
    static func format(_ value: Date) -> String {
        DateFormatter.proWorkSQLite.string(from: value)
    }
}
