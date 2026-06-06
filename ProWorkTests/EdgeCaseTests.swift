//  EdgeCaseTests.swift
//  ProWorkTests
//  daha önce kapsam dışı kalan kenar durumları:
//    • DST geçişi olan tarihler (Türkiye DST bırakmış olsa da legacy/
//      uluslararası veri için Calendar davranışı sabit kalmalı).
//    • Artık yıl 29 Şubat.
//    • Sıfır ve negatif `Money` davranışı (ayrı para üretmemeli, currency
//      bütünlüğü).

import XCTest
@testable import ProWork

final class EdgeCaseTests: XCTestCase {

    // MARK: - DST

    /// Avrupa/Istanbul DST 2016'da kalktı; öncesinde 2015-03-29 03:00'da
    /// yaza geçilirdi. Calendar bu tarihi doğru hesaplamalı; gün eklemek
    /// 24 saatlik literal değil, takvim günü olarak ilerlemeli.
    func test_O24_calendarRespectsHistoricalDSTTransition() throws {
        let cal = AppCalendar.istanbul
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.timeZone = cal.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let preDST = try XCTUnwrap(formatter.date(from: "2015-03-28 12:00:00"))
        let nextDay = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: preDST))

        let components = cal.dateComponents([.hour, .minute, .day, .month, .year], from: nextDay)
        XCTAssertEqual(components.year, 2015)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 29)
        // Saat 12 olarak kalmalı — bir saatlik DST atlama Calendar tarafından
        // absorbe edilir.
        XCTAssertEqual(components.hour, 12)
    }

    // MARK: - Artık yıl

    func test_O24_leapYearFebruary29IsValid() throws {
        let cal = AppCalendar.istanbul
        var components = DateComponents()
        components.year = 2024 // 2024 artık yıl
        components.month = 2
        components.day = 29
        let date = try XCTUnwrap(cal.date(from: components))
        let read = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(read.year, 2024)
        XCTAssertEqual(read.month, 2)
        XCTAssertEqual(read.day, 29)
    }

    func test_O24_nonLeapYearFebruary29RollsOver() throws {
        let cal = AppCalendar.istanbul
        var components = DateComponents()
        components.year = 2023 // 2023 artık yıl değil
        components.month = 2
        components.day = 29
        let date = try XCTUnwrap(cal.date(from: components))
        let read = cal.dateComponents([.year, .month, .day], from: date)
        // Foundation lenient mode: 29 Şubat 2023 → 1 Mart 2023
        XCTAssertEqual(read.year, 2023)
        XCTAssertEqual(read.month, 3)
        XCTAssertEqual(read.day, 1)
    }

    // MARK: - Money zero / negative

    func test_O24_zeroMoneyKeepsCurrency() {
        let zero = Money(minorUnits: 0, currency: "TRY")
        XCTAssertEqual(zero.minorUnits, 0)
        XCTAssertEqual(zero.currency, "TRY")
    }

    func test_O24_negativeMoneyArithmeticPreservesSign() {
        let owed = Money(minorUnits: -1500, currency: "TRY")
        let paid = Money(minorUnits: 500, currency: "TRY")
        let balance = owed + paid
        XCTAssertEqual(balance.minorUnits, -1000)
        XCTAssertEqual(balance.currency, "TRY")
    }

    func test_O24_moneyDecimalMultiplicationKeepsCurrency() {
        let amount = Money(minorUnits: 1234, currency: "USD")
        let scaled = amount * Decimal(string: "2.5")!
        XCTAssertEqual(scaled.currency, "USD")
        XCTAssertEqual(scaled.minorUnits, 3085) // 1234 * 2.5 = 3085
    }
}
