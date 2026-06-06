//  AppDatabase.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3
import os

final class AppDatabase {
    /// Lock-guarded thread-safe singleton. `nonisolated` because every
    /// state mutation is guarded by `NSRecursiveLock` — repository
    /// inits resolve the default `AppDatabase.shared` argument in a nonisolated
    /// context'ten okuyabilsin diye (Swift 6 strict concurrency).
    nonisolated static let shared = AppDatabase()

    // All mutable state below is guarded by `lock`. NSRecursiveLock is used
    // because reentrancy is required: `configure` triggers migrations that
    // call back into `execute`/`query`, and `withReconnectRetry` re-enters
    // `configure` through `reopenCurrentConnection`.
    private let lock = NSRecursiveLock()
    private var db: OpaquePointer?
    private var _databaseURL: URL?
    private var securityScopedDatabaseURL: URL?
    private var securityScopedContainerURL: URL?
    private var isDatabaseSecurityScopeActive = false
    private var isContainerSecurityScopeActive = false
    /// While `configure` and migrations run, `withReconnectRetry` must not
    /// enter the reopen branch — otherwise `reopen → configure → runMigrations
    /// → execute → withReconnectRetry → reopen` would spin into infinite
    /// recursion (Migration002 surfaced this). True for the duration of configure.
    private var isConfiguring = false
    /// Reentrancy guard for transaction helpers. `inWriteTransaction`
    /// and `inTransaction` may be nested in any order; when depth > 0
    /// the outer transaction already owns the SQLite write lock, so the
    /// inner call must use SAVEPOINT instead of `BEGIN IMMEDIATE`
    /// (nested BEGIN raises "cannot start a transaction within a
    /// transaction"). Guarded by `lock`.
    fileprivate var transactionDepth = 0

    /// Journal mode resolved during the last `configure`. When it fell
    /// back to `.memory` there's no crash-safety (sidecar files couldn't
    /// be created — typically a cloud-sync folder); the upper layer
    /// inspects this and warns the user.
    private var _resolvedJournalMode: JournalMode = .memory

    enum JournalMode: String {
        case wal = "WAL"
        case truncate = "TRUNCATE"
        case memory = "MEMORY"

        /// Sidecar-based (disk-writing rollback) durable modes.
        /// `.memory` is not durable.
        var isDurable: Bool { self != .memory }
    }

    var resolvedJournalMode: JournalMode {
        lock.lock()
        defer { lock.unlock() }
        return _resolvedJournalMode
    }

    var databaseURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _databaseURL
    }

    private init() {}

    deinit {
        close()
    }
}

