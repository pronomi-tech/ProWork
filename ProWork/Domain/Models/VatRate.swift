//  VatRate.swift
//  ProWork
//  Created by Pronomi.
//  Named VAT rate definition. Assigned individually to customer / project /
//  category; if no assignment, the `isDefault = true` entry applies.
//  When `isExempt = true` the rate is treated as 0; the invoice/PDF shows
//  "Muaf" (Exempt) instead of an amount.

import Foundation
import os

struct VatRate: Identifiable, Hashable {
    let id: String
    var name: String
    /// Stored as a multiplier rather than a percentage (20% = 0.20).
    var rate: Decimal
    var isDefault: Bool
    var isExempt: Bool
    var isActive: Bool
    var note: String?
    /// Day this rate becomes effective (`YYYY-MM-DD`). If `nil`, the rate
    /// applies retroactively to all history. When finalizing a past
    /// period, `BillingRunLifecycleService` emits a log warning if
    /// periodStart precedes this date — guards against snapshotting the
    /// wrong rate for old periods after changes like Türkiye VAT 18% → 20%
    /// (July 2023).
    var effectiveFrom: String?

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
        effectiveFrom: String? = nil,
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
        // The previous `self.rate = isExempt ? 0 : rate`
        // line silently discarded a non-zero `rate` when `isExempt: true`
        // was passed alongside it. The "zero out" behaviour is intentional
        // (it's the model invariant) and a downstream test pins it, but
        // doing it silently let a caller lose the rate without realising.
        // Keep the normalisation, drop the silence: log an error so the
        // overwrite is visible in macOS Console / dev logs.
        let normalisedRate: Decimal
        if isExempt {
            if rate > 0 {
                // Name is tenant-customisable text; keep
                // it private. rate is non-PII but mark explicit for clarity.
                // The rate is stringified outside the interpolation so the
                // validate-log-privacy linter (which uses a non-recursive
                // regex) can match the privacy marker.
                let rateString = String(describing: rate)
                ProWorkLog.database.error("VatRate '\(name, privacy: .private)' created exempt with non-zero rate \(rateString, privacy: .public); rate forced to 0.")
            }
            normalisedRate = 0
        } else {
            normalisedRate = rate
        }

        self.id = id
        self.name = name
        self.rate = normalisedRate
        self.isDefault = isDefault
        self.isExempt = isExempt
        self.isActive = isActive
        self.note = note
        self.effectiveFrom = effectiveFrom
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
        effectiveFrom: String? = nil,
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
            effectiveFrom: effectiveFrom,
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

    /// VAT amount applied to `subtotalMinor` (banker's rounding).
    func vatMinor(forSubtotal subtotalMinor: Int) -> Int {
        guard !isExempt, rate > 0, subtotalMinor != 0 else { return 0 }
        var rounded = Decimal()
        var product = Decimal(subtotalMinor) * rate
        NSDecimalRound(&rounded, &product, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

// `BuiltInVatRateId` moved to `Domain/Enums/BuiltInVatRateId.swift`
// so it lives next to the other `BuiltIn*` constant enums. Kept here as
// a `@available` deprecation shim for the (now zero) lingering direct
// references during transition; remove on the next sweep.
