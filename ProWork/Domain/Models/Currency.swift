//  Currency.swift
//  ProWork
//  Created by Pronomi.

import Foundation

struct Currency: Hashable {
    let code: String
    let symbol: String
    let decimalPlaces: Int
    /// `displayName` carries the raw fallback (Turkish today
    /// because the registry is bootstrapped for a TR-locale build). The
    /// **only** correct way to read it from UI is `Currency.info(for:)`,
    /// which applies `ProWorkLocalizer` first. The setter is now
    /// `internal(set)` so external callers can read it but cannot
    /// silently assign a non-localised value; tests that need to mutate
    /// stay inside the module.
    private(set) var displayName: String

    init(code: String, symbol: String, decimalPlaces: Int, displayName: String) {
        self.code = code
        self.symbol = symbol
        self.decimalPlaces = decimalPlaces
        self.displayName = displayName
    }

    /// The `displayName` fields hold static Turkish fallbacks; the real
    /// user-facing string comes from `info(for:)`, which routes through
    /// `localizedDisplayName` every time. Any code path that reads the
    /// registry directly and prints `displayName` to the UI must go through
    /// `info(for:)`, otherwise the unlocalized Turkish string leaks out.
    static let registry: [String: Currency] = [
        "TRY": Currency(code: "TRY", symbol: "₺", decimalPlaces: 2, displayName: "Türk Lirası"),
        "USD": Currency(code: "USD", symbol: "$", decimalPlaces: 2, displayName: "ABD Doları"),
        "EUR": Currency(code: "EUR", symbol: "€", decimalPlaces: 2, displayName: "Euro"),
        "GBP": Currency(code: "GBP", symbol: "£", decimalPlaces: 2, displayName: "İngiliz Sterlini"),
        "CHF": Currency(code: "CHF", symbol: "CHF", decimalPlaces: 2, displayName: "İsviçre Frangı"),
        "JPY": Currency(code: "JPY", symbol: "¥", decimalPlaces: 0, displayName: "Japon Yeni"),
        "AED": Currency(code: "AED", symbol: "د.إ", decimalPlaces: 2, displayName: "BAE Dirhemi"),
        "SAR": Currency(code: "SAR", symbol: "﷼", decimalPlaces: 2, displayName: "Suudi Arabistan Riyali")
    ]

    /// Derive from `registry.keys` so adding a currency upstream
    /// automatically opts it into TCMB/Frankfurter sync. The previous
    /// 4-item literal silently excluded CHF/JPY/AED/SAR even though
    /// they were registered.
    static var allCodes: [String] { registry.keys.sorted() }

    /// Callers like CurrencyConverter need a quick check
    /// for "is this code in the registry?" so they can detect when
    /// `info(for:)` is falling back to the synthesized 2-decimal default.
    /// Backed by the registry's keys so adding a currency above keeps this
    /// in sync automatically.
    static var knownCodes: Set<String> {
        Set(registry.keys)
    }

    static func info(for code: String) -> Currency {
        let normalized = code.uppercased()
        if var known = registry[normalized] {
            known.displayName = localizedDisplayName(for: normalized, fallback: known.displayName)
            return known
        }
        return Currency(
            code: normalized,
            symbol: normalized,
            decimalPlaces: 2,
            displayName: normalized
        )
    }

    private static func localizedDisplayName(for code: String, fallback: String) -> String {
        switch code {
        case "TRY":
            return ProWorkLocalizer.shared.string("currency.try", defaultValue: fallback)
        case "USD":
            return ProWorkLocalizer.shared.string("currency.usd", defaultValue: fallback)
        case "EUR":
            return ProWorkLocalizer.shared.string("currency.eur", defaultValue: fallback)
        case "GBP":
            return ProWorkLocalizer.shared.string("currency.gbp", defaultValue: fallback)
        case "CHF":
            return ProWorkLocalizer.shared.string("currency.chf", defaultValue: fallback)
        case "JPY":
            return ProWorkLocalizer.shared.string("currency.jpy", defaultValue: fallback)
        case "AED":
            return ProWorkLocalizer.shared.string("currency.aed", defaultValue: fallback)
        case "SAR":
            return ProWorkLocalizer.shared.string("currency.sar", defaultValue: fallback)
        default:
            return fallback
        }
    }

    /// Express the per-currency minor-unit multiplier as a
    /// `Decimal` with a positive `exponent` so the relationship between
    /// `decimalPlaces` and `10^N` reads directly instead of being
    /// derived from a hand-rolled loop. `Decimal(sign:exponent:significand:)`
    /// is the canonical way to build a power-of-ten Decimal.
    static func minorMultiplier(for code: String) -> Decimal {
        let places = info(for: code).decimalPlaces
        guard places > 0 else { return 1 }
        return Decimal(sign: .plus, exponent: places, significand: 1)
    }
}
