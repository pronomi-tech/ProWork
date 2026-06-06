//  AppServices.swift
//  ProWork
//  Created by Pronomi.
//  Central container for repository and service instances.
//  - SwiftUI views reach for `@EnvironmentObject AppServices` instead of
//    `@StateObject TodoRepository()` directly; instances live in one place
//    and can be swapped for mocks in tests.
//  - The existing `Repository(database: AppDatabase = .shared)` defaults are
//    not broken; the container is adopted incrementally.

import Combine
import Foundation

final class AppServices: ObservableObject {
    // ViewModels' `init(services: AppServices = .shared)` default-arg
    // expressions are resolved in a synthesized nonisolated context,
    // so `shared` is explicitly nonisolated. AppServices is final + let-only,
    // therefore already Sendable; no `(unsafe)` modifier needed.
    nonisolated static let shared = AppServices()

    /// Canonical "who is performing this mutation" accessor for audit
    /// columns (`updatedByUserId`, soft-delete `by:`, etc.). Single-user
    /// desktop deployment today, so it returns the built-in default
    /// owner; when authentication arrives this becomes the logged-in
    /// user. Call sites pass this through repositories' `by:` parameter
    /// so an audit trail never reads "defaultOwner" via a silent
    /// default that masked the real caller.
    nonisolated static var currentUserId: String {
        BuiltInUserId.defaultOwner
    }

    // MARK: - Infrastructure

    let clock: AppClock

    // MARK: - Repositories

    let customerRepository: CustomerRepository
    let projectRepository: ProjectRepository
    let categoryRepository: TaskCategoryRepository
    let statusRepository: TodoStatusRepository
    let todoRepository: TodoRepository
    let todoTimeSessionRepository: TodoTimeSessionRepository
    let todoBillingOverrideRepository: TodoBillingOverrideRepository

    let organizationRepository: OrganizationRepository
    let userRepository: UserRepository
    let companyProfileRepository: CompanyProfileRepository
    let appSettingsRepository: AppSettingsRepository

    let priceListRepository: PriceListRepository
    let priceListRowRepository: PriceListRowRepository
    let billingRuleRepository: BillingRuleRepository
    let holidayRepository: HolidayRepository
    let vatRateRepository: VatRateRepository

    let exchangeRateRepository: ExchangeRateRepository
    let paymentRepository: PaymentRepository
    let billingReportRunRepository: BillingReportRunRepository
    let billingReportLineRepository: BillingReportLineRepository
    let billingDocumentSequenceRepository: BillingDocumentSequenceRepository
    let quoteDocumentSequenceRepository: QuoteDocumentSequenceRepository
    let billingReportRunSnapshotRepository: BillingReportRunSnapshotRepository

    // MARK: - Pure-logic services

    /// `PricingCurrencyResolver` is a thin wrapper over the repos; form and
    /// list views share this single instance instead of allocating a new
    /// one per render.
    let pricingCurrencyResolver: PricingCurrencyResolver

    /// Master currency cache keyed by organizationId so the UI doesn't run
    /// `OrganizationRepository.fetchDefault()` per render.
    /// `AppServices` is rebuilt on DB change (K11/K13), so the cache stays
    /// bounded by process lifetime; call
    /// `invalidateOrganizationCurrencyCache()` if manual invalidation is needed.
    private let organizationCurrencyLock = NSLock()
    private var organizationCurrencyCache: [String: String] = [:]

    init(
        clock: AppClock = SystemAppClock(),
        database: AppDatabase = .shared
    ) {
        self.clock = clock

        self.customerRepository = CustomerRepository(database: database)
        self.projectRepository = ProjectRepository(database: database)
        self.categoryRepository = TaskCategoryRepository(database: database)
        self.statusRepository = TodoStatusRepository(database: database)
        self.todoRepository = TodoRepository(database: database)
        self.todoTimeSessionRepository = TodoTimeSessionRepository(database: database)
        self.todoBillingOverrideRepository = TodoBillingOverrideRepository(database: database)

        self.organizationRepository = OrganizationRepository(database: database)
        self.userRepository = UserRepository(database: database)
        self.companyProfileRepository = CompanyProfileRepository(database: database)
        self.appSettingsRepository = AppSettingsRepository(database: database)

        self.priceListRepository = PriceListRepository(database: database)
        self.priceListRowRepository = PriceListRowRepository(database: database)
        self.billingRuleRepository = BillingRuleRepository(database: database)
        self.holidayRepository = HolidayRepository(database: database)
        self.vatRateRepository = VatRateRepository(database: database)

        self.exchangeRateRepository = ExchangeRateRepository(database: database)
        self.paymentRepository = PaymentRepository(database: database)
        self.billingReportRunRepository = BillingReportRunRepository(database: database)
        self.billingReportLineRepository = BillingReportLineRepository(database: database)
        self.billingDocumentSequenceRepository = BillingDocumentSequenceRepository(database: database)
        self.quoteDocumentSequenceRepository = QuoteDocumentSequenceRepository(database: database)
        self.billingReportRunSnapshotRepository = BillingReportRunSnapshotRepository(database: database)

        self.pricingCurrencyResolver = PricingCurrencyResolver(
            organizationRepository: self.organizationRepository,
            customerRepository: self.customerRepository,
            priceListRepository: self.priceListRepository
        )
    }

    /// Cached master currency. Avoids hitting the DB via
    /// `fetchDefault()` / `fetch(id:)` on every render. If the load fails,
    /// we don't negative-cache to `"TRY"` permanently; the next call retries.
    ///
    /// Double-checked locking. The previous version held
    /// `organizationCurrencyLock` for the entire DB fetch, blocking
    /// every concurrent caller for the slowest query in the system.
    /// Now the lock is held only across the cache reads/writes; the
    /// DB query runs without the lock, then the second check covers
    /// the rare case where another thread populated the entry while
    /// we were querying. SQLite serialises writes through its own
    /// `inWriteTransaction` lock, so duplicate fetches are cheap and
    /// correct.
    func cachedMasterCurrency(
        organizationId: String = BuiltInOrganizationId.default
    ) -> String {
        organizationCurrencyLock.lock()
        if let cached = organizationCurrencyCache[organizationId] {
            organizationCurrencyLock.unlock()
            return cached
        }
        organizationCurrencyLock.unlock()

        let resolved: String?
        do {
            let org: Organization?
            if organizationId == BuiltInOrganizationId.default {
                org = try organizationRepository.fetchDefault()
            } else {
                org = try organizationRepository.fetch(id: organizationId)
            }
            resolved = org?.masterCurrency.uppercased()
        } catch {
            resolved = nil
        }

        let value = resolved ?? "TRY"
        guard resolved != nil else { return value }

        organizationCurrencyLock.lock()
        defer { organizationCurrencyLock.unlock() }
        if let raced = organizationCurrencyCache[organizationId] {
            // Another thread populated the cache while we were
            // querying; prefer their value (matches the read above so
            // callers see a single stable answer per cache lifetime).
            return raced
        }
        organizationCurrencyCache[organizationId] = value
        return value
    }

    /// Callers invoke this when the company profile or master currency
    /// changes to clear the cache.
    func invalidateOrganizationCurrencyCache() {
        organizationCurrencyLock.lock()
        organizationCurrencyCache = [:]
        organizationCurrencyLock.unlock()
    }
}
