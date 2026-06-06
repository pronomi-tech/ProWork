//  AppDateFormatOption.swift
//  ProWork
//  Created by Pronomi.

import Foundation

enum AppDateFormatOption: String, CaseIterable, Identifiable {
    case dayMonthYearDot = "dd.MM.yyyy"
    case dayMonthYearSlash = "dd/MM/yyyy"
    case yearMonthDayDash = "yyyy-MM-dd"
    case dayShortMonthYear = "d MMM yyyy"

    var id: String {
        rawValue
    }

    /// Format-picker labels reuse `ProWorkFormatters.cachedDateFormatter`
    /// so listing four options doesn't allocate four DateFormatter
    /// instances per render.: anchor the calendar/timezone
    /// pair to UTC so the sample date is deterministic (the previous
    /// `.current` calendar would jitter labels at midnight TZ
    /// boundaries during DST transitions). The displayed sample is
    /// purely cosmetic — keeping it locale-aware via the formatter
    /// while keeping the source date stable is the right trade-off.
    func title(locale: Locale) -> String {
        let formatter = ProWorkFormatters.cachedDateFormatter(
            localeIdentifier: locale.identifier,
            dateFormat: rawValue
        )

        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 31

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let sampleDate = utcCalendar.date(from: components) ?? Date()
        return formatter.string(from: sampleDate)
    }
}
