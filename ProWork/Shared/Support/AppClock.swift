//  AppClock.swift
//  ProWork
//  Created by Pronomi.
//  Single source for clock / calendar / date formatter across the app.
//  Previously, `DateFormatter` and `Calendar` instances were copied across
//  files; some used `timeZone = .current`, which risked day-boundary
//  drift across DST transitions. This file is the single authority.

import Foundation

/// Protocol so test and preview flows can fake "now".
protocol AppClock {
    func now() -> Date
}

struct SystemAppClock: AppClock {
    func now() -> Date { Date() }
}

enum AppCalendar {
    /// UTC calendar used with SQLite ISO-8601 strings.
    /// The `proWorkSQLite` formatter and the day-only formatters bind to this calendar.
    /// The `TimeZone(secondsFromGMT: 0)` failable initializer always returns
    /// a value (zero offset is valid on every platform); the previous
    /// `?? .current` fallback was dead code. Switched to force-unwrap so the
    /// intent is explicit — if UTC isn't valid, Foundation itself is broken.
    static let sqliteUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    /// Working / weekend / holiday bands in the billing flow are computed
    /// against the Türkiye time zone.
    ///
    /// Force-unwrap mirrors the `sqliteUTC` style. The IANA
    /// identifier "Europe/Istanbul" is a documented Foundation zone
    /// that has shipped on every supported macOS; failure here means
    /// the OS time-zone database is broken and silently falling back
    /// to `.current` would mask a billing bug in a way that's far
    /// worse than a crash (user travels → working-hour bands silently
    /// shift). Crashing is the safe failure mode.
    static let istanbul: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        cal.locale = Locale(identifier: "tr_TR")
        return cal
    }()
}

enum AppDateFormatters {
    /// For SQLite TIMESTAMP columns (UTC, milliseconds + offset).
    static let sqliteTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.calendar = AppCalendar.sqliteUTC
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return f
    }()

    /// For day-only storage (exchange rate sync, day-grain reports). UTC.
    static let sqliteDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = AppCalendar.sqliteUTC
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "yyyy-MM-dd" output corresponding to a Türkiye business day. Used
    /// for holiday dates and the user-visible day in billing reports —
    /// `sqliteDay` stays UTC so UTC-anchored records (rates, sync) aren't
    /// shifted.
    static let istanbulDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = AppCalendar.istanbul
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppCalendar.istanbul.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
