//  Migration007QuoteSequenceMigrationTests.swift
//  ProWorkTests
// Verifies Migration007:
//    1. Fresh DB has the `quote_document_sequences` table.
//    2. QuoteDocumentSequenceRepository.reserveNext returns 1 on fresh state.
//    3. A pre-existing JSON payload in `app_settings.quoteSequenceByYear`
//       is seeded into the new table so monotonicity survives the migration.

import XCTest
@testable import ProWork

final class Migration007QuoteSequenceMigrationTests: XCTestCase {

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
                       "Migration007 should create quote_document_sequences.")
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

    func test_legacyAppSettingsJSON_isPreservedInsideNewTable() throws {
        // Simulate a DB that lived through the old JSON-counter era by
        // inserting a quoteSequenceByYear app_settings row, then running
        // a "re-migration" via a fresh AppDatabase.configure on the same URL.
        // Since fresh tests start with the table already populated by
        // Migration007's seed step, the cleanest way to validate the
        // seed-from-JSON path is to:
        //   1. Wipe quote_document_sequences.
        //   2. Insert a JSON row into app_settings (matching the legacy
        //      payload shape).
        //   3. Re-invoke the seed step directly.
        try AppDatabase.shared.execute("DELETE FROM quote_document_sequences;")

        let now = AppDateFormatters.sqliteTimestamp.string(from: Date())
        try AppDatabase.shared.execute("""
        INSERT OR REPLACE INTO app_settings (key, value, createdAt, updatedAt)
        VALUES (?, ?, ?, ?);
        """) { stmt in
            stmt.bindText("quoteSequenceByYear", at: 1)
            stmt.bindText(#"{"2025":7}"#, at: 2)
            stmt.bindText(now, at: 3)
            stmt.bindText(now, at: 4)
        }

        // Re-invoke the migration step (idempotent).
        try Migration007QuoteSequenceTable().up(AppDatabase.shared)

        let repo = QuoteDocumentSequenceRepository()
        let peeked = try repo.peekCurrent(
            organizationId: BuiltInOrganizationId.default,
            year: 2025
        )
        XCTAssertEqual(peeked, 7,
                       "Legacy JSON value should seed the new table.")

        // The next reservation continues the legacy series — value 8.
        let next = try repo.reserveNext(
            organizationId: BuiltInOrganizationId.default,
            year: 2025
        )
        XCTAssertEqual(next, 8,
                       "reserveNext after seed should continue monotonically.")
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
