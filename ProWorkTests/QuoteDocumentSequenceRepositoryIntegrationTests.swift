//  QuoteDocumentSequenceRepositoryIntegrationTests.swift
//  ProWorkTests
//  Quote numbering persistence and concurrency behavior.

import XCTest
@testable import ProWork

final class QuoteDocumentSequenceRepositoryIntegrationTests: XCTestCase {

    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
    }

    override func tearDown() {
        if let url = dbURL {
            DatabaseTestHelper.teardown(at: url)
        }
        dbURL = nil
        super.tearDown()
    }

    func test_freshDB_hasQuoteDocumentSequencesTable() throws {
        let rows = try AppDatabase.shared.query("""
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = 'quote_document_sequences';
        """) { statement in
            statement.text(at: 0) ?? ""
        }
        XCTAssertEqual(rows, ["quote_document_sequences"],
                       "The consolidated migrations should create quote_document_sequences.")
    }

    func test_reserveNext_returnsOne_onFreshTable() throws {
        let repo = QuoteDocumentSequenceRepository()
        let first = try repo.reserveNext(
            organizationId: BuiltInOrganizationId.default,
            year: 2026
        )
        XCTAssertEqual(first, 1)
    }

    func test_reserveNext_isMonotonic_perOrgAndYear() throws {
        let repo = QuoteDocumentSequenceRepository()
        let org = BuiltInOrganizationId.default

        let a1 = try repo.reserveNext(organizationId: org, year: 2026)
        let a2 = try repo.reserveNext(organizationId: org, year: 2026)
        let a3 = try repo.reserveNext(organizationId: org, year: 2026)
        XCTAssertEqual([a1, a2, a3], [1, 2, 3])

        let b1 = try repo.reserveNext(organizationId: org, year: 2027)
        XCTAssertEqual(b1, 1, "Different year should restart at 1.")
    }

    func test_peekCurrent_doesNotConsumeASlot() throws {
        let repo = QuoteDocumentSequenceRepository()
        _ = try repo.reserveNext(organizationId: BuiltInOrganizationId.default, year: 2026)

        let peeked1 = try repo.peekCurrent(organizationId: BuiltInOrganizationId.default, year: 2026)
        let peeked2 = try repo.peekCurrent(organizationId: BuiltInOrganizationId.default, year: 2026)
        XCTAssertEqual(peeked1, 1)
        XCTAssertEqual(peeked2, 1, "peekCurrent should NOT advance the counter.")
    }

    // MARK: - Concurrent reservation: duplicate üretmemeli

    /// Regression guard: paralel `reserveNext` çağrıları unique
    /// 1..N değerleri dönmeli; `NSRecursiveLock` + `BEGIN IMMEDIATE` her
    /// rezervasyonu serileştirir. Aynı senaryo `BillingDocumentSequenceRepository`
    /// için doğrulandı (BillingDocumentSequenceRepositoryIntegrationTests),
    /// buradaki test quote tarafı için sigortayı koyuyor.
    func test_reserveNext_underConcurrentCalls_producesUniqueValues() throws {
        let repository = QuoteDocumentSequenceRepository()
        let org = BuiltInOrganizationId.default
        let year = 2026
        let iterations = 100

        let queue = DispatchQueue(
            label: "test.quote.concurrent.reserve",
            qos: .userInitiated,
            attributes: .concurrent
        )
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [Int] = []
        collected.reserveCapacity(iterations)
        var failures: [Error] = []

        for _ in 0..<iterations {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    let value = try repository.reserveNext(organizationId: org, year: year)
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
        XCTAssertEqual(waitResult, .success, "Concurrent reservations should finish within 20s.")

        XCTAssertTrue(failures.isEmpty, "No reservation should throw under contention: \(failures)")
        XCTAssertEqual(collected.count, iterations)

        let unique = Set(collected)
        XCTAssertEqual(unique.count, iterations,
                       "Every reservation must return a unique value (duplicate quote-number risk).")
        XCTAssertEqual(unique, Set(1...iterations),
                       "Reservations should cover exactly 1...\(iterations) with no gaps.")

        XCTAssertEqual(
            try repository.peekCurrent(organizationId: org, year: year),
            iterations,
            "Final stored nextValue should equal the iteration count."
        )
    }
}
