//  PriceListRowRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class PriceListRowRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var rowRepository: PriceListRowRepository!
    private var listRepository: PriceListRepository!
    private var priceList: PriceList!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        rowRepository = PriceListRowRepository()
        listRepository = PriceListRepository()
        priceList = PriceList(
            ownerType: .global,
            name: "qa-Test Liste",
            currency: "TRY"
        )
        try listRepository.insert(priceList)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - CRUD

    func test_insert_thenFetchAll_returnsRow() throws {
        let row = makeRow(unitPriceMinor: 50_00, serviceType: .remote, timeType: .regular)
        try rowRepository.insert(row)

        let rows = try rowRepository.fetchAll(priceListId: priceList.id)
        XCTAssertEqual(rows.count, 1)
        let fetched = try XCTUnwrap(rows.first)
        XCTAssertEqual(fetched.unitPriceMinor, 50_00)
        XCTAssertEqual(fetched.serviceType, .remote)
        XCTAssertEqual(fetched.timeType, .regular)
        XCTAssertEqual(fetched.currency, "TRY")
    }

    func test_update_persistsPriceAndWindow() throws {
        var row = makeRow(unitPriceMinor: 30_00)
        try rowRepository.insert(row)

        row.unitPriceMinor = 75_00
        row.minimumWindowMinutes = 60
        try rowRepository.update(row)

        let fetched = try XCTUnwrap(try rowRepository.fetchAll(priceListId: priceList.id).first)
        XCTAssertEqual(fetched.unitPriceMinor, 75_00)
        XCTAssertEqual(fetched.minimumWindowMinutes, 60)
    }

    func test_fetchAll_sortsBySortOrder_thenServiceType_thenTimeType() throws {
        try rowRepository.insert(makeRow(unitPriceMinor: 1, sortOrder: 20, serviceType: .remote))
        try rowRepository.insert(makeRow(unitPriceMinor: 2, sortOrder: 10, serviceType: .remote, timeType: .holiday))
        try rowRepository.insert(makeRow(unitPriceMinor: 3, sortOrder: 10, serviceType: .remote, timeType: .regular))

        let rows = try rowRepository.fetchAll(priceListId: priceList.id)
        // 10/regular gelir, 10/holiday gelir (timeType alfabetik: holiday > regular,
        // bu test ASC ile teyit ediyor), sonra 20.
        XCTAssertEqual(rows.map(\.unitPriceMinor), [2, 3, 1])
    }

    // MARK: - fetchActive scope

    func test_fetchActive_filtersByDateRange() throws {
        try rowRepository.insert(makeRow(unitPriceMinor: 1, validFrom: "2026-01-01", validTo: "2026-12-31"))
        try rowRepository.insert(makeRow(unitPriceMinor: 2, validFrom: "2027-01-01", validTo: nil))
        try rowRepository.insert(makeRow(unitPriceMinor: 3, validFrom: nil, validTo: nil))

        // Hedef tarih 2026-06-15: 1 ve 3 aktif; 2 henüz geçerli değil.
        let active = try rowRepository.fetchActive(priceListId: priceList.id, on: "2026-06-15")
        XCTAssertEqual(Set(active.map(\.unitPriceMinor)), [1, 3])
    }

    func test_fetchActive_excludesInactiveRows() throws {
        try rowRepository.insert(makeRow(unitPriceMinor: 10, isActive: true))
        try rowRepository.insert(makeRow(unitPriceMinor: 20, isActive: false))

        let active = try rowRepository.fetchActive(priceListId: priceList.id, on: "2026-06-15")
        XCTAssertEqual(active.map(\.unitPriceMinor), [10])
    }

    // MARK: - Soft delete

    func test_softDelete_hidesRowFromFetchAll() throws {
        let kept = makeRow(unitPriceMinor: 1)
        let deleted = makeRow(unitPriceMinor: 2)
        try rowRepository.insert(kept)
        try rowRepository.insert(deleted)

        try rowRepository.softDelete(id: deleted.id, by: BuiltInUserId.defaultOwner)

        let rows = try rowRepository.fetchAll(priceListId: priceList.id).map(\.unitPriceMinor)
        XCTAssertEqual(rows, [1])
    }

    // MARK: - Helper

    private func makeRow(
        unitPriceMinor: Int,
        sortOrder: Int = 0,
        serviceType: ServiceType = .remote,
        timeType: TimeType = .regular,
        validFrom: String? = nil,
        validTo: String? = nil,
        isActive: Bool = true
    ) -> PriceListRow {
        PriceListRow(
            priceListId: priceList.id,
            serviceType: serviceType,
            timeType: timeType,
            categoryId: nil,
            unitPriceMinor: unitPriceMinor,
            currency: "TRY",
            validFrom: validFrom,
            validTo: validTo,
            isActive: isActive,
            sortOrder: sortOrder
        )
    }
}
