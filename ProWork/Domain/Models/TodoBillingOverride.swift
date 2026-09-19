//  TodoBillingOverride.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import os

/// Billing arrangement for a specific todo. `unitPrice` keeps the existing
/// tracked-time override, while the other cases are session-independent
/// commercial sources that must be emitted once per todo.
enum TodoBillingOverrideType: String, CaseIterable, Identifiable, Hashable {
    case unitPrice  // overrides the hourly unit price
    case projectedFee // agreed man-hours multiplied by an hourly unit price
    case fixedFee   // total amount for the todo (duration-independent)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unitPrice: return ProWorkLocalizer.shared.string("billingOverride.unitPrice", defaultValue: "Birim Ücret Override")
        case .projectedFee: return ProWorkLocalizer.shared.string("billingOverride.projectedFee", defaultValue: "Projelendirilmiş Ücret")
        case .fixedFee: return ProWorkLocalizer.shared.string("billingOverride.fixedFee", defaultValue: "Sabit Tutar")
        }
    }

    var isSessionIndependent: Bool {
        self == .projectedFee || self == .fixedFee
    }
}

/// Price override record for a todo (1:1 relationship).
struct TodoBillingOverride: Identifiable, Hashable {
    let id: String
    var todoId: String
    var overrideType: TodoBillingOverrideType
    /// Set for tracked-time unit-price overrides and projected fees.
    var unitPriceMinor: Int?
    /// Contracted duration for `projectedFee`; actual work sessions remain
    /// operational evidence and do not replace this priced quantity.
    var projectedBillableSeconds: Int?
    /// Set only when the type is `fixedFee`.
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
        projectedBillableSeconds: Int? = nil,
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
        originDeviceId: String? = DeviceIdentity.current
    ) {
        // Normalize fields by pricing method so stale values from a previous
        // selection cannot leak into billing after the user changes methods.
        let (normalisedUnit, normalisedProjectedSeconds, normalisedFixed): (Int?, Int?, Int?) = {
            switch overrideType {
            case .unitPrice:
                if fixedFeeMinor != nil || projectedBillableSeconds != nil {
                    assertionFailure("TodoBillingOverride: tracked-time override carried session-independent values; dropping them")
                    ProWorkLog.database.error("TodoBillingOverride conflict (todoId=\(todoId, privacy: .private)): unitPrice override carried session-independent values; dropped.")
                }
                return (unitPriceMinor, nil, nil)
            case .projectedFee:
                if fixedFeeMinor != nil {
                    assertionFailure("TodoBillingOverride: projectedFee carried fixedFeeMinor; dropping it")
                    ProWorkLog.database.error("TodoBillingOverride conflict (todoId=\(todoId, privacy: .private)): projectedFee carried fixedFeeMinor; dropped.")
                }
                return (unitPriceMinor, projectedBillableSeconds.map { max(0, $0) }, nil)
            case .fixedFee:
                if unitPriceMinor != nil || projectedBillableSeconds != nil {
                    assertionFailure("TodoBillingOverride: fixedFee carried hourly pricing values; dropping them")
                    ProWorkLog.database.error("TodoBillingOverride conflict (todoId=\(todoId, privacy: .private)): fixedFee carried hourly pricing values; dropped.")
                }
                return (nil, nil, fixedFeeMinor)
            }
        }()

        self.id = id
        self.todoId = todoId
        self.overrideType = overrideType
        self.unitPriceMinor = normalisedUnit
        self.projectedBillableSeconds = normalisedProjectedSeconds
        self.fixedFeeMinor = normalisedFixed
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
        projectedBillableSeconds: Int? = nil,
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
            projectedBillableSeconds: projectedBillableSeconds,
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
