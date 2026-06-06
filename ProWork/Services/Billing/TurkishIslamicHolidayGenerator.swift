//  TurkishIslamicHolidayGenerator.swift
//  ProWork
//  Created by Pronomi.
//  Computes the Gregorian dates of Türkiye's religious holidays
//  (Ramadan & Kurban Eid) and their arefes at runtime. Migration001
//  previously hardcoded 2024–2030 dates individually; that approach
//  required a manual update for every year after 2030.
//  Calculation method:
//    1. The Hijri datum of the holiday (Shawwal 1 = Ramadan Eid, Dhu
//       al-Hijjah 10 = Kurban Eid) is fixed.
//    2. The Gregorian counterpart for that year is computed with
//       `Calendar(identifier: .islamicUmmAlQura)`. UmmAlQura is the
//       Foundation calendar closest to the system Diyanet bases its
//       announcements on; the old `.islamicCivil` used tabular month
//       lengths and fell behind by a day or two ~50% of the years.
//    3. Block-based offset override mechanism: in some years Diyanet
//       announces dates shifted by ±1 day due to astronomical
//       observation differences. An override shifts the **entire
//       holiday + arefe** together when added.
//    4. `verifiedThroughGregorianYear` — the last Gregorian year whose
//       dates have been manually compared against Diyanet's
//       announcement and verified. If the produced date is after this
//       year, `IslamicHolidayBootstrap` emits a log warning; the
//       developer should update the Diyanet list, advancing the
//       verified year (adding an override row if necessary).

import Foundation

enum TurkishIslamicHolidayBlockId: String {
    case ramazan
    case kurban
}

struct TurkishIslamicHolidayBlock {
    let id: TurkishIslamicHolidayBlockId
    /// Hijri month number: Shawwal = 10 (day 1 of Ramadan Eid),
    /// Dhu al-Hijjah = 12 (day 1 of Kurban Eid).
    let hijriMonth: Int
    /// Index within the Hijri month of the bayram's first day.
    let hijriDayOfFirstBayram: Int
    /// Day count of the bayram (Ramadan 3, Kurban 4).
    let bayramDayCount: Int
    /// Arefe name.
    let arefeName: String
    /// Bayram name ("1. Gün", "2. Gün", etc. are appended per day).
    let bayramName: String
}

extension TurkishIslamicHolidayBlock {
    static let ramazan = TurkishIslamicHolidayBlock(
        id: .ramazan,
        hijriMonth: 10,                // Shawwal
        hijriDayOfFirstBayram: 1,
        bayramDayCount: 3,
        arefeName: "Ramazan Bayramı Arifesi",
        bayramName: "Ramazan Bayramı"
    )

    static let kurban = TurkishIslamicHolidayBlock(
        id: .kurban,
        hijriMonth: 12,                // Dhu al-Hijjah
        hijriDayOfFirstBayram: 10,
        bayramDayCount: 4,
        arefeName: "Kurban Bayramı Arifesi",
        bayramName: "Kurban Bayramı"
    )

    static let allBlocks: [TurkishIslamicHolidayBlock] = [.ramazan, .kurban]
}

/// Override for years where the date announced by Diyanet differs from
/// UmmAlQura. Overrides are **block-based**: a single row shifts all
/// days of the bayram + its arefe together.
struct DiyanetHolidayOverride: Hashable {
    let gregorianYear: Int
    let blockId: TurkishIslamicHolidayBlockId
    /// Signed shift. -1 = one day earlier, +1 = one day later.
    let dayShift: Int
}

enum TurkishIslamicHolidayGenerator {
    /// Manual correction list for Diyanet vs. UmmAlQura discrepancies.
    /// Empty for now — rows are added when Diyanet's announcement differs.
    /// Format: `(year, block, day shift)`.
    static let diyanetOverrides: [DiyanetHolidayOverride] = []

    /// Last Gregorian year whose dates have been compared against the
    /// Diyanet announcement and verified. For generation beyond this
    /// year, `IslamicHolidayBootstrap` emits a log warning — advance
    /// this value as Diyanet publishes each next year's official holiday
    /// calendar (adding a `diyanetOverrides` row if needed).
    static let verifiedThroughGregorianYear: Int = 2026

