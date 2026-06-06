//  AppSettingsRepositoryIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.

import XCTest
@testable import ProWork

final class AppSettingsRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: AppSettingsRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = AppSettingsRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    // MARK: - Defaults round-trip

    func test_fetch_returnsDefaults_onFreshDatabase() throws {
        let settings = try repository.fetch()
        XCTAssertEqual(settings.language, AppSettings.defaults.language)
        XCTAssertEqual(settings.dateFormat, AppSettings.defaults.dateFormat)
        XCTAssertEqual(settings.fontSize, AppSettings.defaults.fontSize)
        XCTAssertEqual(settings.idleAutoStopMinutes, AppSettings.defaults.idleAutoStopMinutes)
        XCTAssertEqual(settings.menuBarEnabled, AppSettings.defaults.menuBarEnabled)
    }

    // MARK: - Update by key

    func test_update_persistsSimpleStringValue() throws {
        try repository.update(key: "dateFormat", value: "yyyy-MM-dd")

        let settings = try repository.fetch()
        XCTAssertEqual(settings.dateFormat, "yyyy-MM-dd")
    }

    func test_update_persistsBoolValue() throws {
        try repository.update(key: "menuBarEnabled", value: "0")
        let off = try repository.fetch()
        XCTAssertEqual(off.menuBarEnabled, false)

        try repository.update(key: "menuBarEnabled", value: "1")
        let on = try repository.fetch()
        XCTAssertEqual(on.menuBarEnabled, true)
    }

    func test_update_persistsIntValue() throws {
        try repository.update(key: "idleAutoStopMinutes", value: "25")

        let settings = try repository.fetch()
        XCTAssertEqual(settings.idleAutoStopMinutes, 25)
    }

    func test_update_persistsLanguageEnum() throws {
        try repository.update(key: "language", value: AppLanguage.english.rawValue)
        XCTAssertEqual(try repository.fetch().language, .english)

        try repository.update(key: "language", value: AppLanguage.turkish.rawValue)
        XCTAssertEqual(try repository.fetch().language, .turkish)
    }

    // MARK: - Codable JSON value

    func test_update_persistsQuoteSequenceByYear_asJson() throws {
        let json = #"{"2026":17,"2027":1}"#
        try repository.update(key: "quoteSequenceByYear", value: json)

        let settings = try repository.fetch()
        XCTAssertEqual(settings.quoteSequenceByYear["2026"], 17)
        XCTAssertEqual(settings.quoteSequenceByYear["2027"], 1)
    }

    func test_update_persistsBillingDocumentSequenceByYear_asJson() throws {
        let json = #"{"2026":123}"#
        try repository.update(key: "billingDocumentSequenceByYear", value: json)

        let settings = try repository.fetch()
        XCTAssertEqual(settings.billingDocumentSequenceByYear["2026"], 123)
    }

    // MARK: - Upsert semantics

    func test_update_overwritesPreviousValue_onSameKey() throws {
        try repository.update(key: "dateFormat", value: "dd/MM/yyyy")
        try repository.update(key: "dateFormat", value: "yyyy-MM-dd")

        let settings = try repository.fetch()
        XCTAssertEqual(settings.dateFormat, "yyyy-MM-dd", "Aynı key için ON CONFLICT DO UPDATE çalışmalı")
    }

    // MARK: - Invalid / partial values

    func test_update_unknownLanguage_fallsBackToDefault() throws {
        try repository.update(key: "language", value: "klingon")

        let settings = try repository.fetch()
        XCTAssertEqual(settings.language, AppSettings.defaults.language)
    }

    func test_update_malformedJson_fallsBackToDefault() throws {
        try repository.update(key: "quoteSequenceByYear", value: "{not-json}")

        let settings = try repository.fetch()
        XCTAssertEqual(settings.quoteSequenceByYear, AppSettings.defaults.quoteSequenceByYear)
    }
}
