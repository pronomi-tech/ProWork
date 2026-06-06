//  ProWorkNumberFieldSanitizeTests.swift
//  ProWorkTests
//  unit tests for ProWorkNumberField.sanitize — the
//  locale-aware text filter that powers numeric input across the app.
//  The helper was extracted as a pure static function so it can be
//  exercised without a SwiftUI environment / settings store.

import XCTest
@testable import ProWork

final class ProWorkNumberFieldSanitizeTests: XCTestCase {

    // MARK: - Integer style

    func test_integer_stripsNonDigits() {
        let result = ProWorkNumberField.sanitize(
            "abc123def",
            style: .integer(maxDigits: nil),
            separator: ","
        )
        XCTAssertEqual(result, "123")
    }

    func test_integer_clampsToMaxDigits() {
        let result = ProWorkNumberField.sanitize(
            "1234567890",
            style: .integer(maxDigits: 4),
            separator: ","
        )
        XCTAssertEqual(result, "1234")
    }

    func test_integer_emptyInput() {
        let result = ProWorkNumberField.sanitize(
            "",
            style: .integer(maxDigits: nil),
            separator: ","
        )
        XCTAssertEqual(result, "")
    }

    // MARK: - Decimal style — TR locale (separator ",")

    func test_decimal_tr_acceptsComma() {
        let result = ProWorkNumberField.sanitize(
            "1234,56",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        XCTAssertEqual(result, "1234,56")
    }

    func test_decimal_tr_convertsLoneDotToComma() {
        // User typed US-style "1500.00" while app locale is TR. The single
        // alternate separator is interpreted as the user's decimal.
        let result = ProWorkNumberField.sanitize(
            "1500.00",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        XCTAssertEqual(result, "1500,00")
    }

    func test_decimal_tr_dropsThousandsSeparator() {
        // "1.500,00" — dot is the TR thousands separator, drop it.
        let result = ProWorkNumberField.sanitize(
            "1.500,00",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        XCTAssertEqual(result, "1500,00")
    }

    func test_decimal_clampsFractionDigits() {
        let result = ProWorkNumberField.sanitize(
            "12,3456789",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        XCTAssertEqual(result, "12,34")
    }

    func test_decimal_zeroFractionDigits_dropsSeparatorAndTail() {
        let result = ProWorkNumberField.sanitize(
            "42,99",
            style: .decimal(maxFractionDigits: 0),
            separator: ","
        )
        XCTAssertEqual(result, "42")
    }

    func test_decimal_clampsIntegerDigits() {
        let result = ProWorkNumberField.sanitize(
            "1234567,89",
            style: .decimal(maxFractionDigits: 2, maxIntegerDigits: 4),
            separator: ","
        )
        XCTAssertEqual(result, "1234,89")
    }

    func test_decimal_multipleSeparators_keepsFirst() {
        // "12,34,56" — second comma is dropped, fraction clamps to 2.
        let result = ProWorkNumberField.sanitize(
            "12,34,56",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        XCTAssertEqual(result, "12,34")
    }

    func test_decimal_stripsLetters() {
        let result = ProWorkNumberField.sanitize(
            "abc12,34def",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        XCTAssertEqual(result, "12,34")
    }

    // MARK: - Decimal style — US locale (separator ".")

    func test_decimal_us_acceptsDot() {
        let result = ProWorkNumberField.sanitize(
            "1234.56",
            style: .decimal(maxFractionDigits: 2),
            separator: "."
        )
        XCTAssertEqual(result, "1234.56")
    }

    func test_decimal_us_convertsLoneCommaToDot() {
        // User typed TR-style "1500,00" while app locale is US.
        let result = ProWorkNumberField.sanitize(
            "1500,00",
            style: .decimal(maxFractionDigits: 2),
            separator: "."
        )
        XCTAssertEqual(result, "1500.00")
    }

    func test_decimal_us_dropsCommaThousandsSeparator() {
        // "1,500.00" — comma is US thousands separator, drop it.
        let result = ProWorkNumberField.sanitize(
            "1,500.00",
            style: .decimal(maxFractionDigits: 2),
            separator: "."
        )
        XCTAssertEqual(result, "1500.00")
    }

    // MARK: - Defensive final clamp (review HIGH guarantee)

    func test_decimal_finalClamp_handlesMixedSeparators() {
        // A paste of "1.500,123456,99" — dot becomes thousands separator
        // (dropped), comma is the decimal, tail clamps to 2.
        let result = ProWorkNumberField.sanitize(
            "1.500,123456,99",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        // Implementation detail: extra commas after the first are ignored
        // by `split(omittingEmptySubsequences: false)`, then fraction
        // tail is clamped to 2 chars.
        XCTAssertEqual(result, "1500,12")
    }

    func test_decimal_emptyInput() {
        let result = ProWorkNumberField.sanitize(
            "",
            style: .decimal(maxFractionDigits: 2),
            separator: ","
        )
        XCTAssertEqual(result, "")
    }
}
