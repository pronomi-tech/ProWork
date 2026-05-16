//
//  CustomersView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct CustomersView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = CustomersViewModel()

    @State private var isShowingCreateForm = false
    @State private var editingCustomer: Customer?
    @State private var pricingCustomer: Customer?
    @State private var confirmation: ProWorkConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            header
            customerList
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
        .proWorkFrame(minWidth: 860, minHeight: 560)
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.load(settingsStore: settingsStore)
        }
        .sheet(isPresented: $isShowingCreateForm) {
            CustomerFormView(mode: .create) { customer in
                if viewModel.create(customer, settingsStore: settingsStore) {
                    isShowingCreateForm = false
                }
            }
        }
        .sheet(item: $editingCustomer) { customer in
            CustomerFormView(mode: .edit(customer)) { updatedCustomer in
                if viewModel.update(updatedCustomer, settingsStore: settingsStore) {
                    editingCustomer = nil
                }
            }
        }
        .sheet(item: $pricingCustomer) { customer in
            ScopedPriceListsView(
                ownerType: .customer,
                ownerId: customer.id,
                ownerLabel: customer.name,
                defaultCurrency: viewModel.customerCurrencies[customer.id] ?? "TRY",
                onListsChanged: {
                    viewModel.load(settingsStore: settingsStore)
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
            if viewModel.customers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                        ForEach(viewModel.customers) { customer in
                            CustomerRowView(
                                customer: customer,
                                effectiveCurrency: viewModel.customerCurrencies[customer.id] ?? "TRY",
                                vatLabel: customer.vatRateId.flatMap { viewModel.vatLabelsById[$0] },
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

    private func askDeleteCustomer(_ customer: Customer) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("customers.delete.title", defaultValue: "Müşteri silinsin mi?"),
            message: String(format: settingsStore.localized("customers.delete.message", defaultValue: "“%@” müşterisi silinecek. Bu işlem geri alınamaz."), customer.name),
            confirmTitle: settingsStore.localized("customers.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("customers.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.delete(id: customer.id, settingsStore: settingsStore)
        }
    }
}
