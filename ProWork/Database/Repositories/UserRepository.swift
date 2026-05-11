//
//  UserRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

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
            Self.makeUser(from: statement)
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
            map: { Self.makeUser(from: $0) },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    /// Varsayılan sahip kullanıcısını döner.
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

    func softDelete(id: String) throws {
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

    private static func makeUser(from statement: SQLiteStatement) -> User {
        User(
            id: statement.text(at: 0) ?? UUID().uuidString,
            email: statement.text(at: 1),
            fullName: statement.text(at: 2) ?? "",
            avatarColor: statement.text(at: 3),
            isActive: statement.int(at: 4) == 1,
            createdAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 5) ?? "") ?? Date(),
            updatedAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 6) ?? "") ?? Date(),
            deletedAt: statement.text(at: 7).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            rowVersion: statement.int(at: 8),
            syncStatus: SyncStatus(rawValue: statement.text(at: 9) ?? "") ?? .local,
            lastSyncedAt: statement.text(at: 10).flatMap(DateFormatter.proWorkSQLite.date(from:)),
            originDeviceId: statement.text(at: 11)
        )
    }
}
