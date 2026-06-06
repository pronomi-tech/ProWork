//  RecordMetadata.swift
//  ProWork
//  Created by Pronomi.
//  Helper type packaging the tenant + audit + sync metadata shared by
//  every domain record. Stored as 10 columns in each table:
//      organizationId, createdByUserId, updatedByUserId,
//      createdAt, updatedAt, deletedAt, rowVersion,
//      syncStatus, lastSyncedAt, originDeviceId
//  Comes with an SQLiteStatement extension so repositories can read and
//  write this block in a single call.

import Foundation
import os

struct RecordMetadata: Hashable {
    var organizationId: String
    var createdByUserId: String?
    var updatedByUserId: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rowVersion: Int
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?
    var originDeviceId: String?

    /// Default metadata for a new record.
    /// `originDeviceId` is filled from `DeviceIdentity.current` — when
    /// multi-device sync arrives, writes from two devices of the same
    /// user can be distinguished. Even for records that have never been
    /// synced, the source device is useful in the audit trail.
    static func new(
        organizationId: String = BuiltInOrganizationId.default,
        by userId: String = BuiltInUserId.defaultOwner,
        at date: Date = Date(),
        originDeviceId: String = DeviceIdentity.current
    ) -> RecordMetadata {
        RecordMetadata(
            organizationId: organizationId,
            createdByUserId: userId,
            updatedByUserId: userId,
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            rowVersion: 0,
            syncStatus: .local,
            lastSyncedAt: nil,
            originDeviceId: originDeviceId
        )
    }

    /// Returns a copy with `updatedAt`/`updatedByUserId` bumped for updates.
    /// `rowVersion`/`syncStatus` are bumped automatically in the repository UPDATE SQL.
    func touched(by userId: String = BuiltInUserId.defaultOwner, at date: Date = Date()) -> RecordMetadata {
        var copy = self
        copy.updatedAt = date
        copy.updatedByUserId = userId
        return copy
    }
}

extension SQLiteStatement {
    /// Reads 10 metadata columns starting at the given index.
    /// Column order: organizationId, createdByUserId, updatedByUserId,
    ///               createdAt, updatedAt, deletedAt, rowVersion,
    ///               syncStatus, lastSyncedAt, originDeviceId
    /// Throws when a `createdAt` / `updatedAt` cell is missing or
    /// unparseable. Silently tolerating those would (a) coerce broken
    /// timestamps to "now", which silently corrupts billing windows and
    /// dedup, and (b) hide real schema-violation bugs.
    func readMetadata(startingAt startIndex: Int32) throws -> RecordMetadata {
        RecordMetadata(
            organizationId: try requirePersistedText(
                text(at: startIndex),
                field: "metadata.organizationId"
            ),
            createdByUserId: text(at: startIndex + 1),
            updatedByUserId: text(at: startIndex + 2),
            createdAt: try parsePersistedDate(text(at: startIndex + 3), field: "metadata.createdAt"),
            updatedAt: try parsePersistedDate(text(at: startIndex + 4), field: "metadata.updatedAt"),
            deletedAt: try parseOptionalPersistedDate(
                text(at: startIndex + 5),
                field: "metadata.deletedAt"
            ),
            rowVersion: int(at: startIndex + 6),
            syncStatus: try parsePersistedSyncStatus(
                text(at: startIndex + 7),
                field: "metadata.syncStatus"
            ),
            lastSyncedAt: try parseOptionalPersistedDate(
                text(at: startIndex + 8),
                field: "metadata.lastSyncedAt"
            ),
            originDeviceId: text(at: startIndex + 9)
        )
    }

