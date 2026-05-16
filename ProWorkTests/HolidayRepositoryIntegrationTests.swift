//
//  HolidayRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//

import XCTest
@testable import ProWork

final class HolidayRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: HolidayRepository!
    private var customerRepository: CustomerRepository!
    private var customer: Customer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = HolidayRepository()
        customerRepository = CustomerRepository()
        customer = Customer(name: "Müşteri A")
        try customerRepository.insert(customer)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Seeded holidays + custom CRUD

    func test_fetchAll_includesSeededTurkishHolidays() throws {
        let holidays = try repository.fetchAll(organizationId: BuiltInOrganizationId.default)
        // Migration001 23 Nisan'ı (Ulusal Egemenlik) seed eder.
        XCTAssertTrue(holidays.contains { $0.name.contains("Ulusal Egemenlik") })
    }

    func test_insert_thenFetchAll_returnsCustomHoliday() throws {
        let holiday = Holiday(
            scope: .global,
            dateString: "2099-12-25",
            name: "qa-Test Tatili",
            isHalfDay: false
        )
        try repository.insert(holiday)

        let inserted = try repository.fetchAll(organizationId: BuiltInOrganizationId.default)
            .first(where: { $0.name == "qa-Test Tatili" })
        XCTAssertNotNil(inserted)
        XCTAssertEqual(inserted?.dateString, "2099-12-25")
        XCTAssertEqual(inserted?.scope, .global)
    }

    // MARK: - fetchForDate

    func test_fetchForDate_returnsGlobalHolidays_whenNoCustomerProvided() throws {
        let date = "2099-11-11"
        try repository.insert(Holiday(scope: .global, dateString: date, name: "qa-Global"))
        try repository.insert(Holiday(
            scope: .customer,
            customerId: customer.id,
            dateString: date,
            name: "qa-CustomerOnly"
        ))

        let matches = try repository.fetchForDate(
            organizationId: BuiltInOrganizationId.default,
            date: date,
            customerId: nil
        )

        let names = matches.map(\.name)
        XCTAssertTrue(names.contains("qa-Global"))
        XCTAssertFalse(
            names.contains("qa-CustomerOnly"),
            "customerId verilmediğinde scope=customer satırları döndürülmemeli"
        )
    }

    func test_fetchForDate_returnsGlobalAndCustomerHolidays_whenCustomerProvided() throws {
        let date = "2099-10-10"
        try repository.insert(Holiday(scope: .global, dateString: date, name: "qa-Global"))
        try repository.insert(Holiday(
            scope: .customer,
            customerId: customer.id,
            dateString: date,
            name: "qa-CustomerOnly"
        ))

        let matches = try repository.fetchForDate(
            organizationId: BuiltInOrganizationId.default,
            date: date,
            customerId: customer.id
        )

        let names = Set(matches.map(\.name))
        XCTAssertTrue(names.contains("qa-Global"))
        XCTAssertTrue(names.contains("qa-CustomerOnly"))
    }

    // MARK: - Active filter

    func test_fetchAll_excludesInactive_unlessIncludingInactiveSet() throws {
        let date = "2099-09-09"
        try repository.insert(Holiday(scope: .global, dateString: date, name: "qa-Active", isActive: true))
        try repository.insert(Holiday(scope: .global, dateString: date, name: "qa-Inactive", isActive: false))

        let activeOnly = try repository.fetchAll(
            organizationId: BuiltInOrganizationId.default,
            includingInactive: false
        )
        XCTAssertTrue(activeOnly.contains { $0.name == "qa-Active" })
        XCTAssertFalse(activeOnly.contains { $0.name == "qa-Inactive" })

        let allRows = try repository.fetchAll(
            organizationId: BuiltInOrganizationId.default,
            includingInactive: true
        )
        XCTAssertTrue(allRows.contains { $0.name == "qa-Inactive" })
    }

    // MARK: - Update + soft delete

    func test_update_persistsNameAndHalfDayFlag() throws {
        var holiday = Holiday(
            scope: .global,
            dateString: "2099-08-08",
            name: "qa-Original",
            isHalfDay: false
        )
        try repository.insert(holiday)

        holiday.name = "qa-Updated"
        holiday.isHalfDay = true
        holiday.halfDayCutoff = TimeOfDay(hour: 13, minute: 0)
        try repository.update(holiday)

        let fetched = try repository.fetchAll(organizationId: BuiltInOrganizationId.default)
            .first(where: { $0.id == holiday.id })
        XCTAssertEqual(fetched?.name, "qa-Updated")
        XCTAssertEqual(fetched?.isHalfDay, true)
    }

    func test_softDelete_hidesFromFetchAll() throws {
        let holiday = Holiday(scope: .global, dateString: "2099-07-07", name: "qa-Soft")
        try repository.insert(holiday)

        try repository.softDelete(id: holiday.id)

        let remaining = try repository.fetchAll(organizationId: BuiltInOrganizationId.default, includingInactive: true)
        XCTAssertFalse(remaining.contains { $0.name == "qa-Soft" })
    }
}
