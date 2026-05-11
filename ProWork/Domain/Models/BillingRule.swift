//
//  BillingRule.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Bir günün mesai saati aralığı.
struct DailyWorkHours: Codable, Hashable {
    var start: TimeOfDay
    var end: TimeOfDay

    init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }
}

/// Mesai kuralı kapsamı.
enum BillingRuleScope: String, CaseIterable, Identifiable, Hashable {
    case global   // organization seviyesi varsayılan
    case customer // belirli müşteri override

    var id: String { rawValue }
}

/// Mesai içi/dışı, hafta sonu ve zaman dilimi tanımı.
/// Her organization'ın bir global kuralı vardır; her müşteri için override eklenebilir.
struct BillingRule: Identifiable, Hashable {
    let id: String
    var scope: BillingRuleScope
    var customerId: String?
    /// Her haftagünü için mesai saatleri. Bir günün anahtarı yoksa o gün mesai dışı sayılır.
    var weekdayHours: [Weekday: DailyWorkHours]
    /// Hangi günler hafta sonu (örn. [.saturday, .sunday]).
    var weekendDays: Set<Weekday>
    var timezone: String
    var isActive: Bool

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
        scope: BillingRuleScope = .global,
        customerId: String? = nil,
        weekdayHours: [Weekday: DailyWorkHours] = BillingRule.defaultWeekdayHours,
        weekendDays: Set<Weekday> = [.saturday, .sunday],
        timezone: String = "Europe/Istanbul",
        isActive: Bool = true,
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
        self.scope = scope
        self.customerId = customerId
        self.weekdayHours = weekdayHours
        self.weekendDays = weekendDays
        self.timezone = timezone
        self.isActive = isActive
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

extension BillingRule {
    static let defaultWeekdayHours: [Weekday: DailyWorkHours] = {
        let standard = DailyWorkHours(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0)
        )
        return [
            .monday: standard,
            .tuesday: standard,
            .wednesday: standard,
            .thursday: standard,
            .friday: standard
        ]
    }()

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

    /// Verilen tarihin mesai dilimi içinde olup olmadığını döner.
    func isWithinWorkHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = Weekday.from(date: date, calendar: calendar)
        guard let hours = weekdayHours[weekday] else { return false }
        let timeOfDay = TimeOfDay.from(date: date, calendar: calendar)
        return timeOfDay >= hours.start && timeOfDay < hours.end
    }

    func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        weekendDays.contains(Weekday.from(date: date, calendar: calendar))
    }
}
