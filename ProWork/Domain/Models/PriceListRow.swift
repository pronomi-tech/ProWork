//  PriceListRow.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// A single row of a price list.
/// Match priority (most specific to most general):
///  - exact category + time type + service type + time-range match
///  - category NULL (applies to all categories)
///  - time-type fallback (TimeType.fallbackOrder)
struct PriceListRow: Identifiable, Hashable {
    let id: String
    var priceListId: String
    var serviceType: ServiceType
    var timeType: TimeType
    var categoryId: String?
    /// Bitmask: bit0=Mon ... bit6=Sun. nil means all days.
    /// When read from the SQL console, values like `weekdayMask=63` are
    /// hard to interpret (Mon–Fri) — annoying for debugging.
    /// `Set<Weekday>` JSON storage would be more readable, but the migration
    /// + update of every comparison site is expensive; for now we keep the
    /// bitmask format and route through the `Weekday.fromMask(_:)` / `toMask`
    /// helpers. JSON conversion should be revisited later.
    var weekdayMask: Int?
    var startTime: TimeOfDay?
    var endTime: TimeOfDay?
    /// Hourly unit price — minor units (e.g. kuruş).
    var unitPriceMinor: Int
    var currency: String
    /// Persisted but **NOT** consulted by
    /// `BillingCalculator`. Session-level window resolution now comes
    /// from Project/Customer.defaultMinBillingMinutes. The field is
    /// kept here so existing rows round-trip cleanly through repo +
    /// schema; do not start writing new values without re-wiring the
    /// calculator first.
    var minimumWindowMinutes: Int?
    var validFrom: String?
    var validTo: String?
    var isActive: Bool
    var sortOrder: Int
    var notes: String?

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
        priceListId: String,
        serviceType: ServiceType,
        timeType: TimeType = .regular,
        categoryId: String? = nil,
        weekdayMask: Int? = nil,
        startTime: TimeOfDay? = nil,
        endTime: TimeOfDay? = nil,
        unitPriceMinor: Int,
        currency: String = "TRY",
        minimumWindowMinutes: Int? = nil,
        validFrom: String? = nil,
        validTo: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0,
        notes: String? = nil,
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
        self.priceListId = priceListId
        self.serviceType = serviceType
        self.timeType = timeType
        self.categoryId = categoryId
        self.weekdayMask = weekdayMask
        self.startTime = startTime
        self.endTime = endTime
        self.unitPriceMinor = unitPriceMinor
        self.currency = currency.uppercased()
        self.minimumWindowMinutes = minimumWindowMinutes
        self.validFrom = validFrom
        self.validTo = validTo
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.notes = notes
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

extension PriceListRow {
    /// Returns the hourly unit price as `Money`.
    var unitPrice: Money {
        Money(minorUnits: unitPriceMinor, currency: currency)
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

    /// WeekdayMask check: does this row apply to the given weekday?
    func appliesTo(weekday: Weekday) -> Bool {
        guard let mask = weekdayMask else { return true }
        let bit = 1 << (weekday.rawValue - 1)
        return (mask & bit) != 0
    }

    static func weekdayMask(from days: Set<Weekday>) -> Int {
        days.reduce(0) { $0 | (1 << ($1.rawValue - 1)) }
    }

    static func weekdays(fromMask mask: Int) -> Set<Weekday> {
        var result: Set<Weekday> = []
        for weekday in Weekday.allCases {
            let bit = 1 << (weekday.rawValue - 1)
            if (mask & bit) != 0 {
                result.insert(weekday)
            }
        }
        return result
    }
}
