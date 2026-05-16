//
//  VatRatesView.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Adlandırılmış KDV tanımlarının yönetimi. Kullanıcı tanımı buradan oluşturur,
//  müşteri/proje/kategori formundan atar. Atama yoksa `isDefault` tanım uygulanır.
//

import SwiftUI

struct VatRatesView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = VatRatesViewModel()

    @State private var isShowingNew = false
    @State private var editingRate: VatRate?
    @State private var confirmation: ProWorkConfirmation?

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("vat.title", defaultValue: "KDV Tanımları"),
            subtitle: settingsStore.localized(
                "vat.subtitle",
                defaultValue: "KDV oranlarını burada tanımlayın; müşteri, proje veya kategoriye atayın. Atama yoksa varsayılan oran uygulanır."
            ),
            errorMessage: viewModel.errorMessage,
            toolbar: {
                Button {
                    isShowingNew = true
                } label: {
                    ProWorkButtonLabel(
                        title: settingsStore.localized("vat.action.newRate", defaultValue: "Yeni Tanım"),
                        systemImage: "plus",
                        minHeight: 32
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        ) {
            if viewModel.rates.isEmpty {
                SettingsCard {
                    SettingsEmptyState(
                        systemImage: "percent",
                        title: settingsStore.localized("vat.empty.title", defaultValue: "KDV tanımı yok"),
                        message: settingsStore.localized(
                            "vat.empty.message",
                            defaultValue: "Sağ üstten yeni bir KDV tanımı oluşturun ve birini varsayılan olarak işaretleyin."
                        )
                    )
                }
            } else {
                table
            }
        }
        .onAppear { viewModel.load() }
        .sheet(isPresented: $isShowingNew) {
            VatRateFormView(mode: .create) { rate in
                if viewModel.create(rate) {
                    isShowingNew = false
                }
            }
        }
        .sheet(item: $editingRate) { rate in
            VatRateFormView(mode: .edit(rate)) { updated in
                if viewModel.update(updated) {
                    editingRate = nil
                }
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var table: some View {
        SettingsTableContainer {
            tableHeader
            Divider()
            ForEach(viewModel.rates) { rate in
                row(rate)
                Divider()
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("vat.column.name", defaultValue: "Ad"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("vat.column.rate", defaultValue: "Oran"))
                .frame(width: 110, alignment: .trailing)
            Text(settingsStore.localized("vat.column.default", defaultValue: "Varsayılan"))
                .frame(width: 110, alignment: .center)
            Text(settingsStore.localized("priceLists.column.active", defaultValue: "Aktif"))
                .frame(width: 60, alignment: .center)
            Text("").frame(width: 76)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func row(_ rate: VatRate) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: rate.isExempt ? "checkmark.shield" : "percent")
                    .foregroundStyle(rate.isExempt ? .green : .blue)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rate.name)
                        .proWorkTextStyle(.callout, weight: .medium)
                        .lineLimit(1)
                    if let note = rate.note, !note.isEmpty {
                        Text(note)
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(rateDisplay(rate))
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(width: 110, alignment: .trailing)

            Image(systemName: rate.isDefault ? "star.fill" : "star")
                .foregroundStyle(rate.isDefault ? .yellow : .secondary.opacity(0.5))
                .frame(width: 110, alignment: .center)
                .help(settingsStore.localized("vat.column.default.tooltip", defaultValue: "Atama yoksa uygulanır"))

            Image(systemName: rate.isActive ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(rate.isActive ? .green : .secondary)
                .frame(width: 60, alignment: .center)

            HStack(spacing: 6) {
                Button { editingRate = rate } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button { askDelete(rate) } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(rate.id == BuiltInVatRateId.defaultStandard || rate.id == BuiltInVatRateId.exempt)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func rateDisplay(_ rate: VatRate) -> String {
        if rate.isExempt {
            return settingsStore.localized("vat.exemptBadge", defaultValue: "Muaf")
        }
        let percent = NSDecimalNumber(decimal: rate.rate * 100).stringValue
        return "% \(percent)"
    }

    // MARK: - Actions

    private func askDelete(_ rate: VatRate) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("vat.delete.title", defaultValue: "KDV tanımı silinsin mi?"),
            message: settingsStore.localized(
                "vat.delete.message",
                defaultValue: "Bu tanım silinecek ve müşteri/proje/kategori atamaları temizlenecek."
            ),
            confirmTitle: settingsStore.localized("vat.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("vat.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.softDelete(id: rate.id)
        }
    }
}
