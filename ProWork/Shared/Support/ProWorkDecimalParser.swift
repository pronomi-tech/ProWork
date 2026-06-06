//  ProWorkDecimalParser.swift
//  ProWork
//  Created by Pronomi.
// shared "locale-aware decimal parse with POSIX fallback"
//  helper. Two settings forms (PriceListRowFormView,
//  VatRateFormView) hand-rolled the same two-pass parser inline; the
//  two could drift on `maximumFractionDigits` or normalisation if one
//  picked up a change the other missed. Routing both through this
//  helper guarantees a single behaviour:
//   1. Try the caller-supplied formatter (locale-aware, e.g. "1.500,00"
//      for TR).
//   2. Fall back to an en_US_POSIX decimal formatter so a paste from
//      a foreign spreadsheet ("1,500.00" or "1500.00") still parses.
//  Both stages share the same `maximumFractionDigits` so percentage
//  vs price callers can tune precision without forking the helper.

import Foundation

enum ProWorkDecimalParser {
    /// Parses `input` using `primary`, falling back to a POSIX
    /// (`en_US_POSIX`) decimal formatter when the primary rejects it.
    /// Returns nil for empty/whitespace input or genuinely
    /// unparseable values.
    static func parse(
        _ input: String,
        primary: NumberFormatter,
        maximumFractionDigits: Int = 4
    ) -> Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsed = primary.number(from: trimmed)?.decimalValue {
            return parsed
        }

        let posix = NumberFormatter()
        posix.locale = Locale(identifier: "en_US_POSIX")
        posix.numberStyle = .decimal
        posix.maximumFractionDigits = maximumFractionDigits
        return posix.number(from: trimmed)?.decimalValue
    }
}
