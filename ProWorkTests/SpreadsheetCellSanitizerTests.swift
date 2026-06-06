//  SpreadsheetCellSanitizerTests.swift
//  ProWorkTests
//  XLSX/CSV ortak formül enjeksiyonu korumasını doğrular.

import XCTest
@testable import ProWork

final class SpreadsheetCellSanitizerTests: XCTestCase {

    func test_neutralValues_passThroughUnchanged() {
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("Acme Ltd"), "Acme Ltd")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("1234"), "1234")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape(""), "")
    }

    func test_dangerousLeaders_arePrefixedWithApostrophe() {
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("=cmd|' /C calc'!A1"), "'=cmd|' /C calc'!A1")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("+SUM(A1)"), "'+SUM(A1)")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("-5"), "'-5")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("@HYPERLINK"), "'@HYPERLINK")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("|cmd"), "'|cmd")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("\tinjected"), "'\tinjected")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("\rinjected"), "'\rinjected")
    }

    /// Y4: leading spaces must not bypass the leader check.
    /// Excel trims spaces before parsing formulas. TAB/CR are themselves
    /// dangerous leaders (see K7 test), so they're not stripped.
    func test_Y4_leadingSpaces_doNotBypassLeaderCheck() {
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("   =cmd|' /C calc'!A1"), "'   =cmd|' /C calc'!A1")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("  +SUM(A1)"), "'  +SUM(A1)")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("   @HYPERLINK"), "'   @HYPERLINK")
    }

    func test_apostropheInMiddle_isNotTouched() {
        // Tek karakter koşulu yalnızca başlangıçta tetiklenir; içerideki
        // tehlikeli sembol bağlam dışıdır.
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("Ali=Veli"), "Ali=Veli")
        XCTAssertEqual(SpreadsheetCellSanitizer.escape("x+y"), "x+y")
    }
}
