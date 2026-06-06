//  CustomerRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class CustomerRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: CustomerRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = CustomerRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - CRUD

    func test_insert_thenFetchById_returnsCustomer() throws {
        let customer = Customer(name: "Acme Ltd", code: "ACME", contactPerson: "Ali")
        try repository.insert(customer)

        let fetched = try repository.fetch(id: customer.id)
        XCTAssertEqual(fetched?.name, "Acme Ltd")
        XCTAssertEqual(fetched?.code, "ACME")
        XCTAssertEqual(fetched?.contactPerson, "Ali")
    }

    func test_fetchById_returnsNil_forUnknownId() throws {
        XCTAssertNil(try repository.fetch(id: UUID().uuidString))
    }

    func test_fetchAll_returnsResults_alphabeticallyByName() throws {
        try repository.insert(Customer(name: "Çiğdem"))
        try repository.insert(Customer(name: "Ali"))
        try repository.insert(Customer(name: "berkay"))

        // SQLite NOCASE collation Latin sıralaması — Çiğdem 'C' grubunda
        // değil özel karakter olarak en sonda gelir (en_US).
        let names = try repository.fetchAll().map(\.name)
        XCTAssertEqual(names, ["Ali", "berkay", "Çiğdem"])
    }

    func test_update_persistsChanges() throws {
        var customer = Customer(name: "Beta Ltd")
        try repository.insert(customer)

        customer.name = "Beta A.Ş."
        customer.defaultMinBillingMinutes = 30
        try repository.update(customer)

        let fetched = try repository.fetch(id: customer.id)
        XCTAssertEqual(fetched?.name, "Beta A.Ş.")
        XCTAssertEqual(fetched?.defaultMinBillingMinutes, 30)
    }

    // MARK: - Soft delete vs hard delete

    func test_softDelete_hidesFromFetchAll() throws {
        let kept = Customer(name: "Kalan")
        let deleted = Customer(name: "Silinen")
        try repository.insert(kept)
        try repository.insert(deleted)

        try repository.softDelete(id: deleted.id, by: BuiltInUserId.defaultOwner)

        let remaining = try repository.fetchAll().map(\.name)
        XCTAssertEqual(remaining, ["Kalan"])
    }

    func test_softDelete_hidesFromFetchById() throws {
        let customer = Customer(name: "Silinecek")
        try repository.insert(customer)
        try repository.softDelete(id: customer.id, by: BuiltInUserId.defaultOwner)

        XCTAssertNil(try repository.fetch(id: customer.id))
    }

    func test_hardDelete_removesRowEntirely() throws {
        let customer = Customer(name: "Silinecek")
        try repository.insert(customer)
        try repository._hardDelete(id: customer.id)

        XCTAssertNil(try repository.fetch(id: customer.id))
        XCTAssertEqual(try repository.fetchAll().count, 0)
    }

    // MARK: - Defaults round-trip

    func test_defaults_roundTrip_throughInsertFetch() throws {
        let customer = Customer(name: "Defaults")
        try repository.insert(customer)

        let fetched = try repository.fetch(id: customer.id)
        XCTAssertEqual(fetched?.isActive, true)
        XCTAssertEqual(fetched?.defaultServiceType, "remote")
        XCTAssertEqual(fetched?.defaultMinBillingMinutes, 60)
        XCTAssertNil(fetched?.vatRateId)
    }
}
