//
//  BillingReportRun.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum BillingRunStatus: String, CaseIterable, Identifiable, Hashable {
    case draft       // canlı hesap, fiyat değişirse yeniden hesaplanır
    case final       // kesinleşmiş, snapshot kilitli
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return ProWorkLocalizer.shared.string("billing.status.draft", defaultValue: "Taslak")
        case .final: return ProWorkLocalizer.shared.string("billing.status.final", defaultValue: "Kesinleşti")
        case .cancelled: return ProWorkLocalizer.shared.string("billing.status.cancelled", defaultValue: "İptal")
        }
    }
}

enum PaymentStatus: String, CaseIterable, Identifiable, Hashable {
    case unpaid
    case partial
    case paid
    case overdue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unpaid: return ProWorkLocalizer.shared.string("paymentStatus.unpaid", defaultValue: "Ödenmedi")
        case .partial: return ProWorkLocalizer.shared.string("paymentStatus.partial", defaultValue: "Kısmen Ödendi")
        case .paid: return ProWorkLocalizer.shared.string("paymentStatus.paid", defaultValue: "Ödendi")
        case .overdue: return ProWorkLocalizer.shared.string("paymentStatus.overdue", defaultValue: "Vadesi Geçti")
        }
    }
}

/// Bir müşteri için bir dönemin faturalandırma raporu.
/// `draft` halindeyken canlı hesaplanır; `final` olunca `snapshotJson` kilitlenir
/// ve `BillingReportLine` tablosundaki satırlar doğruluk kaynağı olur.
struct BillingReportRun: Identifiable, Hashable {
    let id: String
    var customerId: String
    /// "yyyy-MM-dd"
    var periodStart: String
    var periodEnd: String
    var status: BillingRunStatus
    var title: String?
    var invoiceNumber: String?
    var currency: String
    var subtotalMinor: Int
    var vatMinor: Int
    var totalMinor: Int
    var paidMinor: Int
    var balanceMinor: Int
    var paymentStatus: PaymentStatus
    var dueDate: String?
    var snapshotJson: String?
    var notes: String?
    var finalizedAt: Date?
    var finalizedByUserId: String?

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
        periodStart: String,
        periodEnd: String,
        status: BillingRunStatus = .draft,
        title: String? = nil,
        invoiceNumber: String? = nil,
        currency: String = "TRY",
        subtotalMinor: Int = 0,
        vatMinor: Int = 0,
        totalMinor: Int = 0,
        paidMinor: Int = 0,
        balanceMinor: Int = 0,
        paymentStatus: PaymentStatus = .unpaid,
        dueDate: String? = nil,
        snapshotJson: String? = nil,
        notes: String? = nil,
        finalizedAt: Date? = nil,
        finalizedByUserId: String? = nil,
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
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.status = status
        self.title = title
        self.invoiceNumber = invoiceNumber
        self.currency = currency.uppercased()
        self.subtotalMinor = subtotalMinor
        self.vatMinor = vatMinor
        self.totalMinor = totalMinor
        self.paidMinor = paidMinor
        self.balanceMinor = balanceMinor
        self.paymentStatus = paymentStatus
        self.dueDate = dueDate
        self.snapshotJson = snapshotJson
        self.notes = notes
        self.finalizedAt = finalizedAt
        self.finalizedByUserId = finalizedByUserId
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

extension BillingReportRun {
    var subtotal: Money { Money(minorUnits: subtotalMinor, currency: currency) }
    var vat: Money { Money(minorUnits: vatMinor, currency: currency) }
    var total: Money { Money(minorUnits: totalMinor, currency: currency) }
    var paid: Money { Money(minorUnits: paidMinor, currency: currency) }
    var balance: Money { Money(minorUnits: balanceMinor, currency: currency) }

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
