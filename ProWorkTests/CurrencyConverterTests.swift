//
//  CurrencyConverterTests.swift
//  ProWorkTests
//
//  Currency çevirme:
//   1. Doğrudan kayıt
//   2. Ters kayıt (1/rate)
//   3. Master üzerinden zincir
//   4. Hiçbiri yoksa hata
//

import XCTest
@testable import ProWork

@MainActor
final class CurrencyConverterTests: XCTestCase {

    private var dbURL: URL!
    private var rateRepository: ExchangeRateRepository!

    override func setUp() async throws {
        try await super.setUp()
        dbURL = try DatabaseTestHelper.freshDatabase()
        rateRepository = ExchangeRateRepository()
    }

    override func tearDown() async throws {
        if let url = dbURL {
            DatabaseTestHelper.teardown(at: url)
        }
        dbURL = nil
        rateRepository = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func upsertRate(
        from: String,
        to: String,
        rate: Decimal,
        on date: String = "2026-05-07",
        source: ExchangeRateSource = .manual
    ) throws {
        let rate = ExchangeRate(
            fromCurrency: from,
            toCurrency: to,
            rate: rate,
            forexSelling: rate,
            rateDate: date,
            source: source
        )
        try rateRepository.upsert(rate)
    }

    private func makeConverter(masterCurrency: String = "TRY") -> CurrencyConverter {
        CurrencyConverter(
            rateRepository: rateRepository,
            organizationId: BuiltInOrganizationId.default,
            masterCurrency: masterCurrency,
            preferredAutoSource: .tcmb
        )
    }

    // MARK: - Identity

    func test_sameCurrency_returnsUnchanged() throws {
        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "TRY"), to: "TRY", on: "2026-05-07")
        XCTAssertEqual(result.amount, 100)
        XCTAssertEqual(result.currency, "TRY")
    }

    // MARK: - Doğrudan kayıt

    func test_directRate_isUsed() throws {
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "35")!)

        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")
        XCTAssertEqual(result.amount, 3500)
        XCTAssertEqual(result.currency, "TRY")
    }

    func test_convertToMaster_usesMasterCurrency() throws {
        try upsertRate(from: "EUR", to: "TRY", rate: Decimal(string: "40")!)

        let conv = makeConverter(masterCurrency: "TRY")
        let result = try conv.convertToMaster(Money(amount: 50, currency: "EUR"), on: "2026-05-07")
        XCTAssertEqual(result.amount, 2000)
        XCTAssertEqual(result.currency, "TRY")
    }

    // MARK: - Ters kayıt

    func test_reverseRate_isUsedWhenDirectMissing() throws {
        // Sadece TRY→USD kaydı var; USD→TRY istenince 1/rate uygulanmalı
        try upsertRate(from: "TRY", to: "USD", rate: Decimal(string: "0.0285714285714286")!)
        // 1/0.0285... ≈ 35

        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")
        // Hassasiyet farkı olabilir, yaklaşık 3500 olmalı
        let asDouble = NSDecimalNumber(decimal: result.amount).doubleValue
        XCTAssertEqual(asDouble, 3500, accuracy: 0.01)
    }

    // MARK: - Master üzerinden zincir

    func test_chainViaMaster_whenNoDirectOrReverse() throws {
        // Master = TRY. EUR→TRY ve TRY→USD var; EUR→USD istenince zincir kullanılmalı.
        try upsertRate(from: "EUR", to: "TRY", rate: Decimal(string: "40")!)
        try upsertRate(from: "TRY", to: "USD", rate: Decimal(string: "0.0285714285714286")!)
        // 100 EUR → 4000 TRY → 4000 * 0.02857... ≈ 114.28 USD

        let conv = makeConverter(masterCurrency: "TRY")
        let result = try conv.convert(Money(amount: 100, currency: "EUR"), to: "USD", on: "2026-05-07")
        let asDouble = NSDecimalNumber(decimal: result.amount).doubleValue
        XCTAssertEqual(asDouble, 114.285, accuracy: 0.1)
    }

    // MARK: - Yokluk

    func test_noRateAvailable_throwsError() {
        let conv = makeConverter()
        XCTAssertThrowsError(
            try conv.convert(Money(amount: 100, currency: "USD"), to: "GBP", on: "2026-05-07")
        ) { error in
            guard case CurrencyConversionError.noRateAvailable = error else {
                XCTFail("noRateAvailable bekleniyordu, alınan: \(error)")
                return
            }
        }
    }

    // MARK: - Tarih bazlı seçim

    func test_olderRateIsUsed_whenLaterDateMissing() throws {
        // 2026-01-01 kaydı var; 2026-05-07 isteğinde bu kullanılmalı (rateDate <= targetDate)
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "32")!, on: "2026-01-01")

        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")
        XCTAssertEqual(result.amount, 3200)
    }

    func test_futureRate_isIgnored() throws {
        // Sadece gelecek tarihli kayıt var → bulunamaz
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "40")!, on: "2027-01-01")

        let conv = makeConverter()
        XCTAssertThrowsError(
            try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")
        )
    }

    func test_mostRecentRate_winsAmongMultiple() throws {
        // Aynı çift için 2 farklı tarih; daha yakın olan kazanır.
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "30")!, on: "2026-01-01")
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "35")!, on: "2026-04-01")

        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")
        XCTAssertEqual(result.amount, 3500, "En son tarihli kur kazanmalı")
    }

    // MARK: - sumInMaster

    func test_sumInMaster_aggregatesMultiCurrency() throws {
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "35")!)
        try upsertRate(from: "EUR", to: "TRY", rate: Decimal(string: "40")!)

        let conv = makeConverter()
        let total = try conv.sumInMaster([
            Money(amount: 100, currency: "TRY"),
            Money(amount: 10, currency: "USD"),  // → 350 TRY
            Money(amount: 5, currency: "EUR")    // → 200 TRY
        ], on: "2026-05-07")

        XCTAssertEqual(total.amount, 650)
        XCTAssertEqual(total.currency, "TRY")
    }

    func test_sumInMaster_emptyArray_isZero() throws {
        let conv = makeConverter()
        let total = try conv.sumInMaster([], on: "2026-05-07")
        XCTAssertEqual(total.amount, 0)
        XCTAssertEqual(total.currency, "TRY")
    }

    // MARK: - Source priority

    func test_manualRate_winsOverAutoSource() throws {
        // Aynı tarih için manuel ve TCMB kayıtları → manuel kazanmalı (sourcePriority listesinde manual ilk)
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "30")!, source: .tcmb)
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "35")!, source: .manual)

        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")
        XCTAssertEqual(result.amount, 3500, "Manuel kayıt otomatik kaynaklara önceliklidir")
    }
}
