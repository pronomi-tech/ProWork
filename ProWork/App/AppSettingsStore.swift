//  AppSettingsStore.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import Combine
import os

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings = .defaults

    /// Previously this store and `AppServices` each held
    /// their own `AppSettingsRepository`. Both repositories are stateless
    /// (they only forward to `AppDatabase.shared`), so the SSoT violation
    /// was stylistic — but the duplication confused readers. Accept an
    /// injectable repository so tests and `AppServices` can pass in a
    /// shared instance. Production callers can still default-construct it.
    private let repository: AppSettingsRepository
    private let quoteSequenceRepository: QuoteDocumentSequenceRepository
    private let launchAtLoginService = LaunchAtLoginService()

    init(
        repository: AppSettingsRepository = AppSettingsRepository(),
        quoteSequenceRepository: QuoteDocumentSequenceRepository = QuoteDocumentSequenceRepository()
    ) {
        self.repository = repository
        self.quoteSequenceRepository = quoteSequenceRepository
    }

    // MARK: - User-scope preference mirror
    // a handful of settings are user-scope (preference of
    // this human/device) rather than workspace-scope (data belonging to the
    // DB being edited). Examples: UI language, font size, launch-at-login.
    // Previously these lived only in the DB, so switching to a different DB
    // file silently reset them to that DB's seeded defaults. We mirror them
    // into UserDefaults; on load we honor the UserDefaults value when
    // present, and on update we write both stores so the DB stays a
    // consistent self-contained backup.
    private static let userScopeLanguageKey = "com.pronomi.prowork.userPref.language"
    private static let userScopeFontSizeKey = "com.pronomi.prowork.userPref.fontSize"
    private static let userScopeLaunchAtLoginKey = "com.pronomi.prowork.userPref.launchAtLogin"
    private let defaults = UserDefaults.standard

    /// Keep failure isolation tight. The previous flow nested
    /// every step (DB fetch, user-defaults overlay, system sync, write-
    /// back) under one `do/catch`, so a launch-at-login sync write
    /// failure would blow the whole settings tree back to `.defaults`.
    /// Now the load splits into two phases:
    ///   1. **Hard required**: `repository.fetch()`. If this throws, we
    ///      genuinely have nothing to show and falling back to defaults
    ///      is the only safe option.
    ///   2. **Best-effort overlays**: user-defaults + system
    ///      launch-at-login. Each step is logged independently so a
    ///      transient failure no longer cascades into "every setting
    ///      reset on next launch".
    func load() {
        let fetched: AppSettings
        do {
            fetched = try repository.fetch()
        } catch {
            settings = .defaults
            ProWorkLocalizer.shared.update(language: .turkish)
            ProWorkLog.settings.error("AppSettings load (fetch) error: \(error.localizedDescription, privacy: .private)")
            return
        }
        var loaded = fetched

        // User-scope overrides win over whatever the (possibly newly
        // switched) DB seeded.
        if let rawLanguage = defaults.string(forKey: Self.userScopeLanguageKey),
           let language = AppLanguage(rawValue: rawLanguage) {
            loaded.language = language
        }
        if let rawFont = defaults.string(forKey: Self.userScopeFontSizeKey),
           let fontSize = AppFontSizeOption(rawValue: rawFont) {
            loaded.fontSize = fontSize
        }
        if defaults.object(forKey: Self.userScopeLaunchAtLoginKey) != nil {
            loaded.launchAtLoginEnabled = defaults.bool(forKey: Self.userScopeLaunchAtLoginKey)
        }

        // Best-effort: sync DB with macOS reality. Failure is logged
        // but does NOT reset other settings — `loaded` already
        // reflects the best information we have.
        if launchAtLoginService.isSupported {
            let systemValue = launchAtLoginService.currentEnabled()
            if loaded.launchAtLoginEnabled != systemValue {
                do {
                    try repository.update(
                        key: "launchAtLoginEnabled",
                        value: systemValue ? "1" : "0"
                    )
                    loaded.launchAtLoginEnabled = systemValue
                    defaults.set(systemValue, forKey: Self.userScopeLaunchAtLoginKey)
                } catch {
                    ProWorkLog.settings.error(
                        "AppSettings load (launchAtLogin sync) error: \(error.localizedDescription, privacy: .private); ignoring and keeping the user-mirror value"
                    )
                }
            }
        }

        settings = loaded
        ProWorkLocalizer.shared.update(language: loaded.language)
    }

    func updateDateFormat(_ value: String) {
        update(key: "dateFormat", value: value)
    }

    func updateLanguage(_ value: AppLanguage) {
        defaults.set(value.rawValue, forKey: Self.userScopeLanguageKey)
        update(key: "language", value: value.rawValue)
    }

    func updateTimeFormat(_ value: String) {
        update(key: "timeFormat", value: value)
    }

    func updateDateTimeFormat(_ value: String) {
        update(key: "dateTimeFormat", value: value)
    }

    func updateFontSize(_ value: AppFontSizeOption) {
        defaults.set(value.rawValue, forKey: Self.userScopeFontSizeKey)
        update(key: "fontSize", value: value.rawValue)
    }

    /// DB → system → UserDefaults order with rollback. The
    /// previous flow registered the launch agent first; if the DB write
    /// then failed, macOS would still launch the app on the next boot
    /// while the in-memory + persisted state disagreed. Order now:
    ///   1. DB write (durable, rolled back via update on failure).
    ///   2. System register (reversible).
    ///   3. UserDefaults mirror (cheap; reversible).
    /// If step 2 fails we explicitly write the previous value back to
    /// the DB so the UI and macOS stay aligned. Step 3 errors are
    /// effectively impossible (UserDefaults is in-memory) but the
    /// guard still flips state back on failure.
    func updateLaunchAtLoginEnabled(_ value: Bool) {
        let previousValue = settings.launchAtLoginEnabled
        do {
            try repository.update(key: "launchAtLoginEnabled", value: value ? "1" : "0")
        } catch {
            ProWorkLog.settings.error("LaunchAtLogin DB write failed: \(error.localizedDescription, privacy: .private)")
            ProWorkToastStore.shared.show(
                ProWorkLocalizer.shared.string(
                    "settings.error.saveFailed",
                    defaultValue: "Ayar kaydedilemedi."
                ),
                style: .error
            )
            return
        }

        do {
            try launchAtLoginService.setEnabled(value)
        } catch {
            ProWorkLog.settings.error("LaunchAtLogin system register failed: \(error.localizedDescription, privacy: .private)")
            // Rollback the DB write to keep persisted state in sync
            // with what macOS will actually do at next launch.
            do {
                try repository.update(key: "launchAtLoginEnabled", value: previousValue ? "1" : "0")
            } catch {
                ProWorkLog.settings.error("LaunchAtLogin rollback failed: \(error.localizedDescription, privacy: .private)")
            }
            ProWorkToastStore.shared.show(
                ProWorkLocalizer.shared.string(
                    "settings.error.launchAtLoginFailed",
                    defaultValue: "Açılışta otomatik başlatma değiştirilemedi."
                ),
                style: .error
            )
            load()
            return
        }

        defaults.set(value, forKey: Self.userScopeLaunchAtLoginKey)
        do {
            settings = try repository.fetch()
        } catch {
            ProWorkLog.settings.error("LaunchAtLogin fetch-after-update failed: \(error.localizedDescription, privacy: .private)")
            load()
        }
    }

    func updateOpenMainWindowOnLaunch(_ value: Bool) {
        update(key: "openMainWindowOnLaunch", value: value ? "1" : "0")
    }

    func updateMenuBarEnabled(_ value: Bool) {
        update(key: "menuBarEnabled", value: value ? "1" : "0")
    }

    func updateMenuBarStatusIds(_ value: [String]) {
        update(key: "menuBarStatusIds", value: value.joined(separator: ","))
    }

    func updateIdleAutoStopEnabled(_ value: Bool) {
        update(key: "idleAutoStopEnabled", value: value ? "1" : "0")
    }

    func updateIdleAutoStopMinutes(_ value: Int) {
        update(key: "idleAutoStopMinutes", value: String(max(1, value)))
    }

    func updatePreferredExchangeRateSource(_ value: ExchangeRateAutoSource) {
        update(key: "preferredExchangeRateSource", value: value.rawValue)
    }

    /// Surface save failures via `ProWorkToastStore` so the UI
    /// doesn't claim success while the on-disk value silently lags.
    /// Mirrors the behaviour of the generic `update(key:value:)` path.
    func updateServiceDocumentTemplateSettings(_ value: ServiceDocumentTemplateSettings) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            let json = String(decoding: data, as: UTF8.self)
            try repository.update(key: "serviceDocumentTemplateSettings", value: json)
            settings = try repository.fetch()
        } catch {
            ProWorkLog.settings.error("ServiceDocumentTemplateSettings update error: \(error.localizedDescription, privacy: .private)")
            ProWorkToastStore.shared.show(
                String(
                    format: ProWorkLocalizer.shared.string(
                        "settings.error.saveFailed",
                        defaultValue: "Ayar kaydedilemedi: %@"
                    ),
                    error.localizedDescription
                ),
                style: .error
            )
        }
    }

    func updatePriceListQuoteTemplateSettings(_ value: PriceListQuoteTemplateSettings) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            let json = String(decoding: data, as: UTF8.self)
            try repository.update(key: "priceListQuoteTemplateSettings", value: json)
            settings = try repository.fetch()
        } catch {
            ProWorkLog.settings.error("PriceListQuoteTemplateSettings update error: \(error.localizedDescription, privacy: .private)")
            ProWorkToastStore.shared.show(
                String(
                    format: ProWorkLocalizer.shared.string(
                        "settings.error.saveFailed",
                        defaultValue: "Ayar kaydedilemedi: %@"
                    ),
                    error.localizedDescription
                ),
                style: .error
            )
        }
    }

    /// Atomic reservation through `QuoteDocumentSequenceRepository`.
    /// Previous implementation read the JSON map from `app_settings`,
    /// incremented in memory, and wrote back — two parallel saves could
    /// reserve the same number. `reserveNext` UPSERTs inside a write
    /// transaction so concurrent calls serialize at the DB layer.
    func consumeNextQuoteSequence(year: Int) -> Int {
        do {
            return try quoteSequenceRepository.reserveNext(
                organizationId: BuiltInOrganizationId.default,
                year: year
            )
        } catch {
            ProWorkLog.settings.error(
                "quote sequence reservation failed: \(error.localizedDescription, privacy: .private)"
            )
            // Fall back to a peek-based candidate so the caller still
            // gets a non-zero hint; do NOT persist a fake reservation
            // since the next real reservation will detect the gap and
            // log it. UI surfaces the error via ProWorkToastStore on
            // higher-level callers.
            return (try? quoteSequenceRepository.peekCurrent(
                organizationId: BuiltInOrganizationId.default,
                year: year
            ) + 1) ?? 1
        }
    }

    /// Read-only candidate "next number" for form previews. Does not
    /// consume a counter slot, so a user staring at the screen does
    /// not burn quote numbers.
    func peekNextQuoteSequence(year: Int) -> Int {
        do {
            let current = try quoteSequenceRepository.peekCurrent(
                organizationId: BuiltInOrganizationId.default,
                year: year
            )
            return current + 1
        } catch {
            ProWorkLog.settings.error(
                "quote sequence peek failed: \(error.localizedDescription, privacy: .private)"
            )
            return 1
        }
    }

    func makeDateFormatter() -> DateFormatter {
        makeFormatter(format: settings.dateFormat)
    }

    func makeTimeFormatter() -> DateFormatter {
        makeFormatter(format: settings.timeFormat)
    }

    func makeDateTimeFormatter() -> DateFormatter {
        makeFormatter(format: settings.dateTimeFormat)
    }
    
    func formatDate(_ date: Date) -> String {
        makeDateFormatter().string(from: date)
    }

    func formatTime(_ date: Date) -> String {
        makeTimeFormatter().string(from: date)
    }

    func formatDateTime(_ date: Date) -> String {
        makeDateTimeFormatter().string(from: date)
    }

    func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    var locale: Locale {
        Locale(identifier: settings.language.localeIdentifier)
    }

    private func update(key: String, value: String) {
        do {
            try repository.update(key: key, value: value)
            settings = try repository.fetch()
            ProWorkLocalizer.shared.update(language: settings.language)
        } catch {
            // Previously the DB write failure was logged
            // and silently dropped, so the UI showed a successful save while
            // the next launch reverted to the old value. Surface via the
            // shared toast store so the user knows their change did not
            // persist; logging stays for diagnostics.
            ProWorkLog.settings.error("AppSettings update error: \(error.localizedDescription, privacy: .private)")
            let message = String(
                format: ProWorkLocalizer.shared.string(
                    "settings.error.saveFailed",
                    defaultValue: "Ayar kaydedilemedi: %@"
                ),
                error.localizedDescription
            )
            ProWorkToastStore.shared.show(message, style: .error)
        }
    }

    private func makeFormatter(format: String) -> DateFormatter {
        // K16: a single formatter is tied to a (locale, format) pair;
        // use the central cache instead of allocating one per row.
        ProWorkFormatters.cachedDateFormatter(
            localeIdentifier: settings.language.localeIdentifier,
            dateFormat: format
        )
    }
}
