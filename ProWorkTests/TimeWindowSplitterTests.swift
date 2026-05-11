//
//  TimeWindowSplitterTests.swift
//  ProWorkTests
//
//  Spec §5 — Çalışma süresinin zaman tiplerine bölünmesi.
//

import XCTest
@testable import ProWork

final class TimeWindowSplitterTests: XCTestCase {

    private let calendar: Calendar = TimeWindowSplitter.istanbulCalendar

    /// Pzt-Cum 09:00–18:00, Cmt+Paz hafta sonu, tatil yok.
    private func defaultRule() -> BillingRule {
        let workHours = DailyWorkHours(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0)
        )
        return BillingRule(
            scope: .global,
            customerId: nil,
            weekdayHours: [
                .monday: workHours,
                .tuesday: workHours,
                .wednesday: workHours,
                .thursday: workHours,
                .friday: workHours
            ],
            weekendDays: [.saturday, .sunday],
            timezone: "Europe/Istanbul"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return calendar.date(from: components)!
    }

    // MARK: - Spec §5 örneği

    /// 17:30–19:15 ⇒ [17:30–18:00 regular], [18:00–19:15 afterHours]
    func test_specCase_crossesWorkEnd_splitsIntoRegularAndAfterHours() {
        // 7 Mayıs 2026 Perşembe
        let start = date(2026, 5, 7, 17, 30)
        let end = date(2026, 5, 7, 19, 15)

        let segments = TimeWindowSplitter.split(
            from: start, to: end,
            rule: defaultRule(),
            holidays: [],
            calendar: calendar
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].timeType, .regular)
        XCTAssertEqual(segments[0].start, start)
        XCTAssertEqual(segments[0].end, date(2026, 5, 7, 18, 0))
        XCTAssertEqual(segments[1].timeType, .afterHours)
        XCTAssertEqual(segments[1].start, date(2026, 5, 7, 18, 0))
        XCTAssertEqual(segments[1].end, end)
    }

    func test_entirelyWithinWorkHours_isSingleRegularSegment() {
        // Perşembe 10:00–14:00
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 14, 0)

        let segments = TimeWindowSplitter.split(
            from: start, to: end,
            rule: defaultRule(), holidays: [], calendar: calendar
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timeType, .regular)
        XCTAssertEqual(segments[0].durationSeconds, 4 * 3600)
    }

    func test_morningCrossesWorkStart_splitsAfterHoursAndRegular() {
        // Perşembe 08:00–10:00 ⇒ 08:00–09:00 afterHours, 09:00–10:00 regular
        let start = date(2026, 5, 7, 8, 0)
        let end = date(2026, 5, 7, 10, 0)

        let segments = TimeWindowSplitter.split(
            from: start, to: end,
            rule: defaultRule(), holidays: [], calendar: calendar
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].timeType, .afterHours)
        XCTAssertEqual(segments[1].timeType, .regular)
    }

    func test_weekendDay_isSingleWeekendSegment() {
        // Cumartesi (9 Mayıs 2026) 10:00–12:00
        let start = date(2026, 5, 9, 10, 0)
        let end = date(2026, 5, 9, 12, 0)

        let segments = TimeWindowSplitter.split(
            from: start, to: end,
            rule: defaultRule(), holidays: [], calendar: calendar
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timeType, .weekend)
    }

    func test_holiday_overridesWorkHours() {
        // Perşembe normalde mesai içi olur ama 7 Mayıs 2026'yı tatil yap
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 12, 0)

        let holiday = Holiday(
            scope: .global,
            dateString: "2026-05-07",
            name: "Test Tatili",
            isHalfDay: false
        )

        let segments = TimeWindowSplitter.split(
            from: start, to: end,
            rule: defaultRule(),
            holidays: [holiday],
            calendar: calendar
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timeType, .holiday)
    }

    func test_halfDayHoliday_splitsAtCutoff() {
        // 28 Ekim 2026 Çarşamba — Cumhuriyet Bayramı Arifesi (yarım gün 13:00 sonrası tatil)
        let start = date(2026, 10, 28, 11, 0)
        let end = date(2026, 10, 28, 15, 0)

        let holiday = Holiday(
            scope: .global,
            dateString: "2026-10-28",
            name: "Cumhuriyet Bayramı Arifesi",
            isHalfDay: true,
            halfDayCutoff: TimeOfDay(hour: 13, minute: 0)
        )

        let segments = TimeWindowSplitter.split(
            from: start, to: end,
            rule: defaultRule(),
            holidays: [holiday],
            calendar: calendar
        )

        // 11:00–13:00 regular, 13:00–15:00 holiday
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].timeType, .regular)
        XCTAssertEqual(segments[0].end, date(2026, 10, 28, 13, 0))
        XCTAssertEqual(segments[1].timeType, .holiday)
        XCTAssertEqual(segments[1].start, date(2026, 10, 28, 13, 0))
    }
}