    /// Produces day-by-day `Holiday` rows (including arefe) for the
    /// Ramadan & Kurban Eids that start within the given Gregorian year.
    /// If dates were already added via UI / API, the caller
    /// (HolidayBootstrap) must not re-write them.
    static func holidays(
        forGregorianYear year: Int,
        organizationId: String = BuiltInOrganizationId.default,
        now: Date = Date()
    ) -> [Holiday] {
        var result: [Holiday] = []

        for block in TurkishIslamicHolidayBlock.allBlocks {
            // Previously only the first matching Gregorian
            // occurrence was kept. In rare years where the same Hijri
            // bayram falls in the Gregorian year twice (early-Jan + late-
            // Dec wrap), we now emit holiday rows for every occurrence.
            let bayramStarts = gregorianStartsOfBayram(
                block: block,
                gregorianYear: year
            )

            let shift = diyanetOverrides.first {
                $0.gregorianYear == year && $0.blockId == block.id
            }?.dayShift ?? 0

            for bayramStart in bayramStarts {
                guard let shiftedStart = AppCalendar.istanbul.date(
                    byAdding: .day,
                    value: shift,
                    to: bayramStart
                ) else {
                    continue
                }

                // Arefe — the day before day 1 of the bayram. Half-day.
                if let arefeDate = AppCalendar.istanbul.date(byAdding: .day, value: -1, to: shiftedStart) {
                    result.append(makeHoliday(
                        date: arefeDate,
                        name: block.arefeName,
                        isHalfDay: true,
                        organizationId: organizationId,
                        now: now
                    ))
                }

                // Bayram days — full day.
                for dayIndex in 0..<block.bayramDayCount {
                    guard let date = AppCalendar.istanbul.date(
                        byAdding: .day,
                        value: dayIndex,
                        to: shiftedStart
                    ) else { continue }

                    let name = "\(block.bayramName) \(dayIndex + 1). Günü"
                    result.append(makeHoliday(
                        date: date,
                        name: name,
                        isHalfDay: false,
                        organizationId: organizationId,
                        now: now
                    ))
                }
            }
        }

        return result
    }

    /// Finds the Gregorian date of the bayram start that falls inside
    /// the given Gregorian year, using `islamicUmmAlQura`. The Hijri
    /// year is ~622 years smaller than the Gregorian year and slides
    /// back ~11 days each year; consequently the same bayram can occur
    /// **twice** or **not at all** within a Gregorian year. Returns
    /// every Gregorian-year match (0..2 dates) so the caller can emit
    /// holiday rows for each occurrence; the previous single-Date
    /// return silently lost the second occurrence.
    private static func gregorianStartsOfBayram(
        block: TurkishIslamicHolidayBlock,
        gregorianYear: Int
    ) -> [Date] {
        // Y7: The system Diyanet bases its announcements on is very
        // close to UmmAlQura. The tabular `.islamicCivil` month lengths
        // didn't track the actual new moon, producing a 1–2 day drift
        // per year.
        // TZ must be pinned to Istanbul; otherwise date conversions
        // shift by a day depending on the system's current TZ (same
        // motivation as K3).
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = AppCalendar.istanbul.timeZone

        // Which Hijri year are we in on Jan 1 of the target year?
        var components = DateComponents()
        components.year = gregorianYear
        components.month = 1
        components.day = 1
        guard let janFirst = AppCalendar.istanbul.date(from: components) else {
            return []
        }
        let hijriYearAtJanFirst = islamic.component(.year, from: janFirst)

        // A Hijri year can start and end inside the same Gregorian
        // year, so try both this and the next Hijri year (Kurban Eid is
        // Dhu al-Hijjah 10 — close to the end of the Hijri year, so its
        // Gregorian counterpart can shift). Collect every
        // candidate that lands in the target Gregorian year so the caller
        // emits a holiday row for each.
        var matches: [Date] = []
        for hijriYear in [hijriYearAtJanFirst, hijriYearAtJanFirst + 1] {
            var hijriComponents = DateComponents()
            hijriComponents.year = hijriYear
            hijriComponents.month = block.hijriMonth
            hijriComponents.day = block.hijriDayOfFirstBayram

            guard let candidate = islamic.date(from: hijriComponents) else {
                continue
            }

            if AppCalendar.istanbul.component(.year, from: candidate) == gregorianYear {
                // Normalize to start-of-day so later day-offset additions
                // don't drag a time-of-day shift along.
                matches.append(AppCalendar.istanbul.startOfDay(for: candidate))
            }
        }

        return matches
    }

    private static func makeHoliday(
        date: Date,
        name: String,
        isHalfDay: Bool,
        organizationId: String,
        now: Date
    ) -> Holiday {
        // Y7: Holiday dates are TR business days; the UTC sqliteDay
        // formatter could shift them back by a day around midnight
        // (this triggered during the UmmAlQura switch on 2025 Ramadan).
        let dateString = AppDateFormatters.istanbulDay.string(from: date)
        return Holiday(
            scope: .global,
            customerId: nil,
            dateString: dateString,
            name: name,
            isHalfDay: isHalfDay,
            halfDayCutoff: isHalfDay ? TimeOfDay(hour: 13, minute: 0) : nil,
            isActive: true,
            organizationId: organizationId,
            createdByUserId: BuiltInUserId.defaultOwner,
            updatedByUserId: BuiltInUserId.defaultOwner,
            createdAt: now,
            updatedAt: now
        )
    }
}
