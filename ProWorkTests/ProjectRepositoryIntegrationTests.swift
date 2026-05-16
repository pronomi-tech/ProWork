//
//  ProjectRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//

import XCTest
@testable import ProWork

final class ProjectRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: ProjectRepository!
    private var customerRepository: CustomerRepository!
    private var customer: Customer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = ProjectRepository()
        customerRepository = CustomerRepository()
        customer = Customer(name: "Müşteri A", code: "MA")
        try customerRepository.insert(customer)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Single CRUD

    func test_insert_thenFetchById_returnsProject() throws {
        let project = makeProject(name: "İlk proje")
        try repository.insert(project)

        let fetched = try repository.fetch(id: project.id)
        XCTAssertEqual(fetched?.name, "İlk proje")
        XCTAssertEqual(fetched?.customerId, customer.id)
    }

    func test_fetchAll_joinsCustomerName_andSortsAlphabetically() throws {
        try repository.insert(makeProject(name: "Beta"))
        try repository.insert(makeProject(name: "Alpha"))

        let listItems = try repository.fetchAll()
        XCTAssertEqual(listItems.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(Set(listItems.map(\.customerName)), [customer.name])
    }

    func test_update_persistsChanges() throws {
        var project = makeProject(name: "Eski")
        try repository.insert(project)
        project.name = "Yeni"
        project.defaultMinBillingMinutes = 15
        try repository.update(project)

        let fetched = try repository.fetch(id: project.id)
        XCTAssertEqual(fetched?.name, "Yeni")
        XCTAssertEqual(fetched?.defaultMinBillingMinutes, 15)
    }

    // MARK: - Bulk fetch

    func test_fetchByIds_returnsOnlyMatching_andSkipsMissing() throws {
        let a = makeProject(name: "A")
        let b = makeProject(name: "B")
        try repository.insert(a)
        try repository.insert(b)

        let result = try repository.fetch(ids: [a.id, "missing", b.id])
        XCTAssertEqual(Set(result.map(\.id)), [a.id, b.id])
    }

    func test_fetchByIds_emptyInput_returnsEmpty() throws {
        XCTAssertEqual(try repository.fetch(ids: []).count, 0)
    }

    func test_fetchByIds_skipsSoftDeletedProjects() throws {
        let a = makeProject(name: "A")
        let b = makeProject(name: "B")
        try repository.insert(a)
        try repository.insert(b)
        try repository.softDelete(id: a.id)

        let result = try repository.fetch(ids: [a.id, b.id])
        XCTAssertEqual(result.map(\.id), [b.id])
    }

    // MARK: - Soft delete vs hard delete

    func test_softDelete_hidesProjectFromFetchAll() throws {
        let kept = makeProject(name: "Kalan")
        let deleted = makeProject(name: "Silinen")
        try repository.insert(kept)
        try repository.insert(deleted)

        try repository.softDelete(id: deleted.id)

        let remaining = try repository.fetchAll().map(\.name)
        XCTAssertEqual(remaining, ["Kalan"])
    }

    func test_hardDelete_removesRowEntirely() throws {
        let project = makeProject(name: "Silinecek")
        try repository.insert(project)
        try repository.delete(id: project.id)

        XCTAssertNil(try repository.fetch(id: project.id))
    }

    // MARK: - Helper

    private func makeProject(name: String) -> Project {
        Project(
            customerId: customer.id,
            name: name,
            status: "active"
        )
    }
}
