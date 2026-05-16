//
//  PriceListRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//

import XCTest
@testable import ProWork

final class PriceListRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: PriceListRepository!
    private var customerRepository: CustomerRepository!
    private var customer: Customer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = PriceListRepository()
        customerRepository = CustomerRepository()
        customer = Customer(name: "Müşteri A")
        try customerRepository.insert(customer)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - CRUD

    func test_insert_thenFetchById_returnsList() throws {
        let list = PriceList(
            ownerType: .customer,
            ownerId: customer.id,
            name: "qa-Customer fiyat",
            currency: "USD"
        )
        try repository.insert(list)

        let fetched = try repository.fetch(id: list.id)
        XCTAssertEqual(fetched?.name, "qa-Customer fiyat")
        XCTAssertEqual(fetched?.currency, "USD")
        XCTAssertEqual(fetched?.ownerType, .customer)
        XCTAssertEqual(fetched?.ownerId, customer.id)
    }

    func test_update_persistsCurrencyAndDefault() throws {
        var list = PriceList(
            ownerType: .global,
            name: "qa-Global",
            currency: "TRY"
        )
        try repository.insert(list)

        list.currency = "EUR"
        list.isDefault = true
        try repository.update(list)

        let fetched = try repository.fetch(id: list.id)
        XCTAssertEqual(fetched?.currency, "EUR")
        XCTAssertEqual(fetched?.isDefault, true)
    }

    // MARK: - fetchOwned semantics

    func test_fetchOwned_filtersByOwnerType_andOwnerId() throws {
        let other = Customer(name: "Diğer Müşteri")
        try customerRepository.insert(other)

        try repository.insert(PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-Mine", currency: "TRY"))
        try repository.insert(PriceList(ownerType: .customer, ownerId: other.id,    name: "qa-Theirs", currency: "TRY"))
        try repository.insert(PriceList(ownerType: .global,                          name: "qa-Global", currency: "TRY"))

        let mine = try repository.fetchOwned(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .customer,
            ownerId: customer.id
        )
        XCTAssertEqual(mine.map(\.name), ["qa-Mine"])

        let globals = try repository.fetchOwned(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .global,
            ownerId: nil
        )
        XCTAssertEqual(globals.map(\.name), ["qa-Global"])
    }

    func test_fetchOwned_sortsDefaultFirst() throws {
        try repository.insert(PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-Aktif", currency: "TRY", isDefault: false))
        try repository.insert(PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-Default", currency: "TRY", isDefault: true))
        try repository.insert(PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-Yedek", currency: "TRY", isDefault: false))

        let owned = try repository.fetchOwned(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .customer,
            ownerId: customer.id
        )
        XCTAssertEqual(owned.first?.name, "qa-Default", "isDefault=true en başta gelmeli")
    }

    // MARK: - fetchDefault

    func test_fetchDefault_returnsTheRowMarkedDefault() throws {
        try repository.insert(PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-A", currency: "TRY"))
        try repository.insert(PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-B", currency: "TRY", isDefault: true))

        let def = try repository.fetchDefault(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .customer,
            ownerId: customer.id
        )
        XCTAssertEqual(def?.name, "qa-B")
    }

    func test_fetchDefault_returnsNil_whenNoneMarked() throws {
        try repository.insert(PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-Sadece", currency: "TRY"))

        let def = try repository.fetchDefault(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .customer,
            ownerId: customer.id
        )
        XCTAssertNil(def)
    }

    // MARK: - Soft delete

    func test_softDelete_hidesFromFetchOwned() throws {
        let keep = PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-Kalan", currency: "TRY")
        let drop = PriceList(ownerType: .customer, ownerId: customer.id, name: "qa-Silinen", currency: "TRY")
        try repository.insert(keep)
        try repository.insert(drop)

        try repository.softDelete(id: drop.id)

        let owned = try repository.fetchOwned(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .customer,
            ownerId: customer.id
        )
        XCTAssertEqual(owned.map(\.name), ["qa-Kalan"])
    }
}
