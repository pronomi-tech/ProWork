//
//  AppSettingsRepository.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import SQLite3

final class AppSettingsRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetch() throws -> AppSettings {
        let rows = try database.query("""
        SELECT key, value
        FROM app_settings;
        """) { statement in
            (
                key: statement.text(at: 0) ?? "",
                value: statement.text(at: 1) ?? ""
            )
        }

        var dictionary: [String: String] = [:]

        for row in rows {
            dictionary[row.key] = row.value
        }

        return AppSettings(
            language: AppLanguage(rawValue: dictionary["language"] ?? "") ?? AppSettings.defaults.language,
            dateFormat: dictionary["dateFormat"] ?? AppSettings.defaults.dateFormat,
            timeFormat: dictionary["timeFormat"] ?? AppSettings.defaults.timeFormat,
            dateTimeFormat: dictionary["dateTimeFormat"] ?? AppSettings.defaults.dateTimeFormat,
            fontSize: AppFontSizeOption(rawValue: dictionary["fontSize"] ?? "") ?? .normal,
            launchAtLoginEnabled: Self.boolValue(dictionary["launchAtLoginEnabled"], default: AppSettings.defaults.launchAtLoginEnabled),
            openMainWindowOnLaunch: Self.boolValue(dictionary["openMainWindowOnLaunch"], default: AppSettings.defaults.openMainWindowOnLaunch),
            menuBarEnabled: Self.boolValue(dictionary["menuBarEnabled"], default: AppSettings.defaults.menuBarEnabled),
            menuBarStatusIds: Self.csvArray(dictionary["menuBarStatusIds"]),
            idleAutoStopEnabled: Self.boolValue(dictionary["idleAutoStopEnabled"], default: AppSettings.defaults.idleAutoStopEnabled),
            idleAutoStopMinutes: Self.intValue(dictionary["idleAutoStopMinutes"], default: AppSettings.defaults.idleAutoStopMinutes),
            preferredExchangeRateSource: ExchangeRateAutoSource(rawValue: dictionary["preferredExchangeRateSource"] ?? "") ?? AppSettings.defaults.preferredExchangeRateSource,
            serviceDocumentTemplateSettings: Self.codableValue(
                dictionary["serviceDocumentTemplateSettings"],
                default: AppSettings.defaults.serviceDocumentTemplateSettings
            ),
            priceListQuoteTemplateSettings: Self.codableValue(
                dictionary["priceListQuoteTemplateSettings"],
                default: AppSettings.defaults.priceListQuoteTemplateSettings
            ),
            quoteSequenceByYear: Self.codableValue(
                dictionary["quoteSequenceByYear"],
                default: AppSettings.defaults.quoteSequenceByYear
            ),
            billingDocumentSequenceByYear: Self.codableValue(
                dictionary["billingDocumentSequenceByYear"],
                default: AppSettings.defaults.billingDocumentSequenceByYear
            )
        )
    }

    func update(key: String, value: String) throws {
        let sql = """
        INSERT INTO app_settings (key, value, createdAt, updatedAt)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updatedAt = excluded.updatedAt;
        """

        try database.execute(sql) { statement in
            let now = DateFormatter.proWorkSQLite.string(from: Date())
            statement.bindText(key, at: 1)
            statement.bindText(value, at: 2)
            statement.bindText(now, at: 3)
            statement.bindText(now, at: 4)
        }
    }

    private static func boolValue(_ raw: String?, default defaultValue: Bool) -> Bool {
        guard let raw else { return defaultValue }
        return raw == "1" || raw.lowercased() == "true"
    }

    private static func intValue(_ raw: String?, default defaultValue: Int) -> Int {
        guard let raw, let value = Int(raw) else { return defaultValue }
        return value
    }

    private static func csvArray(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func codableValue<T: Decodable>(_ raw: String?, default defaultValue: T) -> T {
        guard let raw,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return defaultValue
        }
        return decoded
    }
}
