//  Payment.swift
//  ProWork
//  Created by Pronomi.

import Foundation

// Raw value is persisted as TEXT in the DB; written
// explicitly so a case rename can't break the contract.
enum PaymentMethod: String, CaseIterable, Identifiable, Hashable {
    case bankTransfer = "bank_transfer"
    case cash = "cash"
    case card = "card"
    case check = "check"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bankTransfer: return ProWorkLocalizer.shared.string("payment.method.bankTransfer", defaultValue: "Banka Havalesi")
        case .cash: return ProWorkLocalizer.shared.string("payment.method.cash", defaultValue: "Nakit")
        case .card: return ProWorkLocalizer.shared.string("payment.method.card", defaultValue: "Kart")
        case .check: return ProWorkLocalizer.shared.string("payment.method.check", defaultValue: "Çek")
        case .other: return ProWorkLocalizer.shared.string("payment.method.other", defaultValue: "Diğer")
        }
    }

    var systemImage: String {
        switch self {
        case .bankTransfer: return "building.columns"
        case .cash: return "banknote"
        case .card: return "creditcard"
        case .check: return "doc.text"
        case .other: return "ellipsis.circle"
        }
    }
}

/// Payment record for a `BillingReportRun`. There can be multiple for partial payments.
struct Payment: Identifiable, Hashable {
    let id: String
    var runId: String
    var paidAt: Date
    var amountMinor: Int
    var currency: String
    var method: PaymentMethod
    var reference: String?
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
        runId: String,
        paidAt: Date = Date(),
        amountMinor: Int,
        currency: String = "TRY",
        method: PaymentMethod = .bankTransfer,
        reference: String? = nil,
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
        originDeviceId: String? = DeviceIdentity.current
    ) {
        self.id = id
        self.runId = runId
        self.paidAt = paidAt
        self.amountMinor = amountMinor
        self.currency = currency.uppercased()
        self.method = method
        self.reference = reference
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

extension Payment {
    var amount: Money { Money(minorUnits: amountMinor, currency: currency) }

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
        runId: String,
        paidAt: Date = Date(),
        amountMinor: Int,
        currency: String = "TRY",
        method: PaymentMethod = .bankTransfer,
        reference: String? = nil,
        note: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            runId: runId,
            paidAt: paidAt,
            amountMinor: amountMinor,
            currency: currency,
            method: method,
            reference: reference,
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
