//  BillableMinuteAllocatorTests.swift
//  ProWorkTests
//  Süre ağırlığına göre dakika dağıtımı — toplamı korumalı,
//  largest-remainder kararlı olmalı.

import XCTest
@testable import ProWork

final class BillableMinuteAllocatorTests: XCTestCase {

    func test_emptyDurations_returnsEmpty() {
        let result = BillableMinuteAllocator.allocate(durationSeconds: [], totalBillableMinutes: 60)
        XCTAssertEqual(result, [])
    }

    func test_zeroTotal_returnsZeros() {
        let result = BillableMinuteAllocator.allocate(durationSeconds: [300, 600, 900], totalBillableMinutes: 0)
        XCTAssertEqual(result, [0, 0, 0])
    }

    func test_negativeTotal_returnsZeros() {
        let result = BillableMinuteAllocator.allocate(durationSeconds: [300, 600], totalBillableMinutes: -5)
        XCTAssertEqual(result, [0, 0])
    }

    func test_allDurationsZero_dumpsTotalIntoFirstSlot() {
        let result = BillableMinuteAllocator.allocate(durationSeconds: [0, 0, 0], totalBillableMinutes: 60)
        XCTAssertEqual(result, [60, 0, 0])
    }

    func test_negativeDurations_areClampedToZero() {
        // Sadece son slot pozitif → tüm dakika oraya gider
        let result = BillableMinuteAllocator.allocate(durationSeconds: [-100, -50, 1200], totalBillableMinutes: 60)
        XCTAssertEqual(result, [0, 0, 60])
    }

    func test_evenDivision_preservesTotal() {
        // 2 eşit segment, 60 dk → 30+30
        let result = BillableMinuteAllocator.allocate(durationSeconds: [1800, 1800], totalBillableMinutes: 60)
        XCTAssertEqual(result, [30, 30])
        XCTAssertEqual(result.reduce(0, +), 60)
    }

    func test_unevenWeights_distributesProportionally() {
        // 1:2 oran, 60 dk → 20+40
        let result = BillableMinuteAllocator.allocate(durationSeconds: [600, 1200], totalBillableMinutes: 60)
        XCTAssertEqual(result, [20, 40])
        XCTAssertEqual(result.reduce(0, +), 60)
    }

    func test_remainderGoesToLargestRemainder() {
        // 3 eşit segment, 10 dk → 3,3,3 + 1 kalan
        // Eşit kalanlar → stable: en küçük index kazanır
        let result = BillableMinuteAllocator.allocate(durationSeconds: [600, 600, 600], totalBillableMinutes: 10)
        XCTAssertEqual(result.reduce(0, +), 10)
        // Kalan stable şekilde ilk segmente gider
        XCTAssertEqual(result, [4, 3, 3])
    }

    func test_totalIsAlwaysPreserved_acrossManyShapes() {
        let shapes: [([Int], Int)] = [
            ([100, 200, 300, 400, 500], 73),
            ([1, 1, 1, 1, 1, 1, 1], 100),
            ([999, 1, 1], 47),
            ([500, 500], 1),
            ([1000], 60)
        ]
        for (durations, total) in shapes {
            let result = BillableMinuteAllocator.allocate(durationSeconds: durations, totalBillableMinutes: total)
            XCTAssertEqual(result.reduce(0, +), total, "durations=\(durations) total=\(total)")
            XCTAssertEqual(result.count, durations.count)
            for slot in result {
                XCTAssertGreaterThanOrEqual(slot, 0)
            }
        }
    }

    func test_singleSlot_getsEverything() {
        let result = BillableMinuteAllocator.allocate(durationSeconds: [3600], totalBillableMinutes: 90)
        XCTAssertEqual(result, [90])
    }
}
