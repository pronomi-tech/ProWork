//  BillingReportRunRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.
//  Faturalandırma çekirdeği: BillingReportRun CRUD'ı + Migration002
//  ile gelen documentNumber + recalculatePayments() iş kuralı.

import XCTest
@testable import ProWork

final class BillingReportRunRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: BillingReportRunRepository!
    private var customerRepository: CustomerRepository!
    private var paymentRepository: PaymentRepository!
    private var customer: Customer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = BillingReportRunRepository()
        customerRepository = CustomerRepository()
        paymentRepository = PaymentRepository()
        customer = Customer(name: "Müşteri A")
        try customerRepository.insert(customer)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - CRUD

    func test_insert_thenFetchById_returnsRun() throws {
        let run = makeRun(periodStart: "2026-01-01", periodEnd: "2026-01-31", total: 100_00)
        try repository.insert(run)

        let fetched = try repository.fetch(id: run.id)
        XCTAssertEqual(fetched?.id, run.id)
        XCTAssertEqual(fetched?.customerId, customer.id)
        XCTAssertEqual(fetched?.periodStart, "2026-01-01")
        XCTAssertEqual(fetched?.totalMinor, 100_00)
        XCTAssertEqual(fetched?.status, .draft)
        XCTAssertNil(fetched?.documentNumber)
    }

    func test_documentNumber_roundTrips_throughInsertAndFetch() throws {
        var run = makeRun(periodStart: "2026-02-01", periodEnd: "2026-02-28", total: 0)
        run.documentNumber = "HD-2026-000123"
        try repository.insert(run)

        let fetched = try repository.fetch(id: run.id)
        XCTAssertEqual(fetched?.documentNumber, "HD-2026-000123")
    }

    func test_fetchAll_sortsByPeriodStartDescending() throws {
        try repository.insert(makeRun(periodStart: "2026-01-01", periodEnd: "2026-01-31", total: 1))
        try repository.insert(makeRun(periodStart: "2026-03-01", periodEnd: "2026-03-31", total: 2))
        try repository.insert(makeRun(periodStart: "2026-02-01", periodEnd: "2026-02-28", total: 3))

        let periods = try repository.fetchAll(organizationId: BuiltInOrganizationId.default).map(\.periodStart)
        XCTAssertEqual(periods, ["2026-03-01", "2026-02-01", "2026-01-01"])
    }

    func test_fetchAllForCustomer_filtersByCustomer() throws {
        let other = Customer(name: "Diğer Müşteri")
        try customerRepository.insert(other)

        try repository.insert(makeRun(periodStart: "2026-01-01", periodEnd: "2026-01-31", total: 1, customerId: customer.id))
        try repository.insert(makeRun(periodStart: "2026-01-01", periodEnd: "2026-01-31", total: 2, customerId: other.id))

        let mine = try repository.fetchAllForCustomer(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id
        )
        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(mine.first?.customerId, customer.id)
    }

    // MARK: - Update + status transitions

    func test_update_persistsStatusAndDocumentNumber() throws {
        var run = makeRun(periodStart: "2026-04-01", periodEnd: "2026-04-30", total: 50_00)
        try repository.insert(run)

        run.status = .final
        run.documentNumber = "HD-2026-000999"
        run.finalizedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try repository.update(run)

        let fetched = try repository.fetch(id: run.id)
        XCTAssertEqual(fetched?.status, .final)
        XCTAssertEqual(fetched?.documentNumber, "HD-2026-000999")
        XCTAssertEqual(fetched?.finalizedAt, Date(timeIntervalSince1970: 1_750_000_000))
    }

    // MARK: - fetchUnpaid

    func test_fetchUnpaid_returnsOnlyFinalizedAndStillOwing() throws {
        var draft = makeRun(periodStart: "2026-05-01", periodEnd: "2026-05-31", total: 100_00)
        try repository.insert(draft)

        var unpaidFinal = makeRun(periodStart: "2026-05-01", periodEnd: "2026-05-31", total: 200_00)
        unpaidFinal.status = .final
        unpaidFinal.paymentStatus = .unpaid
        try repository.insert(unpaidFinal)

        var paidFinal = makeRun(periodStart: "2026-05-01", periodEnd: "2026-05-31", total: 300_00)
        paidFinal.status = .final
        paidFinal.paymentStatus = .paid
        try repository.insert(paidFinal)

        let unpaid = try repository.fetchUnpaid(organizationId: BuiltInOrganizationId.default).map(\.id)
        XCTAssertTrue(unpaid.contains(unpaidFinal.id))
        XCTAssertFalse(unpaid.contains(paidFinal.id), "Tam ödenmiş kayıt unpaid listesinde olmamalı")
        XCTAssertFalse(unpaid.contains(draft.id), "Draft kayıt unpaid listesinde olmamalı")
    }

    // MARK: - recalculatePayments

    func test_recalculatePayments_setsPartialStatus_whenSomePaid() throws {
        var run = makeRun(periodStart: "2026-06-01", periodEnd: "2026-06-30", total: 100_00)
        run.status = .final
        try repository.insert(run)

        try paymentRepository.insert(Payment(
            runId: run.id,
            paidAt: Date(),
            amountMinor: 30_00,
            currency: "TRY"
        ))

        try repository.recalculatePayments(runId: run.id)

        let fetched = try XCTUnwrap(try repository.fetch(id: run.id))
        XCTAssertEqual(fetched.paidMinor, 30_00)
        XCTAssertEqual(fetched.balanceMinor, 70_00)
        XCTAssertEqual(fetched.paymentStatus, .partial)
    }

    func test_recalculatePayments_setsPaidStatus_whenFullyPaid() throws {
        var run = makeRun(periodStart: "2026-07-01", periodEnd: "2026-07-31", total: 50_00)
        run.status = .final
        try repository.insert(run)

        try paymentRepository.insert(Payment(
            runId: run.id,
            paidAt: Date(),
            amountMinor: 50_00,
            currency: "TRY"
        ))

        try repository.recalculatePayments(runId: run.id)

        let fetched = try XCTUnwrap(try repository.fetch(id: run.id))
        XCTAssertEqual(fetched.paidMinor, 50_00)
        XCTAssertEqual(fetched.balanceMinor, 0)
        XCTAssertEqual(fetched.paymentStatus, .paid)
    }

    // MARK: - K10: overdue & paid-amount source of truth

    /// `dueDate` < bugün ve hiç ödeme yoksa overdue. Önceki kodda
    /// `date(dueDate) < date('now')` çağrısı `dueDate` formatını
    /// tanımayınca NULL döndürüp overdue'yu hiç set etmiyordu.
    func test_K10_recalculatePayments_setsOverdueStatus_whenDueDateInPast_andNoPayment() throws {
        var run = makeRun(periodStart: "2026-04-01", periodEnd: "2026-04-30", total: 75_00)
        run.status = .final
        run.dueDate = "2026-05-01"  // bugün (2026-05-17) öncesinde
        try repository.insert(run)

        try repository.recalculatePayments(runId: run.id)

        let fetched = try XCTUnwrap(try repository.fetch(id: run.id))
        XCTAssertEqual(fetched.paidMinor, 0)
        XCTAssertEqual(fetched.balanceMinor, 75_00)
        XCTAssertEqual(fetched.paymentStatus, .overdue)
    }

    /// Vadesi gelmemiş, ödenmemiş kayıt → unpaid (overdue değil).
    func test_K10_recalculatePayments_setsUnpaid_whenDueDateInFuture() throws {
        var run = makeRun(periodStart: "2026-09-01", periodEnd: "2026-09-30", total: 50_00)
        run.status = .final
        run.dueDate = "2099-01-01"
        try repository.insert(run)

        try repository.recalculatePayments(runId: run.id)

        let fetched = try XCTUnwrap(try repository.fetch(id: run.id))
        XCTAssertEqual(fetched.paymentStatus, .unpaid)
    }

    /// Vadesi geçmiş ama tam ödenmiş kayıt → paid (overdue değil).
    func test_K10_recalculatePayments_paidWinsOverOverdue() throws {
        var run = makeRun(periodStart: "2026-04-01", periodEnd: "2026-04-30", total: 40_00)
        run.status = .final
        run.dueDate = "2026-05-01"
        try repository.insert(run)

        try paymentRepository.insert(Payment(
            runId: run.id,
            paidAt: Date(),
            amountMinor: 40_00,
            currency: "TRY"
        ))

        try repository.recalculatePayments(runId: run.id)

        let fetched = try XCTUnwrap(try repository.fetch(id: run.id))
        XCTAssertEqual(fetched.paymentStatus, .paid)
    }

    // MARK: - Soft delete

    func test_softDelete_hidesRunFromFetchAll() throws {
        let kept = makeRun(periodStart: "2026-08-01", periodEnd: "2026-08-31", total: 1)
        let deleted = makeRun(periodStart: "2026-08-01", periodEnd: "2026-08-31", total: 2)
        try repository.insert(kept)
        try repository.insert(deleted)

        try repository.softDelete(id: deleted.id, by: BuiltInUserId.defaultOwner)

        let remaining = try repository.fetchAll(organizationId: BuiltInOrganizationId.default).map(\.id)
        XCTAssertTrue(remaining.contains(kept.id))
        XCTAssertFalse(remaining.contains(deleted.id))
    }

    // MARK: - Helper

    private func makeRun(
        periodStart: String,
        periodEnd: String,
        total: Int,
        customerId: String? = nil
    ) -> BillingReportRun {
        BillingReportRun(
            customerId: customerId ?? customer.id,
            periodStart: periodStart,
            periodEnd: periodEnd,
            currency: "TRY",
            subtotalMinor: total,
            vatMinor: 0,
            totalMinor: total,
            balanceMinor: total
        )
    }
}
