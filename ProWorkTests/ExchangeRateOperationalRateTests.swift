//  ExchangeRateOperationalRateTests.swift
//  ProWorkTests
//  `operationalRate` fallback sırasını test'le kilitleyelim.
//  Aksi halde bir refactor `forexBuying ?? forexSelling ?? …` gibi sessiz bir
//  yer değişikliği yapsa kimse fark etmeyebilir.

import XCTest
@testable import ProWork

final class ExchangeRateOperationalRateTests: XCTestCase {

    private func make(
        rate: Decimal = 0,
        forexBuying: Decimal? = nil,
        forexSelling: Decimal? = nil,
        banknoteBuying: Decimal? = nil,
        banknoteSelling: Decimal? = nil
    ) -> ExchangeRate {
        ExchangeRate(
            id: UUID().uuidString,
            fromCurrency: "USD",
            toCurrency: "TRY",
            rate: rate,
            forexBuying: forexBuying,
            forexSelling: forexSelling,
            banknoteBuying: banknoteBuying,
            banknoteSelling: banknoteSelling,
            rateDate: "2026-05-19",
            source: .manual
        )
    }

    func test_O37_prefersForexSelling() {
        let rate = make(
            rate: 1,
            forexBuying: 30,
            forexSelling: 31,
            banknoteBuying: 32,
            banknoteSelling: 33
        )
        XCTAssertEqual(rate.operationalRate, 31)
    }

    func test_O37_fallsBackToForexBuying_whenForexSellingNil() {
        let rate = make(
            rate: 1,
            forexBuying: 30,
            forexSelling: nil,
            banknoteBuying: 32,
            banknoteSelling: 33
        )
        XCTAssertEqual(rate.operationalRate, 30)
    }

    func test_O37_fallsBackToBanknoteSelling_whenForexFieldsNil() {
        let rate = make(
            rate: 1,
            forexBuying: nil,
            forexSelling: nil,
            banknoteBuying: 32,
            banknoteSelling: 33
        )
        XCTAssertEqual(rate.operationalRate, 33)
    }

    func test_O37_fallsBackToBanknoteBuying_whenSellingFieldsNil() {
        let rate = make(
            rate: 1,
            forexBuying: nil,
            forexSelling: nil,
            banknoteBuying: 32,
            banknoteSelling: nil
        )
        XCTAssertEqual(rate.operationalRate, 32)
    }

    func test_O37_finalFallbackIsRate_whenAllOptionalsNil() {
        let rate = make(rate: 27, forexBuying: nil, forexSelling: nil, banknoteBuying: nil, banknoteSelling: nil)
        XCTAssertEqual(rate.operationalRate, 27)
    }
}
