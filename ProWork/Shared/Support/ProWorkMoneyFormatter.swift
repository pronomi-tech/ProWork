//  ProWorkMoneyFormatter.swift
//  ProWork
//  Created by Pronomi.

import Foundation

extension ProWorkFormatters {
    // MARK: - NumberFormatter cache
    // `NumberFormatter` compiles its locale + style configuration lazily;
    // tables that re-render dozens of money columns per row were paying
    // that cost on every cell. The cache keys are (currency code, locale
    // identifier) since `decimalPlaces` is derived from the currency

    /// `nonisolated`: same as the CacheKey pattern — Hashable
    /// conformance is needed for lookups from the nonisolated
    /// `moneyFormatterCache`.
    nonisolated private struct MoneyFormatterKey: Hashable {
        let currencyCode: String
        let localeIdentifier: String
    }

    nonisolated(unsafe) private static var moneyFormatterCache: [MoneyFormatterKey: NumberFormatter] = [:]
    private static let moneyFormatterLock = NSLock()

    /// (formatter cache lock contention): construct the
    /// NumberFormatter *outside* the lock. The critical section is now
    /// only the dictionary read/write. A benign duplicate allocation under
    /// race is preferable to serializing CFLocale work behind one lock
    /// across all callers during high-frequency table renders.
    private static func cachedMoneyFormatter(
        for currencyCode: String,
        localeIdentifier: String = "tr_TR"
    ) -> NumberFormatter {
        let key = MoneyFormatterKey(currencyCode: currencyCode, localeIdentifier: localeIdentifier)
        moneyFormatterLock.lock()
        if let cached = moneyFormatterCache[key] {
            moneyFormatterLock.unlock()
            return cached
        }
        moneyFormatterLock.unlock()

        let info = Currency.info(for: currencyCode)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = info.decimalPlaces
        formatter.maximumFractionDigits = info.decimalPlaces
        formatter.usesGroupingSeparator = true

        moneyFormatterLock.lock()
        defer { moneyFormatterLock.unlock() }
        if let existing = moneyFormatterCache[key] {
            return existing
        }
        moneyFormatterCache[key] = formatter
        return formatter
    }

    /// `localeIdentifier` is now propagated through every
    /// money/hourlyRate formatter call so the user's UI language
    /// drives the grouping/decimal separators. The previous default
    /// of `tr_TR` baked Turkish formatting into every PDF + report
    /// regardless of `AppLanguage`. Callers that don't have a locale
    /// available can pass `ProWorkLocalizer.shared.language.localeIdentifier`
    /// — the convenience wrappers below resolve that automatically.

    /// Formats a `Money` value according to the locale (e.g. "1.500,50 ₺"
    /// in tr_TR, "1,500.50 ₺" in en_US).
    static func money(
        _ value: Money,
        showsCode: Bool = false,
        localeIdentifier: String = ProWorkLocalizer.shared.language.localeIdentifier
    ) -> String {
        let info = Currency.info(for: value.currency)
        let formatter = cachedMoneyFormatter(
            for: value.currency,
            localeIdentifier: localeIdentifier
        )
        let number = NSDecimalNumber(decimal: value.amount)
        let core = formatter.string(from: number) ?? "0"

        if showsCode {
            return "\(core) \(info.code)"
        }
        return "\(core) \(info.symbol)"
    }

    /// Shows negative amounts in parentheses (accounting style).
    /// e.g. -1.500,00 ₺ → "(1.500,00 ₺)"
    static func moneyAccounting(
        _ value: Money,
        localeIdentifier: String = ProWorkLocalizer.shared.language.localeIdentifier
    ) -> String {
        if value.amount < 0 {
            let positive = Money(amount: -value.amount, currency: value.currency)
            return "(\(money(positive, localeIdentifier: localeIdentifier)))"
        }
        return money(value, localeIdentifier: localeIdentifier)
    }

    /// Returns only the numeric part (no symbol/code). For table/column alignment.
    static func moneyAmount(
        _ value: Money,
        localeIdentifier: String = ProWorkLocalizer.shared.language.localeIdentifier
    ) -> String {
        let formatter = cachedMoneyFormatter(
            for: value.currency,
            localeIdentifier: localeIdentifier
        )
        let number = NSDecimalNumber(decimal: value.amount)
        return formatter.string(from: number) ?? "0"
    }

    /// Hourly unit-price label (e.g. "1.500,00 ₺ / saat").
    /// The "saat" suffix string also comes from the localizer.
    static func hourlyRate(
        _ value: Money,
        localeIdentifier: String = ProWorkLocalizer.shared.language.localeIdentifier
    ) -> String {
        let suffix = ProWorkLocalizer.shared.string(
            "common.unit.perHourSuffix",
            defaultValue: "/ saat"
        )
        return "\(money(value, localeIdentifier: localeIdentifier)) \(suffix)"
    }
}
