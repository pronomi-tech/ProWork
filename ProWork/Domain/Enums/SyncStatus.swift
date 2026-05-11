//
//  SyncStatus.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Bir kaydın sunucu sync durumu.
/// Şu an sunucu yok; tüm kayıtlar `local` olarak başlar. İleride backend
/// devreye girince syncing/synced/conflict değerleri devreye alınacak.
enum SyncStatus: String, CaseIterable, Identifiable, Hashable {
    case local
    case syncing
    case synced
    case conflict

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
