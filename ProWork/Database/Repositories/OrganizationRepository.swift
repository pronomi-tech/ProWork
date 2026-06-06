//  OrganizationRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

final class OrganizationRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll() throws -> [Organization] {
        let sql = """
        SELECT
            id, name, slug, masterCurrency, billingWindowMode, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        FROM organizations
        WHERE deletedAt IS NULL
        ORDER BY name COLLATE NOCASE ASC;
        """

        return try database.query(sql) { try Self.makeOrganization(from: $0) }
    }

    func fetch(id: String) throws -> Organization? {
        let sql = """
        SELECT
            id, name, slug, masterCurrency, billingWindowMode, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        FROM organizations
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { try Self.makeOrganization(from: $0) },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    func fetchDefault() throws -> Organization? {
        try fetch(id: BuiltInOrganizationId.default)
    }

    func insert(_ organization: Organization) throws {
        let sql = """
        INSERT INTO organizations (
            id, name, slug, masterCurrency, billingWindowMode, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql) { statement in
            statement.bindText(organization.id, at: 1)
            statement.bindText(organization.name, at: 2)
            statement.bindText(organization.slug, at: 3)
            statement.bindText(organization.masterCurrency, at: 4)
            statement.bindText(organization.billingWindowMode.rawValue, at: 5)
            statement.bindInt(organization.isActive ? 1 : 0, at: 6)
            statement.bindText(organization.createdByUserId, at: 7)
            statement.bindText(organization.updatedByUserId, at: 8)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: organization.createdAt), at: 9)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: organization.updatedAt), at: 10)
            statement.bindText(organization.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 11)
            statement.bindInt(organization.rowVersion, at: 12)
            statement.bindText(organization.syncStatus.rawValue, at: 13)
            statement.bindText(organization.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 14)
            statement.bindText(organization.originDeviceId, at: 15)
        }
    }

    func update(_ organization: Organization) throws {
        let sql = """
        UPDATE organizations
        SET
            name = ?, slug = ?, masterCurrency = ?,
            billingWindowMode = ?, isActive = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(organization.name, at: 1)
            statement.bindText(organization.slug, at: 2)
            statement.bindText(organization.masterCurrency, at: 3)
            statement.bindText(organization.billingWindowMode.rawValue, at: 4)
            statement.bindInt(organization.isActive ? 1 : 0, at: 5)
            statement.bindText(organization.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 6)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 7)
            statement.bindText(organization.id, at: 8)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        // Delegate to the central helper.
        try database.softDelete(table: "organizations", id: id, by: userId)
    }

    /// Centralised metadata reader picks up throw-on-corruption
    /// discipline (organizationId NOT NULL, syncStatus must parse,
    /// dates may not be present-but-unparseable). Organizations table
    /// is the org root, so no organizationId column to read.
    private static func makeOrganization(from statement: SQLiteStatement) throws -> Organization {
        let meta = try statement.readMetadataWithoutOrgId(
            organizationId: "",
            startingAt: 6
        )
        return Organization(
            id: statement.text(at: 0) ?? UUID().uuidString,
            name: statement.text(at: 1) ?? "",
            slug: statement.text(at: 2),
            masterCurrency: statement.text(at: 3) ?? "TRY",
            billingWindowMode: BillingWindowMode(rawValue: statement.text(at: 4) ?? "") ?? .timeline,
            isActive: statement.int(at: 5) == 1,
            createdByUserId: meta.createdByUserId,
            updatedByUserId: meta.updatedByUserId,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            deletedAt: meta.deletedAt,
            rowVersion: meta.rowVersion,
            syncStatus: meta.syncStatus,
            lastSyncedAt: meta.lastSyncedAt,
            originDeviceId: meta.originDeviceId
        )
    }
}
