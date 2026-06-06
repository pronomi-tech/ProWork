//  BillingRuleRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class BillingRuleRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: BillingRuleRepository!
    private var customerRepository: CustomerRepository!
    private var customer: Customer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = BillingRuleRepository()
        customerRepository = CustomerRepository()
        customer = Customer(name: "Müşteri A")
        try customerRepository.insert(customer)
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Seeded global

    func test_fetchGlobal_returnsSeededRule() throws {
        let global = try repository.fetchGlobal(organizationId: BuiltInOrganizationId.default)
        XCTAssertNotNil(global, "Migration001 default global billing rule seed etmeli")
        XCTAssertEqual(global?.scope, .global)
        XCTAssertEqual(global?.timezone, "Europe/Istanbul")
    }

    // MARK: - Upsert + scope semantics

    func test_upsert_customerRule_thenFetchForCustomer_returnsIt() throws {
        let rule = BillingRule(
            scope: .customer,
            customerId: customer.id,
            weekdayHours: BillingRule.defaultWeekdayHours,
            weekendDays: [.saturday, .sunday],
            timezone: "Europe/Istanbul"
        )
        try repository.upsert(rule)

        let fetched = try repository.fetchForCustomer(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id
        )
        XCTAssertEqual(fetched?.id, rule.id)
        XCTAssertEqual(fetched?.scope, .customer)
        XCTAssertEqual(fetched?.customerId, customer.id)
    }

    func test_fetchForCustomer_returnsNil_whenOnlyGlobalExists() throws {
        let fetched = try repository.fetchForCustomer(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id
        )
        XCTAssertNil(fetched, "Müşteriye özel kural yoksa nil dönmeli (global seed varsayılan değil)")
    }

    // MARK: - resolve precedence

    func test_resolve_prefersCustomerRule_overGlobal() throws {
        let customerRule = BillingRule(
            scope: .customer,
            customerId: customer.id,
            weekendDays: [.friday, .saturday], // farklı bir hafta sonu kombinasyonu
            timezone: "Europe/Istanbul"
        )
        try repository.upsert(customerRule)

        let resolved = try repository.resolve(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id
        )
        XCTAssertEqual(resolved?.id, customerRule.id)
        XCTAssertEqual(resolved?.weekendDays, [.friday, .saturday])
    }

    func test_resolve_fallsBackToGlobal_whenCustomerRuleAbsent() throws {
        let resolved = try repository.resolve(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id
        )
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.scope, .global, "Müşteri kuralı yoksa global'e düşmeli")
    }

    func test_resolve_returnsGlobal_whenCustomerIdNil() throws {
        let resolved = try repository.resolve(
            organizationId: BuiltInOrganizationId.default,
            customerId: nil
        )
        XCTAssertEqual(resolved?.scope, .global)
    }

    // MARK: - Upsert overwrites existing row

    func test_upsert_updatesExistingRow_byPrimaryKey() throws {
        var rule = BillingRule(
            scope: .customer,
            customerId: customer.id,
            weekendDays: [.saturday, .sunday]
        )
        try repository.upsert(rule)

        rule.weekendDays = [.friday]
        rule.timezone = "Europe/London"
        try repository.upsert(rule)

        let fetched = try repository.fetchForCustomer(
            organizationId: BuiltInOrganizationId.default,
            customerId: customer.id
        )
        XCTAssertEqual(fetched?.weekendDays, [.friday])
        XCTAssertEqual(fetched?.timezone, "Europe/London")
    }
}
