//
//  AppClock.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Uygulama genelinde tek bir saat / takvim / tarih biçimleyici kaynağı.
//  Daha önce `DateFormatter` ve `Calendar` örnekleri farklı dosyalarda kopyalanmış,
//  bazılarında `timeZone = .current` kullanılmış ve DST geçişlerinde gün sınırı
//  kayması riski doğmuştu. Bu dosya tek otoriteli kaynaktır.
//

import Foundation

/// Test ve önizleme akışlarında "şimdi"yi sahteleyebilmek için protokol.
protocol AppClock {
    func now() -> Date
}

struct SystemAppClock: AppClock {
    func now() -> Date { Date() }
}

enum AppCalendar {
    /// SQLite ISO-8601 string'leriyle çalışan UTC takvim.
    /// `proWorkSQLite` formatter'ı ve gün-only formatter'ları bu takvime bağlanır.
    static let sqliteUTC: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    /// Faturalandırma akışında mesai / hafta sonu / tatil bantları Türkiye saat
    /// dilimine göre hesaplanır.
    static let istanbul: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        cal.locale = Locale(identifier: "tr_TR")
        return cal
    }()
}

enum AppDateFormatters {
    /// SQLite TIMESTAMP kolonları için (UTC, milisaniye + offset).
    static let sqliteTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.calendar = AppCalendar.sqliteUTC
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return f
    }()

    /// Gün-only depolama için (kur senkronizasyonu, gün bazlı raporlar). UTC.
    static let sqliteDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = AppCalendar.sqliteUTC
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
