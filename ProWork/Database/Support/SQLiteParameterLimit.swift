//  SQLiteParameterLimit.swift
//  ProWork
//  Created by Pronomi.
//  Shared constants for batched IN-clause queries. SQLite's compile-time
//  `SQLITE_MAX_VARIABLE_NUMBER` defaults to 999 on most builds; we chunk well
//  below that to leave headroom for the rest of the parameter binds in the
//  same statement.

import Foundation

enum SQLiteParameterLimit {
    /// Maximum number of `?` placeholders we are willing to bind into a single
    /// `IN (?, ?, ...)` clause. Repositories that fan out per-row lookups
    /// should split their inputs into chunks of this size.
    /// Conservative ceiling: SQLite's compile-time max is typically 999 but
    /// some platforms ship with 250. 500 strikes a balance — large enough to
    /// keep round-trips down, small enough to coexist with other binds in the
    /// same statement.
    static let inClauseChunk = 500
}
