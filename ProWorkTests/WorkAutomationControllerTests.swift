//  WorkAutomationControllerTests.swift
//  ProWorkTests

import XCTest
@testable import ProWork

@MainActor
final class WorkAutomationControllerTests: XCTestCase {
    private var dbURL: URL!
    private var controller: WorkAutomationController!
    private var todo: Todo!

    override func setUp() async throws {
        try await super.setUp()
        dbURL = try DatabaseTestHelper.freshDatabase()

        let category = TaskCategory(name: "Genel")
        try TaskCategoryRepository().insert(category)

        todo = Todo(
            categoryId: category.id,
            title: "Menü çubuğu görevi",
            statusId: BuiltInTodoStatusId.inProgress
        )

        let todoRepository = TodoRepository()
        let sessionRepository = TodoTimeSessionRepository()
        try todoRepository.insert(todo)

        controller = WorkAutomationController(
            controlService: WorkSessionControlService(
                todoRepository: todoRepository,
                sessionRepository: sessionRepository
            ),
            idleSecondsProvider: { 0 }
        )
    }

    override func tearDown() async throws {
        controller?.stop()
        controller = nil
        todo = nil
        if let dbURL {
            DatabaseTestHelper.teardown(at: dbURL)
        }
        dbURL = nil
        try await super.tearDown()
    }

    func testSuccessfulActionsAdvanceRevisionAndRefreshSessionState() {
        XCTAssertEqual(controller.workSessionRevision, 0)

        controller.startWork(todoId: todo.id)

        XCTAssertEqual(controller.workSessionRevision, 1)
        XCTAssertEqual(controller.activeSession?.todoId, todo.id)

        controller.stopActiveWork()

        XCTAssertEqual(controller.workSessionRevision, 2)
        XCTAssertNil(controller.activeSession)
    }

    func testFailedActionDoesNotAdvanceRevision() {
        controller.startWork(todoId: "missing-todo")

        XCTAssertEqual(controller.workSessionRevision, 0)
        XCTAssertNil(controller.activeSession)
        XCTAssertNotNil(controller.lastAutomationMessage)
    }

    func testSynchronizeExternalSessionChangeAdvancesRevisionAndRefreshesState() throws {
        try TodoTimeSessionRepository().startSession(
            todoId: todo.id,
            startStatusId: todo.statusId
        )

        controller.synchronizeExternalSessionChange()

        XCTAssertEqual(controller.workSessionRevision, 1)
        XCTAssertEqual(controller.activeSession?.todoId, todo.id)
    }

    func testIdleAutoStop_doesNotPauseAIAgentTask() throws {
        var aiTodo = todo!
        aiTodo.isAIAgentTask = true
        try TodoRepository().update(aiTodo)

        controller = WorkAutomationController(
            controlService: WorkSessionControlService(
                todoRepository: TodoRepository(),
                sessionRepository: TodoTimeSessionRepository()
            ),
            idleSecondsProvider: { 120 }
        )
        var settings = AppSettings.defaults
        settings.idleAutoStopEnabled = true
        settings.idleAutoStopMinutes = 1
        controller.updateSettings(settings)
        controller.startWork(todoId: aiTodo.id)

        controller.fastTick()

        XCTAssertEqual(controller.activeSession?.todoId, aiTodo.id)
        XCTAssertNil(controller.pausedSession)
        XCTAssertEqual(controller.workSessionRevision, 1)
    }
}
