//
//  BillingIntegrationTests.swift
//  ProWorkTests
//
//  Gerçek DB üstünde uçtan uca senaryolar:
//  BillingComputationService.computePeriod + BillingRunLifecycleService.createDraft/finalize/delete.
//

import XCTest
@testable import ProWork

@MainActor
final class BillingIntegrationTests: XCTestCase {

    private var dbURL: URL!
    private let calendar = TimeWindowSplitter.istanbulCalendar

    // Sabit referans ID'leri (test izolasyonu için)
    private let customerId = "cust-test-1"
    private let categoryId = "cat-dev"
    private let priceListId = "pl-cust-1"

    override func setUp() async throws {
        try await super.setUp()
        dbURL = try DatabaseTestHelper.freshDatabase()
        try seedFixture()
    }

    override func tearDown() async throws {
        if let url = dbURL {
            DatabaseTestHelper.teardown(at: url)
        }
        dbURL = nil
        try await super.tearDown()
    }

    // MARK: - Fixture

    /// Bir müşteri + müşteri fiyat listesi + 1 saat saat ücretli regular satır + kategori seed eder.
    /// Default org, default user, default billing rule, default VAT (20%) zaten Migration001'den geliyor.
    private func seedFixture() throws {
        let customer = Customer(
            id: customerId,
            name: "Müşteri A",
            defaultPriceListId: priceListId,
            defaultServiceType: "remote",
            defaultMinBillingMinutes: 60
        )
        try CustomerRepository().insert(customer)

        let category = TaskCategory(
            id: categoryId,
            name: "Geliştirme",
            isBillableDefault: true
        )
        try TaskCategoryRepository().insert(category)

        let list = PriceList(
            id: priceListId,
            ownerType: .customer,
            ownerId: customerId,
            name: "Müşteri A Listesi",
            currency: "TRY"
        )
        try PriceListRepository().insert(list)

        let row = PriceListRow(
            priceListId: priceListId,
            serviceType: .remote,
            timeType: .regular,
            unitPriceMinor: 200_000 // 2.000,00 TRY/saat
        )
        try PriceListRowRepository().insert(row)
    }