private extension AppDatabase {
    func prepareParentDirectory(for url: URL) throws {
        let folderURL = url.deletingLastPathComponent()
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: folderURL.path) {
            try fileManager.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
        }
    }

    func enableForeignKeys() throws {
        try execute("PRAGMA foreign_keys = ON;")
    }

    func configureTemporaryStorage() throws {
        // Avoid sandbox-side temp files for sort/temp work.
        try execute("PRAGMA temp_store = MEMORY;")
    }

    /// Register a busy timeout so writes that briefly contend with another
    /// connection (or with our own background work) retry transparently
    /// instead of returning `SQLITE_BUSY` to the caller. Without this,
    /// `sqlite3_exec` propagates BUSY immediately and the higher-level code
    /// has nothing to retry on.
    /// 5 seconds is generous for an interactive desktop app — the only
    /// readers/writers are this process and macOS' own filesystem layer,
    /// and any "real" lock contention beyond that points at a logic bug
    /// rather than something a longer timeout would mask.
    func configureBusyTimeout() throws {
        guard let db else { throw DatabaseError.notOpen }
        sqlite3_busy_timeout(db, 5_000)
    }

    func configureJournalMode() throws {
        // Durability preference order: WAL → TRUNCATE → MEMORY.
        // WAL is the safest + fastest option but requires sibling files
        // (`-wal`, `-shm`). Under macOS security-scoped folder access
        // those sibling files may not be creatable and SQLite returns
        // "unable to open database file" on the first write. The same
        // happens for TRUNCATE (`-journal`). When that's the case, falling
        // back to MEMORY is the only working option — which is the mode
        // the original version already used.
        // MEMORY trade-off: uncommitted work is lost on crash, and the DB
        // can corrupt on power loss. We accept this for the side-file
        // restriction that forces our hand; users who prefer durability
        // should keep the data file in a folder without those limits.
        // Important: `setJournalMode` itself may throw "unable to open
        // database file" from SQLite under sandbox restrictions (when WAL
        // can't open its `-wal`/`-shm` sibling files). We don't want to
        // break the chain — we swallow with `try?` and fall to the next mode.
        if let walMode = try? setJournalMode("WAL"), walMode == "wal", probeWritability() {
            try execute("PRAGMA synchronous = NORMAL;")
            _resolvedJournalMode = .wal
            ProWorkLog.database.info("Journal mode: WAL")
            return
        }

        if let truncateMode = try? setJournalMode("TRUNCATE"), truncateMode == "truncate", probeWritability() {
            try execute("PRAGMA synchronous = FULL;")
            _resolvedJournalMode = .truncate
            ProWorkLog.database.info("Journal mode: TRUNCATE")
            return
        }

        // Last resort: MEMORY. Should always work because it creates no side files.
        // every journal-mode branch now explicitly
        // re-sets PRAGMA synchronous so the value never inherits from a
        // previous open of the same connection (which could leave us on
        // FULL after a TRUNCATE attempt rolled back to MEMORY). The
        // MEMORY journal pairs naturally with NORMAL — there is no
        // durable rollback log to flush anyway.
        _ = try setJournalMode("MEMORY")
        try execute("PRAGMA synchronous = NORMAL;")
        _resolvedJournalMode = .memory
        ProWorkLog.database.info("Journal mode: MEMORY (fallback)")
    }

    /// `mode` is interpolated into the SQL. Must only be called with the
    /// hardcoded literals at the call sites ("WAL" / "TRUNCATE" / "MEMORY").
    /// Any data coming from the user or disk would create a PRAGMA
    /// injection risk; SQLite does not support binding the PRAGMA name as
    /// a parameter.
    private func setJournalMode(_ mode: String) throws -> String {
        let rows = try query("PRAGMA journal_mode = \(mode);") { statement in
            (statement.text(at: 0) ?? "").lowercased()
        }
        return rows.first ?? ""
    }

    /// In TRUNCATE/DELETE mode SQLite only creates the `-journal` side file
    /// on a **real data/schema write**; BEGIN IMMEDIATE alone isn't enough.
    /// In CloudStorage folders (e.g. OneDrive) the sandbox blocks side-file
    /// creation ("Operation not permitted") and a fake BEGIN/ROLLBACK probe
    /// returns a false positive — then the migration explodes on the first
    /// real write. So we put a real DDL into the probe: create a temp table
    /// and immediately roll back. No persistent schema effect remains, but
    /// the journal-file creation is actually attempted.
    private func probeWritability() -> Bool {
        do {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            try execute("CREATE TABLE _prowork_writability_probe (x INTEGER);")
            try execute("ROLLBACK;")
            return true
        } catch {
            // Clean up so no transaction stays open (if the rollback itself
            // throws it's swallowed — the DB is already unusable at that point).
            try? execute("ROLLBACK;")
            return false
        }
    }

    func runMigrations() throws {
        try DatabaseMigrator.migrate(self)
    }

    func shouldRetryOpenFileFailure(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("unable to open database file")
    }

    func reopenCurrentConnection() throws {
        guard let currentDatabaseURL = securityScopedDatabaseURL ?? _databaseURL else {
            throw DatabaseError.notOpen
        }

        let currentContainerURL = securityScopedContainerURL ?? currentDatabaseURL.deletingLastPathComponent()
        close()
        try configure(at: currentDatabaseURL, containerDirectoryURL: currentContainerURL)
    }

    /// Retries the operation once after a connection reopen when SQLite
    /// reports "unable to open database file" (typically a sandboxed temp dir
    /// went away). Must only wrap **work that has no live statement
    /// outstanding** — most notably `sqlite3_prepare_v2`. Wrapping a full
    /// prepare→step→finalize cycle would leave the in-flight statement
    /// pointing at a closed connection when the retry reopens it, causing
    /// the `defer sqlite3_finalize` to touch a dangling handle. All call
    /// sites in this file use the `prepareStatementWithReconnect` helper,
    /// which respects that rule.
    func withReconnectRetry<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as DatabaseError {
            // The bodies of the executionFailed and openFailed branches were
            // identical; a single catch + if/case-let preserves the semantics
            // and trims the line count. Other DatabaseError branches (e.g.
            // .notOpen), or messages that fail the
            // `isConfiguring`/`shouldRetryOpenFileFailure` check, are
            // re-thrown unchanged.
            let message: String
            switch error {
            case .executionFailed(let m), .openFailed(let m):
                message = m
            case .notOpen:
                throw error
            }
            guard shouldRetryOpenFileFailure(message), !isConfiguring else {
                throw error
            }
            try reopenCurrentConnection()
            return try operation()
        }
    }

    /// Prepares a statement with reconnect-retry semantics scoped strictly
    /// around the prepare call. The returned statement belongs to the
    /// **post-retry** connection, so subsequent bind/step/finalize calls
    /// are always on a live handle. Caller must `sqlite3_finalize` the
    /// returned pointer.
    func prepareStatementWithReconnect(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try withReconnectRetry {
            guard let db else {
                throw DatabaseError.notOpen
            }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let message = lastErrorMessage
                if let statement {
                    sqlite3_finalize(statement)
                }
                statement = nil
                throw DatabaseError.executionFailed(message: message)
            }
        }
        guard let statement else {
            throw DatabaseError.executionFailed(message: lastErrorMessage)
        }
        return statement
    }

    func execute(_ sql: String) throws {
        guard let db else {
            throw DatabaseError.notOpen
        }

        var errorMessage: UnsafeMutablePointer<Int8>?

        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw DatabaseError.executionFailed(message: message)
        }
    }

    var lastErrorMessage: String {
        guard let db else {
            return "Database is not open."
        }

        return String(cString: sqlite3_errmsg(db))
    }
}

