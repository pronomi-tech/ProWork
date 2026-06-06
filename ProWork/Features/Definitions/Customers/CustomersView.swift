//  CustomersView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct CustomersView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = CustomersViewModel()

    @State private var isShowingCreateForm = false
    @State private var editingCustomer: Customer?
    @State private var pricingCustomer: Customer?
    @State private var confirmation: ProWorkConfirmation?

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("customers.title", defaultValue: "Müşteriler"),
            subtitle: settingsStore.localized("customers.subtitle", defaultValue: "Müşteri kartları, varsayılan hizmet tipi ve ücretlendirme penceresi."),
            errorMessage: viewModel.errorMessage,
            contentScrollBehavior: .fixed,
            toolbar: {
                SettingsCRUDToolbarButton(
                    title: settingsStore.localized("customers.action.new", defaultValue: "Yeni Müşteri"),
                    systemImage: "plus"
                ) {
                    isShowingCreateForm = true
                }
            }
        ) {
            customerList
        }
        .onAppear {
            viewModel.load()
        }
        .settingsCRUDPresenter(
            isShowingCreate: $isShowingCreateForm,
            editingItem: $editingCustomer,
            confirmation: $confirmation,
            createForm: {
                CustomerFormView(mode: .create) { customer in
                    if viewModel.create(customer) {
                        isShowingCreateForm = false
                    }
                }
            },
            editForm: { customer in
                CustomerFormView(mode: .edit(customer)) { updatedCustomer in
                    if viewModel.update(updatedCustomer) {
                        editingCustomer = nil
                    }
                }
            }
        )
        // Pricing sheet is kept separate because it's an additional flow
        // outside the CRUDPresenter's standard create/edit/confirmation trio.
        .sheet(item: $pricingCustomer) { customer in
            ScopedPriceListsView(
                ownerType: .customer,
                ownerId: customer.id,
                ownerLabel: customer.name,
                defaultCurrency: viewModel.customerCurrencies[customer.id] ?? "TRY",
                onListsChanged: {
                    viewModel.load()
                }
            )
        }
    }

    private var customerList: some View {
        ProWorkGrid(
            items: viewModel.customers,
            header: { tableHeader },
            emptyContent: {
                ProWorkGridEmptyState(
                    systemImage: "person.2",
                    title: settingsStore.localized("customers.empty.title", defaultValue: "Henüz müşteri yok"),
                    message: settingsStore.localized("customers.empty.message", defaultValue: "Sağ üstten yeni müşteri ekleyebilirsiniz.")
                )
            },
            row: { customer in customerRow(customer) }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("customers.column.name", defaultValue: "Müşteri"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("customers.column.currency", defaultValue: "Para Birimi"))
                .frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("customers.column.serviceType", defaultValue: "Hizmet"))
                .frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("customers.column.window", defaultValue: "Min. Pencere"))
                .frame(width: 110, alignment: .trailing)
            Text(settingsStore.localized("customers.column.vat", defaultValue: "KDV"))
                .frame(width: 140, alignment: .leading)
            Text(settingsStore.localized("customers.column.active", defaultValue: "Durum"))
                .frame(width: 90, alignment: .leading)
            Color.gridHeaderSpacer(width: 110)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func customerRow(_ customer: Customer) -> some View {
        let effectiveCurrency = viewModel.customerCurrencies[customer.id] ?? "TRY"
        let vatLabel = customer.vatRateId.flatMap { viewModel.vatLabelsById[$0] } ?? "—"
        let serviceTitle = ServiceType(rawValue: customer.defaultServiceType)?.title ?? ServiceType.default.title
        let window = String(format: settingsStore.localized("customers.form.minutes", defaultValue: "%d dk"), customer.defaultMinBillingMinutes)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(customer.name)
                        .proWorkTextStyle(.callout, weight: .medium)
                        .lineLimit(1)
                    if let code = customer.code, !code.isEmpty {
                        Text(code)
                            .proWorkTextStyle(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
                if let notes = customer.notes, !notes.isEmpty {
                    Text(notes)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(effectiveCurrency)
                .proWorkTextStyle(.callout)
                .frame(width: 110, alignment: .leading)

            Text(serviceTitle)
                .proWorkTextStyle(.callout)
                .frame(width: 110, alignment: .leading)

            Text(window)
                .proWorkTextStyle(.callout)
                .frame(width: 110, alignment: .trailing)

            Text(vatLabel)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            ProWorkActivityBadge(isActive: customer.isActive)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    pricingCustomer = customer
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help(settingsStore.localized("customers.action.pricing", defaultValue: "Fiyatlandırma"))

                Button {
                    editingCustomer = customer
                } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button {
                    askDeleteCustomer(customer)
                } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func askDeleteCustomer(_ customer: Customer) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("customers.delete.title", defaultValue: "Müşteri silinsin mi?"),
            message: String(format: settingsStore.localized("customers.delete.message", defaultValue: "“%@” müşterisi silinecek. Bu işlem geri alınamaz."), customer.name),
            confirmTitle: settingsStore.localized("customers.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("customers.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.delete(id: customer.id)
        }
    }
}
