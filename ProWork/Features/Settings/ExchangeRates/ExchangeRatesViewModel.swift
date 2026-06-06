//  ExchangeRatesViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation

@MainActor
final class ExchangeRatesViewModel: ObservableObject, CRUDListViewModel {
    @Published private(set) var rates: [ExchangeRate] = []
    @Published private(set) var importingSource: ExchangeRateAutoSource?
    @Published var errorMessage: String?
    @Published var savedNotice: String?

    private let repository: ExchangeRateRepository
    private let tcmbSyncService: TCMBExchangeRateSyncService
    private let globalSyncService: GlobalExchangeRateSyncService
    /// Shared with BillingRunsViewModel; the previous
    /// `savedNotice = …` lines without a clear path left the toast
    /// stuck until the user navigated away.
    private let savedNoticeScheduler = NoticeScheduler()

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
        let ok = performMutation { try repository.upsert(rate) }
        if ok { showSavedNotice(notice) }
        return ok
    }

    @discardableResult
    func update(_ rate: ExchangeRate, notice: String) -> Bool {
        let ok = performMutation { try repository.upsert(rate) }
        if ok { showSavedNotice(notice) }
        return ok
    }

    func softDelete(id: String, notice: String) {
        if performMutation({ try repository.softDelete(id: id, by: AppServices.currentUserId) }) {
            showSavedNotice(notice)
        }
    }

    /// Exposed for the View's import-success path
    /// which produces a message ("Imported 13 rates from TCMB") the VM
    /// can't synthesise without the View's locale + result data. Other
    /// callers (`add`, `update`, `softDelete`) route through this
    /// helper internally.
    func showSavedNotice(_ message: String) {
        savedNoticeScheduler.show(message) { [weak self] value in
            self?.savedNotice = value
        }
    }

    /// Previously import failures only set `errorMessage`,
    /// which routes through the transient toast (auto-dismisses in seconds).
    /// A user who looked away during a long sync would miss the failure
    /// entirely. `lastImportError` stays set until either dismissed or
    /// another import succeeds, so the import panel can render a sticky
    /// inline error banner next to the "Fetch" button.
    @Published var lastImportError: ImportFailure?

    struct ImportFailure: Equatable {
        let source: ExchangeRateAutoSource
        let message: String
    }

    func dismissLastImportError() {
        lastImportError = nil
    }

    func importRates(
        from source: ExchangeRateAutoSource,
        startDate: Date,
        endDate: Date,
        currencies: [String]
    ) async -> TCMBExchangeRateSyncResult? {
        errorMessage = nil
        savedNotice = nil
        lastImportError = nil
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
            lastImportError = ImportFailure(source: source, message: error.localizedDescription)
            return nil
        }
    }
}
