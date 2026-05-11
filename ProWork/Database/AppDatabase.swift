//
//  AppDatabase.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class AppDatabase {
    static let shared = AppDatabase()

    private(set) var db: OpaquePointer?
    private(set) var databaseURL: URL?
    private var securityScopedDatabaseURL: URL?
    private var securityScopedContainerURL: URL?
    private var isDatabaseSecurityScopeActive = false
    private var isContainerSecurityScopeActive = false

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
        // Keep journaling in-process so write operations do not depend on
        // creating sibling -journal/-wal/-shm files in user-selected folders.
        _ = try query("PRAGMA journal_mode = MEMORY;") { statement in
            statement.text(at: 0) ?? "unknown"
        }
    }

    func runMigrations() throws {
        try DatabaseMigrator.migrate(self)
    }

    func shouldRetryOpenFileFailure(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("unable to open database file")
    }

    func reopenCurrentConnection() throws {
        guard let currentDatabaseURL = securityScopedDatabaseURL ?? databaseURL else {
            throw DatabaseError.notOpen
        }

        let currentContainerURL = securityScopedContainerURL ?? currentDatabaseURL.deletingLastPathComponent()
        close()
        try configure(at: currentDatabaseURL, containerDirectoryURL: currentContainerURL)
    }

    func withReconnectRetry<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch DatabaseError.executionFailed(let message) where shouldRetryOpenFileFailure(message) {
            try reopenCurrentConnection()
            return try operation()
        } catch DatabaseError.openFailed(let message) where shouldRetryOpenFileFailure(message) {
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

    var errorDescription: String? {
        switch self {
        case .notOpen:
            return "Database is not open."
        case .openFailed(let message):
            return "Database open failed: \(message)"
        case .executionFailed(let message):
            return "Database execution failed: \(message)"
        }
    }
}

extension AppDatabase {
    var isOpen: Bool {
        db != nil
    }

    func configure(at url: URL, containerDirectoryURL: URL? = nil) throws {
        if let databaseURL, databaseURL == url, isOpen {
            return
        }

        close()

        let didAccessDatabaseSecurityScope = url.startAccessingSecurityScopedResource()
        let didAccessContainerSecurityScope = containerDirectoryURL?.startAccessingSecurityScopedResource() ?? false

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
            databaseURL = url
            securityScopedDatabaseURL = url
            securityScopedContainerURL = containerDirectoryURL
            isDatabaseSecurityScopeActive = didAccessDatabaseSecurityScope
            isContainerSecurityScopeActive = didAccessContainerSecurityScope

            try enableForeignKeys()
            try configureTemporaryStorage()
            try configureJournalMode()
            try runMigrations()

            print("✅ ProWork database ready at: \(url.path)")
        } catch {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
            databaseURL = nil
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
        if let db {
            sqlite3_close(db)
            self.db = nil
        }

        databaseURL = nil

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
        try withReconnectRetry {
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
    static let proWorkSQLite: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}
