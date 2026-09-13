//  BillingTimelineWindowPlannerTests.swift
//  ProWorkTests

import XCTest
@testable import ProWork

final class BillingTimelineWindowPlannerTests: XCTestCase {
    private let calendar = TimeWindowSplitter.istanbulCalendar

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = h
        components.minute = mi
        components.second = s
        components.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return calendar.date(from: components)!
    }

    func test_sessionsInsideSameOpenWindow_shareSingleMinimumWindow() {
        let groupKey = BillingTimelineWindowRequest.GroupKey(customerId: "C1", windowMinutes: 60)
        let requests = [
            BillingTimelineWindowRequest(
                sessionId: "s1",
                groupKey: groupKey,
                startedAt: date(2026, 5, 8, 10, 0),
                endedAt: date(2026, 5, 8, 10, 10),
                actualSeconds: 10 * 60
            ),
            BillingTimelineWindowRequest(
                sessionId: "s2",
                groupKey: groupKey,
                startedAt: date(2026, 5, 8, 10, 20),
                endedAt: date(2026, 5, 8, 10, 50),
                actualSeconds: 30 * 60
            )
        ]

        let result = BillingTimelineWindowPlanner.plan(requests: requests)

        XCTAssertEqual(result["s1"], 600)
        XCTAssertEqual(result["s2"], 3_000)
        XCTAssertEqual(result.values.reduce(0, +), 3_600)
    }

    func test_laterSessionWithinPreviousStartWindow_keepsActualFirstAndPadsLast() {
        let groupKey = BillingTimelineWindowRequest.GroupKey(customerId: "C1", windowMinutes: 60)
        let requests = [
            BillingTimelineWindowRequest(
                sessionId: "s1",
                groupKey: groupKey,
                startedAt: date(2026, 5, 8, 10, 0),
                endedAt: date(2026, 5, 8, 10, 10),
                actualSeconds: 10 * 60
            ),
            BillingTimelineWindowRequest(
                sessionId: "s2",
                groupKey: groupKey,
                startedAt: date(2026, 5, 8, 10, 50),
                endedAt: date(2026, 5, 8, 11, 20),
                actualSeconds: 30 * 60
            )
        ]

        let result = BillingTimelineWindowPlanner.plan(requests: requests)

        XCTAssertEqual(result["s1"], 600)
        XCTAssertEqual(result["s2"], 3_000)
        XCTAssertEqual(result.values.reduce(0, +), 3_600)
    }

    func test_laterSessionInsideLongRecordsSecondWindow_keepsActualFirstAndPadsLast() {
        let groupKey = BillingTimelineWindowRequest.GroupKey(customerId: "C1", windowMinutes: 60)
        let requests = [
            BillingTimelineWindowRequest(
                sessionId: "s1",
                groupKey: groupKey,
                startedAt: date(2026, 9, 2, 12, 24, 6),
                endedAt: date(2026, 9, 2, 13, 40, 19),
                actualSeconds: 4_573
            ),
            BillingTimelineWindowRequest(
                sessionId: "s2",
                groupKey: groupKey,
                startedAt: date(2026, 9, 2, 13, 40, 28),
                endedAt: date(2026, 9, 2, 13, 51, 22),
                actualSeconds: 654
            )
        ]

        let result = BillingTimelineWindowPlanner.plan(requests: requests)

        XCTAssertEqual(result["s1"], 4_573)
        XCTAssertEqual(result["s2"], 2_627)
        XCTAssertEqual(result.values.reduce(0, +), 7_200)
    }

    func test_chainRestartsAfterActiveWindowEnds() {
        let groupKey = BillingTimelineWindowRequest.GroupKey(customerId: "C1", windowMinutes: 60)
        let requests = [
            BillingTimelineWindowRequest(
                sessionId: "s1",
                groupKey: groupKey,
                startedAt: date(2026, 5, 8, 10, 0),
                endedAt: date(2026, 5, 8, 10, 10),
                actualSeconds: 10 * 60
            ),
            BillingTimelineWindowRequest(
                sessionId: "s2",
                groupKey: groupKey,
                startedAt: date(2026, 5, 8, 11, 30),
                endedAt: date(2026, 5, 8, 11, 40),
                actualSeconds: 10 * 60
            )
        ]

        let result = BillingTimelineWindowPlanner.plan(requests: requests)

        XCTAssertEqual(result["s1"], 3_600)
        XCTAssertEqual(result["s2"], 3_600)
        XCTAssertEqual(result.values.reduce(0, +), 7_200)
    }

    func test_timelineChainsEachRecordFromPreviousStart_andPadsOnlyFinalRecord() {
        let groupKey = BillingTimelineWindowRequest.GroupKey(customerId: "C1", windowMinutes: 60)
        let requests = [
            BillingTimelineWindowRequest(
                sessionId: "s1", groupKey: groupKey,
                startedAt: date(2026, 5, 8, 10, 0), endedAt: date(2026, 5, 8, 10, 10),
                actualSeconds: 10 * 60
            ),
            BillingTimelineWindowRequest(
                sessionId: "s2", groupKey: groupKey,
                startedAt: date(2026, 5, 8, 10, 50), endedAt: date(2026, 5, 8, 11, 20),
                actualSeconds: 30 * 60
            ),
            BillingTimelineWindowRequest(
                sessionId: "s3", groupKey: groupKey,
                startedAt: date(2026, 5, 8, 11, 40), endedAt: date(2026, 5, 8, 12, 15),
                actualSeconds: 35 * 60
            )
        ]

        let result = BillingTimelineWindowPlanner.plan(requests: requests)

        XCTAssertEqual(result["s1"], 600)
        XCTAssertEqual(result["s2"], 1_800)
        XCTAssertEqual(result["s3"], 4_800)
        XCTAssertEqual(result.values.reduce(0, +), 7_200)
    }

    func test_reportModeIgnoresGaps_andPadsOnlyFinalRecord() {
        let groupKey = BillingTimelineWindowRequest.GroupKey(customerId: "C1", windowMinutes: 60)
        let requests = [
            BillingTimelineWindowRequest(
                sessionId: "s1", groupKey: groupKey,
                startedAt: date(2026, 5, 8, 9, 0), endedAt: date(2026, 5, 8, 9, 10),
                actualSeconds: 10 * 60
            ),
            BillingTimelineWindowRequest(
                sessionId: "s2", groupKey: groupKey,
                startedAt: date(2026, 5, 10, 14, 0), endedAt: date(2026, 5, 10, 15, 5),
                actualSeconds: 65 * 60
            )
        ]

        let result = BillingTimelineWindowPlanner.planReport(requests: requests)

        XCTAssertEqual(result["s1"], 600)
        XCTAssertEqual(result["s2"], 6_600)
        XCTAssertEqual(result.values.reduce(0, +), 7_200)
    }

    func test_reportModeRoundsCurrenciesIndependently() {
        let requests = [
            BillingTimelineWindowRequest(
                sessionId: "try", groupKey: .init(customerId: "C1", windowMinutes: 60, currency: "TRY"),
                startedAt: date(2026, 5, 8, 9, 0), endedAt: date(2026, 5, 8, 9, 10),
                actualSeconds: 10 * 60
            ),
            BillingTimelineWindowRequest(
                sessionId: "usd", groupKey: .init(customerId: "C1", windowMinutes: 60, currency: "USD"),
                startedAt: date(2026, 5, 8, 10, 0), endedAt: date(2026, 5, 8, 10, 20),
                actualSeconds: 20 * 60
            )
        ]

        let result = BillingTimelineWindowPlanner.planReport(requests: requests)

        XCTAssertEqual(result["try"], 3_600)
        XCTAssertEqual(result["usd"], 3_600)
    }
}
