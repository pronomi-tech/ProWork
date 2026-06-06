//  BillingReportRun.swift
//  ProWork
//  Created by Pronomi.

import Foundation

enum BillingRunStatus: String, CaseIterable, Identifiable, Hashable {
    case draft       // live calculation; recomputed when prices change
    case final       // finalized; snapshot locked
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

/// Billing report for a customer over a given period.
/// While `draft`, it is recalculated live; once `final`, `snapshotJson` is locked
/// and the rows in the `BillingReportLine` table become the source of truth.
struct BillingReportRun: Identifiable, Hashable {
    let id: String
    var customerId: String
    /// `YYYY-MM-DD` (Istanbul business day). The single format for date-only fields.
    /// Use lexicographic string comparison instead of the SQL `date(...)`
    /// function; this format sorts correctly and holiday/due-date checks
    /// don't depend on format-sensitive `date()` calls (Y15 + K10).
    var periodStart: String
    /// `YYYY-MM-DD` (Istanbul business day). See `periodStart`.
    var periodEnd: String
    var status: BillingRunStatus
    var title: String?
    var invoiceNumber: String?
    /// Official document number (e.g. "HD-2026-000123"). Consumed from the
    /// per-year `AppSettings.billingDocumentSequenceByYear` counter at finalize
    /// time; stays nil while draft.
    var documentNumber: String?
    var currency: String
    var subtotalMinor: Int
    var vatMinor: Int
    var totalMinor: Int
    var paidMinor: Int
    var balanceMinor: Int
    var paymentStatus: PaymentStatus
    /// `YYYY-MM-DD` (Istanbul). See `periodStart`. K10's overdue
    /// comparison relies on this invariant.
    var dueDate: String?
    var snapshotJson: String?
    var notes: String?
    /// Instant (ISO timestamp via `DateFormatter.proWorkSQLite`). All Date
    /// columns that need a point-in-time (rather than a date-only) value
    /// use this format.
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
        documentNumber: String? = nil,
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
        originDeviceId: String? = DeviceIdentity.current
    ) {
        self.id = id
        self.customerId = customerId
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.status = status
        self.title = title
        self.invoiceNumber = invoiceNumber
        self.documentNumber = documentNumber
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
