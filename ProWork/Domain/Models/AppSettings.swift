//  AppSettings.swift
//  ProWork
//  Created by Pronomi.

import Foundation

struct AppSettings: Hashable {
    var language: AppLanguage
    var dateFormat: String
    var timeFormat: String
    var dateTimeFormat: String
    var fontSize: AppFontSizeOption
    var launchAtLoginEnabled: Bool
    var openMainWindowOnLaunch: Bool
    var menuBarEnabled: Bool
    var menuBarStatusIds: [String]
    var idleAutoStopEnabled: Bool
    var idleAutoStopMinutes: Int
    var preferredExchangeRateSource: ExchangeRateAutoSource
    var serviceDocumentTemplateSettings: ServiceDocumentTemplateSettings
    var priceListQuoteTemplateSettings: PriceListQuoteTemplateSettings
    /// Last-used quote number counter by year. Key: 4-digit year (e.g. "2026").
    var quoteSequenceByYear: [String: Int]
    /// Last-used billing-run document number counter by year.
    /// Key: 4-digit year. Consumed at finalize time.
    var billingDocumentSequenceByYear: [String: Int]

    static let defaults = AppSettings(
        language: .turkish,
        dateFormat: "dd.MM.yyyy",
        timeFormat: "HH:mm",
        dateTimeFormat: "dd.MM.yyyy HH:mm",
        fontSize: .normal,
        launchAtLoginEnabled: false,
        openMainWindowOnLaunch: true,
        menuBarEnabled: true,
        menuBarStatusIds: [],
        idleAutoStopEnabled: false,
        idleAutoStopMinutes: 10,
        preferredExchangeRateSource: .tcmb,
        serviceDocumentTemplateSettings: .defaultTemplate,
        priceListQuoteTemplateSettings: .defaultTemplate,
        quoteSequenceByYear: [:],
        billingDocumentSequenceByYear: [:]
    )
}
