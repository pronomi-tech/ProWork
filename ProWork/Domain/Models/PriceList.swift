//
//  PriceList.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Bir fiyat listesinin sahibi.
enum PriceListOwnerType: String, CaseIterable, Identifiable, Hashable {
    case global    // organization seviyesi varsayılan
    case customer  // belirli müşteri
    case project   // belirli proje (en yüksek öncelik)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .global: return ProWorkLocalizer.shared.string("priceLists.owner.global", defaultValue: "Genel")
        case .customer: return ProWorkLocalizer.shared.string("priceLists.owner.customer", defaultValue: "Müşteri")
        case .project: return ProWorkLocalizer.shared.string("priceLists.owner.project", defaultValue: "Proje")
        }
    }
}

/// Fiyat listesi başlığı. Satırlar `PriceListRow` ile ayrı tabloda tutulur.
struct PriceList: Identifiable, Hashable {
    let id: String
    var ownerType: PriceListOwnerType
    var ownerId: String?  // global ise nil; müşteri/proje ise ilgili id
    var name: String
    var currency: String
    var isActive: Bool
    var isDefault: Bool
    var validFrom: String?
    var validTo: String?
    var notes: String?

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
        ownerType: PriceListOwnerType,
        ownerId: String? = nil,
        name: String,
        currency: String = "TRY",
        isActive: Bool = true,
        isDefault: Bool = false,
        validFrom: String? = nil,
        validTo: String? = nil,
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
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.name = name
        self.currency = currency.uppercased()
        self.isActive = isActive
        self.isDefault = isDefault
        self.validFrom = validFrom
        self.validTo = validTo
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

extension PriceList {
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
        ownerType: PriceListOwnerType,
        ownerId: String? = nil,
        name: String,
        currency: String = "TRY",
        isActive: Bool = true,
        isDefault: Bool = false,
        validFrom: String? = nil,
        validTo: String? = nil,
        notes: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            name: name,
            currency: currency,
            isActive: isActive,
            isDefault: isDefault,
            validFrom: validFrom,
            validTo: validTo,
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
