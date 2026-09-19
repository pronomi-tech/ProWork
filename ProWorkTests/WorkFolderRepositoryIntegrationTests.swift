//  WorkFolderRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class WorkFolderRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: WorkFolderRepository!
    private var todoRepository: TodoRepository!
    private var projectRepository: ProjectRepository!
    private var customerRepository: CustomerRepository!
    private var categoryRepository: TaskCategoryRepository!
    private var customer: Customer!
    private var project: Project!
    private var category: TaskCategory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = WorkFolderRepository()
        todoRepository = TodoRepository()
        projectRepository = ProjectRepository()
        customerRepository = CustomerRepository()
        categoryRepository = TaskCategoryRepository()

        customer = Customer(name: "Müşteri")
        try customerRepository.insert(customer)
        project = Project(customerId: customer.id, name: "Proje A")
        try projectRepository.insert(project)
        category = TaskCategory(name: "Genel")
        try categoryRepository.insert(category)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    func test_globalAndProjectTrees_allowIndependentNestedFolders() throws {
        let globalRoot = WorkFolder(name: "Teklif")
        let globalChild = WorkFolder(parentFolderId: globalRoot.id, name: "Gönderilenler")
        let projectRoot = WorkFolder(projectId: project.id, name: "Geliştirme")
        let projectChild = WorkFolder(
            projectId: project.id,
            parentFolderId: projectRoot.id,
            name: "Backend"
        )

        try repository.insert(globalRoot)
        try repository.insert(globalChild)
        try repository.insert(projectRoot)
        try repository.insert(projectChild)

        let folders = try repository.fetchAll()
        XCTAssertEqual(Set(folders.map(\.id)), [globalRoot.id, globalChild.id, projectRoot.id, projectChild.id])
        XCTAssertNil(try repository.fetch(id: globalChild.id)?.projectId)
        XCTAssertEqual(try repository.fetch(id: projectChild.id)?.projectId, project.id)
    }

    func test_hierarchy_hasNoBusinessDepthLimit() throws {
        var parentId: String?

        for depth in 0..<100 {
            let folder = WorkFolder(parentFolderId: parentId, name: "Seviye \(depth)")
            try repository.insert(folder)
            parentId = folder.id
        }

        let flattened = WorkFolderHierarchy.flattened(try repository.fetchAll(), projectId: nil)
        XCTAssertEqual(flattened.count, 100)
        XCTAssertEqual(flattened.last?.depth, 99)
    }

    func test_updateRejectsCycle() throws {
        var root = WorkFolder(name: "Kök")
        let child = WorkFolder(parentFolderId: root.id, name: "Alt")
        try repository.insert(root)
        try repository.insert(child)

        root.parentFolderId = child.id

        XCTAssertThrowsError(try repository.update(root))
    }

    func test_parentMustUseSameProjectScope() throws {
        let globalRoot = WorkFolder(name: "Genel")
        try repository.insert(globalRoot)
        let invalid = WorkFolder(
            projectId: project.id,
            parentFolderId: globalRoot.id,
            name: "Geçersiz"
        )

        XCTAssertThrowsError(try repository.insert(invalid))
    }

    func test_todoFolderMustUseSameProjectScope() throws {
        let projectFolder = WorkFolder(projectId: project.id, name: "Proje Klasörü")
        try repository.insert(projectFolder)

        let invalidTodo = Todo(
            folderId: projectFolder.id,
            categoryId: category.id,
            title: "Projesiz çalışma"
        )

        XCTAssertThrowsError(try todoRepository.insert(invalidTodo))
    }

    func test_todoFolderRoundTripsThroughDomainAndListItem() throws {
        let folder = WorkFolder(name: "Muhasebe")
        try repository.insert(folder)
        let todo = Todo(folderId: folder.id, categoryId: category.id, title: "Fatura hazırla")
        try todoRepository.insert(todo)

        XCTAssertEqual(try todoRepository.fetch(id: todo.id)?.folderId, folder.id)
        XCTAssertEqual(try todoRepository.fetchListItem(id: todo.id)?.folderName, folder.name)
    }

    @MainActor
    func test_projectFolderSelection_resolvesCustomerProjectAndFolder() throws {
        let folder = WorkFolder(projectId: project.id, name: "Teslimatlar")
        try repository.insert(folder)

        let assignment = WorkLocationSelection.folder(folder.id).assignment(
            projects: try projectRepository.fetchAll(),
            folders: try repository.fetchAll()
        )

        XCTAssertEqual(
            assignment,
            WorkLocationAssignment(
                customerId: customer.id,
                projectId: project.id,
                folderId: folder.id
            )
        )
    }

    @MainActor
    func test_independentFolderSelection_keepsCustomerAndProjectEmpty() throws {
        let folder = WorkFolder(name: "İdari")
        try repository.insert(folder)

        let assignment = WorkLocationSelection.folder(folder.id).assignment(
            projects: try projectRepository.fetchAll(),
            folders: try repository.fetchAll()
        )

        XCTAssertEqual(
            assignment,
            WorkLocationAssignment(folderId: folder.id)
        )
    }

    @MainActor
    func test_todos_projectAndFolderSelectionsRespectDescendantOption() throws {
        let projectFolder = WorkFolder(projectId: project.id, name: "260902")
        try repository.insert(projectFolder)
        let directProjectTodo = Todo(
            customerId: customer.id,
            projectId: project.id,
            categoryId: category.id,
            title: "Doğrudan proje kaydı"
        )
        let folderTodo = Todo(
            customerId: customer.id,
            projectId: project.id,
            folderId: projectFolder.id,
            categoryId: category.id,
            title: "Klasör kaydı"
        )
        try todoRepository.insert(directProjectTodo)
        try todoRepository.insert(folderTodo)

        let viewModel = TodosViewModel(services: AppServices(database: .shared))
        viewModel.load()

        XCTAssertEqual(
            viewModel.visibleTodos(
                for: .project(project.id),
                includeDescendantFolders: false
            ).map(\.id),
            [directProjectTodo.id]
        )
        XCTAssertEqual(
            Set(viewModel.visibleTodos(
                for: .project(project.id),
                includeDescendantFolders: true
            ).map(\.id)),
            [directProjectTodo.id, folderTodo.id]
        )
        XCTAssertEqual(
            viewModel.visibleTodos(
                for: .folder(projectFolder.id),
                includeDescendantFolders: false
            ).map(\.id),
            [folderTodo.id]
        )
    }

    func test_softDeleteRejectsFolderWithChildOrTodo() throws {
        let root = WorkFolder(name: "Kök")
        let child = WorkFolder(parentFolderId: root.id, name: "Alt")
        try repository.insert(root)
        try repository.insert(child)

        XCTAssertThrowsError(
            try repository.softDelete(id: root.id, by: BuiltInUserId.defaultOwner)
        ) { error in
            XCTAssertEqual(error as? WorkFolderRepositoryError, .folderNotEmpty)
        }

        try repository.softDelete(id: child.id, by: BuiltInUserId.defaultOwner)
        let todo = Todo(folderId: root.id, categoryId: category.id, title: "Çalışma")
        try todoRepository.insert(todo)

        XCTAssertThrowsError(
            try repository.softDelete(id: root.id, by: BuiltInUserId.defaultOwner)
        ) { error in
            XCTAssertEqual(error as? WorkFolderRepositoryError, .folderNotEmpty)
        }
    }

    func test_projectSoftDeleteHidesItsFolders() throws {
        let folder = WorkFolder(projectId: project.id, name: "Proje Klasörü")
        try repository.insert(folder)

        try projectRepository.softDelete(id: project.id, by: BuiltInUserId.defaultOwner)

        XCTAssertNil(try repository.fetch(id: folder.id))
    }

    func test_archiveAndRestore_applyToEntireSubtree() throws {
        let root = WorkFolder(name: "Tamamlanan Proje")
        let child = WorkFolder(parentFolderId: root.id, name: "Teslim")
        try repository.insert(root)
        try repository.insert(child)

        try repository.archive(id: root.id, by: BuiltInUserId.defaultOwner)

        XCTAssertTrue(try repository.fetchAll().isEmpty)
        let archived = try repository.fetchAll(includeArchived: true)
        XCTAssertEqual(Set(archived.map(\.id)), [root.id, child.id])
        XCTAssertTrue(archived.allSatisfy(\.isArchived))

        try repository.restore(id: root.id, by: BuiltInUserId.defaultOwner)

        let restored = try repository.fetchAll()
        XCTAssertEqual(Set(restored.map(\.id)), [root.id, child.id])
        XCTAssertTrue(restored.allSatisfy { !$0.isArchived })
    }

    func test_restoringArchivedChildAlsoRestoresItsAncestorPath() throws {
        let root = WorkFolder(name: "Kök")
        let child = WorkFolder(parentFolderId: root.id, name: "Alt")
        try repository.insert(root)
        try repository.insert(child)
        try repository.archive(id: root.id, by: BuiltInUserId.defaultOwner)

        try repository.restore(id: child.id, by: BuiltInUserId.defaultOwner)

        let restoredIds = Set(try repository.fetchAll().map(\.id))
        XCTAssertEqual(restoredIds, [root.id, child.id])
    }

    func test_archiveRejectsUnbilledSessionInDescendantFolder() throws {
        let root = WorkFolder(name: "Kök")
        let child = WorkFolder(parentFolderId: root.id, name: "Alt")
        try repository.insert(root)
        try repository.insert(child)

        let todo = Todo(
            folderId: child.id,
            categoryId: category.id,
            title: "Faturalandırılacak çalışma"
        )
        try todoRepository.insert(todo)
        let startedAt = BillingFixtures.date(2026, 9, 19, 10)
        try TodoTimeSessionRepository().insertManualSession(
            todoId: todo.id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            note: nil
        )

        XCTAssertThrowsError(
            try repository.archive(id: root.id, by: BuiltInUserId.defaultOwner)
        ) { error in
            XCTAssertEqual(error as? WorkFolderRepositoryError, .folderHasUnbilledWork)
        }
        XCTAssertNotNil(try repository.fetch(id: root.id))
        XCTAssertNotNil(try repository.fetch(id: child.id))
    }

    func test_archiveRejectsUnbilledProjectedFee() throws {
        let folder = WorkFolder(name: "Sözleşmeli İş")
        try repository.insert(folder)
        let todo = Todo(
            customerId: customer.id,
            folderId: folder.id,
            categoryId: category.id,
            title: "Projelendirilmiş çalışma"
        )
        try todoRepository.insert(todo)
        try TodoBillingOverrideRepository().upsert(
            TodoBillingOverride(
                todoId: todo.id,
                overrideType: .projectedFee,
                unitPriceMinor: 1_000_00,
                projectedBillableSeconds: 3_600
            )
        )

        XCTAssertThrowsError(
            try repository.archive(id: folder.id, by: BuiltInUserId.defaultOwner)
        ) { error in
            XCTAssertEqual(error as? WorkFolderRepositoryError, .folderHasUnbilledWork)
        }
    }

    func test_archiveAllowsNonBillableWork() throws {
        let folder = WorkFolder(name: "İdari")
        try repository.insert(folder)
        let todo = Todo(
            folderId: folder.id,
            categoryId: category.id,
            title: "İdari çalışma",
            isBillable: false
        )
        try todoRepository.insert(todo)
        let startedAt = BillingFixtures.date(2026, 9, 19, 10)
        try TodoTimeSessionRepository().insertManualSession(
            todoId: todo.id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            note: nil
        )

        try repository.archive(id: folder.id, by: BuiltInUserId.defaultOwner)

        XCTAssertNil(try repository.fetch(id: folder.id))
        XCTAssertTrue(try XCTUnwrap(repository.fetch(id: folder.id, includeArchived: true)).isArchived)
    }

    func test_archiveAllowsSessionAssignedToNonCancelledBillingRun() throws {
        let folder = WorkFolder(projectId: project.id, name: "Faturalanan İş")
        try repository.insert(folder)
        let todo = Todo(
            customerId: customer.id,
            projectId: project.id,
            folderId: folder.id,
            categoryId: category.id,
            title: "Faturalanmış çalışma"
        )
        try todoRepository.insert(todo)
        let startedAt = BillingFixtures.date(2026, 9, 19, 10)
        let sessionRepository = TodoTimeSessionRepository()
        try sessionRepository.insertManualSession(
            todoId: todo.id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            note: nil
        )
        let session = try XCTUnwrap(
            sessionRepository.fetchAllListItems().first(where: { $0.todoId == todo.id })
        )
        let run = BillingReportRun(
            customerId: customer.id,
            periodStart: "2026-09-01",
            periodEnd: "2026-09-30"
        )
        try BillingReportRunRepository().insert(run)
        try BillingReportLineRepository().insert(
            BillingReportLine(
                runId: run.id,
                sessionId: session.id,
                sourceKind: .timeSession,
                sourceId: session.id,
                todoId: todo.id,
                todoTitle: todo.title,
                projectId: project.id,
                projectName: project.name,
                customerId: customer.id,
                customerName: customer.name,
                categoryId: category.id,
                categoryName: category.name,
                serviceType: .remote,
                timeType: .regular,
                actualSeconds: 3_600,
                billableSeconds: 3_600,
                unitPriceMinor: 100_00,
                amountMinor: 100_00
            )
        )

        try repository.archive(id: folder.id, by: BuiltInUserId.defaultOwner)

        XCTAssertTrue(try XCTUnwrap(repository.fetch(id: folder.id, includeArchived: true)).isArchived)
    }

    func test_archivedFolderRejectsNewTodoAssignment() throws {
        let folder = WorkFolder(name: "Arşiv")
        try repository.insert(folder)
        try repository.archive(id: folder.id, by: BuiltInUserId.defaultOwner)

        XCTAssertThrowsError(
            try todoRepository.insert(
                Todo(folderId: folder.id, categoryId: category.id, title: "Yeni çalışma")
            )
        )
    }

    @MainActor
    func test_archivedFolderContentsAreHiddenUntilArchiveToggleIsEnabled() throws {
        let folder = WorkFolder(name: "Geçmiş")
        try repository.insert(folder)
        let todo = Todo(
            folderId: folder.id,
            categoryId: category.id,
            title: "Geçmiş çalışma",
            isBillable: false
        )
        try todoRepository.insert(todo)
        let startedAt = BillingFixtures.date(2026, 9, 19, 10)
        try TodoTimeSessionRepository().insertManualSession(
            todoId: todo.id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            note: nil
        )
        try repository.archive(id: folder.id, by: BuiltInUserId.defaultOwner)

        let todosViewModel = TodosViewModel(services: AppServices(database: .shared))
        todosViewModel.load()
        XCTAssertFalse(
            todosViewModel.visibleTodos(
                for: .all,
                includeDescendantFolders: false
            ).contains(where: { $0.id == todo.id })
        )
        XCTAssertTrue(
            todosViewModel.visibleTodos(
                for: .all,
                includeDescendantFolders: false,
                showArchivedFolders: true
            ).contains(where: { $0.id == todo.id })
        )

        let sessionsViewModel = WorkSessionsViewModel(services: AppServices(database: .shared))
        sessionsViewModel.loadData()
        XCTAssertFalse(
            sessionsViewModel.visibleSessions(
                for: .all,
                includeDescendantFolders: false
            ).contains(where: { $0.todoId == todo.id })
        )
        XCTAssertTrue(
            sessionsViewModel.visibleSessions(
                for: .all,
                includeDescendantFolders: false,
                showArchivedFolders: true
            ).contains(where: { $0.todoId == todo.id })
        )
    }

    @MainActor
    func test_workSessions_followFolderSelectionAndDescendantOption() throws {
        let parent = WorkFolder(name: "Teklif")
        let child = WorkFolder(parentFolderId: parent.id, name: "Gönderilenler")
        try repository.insert(parent)
        try repository.insert(child)

        let parentTodo = Todo(folderId: parent.id, categoryId: category.id, title: "Ana kayıt")
        let childTodo = Todo(folderId: child.id, categoryId: category.id, title: "Alt kayıt")
        try todoRepository.insert(parentTodo)
        try todoRepository.insert(childTodo)

        let start = BillingFixtures.date(2026, 9, 12, 10)
        try TodoTimeSessionRepository().insertManualSession(
            todoId: parentTodo.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            note: nil
        )
        try TodoTimeSessionRepository().insertManualSession(
            todoId: childTodo.id,
            startedAt: start.addingTimeInterval(7_200),
            endedAt: start.addingTimeInterval(10_800),
            note: nil
        )

        let projectFolder = WorkFolder(projectId: project.id, name: "260902")
        try repository.insert(projectFolder)
        let directProjectTodo = Todo(
            customerId: customer.id,
            projectId: project.id,
            categoryId: category.id,
            title: "Doğrudan proje çalışması"
        )
        let projectFolderTodo = Todo(
            customerId: customer.id,
            projectId: project.id,
            folderId: projectFolder.id,
            categoryId: category.id,
            title: "Proje klasörü çalışması"
        )
        try todoRepository.insert(directProjectTodo)
        try todoRepository.insert(projectFolderTodo)
        try TodoTimeSessionRepository().insertManualSession(
            todoId: directProjectTodo.id,
            startedAt: start.addingTimeInterval(14_400),
            endedAt: start.addingTimeInterval(18_000),
            note: nil
        )
        try TodoTimeSessionRepository().insertManualSession(
            todoId: projectFolderTodo.id,
            startedAt: start.addingTimeInterval(21_600),
            endedAt: start.addingTimeInterval(25_200),
            note: nil
        )

        let viewModel = WorkSessionsViewModel(services: AppServices(database: .shared))
        viewModel.loadData()

        XCTAssertEqual(
            viewModel.visibleSessions(
                for: .folder(parent.id),
                includeDescendantFolders: false
            ).map(\.todoId),
            [parentTodo.id]
        )
        XCTAssertEqual(
            Set(viewModel.visibleSessions(
                for: .folder(parent.id),
                includeDescendantFolders: true
            ).map(\.todoId)),
            [parentTodo.id, childTodo.id]
        )
        XCTAssertEqual(viewModel.folderPath(forTodoId: childTodo.id), "Teklif / Gönderilenler")
        XCTAssertEqual(
            viewModel.visibleSessions(
                for: .project(project.id),
                includeDescendantFolders: false
            ).map(\.todoId),
            [directProjectTodo.id]
        )
        XCTAssertEqual(
            Set(viewModel.visibleSessions(
                for: .project(project.id),
                includeDescendantFolders: true
            ).map(\.todoId)),
            [directProjectTodo.id, projectFolderTodo.id]
        )
    }
}
