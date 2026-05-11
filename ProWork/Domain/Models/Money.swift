//
//  Money.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Para tutarını ondalıklı tam hassasiyetle taşıyan tip.
/// Domain ve UI içinde `amount` (Decimal) kullanılır.
/// Veritabanı sınırında `minorUnits` (kuruş, INTEGER) ile dönüştürülür.
struct Money: Hashable {
    var amount: Decimal
    var currency: String

    init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency.uppercased()
    }

    /// Minor unit (kuruş) cinsinden tutar oluşturur.
    /// Örn: `Money(minorUnits: 150050, currency: "TRY")` -> 1500.50 TRY
    init(minorUnits: Int, currency: String) {
        let normalizedCode = currency.uppercased()
        let multiplier = Currency.minorMultiplier(for: normalizedCode)

        var divisor = multiplier
        var raw = Decimal(minorUnits)
        var result = Decimal()
        NSDecimalDivide(&result, &raw, &divisor, .plain)

        self.amount = result
        self.currency = normalizedCode
    }

    /// DB'ye yazılacak minor unit (kuruş) değeri. Banker's rounding uygulanır.
    var minorUnits: Int {
        var multiplier = Currency.minorMultiplier(for: currency)
        var rawAmount = amount
        var product = Decimal()
        NSDecimalMultiply(&product, &rawAmount, &multiplier, .plain)

        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 0, .bankers)

        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func zero(_ currency: String = "TRY") -> Money {
        Money(amount: 0, currency: currency)
    }

    var isZero: Bool {
        amount == 0
    }
}

// MARK: - Aritmetik

extension Money {
    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(
            lhs.currency == rhs.currency,
            "Farklı para birimleri toplanamaz: \(lhs.currency) ↔ \(rhs.currency)"
        )
        return Money(amount: lhs.amount + rhs.amount, currency: lhs.currency)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        precondition(
            lhs.currency == rhs.currency,
            "Farklı para birimleri çıkarılamaz: \(lhs.currency) ↔ \(rhs.currency)"
        )
        return Money(amount: lhs.amount - rhs.amount, currency: lhs.currency)
    }

    static prefix func - (value: Money) -> Money {
        Money(amount: -value.amount, currency: value.currency)
    }

    static func * (lhs: Money, rhs: Decimal) -> Money {
        Money(amount: lhs.amount * rhs, currency: lhs.currency)
    }

    static func * (lhs: Decimal, rhs: Money) -> Money {
        Money(amount: lhs * rhs.amount, currency: rhs.currency)
    }

    static func * (lhs: Money, rhs: Int) -> Money {
        Money(amount: lhs.amount * Decimal(rhs), currency: lhs.currency)
    }

    static func / (lhs: Money, rhs: Decimal) -> Money {
        precondition(rhs != 0, "Money sıfıra bölünemez")
        return Money(amount: lhs.amount / rhs, currency: lhs.currency)
    }
}

// MARK: - Karşılaştırma

extension Money: Comparable {
    static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(
            lhs.currency == rhs.currency,
            "Farklı para birimleri karşılaştırılamaz: \(lhs.currency) ↔ \(rhs.currency)"
        )
        return lhs.amount < rhs.amount
    }
}

// MARK: - Yardımcı fabrikalar

extension Money {
    /// Saatlik birim ücret * dakika ile tutar üretir.
    /// `unitPricePerHour` bir saatlik ücret. Sonuç: tutar.
    static func fromHourlyRate(_ unitPricePerHour: Money, billableMinutes: Int) -> Money {
        let minutesDecimal = Decimal(billableMinutes)
        let sixty: Decimal = 60
        let perMinute = Money(
            amount: unitPricePerHour.amount / sixty,
            currency: unitPricePerHour.currency
        )
        return perMinute * minutesDecimal
    }
}
