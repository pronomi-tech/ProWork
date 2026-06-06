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

        XCTAssertEqual(result["s1"], 15)
        XCTAssertEqual(result["s2"], 45)
        XCTAssertEqual(result.values.reduce(0, +), 60)
    }

    func test_sessionCrossingWindowBoundary_extendsSharedTimelineWindow() {
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

        XCTAssertEqual(result["s1"], 30)
        XCTAssertEqual(result["s2"], 90)
        XCTAssertEqual(result.values.reduce(0, +), 120)
    }

    func test_windowRestartsAfterCoveredTimelineEnds() {
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

        XCTAssertEqual(result["s1"], 60)
        XCTAssertEqual(result["s2"], 60)
        XCTAssertEqual(result.values.reduce(0, +), 120)
    }
}
