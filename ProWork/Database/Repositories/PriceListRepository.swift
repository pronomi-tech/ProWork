//
//  PriceListRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

enum PriceListRepositoryError: LocalizedError {
    case inUseByCustomer(String)

    var errorDescription: String? {
        switch self {
        case .inUseByCustomer(let customerName):
            return String(
                format: ProWorkLocalizer.shared.string(
                    "priceLists.error.inUseByCustomer",
                    defaultValue: "\"%@\" müşterisinde seçili olan fiyat listesi silinemez."
                ),
                customerName
            )
        }
    }
}

final class PriceListRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(organizationId: String) throws -> [PriceList] {
        let sql = """
        SELECT
            id, ownerType, ownerId, name, currency,
            isActive, isDefault, validFrom, validTo, notes,
            \(RecordMetadataSQL.columns)
        FROM price_lists
        WHERE organizationId = ? AND deletedAt IS NULL
        ORDER BY ownerType, isDefault DESC, name COLLATE NOCASE ASC;
        """

        return try database.query(
            sql,
            map: { Self.makeList(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    func fetch(id: String) throws -> PriceList? {
        let sql = """
        SELECT
            id, ownerType, ownerId, name, currency,
            isActive, isDefault, validFrom, validTo, notes,
            \(RecordMetadataSQL.columns)
        FROM price_lists
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { Self.makeList(from: $0) },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    func fetchOwned(
        organizationId: String,
        ownerType: PriceListOwnerType,
        ownerId: String?
    ) throws -> [PriceList] {
        let sql: String
        let binds: (SQLiteStatement) -> Void

        if let ownerId {
            sql = """
            SELECT
                id, ownerType, ownerId, name, currency,
                isActive, isDefault, validFrom, validTo, notes,
                \(RecordMetadataSQL.columns)
            FROM price_lists
            WHERE organizationId = ? AND ownerType = ? AND ownerId = ? AND deletedAt IS NULL
            ORDER BY isDefault DESC, name COLLATE NOCASE ASC;
            """
            binds = { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(ownerType.rawValue, at: 2)
                stmt.bindText(ownerId, at: 3)
            }
        } else {
            sql = """
            SELECT
                id, ownerType, ownerId, name, currency,
                isActive, isDefault, validFrom, validTo, notes,
                \(RecordMetadataSQL.columns)
            FROM price_lists
            WHERE organizationId = ? AND ownerType = ? AND ownerId IS NULL AND deletedAt IS NULL
            ORDER BY isDefault DESC, name COLLATE NOCASE ASC;
            """
            binds = { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(ownerType.rawValue, at: 2)
            }
        }

        return try database.query(sql, map: { Self.makeList(from: $0) }, bind: binds)
    }

    func fetchDefault(
        organizationId: String,
        ownerType: PriceListOwnerType,
        ownerId: String?
    ) throws -> PriceList? {
        try fetchOwned(
            organizationId: organizationId,
            ownerType: ownerType,
            ownerId: ownerId
        )
        .first(where: \.isDefault)
    }

    func insert(_ list: PriceList) throws {
        if list.isDefault {
            try clearDefaultFlag(
                organizationId: list.organizationId,
                ownerType: list.ownerType,
                ownerId: list.ownerId,
                excluding: nil
            )
        }

        let sql = """
        INSERT INTO price_lists (
            id, organizationId, ownerType, ownerId, name, currency,
            isActive, isDefault, validFrom, validTo, notes,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql) { stmt in
            stmt.bindText(list.id, at: 1)
            stmt.bindText(list.organizationId, at: 2)
            stmt.bindText(list.ownerType.rawValue, at: 3)
            stmt.bindText(list.ownerId, at: 4)
            stmt.bindText(list.name, at: 5)
            stmt.bindText(list.currency, at: 6)
            stmt.bindInt(list.isActive ? 1 : 0, at: 7)
            stmt.bindInt(list.isDefault ? 1 : 0, at: 8)
            stmt.bindText(list.validFrom, at: 9)
            stmt.bindText(list.validTo, at: 10)
            stmt.bindText(list.notes, at: 11)
            stmt.bindText(list.createdByUserId, at: 12)
            stmt.bindText(list.updatedByUserId, at: 13)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: list.createdAt), at: 14)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: list.updatedAt), at: 15)
            stmt.bindText(list.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 16)
            stmt.bindInt(list.rowVersion, at: 17)
            stmt.bindText(list.syncStatus.rawValue, at: 18)
            stmt.bindText(list.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 19)
            stmt.bindText(list.originDeviceId, at: 20)
        }
    }

    func update(_ list: PriceList) throws {
        if list.isDefault {
            try clearDefaultFlag(
                organizationId: list.organizationId,
                ownerType: list.ownerType,
                ownerId: list.ownerId,
                excluding: list.id
            )
        }

        let sql = """
        UPDATE price_lists
        SET ownerType = ?, ownerId = ?, name = ?, currency = ?,
            isActive = ?, isDefault = ?, validFrom = ?, validTo = ?, notes = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(list.ownerType.rawValue, at: 1)
            stmt.bindText(list.ownerId, at: 2)
            stmt.bindText(list.name, at: 3)
            stmt.bindText(list.currency, at: 4)
            stmt.bindInt(list.isActive ? 1 : 0, at: 5)
            stmt.bindInt(list.isDefault ? 1 : 0, at: 6)
            stmt.bindText(list.validFrom, at: 7)
            stmt.bindText(list.validTo, at: 8)
            stmt.bindText(list.notes, at: 9)
            stmt.bindText(list.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 10)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 11)
            stmt.bindText(list.id, at: 12)
        }
    }

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        if let customerName = try customerNameUsingPriceList(id: id) {
            throw PriceListRepositoryError.inUseByCustomer(customerName)
        }

        let sql = """
        UPDATE price_lists
        SET deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            let now = DateFormatter.proWorkSQLite.string(from: Date())
            stmt.bindText(now, at: 1)
            stmt.bindText(now, at: 2)
            stmt.bindText(userId, at: 3)
            stmt.bindText(id, at: 4)
        }
    }

    private func clearDefaultFlag(
        organizationId: String,
        ownerType: PriceListOwnerType,
        ownerId: String?,
        excluding listId: String?
    ) throws {
        let sql: String

        if ownerId != nil {
            sql = """
            UPDATE price_lists
            SET isDefault = 0
            WHERE organizationId = ? AND ownerType = ? AND ownerId = ? AND deletedAt IS NULL
                AND (? IS NULL OR id != ?);
            """
        } else {
            sql = """
            UPDATE price_lists
            SET isDefault = 0
            WHERE organizationId = ? AND ownerType = ? AND ownerId IS NULL AND deletedAt IS NULL
                AND (? IS NULL OR id != ?);
            """
        }

        try database.execute(sql) { stmt in
            stmt.bindText(organizationId, at: 1)
            stmt.bindText(ownerType.rawValue, at: 2)
            if let ownerId {
                stmt.bindText(ownerId, at: 3)
                stmt.bindText(listId, at: 4)
                stmt.bindText(listId, at: 5)
            } else {
                stmt.bindText(listId, at: 3)
                stmt.bindText(listId, at: 4)
            }
        }
    }

    private func customerNameUsingPriceList(id: String) throws -> String? {
        let sql = """
        SELECT name
        FROM customers
        WHERE defaultPriceListId = ? AND deletedAt IS NULL
        ORDER BY name COLLATE NOCASE ASC
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { $0.text(at: 0) ?? "" },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    private static func makeList(from statement: SQLiteStatement) -> PriceList {
        PriceList(
            id: statement.text(at: 0) ?? UUID().uuidString,
            ownerType: PriceListOwnerType(rawValue: statement.text(at: 1) ?? "global") ?? .global,
            ownerId: statement.text(at: 2),
            name: statement.text(at: 3) ?? "",
            currency: statement.text(at: 4) ?? "TRY",
            isActive: statement.int(at: 5) == 1,
            isDefault: statement.int(at: 6) == 1,
            validFrom: statement.text(at: 7),
            validTo: statement.text(at: 8),
            notes: statement.text(at: 9),
            meta: statement.readMetadata(startingAt: 10)
        )
    }
}
