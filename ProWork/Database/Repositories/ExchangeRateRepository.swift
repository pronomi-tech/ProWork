//
//  ExchangeRateRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class ExchangeRateRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Verilen para birimi çiftine en yakın (≤ targetDate) son kuru döner.
    /// Önce manuel, sonra TCMB; yoksa nil.
    func fetchLatest(
        organizationId: String,
        from: String,
        to: String,
        on date: String,
        sourcePriority: [ExchangeRateSource]? = nil
    ) throws -> ExchangeRate? {
        let sql = """
        SELECT
            id, fromCurrency, toCurrency, rate, forexBuying, forexSelling, banknoteBuying, banknoteSelling,
            rateDate, source, fetchedAt, note,
            \(RecordMetadataSQL.columns)
        FROM exchange_rates
        WHERE organizationId = ? AND fromCurrency = ? AND toCurrency = ?
          AND rateDate <= ? AND deletedAt IS NULL
        ORDER BY rateDate DESC, fetchedAt DESC;
        """

        let rows = try database.query(
            sql,
            map: { Self.makeRate(from: $0) },
            bind: { stmt in
                stmt.bindText(organizationId, at: 1)
                stmt.bindText(from.uppercased(), at: 2)
                stmt.bindText(to.uppercased(), at: 3)
                stmt.bindText(date, at: 4)
            }
        )

        return sortByPriority(rows, sourcePriority: sourcePriority).first
    }

    func fetchAll(organizationId: String) throws -> [ExchangeRate] {
        let sql = """
        SELECT
            id, fromCurrency, toCurrency, rate, forexBuying, forexSelling, banknoteBuying, banknoteSelling,
            rateDate, source, fetchedAt, note,
            \(RecordMetadataSQL.columns)
        FROM exchange_rates
        WHERE organizationId = ? AND deletedAt IS NULL
        ORDER BY rateDate DESC, fromCurrency ASC, fetchedAt DESC;
        """

        return try database.query(
            sql,
            map: { Self.makeRate(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    func upsert(_ rate: ExchangeRate) throws {
        let sql = """
        INSERT INTO exchange_rates (
            id, organizationId, fromCurrency, toCurrency, rate,
            forexBuying, forexSelling, banknoteBuying, banknoteSelling,
            rateDate, source,
            fetchedAt, note,
            createdByUserId, updatedByUserId,
            createdAt, updatedAt, deletedAt, rowVersion,
            syncStatus, lastSyncedAt, originDeviceId
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(organizationId, fromCurrency, toCurrency, rateDate, source) DO UPDATE SET
            rate = excluded.rate,
            forexBuying = excluded.forexBuying,
            forexSelling = excluded.forexSelling,
            banknoteBuying = excluded.banknoteBuying,
            banknoteSelling = excluded.banknoteSelling,
            fetchedAt = excluded.fetchedAt,
            note = excluded.note,
            updatedByUserId = excluded.updatedByUserId,
            updatedAt = excluded.updatedAt,
            rowVersion = exchange_rates.rowVersion + 1,
            syncStatus = 'local',
            deletedAt = NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(rate.id, at: 1)
            stmt.bindText(rate.organizationId, at: 2)
            stmt.bindText(rate.fromCurrency, at: 3)
            stmt.bindText(rate.toCurrency, at: 4)
            stmt.bindText(NSDecimalNumber(decimal: rate.rate).stringValue, at: 5)
            stmt.bindText(rate.forexBuying.map { NSDecimalNumber(decimal: $0).stringValue }, at: 6)
            stmt.bindText(rate.forexSelling.map { NSDecimalNumber(decimal: $0).stringValue }, at: 7)
            stmt.bindText(rate.banknoteBuying.map { NSDecimalNumber(decimal: $0).stringValue }, at: 8)
            stmt.bindText(rate.banknoteSelling.map { NSDecimalNumber(decimal: $0).stringValue }, at: 9)
            stmt.bindText(rate.rateDate, at: 10)
            stmt.bindText(rate.source.rawValue, at: 11)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: rate.fetchedAt), at: 12)
            stmt.bindText(rate.note, at: 13)
            stmt.bindText(rate.createdByUserId, at: 14)
            stmt.bindText(rate.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 15)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: rate.createdAt), at: 16)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 17)
            stmt.bindText(rate.deletedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 18)
            stmt.bindInt(rate.rowVersion, at: 19)
            stmt.bindText(rate.syncStatus.rawValue, at: 20)
            stmt.bindText(rate.lastSyncedAt.map(DateFormatter.proWorkSQLite.string(from:)), at: 21)
            stmt.bindText(rate.originDeviceId, at: 22)
        }
    }

    func softDelete(id: String, by userId: String = BuiltInUserId.defaultOwner) throws {
        let sql = """
        UPDATE exchange_rates
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

    private static func makeRate(from statement: SQLiteStatement) -> ExchangeRate {
        let rateString = statement.text(at: 3) ?? "0"
        let rate = Decimal(string: rateString) ?? 0
        let forexBuying = statement.text(at: 4).flatMap { Decimal(string: $0) }
        let forexSelling = statement.text(at: 5).flatMap { Decimal(string: $0) }
        let banknoteBuying = statement.text(at: 6).flatMap { Decimal(string: $0) }
        let banknoteSelling = statement.text(at: 7).flatMap { Decimal(string: $0) }

        return ExchangeRate(
            id: statement.text(at: 0) ?? UUID().uuidString,
            fromCurrency: statement.text(at: 1) ?? "TRY",
            toCurrency: statement.text(at: 2) ?? "TRY",
            rate: rate,
            forexBuying: forexBuying,
            forexSelling: forexSelling,
            banknoteBuying: banknoteBuying,
            banknoteSelling: banknoteSelling,
            rateDate: statement.text(at: 8) ?? "",
            source: ExchangeRateSource(rawValue: statement.text(at: 9) ?? "manual") ?? .manual,
            fetchedAt: DateFormatter.proWorkSQLite.date(from: statement.text(at: 10) ?? "") ?? Date(),
            note: statement.text(at: 11),
            meta: statement.readMetadata(startingAt: 12)
        )
    }

    private func sortByPriority(
        _ rows: [ExchangeRate],
        sourcePriority: [ExchangeRateSource]?
    ) -> [ExchangeRate] {
        let fallbackPriority: [ExchangeRateSource] = [.manual, .tcmb, .global]
        let effectivePriority = sourcePriority ?? fallbackPriority
        let priorityBySource = Dictionary(
            uniqueKeysWithValues: effectivePriority.enumerated().map { ($1, $0) }
        )

        return rows.sorted { lhs, rhs in
            if lhs.rateDate != rhs.rateDate {
                return lhs.rateDate > rhs.rateDate
            }

            let leftPriority = priorityBySource[lhs.source] ?? Int.max
            let rightPriority = priorityBySource[rhs.source] ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }

            if lhs.fetchedAt != rhs.fetchedAt {
                return lhs.fetchedAt > rhs.fetchedAt
            }

            return lhs.fromCurrency < rhs.fromCurrency
        }
    }
}
