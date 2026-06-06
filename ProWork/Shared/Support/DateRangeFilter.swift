//  DateRangeFilter.swift
//  ProWork
//  Created by Pronomi.
//  Shared helper type for date-range filters used across the app.
//  WorkSessionsView and the Reports screens share this enum.
//  each case previously rebuilt its bounds from a fresh
//  `Date()` per call, so two consecutive bounds reads could straddle a clock
//  tick and disagree. The helpers now accept a `now: Date = Date()` parameter
//  so callers can snapshot once and reuse the same instant. The bespoke
//  `Equatable.==` override is also gone — the enum's auto-synthesised
//  conformance handles `pastMonths(Int)` correctly.

import Foundation

enum DateRangeFilter: Equatable, Hashable {
    case all
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case pastMonths(Int)
    case custom
}

extension DateRangeFilter {
    /// Start date. For `.all` and `.custom` the custom value is used.
    /// The `now` argument lets a single filter render share one "now"
    /// across the start/end calls.
    func startDate(
        custom: Date,
        calendar: Calendar = AppCalendar.istanbul,
        now: Date = Date()
    ) -> Date {
        switch self {
        case .all:
            return Date.distantPast
        case .today:
            return calendar.startOfDay(for: now)
        case .yesterday:
            let y = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return calendar.startOfDay(for: y)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .pastMonths(let n):
            return calendar.date(byAdding: .month, value: -n, to: now) ?? now
        case .custom:
            return calendar.startOfDay(for: custom)
        }
    }

    /// End date (exclusive). `.all` returns distantFuture.
    func endDate(
        custom: Date,
        calendar: Calendar = AppCalendar.istanbul,
        now: Date = Date()
    ) -> Date {
        switch self {
        case .all:
            return Date.distantFuture
        case .today:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        case .yesterday:
            return calendar.startOfDay(for: now)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.end ?? now
        case .pastMonths:
            return now
        case .custom:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: custom)) ?? custom
        }
    }

    /// Returns whether the given date falls within the selected range.
    func contains(
        _ date: Date,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar = AppCalendar.istanbul,
        now: Date = Date()
    ) -> Bool {
        if case .all = self { return true }
        let start = startDate(custom: customStart, calendar: calendar, now: now)
        let end = endDate(custom: customEnd, calendar: calendar, now: now)
        return date >= start && date < end
    }
}
