//  ProWorkFormattersTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class ProWorkFormattersTests: XCTestCase {
    func test_durationHHmmss_preservesSecondPrecision() {
        XCTAssertEqual(ProWorkFormatters.durationHHmmss(0), "00:00:00")
        XCTAssertEqual(ProWorkFormatters.durationHHmmss(1_577), "00:26:17")
        XCTAssertEqual(ProWorkFormatters.durationHHmmss(6_388), "01:46:28")
    }
}
