//  TodoTimeSessionRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.
//  Work tracking çekirdeği. start/pause/resume/stop akışı, manuel session,
//  bulk fetch ve soft delete davranışını gerçek SQLite üzerinde doğrular.

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

        try sessionRepository.softDelete(id: ids[0], by: BuiltInUserId.defaultOwner)

        let bulk = try sessionRepository.fetch(ids: ids)
        XCTAssertEqual(bulk.map(\.id), [ids[1]])
    }

    // MARK: - K5: tek aktif çalışma oturumu kuralı DB seviyesinde

    /// Migration003 partial unique index `idx_todo_time_sessions_one_open`
    /// aynı organizasyonda iki açık satırın varlığını reddeder.
    /// Service'in atomic transaction'ı bunu zaten önler — bu test ham SQL
    /// INSERT ile bypass deneyip DB hatasını yakalar.
    func test_K5_partialUniqueIndex_rejectsSecondOpenSession() throws {
        try sessionRepository.startSession(
            todoId: todo.id,
            startStatusId: BuiltInTodoStatusId.inProgress
        )

        let otherTodo = Todo(
            categoryId: category.id,
            title: "Diğer iş",
            statusId: BuiltInTodoStatusId.waiting
        )
        try todoRepository.insert(otherTodo)

        let now = AppDateFormatters.sqliteTimestamp.string(from: Date())
        let rawInsertSQL = """
        INSERT INTO todo_time_sessions (
            id, todoId, startedAt, runningSinceAt, pausedAt, endedAt, durationSeconds,
            startStatusId, endStatusId, note, isManual,
            organizationId, createdByUserId, updatedByUserId, createdAt, updatedAt,
            deletedAt, rowVersion, syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, NULL, NULL, 0, ?, NULL, NULL, 0,
                ?, ?, ?, ?, ?,
                NULL, 0, 'local', NULL, NULL);
        """

        XCTAssertThrowsError(
            try AppDatabase.shared.execute(rawInsertSQL) { stmt in
                stmt.bindText(UUID().uuidString, at: 1)
                stmt.bindText(otherTodo.id, at: 2)
                stmt.bindText(now, at: 3)
                stmt.bindText(now, at: 4)
                stmt.bindText(BuiltInTodoStatusId.inProgress, at: 5)
                stmt.bindText(BuiltInOrganizationId.default, at: 6)
                stmt.bindText(BuiltInUserId.defaultOwner, at: 7)
                stmt.bindText(BuiltInUserId.defaultOwner, at: 8)
                stmt.bindText(now, at: 9)
                stmt.bindText(now, at: 10)
            }
        ) { error in
            let message = (error as? DatabaseError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(
                message.lowercased().contains("unique") || message.lowercased().contains("constraint"),
                "Expected UNIQUE constraint violation, got: \(message)"
            )
        }

        // Açık satır hâlâ yalnızca biri — index ikinci satırı tamamen
        // engelledi.
        let openCount = try AppDatabase.shared.query("""
        SELECT COUNT(*) FROM todo_time_sessions
        WHERE endedAt IS NULL AND deletedAt IS NULL;
        """) { $0.int(at: 0) }.first ?? 0
        XCTAssertEqual(openCount, 1)
    }

    /// Bir önceki oturum doğru şekilde kapatıldıktan sonra index bloklamamalı.
    func test_K5_uniqueIndex_allowsNewOpen_afterPreviousClosed() throws {
        try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        try sessionRepository.stopOpenSession(todoId: todo.id, endStatusId: BuiltInTodoStatusId.done)

        // Yeni oturum sorunsuz açılmalı.
        XCTAssertNoThrow(
            try sessionRepository.startSession(todoId: todo.id, startStatusId: BuiltInTodoStatusId.inProgress)
        )

        let open = try sessionRepository.fetchOpenSession(todoId: todo.id)
        XCTAssertNotNil(open)
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

        try sessionRepository.softDelete(id: sessionId, by: BuiltInUserId.defaultOwner)

        XCTAssertEqual(try sessionRepository.fetchSessions(todoId: todo.id).count, 0)
    }
}
