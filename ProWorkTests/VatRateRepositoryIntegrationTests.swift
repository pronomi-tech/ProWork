//  VatRateRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class VatRateRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: VatRateRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = VatRateRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Built-in seed

    func test_fetchAll_includesBuiltInDefault_andExempt() throws {
        let rates = try repository.fetchAll()
        let ids = Set(rates.map(\.id))
        XCTAssertTrue(ids.contains(BuiltInVatRateId.defaultStandard))
        XCTAssertTrue(ids.contains(BuiltInVatRateId.exempt))
    }

    func test_fetchDefault_returnsTheRowMarkedDefault() throws {
        let defaultRate = try repository.fetchDefault()
        XCTAssertNotNil(defaultRate)
        XCTAssertEqual(defaultRate?.isDefault, true)
    }

    // MARK: - Custom CRUD

    func test_insert_thenFetchById_returnsRate() throws {
        let rate = VatRate(name: "qa-Reduced", rate: Decimal(string: "0.10")!)
        try repository.insert(rate)

        let fetched = try repository.fetch(id: rate.id)
        XCTAssertEqual(fetched?.name, "qa-Reduced")
        XCTAssertEqual(fetched?.rate, Decimal(string: "0.10"))
        XCTAssertEqual(fetched?.isDefault, false)
        XCTAssertEqual(fetched?.isExempt, false)
    }

    func test_exemptRate_zerosOutRate_onInsert() throws {
        let rate = VatRate(name: "qa-Exempt", rate: Decimal(string: "0.20")!, isExempt: true)
        try repository.insert(rate)

        let fetched = try repository.fetch(id: rate.id)
        XCTAssertEqual(fetched?.isExempt, true)
        XCTAssertEqual(fetched?.rate, 0, "isExempt=true rate'i 0'a indirmeli")
    }

    func test_update_persistsNoteAndRate() throws {
        var rate = VatRate(name: "qa-Edit", rate: Decimal(string: "0.10")!)
        try repository.insert(rate)

        rate.note = "İndirimli oran"
        rate.rate = Decimal(string: "0.08")!
        try repository.update(rate)

        let fetched = try repository.fetch(id: rate.id)
        XCTAssertEqual(fetched?.note, "İndirimli oran")
        XCTAssertEqual(fetched?.rate, Decimal(string: "0.08"))
    }

    // MARK: - Soft delete

    func test_softDelete_hidesFromFetchAll() throws {
        let kept = VatRate(name: "qa-Kalan", rate: Decimal(string: "0.20")!)
        let deleted = VatRate(name: "qa-Silinen", rate: Decimal(string: "0.10")!)
        try repository.insert(kept)
        try repository.insert(deleted)

        try repository.softDelete(id: deleted.id, by: BuiltInUserId.defaultOwner)

        let remaining = try repository.fetchAll()
            .filter { $0.name.hasPrefix("qa-") }
            .map(\.name)
        XCTAssertEqual(remaining, ["qa-Kalan"])
    }

    // MARK: - vatMinor calculation

    func test_vatMinor_computesProductOfSubtotalAndRate() throws {
        let rate = VatRate(name: "qa-20pct", rate: Decimal(string: "0.20")!)
        XCTAssertEqual(rate.vatMinor(forSubtotal: 10_000), 2_000) // 100.00 ₺ → 20.00 ₺
        XCTAssertEqual(rate.vatMinor(forSubtotal: 625), 125)      // 6.25 ₺ → 1.25 ₺
    }

    func test_vatMinor_usesBankersRounding_atHalfBoundary() throws {
        // Bankacı yuvarlama: yarım birimde en yakın çift sayıya yuvarlanır
        // (1.5 → 2, 2.5 → 2). Fractional minor üretmek için %2.5 oran.
        let rate = VatRate(name: "qa-2.5pct", rate: Decimal(string: "0.025")!)
        XCTAssertEqual(rate.vatMinor(forSubtotal: 60), 2)  // 60 × 0.025 = 1.5 → 2
        XCTAssertEqual(rate.vatMinor(forSubtotal: 100), 2) // 100 × 0.025 = 2.5 → 2
    }

    func test_vatMinor_returnsZero_whenExempt() throws {
        let rate = VatRate(name: "qa-Exempt", rate: Decimal(string: "0.20")!, isExempt: true)
        XCTAssertEqual(rate.vatMinor(forSubtotal: 10_000), 0)
    }
}
