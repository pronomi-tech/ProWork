//
//  TodoStatus.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct TodoStatus: Identifiable, Hashable {
    let id: String
    var systemKey: String?
    var name: String
    var color: String?
    var sortOrder: Int
    var isSystem: Bool
    var isActive: Bool
    var showInBoard: Bool
    var startsTimer: Bool
    var stopsTimer: Bool
    var marksOpen: Bool
    var marksCompleted: Bool
    var marksCancelled: Bool

    // Tenant + audit + sync
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

    init(
        id: String = UUID().uuidString,
        systemKey: String? = nil,
        name: String,
        color: String? = nil,
        sortOrder: Int = 0,
        isSystem: Bool = false,
        isActive: Bool = true,
        showInBoard: Bool = true,
        startsTimer: Bool = false,
        stopsTimer: Bool = false,
        marksOpen: Bool = true,
        marksCompleted: Bool = false,
        marksCancelled: Bool = false,
        organizationId: String = BuiltInOrganizationId.default,
        createdByUserId: String? = BuiltInUserId.defaultOwner,
        updatedByUserId: String? = BuiltInUserId.defaultOwner,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        rowVersion: Int = 0,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil,
        originDeviceId: String? = nil
    ) {
        self.id = id
        self.systemKey = systemKey
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.isActive = isActive
        self.showInBoard = showInBoard
        self.startsTimer = startsTimer
        self.stopsTimer = stopsTimer
        self.marksOpen = marksOpen
        self.marksCompleted = marksCompleted
        self.marksCancelled = marksCancelled
        self.organizationId = organizationId
        self.createdByUserId = createdByUserId
        self.updatedByUserId = updatedByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.rowVersion = rowVersion
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.originDeviceId = originDeviceId
    }
}

extension TodoStatus {
    var meta: RecordMetadata {
        RecordMetadata(
            organizationId: organizationId,
            createdByUserId: createdByUserId,
            updatedByUserId: updatedByUserId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowVersion: rowVersion,
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt,
            originDeviceId: originDeviceId
        )
    }

    init(
        id: String = UUID().uuidString,
        systemKey: String? = nil,
        name: String,
        color: String? = nil,
        sortOrder: Int = 0,
        isSystem: Bool = false,
        isActive: Bool = true,
        showInBoard: Bool = true,
        startsTimer: Bool = false,
        stopsTimer: Bool = false,
        marksOpen: Bool = true,
        marksCompleted: Bool = false,
        marksCancelled: Bool = false,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            systemKey: systemKey,
            name: name,
            color: color,
            sortOrder: sortOrder,
            isSystem: isSystem,
            isActive: isActive,
            showInBoard: showInBoard,
            startsTimer: startsTimer,
            stopsTimer: stopsTimer,
            marksOpen: marksOpen,
            marksCompleted: marksCompleted,
            marksCancelled: marksCancelled,
            organizationId: meta.organizationId,
            createdByUserId: meta.createdByUserId,
            updatedByUserId: meta.updatedByUserId,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            deletedAt: meta.deletedAt,
            rowVersion: meta.rowVersion,
            syncStatus: meta.syncStatus,
            lastSyncedAt: meta.lastSyncedAt,
            originDeviceId: meta.originDeviceId
        )
    }
}
