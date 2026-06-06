//  TaskCategoryRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class TaskCategoryRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: TaskCategoryRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = TaskCategoryRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - CRUD

    func test_insert_thenFetchById_returnsCategory() throws {
        let category = TaskCategory(name: "Geliştirme", color: "#3B82F6", isBillableDefault: true)
        try repository.insert(category)

        let fetched = try repository.fetch(id: category.id)
        XCTAssertEqual(fetched?.name, "Geliştirme")
        XCTAssertEqual(fetched?.color, "#3B82F6")
        XCTAssertEqual(fetched?.isBillableDefault, true)
    }

    func test_fetchById_returnsNil_forUnknownId() throws {
        XCTAssertNil(try repository.fetch(id: UUID().uuidString))
    }

    func test_fetchAll_sortsBySortOrder_thenName() throws {
        // Migration001 11 sistem kategorisi seed eder (sortOrder 10-110).
        // Test, eklediği kayıtları seed'den ayırt etmek için "qa-" prefix'i
        // ve seed'in tepesinde kalmayacak yüksek sortOrder'lar kullanır.
        try repository.insert(TaskCategory(name: "qa-Bakım",   sortOrder: 9_020))
        try repository.insert(TaskCategory(name: "qa-Analiz",  sortOrder: 9_010))
        try repository.insert(TaskCategory(name: "qa-Yazılım", sortOrder: 9_010))

        let qaNames = try repository.fetchAll()
            .filter { $0.name.hasPrefix("qa-") }
            .map(\.name)
        XCTAssertEqual(qaNames, ["qa-Analiz", "qa-Yazılım", "qa-Bakım"])
    }

    func test_update_persistsChanges() throws {
        var category = TaskCategory(name: "Eski", isBillableDefault: true)
        try repository.insert(category)

        category.name = "Yeni"
        category.isBillableDefault = false
        try repository.update(category)

        let fetched = try repository.fetch(id: category.id)
        XCTAssertEqual(fetched?.name, "Yeni")
        XCTAssertEqual(fetched?.isBillableDefault, false)
    }

    // MARK: - Soft vs hard delete

    func test_softDelete_hidesFromFetchAll() throws {
        let kept = TaskCategory(name: "qa-Kalan")
        let deleted = TaskCategory(name: "qa-Silinen")
        try repository.insert(kept)
        try repository.insert(deleted)

        try repository.softDelete(id: deleted.id, by: BuiltInUserId.defaultOwner)

        let remaining = try repository.fetchAll()
            .filter { $0.name.hasPrefix("qa-") }
            .map(\.name)
        XCTAssertEqual(remaining, ["qa-Kalan"])
    }

    func test_hardDelete_removesRowEntirely() throws {
        let category = TaskCategory(name: "Silinecek")
        try repository.insert(category)
        try repository._hardDelete(id: category.id)

        XCTAssertNil(try repository.fetch(id: category.id))
    }

    // MARK: - Defaults

    func test_defaults_roundTrip_throughInsertFetch() throws {
        let category = TaskCategory(name: "Defaults")
        try repository.insert(category)

        let fetched = try repository.fetch(id: category.id)
        XCTAssertEqual(fetched?.isBillableDefault, true)
        XCTAssertEqual(fetched?.isSystem, false)
        XCTAssertEqual(fetched?.sortOrder, 0)
        XCTAssertNil(fetched?.vatRateId)
        XCTAssertNil(fetched?.color)
    }
}
