//  TaskCategoryFormView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct TaskCategoryFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var id: String = UUID().uuidString
    @State private var name: String = ""
    @State private var color: String = "gray"
    @State private var isBillableDefault: Bool = true
    @State private var sortOrderText: String = "0"
    @State private var isSystem: Bool = false
    @State private var vatRateId: String = ""
    @State private var createdAt: Date = Date()
    @State private var confirmation: ProWorkConfirmation?
    @State private var vatRateOptions: [SearchPickerOption] = []
    @State private var vatRatePlaceholder: String = ""

    let mode: TaskCategoryFormMode
    let onSave: (TaskCategory) -> Void

    /// Routed through the shared `ProWorkColorPickerOptions`
    /// so this form and TodoStatusFormView can't drift on their
    /// color lists.
    private var colorOptions: [SearchPickerOption] {
        ProWorkColorPickerOptions.searchPickerOptions(localizer: settingsStore)
    }

    private var billableOptions: [SearchPickerOption] {
        [
            SearchPickerOption(id: "true", title: settingsStore.localized("taskCategories.type.billable", defaultValue: "Faturalandırılır")),
            SearchPickerOption(id: "false", title: settingsStore.localized("taskCategories.type.admin", defaultValue: "İdari"))
        ]
    }

    private var billableBinding: Binding<String> {
        Binding(
            get: { isBillableDefault ? "true" : "false" },
            set: { isBillableDefault = $0 == "true" }
        )
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            systemImage: "tag",
            width: FormSheetSize.taskCategoryForm.width,
            height: FormSheetSize.taskCategoryForm.height
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
            formRow(label: settingsStore.localized("taskCategories.form.name.label", defaultValue: "Kategori Adı")) {
                ProWorkTextField(
                    placeholder: settingsStore.localized("taskCategories.form.name.placeholder", defaultValue: "Örn: Eğitim"),
                    text: $name,
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(320, using: settingsStore))
            }

            formRow(label: settingsStore.localized("taskCategories.form.color.label", defaultValue: "Renk")) {
                HStack(spacing: ProWorkLayout.formScaled(10, using: settingsStore)) {
                    Circle()
                        .fill(ProWorkColors.fromName(color))
                        .frame(
                            width: ProWorkLayout.formScaled(14, using: settingsStore),
                            height: ProWorkLayout.formScaled(14, using: settingsStore)
                        )

                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("taskCategories.form.color.placeholder", defaultValue: "Renk seçin"),
                        items: colorOptions,
                        selectedId: $color,
                        isDisabled: false,
                        showsSearch: false,
                        systemImage: "paintpalette",
                        itemTitle: { $0.title },
                        itemColor: { item in ProWorkColors.fromName(item.id) },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.formScaled(200, using: settingsStore))
                }
            }

            formRow(label: settingsStore.localized("taskCategories.form.billable.label", defaultValue: "Varsayılan Tip")) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("taskCategories.form.billable.placeholder", defaultValue: "Tip seçin"),
                    items: billableOptions,
                    selectedId: billableBinding,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "creditcard",
                    itemTitle: { $0.title },
                    matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                )
                .frame(width: ProWorkLayout.formScaled(300, using: settingsStore))
            }

            formRow(label: settingsStore.localized("taskCategories.form.order.label", defaultValue: "Sıra")) {
                ProWorkNumberField(
                    placeholder: "0",
                    text: $sortOrderText,
                    style: .integer(),
                    minHeight: 40
                )
                .frame(width: ProWorkLayout.formScaled(90, using: settingsStore))
            }

            formRow(label: settingsStore.localized("taskCategories.form.vatRate", defaultValue: "KDV Oranı")) {
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
                .frame(width: ProWorkLayout.formScaled(300, using: settingsStore))
            }

            if isSystem {
                formRow(label: settingsStore.localized("taskCategories.form.system.label", defaultValue: "Sistem")) {
                    Text(settingsStore.localized("taskCategories.form.system.message", defaultValue: "Bu kategori sistem kategorisidir; silinemez."))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
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
                .frame(width: ProWorkLayout.formScaled(150, using: settingsStore), alignment: .leading)

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
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadInitialValues() {
        guard case .edit(let category) = mode else {
            return
        }

        id = category.id
        name = category.name
        color = category.color ?? "gray"
        isBillableDefault = category.isBillableDefault
        sortOrderText = "\(category.sortOrder)"
        isSystem = category.isSystem
        vatRateId = category.vatRateId ?? ""
        createdAt = category.createdAt
    }

    private func loadVatRateOptions() {
        let content = VatRateLabel.pickerContent(
            organizationId: BuiltInOrganizationId.default,
            repository: AppServices.shared.vatRateRepository
        )
        vatRateOptions = content.options
        vatRatePlaceholder = content.defaultPlaceholder
        if !vatRateId.isEmpty, !vatRateOptions.contains(where: { $0.id == vatRateId }) {
            vatRateId = ""
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrder = sortOrderText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Previously `Int(...) ?? 0` silently coerced
        // unparseable input to zero, so a typo flipped the row to the top
        // of the list without feedback. Empty input still means "use the
        // default 0"; non-empty unparseable input is surfaced.
        let sortOrder: Int
        if trimmedOrder.isEmpty {
            sortOrder = 0
        } else if let parsed = Int(trimmedOrder) {
            sortOrder = parsed
        } else {
            ProWorkToastStore.shared.show(
                settingsStore.localized(
                    "taskCategories.form.error.invalidSortOrder",
                    defaultValue: "Sıralama numarası tam sayı olmalı."
                ),
                style: .error
            )
            return
        }

        guard !cleanName.isEmpty else {
            return
        }

        let category = TaskCategory(
            id: id,
            name: cleanName,
            color: color,
            isBillableDefault: isBillableDefault,
            sortOrder: sortOrder,
            isSystem: isSystem,
            vatRateId: vatRateId.isEmpty ? nil : vatRateId,
            createdAt: createdAt,
            updatedAt: Date()
        )

        switch mode {
        case .create:
            onSave(category)

        case .edit:
            confirmation = ProWorkConfirmation(
                title: settingsStore.localized("taskCategories.form.confirm.title", defaultValue: "Değişiklikler kaydedilsin mi?"),
                message: String(format: settingsStore.localized("taskCategories.form.confirm.message", defaultValue: "'%@' görev kategorisindeki değişiklikler kaydedilecek."), category.name),
                confirmTitle: settingsStore.localized("taskCategories.form.confirm.save", defaultValue: "Kaydet"),
                cancelTitle: settingsStore.localized("taskCategories.form.confirm.cancel", defaultValue: "Vazgeç")
            ) {
                onSave(category)
            }
        }
    }
}
