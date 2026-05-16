//
//  ProjectRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class ProjectRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Read

    /// UI listeleme için müşteri adıyla join edilmiş projeler.
    func fetchAll() throws -> [ProjectListItem] {
        let sql = """
        SELECT
            p.id,
            p.customerId,
            c.name AS customerName,
            p.name,
            p.code,
            p.status,
            p.defaultServiceType,
            p.defaultMinBillingMinutes,
            p.billingWindowMode,
            p.vatRateId,
            p.notes,
            p.createdAt,
            p.updatedAt
        FROM projects p
        INNER JOIN customers c ON c.id = p.customerId AND c.deletedAt IS NULL
        WHERE p.deletedAt IS NULL
        ORDER BY c.name COLLATE NOCASE ASC, p.name COLLATE NOCASE ASC;
        """

        return try database.query(sql) { statement in
            ProjectListItem(
                id: statement.text(at: 0) ?? UUID().uuidString,
                customerId: statement.text(at: 1) ?? "",
                customerName: statement.text(at: 2) ?? "",
                name: statement.text(at: 3) ?? "",
                code: statement.text(at: 4),
                status: statement.text(at: 5) ?? "active",
                defaultServiceType: statement.text(at: 6),
                defaultMinBillingMinutes: statement.optionalInt(at: 7),
                billingWindowMode: BillingWindowMode(rawValue: statement.text(at: 8) ?? ""),
                vatRateId: statement.text(at: 9),
                notes: statement.text(at: 10),
                createdAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 11) ?? "") ?? Date(),
                updatedAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 12) ?? "") ?? Date()
            )
        }
    }

    /// Birden çok id için toplu fetch (raporlama / faturalandırma için).
    /// `SQLITE_MAX_VARIABLE_NUMBER` limitini aşmamak için 500'lük parçalara bölünür.
    func fetch(ids: [String]) throws -> [Project] {
        guard !ids.isEmpty else { return [] }

        var results: [Project] = []
        results.reserveCapacity(ids.count)

        let chunkSize = 500
        for chunkStart in stride(from: 0, to: ids.count, by: chunkSize) {
            let chunk = Array(ids[chunkStart..<min(chunkStart + chunkSize, ids.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
            SELECT
                id, customerId, name, code, status,
                defaultServiceType, defaultMinBillingMinutes, billingWindowMode,
                vatRateId, notes,
                \(RecordMetadataSQL.columns)
            FROM projects
            WHERE id IN (\(placeholders)) AND deletedAt IS NULL;
            """

            let rows = try database.query(
                sql,
                map: { ProjectRepository.makeProject(from: $0) },
                bind: { statement in
                    for (offset, id) in chunk.enumerated() {
                        statement.bindText(id, at: Int32(offset + 1))
                    }
                }
            )
            results.append(contentsOf: rows)
        }

        return results
    }

    /// Düzenleme için tek proje (tüm metadata ile).
    func fetch(id: String) throws -> Project? {
        let sql = """
        SELECT
            id, customerId, name, code, status,
            defaultServiceType, defaultMinBillingMinutes, billingWindowMode,
            vatRateId, notes,
            \(RecordMetadataSQL.columns)
        FROM projects
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { statement in ProjectRepository.makeProject(from: statement) },
            bind: { statement in statement.bindText(id, at: 1) }
        ).first
    }

    // MARK: - Write

    func insert(_ project: Project) throws {
        let sql = """
        INSERT INTO projects (
            id, customerId, name, code, status,
            defaultServiceType, defaultMinBillingMinutes, billingWindowMode,
            vatRateId, notes,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(project.id, at: 1)
            statement.bindText(project.customerId, at: 2)
            statement.bindText(project.name, at: 3)
            statement.bindText(project.code, at: 4)
            statement.bindText(project.status, at: 5)
            statement.bindText(project.defaultServiceType, at: 6)
            statement.bindOptionalInt(project.defaultMinBillingMinutes, at: 7)
            statement.bindText(project.billingWindowMode?.rawValue, at: 8)
            statement.bindText(project.vatRateId, at: 9)
            statement.bindText(project.notes, at: 10)
            statement.bindMetadata(project.meta, startingAt: 11)
        }
    }

    func update(_ project: Project) throws {
        let sql = """
        UPDATE projects
        SET
            customerId = ?, name = ?, code = ?, status = ?,
            defaultServiceType = ?, defaultMinBillingMinutes = ?,
            billingWindowMode = ?, vatRateId = ?, notes = ?,
            updatedByUserId = ?,
            updatedAt = ?,
            rowVersion = rowVersion + 1,
            syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(project.customerId, at: 1)
            statement.bindText(project.name, at: 2)
            statement.bindText(project.code, at: 3)
            statement.bindText(project.status, at: 4)
            statement.bindText(project.defaultServiceType, at: 5)
            statement.bindOptionalInt(project.defaultMinBillingMinutes, at: 6)
            statement.bindText(project.billingWindowMode?.rawValue, at: 7)
            statement.bindText(project.vatRateId, at: 8)
            statement.bindText(project.notes, at: 9)
            statement.bindText(project.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 10)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 11)
            statement.bindText(project.id, at: 12)
        }
    }

    func delete(id: String) throws {
        let sql = """
        DELETE FROM projects
        WHERE id = ?;
        """

        try database.execute(sql) { statement in
            statement.bindText(id, at: 1)
        }
    }

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE projects
        SET
            deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
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

    private static func makeProject(from statement: SQLiteStatement) -> Project {
        Project(
            id: statement.text(at: 0) ?? UUID().uuidString,
            customerId: statement.text(at: 1) ?? "",
            name: statement.text(at: 2) ?? "",
            code: statement.text(at: 3),
            status: statement.text(at: 4) ?? "active",
            defaultServiceType: statement.text(at: 5),
            defaultMinBillingMinutes: statement.optionalInt(at: 6),
            billingWindowMode: BillingWindowMode(rawValue: statement.text(at: 7) ?? ""),
            vatRateId: statement.text(at: 8),
            notes: statement.text(at: 9),
            meta: statement.readMetadata(startingAt: 10)
        )
    }
}
