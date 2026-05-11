//
//  HolidayRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class HolidayRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(organizationId: String, includingInactive: Bool = false) throws -> [Holiday] {
        let activeFilter = includingInactive ? "" : "AND isActive = 1"
        let sql = """
        SELECT
            id, scope, customerId, date, name, isHalfDay, halfDayCutoff, isActive,
            \(RecordMetadataSQL.columns)
        FROM holidays
        WHERE organizationId = ? AND deletedAt IS NULL \(activeFilter)
        ORDER BY date ASC, name ASC;
        """

        return try database.query(
            sql,
            map: { Self.makeHoliday(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    /// Belirli bir tarihe ait tüm tatilleri (global + müşteri) döner.
    func fetchForDate(organizationId: String, date: String, customerId: String? = nil) throws -> [Holiday] {
        let sql: String
        let binds: (SQLiteStatement) -> Void

        if let customerId {
            sql = """
            SELECT
                id, scope, customerId, date, name, isHalfDay, halfDayCutoff, isActive,
                \(RecordMetadataSQL.columns)
            FROM holidays
            WHERE organizationId = ? AND date = ? AND deletedAt IS NULL AND isActive = 1
              AND (scope = 'global' OR (scope = 'customer' AND customerId = ?))
            ORDER BY scope DESC;
            """
            binds = { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(date, at: 2)
                stmt.bindText(customerId, at: 3)
            }
        } else {
            sql = """
            SELECT
                id, scope, customerId, date, name, isHalfDay, halfDayCutoff, isActive,
                \(RecordMetadataSQL.columns)
            FROM holidays
            WHERE organizationId = ? AND date = ? AND deletedAt IS NULL AND isActive = 1
              AND scope = 'global';
            """
            binds = { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(date, at: 2)
            }
        }

        return try database.query(
            sql,
            map: { Self.makeHoliday(from: $0) },
            bind: binds
        )
    }

    func insert(_ holiday: Holiday) throws {
        let sql = """
        INSERT INTO holidays (
            id, organizationId, scope, customerId,
            date, name, isHalfDay, halfDayCutoff, isActive,
            \(RecordMetadataSQL.columns.replacingOccurrences(of: "organizationId, ", with: ""))
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try database.execute(sql) { stmt in
            stmt.bindText(holiday.id, at: 1)
            stmt.bindText(holiday.organizationId, at: 2)
            stmt.bindText(holiday.scope.rawValue, at: 3)
            stmt.bindText(holiday.customerId, at: 4)
            stmt.bindText(holiday.dateString, at: 5)
            stmt.bindText(holiday.name, at: 6)
            stmt.bindInt(holiday.isHalfDay ? 1 : 0, at: 7)
            stmt.bindText(holiday.halfDayCutoff?.formatted, at: 8)
            stmt.bindInt(holiday.isActive ? 1 : 0, at: 9)
            stmt.bindText(holiday.createdByUserId, at: 10)
            stmt.bindText(holiday.updatedByUserId, at: 11)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: holiday.createdAt), at: 12)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: holiday.updatedAt), at: 13)
            stmt.bindText(holiday.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 14)
            stmt.bindInt(holiday.rowVersion, at: 15)
            stmt.bindText(holiday.syncStatus.rawValue, at: 16)
            stmt.bindText(holiday.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 17)
            stmt.bindText(holiday.originDeviceId, at: 18)
        }
    }

    func update(_ holiday: Holiday) throws {
        let sql = """
        UPDATE holidays
        SET scope = ?, customerId = ?, date = ?, name = ?,
            isHalfDay = ?, halfDayCutoff = ?, isActive = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(holiday.scope.rawValue, at: 1)
            stmt.bindText(holiday.customerId, at: 2)
            stmt.bindText(holiday.dateString, at: 3)
            stmt.bindText(holiday.name, at: 4)
            stmt.bindInt(holiday.isHalfDay ? 1 : 0, at: 5)
            stmt.bindText(holiday.halfDayCutoff?.formatted, at: 6)
            stmt.bindInt(holiday.isActive ? 1 : 0, at: 7)
            stmt.bindText(holiday.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 8)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 9)
            stmt.bindText(holiday.id, at: 10)
        }
    }

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE holidays
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

    private static func makeHoliday(from statement: SQLiteStatement) -> Holiday {
        Holiday(
            id: statement.text(at: 0) ?? UUID().uuidString,
            scope: HolidayScope(rawValue: statement.text(at: 1) ?? "global") ?? .global,
            customerId: statement.text(at: 2),
            dateString: statement.text(at: 3) ?? "",
            name: statement.text(at: 4) ?? "",
            isHalfDay: statement.int(at: 5) == 1,
            halfDayCutoff: statement.text(at: 6).flatMap(TimeOfDay.init(string:)),
            isActive: statement.int(at: 7) == 1,
            meta: statement.readMetadata(startingAt: 8)
        )
    }
}
