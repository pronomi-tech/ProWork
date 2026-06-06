//  ProjectsViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation
import SwiftUI

@MainActor
final class ProjectsViewModel: ObservableObject, CRUDListViewModel {
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

    private let services: AppServices

    /// NotificationCenter token listening for customer-mutation broadcasts.
    /// DefinitionsView's ZStack opacity navigation only fires `.onAppear`
    /// on the first mount, so adding a customer in CustomersView wasn't
    /// immediately reflected in ProjectsView. This observer provides
    /// the cross-feature update.
    private var customersChangeObserver: NSObjectProtocol?

    init(services: AppServices = .shared) {
        self.services = services
        self.projectRepository = services.projectRepository
        self.customerRepository = services.customerRepository
        self.priceListRepository = services.priceListRepository
        self.organizationRepository = services.organizationRepository
        self.vatRateRepository = services.vatRateRepository

        // Swift 6 strict concurrency: NotificationCenter handler bir
        // Sendable closure — can't directly capture the @MainActor-
        // isolated `self`. Solution: the handler only fires
        // `Task { @MainActor }` and after the hop re-acquires `self`
        // yakalar. `queue: .main` zaten main thread'i garantiliyor, ama
        // through a weak reference; MainActor isolation at the type level
        // is provided by the Task.
        customersChangeObserver = NotificationCenter.default.addObserver(
            forName: .proWorkCustomersDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.load()
            }
        }
    }

    deinit {
        if let token = customersChangeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func load() {
        do {
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            // Master currency cached in AppServices.
            let organizationCurrency = services.cachedMasterCurrency()
            let priceLists = try priceListRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            let vatRates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            // O(1) customer lookup. The previous
            // `customers.first(where:)` per project gave us O(N×M)
            // on a tenant with hundreds of projects/customers — visible
            // jank on the projects list refresh. Mirrors the
            // BillingRunsViewModel.customerLookup pattern.
            let customerLookup = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0) })
            projectCurrencies = Dictionary(
                uniqueKeysWithValues: projects.map { project in
                    let customer = customerLookup[project.customerId]
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
            vatLabelsById = VatRateLabel.nonDefaultSelectionLabels(rates: vatRates)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(_ project: Project) -> Bool {
        performMutation { try projectRepository.insert(project) }
    }

    @discardableResult
    func update(_ project: Project) -> Bool {
        performMutation { try projectRepository.update(project) }
    }

    func delete(id: String) {
        performMutation { try projectRepository.softDelete(id: id, by: AppServices.currentUserId) }
    }
}
