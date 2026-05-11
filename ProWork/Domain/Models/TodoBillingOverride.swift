//
//  TodoBillingOverride.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Belirli bir todo için fiyat override tipi.
/// Spec §3 / Soru 7 kararı uyarınca XOR — ya birim ücret ya da sabit fee.
enum TodoBillingOverrideType: String, CaseIterable, Identifiable, Hashable {
    case unitPrice  // saatlik birim ücreti override eder
    case fixedFee   // todo'nun toplam tutarı (süre bağımsız)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unitPrice: return ProWorkLocalizer.shared.string("billingOverride.unitPrice", defaultValue: "Birim Ücret Override")
        case .fixedFee: return ProWorkLocalizer.shared.string("billingOverride.fixedFee", defaultValue: "Sabit Tutar")
        }
    }
}

/// Bir todo için fiyat override kaydı (1:1 ilişki).
struct TodoBillingOverride: Identifiable, Hashable {
    let id: String
    var todoId: String
    var overrideType: TodoBillingOverrideType
    /// `unitPrice` türünde dolu; `fixedFee` türünde nil.
    var unitPriceMinor: Int?
    /// `fixedFee` türünde dolu; `unitPrice` türünde nil.
    var fixedFeeMinor: Int?
    var currency: String
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
        todoId: String,
        overrideType: TodoBillingOverrideType,
        unitPriceMinor: Int? = nil,
        fixedFeeMinor: Int? = nil,
        currency: String = "TRY",
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
        self.todoId = todoId
        self.overrideType = overrideType
        self.unitPriceMinor = unitPriceMinor
        self.fixedFeeMinor = fixedFeeMinor
        self.currency = currency.uppercased()
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
}

extension TodoBillingOverride {
    var unitPrice: Money? {
        unitPriceMinor.map { Money(minorUnits: $0, currency: currency) }
    }

    var fixedFee: Money? {
        fixedFeeMinor.map { Money(minorUnits: $0, currency: currency) }
    }

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
        overrideType: TodoBillingOverrideType,
        unitPriceMinor: Int? = nil,
        fixedFeeMinor: Int? = nil,
        currency: String = "TRY",
        note: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            todoId: todoId,
            overrideType: overrideType,
            unitPriceMinor: unitPriceMinor,
            fixedFeeMinor: fixedFeeMinor,
            currency: currency,
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
