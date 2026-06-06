//  BillingFixtures.swift
//  ProWorkTests
//  Faturalandırma test'lerinde kopyalanan helper'ların tek otoriteli kaynağı
//. Önceki durumda `date(...)`, `standardRule()`, `makeRow(...)`
//  her dosyada birebir aynı kodla tekrar ediyordu.

import Foundation
@testable import ProWork

enum BillingFixtures {

    /// Tüm faturalandırma test'leri Istanbul takvimi üzerine kuruludur.
    static let calendar: Calendar = TimeWindowSplitter.istanbulCalendar

    /// `Europe/Istanbul` saat dilimine sabitlenmiş tarih üreticisi.
    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return calendar.date(from: components)!
    }

    /// Pazartesi–Cuma 09:00–18:00, Cumartesi/Pazar hafta sonu — birim test'lerin
    /// büyük çoğunluğunun beklediği standart kural.
    static func standardRule() -> BillingRule {
        let workHours = DailyWorkHours(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0)
        )
        return BillingRule(
            scope: .global,
            weekdayHours: [
                .monday: workHours,
                .tuesday: workHours,
                .wednesday: workHours,
                .thursday: workHours,
                .friday: workHours
            ],
            weekendDays: [.saturday, .sunday]
        )
    }

    /// Standart KDV calculator (%20 default oran).
    static func standardVatCalculator() -> VATCalculator {
        VATCalculator(rates: [
            VatRate(
                id: "std",
                name: "Std",
                rate: Decimal(string: "0.20")!,
                isDefault: true
            )
        ])
    }

    /// `PriceListRow` üretici. PriceListResolverTests'ten taşınmıştır.
    static func makeRow(
        listId: String,
        unit: Int,
        category: String? = nil,
        timeType: TimeType = .regular,
        service: ServiceType = .remote
    ) -> PriceListRow {
        PriceListRow(
            priceListId: listId,
            serviceType: service,
            timeType: timeType,
            categoryId: category,
            unitPriceMinor: unit
        )
    }

    /// Tüm kovaları boş bırakılmış bir `PriceResolutionContext`.
    static func emptyPriceContext() -> PriceResolutionContext {
        PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: [:]
        )
    }
}
