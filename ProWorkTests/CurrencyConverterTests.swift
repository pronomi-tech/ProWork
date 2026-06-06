//  CurrencyConverterTests.swift
//  ProWorkTests
//  Currency çevirme:
//   1. Doğrudan kayıt
//   2. Ters kayıt (1/rate)
//   3. Master üzerinden zincir
//   4. Hiçbiri yoksa hata

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
        // Decimal aritmetiği ile tolerans; Double round-trip yapmak Money'in
        // hassasiyet vaadini geçersiz kılıyordu.
        let expected = Decimal(3500)
        let tolerance = Decimal(string: "0.01")!
        XCTAssertLessThanOrEqual(abs(result.amount - expected), tolerance)
    }

    // MARK: - Master üzerinden zincir

    // MARK:: chained precision across mismatched
    // decimal-place currencies

    func test_M6_chain_JPYtoGBPviaTRY_roundsToGBPMinorUnits() throws {
        // JPY has 0 decimal places, GBP has 2. The chain JPY → TRY → GBP
        // multiplies two approximate rates and then must land on a 2-dp
        // amount without leaking the 8-dp tail of the intermediate.
        try upsertRate(from: "JPY", to: "TRY", rate: Decimal(string: "0.27")!)
        try upsertRate(from: "TRY", to: "GBP", rate: Decimal(string: "0.0233")!)

        let conv = makeConverter(masterCurrency: "TRY")
        let result = try conv.convert(Money(amount: 10_000, currency: "JPY"), to: "GBP", on: "2026-05-07")
        // 10000 JPY → 2700 TRY → 2700 * 0.0233 = 62.910 GBP → 62.91
        let expected = Decimal(string: "62.91")!
        let tolerance = Decimal(string: "0.01")!
        XCTAssertLessThanOrEqual(abs(result.amount - expected), tolerance)
        XCTAssertEqual(result.currency, "GBP")
        XCTAssertEqual(result.minorUnits, 6291)
    }

    func test_M6_chain_GBPtoJPYviaTRY_truncatesToWholeYen() throws {
        // Reverse direction: 2 dp source, 0 dp target. The result must
        // be a whole yen integer; no fractional yen can leak.
        try upsertRate(from: "GBP", to: "TRY", rate: Decimal(string: "42.93")!)
        try upsertRate(from: "TRY", to: "JPY", rate: Decimal(string: "3.7")!)

        let conv = makeConverter(masterCurrency: "TRY")
        let result = try conv.convert(Money(amount: 100, currency: "GBP"), to: "JPY", on: "2026-05-07")
        // 100 GBP → 4293 TRY → 4293 * 3.7 = 15884.1 JPY → 15884 (banker's)
        XCTAssertEqual(result.currency, "JPY")
        XCTAssertEqual(result.minorUnits, 15884)
        XCTAssertEqual(result.amount, Decimal(15884))
    }

    func test_chainViaMaster_whenNoDirectOrReverse() throws {
        // Master = TRY. EUR→TRY ve TRY→USD var; EUR→USD istenince zincir kullanılmalı.
        try upsertRate(from: "EUR", to: "TRY", rate: Decimal(string: "40")!)
        try upsertRate(from: "TRY", to: "USD", rate: Decimal(string: "0.0285714285714286")!)
        // 100 EUR → 4000 TRY → 4000 * 0.02857... ≈ 114.285714... USD
        // convert() applies banker's rounding to the target currency's
        // minor-unit precision. USD = 2 decimal places, so 114.285714…
        // rounds to 114.29 (== 11429 minor units). Assert against the
        // rounded value with a generous tolerance.

        let conv = makeConverter(masterCurrency: "TRY")
        let result = try conv.convert(Money(amount: 100, currency: "EUR"), to: "USD", on: "2026-05-07")
        let expected = Decimal(string: "114.29")!
        let tolerance = Decimal(string: "0.01")!
        XCTAssertLessThanOrEqual(abs(result.amount - expected), tolerance)
        // Minor-unit equality is the DB-persisted contract:
        XCTAssertEqual(result.minorUnits, 11429)
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

    // MARK: - K8: Çevirim hassasiyeti

    /// `convert` sonucu hedef currency'nin minor unit hassasiyetinde (TRY=2)
    /// banker's round olmalı; aksi halde kuyruk birikip `sumInMaster`'da
    /// kayma yaratır.
    func test_K8_convert_roundsToTargetCurrencyDecimalPlaces() throws {
        // Kuyruğu uzun bir rate: 0.333333...
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "0.333333333333")!)

        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")

        // 100 * 0.333... = 33.3333... → TRY (2 ondalık) → 33.33
        XCTAssertEqual(result.amount, Decimal(string: "33.33"),
                       "Sonuç hedef currency ondalık hassasiyetine kırpılmalı")
    }

    /// Cache, aynı rate'i tekrar tekrar isterken aynı değeri dönmeli ve
    /// 8 ondalıktan fazla kuyruk taşımamalı (zincirleme conversion'larda
    /// belirsiz precision drift'i engeller).
    func test_K8_resolveRate_cachesAtFixedPrecision() throws {
        // Ters yön (1/rate) non-terminating üretir.
        try upsertRate(from: "TRY", to: "USD", rate: Decimal(string: "0.0285714285714286")!)

        let conv = makeConverter()
        let r1 = try conv.resolveRate(from: "USD", to: "TRY", on: "2026-05-07")
        let r2 = try conv.resolveRate(from: "USD", to: "TRY", on: "2026-05-07")

        XCTAssertEqual(r1, r2, "Cache aynı (deterministik) değeri dönmeli")

        // 1 / 0.0285714285714286 = 35.0000000000000... → 8 ondalığa
        // banker round → 35.00000000. Decimal scale ≤ 8 olmalı.
        let exponent = -r1.exponent
        XCTAssertLessThanOrEqual(exponent, 8, "Cache rate'i azami 8 ondalık tutmalı")
    }

    func test_manualRate_winsOverAutoSource() throws {
        // Aynı tarih için manuel ve TCMB kayıtları → manuel kazanmalı (sourcePriority listesinde manual ilk)
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "30")!, source: .tcmb)
        try upsertRate(from: "USD", to: "TRY", rate: Decimal(string: "35")!, source: .manual)

        let conv = makeConverter()
        let result = try conv.convert(Money(amount: 100, currency: "USD"), to: "TRY", on: "2026-05-07")
        XCTAssertEqual(result.amount, 3500, "Manuel kayıt otomatik kaynaklara önceliklidir")
    }
}
