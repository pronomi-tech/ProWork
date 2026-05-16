//
//  TimeWindowSplitter.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Spec §5 — Çalışma süresini zaman tiplerine böler.
//  Bir oturum mesai içi, mesai dışı, hafta sonu ve tatil dilimlerine ayrılabilir.
//
//  Örnek:
//      Çalışma: 17:30–19:15, Mesai: 09:00–18:00
//      Sonuç: [17:30–18:00 → regular], [18:00–19:15 → afterHours]
//
//  Algoritma: olay-tabanlı (event-driven). Şu sınırlarda parçalar:
//    - Gece yarısı (gün değişimi)
//    - Mesai başlangıcı / bitişi
//    - Tatil günü başlangıcı (00:00)
//    - Yarım gün tatil cutoff saati
//

import Foundation

struct TimeSegment: Hashable {
    let start: Date
    let end: Date
    let timeType: TimeType

    var durationSeconds: Int {
        Int(end.timeIntervalSince(start))
    }

    /// Yukarı yuvarlanmış dakika (1 saniye bile 1 dakika).
    var durationMinutes: Int {
        guard durationSeconds > 0 else { return 0 }
        return (durationSeconds + 59) / 60
    }
}

enum TimeWindowSplitter {
    /// Verilen çalışma aralığını zaman tiplerine göre parçalara böler.
    static func split(
        from start: Date,
        to end: Date,
        rule: BillingRule,
        holidays: [Holiday],
        calendar: Calendar = TimeWindowSplitter.istanbulCalendar
    ) -> [TimeSegment] {
        guard end > start else { return [] }

        var segments: [TimeSegment] = []
        var cursor = start

        while cursor < end {
            let currentType = timeType(at: cursor, rule: rule, holidays: holidays, calendar: calendar)
            let nextChange = nextBoundary(
                after: cursor,
                cap: end,
                rule: rule,
                holidays: holidays,
                calendar: calendar
            )
            let segmentEnd = min(nextChange, end)

            // Aynı tip ardışık geliyorsa son segmenti uzat (idempotent merge)
            if let last = segments.last, last.timeType == currentType, last.end == cursor {
                segments[segments.count - 1] = TimeSegment(
                    start: last.start,
                    end: segmentEnd,
                    timeType: currentType
                )
            } else {
                segments.append(TimeSegment(
                    start: cursor,
                    end: segmentEnd,
                    timeType: currentType
                ))
            }

            cursor = segmentEnd
        }

        return segments
    }

    // MARK: - Time type

    static func timeType(
        at date: Date,
        rule: BillingRule,
        holidays: [Holiday],
        calendar: Calendar = TimeWindowSplitter.istanbulCalendar
    ) -> TimeType {
        let dateString = Holiday.dateFormatter.string(from: date)
        let timeOfDay = TimeOfDay.from(date: date, calendar: calendar)
        let weekday = Weekday.from(date: date, calendar: calendar)

        // Tatil kontrolü (önce müşteri-spesifik, sonra global — caller filtrelemiş kabul edilir)
        let activeHolidays = holidays.filter { $0.dateString == dateString && $0.isActive }

        if let holiday = activeHolidays.first {
            if holiday.isHalfDay, let cutoff = holiday.halfDayCutoff {
                // Cutoff'tan önce: normal mantık devam eder
                // Cutoff'tan sonra: tatil
                if timeOfDay >= cutoff {
                    return .holiday
                }
                // Aşağıya düş
            } else {
                return .holiday
            }
        }

        // Hafta sonu kontrolü
        if rule.weekendDays.contains(weekday) {
            return .weekend
        }

        // Mesai içi/dışı
        if let workHours = rule.weekdayHours[weekday] {
            if timeOfDay >= workHours.start && timeOfDay < workHours.end {
                return .regular
            }
        }

        return .afterHours
    }

    // MARK: - Boundaries

    /// `date`'ten sonra timeType'ın değişebileceği bir sonraki andır.
    private static func nextBoundary(
        after date: Date,
        cap: Date,
        rule: BillingRule,
        holidays: [Holiday],
        calendar: Calendar
    ) -> Date {
        var candidates: [Date] = []

        // 1. Gece yarısı (gün değişimi)
        if let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) {
            if nextDayStart > date {
                candidates.append(nextDayStart)
            }
        }

        // 2. Bugünkü mesai başlangıcı / bitişi
        let weekday = Weekday.from(date: date, calendar: calendar)
        if let workHours = rule.weekdayHours[weekday] {
            let workStart = workHours.start.combine(with: date, calendar: calendar)
            let workEnd = workHours.end.combine(with: date, calendar: calendar)
            if workStart > date { candidates.append(workStart) }
            if workEnd > date { candidates.append(workEnd) }
        }

        // 3. Bugünkü tatil yarım gün cutoff'u
        let dateString = Holiday.dateFormatter.string(from: date)
        for holiday in holidays where holiday.dateString == dateString && holiday.isActive {
            if holiday.isHalfDay, let cutoff = holiday.halfDayCutoff {
                let cutoffDate = cutoff.combine(with: date, calendar: calendar)
                if cutoffDate > date {
                    candidates.append(cutoffDate)
                }
            }
        }

        // En yakını seç; cap'i aşmasın
        let upper = cap
        let valid = candidates.filter { $0 > date && $0 <= upper }
        return valid.min() ?? upper
    }

    // MARK: - Calendar

    /// Tek otoriteli kaynak `AppCalendar.istanbul`; mevcut caller'ları
    /// kırmamak için bu alias korunuyor. Yeni kod doğrudan `AppCalendar`
    /// üzerinden referans vermeli.
    static var istanbulCalendar: Calendar { AppCalendar.istanbul }
}
