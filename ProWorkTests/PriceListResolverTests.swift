//
//  PriceListResolverTests.swift
//  ProWorkTests
//
//  Spec §3 — Fiyat öncelik sırası: task override → proje → müşteri → genel
//

import XCTest
@testable import ProWork

final class PriceListResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeRow(
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

    private func emptyContext() -> PriceResolutionContext {
        PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: [:]
        )
    }

    // MARK: - §3 Öncelik

    func test_taskFixedFeeOverride_winsOverEverything() {
        var context = emptyContext()
        context.todoOverride = TodoBillingOverride(
            todoId: "todo1",
            overrideType: .fixedFee,
            fixedFeeMinor: 500_000,
            currency: "TRY"
        )
        context.globalPriceLists = [PriceList(ownerType: .global, name: "Global", currency: "TRY")]
        context.rowsByListId = [
            "global-list": [makeRow(listId: "global-list", unit: 100_000)]
        ]

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote,
            timeType: .regular,
            categoryId: nil,
            weekday: .monday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        if case .todoFixedFee(let amount, let cur) = result {
            XCTAssertEqual(amount, 500_000)
            XCTAssertEqual(cur, "TRY")
        } else {
            XCTFail("fixedFee bekleniyordu, alındı: \(result)")
        }
    }

    func test_projectList_winsOverCustomerAndGlobal() {
        let projectList = PriceList(id: "p", ownerType: .project, name: "Proje Listesi", currency: "TRY")
        let customerList = PriceList(id: "c", ownerType: .customer, name: "Müşteri Listesi", currency: "TRY")
        let globalList = PriceList(id: "g", ownerType: .global, name: "Genel", currency: "TRY")

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [projectList],
            customerPriceLists: [customerList],
            globalPriceLists: [globalList],
            organizationCurrency: "TRY",
            rowsByListId: [
                "p": [makeRow(listId: "p", unit: 300_000)],
                "c": [makeRow(listId: "c", unit: 200_000)],
                "g": [makeRow(listId: "g", unit: 100_000)]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote,
            timeType: .regular,
            categoryId: nil,
            weekday: .monday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(let row, let owner) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(row.unitPriceMinor, 300_000)
        XCTAssertEqual(owner, .project)
    }

    func test_customerList_winsWhenNoProjectList() {
        let customerList = PriceList(id: "c", ownerType: .customer, name: "Müşteri", currency: "TRY")
        let globalList = PriceList(id: "g", ownerType: .global, name: "Genel", currency: "TRY")

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [customerList],
            globalPriceLists: [globalList],
            organizationCurrency: "TRY",
            rowsByListId: [
                "c": [makeRow(listId: "c", unit: 200_000)],
                "g": [makeRow(listId: "g", unit: 100_000)]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .regular,
            categoryId: nil, weekday: .monday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(_, let owner) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(owner, .customer)
    }

    func test_categorySpecificRow_beatsGenericRow() {
        // Aynı listede iki satır: biri kategori belirli, diğeri kategori NULL.
        let list = PriceList(id: "L", ownerType: .global, name: "Genel", currency: "TRY")
        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [list],
            organizationCurrency: "TRY",
            rowsByListId: [
                "L": [
                    makeRow(listId: "L", unit: 100_000, category: nil),
                    makeRow(listId: "L", unit: 250_000, category: "dev")
                ]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .regular,
            categoryId: "dev", weekday: .monday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(let row, _) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(row.unitPriceMinor, 250_000)
    }

    func test_holidayTimeType_fallsBackToWeekendThenAfterHoursThenRegular() {
        // Sadece 'regular' satır var, holiday tarafında fallback'le bulmalı.
        let list = PriceList(id: "L", ownerType: .global, name: "Genel", currency: "TRY")
        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [list],
            organizationCurrency: "TRY",
            rowsByListId: [
                "L": [makeRow(listId: "L", unit: 100_000, timeType: .regular)]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .holiday,
            categoryId: nil, weekday: .monday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        // Fallback ile regular satırına düştü
        if case .row(let row, _) = result {
            XCTAssertEqual(row.unitPriceMinor, 100_000)
            XCTAssertEqual(row.timeType, .regular)
        } else {
            XCTFail("regular satırına fallback bekleniyordu")
        }
    }

    // MARK: - Tarih aralığı filtresi

    func test_priceList_outsideValidityWindow_isIgnored() {
        // Liste 2026-01-01 → 2026-04-30 arası geçerli; sorgu 2026-05-07 → geçersiz.
        // Müşteri listesi geçersiz olduğu için global listeye düşmeli.
        let expiredCustomerList = PriceList(
            id: "C-expired",
            ownerType: .customer,
            name: "Eski Müşteri Listesi",
            currency: "TRY",
            validFrom: "2026-01-01",
            validTo: "2026-04-30"
        )
        let globalList = PriceList(id: "G", ownerType: .global, name: "Genel", currency: "TRY")

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [expiredCustomerList],
            globalPriceLists: [globalList],
            organizationCurrency: "TRY",
            rowsByListId: [
                "C-expired": [makeRow(listId: "C-expired", unit: 999_999)],
                "G": [makeRow(listId: "G", unit: 100_000)]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .regular,
            categoryId: nil, weekday: .thursday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(let row, let owner) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(owner, .global, "Müşteri listesi tarih dışı → global'e düşmeli")
        XCTAssertEqual(row.unitPriceMinor, 100_000)
    }

    func test_priceList_validFromInFuture_isIgnored() {
        // Liste 2026-06-01'de başlıyor; sorgu 2026-05-07 → geçersiz.
        let futureList = PriceList(
            id: "C-future",
            ownerType: .customer,
            name: "Yeni Liste",
            currency: "TRY",
            validFrom: "2026-06-01",
            validTo: nil
        )
        let globalList = PriceList(id: "G", ownerType: .global, name: "Genel", currency: "TRY")

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [futureList],
            globalPriceLists: [globalList],
            organizationCurrency: "TRY",
            rowsByListId: [
                "C-future": [makeRow(listId: "C-future", unit: 888_888)],
                "G": [makeRow(listId: "G", unit: 50_000)]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .regular,
            categoryId: nil, weekday: .thursday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(let row, _) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(row.unitPriceMinor, 50_000, "Henüz başlamamış liste atlanmalı")
    }

    func test_priceListRow_outsideValidityWindow_isIgnored() {
        // Listede iki satır: biri eski (2025), biri yeni (2026'dan başlıyor).
        // Sorgu 2026-05-07 → yalnızca yeni satır eşleşmeli.
        let list = PriceList(id: "L", ownerType: .global, name: "Genel", currency: "TRY")
        let oldRow = PriceListRow(
            priceListId: "L",
            serviceType: .remote,
            timeType: .regular,
            unitPriceMinor: 100_000,
            validFrom: "2025-01-01",
            validTo: "2025-12-31"
        )
        let newRow = PriceListRow(
            priceListId: "L",
            serviceType: .remote,
            timeType: .regular,
            unitPriceMinor: 250_000,
            validFrom: "2026-01-01",
            validTo: nil
        )

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [list],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [oldRow, newRow]]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .regular,
            categoryId: nil, weekday: .thursday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(let row, _) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(row.unitPriceMinor, 250_000)
    }

    func test_softDeletedPriceList_isIgnored() {
        var deletedList = PriceList(id: "C", ownerType: .customer, name: "Silinmiş", currency: "TRY")
        deletedList.deletedAt = Date()
        let globalList = PriceList(id: "G", ownerType: .global, name: "Genel", currency: "TRY")

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [deletedList],
            globalPriceLists: [globalList],
            organizationCurrency: "TRY",
            rowsByListId: [
                "C": [makeRow(listId: "C", unit: 999_999)],
                "G": [makeRow(listId: "G", unit: 100_000)]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .regular,
            categoryId: nil, weekday: .monday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(_, let owner) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(owner, .global)
    }

    func test_inactivePriceList_isIgnored() {
        var inactiveList = PriceList(id: "C", ownerType: .customer, name: "Kapalı", currency: "TRY")
        inactiveList.isActive = false
        let globalList = PriceList(id: "G", ownerType: .global, name: "Genel", currency: "TRY")

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [inactiveList],
            globalPriceLists: [globalList],
            organizationCurrency: "TRY",
            rowsByListId: [
                "C": [makeRow(listId: "C", unit: 999_999)],
                "G": [makeRow(listId: "G", unit: 100_000)]
            ]
        )

        let result = PriceListResolver.resolve(
            context: context,
            serviceType: .remote, timeType: .regular,
            categoryId: nil, weekday: .monday,
            timeOfDay: TimeOfDay(hour: 10, minute: 0),
            dateString: "2026-05-07"
        )

        guard case .row(_, let owner) = result else {
            XCTFail("row bekleniyordu")
            return
        }
        XCTAssertEqual(owner, .global)
    }
}
