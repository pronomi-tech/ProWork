//
//  VatRate.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Adlandırılmış KDV oranı tanımı. Müşteri / proje / kategoriye ayrı ayrı
//  atanır; atama yoksa `isDefault = true` olan tanım uygulanır.
//
//  `isExempt = true` ise oran 0 kabul edilir; faturada/PDF'te tutar yerine
//  "Muaf" gösterilir.
//

import Foundation

struct VatRate: Identifiable, Hashable {
    let id: String
    var name: String
    /// Yüzde olarak değil, çarpan olarak saklanır (%20 = 0.20).
    var rate: Decimal
    var isDefault: Bool
    var isExempt: Bool
    var isActive: Bool
    var note: String?

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
        rate: Decimal,
        isDefault: Bool = false,
        isExempt: Bool = false,
        isActive: Bool = true,
        note: String? = nil,
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
        self.rate = isExempt ? 0 : rate
        self.isDefault = isDefault
        self.isExempt = isExempt
        self.isActive = isActive
        self.note = note
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

    init(
        id: String = UUID().uuidString,
        name: String,
        rate: Decimal,
        isDefault: Bool = false,
        isExempt: Bool = false,
        isActive: Bool = true,
        note: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            name: name,
            rate: rate,
            isDefault: isDefault,
            isExempt: isExempt,
            isActive: isActive,
            note: note,
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

extension VatRate {
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

    /// `subtotalMinor`'a uygulanacak KDV tutarı (banker's rounding).
    func vatMinor(forSubtotal subtotalMinor: Int) -> Int {
        guard !isExempt, rate > 0, subtotalMinor != 0 else { return 0 }
        var rounded = Decimal()
        var product = Decimal(subtotalMinor) * rate
        NSDecimalRound(&rounded, &product, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

enum BuiltInVatRateId {
    static let defaultStandard = "vat_rate_default"
    static let exempt = "vat_rate_exempt"
}
