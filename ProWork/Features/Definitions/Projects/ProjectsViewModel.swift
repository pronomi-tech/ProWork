//
//  ProjectsViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published private(set) var projects: [ProjectListItem] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projectCurrencies: [String: String] = [:]
    @Published private(set) var vatLabelsById: [String: String] = [:]
    @Published var errorMessage: String?

    private let projectRepository: ProjectRepository
    private let customerRepository: CustomerRepository
    private let priceListRepository: PriceListRepository
    private let organizationRepository: OrganizationRepository
    private let vatRateRepository: VatRateRepository

    init(services: AppServices = .shared) {
        self.projectRepository = services.projectRepository
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
        self.vatRateRepository = services.vatRateRepository
    }

    func load(settingsStore: AppSettingsStore) {
        do {
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            let organizationCurrency = try organizationRepository.fetchDefault()?.masterCurrency ?? "TRY"
            let priceLists = try priceListRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            let vatRates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            projectCurrencies = Dictionary(
                uniqueKeysWithValues: projects.map { project in
                    let customer = customers.first(where: { $0.id == project.customerId })
                    return (
                        project.id,
                        PricingCurrencyResolver.resolveProjectCurrency(
                            projectId: project.id,
                            customer: customer,
                            priceLists: priceLists,
                            organizationCurrency: organizationCurrency
                        )
                    )
                }
            )
            vatLabelsById = VatRateLabel.nonDefaultSelectionLabels(
                rates: vatRates,
                settingsStore: settingsStore
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(_ project: Project, settingsStore: AppSettingsStore) -> Bool {
        do {
            try projectRepository.insert(project)
            load(settingsStore: settingsStore)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ project: Project, settingsStore: AppSettingsStore) -> Bool {
        do {
            try projectRepository.update(project)
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
            try projectRepository.delete(id: id)
            load(settingsStore: settingsStore)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
