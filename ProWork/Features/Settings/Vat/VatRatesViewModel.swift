//
//  VatRatesViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class VatRatesViewModel: ObservableObject {
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
        do {
            try vatRateRepository.insert(rate)
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ rate: VatRate) -> Bool {
        do {
            try vatRateRepository.update(rate)
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func softDelete(id: String) {
        do {
            try vatRateRepository.softDelete(id: id)
            load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
