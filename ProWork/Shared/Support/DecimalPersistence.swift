//  DecimalPersistence.swift
//  ProWork
//  Created by Pronomi.
//  Locale-stable string encoding/decoding for `Decimal` values that are
//  persisted as SQLite TEXT (VAT rates, exchange rates, line totals).
//  `NSDecimalNumber.stringValue` and the basic `Decimal(string:)` initializer
//  both consult the current locale on some platforms — on a `tr_TR` device
//  this can produce a "0,18" string and then fail to round-trip back through
//  `Decimal(string:)`. All persistence code paths must use
//  these helpers so the on-disk representation is always `en_US_POSIX`
//  formatted (period decimal separator, no thousand separators).

import Foundation

enum DecimalPersistence {
    /// POSIX locale; pinned so persisted values never depend on the user's
    /// current locale.
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// Encode a `Decimal` for storage. Always uses `.` as the decimal
    /// separator and never inserts a grouping separator.
    static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: posixLocale)
    }

    /// Decode a `Decimal` from a persisted string. Tries POSIX-locale parsing
    /// first; falls back to locale-insensitive parsing for legacy values.
    /// Returns `nil` only if the string is genuinely unparseable.
    static func decimal(from string: String) -> Decimal? {
        if let value = Decimal(string: string, locale: posixLocale) {
            return value
        }
        return Decimal(string: string)
    }
}

extension Decimal {
    /// Convenience: locale-stable text representation suitable for SQLite TEXT
    /// columns.
    var persistedString: String {
        DecimalPersistence.string(self)
    }
}
