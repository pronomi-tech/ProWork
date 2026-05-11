//
//  BillingReportLine.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Bir `BillingReportRun`'un tek satırı. Finalize sonrası snapshot —
/// kaynak kayıtlar (todo, customer, kategori) silinse bile satır sabit kalır.
struct BillingReportLine: Identifiable, Hashable {
    let id: String
    var runId: String

    // Bağlantılar (silinmeleri sorun değil)
    var sessionId: String?
    var todoId: String

    // Snapshot kolonları (finalize anında kopyalanır)
    var todoTitle: String
    var projectId: String?
    var projectName: String?
    var customerId: String
    var customerName: String
    var categoryId: String?
    var categoryName: String?

    // Hesap detayları
    var serviceType: ServiceType
    var timeType: TimeType
    var segmentIndex: Int
    var actualSeconds: Int
    var billableMinutes: Int
    var unitPriceMinor: Int
    var fixedFeeMinor: Int?
    var amountMinor: Int
    var currency: String
    /// "0.20" gibi Decimal string.
    var vatRate: Decimal
    var vatMinor: Int
    var totalMinor: Int
    /// KDV muafiyeti uygulandı mı (snapshot). PDF/raporda "Muaf" göstergesi için.
    var isVatExempt: Bool

    // Bayraklar
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
        originDeviceId: String? = nil
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
        self.fixedFeeMinor = fixedFeeMinor
        self.amountMinor = amountMinor
        self.currency = currency.uppercased()
        self.vatRate = vatRate
        self.vatMinor = vatMinor
        self.totalMinor = totalMinor
        self.isVatExempt = isVatExempt
        self.isBillable = isBillable
        self.isManual = isManual
        self.isFixedFee = isFixedFee
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
