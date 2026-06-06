//  TodoBillingOverride.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import os

/// Price override type for a specific todo.
/// Per spec §3 / Q7 the two are XOR — either a unit price or a fixed fee.
enum TodoBillingOverrideType: String, CaseIterable, Identifiable, Hashable {
    case unitPrice  // overrides the hourly unit price
    case fixedFee   // total amount for the todo (duration-independent)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unitPrice: return ProWorkLocalizer.shared.string("billingOverride.unitPrice", defaultValue: "Birim Ücret Override")
        case .fixedFee: return ProWorkLocalizer.shared.string("billingOverride.fixedFee", defaultValue: "Sabit Tutar")
        }
    }
}

/// Price override record for a todo (1:1 relationship).
struct TodoBillingOverride: Identifiable, Hashable {
    let id: String
    var todoId: String
    var overrideType: TodoBillingOverrideType
    /// Set when the type is `unitPrice`; nil when the type is `fixedFee`.
    var unitPriceMinor: Int?
    /// Set when the type is `fixedFee`; nil when the type is `unitPrice`.
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
        originDeviceId: String? = DeviceIdentity.current
    ) {
        // the two price fields are XOR by spec
        // (§3 / Q7). A row that carries both was silently resolved
        // by BillingCalculator picking whichever field its current branch
        // happened to read first, masking real billing-rule bugs.
        // Normalise here so the model invariant is "exactly one of
        // unitPriceMinor / fixedFeeMinor is non-nil, matching
        // overrideType". In debug builds we trip an assertion so the
        // source of the inconsistency is obvious; in release builds we
        // drop the off-type value and log a warning rather than crash
        // on a legacy row.
        let (normalisedUnit, normalisedFixed): (Int?, Int?) = {
            switch overrideType {
            case .unitPrice:
                if fixedFeeMinor != nil {
                    assertionFailure("TodoBillingOverride: overrideType=.unitPrice but fixedFeeMinor is set; dropping fixedFeeMinor")
                    ProWorkLog.database.error("TodoBillingOverride conflict (todoId=\(todoId, privacy: .private)): unitPrice override carried a fixedFee value; dropped.")
                }
                return (unitPriceMinor, nil)
            case .fixedFee:
                if unitPriceMinor != nil {
                    assertionFailure("TodoBillingOverride: overrideType=.fixedFee but unitPriceMinor is set; dropping unitPriceMinor")
                    ProWorkLog.database.error("TodoBillingOverride conflict (todoId=\(todoId, privacy: .private)): fixedFee override carried a unitPrice value; dropped.")
                }
                return (nil, fixedFeeMinor)
            }
        }()

        self.id = id
        self.todoId = todoId
        self.overrideType = overrideType
        self.unitPriceMinor = normalisedUnit
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
