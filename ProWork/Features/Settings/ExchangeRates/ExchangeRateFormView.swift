//
//  ExchangeRateFormView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

enum ExchangeRateFormMode: Hashable {
    case create
    case edit(ExchangeRate)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create: return settingsStore.localized("exchangeRates.form.mode.create", defaultValue: "Yeni Kur")
        case .edit: return settingsStore.localized("exchangeRates.form.mode.edit", defaultValue: "Kuru Düzenle")
        }
    }
}

struct ExchangeRateFormView: View {
    let mode: ExchangeRateFormMode
    let onSave: (ExchangeRate) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var fromCurrency: String = "USD"
    @State private var rateText: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var existingId: String = UUID().uuidString
    @State private var existingCreatedAt: Date = Date()
    @State private var errorMessage: String?

    private var currencyOptions: [PickerOption] {
        Currency.allCodes
            .filter { $0 != "TRY" }
            .map { PickerOption(id: $0, title: $0) }
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: settingsStore.localized("exchangeRates.form.subtitle", defaultValue: "Manuel kur kaydı (yalnızca para birimi → TRY)"),
            systemImage: "arrow.left.arrow.right.circle",
            width: 540,
            height: 500
        ) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                SettingsFormError(message: errorMessage)

                SettingsFormRow(settingsStore.localized("exchangeRates.form.fromCurrency", defaultValue: "Kaynak Birim"), required: true) {
                    ProWorkSearchPickerField(
                        placeholder: "USD",
                        items: currencyOptions,
                        selectedId: $fromCurrency,
                        showsSearch: true,
                        systemImage: "banknote",
                        itemTitle: { $0.title },
                        matchesSearch: { $0.title.localizedCaseInsensitiveContains($1) }
                    )
                    .frame(maxWidth: 200)
                }

                SettingsFormRow(settingsStore.localized("exchangeRates.form.toCurrency", defaultValue: "Hedef Birim"), required: true) {
                    Text("TRY")
                        .proWorkTextStyle(.callout, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 200, alignment: .leading)
                }

                SettingsFormRow(settingsStore.localized("exchangeRates.form.rate", defaultValue: "Kur"), required: true) {
                    HStack(spacing: 6) {
                        Text("1 \(fromCurrency) =")
                            .proWorkTextStyle(.callout)
                            .foregroundStyle(.secondary)
                        ProWorkNumberField(
                            placeholder: "30,5000",
                            text: $rateText,
                            style: .decimal(maxFractionDigits: 4)
                        )
                            .frame(width: 160)
                        Text("TRY")
                            .proWorkTextStyle(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsFormRow(settingsStore.localized("exchangeRates.form.date", defaultValue: "Tarih"), required: true) {
                    ProWorkDateField(title: "", date: $date)
                        .frame(maxWidth: 220)
                }

                SettingsFormRow(settingsStore.localized("exchangeRates.form.note", defaultValue: "Not"), alignment: .top) {
                    ProWorkTextEditor(text: $note, minHeight: 60)
                        .frame(maxWidth: 480)
                }

                Spacer(minLength: 0)
            }
        } footer: {
            SettingsFormFooter(onCancel: { dismiss() }, onSave: save)
        }
        .onAppear { applyMode() }
    }

    private func applyMode() {
        if case .edit(let rate) = mode {
            existingId = rate.id
            existingCreatedAt = rate.createdAt
            fromCurrency = rate.fromCurrency
            rateText = rateNumberFormatter.string(from: NSDecimalNumber(decimal: rate.rate)) ?? NSDecimalNumber(decimal: rate.rate).stringValue
            if let parsed = Holiday.dateFormatter.date(from: rate.rateDate) {
                date = parsed
            }
            note = rate.note ?? ""
        }
    }

    private func save() {
        guard let n = rateNumberFormatter.number(from: rateText), n.decimalValue > 0 else {
            errorMessage = settingsStore.localized("exchangeRates.form.error.invalidRate", defaultValue: "Kur geçersiz.")
            return
        }

        let rate = ExchangeRate(
            id: existingId,
            fromCurrency: fromCurrency,
            toCurrency: "TRY",
            rate: n.decimalValue,
            forexBuying: n.decimalValue,
            forexSelling: n.decimalValue,
            banknoteBuying: n.decimalValue,
            banknoteSelling: n.decimalValue,
            rateDate: Holiday.dateFormatter.string(from: date),
            source: .manual,
            fetchedAt: Date(),
            note: note.isEmpty ? nil : note,
            organizationId: BuiltInOrganizationId.default,
            createdAt: existingCreatedAt
        )
        onSave(rate)
        dismiss()
    }

    private var rateNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = settingsStore.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter
    }
}
