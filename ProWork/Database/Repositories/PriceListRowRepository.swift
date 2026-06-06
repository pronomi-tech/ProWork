//  PriceListRowRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

final class PriceListRowRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(priceListId: String) throws -> [PriceListRow] {
        let sql = """
        SELECT
            id, priceListId, serviceType, timeType, categoryId, weekdayMask,
            startTime, endTime, unitPriceMinor, currency, minimumWindowMinutes,
            validFrom, validTo, isActive, sortOrder, notes,
            \(RecordMetadataSQL.columns)
        FROM price_list_rows
        WHERE priceListId = ? AND deletedAt IS NULL
        ORDER BY sortOrder ASC, serviceType ASC, timeType ASC;
        """

        return try database.query(
            sql,
            map: { try Self.makeRow(from: $0) },
            bind: { $0.bindText(priceListId, at: 1) }
        )
    }

    /// Bulk variant that fetches every row belonging to any of
    /// `priceListIds` in one SQL pass and groups them client-side. The
    /// caller-side loop (`computePeriodInternal`) used to call
    /// `fetchAll(priceListId:)` N times — for an org with dozens of price
    /// lists that's an N+1 storm on every report. Chunks the IN list to
    /// stay under SQLITE_MAX_VARIABLE_NUMBER (same pattern as
    /// `TodoTimeSessionRepository.fetch(ids:)`).
    func fetchAll(priceListIds: [String]) throws -> [String: [PriceListRow]] {
        guard !priceListIds.isEmpty else { return [:] }

        var grouped: [String: [PriceListRow]] = [:]
        let chunkSize = SQLiteParameterLimit.inClauseChunk
        for chunkStart in stride(from: 0, to: priceListIds.count, by: chunkSize) {
            let chunk = Array(priceListIds[chunkStart..<min(chunkStart + chunkSize, priceListIds.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
            SELECT
                id, priceListId, serviceType, timeType, categoryId, weekdayMask,
                startTime, endTime, unitPriceMinor, currency, minimumWindowMinutes,
                validFrom, validTo, isActive, sortOrder, notes,
                \(RecordMetadataSQL.columns)
            FROM price_list_rows
            WHERE priceListId IN (\(placeholders)) AND deletedAt IS NULL
            ORDER BY sortOrder ASC, serviceType ASC, timeType ASC;
            """

            let rows = try database.query(
                sql,
                map: { try Self.makeRow(from: $0) },
                bind: { stmt in
                    for (offset, id) in chunk.enumerated() {
                        stmt.bindText(id, at: Int32(offset + 1))
                    }
                }
            )
            for row in rows {
                grouped[row.priceListId, default: []].append(row)
            }
        }
        return grouped
    }

    func fetchActive(priceListId: String, on date: String) throws -> [PriceListRow] {
        let sql = """
        SELECT
            id, priceListId, serviceType, timeType, categoryId, weekdayMask,
            startTime, endTime, unitPriceMinor, currency, minimumWindowMinutes,
            validFrom, validTo, isActive, sortOrder, notes,
            \(RecordMetadataSQL.columns)
        FROM price_list_rows
        WHERE priceListId = ? AND isActive = 1 AND deletedAt IS NULL
          AND (validFrom IS NULL OR validFrom <= ?)
          AND (validTo IS NULL OR validTo >= ?)
        ORDER BY sortOrder ASC;
        """

        return try database.query(
            sql,
            map: { try Self.makeRow(from: $0) },
            bind: { stmt in
                stmt.bindText(priceListId, at: 1)
                stmt.bindText(date, at: 2)
                stmt.bindText(date, at: 3)
            }
        )
    }

    func insert(_ row: PriceListRow) throws {
        let sql = """
        INSERT INTO price_list_rows (
            id, priceListId, serviceType, timeType, categoryId, weekdayMask,
            startTime, endTime, unitPriceMinor, currency, minimumWindowMinutes,
            validFrom, validTo, isActive, sortOrder, notes,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { stmt in
            stmt.bindText(row.id, at: 1)
            stmt.bindText(row.priceListId, at: 2)
            stmt.bindText(row.serviceType.rawValue, at: 3)
            stmt.bindText(row.timeType.rawValue, at: 4)
            stmt.bindText(row.categoryId, at: 5)
            stmt.bindOptionalInt(row.weekdayMask, at: 6)
            stmt.bindText(row.startTime?.formatted, at: 7)
            stmt.bindText(row.endTime?.formatted, at: 8)
            stmt.bindInt(row.unitPriceMinor, at: 9)
            stmt.bindText(row.currency, at: 10)
            stmt.bindOptionalInt(row.minimumWindowMinutes, at: 11)
            stmt.bindText(row.validFrom, at: 12)
            stmt.bindText(row.validTo, at: 13)
            stmt.bindInt(row.isActive ? 1 : 0, at: 14)
            stmt.bindInt(row.sortOrder, at: 15)
            stmt.bindText(row.notes, at: 16)
            stmt.bindMetadata(row.meta, startingAt: 17)
        }
    }

    func update(_ row: PriceListRow) throws {
        let sql = """
        UPDATE price_list_rows
        SET serviceType = ?, timeType = ?, categoryId = ?, weekdayMask = ?,
            startTime = ?, endTime = ?, unitPriceMinor = ?, currency = ?,
            minimumWindowMinutes = ?, validFrom = ?, validTo = ?,
            isActive = ?, sortOrder = ?, notes = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { stmt in
            stmt.bindText(row.serviceType.rawValue, at: 1)
            stmt.bindText(row.timeType.rawValue, at: 2)
            stmt.bindText(row.categoryId, at: 3)
            stmt.bindOptionalInt(row.weekdayMask, at: 4)
            stmt.bindText(row.startTime?.formatted, at: 5)
            stmt.bindText(row.endTime?.formatted, at: 6)
            stmt.bindInt(row.unitPriceMinor, at: 7)
            stmt.bindText(row.currency, at: 8)
            stmt.bindOptionalInt(row.minimumWindowMinutes, at: 9)
            stmt.bindText(row.validFrom, at: 10)
            stmt.bindText(row.validTo, at: 11)
            stmt.bindInt(row.isActive ? 1 : 0, at: 12)
            stmt.bindInt(row.sortOrder, at: 13)
            stmt.bindText(row.notes, at: 14)
            stmt.bindText(row.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 15)
            stmt.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 16)
            stmt.bindText(row.id, at: 17)
        }
    }

    func softDelete(id: String, by userId: String) throws {
        // Delegate to the central helper.
        try database.softDelete(table: "price_list_rows", id: id, by: userId)
    }

    private static func makeRow(from statement: SQLiteStatement) throws -> PriceListRow {
        PriceListRow(
            id: statement.text(at: 0) ?? UUID().uuidString,
            priceListId: statement.text(at: 1) ?? "",
            serviceType: ServiceType(rawValue: statement.text(at: 2) ?? "remote") ?? .remote,
            timeType: TimeType(rawValue: statement.text(at: 3) ?? "regular") ?? .regular,
            categoryId: statement.text(at: 4),
            weekdayMask: statement.optionalInt(at: 5),
            startTime: statement.text(at: 6).flatMap(TimeOfDay.init(string:)),
            endTime: statement.text(at: 7).flatMap(TimeOfDay.init(string:)),
            unitPriceMinor: statement.int(at: 8),
            currency: statement.text(at: 9) ?? "TRY",
            minimumWindowMinutes: statement.optionalInt(at: 10),
            validFrom: statement.text(at: 11),
            validTo: statement.text(at: 12),
            isActive: statement.int(at: 13) == 1,
            sortOrder: statement.int(at: 14),
            notes: statement.text(at: 15),
            meta: try statement.readMetadata(startingAt: 16)
        )
    }
}

// MARK: - Convenience init from RecordMetadata
//
// This pattern (flat-field model + extension init that unpacks
// a RecordMetadata) only exists for PriceListRow today, so it's
// documented here as the canonical recipe rather than promoted to a
// generic protocol. Other models either carry `meta` directly (no
// init needed) or store metadata as flat fields and accept them at
// init time. If a third repository ever needs the same shape, factor
// into a `MetadataInitializable` protocol; one occurrence isn't
// enough to justify the abstraction.

extension PriceListRow {
    init(
        id: String = UUID().uuidString,
        priceListId: String,
        serviceType: ServiceType,
        timeType: TimeType = .regular,
        categoryId: String? = nil,
        weekdayMask: Int? = nil,
        startTime: TimeOfDay? = nil,
        endTime: TimeOfDay? = nil,
        unitPriceMinor: Int,
        currency: String = "TRY",
        minimumWindowMinutes: Int? = nil,
        validFrom: String? = nil,
        validTo: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0,
        notes: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            priceListId: priceListId,
            serviceType: serviceType,
            timeType: timeType,
            categoryId: categoryId,
            weekdayMask: weekdayMask,
            startTime: startTime,
            endTime: endTime,
            unitPriceMinor: unitPriceMinor,
            currency: currency,
            minimumWindowMinutes: minimumWindowMinutes,
            validFrom: validFrom,
            validTo: validTo,
            isActive: isActive,
            sortOrder: sortOrder,
            notes: notes,
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
