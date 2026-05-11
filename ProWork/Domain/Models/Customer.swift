//
//  Customer.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct Customer: Identifiable, Hashable {
    let id: String
    var name: String
    var code: String?
    var contactPerson: String?
    var address: String?
    var isActive: Bool
    var defaultPriceListId: String?
    var defaultServiceType: String
    var defaultMinBillingMinutes: Int
    var vatRateId: String?
    var notes: String?

    // Tenant + audit + sync (bkz. RecordMetadata)
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
        code: String? = nil,
        contactPerson: String? = nil,
        address: String? = nil,
        isActive: Bool = true,
        defaultPriceListId: String? = nil,
        defaultServiceType: String = "remote",
        defaultMinBillingMinutes: Int = 60,
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
        self.name = name
        self.code = code
        self.contactPerson = contactPerson
        self.address = address
        self.isActive = isActive
        self.defaultPriceListId = defaultPriceListId
        self.defaultServiceType = defaultServiceType
        self.defaultMinBillingMinutes = defaultMinBillingMinutes
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

// MARK: - Metadata köprüsü

extension Customer {
    /// Repository binding/okuma için metadata bloğu.
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

    /// Convenience init: business alanları + tek bir RecordMetadata bloğu.
    init(
        id: String = UUID().uuidString,
        name: String,
        code: String? = nil,
        contactPerson: String? = nil,
        address: String? = nil,
        isActive: Bool = true,
        defaultPriceListId: String? = nil,
        defaultServiceType: String = "remote",
        defaultMinBillingMinutes: Int = 60,
        vatRateId: String? = nil,
        notes: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            name: name,
            code: code,
            contactPerson: contactPerson,
            address: address,
            isActive: isActive,
            defaultPriceListId: defaultPriceListId,
            defaultServiceType: defaultServiceType,
            defaultMinBillingMinutes: defaultMinBillingMinutes,
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
