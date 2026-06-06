//  UserRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

enum UserRepositoryError: Error, LocalizedError {
    case cannotDeleteDefaultOwner

    var errorDescription: String? {
        switch self {
        case .cannotDeleteDefaultOwner:
            return "The default owner user is the audit-trail anchor and cannot be deleted."
        }
    }
}

final class UserRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(includingDeleted: Bool = false) throws -> [User] {
        let whereClause = includingDeleted ? "" : "WHERE deletedAt IS NULL"
        let sql = """
        SELECT
            id, email, fullName, avatarColor, isActive,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        FROM users
        \(whereClause)
        ORDER BY fullName COLLATE NOCASE ASC;
        """

        return try database.query(sql) { statement in
            try Self.makeUser(from: statement)
        }
    }

    func fetch(id: String) throws -> User? {
        let sql = """
        SELECT
            id, email, fullName, avatarColor, isActive,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        FROM users
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { try Self.makeUser(from: $0) },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    /// Returns the default owner user.
    func fetchDefaultOwner() throws -> User? {
        try fetch(id: BuiltInUserId.defaultOwner)
    }

    func insert(_ user: User) throws {
        let sql = """
        INSERT INTO users (
            id, email, fullName, avatarColor, isActive,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql) { statement in
            statement.bindText(user.id, at: 1)
            statement.bindText(user.email, at: 2)
            statement.bindText(user.fullName, at: 3)
            statement.bindText(user.avatarColor, at: 4)
            statement.bindInt(user.isActive ? 1 : 0, at: 5)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: user.createdAt), at: 6)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: user.updatedAt), at: 7)
            statement.bindText(user.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 8)
            statement.bindInt(user.rowVersion, at: 9)
            statement.bindText(user.syncStatus.rawValue, at: 10)
            statement.bindText(user.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 11)
            statement.bindText(user.originDeviceId, at: 12)
        }
    }

    func update(_ user: User) throws {
        let sql = """
        UPDATE users
        SET
            email = ?, fullName = ?, avatarColor = ?, isActive = ?,
            updatedAt = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(user.email, at: 1)
            statement.bindText(user.fullName, at: 2)
            statement.bindText(user.avatarColor, at: 3)
            statement.bindInt(user.isActive ? 1 : 0, at: 4)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 5)
            statement.bindText(user.id, at: 6)
        }
    }

    /// Soft-deleting `BuiltInUserId.defaultOwner` breaks audit-trail
    /// references on every legacy row that points at it via
    /// `createdByUserId` / `updatedByUserId`. Refuse the call so a
    /// misclick in the UI can't orphan history.
    func softDelete(id: String) throws {
        guard id != BuiltInUserId.defaultOwner else {
            throw UserRepositoryError.cannotDeleteDefaultOwner
        }
        let sql = """
        UPDATE users
        SET
            deletedAt = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            let now = DateFormatter.proWorkSQLite.string(from: Date())
            statement.bindText(now, at: 1)
            statement.bindText(now, at: 2)
            statement.bindText(id, at: 3)
        }
    }

    /// `users` table omits createdByUserId/updatedByUserId so it doesn't
    /// match the full RecordMetadata shape; the discipline
    /// (throw on present-but-unparseable timestamps, unknown sync state)
    /// is applied inline instead.
    private static func makeUser(from statement: SQLiteStatement) throws -> User {
        guard let createdAtRaw = statement.text(at: 5),
              let createdAt = SQLitePersistedDate.parse(createdAtRaw) else {
            throw DatabaseError.executionFailed(message: "users.createdAt missing or unparseable; row is corrupt.")
        }
        guard let updatedAtRaw = statement.text(at: 6),
              let updatedAt = SQLitePersistedDate.parse(updatedAtRaw) else {
            throw DatabaseError.executionFailed(message: "users.updatedAt missing or unparseable; row is corrupt.")
        }
        let deletedAt: Date?
        if let raw = statement.text(at: 7), !raw.isEmpty {
            guard let parsed = SQLitePersistedDate.parse(raw) else {
                throw DatabaseError.executionFailed(message: "users.deletedAt present but unparseable; row is corrupt.")
            }
            deletedAt = parsed
        } else {
            deletedAt = nil
        }
        let syncStatusRaw = statement.text(at: 9) ?? ""
        guard let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
            throw DatabaseError.executionFailed(message: "users.syncStatus '\(syncStatusRaw)' unknown; schema drift or row corruption.")
        }
        let lastSyncedAt: Date?
        if let raw = statement.text(at: 10), !raw.isEmpty {
            guard let parsed = SQLitePersistedDate.parse(raw) else {
                throw DatabaseError.executionFailed(message: "users.lastSyncedAt present but unparseable; row is corrupt.")
            }
            lastSyncedAt = parsed
        } else {
            lastSyncedAt = nil
        }

        return User(
            id: statement.text(at: 0) ?? UUID().uuidString,
            email: statement.text(at: 1),
            fullName: statement.text(at: 2) ?? "",
            avatarColor: statement.text(at: 3),
            isActive: statement.int(at: 4) == 1,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowVersion: statement.int(at: 8),
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt,
            originDeviceId: statement.text(at: 11)
        )
    }
}
