//
//  TaskCategoriesViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TaskCategoriesViewModel: ObservableObject {
    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var vatLabelsById: [String: String] = [:]
    @Published var errorMessage: String?

    private let categoryRepository: TaskCategoryRepository
    private let vatRateRepository: VatRateRepository

    init(services: AppServices = .shared) {
        self.categoryRepository = services.categoryRepository
        self.vatRateRepository = services.vatRateRepository
    }

    func load(settingsStore: AppSettingsStore) {
        do {
            categories = try categoryRepository.fetchAll()
            let vatRates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            vatLabelsById = VatRateLabel.nonDefaultSelectionLabels(rates: vatRates, settingsStore: settingsStore)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(_ category: TaskCategory, settingsStore: AppSettingsStore) -> Bool {
        do {
            try categoryRepository.insert(category)
            load(settingsStore: settingsStore)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ category: TaskCategory, settingsStore: AppSettingsStore) -> Bool {
        do {
            try categoryRepository.update(category)
            load(settingsStore: settingsStore)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(id: String, settingsStore: AppSettingsStore) {
        do {
            try categoryRepository.delete(id: id)
            load(settingsStore: settingsStore)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
