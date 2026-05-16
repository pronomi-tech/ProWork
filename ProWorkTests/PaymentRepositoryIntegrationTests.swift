//
//  PaymentRepositoryIntegrationTests.swift
//  ProWorkTests
//
//  Created by Pronomi.
//

import XCTest
@testable import ProWork

final class PaymentRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var paymentRepository: PaymentRepository!
    private var runRepository: BillingReportRunRepository!
    private var customerRepository: CustomerRepository!
    private var customer: Customer!
    private var run: BillingReportRun!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        paymentRepository = PaymentRepository()
        runRepository = BillingReportRunRepository()
        customerRepository = CustomerRepository()

        customer = Customer(name: "Müşteri A")
        try customerRepository.insert(customer)

        run = BillingReportRun(
            customerId: customer.id,
            periodStart: "2026-01-01",
            periodEnd: "2026-01-31",
            currency: "TRY",
            totalMinor: 1_000_00,
            balanceMinor: 1_000_00
        )
        try runRepository.insert(run)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - CRUD

    func test_insert_thenFetchAll_returnsPayment() throws {
        let paidAt = Date(timeIntervalSince1970: 1_750_000_000)
        let payment = Payment(
            runId: run.id,
            paidAt: paidAt,
            amountMinor: 300_00,
            currency: "TRY",
            method: .bankTransfer,
            reference: "TR-001",
            note: "Kapora"
        )
        try paymentRepository.insert(payment)

        let payments = try paymentRepository.fetchAll(runId: run.id)
        XCTAssertEqual(payments.count, 1)
        let fetched = try XCTUnwrap(payments.first)
        XCTAssertEqual(fetched.amountMinor, 300_00)
        XCTAssertEqual(fetched.method, .bankTransfer)
        XCTAssertEqual(fetched.reference, "TR-001")
        XCTAssertEqual(fetched.note, "Kapora")
        XCTAssertEqual(fetched.paidAt, paidAt)
    }

    func test_fetchAll_sortsByPaidAtDescending() throws {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try paymentRepository.insert(Payment(runId: run.id, paidAt: base.addingTimeInterval(0),    amountMinor: 100, currency: "TRY"))
        try paymentRepository.insert(Payment(runId: run.id, paidAt: base.addingTimeInterval(7200), amountMinor: 200, currency: "TRY"))
        try paymentRepository.insert(Payment(runId: run.id, paidAt: base.addingTimeInterval(3600), amountMinor: 300, currency: "TRY"))

        let amounts = try paymentRepository.fetchAll(runId: run.id).map(\.amountMinor)
        // En geç → en erken sırada beklenir.
        XCTAssertEqual(amounts, [200, 300, 100])
    }

    func test_fetchAll_scopesToRun() throws {
        let otherRun = BillingReportRun(
            customerId: customer.id,
            periodStart: "2026-02-01",
            periodEnd: "2026-02-28",
            currency: "TRY",
            totalMinor: 500_00,
            balanceMinor: 500_00
        )
        try runRepository.insert(otherRun)

        try paymentRepository.insert(Payment(runId: run.id, amountMinor: 100, currency: "TRY"))
        try paymentRepository.insert(Payment(runId: otherRun.id, amountMinor: 200, currency: "TRY"))

        let mine = try paymentRepository.fetchAll(runId: run.id)
        XCTAssertEqual(mine.count, 1)
        XCTAssertEqual(mine.first?.amountMinor, 100)
    }

    func test_fetchAllForOrganization_returnsAllRuns() throws {
        let otherRun = BillingReportRun(
            customerId: customer.id,
            periodStart: "2026-02-01",
            periodEnd: "2026-02-28",
            currency: "TRY",
            totalMinor: 500_00,
            balanceMinor: 500_00
        )
        try runRepository.insert(otherRun)

        try paymentRepository.insert(Payment(runId: run.id, amountMinor: 1, currency: "TRY"))
        try paymentRepository.insert(Payment(runId: otherRun.id, amountMinor: 2, currency: "TRY"))

        let all = try paymentRepository.fetchAllForOrganization(BuiltInOrganizationId.default)
        XCTAssertEqual(all.count, 2)
    }

    func test_update_persistsAmountMethodAndReference() throws {
        var payment = Payment(
            runId: run.id,
            amountMinor: 100_00,
            currency: "TRY",
            method: .cash,
            reference: nil
        )
        try paymentRepository.insert(payment)

        payment.amountMinor = 250_00
        payment.method = .bankTransfer
        payment.reference = "TR-999"
        try paymentRepository.update(payment)

        let fetched = try XCTUnwrap(try paymentRepository.fetchAll(runId: run.id).first)
        XCTAssertEqual(fetched.amountMinor, 250_00)
        XCTAssertEqual(fetched.method, .bankTransfer)
        XCTAssertEqual(fetched.reference, "TR-999")
    }

    // MARK: - Soft delete

    func test_softDelete_hidesFromFetchAll() throws {
        let kept = Payment(runId: run.id, amountMinor: 100, currency: "TRY")
        let deleted = Payment(runId: run.id, amountMinor: 200, currency: "TRY")
        try paymentRepository.insert(kept)
        try paymentRepository.insert(deleted)

        try paymentRepository.softDelete(id: deleted.id)

        let remaining = try paymentRepository.fetchAll(runId: run.id).map(\.id)
        XCTAssertEqual(remaining, [kept.id])
    }

    // MARK: - Recalculate-aware integration

    func test_softDelete_excludesPaymentFromRecalculate() throws {
        try paymentRepository.insert(Payment(runId: run.id, amountMinor: 400_00, currency: "TRY"))
        let deleted = Payment(runId: run.id, amountMinor: 600_00, currency: "TRY")
        try paymentRepository.insert(deleted)

        try paymentRepository.softDelete(id: deleted.id)
        try runRepository.recalculatePayments(runId: run.id)

        let refreshed = try XCTUnwrap(try runRepository.fetch(id: run.id))
        XCTAssertEqual(refreshed.paidMinor, 400_00, "Soft-deleted payment recalculate'e dahil edilmemeli")
    }
}
