//  Weekday.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Day of the week. ISO 8601 order: Monday=1 ... Sunday=7.
enum Weekday: Int, CaseIterable, Identifiable, Hashable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .monday: return ProWorkLocalizer.shared.string("weekday.monday", defaultValue: "Pazartesi")
        case .tuesday: return ProWorkLocalizer.shared.string("weekday.tuesday", defaultValue: "Salı")
        case .wednesday: return ProWorkLocalizer.shared.string("weekday.wednesday", defaultValue: "Çarşamba")
        case .thursday: return ProWorkLocalizer.shared.string("weekday.thursday", defaultValue: "Perşembe")
        case .friday: return ProWorkLocalizer.shared.string("weekday.friday", defaultValue: "Cuma")
        case .saturday: return ProWorkLocalizer.shared.string("weekday.saturday", defaultValue: "Cumartesi")
        case .sunday: return ProWorkLocalizer.shared.string("weekday.sunday", defaultValue: "Pazar")
        }
    }

    var shortTitle: String {
        switch self {
        case .monday: return ProWorkLocalizer.shared.string("weekday.short.monday", defaultValue: "Pzt")
        case .tuesday: return ProWorkLocalizer.shared.string("weekday.short.tuesday", defaultValue: "Sal")
        case .wednesday: return ProWorkLocalizer.shared.string("weekday.short.wednesday", defaultValue: "Çar")
        case .thursday: return ProWorkLocalizer.shared.string("weekday.short.thursday", defaultValue: "Per")
        case .friday: return ProWorkLocalizer.shared.string("weekday.short.friday", defaultValue: "Cum")
        case .saturday: return ProWorkLocalizer.shared.string("weekday.short.saturday", defaultValue: "Cmt")
        case .sunday: return ProWorkLocalizer.shared.string("weekday.short.sunday", defaultValue: "Paz")
        }
    }

    /// Apple Calendar's convention is 1=Sunday...7=Saturday.
    /// This helper converts the value returned by Calendar into ISO Weekday.
    ///
    /// `default` branch turns into a `fatalError`. Apple
    /// documents the range as 1...7; any other value means the SDK
    /// changed its contract under us, and silently returning `.monday`
    /// would route Sunday work into Monday holiday rules. Crashing
    /// loud at the boundary surfaces the regression in TestFlight.
    static func from(calendarWeekday raw: Int) -> Weekday {
        switch raw {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default:
            fatalError("Weekday.from(calendarWeekday:) received out-of-range value \(raw); Apple Calendar contract changed.")
        }
    }

    /// Default calendar is `AppCalendar.istanbul` instead of
    /// `Calendar.current` so a user travelling between TZs doesn't
    /// see weekday rules shift around midnight. Billing pipeline
    /// already passes an explicit Istanbul calendar; UI callers
    /// that genuinely want system TZ display must pass `.current`
    /// explicitly.
    static func from(date: Date, calendar: Calendar = AppCalendar.istanbul) -> Weekday {
        let raw = calendar.component(.weekday, from: date)
        return from(calendarWeekday: raw)
    }
}
