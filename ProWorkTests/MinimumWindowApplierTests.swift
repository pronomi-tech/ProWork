//
//  MinimumWindowApplierTests.swift
//  ProWorkTests
//
//  Spec §4 — minimum ücretlendirme penceresi.
//  Spec'te verilen üç vaka (10dk/61dk/130dk) birebir testlenir.
//

import XCTest
@testable import ProWork

final class MinimumWindowApplierTests: XCTestCase {

    // MARK: - Spec §4 örnekleri

    func test_specCase_10MinutesIn60MinuteWindow_isOneFullWindow() {
        let result = MinimumWindowApplier.apply(actualMinutes: 10, windowMinutes: 60)
        XCTAssertEqual(result, 60)
    }

    func test_specCase_61MinutesIn60MinuteWindow_isTwoFullWindows() {
        let result = MinimumWindowApplier.apply(actualMinutes: 61, windowMinutes: 60)
        XCTAssertEqual(result, 120)
    }

    func test_specCase_130MinutesIn60MinuteWindow_isThreeFullWindows() {
        let result = MinimumWindowApplier.apply(actualMinutes: 130, windowMinutes: 60)
        XCTAssertEqual(result, 180)
    }

    // MARK: - Sınır vakalar

    func test_exactWindowBoundary_doesNotRoundUp() {
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 60, windowMinutes: 60), 60)
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 120, windowMinutes: 60), 120)
    }

    func test_zeroActualMinutes_isZero() {
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 0, windowMinutes: 60), 0)
    }

    func test_nilWindow_returnsActualUnchanged() {
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 47, windowMinutes: nil), 47)
    }

    func test_smallerWindow_30Minutes() {
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 1, windowMinutes: 30), 30)
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 30, windowMinutes: 30), 30)
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 31, windowMinutes: 30), 60)
        XCTAssertEqual(MinimumWindowApplier.apply(actualMinutes: 90, windowMinutes: 30), 90)
    }

    // MARK: - Saniye girişi

    func test_secondsInput_partialSecondsRoundUpToMinute() {
        // 1 saniye bile 1 dakika ⇒ 60 dk pencerede 60 dakika
        XCTAssertEqual(MinimumWindowApplier.applySeconds(actualSeconds: 1, windowMinutes: 60), 60)
        XCTAssertEqual(MinimumWindowApplier.applySeconds(actualSeconds: 0, windowMinutes: 60), 0)
        // 600 sn = 10 dk → 60 dk pencere
        XCTAssertEqual(MinimumWindowApplier.applySeconds(actualSeconds: 600, windowMinutes: 60), 60)
        // 3660 sn = 61 dk → 120 dk
        XCTAssertEqual(MinimumWindowApplier.applySeconds(actualSeconds: 3660, windowMinutes: 60), 120)
    }
}
