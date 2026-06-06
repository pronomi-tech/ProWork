//  User.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// System user. Until auth is wired up, a single default Owner is used.
struct User: Identifiable, Hashable {
    let id: String
    var email: String?
    var fullName: String
    var avatarColor: String?
    var isActive: Bool

    // Sync metadata (no organizationId / createdBy — users are global)
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rowVersion: Int
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?
    var originDeviceId: String?

    init(
        id: String = UUID().uuidString,
        email: String? = nil,
        fullName: String,
        avatarColor: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        rowVersion: Int = 0,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil,
        originDeviceId: String? = DeviceIdentity.current
    ) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.avatarColor = avatarColor
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.rowVersion = rowVersion
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.originDeviceId = originDeviceId
    }
}
