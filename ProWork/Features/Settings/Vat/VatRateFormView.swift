//  VatRateFormView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

enum VatRateFormMode: Hashable {
    case create
    case edit(VatRate)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create: return settingsStore.localized("vat.form.mode.create", defaultValue: "Yeni KDV Tanımı")
        case .edit: return settingsStore.localized("vat.form.mode.edit", defaultValue: "KDV Tanımını Düzenle")
        }
    }
}

struct VatRateFormView: View {
    let mode: VatRateFormMode
    let onSave: (VatRate) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var name: String = ""
    @State private var rateText: String = "20"
    @State private var isExempt: Bool = false
    @State private var isDefault: Bool = false
    @State private var isActive: Bool = true
    @State private var note: String = ""
    @State private var existingId: String = UUID().uuidString
    @State private var existingCreatedAt: Date = Date()
    @State private var errorMessage: String?

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: nil,
            systemImage: "percent",
            width: FormSheetSize.vatRateForm.width,
            height: FormSheetSize.vatRateForm.height
        ) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                SettingsFormError(message: errorMessage)

                SettingsFormRow(settingsStore.localized("vat.form.name", defaultValue: "Ad"), required: true) {
                    ProWorkTextField(
                        placeholder: settingsStore.localized(
                            "vat.form.name.placeholder",
                            defaultValue: "Örn: Standart, İndirimli, Muafiyet"
                        ),
                        text: $name,
                        minHeight: 40
                    )
                    .frame(maxWidth: 360)
                }

                SettingsFormRow(settingsStore.localized("vat.form.exempt", defaultValue: "Muafiyet")) {
                    Toggle("", isOn: $isExempt)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(settingsStore.localized(
                            "vat.form.exempt.tooltip",
                            defaultValue: "Açıkken oran 0 olarak hesaplanır ve PDF'te 'Muaf' yazar."
                        ))
                }

                if !isExempt {
                    SettingsFormRow(settingsStore.localized("vat.form.rate", defaultValue: "Oran (%)"), required: true) {
                        ProWorkNumberField(
                            placeholder: settingsStore.localized("vat.form.rate.placeholder", defaultValue: "20"),
                            text: $rateText,
                            style: .decimal(maxFractionDigits: 2)
                        )
                        .frame(width: 120)
                    }
                }

                SettingsFormRow(settingsStore.localized("vat.form.default", defaultValue: "Varsayılan")) {
                    Toggle("", isOn: $isDefault)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(settingsStore.localized(
                            "vat.form.default.tooltip",
                            defaultValue: "Müşteri/proje/kategori ataması yoksa bu oran uygulanır."
                        ))
                }

                SettingsFormRow(settingsStore.localized("priceLists.column.active", defaultValue: "Aktif")) {
                    Toggle("", isOn: $isActive).toggleStyle(.switch).labelsHidden()
                }

                SettingsFormRow(settingsStore.localized("vat.form.note", defaultValue: "Not"), alignment: .top) {
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
            name = rate.name
            isExempt = rate.isExempt
            isDefault = rate.isDefault
            isActive = rate.isActive
            note = rate.note ?? ""
            let percent = NSDecimalNumber(decimal: rate.rate * 100).stringValue
            rateText = percent
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMessage = settingsStore.localized("vat.form.error.nameRequired", defaultValue: "Ad zorunludur.")
            return
        }

        let rate: Decimal
        if isExempt {
            rate = 0
        } else {
            // Routed through the shared ProWorkDecimalParser
            // so VAT and price forms share one locale + POSIX fallback
            // path. The previous String.replacingOccurrences fallback
            // would have corrupted en_US "1,234.56" by stripping the
            // thousand-separator comma.
            let localeFormatter = NumberFormatter()
            localeFormatter.locale = settingsStore.locale
            localeFormatter.numberStyle = .decimal
            let parsed = ProWorkDecimalParser.parse(rateText, primary: localeFormatter, maximumFractionDigits: 4)
            guard let value = parsed, value >= 0 else {
                errorMessage = settingsStore.localized("vat.form.error.invalidRate", defaultValue: "Oran geçersiz.")
                return
            }
            rate = value / 100
        }

        let vatRate = VatRate(
            id: existingId,
            name: cleanName,
            rate: rate,
            isDefault: isDefault,
            isExempt: isExempt,
            isActive: isActive,
            note: note.isEmpty ? nil : note,
            organizationId: BuiltInOrganizationId.default,
            createdAt: existingCreatedAt,
            updatedAt: Date()
        )
        onSave(vatRate)
        dismiss()
    }
}
