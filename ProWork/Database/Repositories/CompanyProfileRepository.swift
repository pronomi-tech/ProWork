//
//  CompanyProfileRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class CompanyProfileRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetch(organizationId: String) throws -> CompanyProfile? {
        let sql = """
        SELECT
            id, legalName, tradeName, taxNumber, taxOffice,
            address, phone, email, website,
            logoData, paymentTermsDays,
            \(RecordMetadataSQL.columns)
        FROM company_profile
        WHERE organizationId = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { Self.makeProfile(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        ).first
    }

    func upsert(_ profile: CompanyProfile) throws {
        let sql = """
        INSERT INTO company_profile (
            id, organizationId, legalName, tradeName, taxNumber, taxOffice,
            address, phone, email, website,
            logoData, paymentTermsDays,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(organizationId) DO UPDATE SET
            legalName = excluded.legalName,
            tradeName = excluded.tradeName,
            taxNumber = excluded.taxNumber,
            taxOffice = excluded.taxOffice,
            address = excluded.address,
            phone = excluded.phone,
            email = excluded.email,
            website = excluded.website,
            logoData = excluded.logoData,
            paymentTermsDays = excluded.paymentTermsDays,
            updatedByUserId = excluded.updatedByUserId,
            updatedAt = excluded.updatedAt,
            rowVersion = company_profile.rowVersion + 1,
            syncStatus = 'local';
        """

        try database.execute(sql) { stmt in
            stmt.bindText(profile.id, at: 1)
            stmt.bindText(profile.organizationId, at: 2)
            stmt.bindText(profile.legalName, at: 3)
            stmt.bindText(profile.tradeName, at: 4)
            stmt.bindText(profile.taxNumber, at: 5)
            stmt.bindText(profile.taxOffice, at: 6)
            stmt.bindText(profile.address, at: 7)
            stmt.bindText(profile.phone, at: 8)
            stmt.bindText(profile.email, at: 9)
            stmt.bindText(profile.website, at: 10)
            stmt.bindBlob(profile.logoData, at: 11)
            stmt.bindInt(profile.paymentTermsDays, at: 12)
            stmt.bindText(profile.createdByUserId, at: 13)
            stmt.bindText(profile.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 14)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: profile.createdAt), at: 15)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 16)
            stmt.bindText(profile.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 17)
            stmt.bindInt(profile.rowVersion, at: 18)
            stmt.bindText(profile.syncStatus.rawValue, at: 19)
            stmt.bindText(profile.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 20)
            stmt.bindText(profile.originDeviceId, at: 21)
        }
    }

    private static func makeProfile(from statement: SQLiteStatement) -> CompanyProfile {
        let meta = statement.readMetadata(startingAt: 11)
        return CompanyProfile(
            id: statement.text(at: 0) ?? UUID().uuidString,
            legalName: statement.text(at: 1) ?? "",
            tradeName: statement.text(at: 2),
            taxNumber: statement.text(at: 3),
            taxOffice: statement.text(at: 4),
            address: statement.text(at: 5),
            phone: statement.text(at: 6),
            email: statement.text(at: 7),
            website: statement.text(at: 8),
            logoData: statement.optionalBlob(at: 9),
            paymentTermsDays: statement.int(at: 10),
            organizationId: meta.organizationId,
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