    /// Read the 9 metadata columns starting at `startIndex`, skipping
    /// `organizationId` (the row's table doesn't carry one — e.g.
    /// `organizations`, `users`). Caller supplies the synthetic
    /// `organizationId` (often an empty string for self-tables) so the
    /// returned struct is well-formed. Same throw-on-corruption
    /// discipline as `readMetadata`.
    func readMetadataWithoutOrgId(
        organizationId: String,
        startingAt startIndex: Int32
    ) throws -> RecordMetadata {
        RecordMetadata(
            organizationId: organizationId,
            createdByUserId: text(at: startIndex),
            updatedByUserId: text(at: startIndex + 1),
            createdAt: try parsePersistedDate(text(at: startIndex + 2), field: "metadata.createdAt"),
            updatedAt: try parsePersistedDate(text(at: startIndex + 3), field: "metadata.updatedAt"),
            deletedAt: try parseOptionalPersistedDate(
                text(at: startIndex + 4),
                field: "metadata.deletedAt"
            ),
            rowVersion: int(at: startIndex + 5),
            syncStatus: try parsePersistedSyncStatus(
                text(at: startIndex + 6),
                field: "metadata.syncStatus"
            ),
            lastSyncedAt: try parseOptionalPersistedDate(
                text(at: startIndex + 7),
                field: "metadata.lastSyncedAt"
            ),
            originDeviceId: text(at: startIndex + 8)
        )
    }

    /// Parses a SQLite TEXT date stored in the canonical `proWorkSQLite`
    /// format. Throws `DatabaseError.executionFailed` for both missing
    /// (NULL/empty) and unparseable values: the metadata columns are
    /// NOT NULL by schema and the previous silent fallback to `Date()`
    /// masked row corruption.
    fileprivate func parsePersistedDate(_ raw: String?, field: String) throws -> Date {
        guard let raw, !raw.isEmpty else {
            ProWorkLog.database.error(
                "Persisted date missing (\(field, privacy: .public)); row corruption."
            )
            throw DatabaseError.executionFailed(
                message: "Persisted date missing for \(field). Row is corrupt."
            )
        }
        // SQLitePersistedDate is the single source of truth for the
        // canonical date format; adopted here so a future format change
        // touches one helper instead of every parse/format call site.
        if let parsed = SQLitePersistedDate.parse(raw) {
            return parsed
        }
        ProWorkLog.database.error(
            "Persisted date parse failed (\(field, privacy: .public))='\(raw, privacy: .private)'; row corruption."
        )
        throw DatabaseError.executionFailed(
            message: "Persisted date parse failed for \(field). Row is corrupt."
        )
    }

    /// Nullable counterpart of `parsePersistedDate`. NULL/empty is a
    /// legitimate "not set" signal, but a *present-but-unparseable* value
    /// must throw: silently coercing it to nil hides bit-rot in the audit
    /// trail (e.g. a corrupted `deletedAt` row would appear alive).
    fileprivate func parseOptionalPersistedDate(_ raw: String?, field: String) throws -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let parsed = SQLitePersistedDate.parse(raw) {
            return parsed
        }
        ProWorkLog.database.error(
            "Persisted optional date parse failed (\(field, privacy: .public))='\(raw, privacy: .private)'; row corruption."
        )
        throw DatabaseError.executionFailed(
            message: "Persisted date parse failed for \(field). Row is corrupt."
        )
    }

    /// `organizationId` is NOT NULL by schema; a missing or empty value
    /// is row corruption. Previously we fell back to
    /// `BuiltInOrganizationId.default`, which silently bucketed corrupt
    /// rows into the default tenant — a multi-tenant data leak.
    fileprivate func requirePersistedText(_ raw: String?, field: String) throws -> String {
        guard let raw, !raw.isEmpty else {
            ProWorkLog.database.error(
                "Persisted text missing (\(field, privacy: .public)); row corruption."
            )
            throw DatabaseError.executionFailed(
                message: "Persisted text missing for \(field). Row is corrupt."
            )
        }
        return raw
    }

    /// `syncStatus` is NOT NULL by schema with a CHECK constraint, but
    /// the previous reader fell back to `.local` for any unknown raw
    /// value, masking schema drift (e.g. an "uploaded" status in code
    /// that the DB hasn't been migrated to recognise).
    fileprivate func parsePersistedSyncStatus(_ raw: String?, field: String) throws -> SyncStatus {
        guard let raw, !raw.isEmpty else {
            ProWorkLog.database.error(
                "Persisted sync status missing (\(field, privacy: .public)); row corruption."
            )
            throw DatabaseError.executionFailed(
                message: "Persisted sync status missing for \(field). Row is corrupt."
            )
        }
        if let parsed = SyncStatus(rawValue: raw) {
            return parsed
        }
        ProWorkLog.database.error(
            "Persisted sync status unknown (\(field, privacy: .public))='\(raw, privacy: .public)'; schema drift or row corruption."
        )
        throw DatabaseError.executionFailed(
            message: "Persisted sync status '\(raw)' is unknown for \(field). Row is corrupt or schema is out of date."
        )
    }

    /// Binds 10 metadata columns starting at the given index.
    func bindMetadata(_ meta: RecordMetadata, startingAt startIndex: Int32) {
        bindText(meta.organizationId, at: startIndex)
        bindText(meta.createdByUserId, at: startIndex + 1)
        bindText(meta.updatedByUserId, at: startIndex + 2)
        bindText(SQLitePersistedDate.format(meta.createdAt), at: startIndex + 3)
        bindText(SQLitePersistedDate.format(meta.updatedAt), at: startIndex + 4)
        bindText(SQLitePersistedDate.format(meta.deletedAt), at: startIndex + 5)
        bindInt(meta.rowVersion, at: startIndex + 6)
        bindText(meta.syncStatus.rawValue, at: startIndex + 7)
        bindText(SQLitePersistedDate.format(meta.lastSyncedAt), at: startIndex + 8)
        bindText(meta.originDeviceId, at: startIndex + 9)
    }

}

