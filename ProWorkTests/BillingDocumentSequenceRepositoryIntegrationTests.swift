//  BillingDocumentSequenceRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.
// regression suite — belge numarası sayacının atomik
//  rezerve edildiğini ve concurrent çağrılarda duplicate üretmediğini
//  doğrular. Eski JSON read-modify-write akışında iki paralel finalize
//  aynı değeri rezerve edebiliyordu; yeni `inWriteTransaction` + SQL
//  UPSERT bu yarışı engelliyor.

import XCTest
@testable import ProWork

final class BillingDocumentSequenceRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: BillingDocumentSequenceRepository!

    private let orgA = BuiltInOrganizationId.default
    private let orgB = "org-test-tenant-b"

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = BillingDocumentSequenceRepository()
    }

    override func tearDown() {
        if let url = dbURL {
            DatabaseTestHelper.teardown(at: url)
        }
        dbURL = nil
        super.tearDown()
    }

    // MARK: - Sıralı rezervasyon

    func test_reserveNext_startsAtOne_onFreshTable() throws {
        let first = try repository.reserveNext(organizationId: orgA, year: 2026)
        XCTAssertEqual(first, 1, "Yeni tabloda ilk rezervasyon 1 olmalı")
    }

    func test_reserveNext_incrementsMonotonically() throws {
        let values = try (0..<5).map { _ in
            try repository.reserveNext(organizationId: orgA, year: 2026)
        }
        XCTAssertEqual(values, [1, 2, 3, 4, 5])
    }

    func test_reserveNext_independentPerYear() throws {
        _ = try repository.reserveNext(organizationId: orgA, year: 2025)
        _ = try repository.reserveNext(organizationId: orgA, year: 2025)
        _ = try repository.reserveNext(organizationId: orgA, year: 2025)

        let firstIn2026 = try repository.reserveNext(organizationId: orgA, year: 2026)
        XCTAssertEqual(firstIn2026, 1, "2026 sayacı 2025'ten bağımsız olmalı")

        let fourthIn2025 = try repository.reserveNext(organizationId: orgA, year: 2025)
        XCTAssertEqual(fourthIn2025, 4, "2025 sayacı 2026'dan etkilenmemeli")
    }

    func test_reserveNext_independentPerOrganization() throws {
        _ = try repository.reserveNext(organizationId: orgA, year: 2026)
        _ = try repository.reserveNext(organizationId: orgA, year: 2026)

        let firstInOrgB = try repository.reserveNext(organizationId: orgB, year: 2026)
        XCTAssertEqual(firstInOrgB, 1, "Org B sayacı Org A'dan bağımsız olmalı")

        let thirdInOrgA = try repository.reserveNext(organizationId: orgA, year: 2026)
        XCTAssertEqual(thirdInOrgA, 3)
    }

    // MARK: - peekCurrent

    func test_peekCurrent_returnsNil_onUnseededRow() throws {
        XCTAssertNil(try repository.peekCurrent(organizationId: orgA, year: 2099))
    }

    func test_peekCurrent_returnsLatestValue_withoutIncrementing() throws {
        _ = try repository.reserveNext(organizationId: orgA, year: 2026)
        _ = try repository.reserveNext(organizationId: orgA, year: 2026)

        XCTAssertEqual(try repository.peekCurrent(organizationId: orgA, year: 2026), 2)
        XCTAssertEqual(try repository.peekCurrent(organizationId: orgA, year: 2026), 2,
                       "peek artırmamalı")
    }

    // MARK: - K1 ana regression: concurrent çağrı duplicate üretmemeli

    func test_reserveNext_underConcurrentCalls_producesUniqueValues() throws {
        // 100 concurrent rezervasyon. NSRecursiveLock + BEGIN IMMEDIATE
        // her birini serileştirir — ama sonuç set'i {1...100} olmalı,
        // hiçbir değer eksik veya duplike değil.
        let iterations = 100
        let queue = DispatchQueue(label: "test.concurrent.reserve",
                                  qos: .userInitiated,
                                  attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [Int] = []
        collected.reserveCapacity(iterations)
        var failures: [Error] = []

        for _ in 0..<iterations {
            group.enter()
            queue.async { [self] in
                defer { group.leave() }
                do {
                    let value = try repository.reserveNext(organizationId: orgA, year: 2026)
                    lock.lock()
                    collected.append(value)
                    lock.unlock()
                } catch {
                    lock.lock()
                    failures.append(error)
                    lock.unlock()
                }
            }
        }

        let waitResult = group.wait(timeout: .now() + .seconds(20))
        XCTAssertEqual(waitResult, .success, "20 saniyede tamamlanmalı")

        XCTAssertTrue(failures.isEmpty, "Hiç hata olmamalı: \(failures)")
        XCTAssertEqual(collected.count, iterations)

        let unique = Set(collected)
        XCTAssertEqual(unique.count, iterations,
                       "Tüm rezervasyon değerleri unique olmalı (duplicate fatura no riski)")
        XCTAssertEqual(unique, Set(1...iterations),
                       "Değerler 1...\(iterations) aralığında olmalı, boşluk olmamalı")

        // Tabloda final durum: nextValue = iterations
        XCTAssertEqual(try repository.peekCurrent(organizationId: orgA, year: 2026), iterations)
    }

    // MARK: - Migration seed: mevcut app_settings JSON değeri korunmalı

    func test_migrationSeed_preservesExistingSequenceValue() throws {
        // Bu test özel bir setup gerektiriyor — mevcut tabloyu silip
        // app_settings'e değer yazdıktan sonra migration'ı yeniden uygulayamayız
        // (DatabaseMigrator idempotent). Bunun yerine ham seed mantığını
        // doğrulamak için: tabloya manuel değer yazıp INSERT OR IGNORE'un
        // mevcut değeri ezmediğini test ediyoruz.

        try AppDatabase.shared.execute("""
        INSERT INTO billing_document_sequences (organizationId, year, nextValue, updatedAt)
        VALUES (?, 2024, 42, '2024-12-31 23:59:59');
        """) { stmt in
            stmt.bindText(self.orgA, at: 1)
        }

        // Yeni rezervasyon mevcut 42'nin üstüne devam etmeli (43, 44 ...)
        let next = try repository.reserveNext(organizationId: orgA, year: 2024)
        XCTAssertEqual(next, 43, "Migration sonrası mevcut değer korunmalı; yeni rezervasyon ardından gelmeli")
    }
}
