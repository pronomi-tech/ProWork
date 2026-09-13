//  Migration001SeedTests.swift
//  ProWorkTests
//  Tertemiz DB üzerinde Migration001 sonrası default kullanıcı, organizasyon,
//  KDV oranları, tatiller ve ayarlar bekleniyor.

import XCTest
@testable import ProWork

final class Migration001SeedTests: XCTestCase {

    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
    }

    override func tearDownWithError() throws {
        if let url = dbURL {
            DatabaseTestHelper.teardown(at: url)
        }
        dbURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Default user / organization

    func test_seed_createsDefaultOwnerUser() throws {
        let user = try UserRepository().fetchDefaultOwner()
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.id, BuiltInUserId.defaultOwner)
        XCTAssertEqual(user?.isActive, true)
        XCTAssertFalse(user?.fullName.isEmpty ?? true)
    }

    func test_seed_createsDefaultOrganization() throws {
        let org = try OrganizationRepository().fetchDefault()
        XCTAssertNotNil(org)
        XCTAssertEqual(org?.id, BuiltInOrganizationId.default)
        XCTAssertEqual(org?.masterCurrency, "TRY")
        XCTAssertEqual(org?.isActive, true)
    }

    func test_seed_doesNotCreateOrphanMembersTables() throws {
        // Üyeler/yetkiler kaldırıldı; bu tablolar şemada artık olmamalı.
        let memberTable = try? AppDatabase.shared.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='organization_members';"
        ) { stmt in stmt.text(at: 0) }
        XCTAssertTrue(memberTable?.isEmpty ?? true, "organization_members tablosu artık oluşmamalı")

        let accessTable = try? AppDatabase.shared.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_access';"
        ) { stmt in stmt.text(at: 0) }
        XCTAssertTrue(accessTable?.isEmpty ?? true, "customer_access tablosu artık oluşmamalı")
    }

    func test_seed_organizationsTable_hasNoDefaultMemberAccessColumn() throws {
        let columns = try AppDatabase.shared.query(
            "PRAGMA table_info(organizations);"
        ) { stmt in
            stmt.text(at: 1) ?? ""
        }
        XCTAssertFalse(columns.contains("defaultMemberAccess"), "defaultMemberAccess kolonu artık şemada olmamalı")
    }

    func test_billingWindowChecks_acceptReportMode_andKeepForeignKeysEnabled() throws {
        let schemas = try AppDatabase.shared.query("""
        SELECT name, sql
        FROM sqlite_master
        WHERE type = 'table' AND name IN ('organizations', 'projects')
        ORDER BY name;
        """) { statement in
            (statement.text(at: 0) ?? "", statement.text(at: 1) ?? "")
        }

        XCTAssertEqual(schemas.map(\.0), ["organizations", "projects"])
        XCTAssertTrue(schemas.allSatisfy { $0.1.contains("'report'") })

        let foreignKeysEnabled = try AppDatabase.shared.query("PRAGMA foreign_keys;") { statement in
            statement.int(at: 0)
        }
        XCTAssertEqual(foreignKeysEnabled, [1])
    }

    func test_billingReportLines_hasSecondPrecisionColumn() throws {
        let columns = try AppDatabase.shared.query(
            "PRAGMA table_info(billing_report_lines);"
        ) { statement in
            statement.text(at: 1) ?? ""
        }

        XCTAssertTrue(columns.contains("billableSeconds"))
    }

    // MARK: - KDV oranları

    func test_seed_createsTurkishVatRates() throws {
        let rates = try VatRateRepository().fetchAll(organizationId: BuiltInOrganizationId.default)
        XCTAssertGreaterThanOrEqual(rates.count, 1, "Varsayılan KDV oranları seed edilmeli")

        // En az bir default rate olmalı
        let defaultRate = rates.first { $0.isDefault }
        XCTAssertNotNil(defaultRate, "isDefault=true bir KDV oranı bulunmalı")
    }

    // MARK: - Tatiller

    func test_seed_createsTurkishHolidays() throws {
        let holidays = try HolidayRepository().fetchAll(organizationId: BuiltInOrganizationId.default)
        XCTAssertGreaterThan(holidays.count, 0, "Türkiye resmi tatilleri seed edilmeli")
        XCTAssertEqual(holidays.count, 119)
        XCTAssertTrue(holidays.contains { $0.dateString == "2024-01-01" && $0.name == "Yılbaşı" })
        XCTAssertTrue(holidays.contains { $0.dateString == "2030-10-29" && $0.name == "Cumhuriyet Bayramı" })
    }

    // MARK: - Şirket profili / mesai kuralı

    func test_seed_createsDefaultCompanyProfile() throws {
        let profile = try CompanyProfileRepository().fetch(organizationId: BuiltInOrganizationId.default)
        XCTAssertNotNil(profile, "Tek satırlık varsayılan şirket profili seed edilmeli")
    }

    func test_seed_createsDefaultBillingRule() throws {
        let rule = try BillingRuleRepository().fetchGlobal(organizationId: BuiltInOrganizationId.default)
        XCTAssertNotNil(rule, "Genel kapsamlı mesai kuralı seed edilmeli")
    }

    // MARK: - Şema tutarlılığı

    func test_seed_priceListsTable_hasIsDefaultColumn() throws {
        // Bu temizlik sürecinde eklendi; regresyon için kontrol.
        let columns = try AppDatabase.shared.query(
            "PRAGMA table_info(price_lists);"
        ) { stmt in
            stmt.text(at: 1) ?? ""
        }
        XCTAssertTrue(columns.contains("isDefault"), "price_lists.isDefault kolonu olmalı")
    }

    func test_seed_idempotent_doesNotDuplicateOnRerun() throws {
        // Migration tekrar çalıştırılırsa duplicate seed atmamalı (INSERT OR IGNORE).
        // freshDatabase zaten bir kez migrate etti; manuel olarak Migration001 sınıfını tekrar uygulayamayız
        // (zaten DatabaseMigrator atlar), ama kullanıcı sayımı 1 olmalı.
        let users = try UserRepository().fetchAll()
        XCTAssertEqual(users.count, 1, "Default user tekil olmalı")

        let orgs = try OrganizationRepository().fetchAll()
        XCTAssertEqual(orgs.count, 1, "Default organization tekil olmalı")
    }
}