/// Single source of truth for the metadata column block used by every
/// repository SELECT / INSERT.
/// the SQL string, the `?` placeholder string, and the
/// hand-keyed bind/read offsets used to be four separately maintained
/// constants. Adding or reordering a column required three coordinated
/// edits and an off-by-one would silently bind values to the wrong
/// column. The list is now `columnNames` and everything else is derived
/// from it; `bindMetadata` / `readMetadata` still depend on the *order*
/// of `columnNames` matching their offset sequence, but the SQL fragments
/// can no longer drift from the list.
/// `organizationId` is the first entry. For tables that store
/// `organizationId` separately (e.g. `holidays`, `billing_report_runs`),
/// use `columnsWithoutOrgId` / `placeholdersWithoutOrgId` and bind the
/// metadata columns manually. The full-width `bindMetadata` /
/// `readMetadata` helpers MUST only be paired with `columns` /
/// `placeholders`; passing them a `WithoutOrgId` SQL fragment would
/// shift bind indexes by one and silently corrupt rows. Repositories
/// using the 9-column variant inline the bind/read order so the
/// mismatch can't be expressed.
enum RecordMetadataSQL {
    /// The ordered metadata column list. Order is contractual: it must
    /// match the offsets used inside `bindMetadata` and `readMetadata`.
    static let columnNames: [String] = [
        "organizationId",
        "createdByUserId",
        "updatedByUserId",
        "createdAt",
        "updatedAt",
        "deletedAt",
        "rowVersion",
        "syncStatus",
        "lastSyncedAt",
        "originDeviceId",
    ]

    /// Same list with `organizationId` stripped, for tables that carry
    /// `organizationId` as a body column rather than a metadata column.
    static let columnNamesWithoutOrgId: [String] = Array(columnNames.dropFirst())

    /// Comma-joined column list for interpolation into SELECT/INSERT SQL.
    static let columns: String = columnNames.joined(separator: ", ")

    /// `?` placeholder list matching `columns` length.
    static let placeholders: String = Array(repeating: "?", count: columnNames.count)
        .joined(separator: ", ")

    /// Column list minus `organizationId`.
    static let columnsWithoutOrgId: String = columnNamesWithoutOrgId.joined(separator: ", ")

    /// Placeholder list matching `columnsWithoutOrgId` length.
    static let placeholdersWithoutOrgId: String = Array(
        repeating: "?",
        count: columnNamesWithoutOrgId.count
    ).joined(separator: ", ")
}
