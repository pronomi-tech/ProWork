//
//  TimeOfDay.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Tarih içermeden saat:dakika değeri (00:00 – 23:59).
/// Mesai saatleri ve fiyat satırı zaman aralıklarında kullanılır.
struct TimeOfDay: Hashable, Comparable, Codable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        precondition((0...23).contains(hour), "TimeOfDay saat 0..23 olmalı, alındı: \(hour)")
        precondition((0...59).contains(minute), "TimeOfDay dakika 0..59 olmalı, alındı: \(minute)")
        self.hour = hour
        self.minute = minute
    }

    /// "HH:mm" formatında string oluşturur.
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

    /// Verilen tarih ile birleştirilmiş `Date` döner (timezone: kullanıcının current).
    func combine(with day: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }
}

extension TimeOfDay {
    static func from(date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

// MARK: - Codable: "HH:mm" string formatı

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
