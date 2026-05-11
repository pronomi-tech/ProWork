//
//  CustomersView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct CustomersView: View {
    @State private var customers: [Customer] = []
    @State private var customerCurrencies: [String: String] = [:]
    @State private var vatLabelsById: [String: String] = [:]
    @State private var isShowingCreateForm = false
    @State private var editingCustomer: Customer?
    @State private var pricingCustomer: Customer?
    @State private var confirmation: ProWorkConfirmation?
    @State private var errorMessage: String?
    @EnvironmentObject private var settingsStore: AppSettingsStore

    private let repository = CustomerRepository()
    private let priceListRepository = PriceListRepository()
    private let organizationRepository = OrganizationRepository()
    private let vatRateRepository = VatRateRepository()

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            header
            customerList
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
        .proWorkFrame(minWidth: 860, minHeight: 560)
        .proWorkToastNotifications(errorMessage: errorMessage)
        .onAppear {
            loadCustomers()
        }
        .sheet(isPresented: $isShowingCreateForm) {
            CustomerFormView(mode: .create) { customer in
                createCustomer(customer)
            }
        }
        .sheet(item: $editingCustomer) { customer in
            CustomerFormView(mode: .edit(customer)) { updatedCustomer in
                updateCustomer(updatedCustomer)
            }
        }
        .sheet(item: $pricingCustomer) { customer in
            ScopedPriceListsView(
                ownerType: .customer,
                ownerId: customer.id,
                ownerLabel: customer.name,
                defaultCurrency: customerCurrencies[customer.id] ?? "TRY",
                onListsChanged: {
                    loadCustomers()
                }
            )
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("customers.title", defaultValue: "Müşteriler"))
                    .proWorkTextStyle(.largeTitle)
                    .bold()

                Text(settingsStore.localized("customers.subtitle", defaultValue: "Müşteri kartları, varsayılan hizmet tipi ve ücretlendirme penceresi."))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingCreateForm = true
            } label: {
                ProWorkButtonLabel(title: settingsStore.localized("customers.action.new", defaultValue: "Yeni Müşteri"), systemImage: "plus", minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var customerList: some View {
        ZStack {
            if customers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                        ForEach(customers) { customer in
                            CustomerRowView(
                                customer: customer,
                                effectiveCurrency: customerCurrencies[customer.id] ?? "TRY",
                                vatLabel: customer.vatRateId.flatMap { vatLabelsById[$0] },
                                onEdit: {
                                    editingCustomer = customer
                                },
                                onPricing: {
                                    pricingCustomer = customer
                                },
                                onDelete: {
                                    askDeleteCustomer(customer)
                                }
                            )
                        }
                    }
                }
            }
        }
        .proWorkFrame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Image(systemName: "person.2")
                .proWorkFont(size: 34)
                .foregroundStyle(.secondary)

            Text(settingsStore.localized("customers.empty.title", defaultValue: "Henüz müşteri yok"))
                .proWorkTextStyle(.title2)
                .bold()

            Text(settingsStore.localized("customers.empty.message", defaultValue: "Sağ üstten yeni müşteri ekleyebilirsiniz."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .proWorkFrame(maxWidth: 420)
    }

    private func loadCustomers() {
        do {
            customers = try repository.fetchAll()
            let organizationCurrency = try organizationRepository.fetchDefault()?.masterCurrency ?? "TRY"
            let priceLists = try priceListRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            let vatRates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            customerCurrencies = Dictionary(
                uniqueKeysWithValues: customers.map { customer in
                    (
                        customer.id,
                        PricingCurrencyResolver.resolveCustomerCurrency(
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

    private func createCustomer(_ customer: Customer) {
        do {
            try repository.insert(customer)
            loadCustomers()
            isShowingCreateForm = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateCustomer(_ customer: Customer) {
        do {
            try repository.update(customer)
            loadCustomers()
            editingCustomer = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func askDeleteCustomer(_ customer: Customer) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("customers.delete.title", defaultValue: "Müşteri silinsin mi?"),
            message: String(format: settingsStore.localized("customers.delete.message", defaultValue: "“%@” müşterisi silinecek. Bu işlem geri alınamaz."), customer.name),
            confirmTitle: settingsStore.localized("customers.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("customers.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            deleteCustomer(customer)
        }
    }
    
    private func deleteCustomer(_ customer: Customer) {
        do {
            try repository.delete(id: customer.id)
            loadCustomers()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
