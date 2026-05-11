//
//  PriceListRowFormView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

enum PriceListRowFormMode: Hashable {
    case create
    case edit(PriceListRow)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create: return settingsStore.localized("priceLists.rows.form.mode.create", defaultValue: "Yeni Fiyat Satırı")
        case .edit: return settingsStore.localized("priceLists.rows.form.mode.edit", defaultValue: "Fiyat Satırını Düzenle")
        }
    }
}

struct PriceListRowFormView: View {
    let mode: PriceListRowFormMode
    let priceListId: String
    let listCurrency: String
    let categories: [TaskCategory]
    let onSave: (PriceListRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var serviceType: ServiceType = .remote
    @State private var timeType: TimeType = .regular
    @State private var categoryId: String = ""  // boş = tüm kategoriler
    @State private var unitPriceText: String = "0,00"
    @State private var isActive: Bool = true
    @State private var notes: String = ""
    @State private var existingId: String = UUID().uuidString
    @State private var existingCreatedAt: Date = Date()
    @State private var errorMessage: String?

    private var serviceOptions: [PickerOption] {
        ServiceType.allCases.map { PickerOption(id: $0.rawValue, title: $0.title) }
    }

    private var timeTypeOptions: [PickerOption] {
        TimeType.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { PickerOption(id: $0.rawValue, title: $0.title) }
    }

    private var categoryOptions: [PickerOption] {
        [PickerOption(id: "", title: settingsStore.localized("priceLists.rows.allCategories", defaultValue: "Tüm kategoriler"))] +
            categories.map { PickerOption(id: $0.id, title: $0.name) }
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: String(format: settingsStore.localized("priceLists.rows.form.subtitle", defaultValue: "%@ listesi"), listCurrency),
            systemImage: "tablecells",
            width: 720,
            height: 560
        ) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                SettingsFormError(message: errorMessage)

                SettingsFormRow(settingsStore.localized("priceLists.rows.form.serviceType", defaultValue: "Hizmet Tipi"), required: true, labelWidth: 170) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("serviceType.remote", defaultValue: "Uzaktan"),
                        items: serviceOptions,
                        selectedId: serviceTypeBinding,
                        showsSearch: false,
                        systemImage: "wifi",
                        itemTitle: { $0.title },
                        matchesSearch: { $0.title.localizedCaseInsensitiveContains($1) }
                    )
                    .frame(maxWidth: 240)
                }

                SettingsFormRow(settingsStore.localized("priceLists.rows.form.timeType", defaultValue: "Zaman Tipi"), required: true, labelWidth: 170) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("timeType.regular", defaultValue: "Mesai İçi"),
                        items: timeTypeOptions,
                        selectedId: timeTypeBinding,
                        showsSearch: false,
                        systemImage: "clock",
                        itemTitle: { $0.title },
                        matchesSearch: { $0.title.localizedCaseInsensitiveContains($1) }
                    )
                    .frame(maxWidth: 240)
                }

                SettingsFormRow(settingsStore.localized("priceLists.rows.form.category", defaultValue: "Kategori"), labelWidth: 170) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("priceLists.rows.allCategories", defaultValue: "Tüm kategoriler"),
                        items: categoryOptions,
                        selectedId: $categoryId,
                        showsSearch: categories.count > 8,
                        systemImage: "tag",
                        itemTitle: { $0.title },
                        matchesSearch: { $0.title.localizedCaseInsensitiveContains($1) }
                    )
                    .frame(maxWidth: 320)
                }

                SettingsFormRow(String(format: settingsStore.localized("priceLists.rows.form.hourlyRate", defaultValue: "Saatlik Ücret (%@)"), listCurrency), required: true, labelWidth: 170) {
                    ProWorkNumberField(
                        placeholder: pricePlaceholder,
                        text: $unitPriceText,
                        style: .decimal(maxFractionDigits: 2)
                    )
                        .frame(maxWidth: 200)
                }

                SettingsFormRow(settingsStore.localized("priceLists.column.active", defaultValue: "Aktif"), labelWidth: 170) {
                    Toggle("", isOn: $isActive).toggleStyle(.switch).labelsHidden()
                }

                SettingsFormRow(settingsStore.localized("priceLists.form.notes", defaultValue: "Notlar"), alignment: .top, labelWidth: 170) {
                    ProWorkTextEditor(text: $notes, minHeight: 60)
                        .frame(maxWidth: 440)
                }

                Spacer(minLength: 0)
            }
        } footer: {
            SettingsFormFooter(onCancel: { dismiss() }, onSave: save)
        }
        .onAppear { applyMode() }
    }

    private var serviceTypeBinding: Binding<String> {
        Binding(
            get: { serviceType.rawValue },
            set: { serviceType = ServiceType(rawValue: $0) ?? .remote }
        )
    }

    private var timeTypeBinding: Binding<String> {
        Binding(
            get: { timeType.rawValue },
            set: { timeType = TimeType(rawValue: $0) ?? .regular }
        )
    }

    private var priceFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = settingsStore.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }

    private var pricePlaceholder: String {
        priceFormatter.string(from: 1500.0 as NSNumber) ?? "1500.00"
    }

    private func applyMode() {
        if case .edit(let row) = mode {
            existingId = row.id
            existingCreatedAt = row.createdAt
            serviceType = row.serviceType
            timeType = row.timeType
            categoryId = row.categoryId ?? ""
            unitPriceText = priceFormatter.string(from: NSDecimalNumber(decimal: Money(minorUnits: row.unitPriceMinor, currency: listCurrency).amount)) ?? NSDecimalNumber(decimal: Money(minorUnits: row.unitPriceMinor, currency: listCurrency).amount).stringValue
            isActive = row.isActive
            notes = row.notes ?? ""
        }
    }

    private func save() {
        let formatter = priceFormatter

        guard let number = formatter.number(from: unitPriceText) else {
            errorMessage = settingsStore.localized("priceLists.rows.form.error.invalidUnitPrice", defaultValue: "Birim ücret geçersiz.")
            return
        }
        let amount = number.decimalValue
        let unitMoney = Money(amount: amount, currency: listCurrency)
        let unitMinor = unitMoney.minorUnits

        guard unitMinor >= 0 else {
            errorMessage = settingsStore.localized("priceLists.rows.form.error.negativeUnitPrice", defaultValue: "Birim ücret negatif olamaz.")
            return
        }

        let row = PriceListRow(
            id: existingId,
            priceListId: priceListId,
            serviceType: serviceType,
            timeType: timeType,
            categoryId: categoryId.isEmpty ? nil : categoryId,
            weekdayMask: nil,
            startTime: nil,
            endTime: nil,
            unitPriceMinor: unitMinor,
            currency: listCurrency,
            minimumWindowMinutes: nil,
            isActive: isActive,
            sortOrder: timeType.sortOrder,
            notes: notes.isEmpty ? nil : notes,
            organizationId: BuiltInOrganizationId.default,
            createdAt: existingCreatedAt
        )

        onSave(row)
        dismiss()
    }
}
