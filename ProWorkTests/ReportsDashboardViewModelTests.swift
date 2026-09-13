import XCTest
@testable import ProWork

@MainActor
final class ReportsDashboardViewModelTests: XCTestCase {
    private var databaseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        databaseURL = try DatabaseTestHelper.freshDatabase()
    }

    override func tearDown() async throws {
        if let databaseURL {
            DatabaseTestHelper.teardown(at: databaseURL)
        }
        databaseURL = nil
        try await super.tearDown()
    }

    func test_completedCustomerWork_remainsBillableInDashboard() throws {
        let customer = Customer(id: "customer-1", name: "Müşteri")
        try CustomerRepository().insert(customer)

        let todo = Todo(
            id: "todo-1",
            customerId: customer.id,
            categoryId: "development",
            title: "Tamamlanan ücretli iş",
            statusId: BuiltInTodoStatusId.done,
            isBillable: true,
            completedAt: Date()
        )
        try TodoRepository().insert(todo)

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try TodoTimeSessionRepository().insertManualSession(
            todoId: todo.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            note: nil
        )

        let viewModel = ReportsDashboardViewModel(services: AppServices(database: .shared))
        viewModel.loadData()
        viewModel.recompute(
            range: .all,
            customStart: start,
            customEnd: start,
            customerId: "",
            projectId: "",
            labels: .init(
                noCustomerTitle: "Müşterisiz",
                noProjectFormat: "%@ (Proje yok)",
                administrativeTitle: "İdari",
                billableTitle: "Faturalandırılabilir"
            )
        )

        XCTAssertEqual(viewModel.customerBreakdownData.count, 1)
        XCTAssertEqual(viewModel.customerBreakdownData.first?.name, customer.name)
        XCTAssertEqual(viewModel.billableBreakdownData.count, 1)
        XCTAssertEqual(viewModel.billableBreakdownData.first?.name, "Faturalandırılabilir")
        XCTAssertEqual(viewModel.billableBreakdownData.first?.seconds, 3_600)
    }

    func test_nonBillableCategory_remainsAdministrativeEvenWhenTodoFlagIsEnabled() throws {
        let customer = Customer(id: "customer-2", name: "Müşteri")
        try CustomerRepository().insert(customer)

        let todo = Todo(
            id: "todo-2",
            customerId: customer.id,
            categoryId: "administrative",
            title: "İdari iş",
            statusId: BuiltInTodoStatusId.done,
            isBillable: true,
            completedAt: Date()
        )
        try TodoRepository().insert(todo)

        let start = Date(timeIntervalSince1970: 1_800_100_000)
        try TodoTimeSessionRepository().insertManualSession(
            todoId: todo.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            note: nil
        )

        let viewModel = ReportsDashboardViewModel(services: AppServices(database: .shared))
        viewModel.loadData()
        viewModel.recompute(
            range: .all,
            customStart: start,
            customEnd: start,
            customerId: "",
            projectId: "",
            labels: .init(
                noCustomerTitle: "Müşterisiz",
                noProjectFormat: "%@ (Proje yok)",
                administrativeTitle: "İdari",
                billableTitle: "Faturalandırılabilir"
            )
        )

        XCTAssertEqual(viewModel.billableBreakdownData.count, 1)
        XCTAssertEqual(viewModel.billableBreakdownData.first?.name, "İdari")
        XCTAssertEqual(viewModel.billableBreakdownData.first?.seconds, 1_800)
    }
}
