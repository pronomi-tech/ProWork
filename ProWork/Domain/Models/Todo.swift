//
//  Todo.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct Todo: Identifiable, Hashable {
    let id: String
    var customerId: String?
    var projectId: String?
    var categoryId: String
    var title: String
    var description: String?
    var statusId: String
    var priority: String
    var plannedDate: Date?
    var dueDate: Date?
    var estimatedMinutes: Int?
    var isBillable: Bool
    var completedAt: Date?

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
        customerId: String? = nil,
        projectId: String? = nil,
        categoryId: String,
        title: String,
        description: String? = nil,
        statusId: String = BuiltInTodoStatusId.waiting,
        priority: String = "normal",
        plannedDate: Date? = nil,
        dueDate: Date? = nil,
        estimatedMinutes: Int? = nil,
        isBillable: Bool = true,
        completedAt: Date? = nil,
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
        self.customerId = customerId
        self.projectId = projectId
        self.categoryId = categoryId
        self.title = title
        self.description = description
        self.statusId = statusId
        self.priority = priority
        self.plannedDate = plannedDate
        self.dueDate = dueDate
        self.estimatedMinutes = estimatedMinutes
        self.isBillable = isBillable
        self.completedAt = completedAt
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

extension Todo {
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
        customerId: String? = nil,
        projectId: String? = nil,
        categoryId: String,
        title: String,
        description: String? = nil,
        statusId: String = BuiltInTodoStatusId.waiting,
        priority: String = "normal",
        plannedDate: Date? = nil,
        dueDate: Date? = nil,
        estimatedMinutes: Int? = nil,
        isBillable: Bool = true,
        completedAt: Date? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            customerId: customerId,
            projectId: projectId,
            categoryId: categoryId,
            title: title,
            description: description,
            statusId: statusId,
            priority: priority,
            plannedDate: plannedDate,
            dueDate: dueDate,
            estimatedMinutes: estimatedMinutes,
            isBillable: isBillable,
            completedAt: completedAt,
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
