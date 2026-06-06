//  BillingRuleRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3
import os

enum BillingRuleRepositoryError: Error, LocalizedError {
    case ruleJsonCorrupt(field: String, underlying: Error)
    case duplicateRule(scope: String, customerId: String?)

    var errorDescription: String? {
        switch self {
        case .ruleJsonCorrupt(let field, let underlying):
            return "Billing rule '\(field)' JSON is corrupt: \(underlying.localizedDescription)"
        case .duplicateRule(let scope, let customerId):
            let target = customerId.map { "customer \($0)" } ?? "global"
            return "A billing rule already exists for scope=\(scope), \(target)."
        }
    }
}

final class BillingRuleRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// SQLite UNIQUE constraints treat NULLs as distinct, so the
    /// `UNIQUE(organizationId, scope, customerId)` index allows multiple
    /// global rows (`customerId IS NULL`). `LIMIT 1` would then return an
    /// arbitrary one. Restrict the query explicitly to the global flavour
    /// so a duplicate row can't masquerade as the chosen rule.
    func fetchGlobal(organizationId: String) throws -> BillingRule? {
        let sql = """
        SELECT
            id, scope, customerId, weekdayHours, weekendDays, timezone, isActive,
            \(RecordMetadataSQL.columns)
        FROM billing_rules
        WHERE organizationId = ?
          AND scope = 'global'
          AND customerId IS NULL
          AND deletedAt IS NULL
        ORDER BY updatedAt DESC
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { try Self.makeRule(from: $0) },
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
            map: { try Self.makeRule(from: $0) },
            bind: { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(customerId, at: 2)
            }
        ).first
    }

    /// Returns the customer-specific rule if present, otherwise the global rule. nil if neither exists.
    func resolve(organizationId: String, customerId: String?) throws -> BillingRule? {
        if let customerId, let rule = try fetchForCustomer(organizationId: organizationId, customerId: customerId) {
            return rule
        }
        return try fetchGlobal(organizationId: organizationId)
    }

    /// Returns all customer-specific rules in the organization in a single query.
    /// `BillingComputationService` was calling `resolve()` per customer
    /// during period computation (N customers = N queries); the bulk
    /// fetch collapses that load into a single SELECT.
    func fetchAllCustomerScoped(organizationId: String) throws -> [String: BillingRule] {
        let sql = """
        SELECT
            id, scope, customerId, weekdayHours, weekendDays, timezone, isActive,
            \(RecordMetadataSQL.columns)
        FROM billing_rules
        WHERE organizationId = ? AND scope = 'customer' AND deletedAt IS NULL;
        """
        let rules = try database.query(
            sql,
            map: { try Self.makeRule(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
        var byCustomer: [String: BillingRule] = [:]
        for rule in rules {
            if let id = rule.customerId {
                byCustomer[id] = rule
            }
        }
        return byCustomer
    }

    /// Upsert by id. `ON CONFLICT(id)` keeps the existing primary-key
    /// updates working; the wider `UNIQUE(organizationId, scope, customerId)`
    /// tuple constraint surfaces as a clearer `duplicateRule` error so
    /// callers don't get a raw SQLite "constraint failed" string.
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

        do {
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
        } catch DatabaseError.executionFailed(let message)
                where message.localizedCaseInsensitiveContains("UNIQUE")
                    && message.localizedCaseInsensitiveContains("billing_rules") {
            // Tuple constraint hit (`organizationId, scope, customerId`).
            // Surface a domain-specific error so callers can resolve by
            // updating the existing row instead of guessing from a raw
            // "constraint failed" string.
            throw BillingRuleRepositoryError.duplicateRule(
                scope: rule.scope.rawValue,
                customerId: rule.customerId
            )
        }
    }

    func softDelete(id: String, by userId: String) throws {
        // delegate to the central helper.
        try database.softDelete(table: "billing_rules", id: id, by: userId)
    }

    // MARK: - JSON helpers

    /// `JSONEncoder.encode` only emits valid UTF-8, so the
    /// `String(data:encoding:)` conversion can't actually fail. We
    /// `force-unwrap` instead of substituting `"{}"` / `"[]"` to make a
    /// hypothetical regression (e.g. a custom encoder) crash visibly
    /// rather than silently persist the wrong payload.
    private static func encodeWeekdayHours(_ hours: [Weekday: DailyWorkHours]) throws -> String {
        let stringKeyed = Dictionary(
            uniqueKeysWithValues: hours.map { (String($0.key.rawValue), $0.value) }
        )
        let data = try JSONEncoder().encode(stringKeyed)
        guard let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("JSONEncoder produced non-UTF8 output for weekdayHours; invariant broken.")
        }
        return json
    }

    /// JSON corruption used to fall back to an empty dictionary, which
    /// silently routed every working hour through the after-hours
    /// tariff. The corruption is now logged and surfaced via
    /// `BillingRuleRepositoryError.ruleJsonCorrupt` so callers can
    /// refuse to apply a billing rule with a broken schedule rather
    /// than overbilling.
    private static func decodeWeekdayHours(_ json: String, ruleId: String) throws -> [Weekday: DailyWorkHours] {
        guard let data = json.data(using: .utf8) else {
            let error = CodableDecodeError.nonUTF8
            ProWorkLog.database.error(
                "BillingRule weekdayHours non-UTF8 (ruleId=\(ruleId, privacy: .public))."
            )
            throw BillingRuleRepositoryError.ruleJsonCorrupt(field: "weekdayHours", underlying: error)
        }
        let raw: [String: DailyWorkHours]
        do {
            raw = try JSONDecoder().decode([String: DailyWorkHours].self, from: data)
        } catch {
            ProWorkLog.database.error(
                "BillingRule weekdayHours decode failed (ruleId=\(ruleId, privacy: .public)): \(error.localizedDescription, privacy: .public)."
            )
            throw BillingRuleRepositoryError.ruleJsonCorrupt(field: "weekdayHours", underlying: error)
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
        guard let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("JSONEncoder produced non-UTF8 output for weekendDays; invariant broken.")
        }
        return json
    }

    private static func decodeWeekendDays(_ json: String, ruleId: String) throws -> Set<Weekday> {
        guard let data = json.data(using: .utf8) else {
            let error = CodableDecodeError.nonUTF8
            ProWorkLog.database.error(
                "BillingRule weekendDays non-UTF8 (ruleId=\(ruleId, privacy: .public))."
            )
            throw BillingRuleRepositoryError.ruleJsonCorrupt(field: "weekendDays", underlying: error)
        }
        let ints: [Int]
        do {
            ints = try JSONDecoder().decode([Int].self, from: data)
        } catch {
            ProWorkLog.database.error(
                "BillingRule weekendDays decode failed (ruleId=\(ruleId, privacy: .public)): \(error.localizedDescription, privacy: .public)."
            )
            throw BillingRuleRepositoryError.ruleJsonCorrupt(field: "weekendDays", underlying: error)
        }
        return Set(ints.compactMap(Weekday.init(rawValue:)))
    }

    // MARK: - Mapping

    private static func makeRule(from statement: SQLiteStatement) throws -> BillingRule {
        let ruleId = statement.text(at: 0) ?? UUID().uuidString
        let weekdayHoursJson = statement.text(at: 3) ?? "{}"
        let weekendDaysJson = statement.text(at: 4) ?? "[]"

        return BillingRule(
            id: ruleId,
            scope: BillingRuleScope(rawValue: statement.text(at: 1) ?? "global") ?? .global,
            customerId: statement.text(at: 2),
            weekdayHours: try decodeWeekdayHours(weekdayHoursJson, ruleId: ruleId),
            weekendDays: try decodeWeekendDays(weekendDaysJson, ruleId: ruleId),
            timezone: statement.text(at: 5) ?? "Europe/Istanbul",
            isActive: statement.int(at: 6) == 1,
            meta: try statement.readMetadata(startingAt: 7)
        )
    }
}
