//
//  Currency.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct Currency: Hashable {
    let code: String
    let symbol: String
    let decimalPlaces: Int
    var displayName: String

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

    static let allCodes: [String] = ["TRY", "USD", "EUR", "GBP"]

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

    static func minorMultiplier(for code: String) -> Decimal {
        let places = info(for: code).decimalPlaces
        var multiplier: Decimal = 1
        for _ in 0..<places {
            multiplier *= 10
        }
        return multiplier
    }
}
