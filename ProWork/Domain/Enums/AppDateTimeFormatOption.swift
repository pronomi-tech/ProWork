//
//  AppDateTimeFormatOption.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum AppDateTimeFormatOption: String, CaseIterable, Identifiable {
    case dotDateTwentyFourHour = "dd.MM.yyyy HH:mm"
    case slashDateTwentyFourHour = "dd/MM/yyyy HH:mm"
    case dashDateTwentyFourHour = "yyyy-MM-dd HH:mm"
    case shortMonthTwentyFourHour = "d MMM yyyy HH:mm"

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
        components.hour = 23
        components.minute = 45

        let sampleDate = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: sampleDate)
    }
}
