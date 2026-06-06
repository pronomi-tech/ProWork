//  ExchangeRateRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class ExchangeRateRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: ExchangeRateRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = ExchangeRateRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Upsert

    func test_upsert_thenFetchLatest_returnsRate() throws {
        let rate = makeRate(from: "USD", to: "TRY", rate: 30, date: "2026-01-15", source: .tcmb)
        try repository.upsert(rate)

        let latest = try repository.fetchLatest(
            organizationId: BuiltInOrganizationId.default,
            from: "USD",
            to: "TRY",
            on: "2026-01-15"
        )

        XCTAssertEqual(latest?.rate, 30)
        XCTAssertEqual(latest?.source, .tcmb)
        XCTAssertEqual(latest?.rateDate, "2026-01-15")
    }

    func test_upsert_updatesExistingTriple_inPlace() throws {
        let same = (org: BuiltInOrganizationId.default, from: "USD", to: "TRY", date: "2026-02-01", source: ExchangeRateSource.tcmb)
        let first = makeRate(from: same.from, to: same.to, rate: 31, date: same.date, source: same.source)
        try repository.upsert(first)

        let updated = makeRate(from: same.from, to: same.to, rate: 32, date: same.date, source: same.source)
        try repository.upsert(updated)

        let all = try repository.fetchAll(organizationId: BuiltInOrganizationId.default)
            .filter { $0.fromCurrency == "USD" && $0.toCurrency == "TRY" && $0.rateDate == "2026-02-01" }

        XCTAssertEqual(all.count, 1, "Aynı (org, from, to, date, source) için tek satır olmalı")
        XCTAssertEqual(all.first?.rate, 32)
    }

    // MARK: - fetchLatest semantics

    func test_fetchLatest_returnsHighestDate_atOrBeforeTarget() throws {
        try repository.upsert(makeRate(from: "EUR", to: "TRY", rate: 32, date: "2026-01-01", source: .tcmb))
        try repository.upsert(makeRate(from: "EUR", to: "TRY", rate: 33, date: "2026-01-10", source: .tcmb))
        try repository.upsert(makeRate(from: "EUR", to: "TRY", rate: 99, date: "2026-02-01", source: .tcmb))

        let latest = try repository.fetchLatest(
            organizationId: BuiltInOrganizationId.default,
            from: "EUR",
            to: "TRY",
            on: "2026-01-15"
        )
        XCTAssertEqual(latest?.rate, 33, "≤ targetDate olan en yüksek tarih beklenir, 2026-02-01 atlanmalı")
    }

    func test_fetchLatest_appliesSourcePriority_atSameDate() throws {
        try repository.upsert(makeRate(from: "GBP", to: "TRY", rate: 40, date: "2026-03-01", source: .tcmb))
        try repository.upsert(makeRate(from: "GBP", to: "TRY", rate: 41, date: "2026-03-01", source: .manual))

        // Manual önce geldiği durum (default priority).
        let manualFirst = try repository.fetchLatest(
            organizationId: BuiltInOrganizationId.default,
            from: "GBP",
            to: "TRY",
            on: "2026-03-01"
        )
        XCTAssertEqual(manualFirst?.source, .manual)

        // Caller TCMB'yi öne alırsa onun gelmesi gerekir.
        let tcmbFirst = try repository.fetchLatest(
            organizationId: BuiltInOrganizationId.default,
            from: "GBP",
            to: "TRY",
            on: "2026-03-01",
            sourcePriority: [.tcmb, .manual, .global]
        )
        XCTAssertEqual(tcmbFirst?.source, .tcmb)
    }

    func test_fetchLatest_returnsNil_whenNoRateAtOrBefore() throws {
        try repository.upsert(makeRate(from: "JPY", to: "TRY", rate: 0.2, date: "2099-01-01", source: .tcmb))

        let latest = try repository.fetchLatest(
            organizationId: BuiltInOrganizationId.default,
            from: "JPY",
            to: "TRY",
            on: "2026-01-01"
        )
        XCTAssertNil(latest, "Hedef tarihten önce satır yoksa nil dönmeli")
    }

    // MARK: - Soft delete

    func test_softDelete_excludesRowFromFetchLatest() throws {
        let rate = makeRate(from: "CHF", to: "TRY", rate: 35, date: "2026-04-01", source: .tcmb)
        try repository.upsert(rate)

        try repository.softDelete(id: rate.id, by: BuiltInUserId.defaultOwner)

        let latest = try repository.fetchLatest(
            organizationId: BuiltInOrganizationId.default,
            from: "CHF",
            to: "TRY",
            on: "2026-04-01"
        )
        XCTAssertNil(latest)
    }

    // MARK: - Helper

    private func makeRate(
        from: String,
        to: String,
        rate: Decimal,
        date: String,
        source: ExchangeRateSource
    ) -> ExchangeRate {
        ExchangeRate(
            fromCurrency: from,
            toCurrency: to,
            rate: rate,
            forexBuying: rate,
            forexSelling: rate,
            banknoteBuying: rate,
            banknoteSelling: rate,
            rateDate: date,
            source: source,
            fetchedAt: Date(),
            note: nil
        )
    }
}
