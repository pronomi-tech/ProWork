//  SyncStatus.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Server sync status of a record.
/// There's no server yet; every record starts as `local`. Once the backend
/// lands, the syncing/synced/conflict values come into play.
/// Raw values are persisted as TEXT in the DB. Renaming a case
/// would orphan persisted rows, so we write raw values
/// **explicitly** to keep case renames from breaking the value contract.
enum SyncStatus: String, CaseIterable, Identifiable, Hashable {
    case local = "local"
    case syncing = "syncing"
    case synced = "synced"
    case conflict = "conflict"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return ProWorkLocalizer.shared.string("sync.local", defaultValue: "Yerel")
        case .syncing: return ProWorkLocalizer.shared.string("sync.syncing", defaultValue: "Senkronize Ediliyor")
        case .synced: return ProWorkLocalizer.shared.string("sync.synced", defaultValue: "Senkronize")
        case .conflict: return ProWorkLocalizer.shared.string("sync.conflict", defaultValue: "Çakışma")
        }
    }

    static let `default`: SyncStatus = .local
}
