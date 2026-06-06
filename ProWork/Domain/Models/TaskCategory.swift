//  TaskCategory.swift
//  ProWork
//  Created by Pronomi.

import Foundation

struct TaskCategory: Identifiable, Hashable {
    let id: String
    var name: String
    var color: String?
    var isBillableDefault: Bool
    var sortOrder: Int
    var isSystem: Bool
    var vatRateId: String?

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
        name: String,
        color: String? = nil,
        isBillableDefault: Bool = true,
        sortOrder: Int = 0,
        isSystem: Bool = false,
        vatRateId: String? = nil,
        organizationId: String = BuiltInOrganizationId.default,
        createdByUserId: String? = BuiltInUserId.defaultOwner,
        updatedByUserId: String? = BuiltInUserId.defaultOwner,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        rowVersion: Int = 0,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil,
        originDeviceId: String? = DeviceIdentity.current
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.isBillableDefault = isBillableDefault
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.vatRateId = vatRateId
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

extension TaskCategory {
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
        name: String,
        color: String? = nil,
        isBillableDefault: Bool = true,
        sortOrder: Int = 0,
        isSystem: Bool = false,
        vatRateId: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            name: name,
            color: color,
            isBillableDefault: isBillableDefault,
            sortOrder: sortOrder,
            isSystem: isSystem,
            vatRateId: vatRateId,
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
