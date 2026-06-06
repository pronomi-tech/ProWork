//  CompanyProfile.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// An organization's official/invoice identity — appears in PDF/Excel report headers.
struct CompanyProfile: Identifiable, Hashable {
    let id: String
    var legalName: String
    var tradeName: String?
    var taxNumber: String?
    var taxOffice: String?
    var address: String?
    var phone: String?
    var email: String?
    var website: String?
    var logoData: Data?
    var paymentTermsDays: Int

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
        legalName: String,
        tradeName: String? = nil,
        taxNumber: String? = nil,
        taxOffice: String? = nil,
        address: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        website: String? = nil,
        logoData: Data? = nil,
        paymentTermsDays: Int = 30,
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
        self.legalName = legalName
        self.tradeName = tradeName
        self.taxNumber = taxNumber
        self.taxOffice = taxOffice
        self.address = address
        self.phone = phone
        self.email = email
        self.website = website
        self.logoData = logoData
        self.paymentTermsDays = paymentTermsDays
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

extension CompanyProfile {
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
}
