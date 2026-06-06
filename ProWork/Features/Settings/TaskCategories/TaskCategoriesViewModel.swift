//  TaskCategoriesViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation
import SwiftUI

@MainActor
final class TaskCategoriesViewModel: ObservableObject, CRUDListViewModel {
    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var vatLabelsById: [String: String] = [:]
    @Published var errorMessage: String?

    private let categoryRepository: TaskCategoryRepository
    private let vatRateRepository: VatRateRepository

    init(services: AppServices = .shared) {
        self.categoryRepository = services.categoryRepository
        self.vatRateRepository = services.vatRateRepository
    }

    func load() {
        do {
            categories = try categoryRepository.fetchAll()
            let vatRates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            vatLabelsById = VatRateLabel.nonDefaultSelectionLabels(rates: vatRates)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(_ category: TaskCategory) -> Bool {
        performMutation { try categoryRepository.insert(category) }
    }

    @discardableResult
    func update(_ category: TaskCategory) -> Bool {
        performMutation { try categoryRepository.update(category) }
    }

    func delete(id: String) {
        performMutation { try categoryRepository.softDelete(id: id, by: AppServices.currentUserId) }
    }
}
