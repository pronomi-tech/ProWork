//
//  AppTimeFormatOption.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum AppTimeFormatOption: String, CaseIterable, Identifiable {
    case twentyFourHour = "HH:mm"
    case twelveHour = "hh:mm a"

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
