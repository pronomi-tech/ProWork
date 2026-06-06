//  TimeWindowSplitter.swift
//  ProWork
//  Created by Pronomi.
//  Spec §5 — Splits a work duration by time type.
//  A session can be split across regular hours, after-hours, weekend
//  and holiday slices.
//  Example:
//      Work: 17:30–19:15, Working hours: 09:00–18:00
//      Result: [17:30–18:00 → regular], [18:00–19:15 → afterHours]
//  Algorithm: event-driven. Splits at the following boundaries:
//    - Midnight (day change)
//    - Working-hours start / end
//    - Holiday day start (00:00)
//    - Half-day holiday cutoff time

import Foundation

struct TimeSegment: Hashable {
    let start: Date
    let end: Date
    let timeType: TimeType

    var durationSeconds: Int {
        Int(end.timeIntervalSince(start))
    }

    /// Duration in minutes, rounded up (even 1 second counts as 1 minute).
    var durationMinutes: Int {
        guard durationSeconds > 0 else { return 0 }
        return (durationSeconds + 59) / 60
    }
}

enum TimeWindowSplitter {
    /// Splits the given work range into segments by time type.
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

            // Idempotent merge: extend the previous segment when its end
            // meets the new cursor and the timeType is the same.
            // the join used to require strict equality
            // (`last.end == cursor`). Date objects coming from session
            // boundaries are technically Doubles since 1970, and any
            // upstream second-rounding drift would skip the merge and
            // append a zero-length segment instead. Allow a sub-second
            // tolerance so the merge survives normal floating noise.
            let cursorMatchesPreviousEnd: Bool
            if let last = segments.last {
                cursorMatchesPreviousEnd = abs(last.end.timeIntervalSince(cursor)) < 0.5
            } else {
                cursorMatchesPreviousEnd = false
            }
            if let last = segments.last,
               last.timeType == currentType,
               cursorMatchesPreviousEnd {
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

        // Holiday check (customer-specific first, then global — assumed
        // pre-filtered by the caller).
        // When two holidays fall on the same date (e.g. 19 May +
        // Eid al-Adha collision), the array order used to depend on the
        // DB row order, which isn't deterministic in practice. We pick a
        // half-day cutoff FIRST — if present, treat the post-cutoff
        // window as holiday, fall through for pre-cutoff. If no half-day
        // is present, "full-day holiday" dominates: any active holiday
        // match means the whole day is a holiday.
        let activeHolidays = holidays
            .filter { $0.dateString == dateString && $0.isActive }
            .sorted { lhs, rhs in
                // Full-day holidays sort ahead of half-days for
                // deterministic tiebreak; within the same type, sort
                // by id — names can be localised, id is immutable.
                if lhs.isHalfDay != rhs.isHalfDay { return !lhs.isHalfDay }
                return lhs.id < rhs.id
            }

        if let fullDay = activeHolidays.first(where: { !$0.isHalfDay }) {
            _ = fullDay
            return .holiday
        }
        if let holiday = activeHolidays.first {
            if holiday.isHalfDay, let cutoff = holiday.halfDayCutoff {
                // Before cutoff: normal logic continues
                // After cutoff: holiday
                if timeOfDay >= cutoff {
                    return .holiday
                }
                // Fall through
            } else {
                return .holiday
            }
        }

        // Weekend check
        if rule.weekendDays.contains(weekday) {
            return .weekend
        }

        // Regular / after-hours
        if let workHours = rule.weekdayHours[weekday] {
            if timeOfDay >= workHours.start && timeOfDay < workHours.end {
                return .regular
            }
        }

        return .afterHours
    }

    // MARK: - Boundaries

    /// The next instant after `date` at which timeType could change.
    private static func nextBoundary(
        after date: Date,
        cap: Date,
        rule: BillingRule,
        holidays: [Holiday],
        calendar: Calendar
    ) -> Date {
        var candidates: [Date] = []

        // 1. Midnight (day change)
        if let nextDayStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) {
            if nextDayStart > date {
                candidates.append(nextDayStart)
            }
        }

        // 2. Today's working-hours start / end
        let weekday = Weekday.from(date: date, calendar: calendar)
        if let workHours = rule.weekdayHours[weekday] {
            let workStart = workHours.start.combine(with: date, calendar: calendar)
            let workEnd = workHours.end.combine(with: date, calendar: calendar)
            if workStart > date { candidates.append(workStart) }
            if workEnd > date { candidates.append(workEnd) }
        }

        // 3. Today's half-day holiday cutoff
        let dateString = Holiday.dateFormatter.string(from: date)
        for holiday in holidays where holiday.dateString == dateString && holiday.isActive {
            if holiday.isHalfDay, let cutoff = holiday.halfDayCutoff {
                let cutoffDate = cutoff.combine(with: date, calendar: calendar)
                if cutoffDate > date {
                    candidates.append(cutoffDate)
                }
            }
        }

        // Pick the nearest; must not exceed the cap
        let upper = cap
        let valid = candidates.filter { $0 > date && $0 <= upper }
        return valid.min() ?? upper
    }

    // MARK: - Calendar

    /// `AppCalendar.istanbul` is the single authoritative source; this
    /// alias is kept to avoid breaking existing callers. New code should
    /// reference `AppCalendar` directly.
    static var istanbulCalendar: Calendar { AppCalendar.istanbul }
}
