//
//  TodoStatusRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//

import XCTest
@testable import ProWork

final class TodoStatusRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: TodoStatusRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = TodoStatusRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Built-in seed

    func test_fetchAll_includesBuiltInStatuses() throws {
        let statuses = try repository.fetchAll()
        let ids = Set(statuses.map(\.id))
        XCTAssertTrue(ids.contains(BuiltInTodoStatusId.waiting))
        XCTAssertTrue(ids.contains(BuiltInTodoStatusId.inProgress))
        XCTAssertTrue(ids.contains(BuiltInTodoStatusId.done))
        XCTAssertTrue(ids.contains(BuiltInTodoStatusId.cancelled))
    }

    func test_fetchById_returnsBuiltInWaiting() throws {
        let waiting = try repository.fetch(id: BuiltInTodoStatusId.waiting)
        XCTAssertNotNil(waiting)
        XCTAssertEqual(waiting?.isSystem, true)
    }

    // MARK: - Custom CRUD

    func test_insert_thenFetchById_returnsCustomStatus() throws {
        let status = TodoStatus(
            name: "qa-Beklemede",
            color: "#FF0000",
            sortOrder: 9_010,
            isSystem: false,
            startsTimer: true
        )
        try repository.insert(status)

        let fetched = try repository.fetch(id: status.id)
        XCTAssertEqual(fetched?.name, "qa-Beklemede")
        XCTAssertEqual(fetched?.color, "#FF0000")
        XCTAssertEqual(fetched?.startsTimer, true)
        XCTAssertEqual(fetched?.isSystem, false)
    }

    func test_fetchAll_sortsBySortOrder_thenName_forCustomRows() throws {
        try repository.insert(TodoStatus(name: "qa-Beklemede", sortOrder: 9_020))
        try repository.insert(TodoStatus(name: "qa-Aktif",     sortOrder: 9_010))
        try repository.insert(TodoStatus(name: "qa-Yedek",     sortOrder: 9_010))

        let qaNames = try repository.fetchAll()
            .filter { $0.name.hasPrefix("qa-") }
            .map(\.name)
        XCTAssertEqual(qaNames, ["qa-Aktif", "qa-Yedek", "qa-Beklemede"])
    }

    func test_update_persistsBehaviorChange() throws {
        var status = TodoStatus(name: "qa-Status", startsTimer: false, stopsTimer: true)
        try repository.insert(status)

        status.startsTimer = true
        status.stopsTimer = false
        try repository.update(status)

        let fetched = try repository.fetch(id: status.id)
        XCTAssertEqual(fetched?.startsTimer, true)
        XCTAssertEqual(fetched?.stopsTimer, false)
    }

    // MARK: - Soft delete vs hard delete

    func test_softDelete_hidesFromFetchAll() throws {
        let kept = TodoStatus(name: "qa-Kalan")
        let deleted = TodoStatus(name: "qa-Silinen")
        try repository.insert(kept)
        try repository.insert(deleted)

        try repository.softDelete(id: deleted.id)

        let remaining = try repository.fetchAll()
            .filter { $0.name.hasPrefix("qa-") }
            .map(\.name)
        XCTAssertEqual(remaining, ["qa-Kalan"])
    }

    func test_hardDelete_removesRowEntirely() throws {
        let status = TodoStatus(name: "qa-Silinecek")
        try repository.insert(status)
        try repository.delete(id: status.id)

        XCTAssertNil(try repository.fetch(id: status.id))
    }
}
