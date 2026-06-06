//  SpreadsheetCellSanitizer.swift
//  ProWork
//  Created by Pronomi.
//  Spreadsheet formula-injection guard shared by CSV and XLSX exporters.
//  A field whose first character is one of `=`, `+`, `-`, `@`, `|`, TAB, or
//  CR is interpreted as a formula by Excel / Numbers / LibreOffice — even
//  when the cell type is "text" or an XLSX inline string. The classic
//  exploit is a customer-name like `=cmd|' /C calc'!A1` that fires when an
//  unsuspecting recipient opens the spreadsheet. Prefixing the value with
//  a single apostrophe forces the application into literal-text mode and
//  the apostrophe itself is hidden when displayed.

import Foundation

/// `nonisolated`: the namespace contains only constant data and pure
/// functions; must be callable from nonisolated export pipelines
/// (BillingRunExportService).
nonisolated enum SpreadsheetCellSanitizer {
    /// Include LF (`\n`) alongside TAB and CR. Modern Excel
    /// versions accept `\n` as a row delimiter inside inline strings;
    /// a leading `\n=cmd|…` payload was still being executed as a
    /// formula because the lookahead skipped past the newline rather
    /// than treating it as dangerous. Defensive completeness — pair
    /// with TAB/CR to cover every whitespace leader the various
    /// spreadsheet apps tolerate.
    private static let dangerousLeaders: Set<Character> = [
        "=", "+", "-", "@", "|", "\t", "\r", "\n"
    ]

    /// Returns the value prefixed with a single apostrophe whenever the
    /// **first non-space** character is dangerous. Excel's formula parser
    /// also skips leading spaces, so `"   =cmd|..."` would still execute
    ///. TAB and CR are *themselves* dangerous leaders,
    /// so they are not stripped during the lookahead.
    static func escape(_ value: String) -> String {
        let trimmed = value.drop { $0 == " " }
        guard let first = trimmed.first, dangerousLeaders.contains(first) else {
            return value
        }
        return "'\(value)"
    }
}
