//
//  PriceListMetaFormView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

enum PriceListFormMode: Hashable {
    case create
    case edit(PriceList)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create: return settingsStore.localized("priceLists.form.mode.create", defaultValue: "Yeni Fiyat Listesi")
        case .edit: return settingsStore.localized("priceLists.form.mode.edit", defaultValue: "Fiyat Listesini Düzenle")
        }
    }
}

struct PriceListMetaFormView: View {
    let mode: PriceListFormMode
    let ownerType: PriceListOwnerType
    let ownerId: String?
    let onSave: (PriceList) -> Void

    init(
        mode: PriceListFormMode,
        ownerType: PriceListOwnerType = .global,
        ownerId: String? = nil,
        onSave: @escaping (PriceList) -> Void
    ) {
        self.mode = mode
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.onSave = onSave
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var name: String = ""
    @State private var currency: String = "TRY"
    @State private var notes: String = ""
    @State private var isActive: Bool = true
    @State private var isDefault: Bool = false
    @State private var existingId: String = UUID().uuidString
    @State private var existingCreatedAt: Date = Date()
    @State private var errorMessage: String?

    private var currencyOptions: [PickerOption] {
        Currency.allCodes.map {
            PickerOption(id: $0, title: "\($0) — \(Currency.info(for: $0).displayName)")
        }
    }

    private var subtitle: String {
        switch ownerType {
        case .global: return settingsStore.localized("priceLists.form.subtitle.global", defaultValue: "Genel fiyat listesi")
        case .customer: return settingsStore.localized("priceLists.form.subtitle.customer", defaultValue: "Müşteri fiyat listesi")
        case .project: return settingsStore.localized("priceLists.form.subtitle.project", defaultValue: "Proje fiyat listesi")
        }
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: subtitle,
            systemImage: "list.bullet.rectangle.portrait",
            width: 520,
            height: 500
        ) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                SettingsFormError(message: errorMessage)

                SettingsFormRow(settingsStore.localized("priceLists.form.name", defaultValue: "Ad"), required: true) {
                    ProWorkTextField(placeholder: "", text: $name)
                        .frame(maxWidth: 360)
                }

                SettingsFormRow(settingsStore.localized("priceLists.form.currency", defaultValue: "Para Birimi"), required: true) {
                    ProWorkSearchPickerField(
                        placeholder: "TRY",
                        items: currencyOptions,
                        selectedId: $currency,
                        showsSearch: true,
                        systemImage: "banknote",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(maxWidth: 320)
                }

                SettingsFormRow(settingsStore.localized("priceLists.column.active", defaultValue: "Aktif")) {
                    Toggle("", isOn: $isActive).toggleStyle(.switch).labelsHidden()
                }

                SettingsFormRow(settingsStore.localized("priceLists.column.default", defaultValue: "Varsayılan")) {
                    Toggle("", isOn: $isDefault).toggleStyle(.switch).labelsHidden()
                }

                SettingsFormRow(settingsStore.localized("priceLists.form.notes", defaultValue: "Notlar"), alignment: .top) {
                    ProWorkTextEditor(text: $notes, minHeight: 70)
                        .frame(maxWidth: 440)
                }

                Spacer(minLength: 0)
            }
        } footer: {
            SettingsFormFooter(onCancel: { dismiss() }, onSave: save)
        }
        .onAppear { applyMode() }
    }

    private func applyMode() {
        if case .edit(let list) = mode {
            existingId = list.id
            existingCreatedAt = list.createdAt
            name = list.name
            currency = list.currency
            notes = list.notes ?? ""
            isActive = list.isActive
            isDefault = list.isDefault
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = settingsStore.localized("priceLists.form.error.nameRequired", defaultValue: "Liste adı zorunludur.")
            return
        }

        let list = PriceList(
            id: existingId,
            ownerType: ownerType,
            ownerId: ownerId,
            name: trimmedName,
            currency: currency,
            isActive: isActive,
            isDefault: isDefault,
            notes: notes.isEmpty ? nil : notes,
            organizationId: BuiltInOrganizationId.default,
            createdAt: existingCreatedAt
        )
        onSave(list)
        dismiss()
    }
}

/// Generic ID/title item used by various pickers in Settings screens.
struct PickerOption: Identifiable, Hashable {
    let id: String
    let title: String
}
