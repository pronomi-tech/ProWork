//
//  PriceListRowsEditViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class PriceListRowsEditViewModel: ObservableObject {
    @Published private(set) var rows: [PriceListRow] = []
    @Published private(set) var categories: [TaskCategory] = []
    @Published var errorMessage: String?

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
            try rowRepository.softDelete(id: id)
            load(priceListId: priceListId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Quote helpers

    /// Quote sheet recipient picker'ı için müşteri listesi.
    func loadCustomers() -> [Customer] {
        (try? customerRepository.fetchAll()) ?? []
    }

    /// Quote PDF üretiminde gereken company profile + customer çözümlemesi.
    func loadQuoteContext(
        organizationId: String,
        ownerType: PriceListOwnerType,
        ownerId: String?
    ) throws -> (companyProfile: CompanyProfile?, customer: Customer?) {
        let profile = try companyProfileRepository.fetch(organizationId: organizationId)
        let customer: Customer? = {
            guard ownerType == .customer, let ownerId else { return nil }
            return try? customerRepository.fetch(id: ownerId)
        }()
        return (profile, customer)
    }

    private func rowSortOrder(_ lhs: PriceListRow, _ rhs: PriceListRow) -> Bool {
        if lhs.serviceType.sortOrder != rhs.serviceType.sortOrder {
            return lhs.serviceType.sortOrder < rhs.serviceType.sortOrder
        }
        if lhs.timeType.sortOrder != rhs.timeType.sortOrder {
            return lhs.timeType.sortOrder < rhs.timeType.sortOrder
        }

        let lhsCategory = lhs.categoryId.flatMap { id in
            categories.first(where: { $0.id == id })?.name
        } ?? ""
        let rhsCategory = rhs.categoryId.flatMap { id in
            categories.first(where: { $0.id == id })?.name
        } ?? ""

        return lhsCategory.localizedStandardCompare(rhsCategory) == .orderedAscending
    }
}
