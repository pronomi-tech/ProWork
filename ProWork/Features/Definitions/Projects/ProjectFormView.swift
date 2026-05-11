//
//  ProjectFormView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var id: String = UUID().uuidString
    @State private var customerId: String = ""
    @State private var name: String = ""
    @State private var code: String = ""
    @State private var status: String = "active"
    @State private var defaultServiceType: String = ""
    @State private var defaultMinBillingMinutes: Int = 0
    @State private var billingWindowMode: String = ""
    @State private var vatRateId: String = ""
    @State private var notes: String = ""
    @State private var createdAt: Date = Date()
    @State private var confirmation: ProWorkConfirmation?
    @State private var vatRateOptions: [SearchPickerOption] = []

    let mode: ProjectFormMode
    let customers: [Customer]
    let onSave: (Project) -> Void

    private var statusOptions: [SearchPickerOption] {
        [
            SearchPickerOption(id: "active", title: settingsStore.localized("projects.status.active", defaultValue: "Aktif")),
            SearchPickerOption(id: "passive", title: settingsStore.localized("projects.status.passive", defaultValue: "Pasif")),
            SearchPickerOption(id: "completed", title: settingsStore.localized("projects.status.completed", defaultValue: "Tamamlandı")),
            SearchPickerOption(id: "suspended", title: settingsStore.localized("projects.status.suspended", defaultValue: "Askıda"))
        ]
    }

    private var serviceTypeOptions: [SearchPickerOption] {
        [
            SearchPickerOption(id: "", title: settingsStore.localized("projects.form.serviceType.inheritCustomer", defaultValue: "Müşteri Ayarı Geçerli")),
            SearchPickerOption(id: ServiceType.remote.rawValue, title: ServiceType.remote.title),
            SearchPickerOption(id: ServiceType.onsite.rawValue, title: ServiceType.onsite.title)
        ]
    }

    private var minBillingOptions: [SearchPickerOption] {
        [0, 15, 30, 45, 60, 90, 120].map { minutes in
            SearchPickerOption(
                id: String(minutes),
                title: minutes == 0
                    ? settingsStore.localized("projects.form.minBilling.inheritCustomer", defaultValue: "Müşteri Ayarı Geçerli")
                    : String(format: settingsStore.localized("projects.form.minutes", defaultValue: "%d dk"), minutes)
            )
        }
    }

    private var billingWindowModeOptions: [SearchPickerOption] {
        [
            SearchPickerOption(id: "", title: settingsStore.localized("projects.form.billingWindow.inheritOrganization", defaultValue: "Organizasyon Ayarı Geçerli")),
            SearchPickerOption(id: BillingWindowMode.timeline.rawValue, title: BillingWindowMode.timeline.title),
            SearchPickerOption(id: BillingWindowMode.session.rawValue, title: BillingWindowMode.session.title)
        ]
    }

    private var customerOptions: [SearchPickerOption] {
        [SearchPickerOption(id: "", title: settingsStore.localized("projects.form.customer.placeholder", defaultValue: "Müşteri seçiniz"))] +
        customers.map { SearchPickerOption(id: $0.id, title: $0.name) }
    }

    private var minBillingBinding: Binding<String> {
        Binding(
            get: { String(defaultMinBillingMinutes) },
            set: { defaultMinBillingMinutes = Int($0) ?? 0 }
        )
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            systemImage: "folder",
            width: 580,
            height: 710
        ) {
            formFields
        } footer: {
            footer
        }
        .onAppear {
            loadInitialValues()
            loadVatRateOptions()
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
            formRow(label: settingsStore.localized("projects.form.customer", defaultValue: "Müşteri")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("projects.form.customer.placeholder", defaultValue: "Müşteri seçiniz"),
                    items: customerOptions,
                    selectedId: $customerId,
                    isDisabled: customers.isEmpty,
                    showsSearch: customers.count > 8,
                    systemImage: "person.2",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("projects.form.name", defaultValue: "Proje Adı")) {
                ProWorkTextField(
                    placeholder: "",
                    text: $name,
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("projects.form.code", defaultValue: "Proje Kodu")) {
                ProWorkTextField(
                    placeholder: "",
                    text: $code,
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(180, using: settingsStore))
            }

            formRow(label: settingsStore.localized("projects.form.status", defaultValue: "Durum")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("projects.form.status.placeholder", defaultValue: "Durum seçin"),
                    items: statusOptions,
                    selectedId: $status,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "circle.lefthalf.filled",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(180, using: settingsStore))
            }

            formRow(label: settingsStore.localized("projects.form.serviceType", defaultValue: "Varsayılan Hizmet")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("projects.form.serviceType.placeholder", defaultValue: "Hizmet türü seçin"),
                    items: serviceTypeOptions,
                    selectedId: $defaultServiceType,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "briefcase",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("projects.form.minBilling", defaultValue: "Min. Zaman Penceresi")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("projects.form.minBilling.placeholder", defaultValue: "Süre seçin"),
                    items: minBillingOptions,
                    selectedId: minBillingBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "clock",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("projects.form.billingWindow", defaultValue: "Pencere Akışı")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("projects.form.billingWindow.placeholder", defaultValue: "Akış seçin"),
                    items: billingWindowModeOptions,
                    selectedId: $billingWindowMode,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "arrow.left.arrow.right",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("projects.form.vatRate", defaultValue: "KDV Oranı")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized(
                        "vat.picker.useInherit",
                        defaultValue: "Müşteri/Varsayılan"
                    ),
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

            formRow(label: settingsStore.localized("priceLists.form.notes", defaultValue: "Notlar"), alignment: .top) {
                ProWorkTextEditor(
                    placeholder: settingsStore.localized("projects.form.notes.placeholder", defaultValue: "Opsiyonel not"),
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
                .frame(width: ProWorkLayout.formScaled(170, using: settingsStore), alignment: .leading)

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
            saveDisabled: !canSave
        )
    }

    private var canSave: Bool {
        !customerId.isEmpty &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadInitialValues() {
        if customerId.isEmpty {
            customerId = customers.first?.id ?? ""
        }

        guard case .edit(let project) = mode else {
            return
        }

        id = project.id
        customerId = project.customerId
        name = project.name
        code = project.code ?? ""
        status = project.status
        defaultServiceType = project.defaultServiceType ?? ""
        defaultMinBillingMinutes = project.defaultMinBillingMinutes ?? 0
        billingWindowMode = project.billingWindowMode?.rawValue ?? ""
        vatRateId = project.vatRateId ?? ""
        notes = project.notes ?? ""
        createdAt = project.createdAt
    }

    private func loadVatRateOptions() {
        let content = VatRateLabel.pickerContent(
            organizationId: BuiltInOrganizationId.default,
            settingsStore: settingsStore
        )
        vatRateOptions = content.options
        if !vatRateId.isEmpty, !vatRateOptions.contains(where: { $0.id == vatRateId }) {
            vatRateId = ""
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !customerId.isEmpty, !cleanName.isEmpty else {
            return
        }

        let project = Project(
            id: id,
            customerId: customerId,
            name: cleanName,
            code: cleanCode.isEmpty ? nil : cleanCode,
            status: status,
            defaultServiceType: defaultServiceType.isEmpty ? nil : defaultServiceType,
            defaultMinBillingMinutes: defaultMinBillingMinutes == 0 ? nil : defaultMinBillingMinutes,
            billingWindowMode: BillingWindowMode(rawValue: billingWindowMode),
            vatRateId: vatRateId.isEmpty ? nil : vatRateId,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            createdAt: createdAt,
            updatedAt: Date()
        )

        switch mode {
        case .create:
            onSave(project)

        case .edit:
            confirmation = ProWorkConfirmation(
                title: settingsStore.localized("projects.form.confirm.title", defaultValue: "Değişiklikler kaydedilsin mi?"),
                message: String(format: settingsStore.localized("projects.form.confirm.message", defaultValue: "'%@' proje kartındaki değişiklikler kaydedilecek."), project.name),
                confirmTitle: settingsStore.localized("common.save", defaultValue: "Kaydet"),
                cancelTitle: settingsStore.localized("projects.delete.cancel", defaultValue: "Vazgeç")
            ) {
                onSave(project)
            }
        }
    }
}
