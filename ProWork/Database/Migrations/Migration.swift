//  Migration.swift
//  ProWork
//  Created by Pronomi.
//  Unit that applies schema changes sequentially. Each migration is
//  recorded with a monotonically increasing `id`; `up(_:)` runs once
//  idempotently.
//
//  Rollback (`down()`) is deliberately unsupported: ProWork is a
//  single-process SQLite desktop app. If a buggy migration is
//  encountered in production, the recovery path is **manual restore**
//  (from the user's backup under `~/Library/...` or an iCloud
//  snapshot). The "Data recovery" section in the README lists these
//  steps. The forward-only flow was chosen to avoid a multi-writer
//  migration matrix living with half-applied schemas.

import Foundation

protocol Migration {
    var id: Int { get }
    var name: String { get }

    func up(_ database: AppDatabase) throws
}
