//  BillingReportLine.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import os

/// A single line of a `BillingReportRun`. Snapshotted at finalize time —
/// the line stays fixed even if the source records (todo, customer, category) are deleted.
struct BillingReportLine: Identifiable, Hashable {
    let id: String
    var runId: String

    // References (deletions are tolerated)
    var sessionId: String?
    var todoId: String

    // Snapshot columns (copied at finalize time)
    var todoTitle: String
    var projectId: String?
    var projectName: String?
    var customerId: String
    var customerName: String
    var categoryId: String?
    var categoryName: String?

    // Calculation details
    var serviceType: ServiceType
    var timeType: TimeType
    var segmentIndex: Int
    var actualSeconds: Int
    var billableMinutes: Int
    var unitPriceMinor: Int
    var fixedFeeMinor: Int?
    var amountMinor: Int
    var currency: String
    /// Decimal string such as "0.20".
    var vatRate: Decimal
    var vatMinor: Int
    var totalMinor: Int
    /// Whether VAT exemption was applied (snapshot). Used to render the "Exempt" badge in PDF/reports.
    var isVatExempt: Bool

    // Flags
    var isBillable: Bool
    var isManual: Bool
    var isFixedFee: Bool

    var startedAt: Date?
    var endedAt: Date?
    var note: String?
    var sortOrder: Int

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
        sessionId: String? = nil,
        todoId: String,
        todoTitle: String,
        projectId: String? = nil,
        projectName: String? = nil,
        customerId: String,
        customerName: String,
        categoryId: String? = nil,
        categoryName: String? = nil,
        serviceType: ServiceType,
        timeType: TimeType,
        segmentIndex: Int = 0,
        actualSeconds: Int = 0,
        billableMinutes: Int = 0,
        unitPriceMinor: Int = 0,
        fixedFeeMinor: Int? = nil,
        amountMinor: Int = 0,
        currency: String = "TRY",
        vatRate: Decimal = 0,
        vatMinor: Int = 0,
        totalMinor: Int = 0,
        isVatExempt: Bool = false,
        isBillable: Bool = true,
        isManual: Bool = false,
        isFixedFee: Bool = false,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        note: String? = nil,
        sortOrder: Int = 0,
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
        self.sessionId = sessionId
        self.todoId = todoId
        self.todoTitle = todoTitle
        self.projectId = projectId
        self.projectName = projectName
        self.customerId = customerId
        self.customerName = customerName
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.serviceType = serviceType
        self.timeType = timeType
        self.segmentIndex = segmentIndex
        self.actualSeconds = actualSeconds
        self.billableMinutes = billableMinutes
        self.unitPriceMinor = unitPriceMinor
        // self.fixedFeeMinor / self.isFixedFee assigned below after
        // XOR normalisation.
        self.amountMinor = amountMinor
        self.currency = currency.uppercased()
        self.vatRate = vatRate
        self.vatMinor = vatMinor
        self.totalMinor = totalMinor
        self.isVatExempt = isVatExempt
        self.isBillable = isBillable
        self.isManual = isManual

        // Enforce the XOR invariant between `isFixedFee` and
        // `fixedFeeMinor`. The sibling model `TodoBillingOverride`
        // normalises at init; the same discipline applies here so a
        // mis-built line cannot render "Fixed Amount: 0,00 ₺" downstream.
        //   - isFixedFee = true but fixedFeeMinor = nil → drop the
        //     flag (best-effort recovery; line falls back to the
        //     normal amountMinor path).
        //   - isFixedFee = false but fixedFeeMinor != nil → drop the
        //     fee (caller forgot the flag; the unit-priced amount is
        //     the authoritative source).
        var normalizedIsFixedFee = isFixedFee
        var normalizedFixedFee = fixedFeeMinor
        if isFixedFee && fixedFeeMinor == nil {
            ProWorkLog.billing.error(
                "BillingReportLine init: isFixedFee=true but fixedFeeMinor=nil for line id=\(id, privacy: .public); dropping flag."
            )
            normalizedIsFixedFee = false
        } else if !isFixedFee && fixedFeeMinor != nil {
            ProWorkLog.billing.error(
                "BillingReportLine init: fixedFeeMinor=\(fixedFeeMinor ?? 0, privacy: .public) but isFixedFee=false for line id=\(id, privacy: .public); dropping fixedFeeMinor."
            )
            normalizedFixedFee = nil
        }
        self.fixedFeeMinor = normalizedFixedFee
        self.isFixedFee = normalizedIsFixedFee
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.sortOrder = sortOrder
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

extension BillingReportLine {
    var amount: Money { Money(minorUnits: amountMinor, currency: currency) }
    var vat: Money { Money(minorUnits: vatMinor, currency: currency) }
    var total: Money { Money(minorUnits: totalMinor, currency: currency) }
    var unitPrice: Money { Money(minorUnits: unitPriceMinor, currency: currency) }
    var selectionKey: String {
        Self.makeSelectionKey(
            sessionId: sessionId,
            todoId: todoId,
            segmentIndex: segmentIndex,
            startedAt: startedAt
        )
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

    static func makeSelectionKey(
        sessionId: String?,
        todoId: String,
        segmentIndex: Int,
        startedAt: Date?
    ) -> String {
        let sourceId = sessionId ?? "todo:\(todoId)"
        let startToken = startedAt.map(DateFormatter.proWorkSQLite.string(from:)) ?? "no-start"
        return "\(sourceId)#\(segmentIndex)#\(startToken)"
    }
}
