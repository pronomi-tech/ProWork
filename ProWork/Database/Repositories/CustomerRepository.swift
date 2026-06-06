//  CustomerRepository.swift
//  ProWork
//  Created by Pronomi.

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
            try CustomerRepository.makeCustomer(from: statement)
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
            map: { statement in try CustomerRepository.makeCustomer(from: statement) },
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
        NotificationCenter.default.post(name: .proWorkCustomersDidChange, object: nil)
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
        NotificationCenter.default.post(name: .proWorkCustomersDidChange, object: nil)
    }

    /// Hard delete. Production code should never call this — soft-delete
    /// (with audit trail + sync semantics) is the only standard. Kept
    /// public for integration tests that need to drop fixtures; the
    /// underscore prefix is a stronger marker than `internal` because
    /// Swift module access doesn't help when tests sit in the same
    /// scheme. New call sites should fail code review.
    func _hardDelete(id: String) throws {
        let sql = """
        DELETE FROM customers
        WHERE id = ?;
        """

        try database.execute(sql) { statement in
            statement.bindText(id, at: 1)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        // delegate to the central helper so a schema-wide
        // rowVersion / timestamp tweak is a one-line edit.
        try database.softDelete(table: "customers", id: id, by: userId)
        NotificationCenter.default.post(name: .proWorkCustomersDidChange, object: nil)
    }

    // MARK: - Mapping

    /// Broadcast posted after any customer mutation (insert/update/
    /// softDelete). Because DefinitionsView's ZStack opacity pattern only
    /// fires ProjectsView's `.onAppear` on the first mount (not on tab
    /// selection), ProjectsViewModel observes this signal to keep the
    /// customer list fresh. The same pattern
    /// `proWorkExchangeRatesDidChange` ile CurrencyConverter cache'inde
    /// is used.
    private static func makeCustomer(from statement: SQLiteStatement) throws -> Customer {
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
            meta: try statement.readMetadata(startingAt: 11)
        )
    }
}

extension Notification.Name {
    /// Posted after CustomerRepository.insert / update / softDelete.
    /// Cross-feature view-models (e.g. ProjectsViewModel) observe this signal
    /// observe ederek cache'lerini yeniler — DefinitionsView'in ZStack
    /// because the opacity navigation doesn't re-fire `onAppear` after
    /// the first mount, which was causing a stale-list issue.
    static let proWorkCustomersDidChange = Notification.Name("ProWorkCustomersDidChange")
}
