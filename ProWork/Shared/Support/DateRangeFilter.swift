//
//  DateRangeFilter.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Tüm uygulama genelinde tarih aralığı filtreleri için ortak yardımcı tip.
//  WorkSessionsView ve Reports ekranları aynı enum'u kullanır.
//

import Foundation

enum DateRangeFilter: Equatable, Hashable {
    case all
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case pastMonths(Int)
    case custom

    static func == (lhs: DateRangeFilter, rhs: DateRangeFilter) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all), (.today, .today), (.yesterday, .yesterday),
             (.thisWeek, .thisWeek), (.thisMonth, .thisMonth), (.custom, .custom):
            return true
        case (.pastMonths(let a), .pastMonths(let b)):
            return a == b
        default:
            return false
        }
    }
}

extension DateRangeFilter {
    /// Başlangıç tarihi. `.all` ve `.custom` için custom değer kullanılır.
    func startDate(custom: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .all:
            return Date.distantPast
        case .today:
            return calendar.startOfDay(for: Date())
        case .yesterday:
            let y = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return calendar.startOfDay(for: y)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        case .pastMonths(let n):
            return calendar.date(byAdding: .month, value: -n, to: Date()) ?? Date()
        case .custom:
            return calendar.startOfDay(for: custom)
        }
    }

    /// Bitiş tarihi (exclusive). `.all` distantFuture döner.
    func endDate(custom: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .all:
            return Date.distantFuture
        case .today:
            return calendar.date(byAdding: .day, value: 1, to: startDate(custom: Date(), calendar: calendar)) ?? Date()
        case .yesterday:
            return calendar.startOfDay(for: Date())
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: Date())?.end ?? Date()
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: Date())?.end ?? Date()
        case .pastMonths:
            return Date()
        case .custom:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: custom)) ?? custom
        }
    }

    /// Verilen tarihin seçili aralık içinde kalıp kalmadığını döner.
    func contains(
        _ date: Date,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .custom:
            let start = startDate(custom: customStart, calendar: calendar)
            let end = endDate(custom: customEnd, calendar: calendar)
            return date >= start && date < end
        default:
            let start = startDate(custom: customStart, calendar: calendar)
            let end = endDate(custom: customEnd, calendar: calendar)
            return date >= start && date < end
        }
    }
}
