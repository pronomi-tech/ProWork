//
//  BillingRuleRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class BillingRuleRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchGlobal(organizationId: String) throws -> BillingRule? {
        let sql = """
        SELECT
            id, scope, customerId, weekdayHours, weekendDays, timezone, isActive,
            \(RecordMetadataSQL.columns)
        FROM billing_rules
        WHERE organizationId = ? AND scope = 'global' AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { Self.makeRule(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        ).first
    }

    func fetchForCustomer(organizationId: String, customerId: String) throws -> BillingRule? {
        let sql = """
        SELECT
            id, scope, customerId, weekdayHours, weekendDays, timezone, isActive,
            \(RecordMetadataSQL.columns)
        FROM billing_rules
        WHERE organizationId = ? AND scope = 'customer' AND customerId = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { Self.makeRule(from: $0) },
            bind: { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(customerId, at: 2)
            }
        ).first
    }

    /// Müşteri için kural varsa onu, yoksa global kuralı döner. Hiçbiri yoksa nil.
    func resolve(organizationId: String, customerId: String?) throws -> BillingRule? {
        if let customerId, let rule = try fetchForCustomer(organizationId: organizationId, customerId: customerId) {
            return rule
        }
        return try fetchGlobal(organizationId: organizationId)
    }

    func upsert(_ rule: BillingRule) throws {
        let weekdayHoursJson = try Self.encodeWeekdayHours(rule.weekdayHours)
        let weekendDaysJson = try Self.encodeWeekendDays(rule.weekendDays)

        let sql = """
        INSERT INTO billing_rules (
            id, organizationId, scope, customerId,
            weekdayHours, weekendDays, timezone, isActive,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            organizationId = excluded.organizationId,
            scope = excluded.scope,
            customerId = excluded.customerId,
            weekdayHours = excluded.weekdayHours,
            weekendDays = excluded.weekendDays,
            timezone = excluded.timezone,
            isActive = excluded.isActive,
            updatedByUserId = excluded.updatedByUserId,
            updatedAt = excluded.updatedAt,
            rowVersion = billing_rules.rowVersion + 1,
            syncStatus = 'local',
            deletedAt = NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(rule.id, at: 1)
            stmt.bindText(rule.organizationId, at: 2)
            stmt.bindText(rule.scope.rawValue, at: 3)
            stmt.bindText(rule.customerId, at: 4)
            stmt.bindText(weekdayHoursJson, at: 5)
            stmt.bindText(weekendDaysJson, at: 6)
            stmt.bindText(rule.timezone, at: 7)
            stmt.bindInt(rule.isActive ? 1 : 0, at: 8)
            stmt.bindText(rule.createdByUserId, at: 9)
            stmt.bindText(rule.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 10)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: rule.createdAt), at: 11)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 12)
            stmt.bindText(rule.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 13)
            stmt.bindInt(rule.rowVersion, at: 14)
            stmt.bindText(rule.syncStatus.rawValue, at: 15)
            stmt.bindText(rule.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 16)
            stmt.bindText(rule.originDeviceId, at: 17)
        }
    }

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE billing_rules
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

    // MARK: - JSON helpers

    private static func encodeWeekdayHours(_ hours: [Weekday: DailyWorkHours]) throws -> String {
        let stringKeyed = Dictionary(
            uniqueKeysWithValues: hours.map { (String($0.key.rawValue), $0.value) }
        )
        let data = try JSONEncoder().encode(stringKeyed)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decodeWeekdayHours(_ json: String) -> [Weekday: DailyWorkHours] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: DailyWorkHours].self, from: data)
        else {
            return [:]
        }

        var result: [Weekday: DailyWorkHours] = [:]
        for (key, value) in raw {
            if let intKey = Int(key), let weekday = Weekday(rawValue: intKey) {
                result[weekday] = value
            }
        }
        return result
    }

    private static func encodeWeekendDays(_ days: Set<Weekday>) throws -> String {
        let raws = days.map { $0.rawValue }.sorted()
        let data = try JSONEncoder().encode(raws)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeWeekendDays(_ json: String) -> Set<Weekday> {
        guard let data = json.data(using: .utf8),
              let ints = try? JSONDecoder().decode([Int].self, from: data)
        else {
            return [.saturday, .sunday]
        }
        return Set(ints.compactMap(Weekday.init(rawValue:)))
    }

    // MARK: - Mapping

    private static func makeRule(from statement: SQLiteStatement) -> BillingRule {
        let weekdayHoursJson = statement.text(at: 3) ?? "{}"
        let weekendDaysJson = statement.text(at: 4) ?? "[]"

        return BillingRule(
            id: statement.text(at: 0) ?? UUID().uuidString,
            scope: BillingRuleScope(rawValue: statement.text(at: 1) ?? "global") ?? .global,
            customerId: statement.text(at: 2),
            weekdayHours: decodeWeekdayHours(weekdayHoursJson),
            weekendDays: decodeWeekendDays(weekendDaysJson),
            timezone: statement.text(at: 5) ?? "Europe/Istanbul",
            isActive: statement.int(at: 6) == 1,
            organizationId: BuiltInOrganizationId.default, // override edilecek
            createdAt: Date(),
            updatedAt: Date()
        ).withMetadata(statement.readMetadata(startingAt: 7))
    }
}

private extension BillingRule {
    func withMetadata(_ meta: RecordMetadata) -> BillingRule {
        var copy = self
        copy.organizationId = meta.organizationId
        copy.createdByUserId = meta.createdByUserId
        copy.updatedByUserId = meta.updatedByUserId
        copy.createdAt = meta.createdAt
        copy.updatedAt = meta.updatedAt
        copy.deletedAt = meta.deletedAt
        copy.rowVersion = meta.rowVersion
        copy.syncStatus = meta.syncStatus
        copy.lastSyncedAt = meta.lastSyncedAt
        copy.originDeviceId = meta.originDeviceId
        return copy
    }
}
