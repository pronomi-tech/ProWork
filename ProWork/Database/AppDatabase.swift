//
//  AppDatabase.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3
import os

final class AppDatabase {
    static let shared = AppDatabase()

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
    /// `configure` ve migrasyonlar çalışırken `withReconnectRetry` reopen
    /// dalına girmemeli — aksi halde `reopen → configure → runMigrations →
    /// execute → withReconnectRetry → reopen` sonsuz rekürsiyon doğar
    /// (Migration002 bunu ortaya çıkardı). Configure süresince true.
    private var isConfiguring = false

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

    func configureJournalMode() throws {
        // Durability tercih sırası: WAL → TRUNCATE → MEMORY.
        //
        // WAL en güvenli + en hızlı seçim ama yan dosya yaratmayı gerektirir
        // (`-wal`, `-shm`). macOS güvenlik kapsamlı (security-scoped) klasör
        // erişimlerinde bu sibling dosyaları yaratılamayabiliyor ve SQLite
        // ilk yazıda "unable to open database file" döndürüyor. Aynı sorun
        // TRUNCATE (`-journal`) için de geçerli. Bu durumda MEMORY'ye düşmek
        // tek çalışan seçenek — bu, orijinal sürümün zaten kullandığı moddu.
        //
        // MEMORY trade-off'u: crash anında commit edilmemiş işlemler kaybolur,
        // güç kesintisinde DB bozulabilir. Bunu kaçınılmaz hale getiren yan
        // dosya kısıtı için bunu kabul ediyoruz; durability'yi tercih eden
        // kullanıcılar veri dosyasını sınırsız bir klasörde tutmalı.
        // Önemli: setJournalMode'un kendisi sandbox kısıtlamalarında SQLite
        // tarafından "unable to open database file" ile fırlayabilir (WAL için
        // -wal/-shm yan dosyalarını açamadığında). Bu durumda zinciri kırmak
        // istemiyoruz — try? ile yutup bir sonraki moda düşüyoruz.
        if let walMode = try? setJournalMode("WAL"), walMode == "wal", probeWritability() {
            try execute("PRAGMA synchronous = NORMAL;")
            ProWorkLog.database.info("Journal mode: WAL")
            return
        }

        if let truncateMode = try? setJournalMode("TRUNCATE"), truncateMode == "truncate", probeWritability() {
            try execute("PRAGMA synchronous = FULL;")
            ProWorkLog.database.info("Journal mode: TRUNCATE")
            return
        }

        // Son çare: MEMORY. Yan dosya yaratmadığı için her zaman çalışmalı.
        _ = try setJournalMode("MEMORY")
        try execute("PRAGMA synchronous = NORMAL;")
        ProWorkLog.database.info("Journal mode: MEMORY (fallback)")
    }

    private func setJournalMode(_ mode: String) throws -> String {
        let rows = try query("PRAGMA journal_mode = \(mode);") { statement in
            (statement.text(at: 0) ?? "").lowercased()
        }
        return rows.first ?? ""
    }

    /// TRUNCATE/DELETE modunda SQLite, `-journal` yan dosyasını sadece **gerçek
    /// bir veri/şema yazımı** olduğunda yaratır; BEGIN IMMEDIATE tek başına
    /// yetmiyor. OneDrive gibi CloudStorage klasörlerinde sandbox yan dosya
    /// yaratımını engelliyor ("Operation not permitted") ve sahte BEGIN/ROLLBACK
    /// probe'u false-positive dönüyor — sonra migration gerçek yazıda patlıyor.
    ///
    /// Bu yüzden probe'a gerçek bir DDL koyuyoruz: geçici tablo oluştur, hemen
    /// rollback ile geri al. Schema'ya hiçbir kalıcı etki kalmaz ama journal
    /// dosyası yaratımı gerçekten denenir.
    private func probeWritability() -> Bool {
        do {
            try execute("BEGIN IMMEDIATE TRANSACTION;")
            try execute("CREATE TABLE _prowork_writability_probe (x INTEGER);")
            try execute("ROLLBACK;")
            return true
        } catch {
            // Açık transaction kalmasın diye temizle (rollback'in kendisi de
            // çökerse yutulur — DB zaten kullanılamayacak durumda demektir).
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

    func withReconnectRetry<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch DatabaseError.executionFailed(let message) where shouldRetryOpenFileFailure(message) && !isConfiguring {
            try reopenCurrentConnection()
            return try operation()
        } catch DatabaseError.openFailed(let message) where shouldRetryOpenFileFailure(message) && !isConfiguring {
            try reopenCurrentConnection()
            return try operation()
        }
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

enum DatabaseError: Error, LocalizedError {
    case notOpen
    case openFailed(message: String)
    case executionFailed(message: String)

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    private func humanReadable(_ rawMessage: String) -> String {
        // SQLite/sandbox üzerinden gelen ham mesajları kullanıcıya dostça çevir.
        // Tipik durumlar: security-scoped klasörde sibling journal/wal dosyası
        // yaratılamadığında "unable to open database file" gelir.
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
            try configureJournalMode()
            try runMigrations()

            // DB path kullanıcı dizini içerebileceği için privacy: .private.
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

    func execute(_ sql: String, bind: ((SQLiteStatement) -> Void)? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        try withReconnectRetry {
            guard let db else {
                throw DatabaseError.notOpen
            }

            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.executionFailed(message: lastErrorMessage)
            }

            defer {
                sqlite3_finalize(statement)
            }

            if let statement {
                bind?(SQLiteStatement(statement: statement))
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(message: lastErrorMessage)
            }
        }
    }

    func query<T>(_ sql: String, map: (SQLiteStatement) throws -> T) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }

        return try withReconnectRetry {
            guard let db else {
                throw DatabaseError.notOpen
            }

            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.executionFailed(message: lastErrorMessage)
            }

            defer {
                sqlite3_finalize(statement)
            }

            var result: [T] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                if let statement {
                    result.append(try map(SQLiteStatement(statement: statement)))
                }
            }

            return result
        }
    }

    func query<T>(
        _ sql: String,
        map: (SQLiteStatement) throws -> T,
        bind: (SQLiteStatement) throws -> Void
    ) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }

        return try withReconnectRetry {
            guard let db else {
                throw DatabaseError.notOpen
            }

            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.executionFailed(message: lastErrorMessage)
            }

            guard let statement else {
                throw DatabaseError.executionFailed(message: "Statement could not be created.")
            }

            defer {
                sqlite3_finalize(statement)
            }

            let wrappedStatement = SQLiteStatement(statement: statement)

            try bind(wrappedStatement)

            var rows: [T] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let item = try map(wrappedStatement)
                rows.append(item)
            }

            return rows
        }
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

    func int(at index: Int32) -> Int {
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
    /// Tek otoriteli kaynak `AppDateFormatters.sqliteTimestamp`; mevcut 30+
    /// call site'ı kırmamak için bu alias korunuyor. Yeni kodda doğrudan
    /// `AppDateFormatters` üzerinden referans verilmeli.
    static var proWorkSQLite: DateFormatter { AppDateFormatters.sqliteTimestamp }
}
