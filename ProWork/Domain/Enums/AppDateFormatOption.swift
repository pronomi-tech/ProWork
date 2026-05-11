//
//  AppDateFormatOption.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum AppDateFormatOption: String, CaseIterable, Identifiable {
    case dayMonthYearDot = "dd.MM.yyyy"
    case dayMonthYearSlash = "dd/MM/yyyy"
    case yearMonthDayDash = "yyyy-MM-dd"
    case dayShortMonthYear = "d MMM yyyy"

    var id: String {
        rawValue
    }

    func title(locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateFormat = rawValue

        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 31

        let sampleDate = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: sampleDate)
    }
}
