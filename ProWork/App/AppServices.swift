//
//  AppServices.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Repository ve servis instance'ları için merkezi container.
//  - SwiftUI view'ları doğrudan `@StateObject TodoRepository()` yaratmak yerine
//    `@EnvironmentObject AppServices` üzerinden erişir; instance'lar tek noktada
//    yaşar ve test akışlarında mock varyantlarla değiştirilebilir.
//  - Mevcut `Repository(database: AppDatabase = .shared)` default'ları kırılmıyor;
//    container kademeli olarak benimseniyor.
//

import Combine
import Foundation

final class AppServices: ObservableObject {
    // ViewModel'lerin `init(services: AppServices = .shared)` default arg
    // ifadeleri synthesized nonisolated bağlamda çözüldüğü için `shared`
    // explicit nonisolated. AppServices final + let-only olduğundan zaten
    // Sendable; `(unsafe)` modifier gereksiz.
    nonisolated static let shared = AppServices()

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
    }
}
