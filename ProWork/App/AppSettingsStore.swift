//
//  AppSettingsStore.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI
import Combine
import os

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings = .defaults

    private let repository = AppSettingsRepository()
    private let launchAtLoginService = LaunchAtLoginService()

    func load() {
        do {
            var loaded = try repository.fetch()

            if launchAtLoginService.isSupported {
                let systemValue = launchAtLoginService.currentEnabled()
                if loaded.launchAtLoginEnabled != systemValue {
                    try repository.update(
                        key: "launchAtLoginEnabled",
                        value: systemValue ? "1" : "0"
                    )
                    loaded.launchAtLoginEnabled = systemValue
                }
            }

            settings = loaded
            ProWorkLocalizer.shared.update(language: loaded.language)
        } catch {
            settings = .defaults
            ProWorkLocalizer.shared.update(language: .turkish)
            ProWorkLog.settings.error("AppSettings load error: \(error.localizedDescription, privacy: .private)")
        }
    }

    func updateDateFormat(_ value: String) {
        update(key: "dateFormat", value: value)
    }

    func updateLanguage(_ value: AppLanguage) {
        update(key: "language", value: value.rawValue)
    }

    func updateTimeFormat(_ value: String) {
        update(key: "timeFormat", value: value)
    }

    func updateDateTimeFormat(_ value: String) {
        update(key: "dateTimeFormat", value: value)
    }

    func updateFontSize(_ value: AppFontSizeOption) {
        update(key: "fontSize", value: value.rawValue)
    }

    func updateLaunchAtLoginEnabled(_ value: Bool) {
        do {
            try launchAtLoginService.setEnabled(value)
            try repository.update(key: "launchAtLoginEnabled", value: value ? "1" : "0")
            settings = try repository.fetch()
        } catch {
            ProWorkLog.settings.error("LaunchAtLogin update error: \(error.localizedDescription, privacy: .private)")
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

    func updateServiceDocumentTemplateSettings(_ value: ServiceDocumentTemplateSettings) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            let json = String(decoding: data, as: UTF8.self)
            try repository.update(key: "serviceDocumentTemplateSettings", value: json)
            settings = try repository.fetch()
        } catch {
            ProWorkLog.settings.error("ServiceDocumentTemplateSettings update error: \(error.localizedDescription, privacy: .private)")
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
        }
    }

    /// Verilen yıl için bir sonraki teklif sıra numarasını döner ve sayaç değerini kalıcı olarak günceller.
    func consumeNextQuoteSequence(year: Int) -> Int {
        let key = String(year)
        let next = (settings.quoteSequenceByYear[key] ?? 0) + 1
        var updated = settings.quoteSequenceByYear
        updated[key] = next
        persistQuoteSequence(updated)
        return next
    }

    /// Sayaç tüketmeden bir sonraki olası sıra numarasını döner (form öneri alanı için).
    func peekNextQuoteSequence(year: Int) -> Int {
        let key = String(year)
        return (settings.quoteSequenceByYear[key] ?? 0) + 1
    }

    private func persistQuoteSequence(_ value: [String: Int]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            let json = String(decoding: data, as: UTF8.self)
            try repository.update(key: "quoteSequenceByYear", value: json)
            settings = try repository.fetch()
        } catch {
            ProWorkLog.settings.error("quoteSequenceByYear update error: \(error.localizedDescription, privacy: .private)")
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
            ProWorkLog.settings.error("AppSettings update error: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func makeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}
