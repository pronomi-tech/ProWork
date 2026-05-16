//
//  ExchangeRatesViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class ExchangeRatesViewModel: ObservableObject {
    @Published private(set) var rates: [ExchangeRate] = []
    @Published private(set) var importingSource: ExchangeRateAutoSource?
    @Published var errorMessage: String?
    @Published var savedNotice: String?

    private let repository: ExchangeRateRepository
    private let tcmbSyncService: TCMBExchangeRateSyncService
    private let globalSyncService: GlobalExchangeRateSyncService

    init(
        services: AppServices = .shared,
        tcmbSyncService: TCMBExchangeRateSyncService? = nil,
        globalSyncService: GlobalExchangeRateSyncService? = nil
    ) {
        self.repository = services.exchangeRateRepository
        self.tcmbSyncService = tcmbSyncService ?? TCMBExchangeRateSyncService()
        self.globalSyncService = globalSyncService ?? GlobalExchangeRateSyncService()
    }

    func load() {
        do {
            rates = try repository.fetchAll(organizationId: BuiltInOrganizationId.default)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func add(_ rate: ExchangeRate, notice: String) -> Bool {
        do {
            try repository.upsert(rate)
            savedNotice = notice
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ rate: ExchangeRate, notice: String) -> Bool {
        do {
            try repository.upsert(rate)
            savedNotice = notice
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func softDelete(id: String, notice: String) {
        do {
            try repository.softDelete(id: id)
            savedNotice = notice
            load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importRates(
        from source: ExchangeRateAutoSource,
        startDate: Date,
        endDate: Date,
        currencies: [String]
    ) async -> TCMBExchangeRateSyncResult? {
        errorMessage = nil
        savedNotice = nil
        importingSource = source
        defer { importingSource = nil }

        do {
            let result: TCMBExchangeRateSyncResult
            switch source {
            case .tcmb:
                result = try await tcmbSyncService.sync(
                    from: startDate,
                    to: endDate,
                    currencies: currencies
                )
            case .global:
                result = try await globalSyncService.sync(
                    from: startDate,
                    to: endDate,
                    currencies: currencies
                )
            }
            load()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
