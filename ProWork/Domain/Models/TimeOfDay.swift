//  TimeOfDay.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// A time-of-day value with no date component (00:00 – 23:59).
/// Used for working-hours ranges and price-list time slots.
struct TimeOfDay: Hashable, Comparable, Codable {
    let hour: Int
    let minute: Int

    /// Throws-safe initializer. Use this in any user-facing path (form
    /// parsing, picker selection, deserialisation) so out-of-range input
    /// surfaces as a recoverable error rather than crashing the app
    init(validatedHour hour: Int, minute: Int) throws {
        guard (0...23).contains(hour) else {
            throw TimeOfDayError.outOfRangeHour(hour)
        }
        guard (0...59).contains(minute) else {
            throw TimeOfDayError.outOfRangeMinute(minute)
        }
        self.hour = hour
        self.minute = minute
    }

    /// Crashing initializer kept for compile-time-constant call sites such as
    /// `TimeOfDay(hour: 0, minute: 0)` in `startOfDay`. Hitting a precondition
    /// from these literal call sites indicates a programming error, not user
    /// input — those should go through `init(validatedHour:minute:)`.
    init(hour: Int, minute: Int) {
        precondition((0...23).contains(hour), "TimeOfDay saat 0..23 olmalı, alındı: \(hour)")
        precondition((0...59).contains(minute), "TimeOfDay dakika 0..59 olmalı, alındı: \(minute)")
        self.hour = hour
        self.minute = minute
    }

    /// Parses an "HH:mm" formatted string.
    nonisolated init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0...23).contains(h),
              (0...59).contains(m)
        else {
            return nil
        }
        self.hour = h
        self.minute = m
    }

    var totalMinutes: Int {
        hour * 60 + minute
    }

    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }

    static let startOfDay = TimeOfDay(hour: 0, minute: 0)
    static let endOfDay = TimeOfDay(hour: 23, minute: 59)

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.totalMinutes < rhs.totalMinutes
    }

    /// Returns a `Date` combining this time with the given day.
    ///
    /// Default calendar is `AppCalendar.istanbul` instead of
    /// `Calendar.current`. The billing pipeline already passes an
    /// explicit Istanbul calendar; the UI-side callers (Holiday /
    /// BillingRules forms) previously inherited the system TZ via
    /// `.current`, which silently shifted "13:00 cutoff" if the user
    /// travelled. ProWork is a TR-anchored billing tool, so the
    /// canonical TZ is Istanbul; views that want a user-locale-relative
    /// picker must pass `.current` explicitly.
    func combine(with day: Date, calendar: Calendar = AppCalendar.istanbul) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }
}

extension TimeOfDay {
    /// Default mirrors `combine(with:calendar:)` — Istanbul,
    /// not system TZ. Same drift-resistance reasoning.
    static func from(date: Date, calendar: Calendar = AppCalendar.istanbul) -> TimeOfDay {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

enum TimeOfDayError: LocalizedError {
    case outOfRangeHour(Int)
    case outOfRangeMinute(Int)

    var errorDescription: String? {
        switch self {
        case .outOfRangeHour(let h):
            return ProWorkLocalizer.shared.string(
                "timeOfDay.error.hourOutOfRange",
                defaultValue: "Saat 0–23 aralığında olmalı: \(h)"
            )
        case .outOfRangeMinute(let m):
            return ProWorkLocalizer.shared.string(
                "timeOfDay.error.minuteOutOfRange",
                defaultValue: "Dakika 0–59 aralığında olmalı: \(m)"
            )
        }
    }
}

// MARK: - Codable: "HH:mm" string format

extension TimeOfDay {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = TimeOfDay(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Geçersiz TimeOfDay: \(raw)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(formatted)
    }
}
