//
//  BillingReportLineRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//

import XCTest
@testable import ProWork

final class BillingReportLineRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var lineRepository: BillingReportLineRepository!
    private var runRepository: BillingReportRunRepository!
    private var customerRepository: CustomerRepository!
    private var todoRepository: TodoRepository!
    private var categoryRepository: TaskCategoryRepository!
    private var customer: Customer!
    private var category: TaskCategory!
    private var run: BillingReportRun!
    private var todo: Todo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        lineRepository = BillingReportLineRepository()
        runRepository = BillingReportRunRepository()
        customerRepository = CustomerRepository()
        todoRepository = TodoRepository()
        categoryRepository = TaskCategoryRepository()

        customer = Customer(name: "qa-Müşteri")
        try customerRepository.insert(customer)

        category = TaskCategory(name: "qa-Kategori")
        try categoryRepository.insert(category)

        todo = Todo(
            categoryId: category.id,
            title: "qa-Test todo",
            statusId: BuiltInTodoStatusId.waiting
        )
        try todoRepository.insert(todo)

        run = BillingReportRun(
            customerId: customer.id,
            periodStart: "2026-01-01",
            periodEnd: "2026-01-31",
            currency: "TRY",
            totalMinor: 0,
            balanceMinor: 0
        )
        try runRepository.insert(run)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - CRUD

    func test_insert_thenFetchAll_returnsLine() throws {
        let line = makeLine(amount: 100_00, segmentIndex: 0)
        try lineRepository.insert(line)

        let lines = try lineRepository.fetchAll(runId: run.id)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.amountMinor, 100_00)
        XCTAssertEqual(lines.first?.todoTitle, "qa-Test todo")
        XCTAssertEqual(lines.first?.customerName, customer.name)
    }

    func test_fetchAll_sortsBySortOrder() throws {
        try lineRepository.insert(makeLine(amount: 1, segmentIndex: 0, sortOrder: 10))
        try lineRepository.insert(makeLine(amount: 2, segmentIndex: 1, sortOrder: 0))
        try lineRepository.insert(makeLine(amount: 3, segmentIndex: 2, sortOrder: 5))

        let amounts = try lineRepository.fetchAll(runId: run.id).map(\.amountMinor)
        XCTAssertEqual(amounts, [2, 3, 1])
    }

    // MARK: - replace

    func test_replace_clearsExistingAndInsertsNewLines() throws {
        try lineRepository.insert(makeLine(amount: 1, segmentIndex: 0))
        try lineRepository.insert(makeLine(amount: 2, segmentIndex: 1))

        let replaced = [
            makeLine(amount: 50, segmentIndex: 0),
            makeLine(amount: 60, segmentIndex: 1),
            makeLine(amount: 70, segmentIndex: 2)
        ]
        try lineRepository.replace(runId: run.id, lines: replaced)

        let amounts = try lineRepository.fetchAll(runId: run.id).map(\.amountMinor)
        XCTAssertEqual(Set(amounts), [50, 60, 70])
    }

    func test_replace_isAtomic_rollsBackOnFailure() throws {
        try lineRepository.insert(makeLine(amount: 99, segmentIndex: 0))

        // Run id mismatch — replace deletes the original lines and tries to
        // insert lines with the wrong runId; FK fails and we expect a throw.
        let badLines = [
            BillingReportLine(
                runId: "non-existent-run",
                todoId: todo.id,
                todoTitle: "qa-Bad",
                customerId: customer.id,
                customerName: customer.name,
                serviceType: .remote,
                timeType: .regular,
                amountMinor: 1,
                currency: "TRY"
            )
        ]

        XCTAssertThrowsError(try lineRepository.replace(runId: run.id, lines: badLines))

        let remaining = try lineRepository.fetchAll(runId: run.id).map(\.amountMinor)
        XCTAssertEqual(remaining, [99], "Failed replace ROLLBACK ile orijinal satırı korumalı")
    }

    // MARK: - deleteAll

    func test_deleteAll_removesEveryLineForRun() throws {
        try lineRepository.insert(makeLine(amount: 1, segmentIndex: 0))
        try lineRepository.insert(makeLine(amount: 2, segmentIndex: 1))

        try lineRepository.deleteAll(runId: run.id)

        XCTAssertEqual(try lineRepository.fetchAll(runId: run.id).count, 0)
    }

    // MARK: - fetchSelectionAssignments

    func test_fetchSelectionAssignments_returnsLinesForCustomer() throws {
        try lineRepository.insert(makeLine(amount: 100, segmentIndex: 0))

        let assignments = try lineRepository.fetchSelectionAssignments(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id
        )
        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments.first?.runLabel, run.title ?? run.invoiceNumber ?? run.id)
    }

    func test_fetchSelectionAssignments_excludesGivenRun() throws {
        try lineRepository.insert(makeLine(amount: 100, segmentIndex: 0))

        let assignments = try lineRepository.fetchSelectionAssignments(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id,
            excludingRunId: run.id
        )
        XCTAssertEqual(assignments.count, 0, "excludingRunId verilen run'ın satırlarını dışlamalı")
    }

    // MARK: - Helper

    private func makeLine(
        amount: Int,
        segmentIndex: Int,
        sortOrder: Int = 0
    ) -> BillingReportLine {
        BillingReportLine(
            runId: run.id,
            sessionId: nil,
            todoId: todo.id,
            todoTitle: todo.title,
            customerId: customer.id,
            customerName: customer.name,
            serviceType: .remote,
            timeType: .regular,
            segmentIndex: segmentIndex,
            actualSeconds: 3600,
            billableMinutes: 60,
            unitPriceMinor: amount,
            amountMinor: amount,
            currency: "TRY",
            vatMinor: 0,
            totalMinor: amount,
            sortOrder: sortOrder
        )
    }
}
