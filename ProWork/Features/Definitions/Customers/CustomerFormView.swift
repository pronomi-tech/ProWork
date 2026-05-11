//
//  CustomerFormView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct CustomerFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var id: String = UUID().uuidString
    @State private var name: String = ""
    @State private var code: String = ""
    @State private var contactPerson: String = ""
    @State private var address: String = ""
    @State private var isActive: Bool = true
    @State private var defaultPriceListId: String = ""
    @State private var serviceType: String = "remote"
    @State private var minBillingMinutes: Int = 0
    @State private var vatRateId: String = ""
    @State private var notes: String = ""
    @State private var createdAt: Date = Date()
    @State private var confirmation: ProWorkConfirmation?
    @State private var priceListOptions: [SearchPickerOption] = []
    @State private var vatRateOptions: [SearchPickerOption] = []
    @State private var vatRatePlaceholder: String = ""

    let mode: CustomerFormMode
    let onSave: (Customer) -> Void

    private let priceListRepository = PriceListRepository()
    private var serviceTypeOptions: [SearchPickerOption] {
        [
            SearchPickerOption(id: ServiceType.remote.rawValue, title: ServiceType.remote.title),
            SearchPickerOption(id: ServiceType.onsite.rawValue, title: ServiceType.onsite.title)
        ]
    }

    private var minBillingOptions: [SearchPickerOption] {
        [0, 15, 30, 45, 60, 90, 120, 150, 180].map { minutes in
            SearchPickerOption(
                id: String(minutes),
                title: minutes == 0
                    ? settingsStore.localized("customers.form.minBilling.none", defaultValue: "Min Zaman Yok")
                    : String(format: settingsStore.localized("customers.form.minutes", defaultValue: "%d dk"), minutes)
            )
        }
    }

    private var minBillingBinding: Binding<String> {
        Binding(
            get: { String(minBillingMinutes) },
            set: { minBillingMinutes = Int($0) ?? 60 }
        )
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            systemImage: "person.2",
            width: 580,
            height: 780
        ) {
            formFields
        } footer: {
            footer
        }
        .onAppear {
            loadInitialValues()
            loadPriceListOptions()
            loadVatRateOptions()
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
            formRow(label: settingsStore.localized("customers.form.name", defaultValue: "Müşteri Adı")) {
                ProWorkTextField(
                    placeholder: settingsStore.localized("customers.form.name.placeholder", defaultValue: "Örn: ABC Makine"),
                    text: $name,
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("customers.form.code", defaultValue: "Müşteri Kodu")) {
                ProWorkTextField(
                    placeholder: settingsStore.localized("customers.form.code.placeholder", defaultValue: "Örn: ABC"),
                    text: $code,
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(180, using: settingsStore))
            }

            formRow(label: settingsStore.localized("customers.form.contactPerson", defaultValue: "İlgili Kişi")) {
                ProWorkTextField(
                    placeholder: "",
                    text: $contactPerson,
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("customers.form.address", defaultValue: "Adres"), alignment: .top) {
                ProWorkTextEditor(
                    placeholder: settingsStore.localized("customers.form.address.placeholder", defaultValue: "Opsiyonel posta adresi"),
                    text: $address,
                    minHeight: 60
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("customers.form.serviceType", defaultValue: "Varsayılan Hizmet")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("customers.form.serviceType.placeholder", defaultValue: "Hizmet türü seçin"),
                    items: serviceTypeOptions,
                    selectedId: $serviceType,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "briefcase",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(260, using: settingsStore))
            }

            formRow(label: settingsStore.localized("customers.form.minBilling", defaultValue: "Min. Zaman Penceresi")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("customers.form.minBilling.placeholder", defaultValue: "Süre seçin"),
                    items: minBillingOptions,
                    selectedId: minBillingBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "clock",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(260, using: settingsStore))
            }

            formRow(label: settingsStore.localized("customers.form.defaultPriceList", defaultValue: "Öntanımlı Fiyat Listesi")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("customers.form.defaultPriceList.placeholder", defaultValue: "Fiyat listesi seçin"),
                    items: priceListOptions,
                    selectedId: $defaultPriceListId,
                    isDisabled: priceListOptions.isEmpty,
                    showsSearch: false,
                    systemImage: "list.bullet.rectangle.portrait",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("customers.form.vatRate", defaultValue: "KDV Oranı")) {
                ProWorkSearchPickerField(
                    placeholder: vatRatePlaceholder.isEmpty
                        ? settingsStore.localized("vat.picker.useDefault", defaultValue: "Varsayılan KDV")
                        : vatRatePlaceholder,
                    items: vatRateOptions,
                    selectedId: $vatRateId,
                    isDisabled: vatRateOptions.isEmpty,
                    showsSearch: vatRateOptions.count > 8,
                    allowsClearingSelection: true,
                    systemImage: "percent",
                    itemTitle: { $0.title },
                    itemSubtitle: { $0.subtitle },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("priceLists.column.active", defaultValue: "Aktif")) {
                ProWorkCheckbox(isOn: $isActive, boxSize: 22)
            }

            formRow(label: settingsStore.localized("priceLists.form.notes", defaultValue: "Notlar"), alignment: .top) {
                ProWorkTextEditor(
                    placeholder: settingsStore.localized("customers.form.notes.placeholder", defaultValue: "Opsiyonel not"),
                    text: $notes,
                    minHeight: 80
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }
        }
    }

    private func formRow<Content: View>(
        label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.callout, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: ProWorkLayout.formScaled(160, using: settingsStore), alignment: .leading)

            HStack {
                content()
                Spacer(minLength: 0)
            }
            .frame(width: ProWorkLayout.formScaled(340, using: settingsStore), alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        ProWorkFormFooter(
            onCancel: { dismiss() },
            onSave: { save() },
            saveTitle: mode.saveButtonTitle(using: settingsStore),
            saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || defaultPriceListId.isEmpty
        )
    }

    private func loadInitialValues() {
        guard case .edit(let customer) = mode else {
            return
        }

        id = customer.id
        name = customer.name
        code = customer.code ?? ""
        contactPerson = customer.contactPerson ?? ""
        address = customer.address ?? ""
        isActive = customer.isActive
        defaultPriceListId = customer.defaultPriceListId ?? ""
        serviceType = customer.defaultServiceType
        minBillingMinutes = customer.defaultMinBillingMinutes
        vatRateId = customer.vatRateId ?? ""
        notes = customer.notes ?? ""
        createdAt = customer.createdAt
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContact = contactPerson.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty else {
            return
        }

        let normalizedDefaultPriceListId = normalizedDefaultPriceListSelection()
        guard normalizedDefaultPriceListId != nil else {
            return
        }

        let customer = Customer(
            id: id,
            name: cleanName,
            code: cleanCode.isEmpty ? nil : cleanCode,
            contactPerson: cleanContact.isEmpty ? nil : cleanContact,
            address: cleanAddress.isEmpty ? nil : cleanAddress,
            isActive: isActive,
            defaultPriceListId: normalizedDefaultPriceListId,
            defaultServiceType: serviceType,
            defaultMinBillingMinutes: minBillingMinutes,
            vatRateId: vatRateId.isEmpty ? nil : vatRateId,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            createdAt: createdAt,
            updatedAt: Date()
        )

        switch mode {
        case .create:
            onSave(customer)

        case .edit:
            confirmation = ProWorkConfirmation(
                title: settingsStore.localized("customers.form.confirm.title", defaultValue: "Değişiklikler kaydedilsin mi?"),
                message: settingsStore.localized("customers.form.confirm.message", defaultValue: "Müşteri kartındaki değişiklikler kaydedilecek."),
                confirmTitle: settingsStore.localized("common.save", defaultValue: "Kaydet"),
                cancelTitle: settingsStore.localized("customers.delete.cancel", defaultValue: "Vazgeç")
            ) {
                onSave(customer)
            }
        }
    }

    private func loadPriceListOptions() {
        let globalLists = (try? priceListRepository.fetchOwned(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .global,
            ownerId: nil
        )) ?? []
        let customerLists = (try? priceListRepository.fetchOwned(
            organizationId: BuiltInOrganizationId.default,
            ownerType: .customer,
            ownerId: id
        )) ?? []

        let globalOptions = globalLists.map { list in
            SearchPickerOption(
                id: list.id,
                title: listOptionTitle(
                    scope: settingsStore.localized("customers.form.priceListScope.global", defaultValue: "Genel"),
                    list: list
                )
            )
        }
        let customerOptions = customerLists.map { list in
            SearchPickerOption(
                id: list.id,
                title: listOptionTitle(
                    scope: settingsStore.localized("customers.form.priceListScope.customer", defaultValue: "Müşteriye Özel"),
                    list: list
                )
            )
        }

        priceListOptions = globalOptions + customerOptions

        let defaultGlobalListId = globalLists.first(where: \.isDefault)?.id
        let firstAvailableListId = priceListOptions.first?.id

        if defaultPriceListId.isEmpty {
            defaultPriceListId = defaultGlobalListId ?? firstAvailableListId ?? ""
        } else if !priceListOptions.contains(where: { $0.id == defaultPriceListId }) {
            defaultPriceListId = defaultGlobalListId ?? firstAvailableListId ?? ""
        }
    }

    private func normalizedDefaultPriceListSelection() -> String? {
        let cleanSelection = defaultPriceListId.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanSelection.isEmpty ? nil : cleanSelection
    }

    private func loadVatRateOptions() {
        let content = VatRateLabel.pickerContent(
            organizationId: BuiltInOrganizationId.default,
            settingsStore: settingsStore
        )
        vatRateOptions = content.options
        vatRatePlaceholder = content.defaultPlaceholder
        if !vatRateId.isEmpty, !vatRateOptions.contains(where: { $0.id == vatRateId }) {
            vatRateId = ""
        }
    }

    private func listOptionTitle(scope: String, list: PriceList) -> String {
        var tags: [String] = [scope, list.name, list.currency]
        if list.isDefault {
            tags.append(settingsStore.localized("priceLists.defaultBadge", defaultValue: "Varsayılan"))
        }
        if !list.isActive {
            tags.append(settingsStore.localized("customers.status.inactive", defaultValue: "Pasif"))
        }
        return tags.joined(separator: " • ")
    }
}
