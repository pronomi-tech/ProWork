//
//  TodoRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//
//  TodoRepository'nin gerçek SQLite üzerinde CRUD + bulk lookup davranışını
//  doğrular. Sprint 5 review'unun "repository / integration testleri sıfır"
//  saptamasının ilk çözümü; başlangıç noktası olarak en çok kullanılan
//  repository seçildi. Diğer repository'ler benzer pattern'le ayrı dosyalarda
//  eklenecek.
//

import XCTest
@testable import ProWork

final class TodoRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: TodoRepository!
    private var categoryRepository: TaskCategoryRepository!
    private var category: TaskCategory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = TodoRepository()
        categoryRepository = TaskCategoryRepository()
        category = TaskCategory(name: "Genel", color: "#3B82F6")
        try categoryRepository.insert(category)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Insert / fetch single

    func test_insert_thenFetchById_returnsTodo() throws {
        let todo = makeTodo(title: "İlk iş")
        try repository.insert(todo)

        let fetched = try repository.fetch(id: todo.id)
        XCTAssertEqual(fetched?.id, todo.id)
        XCTAssertEqual(fetched?.title, "İlk iş")
        XCTAssertEqual(fetched?.categoryId, category.id)
    }

    func test_fetchById_returnsNil_forUnknownId() throws {
        let fetched = try repository.fetch(id: UUID().uuidString)
        XCTAssertNil(fetched)
    }

    // MARK: - fetchAll + fetchListItem (joins)

    func test_fetchAll_returnsInsertedTodos_withJoinedCategoryName() throws {
        try repository.insert(makeTodo(title: "A"))
        try repository.insert(makeTodo(title: "B"))

        let items = try repository.fetchAll()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.categoryName)), ["Genel"])
        XCTAssertEqual(items.first?.statusName, "Beklemede")
    }

    func test_fetchListItem_returnsSingleRow_byId() throws {
        let todo = makeTodo(title: "Tekil")
        try repository.insert(todo)

        let item = try repository.fetchListItem(id: todo.id)
        XCTAssertEqual(item?.id, todo.id)
        XCTAssertEqual(item?.title, "Tekil")
        XCTAssertEqual(item?.categoryName, "Genel")
    }

    func test_fetchListItem_returnsNil_forUnknownId() throws {
        let item = try repository.fetchListItem(id: "no-such-id")
        XCTAssertNil(item)
    }

    // MARK: - Bulk fetch (added in Sprint 2 for batch reporting)

    func test_fetchByIds_returnsOnlyMatching_andSkipsMissing() throws {
        let a = makeTodo(title: "A")
        let b = makeTodo(title: "B")
        let c = makeTodo(title: "C")
        try repository.insert(a)
        try repository.insert(b)
        try repository.insert(c)

        let result = try repository.fetch(ids: [a.id, "missing", c.id])
        XCTAssertEqual(Set(result.map(\.id)), [a.id, c.id])
    }

    func test_fetchByIds_emptyInput_returnsEmpty() throws {
        let result = try repository.fetch(ids: [])
        XCTAssertEqual(result.count, 0)
    }

    func test_fetchByIds_skipsSoftDeletedTodos() throws {
        let a = makeTodo(title: "A")
        let b = makeTodo(title: "B")
        try repository.insert(a)
        try repository.insert(b)
        try repository.softDelete(id: a.id)

        let result = try repository.fetch(ids: [a.id, b.id])
        XCTAssertEqual(result.map(\.id), [b.id])
    }

    // MARK: - Update + status change

    func test_update_persistsTitleChange() throws {
        var todo = makeTodo(title: "Eski başlık")
        try repository.insert(todo)
        todo.title = "Yeni başlık"
        try repository.update(todo)

        let fetched = try repository.fetch(id: todo.id)
        XCTAssertEqual(fetched?.title, "Yeni başlık")
    }

    func test_updateStatus_stampsCompletedAt_whenTransitioningToDone() throws {
        let todo = makeTodo(title: "Tamamlanacak")
        try repository.insert(todo)
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try repository.updateStatus(
            id: todo.id,
            statusId: BuiltInTodoStatusId.done,
            completedAt: completedAt
        )

        let item = try repository.fetchListItem(id: todo.id)
        XCTAssertEqual(item?.statusId, BuiltInTodoStatusId.done)
        XCTAssertEqual(item?.completedAt, completedAt)
    }

    // MARK: - Soft delete

    func test_softDelete_hidesTodoFromFetchAll() throws {
        let kept = makeTodo(title: "Kalsın")
        let deleted = makeTodo(title: "Silinsin")
        try repository.insert(kept)
        try repository.insert(deleted)

        try repository.softDelete(id: deleted.id)

        let remaining = try repository.fetchAll().map(\.id)
        XCTAssertEqual(remaining, [kept.id])
    }

    func test_softDelete_alsoHidesFromFetchById() throws {
        let todo = makeTodo(title: "Silinecek")
        try repository.insert(todo)
        try repository.softDelete(id: todo.id)

        XCTAssertNil(try repository.fetch(id: todo.id))
        XCTAssertNil(try repository.fetchListItem(id: todo.id))
    }

    // MARK: - Helper

    private func makeTodo(title: String) -> Todo {
        Todo(
            categoryId: category.id,
            title: title,
            statusId: BuiltInTodoStatusId.waiting,
            priority: "normal",
            isBillable: true
        )
    }
}
