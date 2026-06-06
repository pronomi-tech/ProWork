//  PriceListRowsEditViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation
import os

@MainActor
final class PriceListRowsEditViewModel: ObservableObject {
    @Published private(set) var rows: [PriceListRow] = []
    @Published private(set) var categories: [TaskCategory] = []
    /// Views push errors through `reportError(_:)` rather
    /// than mutating this property directly so the encapsulation is
    /// enforced at the type level.
    @Published private(set) var errorMessage: String?

    func reportError(_ message: String?) {
        errorMessage = message
    }

    private let rowRepository: PriceListRowRepository
    private let categoryRepository: TaskCategoryRepository
    private let companyProfileRepository: CompanyProfileRepository
    private let customerRepository: CustomerRepository

    init(services: AppServices = .shared) {
        self.rowRepository = services.priceListRowRepository
        self.categoryRepository = services.categoryRepository
        self.companyProfileRepository = services.companyProfileRepository
        self.customerRepository = services.customerRepository
    }

    func load(priceListId: String) {
        do {
            categories = try categoryRepository.fetchAll()
            rows = try rowRepository.fetchAll(priceListId: priceListId)
                .sorted(by: rowSortOrder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func add(_ row: PriceListRow, priceListId: String) -> Bool {
        do {
            try rowRepository.insert(row)
            load(priceListId: priceListId)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ row: PriceListRow, priceListId: String) -> Bool {
        do {
            try rowRepository.update(row)
            load(priceListId: priceListId)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func softDelete(id: String, priceListId: String) {
        do {
            try rowRepository.softDelete(id: id, by: AppServices.currentUserId)
            load(priceListId: priceListId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Quote helpers

    /// Customer list for the quote sheet recipient picker.
    /// On fetch failure the list comes back empty but the error is
    /// written to `errorMessage`, so even an empty picker doesn't hide
    /// the silent failure from the user.
    func loadCustomers() -> [Customer] {
        do {
            return try customerRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Company profile + customer resolution needed for quote PDF generation.
    /// Customer fetch also logs (the old `try?` silent drop wasn't reported).
    func loadQuoteContext(
        organizationId: String,
        ownerType: PriceListOwnerType,
        ownerId: String?
    ) throws -> (companyProfile: CompanyProfile?, customer: Customer?) {
        let profile = try companyProfileRepository.fetch(organizationId: organizationId)
        let customer: Customer?
        if ownerType == .customer, let ownerId {
            do {
                customer = try customerRepository.fetch(id: ownerId)
            } catch {
                ProWorkLog.app.error(
                    "PriceListRowsEditViewModel.loadQuoteContext customer fetch failed for id=\(ownerId, privacy: .public): \(error.localizedDescription, privacy: .private)"
                )
                customer = nil
            }
        } else {
            customer = nil
        }
        return (profile, customer)
    }

    /// O(1) category-name lookup. With M categories and N rows
    /// the sort comparator was O(N log N × M) — visible jank on a
    /// price list with ~50 rows / ~10 categories. Pre-building the
    /// name dict once per sort call collapses M to a constant.
    private func rowSortOrder(_ lhs: PriceListRow, _ rhs: PriceListRow) -> Bool {
        if lhs.serviceType.sortOrder != rhs.serviceType.sortOrder {
            return lhs.serviceType.sortOrder < rhs.serviceType.sortOrder
        }
        if lhs.timeType.sortOrder != rhs.timeType.sortOrder {
            return lhs.timeType.sortOrder < rhs.timeType.sortOrder
        }
        let lhsCategory = lhs.categoryId.flatMap { categoryNamesById[$0] } ?? ""
        let rhsCategory = rhs.categoryId.flatMap { categoryNamesById[$0] } ?? ""
        return lhsCategory.localizedStandardCompare(rhsCategory) == .orderedAscending
    }

    private var categoryNamesById: [String: String] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
    }
}
