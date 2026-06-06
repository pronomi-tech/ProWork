//  TenantRepositoriesIntegrationTests.swift
//  ProWorkTests
//  Created by Pronomi.
//  Üç ufak tenant repository'sini tek dosyada toplar:
//    - OrganizationRepository
//    - UserRepository
//    - CompanyProfileRepository

import XCTest
@testable import ProWork

final class OrganizationRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: OrganizationRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = OrganizationRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    func test_fetchDefault_returnsSeededOrganization() throws {
        let org = try repository.fetchDefault()
        XCTAssertNotNil(org, "Migration001 default organization seed etmeli")
        XCTAssertEqual(org?.id, BuiltInOrganizationId.default)
    }

    func test_insert_thenFetchById_returnsOrganization() throws {
        let org = Organization(name: "qa-Acme", slug: "qa-acme", masterCurrency: "USD")
        try repository.insert(org)

        let fetched = try repository.fetch(id: org.id)
        XCTAssertEqual(fetched?.name, "qa-Acme")
        XCTAssertEqual(fetched?.slug, "qa-acme")
        XCTAssertEqual(fetched?.masterCurrency, "USD")
    }

    func test_update_persistsMasterCurrency() throws {
        var org = Organization(name: "qa-Update", masterCurrency: "TRY")
        try repository.insert(org)

        org.masterCurrency = "EUR"
        org.billingWindowMode = .session
        try repository.update(org)

        let fetched = try repository.fetch(id: org.id)
        XCTAssertEqual(fetched?.masterCurrency, "EUR")
        XCTAssertEqual(fetched?.billingWindowMode, .session)
    }

    func test_softDelete_hidesFromFetchAll() throws {
        let org = Organization(name: "qa-Silinen", masterCurrency: "TRY")
        try repository.insert(org)
        try repository.softDelete(id: org.id, by: BuiltInUserId.defaultOwner)

        let visible = try repository.fetchAll()
        XCTAssertFalse(visible.contains { $0.id == org.id })
    }
}

final class UserRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: UserRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = UserRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    func test_fetchDefaultOwner_returnsSeededOwner() throws {
        let owner = try repository.fetchDefaultOwner()
        XCTAssertNotNil(owner, "Migration001 default owner seed etmeli")
        XCTAssertEqual(owner?.id, BuiltInUserId.defaultOwner)
    }

    func test_insert_thenFetchById_returnsUser() throws {
        let user = User(email: "test@example.com", fullName: "qa-Test User", avatarColor: "blue")
        try repository.insert(user)

        let fetched = try repository.fetch(id: user.id)
        XCTAssertEqual(fetched?.email, "test@example.com")
        XCTAssertEqual(fetched?.fullName, "qa-Test User")
        XCTAssertEqual(fetched?.avatarColor, "blue")
    }

    func test_update_persistsFullNameAndEmail() throws {
        var user = User(email: "old@example.com", fullName: "qa-Old Name")
        try repository.insert(user)

        user.fullName = "qa-New Name"
        user.email = "new@example.com"
        try repository.update(user)

        let fetched = try repository.fetch(id: user.id)
        XCTAssertEqual(fetched?.fullName, "qa-New Name")
        XCTAssertEqual(fetched?.email, "new@example.com")
    }

    func test_softDelete_hidesFromFetchAll_unlessIncludingDeleted() throws {
        let user = User(fullName: "qa-Silinen")
        try repository.insert(user)
        try repository.softDelete(id: user.id)

        let active = try repository.fetchAll().map(\.id)
        XCTAssertFalse(active.contains(user.id))

        let all = try repository.fetchAll(includingDeleted: true).map(\.id)
        XCTAssertTrue(all.contains(user.id))
    }
}

final class CompanyProfileRepositoryIntegrationTests: XCTestCase {
    private var dbURL: URL!
    private var repository: CompanyProfileRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbURL = try DatabaseTestHelper.freshDatabase()
        repository = CompanyProfileRepository()
    }

    override func tearDown() {
        DatabaseTestHelper.teardown(at: dbURL)
        super.tearDown()
    }

    func test_fetch_returnsSeededCompanyProfile() throws {
        let profile = try repository.fetch(organizationId: BuiltInOrganizationId.default)
        XCTAssertNotNil(profile, "Migration001 default company profile seed etmeli")
        XCTAssertEqual(profile?.organizationId, BuiltInOrganizationId.default)
    }

    func test_upsert_updatesExistingProfile_inPlace() throws {
        // Seed olduğu için ilk fetch zaten bir satır döner; aynı organizationId ile
        // upsert güncellemeli, yeni satır yaratmamalı.
        var profile = try XCTUnwrap(try repository.fetch(organizationId: BuiltInOrganizationId.default))
        profile.legalName = "qa-Updated A.Ş."
        profile.taxNumber = "1234567890"
        profile.paymentTermsDays = 45
        try repository.upsert(profile)

        let fetched = try repository.fetch(organizationId: BuiltInOrganizationId.default)
        XCTAssertEqual(fetched?.legalName, "qa-Updated A.Ş.")
        XCTAssertEqual(fetched?.taxNumber, "1234567890")
        XCTAssertEqual(fetched?.paymentTermsDays, 45)
    }

    func test_upsert_persistsLogoData() throws {
        var profile = try XCTUnwrap(try repository.fetch(organizationId: BuiltInOrganizationId.default))
        let payload = Data([0xCA, 0xFE, 0xBA, 0xBE])
        profile.logoData = payload
        try repository.upsert(profile)

        let fetched = try repository.fetch(organizationId: BuiltInOrganizationId.default)
        XCTAssertEqual(fetched?.logoData, payload)
    }
}
