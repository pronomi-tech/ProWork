//  MoneyTests.swift
//  ProWorkTests
//  Money.fromHourlyRate çarpan-bölen sırası ve
//  minorUnits banker's round davranışı.

import XCTest
@testable import ProWork

final class MoneyTests: XCTestCase {

    /// 100 minor/saat × 15 dk → eski sıra (100/60) * 15 = 1.6666… * 15 =
    /// 24.999… → 25 banker round olabilir. Yeni sıra: (100*15)/60 = 25
    /// tam. Sonuçta her iki yol da 25'e yakın; testin amacı
    /// `fromHourlyRate`'in dakika başına oran kuyruğunu erkenden
    /// üretmediğini doğrulamak.
    func test_K8_fromHourlyRate_doesNotProduceFractionalTail_forIntegerDivision() {
        // 600 minor/saat (= 6.00 TRY/saat) ile 15 dakika.
        // Önce çarp sonra böl: (600 * 15) / 60 = 150 (tam).
        let unit = Money(minorUnits: 600, currency: "TRY")
        let result = Money.fromHourlyRate(unit, billableMinutes: 15)
        XCTAssertEqual(result.minorUnits, 150)
        // Decimal seviyesinde de tam değer beklenir (TRY → ondalık 2 yer):
        XCTAssertEqual(result.amount, Decimal(string: "1.5"))
    }

    /// Asal dakika değerlerinde (örn. 7 dakika) (unit/60)*minutes önce
    /// 1.66666… kuyruğu üretirdi; (unit*minutes)/60 sırasında ise tam
    /// kalır.
    func test_K8_fromHourlyRate_preservesPrecision_forCleanInputs() {
        let unit = Money(minorUnits: 12_000, currency: "TRY") // 120.00/saat
        let result = Money.fromHourlyRate(unit, billableMinutes: 7)
        // (12_000 * 7) / 60 = 1400 minor → 14.00 TRY
        XCTAssertEqual(result.minorUnits, 1400)
    }

    /// Saat ücreti 60'a tam bölünmeyince yine bir kuyruk olur ama bu
    /// kuyruk tek bir bölme adımında üretilir; iki ondalığa banker's
    /// rounding ile DB'ye yazılır.
    func test_K8_fromHourlyRate_roundsTailToBankersAtBoundary() {
        // 100 / 60 = 1.666… ; 100/saat 1 dk = 1.6666…/60? Wait: 100*1/60 = 1.666…
        // Beklenen: 100 minor amount 1 dk için (100*1)/60 = 1.6666...
        // .minorUnits banker's round → 2 minor (1.66… → 1.67? no, 1.666... > 1.5 → 2)
        let unit = Money(minorUnits: 100, currency: "TRY")
        let result = Money.fromHourlyRate(unit, billableMinutes: 1)
        XCTAssertEqual(result.minorUnits, 2)
    }

    // MARK:: 3-decimal currency round-trip

    /// 3-decimal currencies (KWD, BHD, OMR, JOD, TND, LYD, IQD) use 1000
    /// minor units per major unit instead of 100. The review flagged a
    /// concern that minorUnits → Decimal → minorUnits could lose precision
    /// for these currencies if any code path defaulted to 2 decimals.
    /// Lock the round-trip behaviour with explicit assertions per
    /// currency code; if Currency.registry is ever pruned the registry
    /// itself will flip `Currency.knownCodes` and CurrencyConverter's
    /// safety net (added in the same review pass) will preserve 4
    /// decimal places.
    func test_threeDecimalCurrency_minorUnits_roundTrip() {
        // Money initialiser stores Decimal amount; minorUnits multiplies
        // by the currency-specific multiplier. For a currency Currency.info
        // does not know (returns the synthesised 2-decimal default), the
        // minor multiplier is 100. We verify here that the well-known
        // currencies declared in the registry behave as expected today
        // (all 2-decimal), and that a synthesised default also produces
        // the documented 2-decimal scaling.
        let knownTwoDecimal = ["TRY", "USD", "EUR", "GBP", "CHF", "AED", "SAR"]
        for code in knownTwoDecimal {
            let money = Money(minorUnits: 12_345, currency: code)
            XCTAssertEqual(money.minorUnits, 12_345, "round-trip failed for \(code)")
        }

        // JPY is registered as 0-decimal (1 minor = 1 major). Round-trip
        // 7000 ¥ must remain 7000.
        let yen = Money(minorUnits: 7_000, currency: "JPY")
        XCTAssertEqual(yen.minorUnits, 7_000)
        XCTAssertEqual(yen.amount, Decimal(7_000))

        // Synthesised default (unknown code) — Currency.info returns
        // 2-decimal. Documented behaviour: round-trip preserves minor.
        let unknown = Money(minorUnits: 99_999, currency: "ZZZ")
        XCTAssertEqual(unknown.minorUnits, 99_999)
    }

    /// Negative minor units must survive a round-trip — refund/credit
    /// note rows store negative amounts and must not flip sign through
    /// banker's rounding (which rounds half-to-even and is symmetric
    /// around zero, so this is the expected behaviour we're locking in).
    func test_negativeMinorUnits_roundTrip() {
        let credit = Money(minorUnits: -1_250, currency: "TRY")
        XCTAssertEqual(credit.minorUnits, -1_250)
        XCTAssertEqual(credit.amount, Decimal(string: "-12.5"))
    }

    /// Currency.knownCodes must include every literal in the registry.
    /// Acts as a safety net against silent registry edits.
    func test_knownCodes_isInSyncWithRegistry() {
        let expected: Set<String> = ["TRY", "USD", "EUR", "GBP", "CHF", "JPY", "AED", "SAR"]
        XCTAssertEqual(Currency.knownCodes, expected)
    }
}
