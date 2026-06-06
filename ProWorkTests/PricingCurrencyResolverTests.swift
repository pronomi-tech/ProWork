//  PricingCurrencyResolverTests.swift
//  ProWorkTests
//  Currency çözümleme öncelik sırası:
//    1. Müşterinin defaultPriceListId'si varsa (müşteri/global listelerden) onun currency'si
//    2. Proje listesi (proje currency'si için)
//    3. Müşteri listesi (default hariç)
//    4. Global liste (default hariç)
//    5. Organizasyon master currency'si

import XCTest
@testable import ProWork

final class PricingCurrencyResolverTests: XCTestCase {

    // MARK: - Müşteri currency

    func test_customerCurrency_fallsBackToOrganization_whenNoLists() {
        let currency = PricingCurrencyResolver.resolveCustomerCurrency(
            customerLists: [],
            globalLists: [],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "TRY")
    }

    func test_customerCurrency_picksCustomerListOverGlobal() {
        let customerList = PriceList(id: "C", ownerType: .customer, name: "M", currency: "EUR")
        let globalList = PriceList(id: "G", ownerType: .global, name: "G", currency: "USD")

        let currency = PricingCurrencyResolver.resolveCustomerCurrency(
            customerLists: [customerList],
            globalLists: [globalList],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "EUR")
    }

    func test_customerCurrency_fallsBackToGlobal_whenCustomerEmpty() {
        let globalList = PriceList(id: "G", ownerType: .global, name: "G", currency: "USD")

        let currency = PricingCurrencyResolver.resolveCustomerCurrency(
            customerLists: [],
            globalLists: [globalList],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "USD")
    }

    func test_customerCurrency_defaultPriceListId_winsOverOtherLists() {
        // Müşterinin defaultPriceListId'si global listeyi gösteriyor → onun currency'si kazanmalı.
        let customerList = PriceList(id: "C", ownerType: .customer, name: "M", currency: "EUR")
        let preferred = PriceList(id: "PREF", ownerType: .global, name: "Tercih", currency: "GBP")

        let currency = PricingCurrencyResolver.resolveCustomerCurrency(
            customerDefaultPriceListId: "PREF",
            customerLists: [customerList],
            globalLists: [preferred],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "GBP")
    }

    func test_customerCurrency_inactiveList_isSkipped() {
        var inactive = PriceList(id: "C", ownerType: .customer, name: "Kapalı", currency: "EUR")
        inactive.isActive = false
        let globalList = PriceList(id: "G", ownerType: .global, name: "G", currency: "USD")

        let currency = PricingCurrencyResolver.resolveCustomerCurrency(
            customerLists: [inactive],
            globalLists: [globalList],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "USD")
    }

    func test_customerCurrency_softDeletedList_isSkipped() {
        var deleted = PriceList(id: "C", ownerType: .customer, name: "Silinmiş", currency: "EUR")
        deleted.deletedAt = Date()
        let globalList = PriceList(id: "G", ownerType: .global, name: "G", currency: "USD")

        let currency = PricingCurrencyResolver.resolveCustomerCurrency(
            customerLists: [deleted],
            globalLists: [globalList],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "USD")
    }

    func test_customerCurrency_dateFilter_skipsExpiredList() {
        let expired = PriceList(
            id: "C", ownerType: .customer, name: "Eski", currency: "EUR",
            validFrom: nil, validTo: "2025-12-31"
        )
        let globalList = PriceList(id: "G", ownerType: .global, name: "G", currency: "USD")

        let currency = PricingCurrencyResolver.resolveCustomerCurrency(
            customerLists: [expired],
            globalLists: [globalList],
            organizationCurrency: "TRY",
            dateString: "2026-05-07"
        )
        XCTAssertEqual(currency, "USD")
    }

    // MARK: - Proje currency

    func test_projectCurrency_projectListWinsOverCustomerAndGlobal() {
        let projectList = PriceList(id: "P", ownerType: .project, name: "Proje", currency: "EUR")
        let customerList = PriceList(id: "C", ownerType: .customer, name: "M", currency: "USD")
        let globalList = PriceList(id: "G", ownerType: .global, name: "G", currency: "GBP")

        let currency = PricingCurrencyResolver.resolveProjectCurrency(
            projectLists: [projectList],
            customerLists: [customerList],
            globalLists: [globalList],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "EUR")
    }

    func test_projectCurrency_fallsBackToCustomer_whenNoProjectList() {
        let customerList = PriceList(id: "C", ownerType: .customer, name: "M", currency: "USD")
        let globalList = PriceList(id: "G", ownerType: .global, name: "G", currency: "GBP")

        let currency = PricingCurrencyResolver.resolveProjectCurrency(
            projectLists: [],
            customerLists: [customerList],
            globalLists: [globalList],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "USD")
    }

    func test_projectCurrency_fallsBackToOrganization_whenAllEmpty() {
        let currency = PricingCurrencyResolver.resolveProjectCurrency(
            projectLists: [],
            customerLists: [],
            globalLists: [],
            organizationCurrency: "TRY"
        )
        XCTAssertEqual(currency, "TRY")
    }
}
