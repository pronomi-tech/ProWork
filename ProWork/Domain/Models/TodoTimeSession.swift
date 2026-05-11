//
//  TodoTimeSession.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct TodoTimeSession: Identifiable, Hashable {
    let id: String
    var todoId: String
    var startedAt: Date
    var runningSinceAt: Date?
    var pausedAt: Date?
    var endedAt: Date?
    var durationSeconds: Int?
    var startStatusId: String?
    var endStatusId: String?
    var note: String?
    var isManual: Bool

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
        todoId: String,
        startedAt: Date = Date(),
        runningSinceAt: Date? = nil,
        pausedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSeconds: Int? = nil,
        startStatusId: String? = nil,
        endStatusId: String? = nil,
        note: String? = nil,
        isManual: Bool = false,
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
        self.todoId = todoId
        self.startedAt = startedAt
        self.runningSinceAt = runningSinceAt
        self.pausedAt = pausedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.startStatusId = startStatusId
        self.endStatusId = endStatusId
        self.note = note
        self.isManual = isManual
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

extension TodoTimeSession {
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
        todoId: String,
        startedAt: Date = Date(),
        runningSinceAt: Date? = nil,
        pausedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSeconds: Int? = nil,
        startStatusId: String? = nil,
        endStatusId: String? = nil,
        note: String? = nil,
        isManual: Bool = false,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            todoId: todoId,
            startedAt: startedAt,
            runningSinceAt: runningSinceAt,
            pausedAt: pausedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            startStatusId: startStatusId,
            endStatusId: endStatusId,
            note: note,
            isManual: isManual,
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
