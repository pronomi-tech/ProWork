//  AppSettingsRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3
import os

final class AppSettingsRepository {
    private let database: AppDatabase

    /// `nonisolated`: stateless forwarder — together with the default
    /// `AppDatabase.shared`, can be safely called from both
    /// AppSettingsStore's MainActor init and from a default-argument
    /// nonisolated context.
    nonisolated init(database: AppDatabase = .shared) {
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

        // Both counter fields are now
        // *legacy* mirrors. `billingDocumentSequenceByYear` was moved
        // into the `billing_document_sequences` table by Migration002,
        // and `quoteSequenceByYear` was moved into
        // `quote_document_sequences` by the same migration. The app
        // settings rows are kept for back-compat with imports/exports
        // but never consulted for actual numbering. A corrupt payload
        // here is therefore not safety-critical — log it loudly via
        // `codableValue` (keeps the log) and fall back to
        // defaults so `fetch()` doesn't abort the whole settings load.
        let billingSeq = Self.codableValue(
            dictionary["billingDocumentSequenceByYear"],
            default: AppSettings.defaults.billingDocumentSequenceByYear,
            key: "billingDocumentSequenceByYear"
        )
        let quoteSeq = Self.codableValue(
            dictionary["quoteSequenceByYear"],
            default: AppSettings.defaults.quoteSequenceByYear,
            key: "quoteSequenceByYear"
        )

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
                default: AppSettings.defaults.serviceDocumentTemplateSettings,
                key: "serviceDocumentTemplateSettings"
            ),
            priceListQuoteTemplateSettings: Self.codableValue(
                dictionary["priceListQuoteTemplateSettings"],
                default: AppSettings.defaults.priceListQuoteTemplateSettings,
                key: "priceListQuoteTemplateSettings"
            ),
            quoteSequenceByYear: quoteSeq,
            billingDocumentSequenceByYear: billingSeq
        )
    }

    /// Generic update entrypoint. Callers should prefer the typed
    /// convenience methods below (`updateBool`, `updateInt`,
    /// `updateCodable`) — the generic form takes any string and the
    /// fetch path silently defaults when a value doesn't parse to the
    /// expected type, so an "updateBool(false)" written via this method
    /// as `"false"` would clash with the boolean reader expecting
    /// `"0"`/`"1"`/`"true"`. Documented loudly to discourage misuse.
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

    /// Bool persistence mirrors the reader's accepted set (`"0"`/`"1"`).
    func updateBool(key: String, value: Bool) throws {
        try update(key: key, value: value ? "1" : "0")
    }

    /// Integer persistence in canonical base-10. The reader uses
    /// `Int(_:)` which is base-10-only by default.
    func updateInt(key: String, value: Int) throws {
        try update(key: key, value: String(value))
    }

    /// Codable persistence with UTF-8 invariant. JSONEncoder always
    /// produces UTF-8 so the conversion can't fail in practice; we
    /// `preconditionFailure` rather than swallowing instead of silently
    /// writing a fallback string the reader would default away.
    func updateCodable<T: Encodable>(key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("JSONEncoder produced non-UTF8 output for key \(key); invariant broken.")
        }
        try update(key: key, value: json)
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

    /// JSON-stored setting decoding. A silently swallowed decode failure on a
    /// counter (`quoteSequenceByYear`, `billingDocumentSequenceByYear`) would
    /// quietly reset the sequence and risk duplicate document numbers — so we
    /// log the failure loudly. Migration002 moved the billing counter into a
    /// dedicated table; this guard remains for the JSON-backed settings that
    /// still live in `app_settings`.
    /// previously the helper conflated three states under a
    /// single "fall back to default" branch — missing key (legitimate
    /// initial state), empty value, and corrupt JSON. Corrupt JSON is the
    /// only one that warrants an alert; the other two are silent. Surface
    /// the corruption case to callers via the optional `onDecodeFailure`
    /// callback so safety-critical counters can refuse to overwrite the
    /// persisted value while non-critical preferences continue to default.
    /// Strict variant of `codableValue` used by safety-critical counters.
    /// Returns the default only when the persisted value is genuinely
    /// absent (NULL/empty). A present-but-corrupt payload throws so
    /// `fetch()` aborts and the caller can refuse to overwrite the
    /// existing on-disk value — without this, a sequence counter
    /// corruption would silently reset to 1 and risk duplicate invoice
    /// numbers across orgs.
    private static func requireCodableValue<T: Decodable>(
        _ raw: String?,
        default defaultValue: T,
        key: String
    ) throws -> T {
        guard let raw, !raw.isEmpty else { return defaultValue }
        guard let data = raw.data(using: .utf8) else {
            ProWorkLog.database.error(
                "app_settings JSON decode aborted (key=\(key, privacy: .public)): non-UTF8 payload"
            )
            throw CodableDecodeError.nonUTF8
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            ProWorkLog.database.error(
                "app_settings strict decode failed (key=\(key, privacy: .public)): \(error.localizedDescription, privacy: .public). Refusing to default — investigate persisted value to avoid silent counter reset."
            )
            throw error
        }
    }

    private static func codableValue<T: Decodable>(
        _ raw: String?,
        default defaultValue: T,
        key: String = #function,
        onDecodeFailure: ((Error) -> Void)? = nil
    ) -> T {
        // Missing key OR empty payload — both legitimate "no record yet"
        // states for an `app_settings` row that hasn't been written. No
        // log, no callback, just default.
        guard let raw, !raw.isEmpty else {
            return defaultValue
        }
        guard let data = raw.data(using: .utf8) else {
            ProWorkLog.database.error(
                "app_settings JSON decode aborted (key=\(key, privacy: .public)): non-UTF8 payload"
            )
            onDecodeFailure?(CodableDecodeError.nonUTF8)
            return defaultValue
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Real corruption: the row contains data but it doesn't
            // decode. Log loudly so an operator can investigate before
            // the on-disk value gets overwritten with the default on
            // next save.
            ProWorkLog.database.error(
                "app_settings JSON decode failed (key=\(key, privacy: .public)): \(error.localizedDescription, privacy: .public). Falling back to default — investigate persisted value to avoid silent counter reset."
            )
            onDecodeFailure?(error)
            return defaultValue
        }
    }
}

/// Marker error for the non-UTF8 branch so callers can
/// distinguish it from a JSONDecoder error if they need to react
/// differently (e.g. surface a clearer message in diagnostics).
enum CodableDecodeError: Error {
    case nonUTF8
}
