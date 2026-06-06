//  BillingRule.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Working-hours range for a single day.
struct DailyWorkHours: Codable, Hashable {
    var start: TimeOfDay
    var end: TimeOfDay

    init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }
}

/// Scope of a billing rule.
enum BillingRuleScope: String, CaseIterable, Identifiable, Hashable {
    case global   // organization-level default
    case customer // customer-specific override

    var id: String { rawValue }
}

/// Defines working/after hours, weekend days, and timezone.
/// Each organization has one global rule; per-customer overrides can be added.
struct BillingRule: Identifiable, Hashable {
    let id: String
    var scope: BillingRuleScope
    var customerId: String?
    /// Working hours per weekday. A weekday with no key is treated as fully off-hours.
    var weekdayHours: [Weekday: DailyWorkHours]
    /// Which days are weekend (e.g. [.saturday, .sunday]).
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
        originDeviceId: String? = DeviceIdentity.current
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

    /// Convenience initializer: entity fields + a single `RecordMetadata`.
    /// replaces the BillingRuleRepository.makeRule →
    /// `withMetadata(...)` two-step workaround so mapping reads as
    /// "construct rule from row" rather than "construct rule with bogus
    /// metadata then overwrite it".
    init(
        id: String,
        scope: BillingRuleScope,
        customerId: String?,
        weekdayHours: [Weekday: DailyWorkHours],
        weekendDays: Set<Weekday>,
        timezone: String,
        isActive: Bool,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            scope: scope,
            customerId: customerId,
            weekdayHours: weekdayHours,
            weekendDays: weekendDays,
            timezone: timezone,
            isActive: isActive,
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

    /// Calendar specific to this rule. Derived from the `timezone` field;
    /// falls back to Istanbul when `timezone` is unknown or empty. This
    /// keeps the rule's timezone independent of the caller's
    /// `Calendar.current`.
    ///
    /// Computed properties on `BillingRule` (a struct) used to
    /// re-allocate the Calendar on every `isWithinWorkHours` /
    /// `isWeekend` call — costly on the billing hot path where a
    /// single line touches the calendar 4-6 times. A timezone-keyed
    /// static cache memoises one Calendar per distinct `timezone`
    /// string so the next caller for the same rule gets the prebuilt
    /// instance. The cache key is the resolved IANA identifier (or the
    /// `defaultTimeZoneIdentifier` for unknown values), so two rules
    /// pointing at the same zone share one entry.
    var calendar: Calendar {
        Self.cachedCalendar(forTimezoneIdentifier: timezone)
    }

    private static let cachedCalendarLock = NSLock()
    private nonisolated(unsafe) static var cachedCalendarsByTimezone: [String: Calendar] = [:]
    private static let defaultTimeZoneIdentifier = AppCalendar.istanbul.timeZone.identifier

    private static func cachedCalendar(forTimezoneIdentifier raw: String) -> Calendar {
        let timezone = TimeZone(identifier: raw) ?? TimeZone(identifier: defaultTimeZoneIdentifier)!
        let key = timezone.identifier
        cachedCalendarLock.lock()
        defer { cachedCalendarLock.unlock() }
        if let cached = cachedCalendarsByTimezone[key] {
            return cached
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        cal.locale = Locale(identifier: "en_US_POSIX")
        cachedCalendarsByTimezone[key] = cal
        return cal
    }

    /// Returns whether the given date falls within working hours. The
    /// calendar is derived from the rule's own `timezone` field.
    func isWithinWorkHours(_ date: Date) -> Bool {
        let cal = calendar
        let weekday = Weekday.from(date: date, calendar: cal)
        guard let hours = weekdayHours[weekday] else { return false }
        let timeOfDay = TimeOfDay.from(date: date, calendar: cal)
        return timeOfDay >= hours.start && timeOfDay < hours.end
    }

    func isWeekend(_ date: Date) -> Bool {
        weekendDays.contains(Weekday.from(date: date, calendar: calendar))
    }
}
