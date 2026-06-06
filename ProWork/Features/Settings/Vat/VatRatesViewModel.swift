//  VatRatesViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation

@MainActor
final class VatRatesViewModel: ObservableObject, CRUDListViewModel {
    @Published private(set) var rates: [VatRate] = []
    @Published var errorMessage: String?

    private let vatRateRepository: VatRateRepository

    init(services: AppServices = .shared) {
        self.vatRateRepository = services.vatRateRepository
    }

    func load() {
        do {
            rates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(_ rate: VatRate) -> Bool {
        performMutation { try vatRateRepository.insert(rate) }
    }

    @discardableResult
    func update(_ rate: VatRate) -> Bool {
        performMutation { try vatRateRepository.update(rate) }
    }

    func softDelete(id: String) {
        performMutation { try vatRateRepository.softDelete(id: id, by: AppServices.currentUserId) }
    }
}
