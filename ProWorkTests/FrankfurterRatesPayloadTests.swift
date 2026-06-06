//  FrankfurterRatesPayloadTests.swift
//  ProWorkTests
//  Frankfurter JSON yanıtındaki kur değerlerinin
//  `Decimal` olarak Double round-trip yapmadan parse edildiğini doğrular.

import XCTest
@testable import ProWork

final class FrankfurterRatesPayloadTests: XCTestCase {

    func test_decode_preservesDecimalPrecision_forShortFractionalRate() throws {
        let json = """
        {
          "amount": 1.0,
          "base": "TRY",
          "date": "2026-05-17",
          "rates": { "USD": 0.0234 }
        }
        """.data(using: .utf8)!

        let payload = try FrankfurterRatesPayload.decode(from: json)

        XCTAssertEqual(payload.date, "2026-05-17")
        let usd = try XCTUnwrap(payload.rates["USD"])
        XCTAssertEqual(usd, Decimal(string: "0.0234"),
                       "Decimal should reconstruct from canonical text, not from Double round-trip")
    }

    func test_decode_preservesPrecision_forManyDecimalPlaces() throws {
        let json = """
        {
          "date": "2026-05-17",
          "rates": { "EUR": 0.034567, "GBP": 0.029988 }
        }
        """.data(using: .utf8)!

        let payload = try FrankfurterRatesPayload.decode(from: json)
        XCTAssertEqual(payload.rates["EUR"], Decimal(string: "0.034567"))
        XCTAssertEqual(payload.rates["GBP"], Decimal(string: "0.029988"))
    }

    func test_decode_handlesIntegerValues() throws {
        let json = """
        {
          "date": "2026-05-17",
          "rates": { "JPY": 5 }
        }
        """.data(using: .utf8)!

        let payload = try FrankfurterRatesPayload.decode(from: json)
        XCTAssertEqual(payload.rates["JPY"], Decimal(5))
    }

    func test_decode_acceptsStringNumbers() throws {
        // Bazı kaynaklar (örn. proxy'den geçen yanıtlar) "0.0234" gibi
        // string olarak gönderebilir; aynı kanaldan parse edebilmeliyiz.
        let json = """
        {
          "date": "2026-05-17",
          "rates": { "USD": "0.0234" }
        }
        """.data(using: .utf8)!

        let payload = try FrankfurterRatesPayload.decode(from: json)
        XCTAssertEqual(payload.rates["USD"], Decimal(string: "0.0234"))
    }

    func test_decode_skipsNonNumericEntries() throws {
        let json = """
        {
          "date": "2026-05-17",
          "rates": { "USD": 0.0234, "BAD": null }
        }
        """.data(using: .utf8)!

        let payload = try FrankfurterRatesPayload.decode(from: json)
        XCTAssertEqual(payload.rates["USD"], Decimal(string: "0.0234"))
        XCTAssertNil(payload.rates["BAD"])
    }
}
