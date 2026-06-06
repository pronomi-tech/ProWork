//  TodoBillingOverrideRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class TodoBillingOverrideRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var overrideRepository: TodoBillingOverrideRepository!
    private var todoRepository: TodoRepository!
    private var categoryRepository: TaskCategoryRepository!
    private var category: TaskCategory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        overrideRepository = TodoBillingOverrideRepository()
        todoRepository = TodoRepository()
        categoryRepository = TaskCategoryRepository()
        category = TaskCategory(name: "qa-Genel")
        try categoryRepository.insert(category)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - upsert + single-row fetch

    func test_upsert_thenFetchByTodoId_returnsUnitPriceOverride() throws {
        let todo = try makeTodo()
        let override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .unitPrice,
            unitPriceMinor: 75_00,
            currency: "USD"
        )
        try overrideRepository.upsert(override)

        let fetched = try overrideRepository.fetch(todoId: todo.id)
        XCTAssertEqual(fetched?.overrideType, .unitPrice)
        XCTAssertEqual(fetched?.unitPriceMinor, 75_00)
        XCTAssertEqual(fetched?.currency, "USD")
        XCTAssertNil(fetched?.fixedFeeMinor)
    }

    func test_upsert_thenFetch_returnsFixedFeeOverride() throws {
        let todo = try makeTodo()
        let override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .fixedFee,
            fixedFeeMinor: 1_500_00,
            currency: "TRY",
            note: "Toplu iş bedeli"
        )
        try overrideRepository.upsert(override)

        let fetched = try overrideRepository.fetch(todoId: todo.id)
        XCTAssertEqual(fetched?.overrideType, .fixedFee)
        XCTAssertEqual(fetched?.fixedFeeMinor, 1_500_00)
        XCTAssertEqual(fetched?.note, "Toplu iş bedeli")
        XCTAssertNil(fetched?.unitPriceMinor)
    }

    // MARK: - todoId UNIQUE

    func test_upsert_replacesExistingOverride_forSameTodo() throws {
        let todo = try makeTodo()
        try overrideRepository.upsert(TodoBillingOverride(
            todoId: todo.id,
            overrideType: .unitPrice,
            unitPriceMinor: 50_00,
            currency: "TRY"
        ))
        try overrideRepository.upsert(TodoBillingOverride(
            todoId: todo.id,
            overrideType: .fixedFee,
            fixedFeeMinor: 200_00,
            currency: "TRY"
        ))

        let fetched = try overrideRepository.fetch(todoId: todo.id)
        XCTAssertEqual(fetched?.overrideType, .fixedFee)
        XCTAssertEqual(fetched?.fixedFeeMinor, 200_00)
        XCTAssertNil(fetched?.unitPriceMinor)
    }

    // MARK: - Bulk fetch by todoIds

    func test_fetchByTodoIds_returnsMap_keyedByTodoId() throws {
        let a = try makeTodo(title: "A")
        let b = try makeTodo(title: "B")
        let c = try makeTodo(title: "C")

        try overrideRepository.upsert(TodoBillingOverride(
            todoId: a.id, overrideType: .unitPrice, unitPriceMinor: 10_00, currency: "TRY"
        ))
        try overrideRepository.upsert(TodoBillingOverride(
            todoId: c.id, overrideType: .fixedFee, fixedFeeMinor: 50_00, currency: "TRY"
        ))

        let map = try overrideRepository.fetch(todoIds: [a.id, b.id, c.id])
        XCTAssertEqual(Set(map.keys), [a.id, c.id])
        XCTAssertEqual(map[a.id]?.overrideType, .unitPrice)
        XCTAssertEqual(map[c.id]?.overrideType, .fixedFee)
    }

    func test_fetchByTodoIds_emptyInput_returnsEmptyMap() throws {
        let map = try overrideRepository.fetch(todoIds: [])
        XCTAssertTrue(map.isEmpty)
    }

    // MARK: - remove

    func test_remove_softDeletesOverride() throws {
        let todo = try makeTodo()
        try overrideRepository.upsert(TodoBillingOverride(
            todoId: todo.id, overrideType: .unitPrice, unitPriceMinor: 99_00, currency: "TRY"
        ))

        try overrideRepository.remove(todoId: todo.id)

        XCTAssertNil(try overrideRepository.fetch(todoId: todo.id))
    }

    func test_upsert_afterRemove_restoresRow() throws {
        let todo = try makeTodo()
        try overrideRepository.upsert(TodoBillingOverride(
            todoId: todo.id, overrideType: .unitPrice, unitPriceMinor: 10_00, currency: "TRY"
        ))
        try overrideRepository.remove(todoId: todo.id)

        try overrideRepository.upsert(TodoBillingOverride(
            todoId: todo.id, overrideType: .unitPrice, unitPriceMinor: 20_00, currency: "TRY"
        ))

        let fetched = try overrideRepository.fetch(todoId: todo.id)
        XCTAssertEqual(fetched?.unitPriceMinor, 20_00, "Upsert deletedAt=NULL set ederek satırı yeniden aktif etmeli")
    }

    // MARK: - Helper

    private func makeTodo(title: String = "qa-Test") throws -> Todo {
        let todo = Todo(
            categoryId: category.id,
            title: title,
            statusId: BuiltInTodoStatusId.waiting
        )
        try todoRepository.insert(todo)
        return todo
    }
}