extension AppDatabase {
    /// Number of rows changed by the most recent INSERT/UPDATE/DELETE on
    /// this connection. Wraps `sqlite3_changes`; callers that need to
    /// verify a precondition-bound UPDATE actually matched a row can
    /// inspect this immediately after the `execute` call. Returns 0 when
    /// the connection is not open.
    var lastChangedRowCount: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }
        return Int(sqlite3_changes(db))
    }
}

enum DatabaseError: Error, LocalizedError {
    case notOpen
    case openFailed(message: String)
    case executionFailed(message: String)

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    private func humanReadable(_ rawMessage: String) -> String {
        // Translate raw messages coming from SQLite/sandbox into user-friendly text.
        // Typical case: when the security-scoped folder can't create the sibling
        // journal/wal file, "unable to open database file" comes through.
        let lower = rawMessage.lowercased()
        if lower.contains("unable to open database file") {
            return localized(
                "database.error.unableToOpenFile",
                defaultValue: "Veri dosyasına erişilemiyor. Klasör izinleri değişmiş ya da dosya başka bir yere taşınmış olabilir. Lütfen dosyayı yeniden seçin."
            )
        }
        if lower.contains("database is locked") {
            return localized(
                "database.error.locked",
                defaultValue: "Veri dosyası başka bir işlem tarafından kullanılıyor olabilir. Birkaç saniye sonra yeniden deneyin."
            )
        }
        if lower.contains("disk i/o error") || lower.contains("disk full") {
            return localized(
                "database.error.diskIO",
                defaultValue: "Disk erişiminde bir sorun oluştu. Diskte yeterli alan olduğundan ve dosyanın yazılabilir olduğundan emin olun."
            )
        }
        return rawMessage
    }

