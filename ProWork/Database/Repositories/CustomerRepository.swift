//
//  CustomerRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class CustomerRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Read

    func fetchAll() throws -> [Customer] {
        let sql = """
        SELECT
            id, name, code, contactPerson, address, isActive,
            defaultPriceListId, defaultServiceType, defaultMinBillingMinutes,
            vatRateId, notes,
            \(RecordMetadataSQL.columns)
        FROM customers
        WHERE deletedAt IS NULL
        ORDER BY name COLLATE NOCASE ASC;
        """

        return try database.query(sql) { statement in
            CustomerRepository.makeCustomer(from: statement)
        }
    }

    func fetch(id: String) throws -> Customer? {
        let sql = """
        SELECT
            id, name, code, contactPerson, address, isActive,
            defaultPriceListId, defaultServiceType, defaultMinBillingMinutes,
            vatRateId, notes,
            \(RecordMetadataSQL.columns)
        FROM customers
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in CustomerRepository.makeCustomer(from: statement) },
            bind: { statement in statement.bindText(id, at: 1) }
        ).first
    }

    // MARK: - Write

    func insert(_ customer: Customer) throws {
        let sql = """
        INSERT INTO customers (
            id, name, code, contactPerson, address, isActive,
            defaultPriceListId, defaultServiceType, defaultMinBillingMinutes,
            vatRateId, notes,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(customer.id, at: 1)
            statement.bindText(customer.name, at: 2)
            statement.bindText(customer.code, at: 3)
            statement.bindText(customer.contactPerson, at: 4)
            statement.bindText(customer.address, at: 5)
            statement.bindInt(customer.isActive ? 1 : 0, at: 6)
            statement.bindText(customer.defaultPriceListId, at: 7)
            statement.bindText(customer.defaultServiceType, at: 8)
            statement.bindInt(customer.defaultMinBillingMinutes, at: 9)
            statement.bindText(customer.vatRateId, at: 10)
            statement.bindText(customer.notes, at: 11)
            statement.bindMetadata(customer.meta, startingAt: 12)
        }
    }

    func update(_ customer: Customer) throws {
        let sql = """
        UPDATE customers
        SET
            name = ?, code = ?, contactPerson = ?, address = ?, isActive = ?,
            defaultPriceListId = ?, defaultServiceType = ?, defaultMinBillingMinutes = ?,
            vatRateId = ?, notes = ?,
            updatedByUserId = ?,
            updatedAt = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(customer.name, at: 1)
            statement.bindText(customer.code, at: 2)
            statement.bindText(customer.contactPerson, at: 3)
            statement.bindText(customer.address, at: 4)
            statement.bindInt(customer.isActive ? 1 : 0, at: 5)
            statement.bindText(customer.defaultPriceListId, at: 6)
            statement.bindText(customer.defaultServiceType, at: 7)
            statement.bindInt(customer.defaultMinBillingMinutes, at: 8)
            statement.bindText(customer.vatRateId, at: 9)
            statement.bindText(customer.notes, at: 10)
            statement.bindText(customer.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 11)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 12)
            statement.bindText(customer.id, at: 13)
        }
    }

    func delete(id: String) throws {
        let sql = """
        DELETE FROM customers
        WHERE id = ?;
        """

        try database.execute(sql) { statement in
            statement.bindText(id, at: 1)
        }
    }

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE customers
        SET
            deletedAt = ?,
            updatedAt = ?,
            updatedByUserId = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            let now = DateFormatter.proWorkSQLite.string(from: Date())
            statement.bindText(now, at: 1)
            statement.bindText(now, at: 2)
            statement.bindText(userId, at: 3)
            statement.bindText(id, at: 4)
        }
    }

    // MARK: - Mapping

    private static func makeCustomer(from statement: SQLiteStatement) -> Customer {
        Customer(
            id: statement.text(at: 0) ?? UUID().uuidString,
            name: statement.text(at: 1) ?? "",
            code: statement.text(at: 2),
            contactPerson: statement.text(at: 3),
            address: statement.text(at: 4),
            isActive: statement.int(at: 5) == 1,
            defaultPriceListId: statement.text(at: 6),
            defaultServiceType: statement.text(at: 7) ?? "remote",
            defaultMinBillingMinutes: statement.int(at: 8),
            vatRateId: statement.text(at: 9),
            notes: statement.text(at: 10),
            meta: statement.readMetadata(startingAt: 11)
        )
    }
}
