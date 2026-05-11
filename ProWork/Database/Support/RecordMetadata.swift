//
//  RecordMetadata.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Tüm domain kayıtlarında ortak olan tenant + audit + sync metadata'sını
//  paketleyen yardımcı tip. Her tabloda 10 kolon olarak saklanır:
//
//      organizationId, createdByUserId, updatedByUserId,
//      createdAt, updatedAt, deletedAt, rowVersion,
//      syncStatus, lastSyncedAt, originDeviceId
//
//  Repository'ler bu blok'u tek seferde okuyup yazabilsin diye
//  SQLiteStatement uzantısı sağlanır.
//

import Foundation

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

    /// Yeni bir kayıt için varsayılan metadata.
    static func new(
        organizationId: String = BuiltInOrganizationId.default,
        by userId: String = BuiltInUserId.defaultOwner,
        at date: Date = Date()
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
            originDeviceId: nil
        )
    }

    /// Update'te `updatedAt`/`updatedByUserId` bumplanmış kopya döner.
    /// `rowVersion`/`syncStatus` repository UPDATE SQL'inde otomatik bumplanır.
    func touched(by userId: String = BuiltInUserId.defaultOwner, at date: Date = Date()) -> RecordMetadata {
        var copy = self
        copy.updatedAt = date
        copy.updatedByUserId = userId
        return copy
    }
}

extension SQLiteStatement {
    /// Verilen başlangıç indeksten itibaren 10 metadata kolonunu okur.
    /// Kolon sırası: organizationId, createdByUserId, updatedByUserId,
    ///               createdAt, updatedAt, deletedAt, rowVersion,
    ///               syncStatus, lastSyncedAt, originDeviceId
    func readMetadata(startingAt startIndex: Int32) -> RecordMetadata {
        RecordMetadata(
            organizationId: text(at: startIndex) ?? BuiltInOrganizationId.default,
            createdByUserId: text(at: startIndex + 1),
            updatedByUserId: text(at: startIndex + 2),
            createdAt: DateFormatter.proWorkSQLite.date(from: text(at: startIndex + 3) ?? "") ?? Date(),
            updatedAt: DateFormatter.proWorkSQLite.date(from: text(at: startIndex + 4) ?? "") ?? Date(),
            deletedAt: text(at: startIndex + 5).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            rowVersion: int(at: startIndex + 6),
            syncStatus: SyncStatus(rawValue: text(at: startIndex + 7) ?? "") ?? .local,
            lastSyncedAt: text(at: startIndex + 8).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            originDeviceId: text(at: startIndex + 9)
        )
    }

    /// Verilen başlangıç indeksten itibaren 10 metadata kolonunu bağlar.
    func bindMetadata(_ meta: RecordMetadata, startingAt startIndex: Int32) {
        bindText(meta.organizationId, at: startIndex)
        bindText(meta.createdByUserId, at: startIndex + 1)
        bindText(meta.updatedByUserId, at: startIndex + 2)
        bindText(DateFormatter.proWorkSQLite.string(from: meta.createdAt), at: startIndex + 3)
        bindText(DateFormatter.proWorkSQLite.string(from: meta.updatedAt), at: startIndex + 4)
        bindText(meta.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: startIndex + 5)
        bindInt(meta.rowVersion, at: startIndex + 6)
        bindText(meta.syncStatus.rawValue, at: startIndex + 7)
        bindText(meta.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: startIndex + 8)
        bindText(meta.originDeviceId, at: startIndex + 9)
    }
}

/// Tüm metadata kolonlarının SELECT/INSERT yazımını tekrarlamamak için sabit.
/// Repository'ler kendi kolonlarına ekler.
enum RecordMetadataSQL {
    static let columns = """
    organizationId, createdByUserId, updatedByUserId,
    createdAt, updatedAt, deletedAt, rowVersion,
    syncStatus, lastSyncedAt, originDeviceId
    """

    static let placeholders = "?, ?, ?, ?, ?, ?, ?, ?, ?, ?"
}
