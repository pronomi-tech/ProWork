//
//  Project.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct Project: Identifiable, Hashable {
    let id: String
    var customerId: String
    var name: String
    var code: String?
    var status: String
    var defaultServiceType: String?
    var defaultMinBillingMinutes: Int?
    var billingWindowMode: BillingWindowMode?
    var vatRateId: String?
    var notes: String?

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
        customerId: String,
        name: String,
        code: String? = nil,
        status: String = "active",
        defaultServiceType: String? = nil,
        defaultMinBillingMinutes: Int? = nil,
        billingWindowMode: BillingWindowMode? = nil,
        vatRateId: String? = nil,
        notes: String? = nil,
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
        self.name = name
        self.code = code
        self.status = status
        self.defaultServiceType = defaultServiceType
        self.defaultMinBillingMinutes = defaultMinBillingMinutes
        self.billingWindowMode = billingWindowMode
        self.vatRateId = vatRateId
        self.notes = notes
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

extension Project {
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
        customerId: String,
        name: String,
        code: String? = nil,
        status: String = "active",
        defaultServiceType: String? = nil,
        defaultMinBillingMinutes: Int? = nil,
        billingWindowMode: BillingWindowMode? = nil,
        vatRateId: String? = nil,
        notes: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            customerId: customerId,
            name: name,
            code: code,
            status: status,
            defaultServiceType: defaultServiceType,
            defaultMinBillingMinutes: defaultMinBillingMinutes,
            billingWindowMode: billingWindowMode,
            vatRateId: vatRateId,
            notes: notes,
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