    /// 2026-05-07 Perşembe 10:00 (mesai içi) tarihinde başlayan, belirtilen dakika kadar süren manuel session ekler.
    /// Geri dönen Todo + session id.
    @discardableResult
    private func seedSession(startHour: Int = 10, startMinute: Int = 0, durationMinutes: Int) throws -> (todo: Todo, sessionStart: Date, sessionEnd: Date) {
        let todo = Todo(
            customerId: customerId,
            categoryId: categoryId,
            title: "Test todo",
            isBillable: true
        )
        try TodoRepository().insert(todo)

        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 7
        c.hour = startHour; c.minute = startMinute
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")
        let start = calendar.date(from: c)!
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))

        try TodoTimeSessionRepository().insertManualSession(
            todoId: todo.id,
            startedAt: start,
            endedAt: end,
            note: nil
        )

        return (todo, start, end)
    }

    private func dayBoundary(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = 0; c.minute = 0
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return calendar.date(from: c)!
    }

    // MARK: - BillingComputationService

    func test_computePeriod_singleSession_producesExpectedLineWithVat() throws {
        try seedSession(durationMinutes: 60)

        let svc = BillingComputationService()
        let lines = try svc.computePeriod(
            from: dayBoundary(year: 2026, month: 5, day: 7),
            to: dayBoundary(year: 2026, month: 5, day: 8)
        )

        XCTAssertEqual(lines.count, 1)
        let line = lines[0]
        XCTAssertEqual(line.unitPriceMinor, 200_000)
        XCTAssertEqual(line.billableMinutes, 60)
        XCTAssertEqual(line.amountMinor, 200_000)
        XCTAssertEqual(line.timeType, .regular)
        XCTAssertEqual(line.currency, "TRY")
        // Default 20% VAT
        XCTAssertEqual(line.vatRate, Decimal(string: "0.20"))
        XCTAssertEqual(line.vatMinor, 40_000)
        XCTAssertEqual(line.totalMinor, 240_000)
    }

    func test_computePeriod_sessionOutsidePeriod_isExcluded() throws {
        try seedSession(durationMinutes: 60) // 2026-05-07

        let svc = BillingComputationService()
        // Bambaşka bir dönem (Mart) → satır olmamalı
        let lines = try svc.computePeriod(
            from: dayBoundary(year: 2026, month: 3, day: 1),
            to: dayBoundary(year: 2026, month: 3, day: 31)
        )
        XCTAssertEqual(lines.count, 0)
    }

    func test_computePeriod_emptyDb_returnsEmpty() throws {
        // Hiç session yok
        let svc = BillingComputationService()
        let lines = try svc.computePeriod(
            from: dayBoundary(year: 2026, month: 5, day: 7),
            to: dayBoundary(year: 2026, month: 5, day: 8)
        )
        XCTAssertEqual(lines.count, 0)
    }

    // MARK: - BillingRunLifecycleService

    func test_lifecycle_createDraft_thenFinalize_thenStateChanges() throws {
        try seedSession(durationMinutes: 60)

        let svc = BillingRunLifecycleService()
        let draft = try svc.createDraft(
            customerId: customerId,
            periodStart: dayBoundary(year: 2026, month: 5, day: 1),
            periodEnd: dayBoundary(year: 2026, month: 5, day: 31),
            title: "Mayıs 2026"
        )

        XCTAssertEqual(draft.run.status, .draft)
        XCTAssertFalse(draft.lines.isEmpty)
        XCTAssertEqual(draft.run.subtotalMinor, 200_000)
        XCTAssertEqual(draft.run.totalMinor, 240_000)
        XCTAssertEqual(draft.run.currency, "TRY")
        XCTAssertEqual(draft.customer?.id, customerId)

        let finalized = try svc.finalizeRun(runId: draft.run.id, invoiceNumber: "INV-001")
        XCTAssertEqual(finalized.run.status, .final)
        XCTAssertEqual(finalized.run.invoiceNumber, "INV-001")
        XCTAssertNotNil(finalized.run.finalizedAt)
    }

    func test_lifecycle_createDraft_noSessions_throwsNoBillableLines() throws {
        // Session yok → draft oluşturulamaz
        let svc = BillingRunLifecycleService()
        XCTAssertThrowsError(
            try svc.createDraft(
                customerId: customerId,
                periodStart: dayBoundary(year: 2026, month: 5, day: 1),
                periodEnd: dayBoundary(year: 2026, month: 5, day: 31)
            )
        ) { error in
            guard case BillingRunLifecycleError.noBillableLinesForPeriod = error else {
                XCTFail("noBillableLinesForPeriod bekleniyordu, alındı: \(error)")
                return
            }
        }
    }

    func test_lifecycle_createDraft_unknownCustomer_throwsCustomerNotFound() throws {
        let svc = BillingRunLifecycleService()
        XCTAssertThrowsError(
            try svc.createDraft(
                customerId: "olmayan-musteri",
                periodStart: dayBoundary(year: 2026, month: 5, day: 1),
                periodEnd: dayBoundary(year: 2026, month: 5, day: 31)
            )
        ) { error in
            guard case BillingRunLifecycleError.customerNotFound = error else {
                XCTFail("customerNotFound bekleniyordu, alındı: \(error)")
                return
            }
        }
    }

    func test_lifecycle_deleteRun_onDraft_succeeds() throws {
        try seedSession(durationMinutes: 60)

        let svc = BillingRunLifecycleService()
        let draft = try svc.createDraft(
            customerId: customerId,
            periodStart: dayBoundary(year: 2026, month: 5, day: 1),
            periodEnd: dayBoundary(year: 2026, month: 5, day: 31)
        )
        XCTAssertNoThrow(try svc.deleteRun(runId: draft.run.id))

        // Tekrar silme → runNotFound (soft-deleted artık fetch dönmez)
        XCTAssertThrowsError(try svc.deleteRun(runId: draft.run.id)) { error in
            guard case BillingRunLifecycleError.runNotFound = error else {
                XCTFail("runNotFound bekleniyordu, alındı: \(error)")
                return
            }
        }
    }

    func test_lifecycle_deleteRun_onFinalized_throws() throws {
        try seedSession(durationMinutes: 60)

        let svc = BillingRunLifecycleService()
        let draft = try svc.createDraft(
            customerId: customerId,
            periodStart: dayBoundary(year: 2026, month: 5, day: 1),
            periodEnd: dayBoundary(year: 2026, month: 5, day: 31)
        )
        _ = try svc.finalizeRun(runId: draft.run.id)

        XCTAssertThrowsError(try svc.deleteRun(runId: draft.run.id)) { error in
            guard case BillingRunLifecycleError.onlyDraftRunsCanBeDeleted = error else {
                XCTFail("onlyDraftRunsCanBeDeleted bekleniyordu, alındı: \(error)")
                return
            }
        }
    }

    func test_lifecycle_cancelRun_onlyAllowsFinalized() throws {
        try seedSession(durationMinutes: 60)

        let svc = BillingRunLifecycleService()
        let draft = try svc.createDraft(
            customerId: customerId,
            periodStart: dayBoundary(year: 2026, month: 5, day: 1),
            periodEnd: dayBoundary(year: 2026, month: 5, day: 31)
        )

        // Draft iken cancel → hata
        XCTAssertThrowsError(try svc.cancelRun(runId: draft.run.id)) { error in
            guard case BillingRunLifecycleError.onlyFinalizedRunsCanBeCancelled = error else {
                XCTFail("onlyFinalizedRunsCanBeCancelled bekleniyordu, alındı: \(error)")
                return
            }
        }

        // Finalize sonrası cancel → çalışmalı
        _ = try svc.finalizeRun(runId: draft.run.id)
        let cancelled = try svc.cancelRun(runId: draft.run.id)
        XCTAssertEqual(cancelled.run.status, .cancelled)
    }

    func test_lifecycle_finalize_thenReopen_returnsToDraft() throws {
        try seedSession(durationMinutes: 60)

        let svc = BillingRunLifecycleService()
        let draft = try svc.createDraft(
            customerId: customerId,
            periodStart: dayBoundary(year: 2026, month: 5, day: 1),
            periodEnd: dayBoundary(year: 2026, month: 5, day: 31)
        )
        _ = try svc.finalizeRun(runId: draft.run.id)

        let reopened = try svc.reopenRun(runId: draft.run.id)
        XCTAssertEqual(reopened.run.status, .draft)
        XCTAssertNil(reopened.run.finalizedAt)
    }
}
