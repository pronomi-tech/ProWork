//  Money.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Carries a money amount with full decimal precision.
/// Domain and UI code work with `amount` (Decimal).
/// At the DB boundary it converts to `minorUnits` (e.g. kuruş, INTEGER).
struct Money: Hashable {
    var amount: Decimal
    var currency: String

    init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency.uppercased()
    }

    /// Builds an amount from minor units (e.g. kuruş).
    /// e.g. `Money(minorUnits: 150050, currency: "TRY")` -> 1500.50 TRY
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

    /// Minor-unit (e.g. kuruş) value written to the DB. Uses banker's rounding.
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

// MARK: - Arithmetic

extension Money {
    /// Arithmetic on heterogeneous currencies is a
    /// **programming error** (the caller forgot to convert before adding
    /// kuruş + cent), not a runtime data condition. We keep the
    /// `precondition` semantics — a wrong-currency add produces a
    /// crash report we can act on — but route the messages through the
    /// localiser so debug Console output isn't hardcoded Turkish.
    /// English defaults track the rest of the codebase's diagnostic
    /// strings. Production builds elide `precondition` in -O, so the
    /// trap only fires in DEBUG / -Onone where the caller would catch
    /// it during development.
    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(
            lhs.currency == rhs.currency,
            currencyMismatchMessage(operation: "add", lhs: lhs.currency, rhs: rhs.currency)
        )
        return Money(amount: lhs.amount + rhs.amount, currency: lhs.currency)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        precondition(
            lhs.currency == rhs.currency,
            currencyMismatchMessage(operation: "subtract", lhs: lhs.currency, rhs: rhs.currency)
        )
        return Money(amount: lhs.amount - rhs.amount, currency: lhs.currency)
    }

    static prefix func - (value: Money) -> Money {
        Money(amount: -value.amount, currency: value.currency)
    }

    /// Scale a money amount by a unit-less factor (e.g. a quantity, a
    /// percentage, an FX rate). The result keeps the **left** operand's
    /// currency — multiplying by an FX rate does **not** convert; for
    /// conversion use `Money.convert(to:rate:)` which surfaces the
    /// intent in the function name.
    static func * (lhs: Money, rhs: Decimal) -> Money {
        Money(amount: lhs.amount * rhs, currency: lhs.currency)
    }

    /// Mirror of `Money * Decimal` for callers that prefer
    /// `factor * money` ordering.
    static func * (lhs: Decimal, rhs: Money) -> Money {
        Money(amount: lhs * rhs.amount, currency: rhs.currency)
    }

    /// Scale a money amount by an `Int` count. Currency is preserved.
    static func * (lhs: Money, rhs: Int) -> Money {
        Money(amount: lhs.amount * Decimal(rhs), currency: lhs.currency)
    }

    static func / (lhs: Money, rhs: Decimal) -> Money {
        precondition(
            rhs != 0,
            ProWorkLocalizer.shared.string(
                "money.error.divideByZero",
                defaultValue: "Money cannot be divided by zero."
            )
        )
        return Money(amount: lhs.amount / rhs, currency: lhs.currency)
    }

    private static func currencyMismatchMessage(operation: String, lhs: String, rhs: String) -> String {
        String(
            format: ProWorkLocalizer.shared.string(
                "money.error.currencyMismatch.\(operation)",
                defaultValue: "Cannot \(operation) Money values across currencies: %@ ↔ %@"
            ),
            lhs,
            rhs
        )
    }
}

// MARK: - Comparison

extension Money: Comparable {
    static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(
            lhs.currency == rhs.currency,
            Self.currencyMismatchMessage(operation: "compare", lhs: lhs.currency, rhs: rhs.currency)
        )
        return lhs.amount < rhs.amount
    }
}

// MARK: - Convenience factories

extension Money {
    /// Computes amount = hourly rate × minutes / 60.
    /// Operation order matters: multiplying first and dividing last
    /// preserves precision whenever the ratio is integer-clean and
    /// confines the rounding to a single trailing division otherwise.
    /// (Reversing the order — dividing the per-hour rate by 60 first —
    /// would produce a non-terminating Decimal tail like 100 / 60 =
    /// 1.666… which then propagates into the final minor unit on
    /// rounding.) The "Decimal non-terminating" caveat in the previous
    /// comment was historical from earlier Swift versions; the math
    /// reason — divide last to keep precision — still holds, so the
    /// shape stays the same.
    static func fromHourlyRate(_ unitPricePerHour: Money, billableMinutes: Int) -> Money {
        let minutesDecimal = Decimal(billableMinutes)
        let sixty: Decimal = 60
        return Money(
            amount: (unitPricePerHour.amount * minutesDecimal) / sixty,
            currency: unitPricePerHour.currency
        )
    }

    /// Explicit FX conversion. Use this — never `money * rate` — when the
    /// intent is to translate the amount into `target`.
    /// The multiplication operator preserves the source currency by design.
    func convert(to target: String, rate: Decimal) -> Money {
        Money(amount: amount * rate, currency: target)
    }
}
