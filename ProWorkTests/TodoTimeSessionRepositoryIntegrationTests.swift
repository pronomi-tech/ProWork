//
//  TodoTimeSessionRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//
//  Work tracking çekirdeği. start/pause/resume/stop akışı, manuel session,
//  bulk fetch ve soft delete davranışını gerçek SQLite üzerinde doğrular.
//

import XCTest
@testable import ProWork

final class TodoTimeSessionRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var sessionRepository: TodoTimeSessionRepository!
    private var todoRepository: TodoRepository!
    private var categoryRepository: TaskCategoryRepository!
    private var category: TaskCategory!
    private var todo: Todo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        sessionRepository = TodoTimeSessionRepository()
        todoRepository = TodoRepository()
        categoryRepository = TaskCategoryRepository()
        category = TaskCategory(name: "Genel")
        try categoryRepository.insert(category)
        todo = Todo(
            categoryId: category.id,
            title: "Test todo",
            statusId: BuiltInTodoStatusId.waiting
        )
        try todoRepository.insert(todo)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Start / open session

    func test_startSession_createsOpenSession() throws {
        try sessionRepository.startSession(
            todoId: todo.id,
            startStatusId: BuiltInTodoStatusId.inProgress
        )

        let open = try sessionRepository.fetchOpenSession(todoId: todo.id)
        XCTAssertNotNil(open)
        XCTAssertNil(open?.endedAt)
        XCTAssertNil(open?.pausedAt)
        XCTAssertNotNil(open?.runningSinceAt)
        XCTAssertEqual(open?.isManual, false)
    }

    func test_startSession_isIdempotent_whileAnotherSessionIsOpen() throws {
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)

        // Bir todo için en fazla bir açık session olmalı; ikinci start hiçbir
        // şey yapmamalı (no-op).
        let sessions = try sessionRepository.fetchSessions(todoId: todo.id)
        let openCount = sessions.filter { $0.endedAt == nil }.count
        XCTAssertEqual(openCount, 1)
    }

    // MARK: - Pause / resume

    func test_pauseSession_setsPausedAt_andClearsRunningSinceAt() throws {
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        guard let sessionId = try sessionRepository.fetchOpenSession(todoId: todo.id)?.id else {
            return XCTFail("Open session missing")
        }

        try sessionRepository.pauseSession(sessionId: sessionId)

        let sessions = try sessionRepository.fetchSessions(todoId: todo.id)
        let paused = sessions.first(where: { $0.id == sessionId })
        XCTAssertNotNil(paused?.pausedAt)
        XCTAssertNil(paused?.runningSinceAt)
        XCTAssertNil(paused?.endedAt)
    }

    func test_resumeSession_clearsPausedAt_andSetsRunningSinceAt() throws {
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        guard let sessionId = try sessionRepository.fetchOpenSession(todoId: todo.id)?.id else {
            return XCTFail("Open session missing")
        }
        try sessionRepository.pauseSession(sessionId: sessionId)
        try sessionRepository.resumeSession(sessionId: sessionId)

        let sessions = try sessionRepository.fetchSessions(todoId: todo.id)
        let resumed = sessions.first(where: { $0.id == sessionId })
        XCTAssertNil(resumed?.pausedAt)
        XCTAssertNotNil(resumed?.runningSinceAt)
    }

    func test_fetchPausedSession_returnsOnlyPausedRow() throws {
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        guard let sessionId = try sessionRepository.fetchOpenSession(todoId: todo.id)?.id else {
            return XCTFail("Open session missing")
        }
        XCTAssertNil(try sessionRepository.fetchPausedSession())

        try sessionRepository.pauseSession(sessionId: sessionId)
        let paused = try sessionRepository.fetchPausedSession()
        XCTAssertEqual(paused?.session.id, sessionId)
    }

    // MARK: - Stop

    func test_stopOpenSession_setsEndedAtAndStatus() throws {
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        try sessionRepository.stopOpenSession(
            todoId: todo.id,
            endStatusId: BuiltInTodoStatusId.done
        )

        let sessions = try sessionRepository.fetchSessions(todoId: todo.id)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions.first?.endedAt)
        XCTAssertEqual(sessions.first?.endStatusId, BuiltInTodoStatusId.done)
        XCTAssertNil(try sessionRepository.fetchOpenSession(todoId: todo.id))
    }

    func test_stopSession_byId_closesTheRow() throws {
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        guard let sessionId = try sessionRepository.fetchOpenSession(todoId: todo.id)?.id else {
            return XCTFail("Open session missing")
        }

        try sessionRepository.stopSession(sessionId: sessionId, endStatusId: BuiltInTodoStatusId.done)

        XCTAssertNil(try sessionRepository.fetchOpenSession(todoId: todo.id))
    }

    // MARK: - Manual session

    func test_insertManualSession_persistsDurationAndManualFlag() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(3600)
        try sessionRepository.insertManualSession(
            todoId: todo.id,
            startedAt: started,
            endedAt: ended,
            note: "Tamamlandı"
        )

        let sessions = try sessionRepository.fetchSessions(todoId: todo.id)
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.durationSeconds, 3600)
        XCTAssertEqual(session.isManual, true)
        XCTAssertEqual(session.note, "Tamamlandı")
    }

    func test_insertManualSession_rejectsInvalidRange() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = started.addingTimeInterval(-1)
        XCTAssertThrowsError(
            try sessionRepository.insertManualSession(
                todoId: todo.id,
                startedAt: started,
                endedAt: ended,
                note: nil
            )
        )
    }

    // MARK: - Bulk fetch

    func test_fetchByIds_returnsOnlyMatching_andSkipsSoftDeleted() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        try sessionRepository.insertManualSession(
            todoId: todo.id,
            startedAt: started,
            endedAt: started.addingTimeInterval(60),
            note: "A"
        )
        try sessionRepository.insertManualSession(
            todoId: todo.id,
            startedAt: started.addingTimeInterval(120),
            endedAt: started.addingTimeInterval(180),
            note: "B"
        )
        let ids = try sessionRepository.fetchSessions(todoId: todo.id).map(\.id)
        XCTAssertEqual(ids.count, 2)

        try sessionRepository.softDelete(id: ids[0])

        let bulk = try sessionRepository.fetch(ids: ids)
        XCTAssertEqual(bulk.map(\.id), [ids[1]])
    }

    // MARK: - Soft delete vs hard delete

    func test_softDelete_hidesFromFetchSessions() throws {
        try sessionRepository.insertManualSession(
            todoId: todo.id,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 60),
            note: nil
        )
        let sessionId = try XCTUnwrap(try sessionRepository.fetchSessions(todoId: todo.id).first?.id)

        try sessionRepository.softDelete(id: sessionId)

        XCTAssertEqual(try sessionRepository.fetchSessions(todoId: todo.id).count, 0)
    }
}