    var errorDescription: String? {
        switch self {
        case .notOpen:
            return localized(
                "database.error.notOpen",
                defaultValue: "Veri dosyası açık değil."
            )
        case .openFailed(let message):
            return humanReadable(message)
        case .executionFailed(let message):
            return humanReadable(message)
        }
    }
}

extension AppDatabase {
    /// 14+ repositories carried byte-for-byte identical
    /// `softDelete(id:by:)` implementations. Centralise the SQL skeleton
    /// here so a tuning change (e.g. bumping `rowVersion`, swapping the
    /// timestamp format) is a one-line edit.
    /// `table` is interpolated into the SQL string — pass only a hardcoded
    /// table identifier from a repository, never user input.
    func softDelete(
        table: String,
        id: String,
        by userId: String = BuiltInUserId.defaultOwner,
        at date: Date = Date()
    ) throws {
        let sql = """
        UPDATE \(table)
        SET
            deletedAt = ?,
            updatedAt = ?,
            updatedByUserId = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try execute(sql) { statement in
            let timestamp = DateFormatter.proWorkSQLite.string(from: date)
            statement.bindText(timestamp, at: 1)
            statement.bindText(timestamp, at: 2)
            statement.bindText(userId, at: 3)
            statement.bindText(id, at: 4)
        }
    }
}

extension AppDatabase {
    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return db != nil
    }

    func configure(at url: URL, containerDirectoryURL: URL? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        if let existing = _databaseURL, existing == url, db != nil {
            return
        }

        close()

        let didAccessDatabaseSecurityScope = url.startAccessingSecurityScopedResource()
        let didAccessContainerSecurityScope = containerDirectoryURL?.startAccessingSecurityScopedResource() ?? false

        isConfiguring = true
        defer { isConfiguring = false }

        do {
            try prepareParentDirectory(for: url)

            var connection: OpaquePointer?
            if sqlite3_open(url.path, &connection) != SQLITE_OK {
                let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown database error."
                if let connection {
                    sqlite3_close(connection)
                }
                throw DatabaseError.openFailed(message: message)
            }

            db = connection
            _databaseURL = url
            securityScopedDatabaseURL = url
            securityScopedContainerURL = containerDirectoryURL
            isDatabaseSecurityScopeActive = didAccessDatabaseSecurityScope
            isContainerSecurityScopeActive = didAccessContainerSecurityScope

            try enableForeignKeys()
            try configureTemporaryStorage()
            try configureBusyTimeout()
            try configureJournalMode()
            try runMigrations()

            // DB path may contain the user directory, so privacy: .private.
            ProWorkLog.database.info("ProWork database ready at: \(url.path, privacy: .private)")
        } catch {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
            _databaseURL = nil
            if didAccessDatabaseSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            if didAccessContainerSecurityScope {
                containerDirectoryURL?.stopAccessingSecurityScopedResource()
            }
            securityScopedDatabaseURL = nil
            securityScopedContainerURL = nil
            isDatabaseSecurityScopeActive = false
            isContainerSecurityScopeActive = false
            throw error
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }

        if let db {
            sqlite3_close(db)
            self.db = nil
        }

        _databaseURL = nil

        if isDatabaseSecurityScopeActive {
            securityScopedDatabaseURL?.stopAccessingSecurityScopedResource()
        }
        if isContainerSecurityScopeActive {
            securityScopedContainerURL?.stopAccessingSecurityScopedResource()
        }

        securityScopedDatabaseURL = nil
        securityScopedContainerURL = nil
        isDatabaseSecurityScopeActive = false
        isContainerSecurityScopeActive = false
    }

    /// Runs the given block inside a **serialised write transaction**:
    /// `lock` is held for the duration of the block and `BEGIN IMMEDIATE
    /// TRANSACTION` also takes an exclusive write lock at the SQLite level.
    /// No other thread in this process (e.g. a parallel `finalizeRun`)
    /// can acquire `lock` until the block ends, so "read-then-write" race
    /// conditions are prevented. Because `NSRecursiveLock` is used, every
    /// `execute/query` call made inside the block can safely re-enter on
    /// the same thread.
    /// - Note: Reentrant calls (e.g. `inTransaction { inWriteTransaction { … } }`)
    ///   are supported: the outer transaction already owns the SQLite
    ///   write lock, so the inner call falls back to SAVEPOINT instead of
    ///   `BEGIN IMMEDIATE`. Detected via the `transactionDepth` counter.
    func inWriteTransaction<T>(_ block: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        if transactionDepth > 0 {
            // Outer transaction already holds the write lock; nested BEGIN
            // would fail. Delegate to the savepoint helper which gives the
            // caller the same all-or-nothing semantics within the outer tx.
            return try inTransaction(block)
        }

        try execute("BEGIN IMMEDIATE TRANSACTION;")
        transactionDepth += 1
        do {
            let result = try block()
            try execute("COMMIT;")
            transactionDepth -= 1
            return result
        } catch {
            // Clean up so no transaction stays open. If the ROLLBACK itself
            // throws (e.g. the connection dropped) it's swallowed; the main
            // path is `throw error` so the original error is preserved.
            try? execute("ROLLBACK;")
            transactionDepth -= 1
            throw error
        }
    }

    /// Reentrant transaction helper built on SQLite `SAVEPOINT`.
    /// Repositories used to call `execute("BEGIN TRANSACTION;")` directly;
    /// when a service tried to wrap two repository writes in one
    /// transaction, the inner call hit `cannot start a transaction within
    /// a transaction` because the outer `BEGIN` was already open. With
    /// `SAVEPOINT`, each call can be rolled back at its own level without
    /// affecting the outer transaction.
    /// Savepoint names are derived from a unique UUID hex; no SQL
    /// injection or collision risk.
    func inTransaction<T>(_ block: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        let savepoint = "sp_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        try execute("SAVEPOINT \(savepoint);")
        transactionDepth += 1
        do {
            let result = try block()
            try execute("RELEASE SAVEPOINT \(savepoint);")
            transactionDepth -= 1
            return result
        } catch {
            // ROLLBACK TO savepoint reverts any rows recorded while it
            // was open but does not close the savepoint; RELEASE clears
            // that. Both are best-effort — the original error is re-thrown
            // in any case.
            try? execute("ROLLBACK TRANSACTION TO SAVEPOINT \(savepoint);")
            try? execute("RELEASE SAVEPOINT \(savepoint);")
            transactionDepth -= 1
            throw error
        }
    }

    func execute(_ sql: String, bind: ((SQLiteStatement) -> Void)? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        // Retry is scoped to the prepare step only (K4); once we own a
        // live statement, a step failure must not trigger a reconnect.
        let statement = try prepareStatementWithReconnect(sql)
        defer { sqlite3_finalize(statement) }

        bind?(SQLiteStatement(statement: statement))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(message: lastErrorMessage)
        }
    }

    func query<T>(_ sql: String, map: (SQLiteStatement) throws -> T) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }

        let statement = try prepareStatementWithReconnect(sql)
        defer { sqlite3_finalize(statement) }

        var result: [T] = []
        let wrapped = SQLiteStatement(statement: statement)

        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try map(wrapped))
        }

        return result
    }

    /// Bulk insert/update with statement reuse — prepare runs once, and the
    /// statement is reused for every item via `sqlite3_reset` +
    /// `sqlite3_clear_bindings`. The old "execute in a loop" pattern
    /// prepared + finalised per row; for thousands of lines that overhead
    /// was noticeable. One critical section (`lock`), one prepared statement.
    ///
    /// - Parameter wrapInTransaction: Default `true`. When wrapping is on
    ///   the batch runs in a single transaction; if interrupted, the rows
    ///   already processed are rolled back. If the caller has an outer
    ///   transaction open they can pass `false` (a nested SAVEPOINT would
    ///   be a redundant extra layer).
    func executeBatch<C: Collection>(
        _ sql: String,
        items: C,
        wrapInTransaction: Bool = true,
        bind: (SQLiteStatement, C.Element) throws -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        if wrapInTransaction {
            try inTransaction {
                try runBatch(sql: sql, items: items, bind: bind)
            }
        } else {
            try runBatch(sql: sql, items: items, bind: bind)
        }
    }

    private func runBatch<C: Collection>(
        sql: String,
        items: C,
        bind: (SQLiteStatement, C.Element) throws -> Void
    ) throws {
        let statement = try prepareStatementWithReconnect(sql)
        defer { sqlite3_finalize(statement) }
        let wrapped = SQLiteStatement(statement: statement)

        for item in items {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(wrapped, item)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(message: lastErrorMessage)
            }
        }
    }

    func query<T>(
        _ sql: String,
        map: (SQLiteStatement) throws -> T,
        bind: (SQLiteStatement) throws -> Void
    ) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }

        let statement = try prepareStatementWithReconnect(sql)
        defer { sqlite3_finalize(statement) }

        let wrappedStatement = SQLiteStatement(statement: statement)
        try bind(wrappedStatement)

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(try map(wrappedStatement))
        }

        return rows
    }
}

struct SQLiteStatement {
    let statement: OpaquePointer

    func text(at index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: value)
    }

    /// Returns 0 for NULL columns — this conflates a real 0 with missing
    /// data in financial columns. Prefer `requiredInt(at:)` on NOT NULL
    /// schema-guaranteed fields; use `optionalInt(at:)` on fields that
    /// allow NULL. The non-throwing API is kept for backward compatibility
    /// with existing call sites.
    func int(at index: Int32) -> Int {
        return Int(sqlite3_column_int(statement, index))
    }

    /// Throws when the column is SQL NULL. Use this on columns declared
    /// NOT NULL — billing minor amounts, counts, version numbers — so a
    /// schema drift (or a corrupt row) surfaces instead of silently
    /// reading 0 and corrupting downstream math (e.g. invoices summing
    /// to zero).
    func requiredInt(at index: Int32, field: String) throws -> Int {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            throw DatabaseError.executionFailed(
                message: "Required integer column '\(field)' is NULL. Row is corrupt or schema is out of date."
            )
        }
        return Int(sqlite3_column_int(statement, index))
    }

    func optionalInt(at index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return Int(sqlite3_column_int(statement, index))
    }

    func bindText(_ value: String?, at index: Int32) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindInt(_ value: Int, at index: Int32) {
        sqlite3_bind_int(statement, index, Int32(value))
    }

    func bindOptionalInt(_ value: Int?, at index: Int32) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bindBlob(_ value: Data?, at index: Int32) {
        if let value {
            value.withUnsafeBytes { rawBuffer in
                let pointer = rawBuffer.baseAddress
                sqlite3_bind_blob(
                    statement,
                    index,
                    pointer,
                    Int32(value.count),
                    SQLITE_TRANSIENT
                )
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func optionalBlob(at index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        let length = Int(sqlite3_column_bytes(statement, index))
        guard length > 0, let pointer = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(bytes: pointer, count: length)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension DateFormatter {
    /// `AppDateFormatters.sqliteTimestamp` is the single authoritative source;
    /// this alias is kept to avoid breaking the existing 30+ call sites.
    /// New code should reference `AppDateFormatters` directly.
    static var proWorkSQLite: DateFormatter { AppDateFormatters.sqliteTimestamp }
}
