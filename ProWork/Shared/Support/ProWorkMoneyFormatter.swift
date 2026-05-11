//
//  ProWorkMoneyFormatter.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

extension ProWorkFormatters {
    /// `Money` değerini "1.500,50 ₺" şeklinde tr_TR locale'ine göre formatlar.
    static func money(_ value: Money, showsCode: Bool = false) -> String {
        let info = Currency.info(for: value.currency)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = info.decimalPlaces
        formatter.maximumFractionDigits = info.decimalPlaces
        formatter.usesGroupingSeparator = true

        let number = NSDecimalNumber(decimal: value.amount)
        let core = formatter.string(from: number) ?? "0"

        if showsCode {
            return "\(core) \(info.code)"
        }
        return "\(core) \(info.symbol)"
    }

    /// Negatif tutarları parantez içinde gösterir (muhasebe tarzı).
    /// Örn: -1.500,00 ₺ → "(1.500,00 ₺)"
    static func moneyAccounting(_ value: Money) -> String {
        if value.amount < 0 {
            let positive = Money(amount: -value.amount, currency: value.currency)
            return "(\(money(positive)))"
        }
        return money(value)
    }

    /// Sadece sayısal kısmı (sembol/kod olmadan) döner. Tablo/kolon hizalaması için.
    static func moneyAmount(_ value: Money) -> String {
        let info = Currency.info(for: value.currency)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = info.decimalPlaces
        formatter.maximumFractionDigits = info.decimalPlaces
        formatter.usesGroupingSeparator = true

        let number = NSDecimalNumber(decimal: value.amount)
        return formatter.string(from: number) ?? "0"
    }

    /// Saatlik birim ücret etiketi: "1.500,00 ₺ / saat"
    static func hourlyRate(_ value: Money) -> String {
        "\(money(value)) / saat"
    }
}
