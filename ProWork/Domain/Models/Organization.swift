//  Organization.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Multi-tenant organization. Every customer/project/price list/company profile
/// belongs to an organization. A user can be a member of multiple organizations.
struct Organization: Identifiable, Hashable {
    let id: String
    var name: String
    var slug: String?
    var masterCurrency: String
    var billingWindowMode: BillingWindowMode
    var isActive: Bool

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
        slug: String? = nil,
        masterCurrency: String = "TRY",
        billingWindowMode: BillingWindowMode = .timeline,
        isActive: Bool = true,
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
        self.slug = slug
        self.masterCurrency = masterCurrency
        self.billingWindowMode = billingWindowMode
        self.isActive = isActive
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
