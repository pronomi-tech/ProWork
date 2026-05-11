//
//  TodoFormView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct TodoFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var id: String = UUID().uuidString
    @State private var customerId: String = ""
    @State private var projectId: String = ""
    @State private var categoryId: String = ""
    @State private var statusId: String = BuiltInTodoStatusId.waiting
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: String = "normal"
    @State private var estimatedMinutesText: String = ""
    @State private var isBillable: Bool = true

    @State private var hasPlannedDate: Bool = false
    @State private var plannedDate: Date = Date()

    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()

    @State private var createdAt: Date = Date()
    @State private var completedAt: Date?
    @State private var confirmation: ProWorkConfirmation?

    // MARK: - Billing override (yalnızca düzenleme modunda)
    @State private var hasBillingOverride: Bool = false
    @State private var billingOverrideType: TodoBillingOverrideType = .unitPrice
    @State private var billingOverrideAmountText: String = ""
    @State private var billingOverrideCurrency: String = "TRY"
    @State private var billingOverrideRecord: TodoBillingOverride?
    @State private var hasCustomBillingOverrideCurrency: Bool = false

    private let billingOverrideRepository = TodoBillingOverrideRepository()
    private let currencyResolver = PricingCurrencyResolver()
    private let organizationRepository = OrganizationRepository()

    let mode: TodoFormMode
    let customers: [Customer]
    let projects: [ProjectListItem]
    let categories: [TaskCategory]
    let statuses: [TodoStatus]
    let onSave: (Todo) -> Void

    private func formW(_ value: CGFloat) -> CGFloat {
        ProWorkLayout.formScaled(value, using: settingsStore)
    }

    private func formH(_ value: CGFloat) -> CGFloat {
        ProWorkLayout.formScaled(value, using: settingsStore)
    }

    private var filteredProjects: [ProjectListItem] {
        guard !customerId.isEmpty else {
            return []
        }

        return projects.filter { $0.customerId == customerId }
    }

    private var activeStatuses: [TodoStatus] {
        statuses.filter { $0.isActive }
    }

    private var customerOptions: [TodoFormSelectOption] {
        [
            TodoFormSelectOption(
                id: "",
                title: settingsStore.localized("todoForm.customer.none", defaultValue: "İdari / müşteri yok"),
                subtitle: nil,
                systemColorName: nil
            )
        ] + customers.map { customer in
            TodoFormSelectOption(
                id: customer.id,
                title: customer.name,
                subtitle: nil,
                systemColorName: nil
            )
        }
    }

    private var projectOptions: [TodoFormSelectOption] {
        [
            TodoFormSelectOption(
                id: "",
                title: settingsStore.localized("todoForm.project.none", defaultValue: "Proje yok"),
                subtitle: nil,
                systemColorName: nil
            )
        ] + filteredProjects.map { project in
            TodoFormSelectOption(
                id: project.id,
                title: project.name,
                subtitle: project.customerName,
                systemColorName: nil
            )
        }
    }

    private var categoryOptions: [TodoFormSelectOption] {
        categories.map { category in
            TodoFormSelectOption(
                id: category.id,
                title: category.name,
                subtitle: category.isBillableDefault
                    ? settingsStore.localized("todos.quick.category.billableDefault", defaultValue: "Varsayılan: Faturalandırılır")
                    : settingsStore.localized("todos.quick.category.administrativeDefault", defaultValue: "Varsayılan: İdari"),
                systemColorName: category.color
            )
        }
    }

    private var statusOptions: [TodoFormSelectOption] {
        activeStatuses.map { status in
            TodoFormSelectOption(
                id: status.id,
                title: status.name,
                subtitle: statusSubtitle(status),
                systemColorName: status.color
            )
        }
    }

    private var priorityOptions: [TodoFormSelectOption] {
        [
            TodoFormSelectOption(
                id: "low",
                title: ProWorkLabels.priorityTitle("low"),
                subtitle: nil,
                systemColorName: nil
            ),
            TodoFormSelectOption(
                id: "normal",
                title: ProWorkLabels.priorityTitle("normal"),
                subtitle: nil,
                systemColorName: nil
            ),
            TodoFormSelectOption(
                id: "high",
                title: ProWorkLabels.priorityTitle("high"),
                subtitle: nil,
                systemColorName: "orange"
            ),
            TodoFormSelectOption(
                id: "urgent",
                title: ProWorkLabels.priorityTitle("urgent"),
                subtitle: nil,
                systemColorName: "red"
            )
        ]
    }

    private var currencyOptions: [TodoFormSelectOption] {
        Currency.allCodes.map { code in
            let info = Currency.info(for: code)
            return TodoFormSelectOption(
                id: code,
                title: code,
                subtitle: info.displayName,
                systemColorName: nil
            )
        }
    }

    private var billingOverrideCurrencyBinding: Binding<String> {
        Binding(
            get: { billingOverrideCurrency },
            set: { newValue in
                hasCustomBillingOverrideCurrency = true
                billingOverrideCurrency = newValue
            }
        )
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: formSubtitle,
            systemImage: "checklist",
            width: 680,
            height: 860
        ) {
            formFields
        } footer: {
            footer
        }
        .onAppear {
            loadInitialValues()
        }
        .onChange(of: customerId) { _, _ in
            if !filteredProjects.contains(where: { $0.id == projectId }) {
                projectId = ""
            }
            refreshSuggestedBillingOverrideCurrency()
        }
        .onChange(of: projectId) { _, _ in
            refreshSuggestedBillingOverrideCurrency()
        }
        .onChange(of: hasBillingOverride) { _, enabled in
            if enabled {
                refreshSuggestedBillingOverrideCurrency()
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var formSubtitle: String {
        switch mode {
        case .create:
            return settingsStore.localized("todoForm.subtitle.create", defaultValue: "Yeni yapılacak iş bilgilerini girin.")
        case .edit:
            return settingsStore.localized("todoForm.subtitle.edit", defaultValue: "Yapılacak iş bilgilerini düzenleyin.")
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: formH(14)) {
            formRow(label: settingsStore.localized("todoForm.title", defaultValue: "Başlık"), alignment: .center) {
                ProWorkTextField(
                    placeholder: "",
                    text: $title,
                    minHeight: 40
                )
                .frame(width: formW(430))
            }

            formRow(label: settingsStore.localized("projects.form.customer", defaultValue: "Müşteri"), alignment: .center) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("projects.form.customer.placeholder", defaultValue: "Müşteri seçiniz"),
                    items: customerOptions,
                    selectedId: $customerId,
                    isDisabled: false,
                    showsSearch: customers.count > 8,
                    systemImage: "person.2",
                    itemTitle: { item in
                        item.title
                    },
                    itemSubtitle: { item in
                        item.subtitle
                    },
                    itemColor: { item in
                        ProWorkColors.fromName(item.systemColorName)
                    },
                    matchesSearch: { item, searchText in
                        item.title.localizedCaseInsensitiveContains(searchText) ||
                        (item.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                    }
                )
                .frame(width: formW(360))
            }

            formRow(label: settingsStore.localized("priceLists.owner.project", defaultValue: "Proje"), alignment: .center) {
                ProWorkSearchPickerField(
                    placeholder: customerId.isEmpty
                        ? settingsStore.localized("todoForm.project.selectCustomerFirst", defaultValue: "Önce müşteri seçin")
                        : settingsStore.localized("todoForm.project.placeholder", defaultValue: "Proje seçin"),
                    items: projectOptions,
                    selectedId: $projectId,
                    isDisabled: customerId.isEmpty,
                    showsSearch: filteredProjects.count > 8,
                    systemImage: "folder",
                    itemTitle: { item in
                        item.title
                    },
                    itemSubtitle: { item in
                        item.subtitle
                    },
                    itemColor: { item in
                        ProWorkColors.fromName(item.systemColorName)
                    },
                    matchesSearch: { item, searchText in
                        item.title.localizedCaseInsensitiveContains(searchText) ||
                        (item.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                    }
                )
                .frame(width: formW(360))
            }

            formRow(label: settingsStore.localized("reports.todo.table.category", defaultValue: "Kategori"), alignment: .center) {
                ProWorkSearchPickerField(
                    placeholder: categories.isEmpty
                        ? settingsStore.localized("todoForm.category.none", defaultValue: "Kategori yok")
                        : settingsStore.localized("todoForm.category.placeholder", defaultValue: "Kategori seçin"),
                    items: categoryOptions,
                    selectedId: $categoryId,
                    isDisabled: categories.isEmpty,
                    showsSearch: categories.count > 8,
                    systemImage: "tag",
                    itemTitle: { item in
                        item.title
                    },
                    itemSubtitle: { item in
                        item.subtitle
                    },
                    itemColor: { item in
                        ProWorkColors.fromName(item.systemColorName)
                    },
                    matchesSearch: { item, searchText in
                        item.title.localizedCaseInsensitiveContains(searchText) ||
                        (item.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                    }
                )
                .frame(width: formW(320))
            }

            formRow(label: settingsStore.localized("projects.form.status", defaultValue: "Durum"), alignment: .center) {
                ProWorkSearchPickerField(
                    placeholder: statuses.isEmpty
                        ? settingsStore.localized("todoForm.status.none", defaultValue: "Durum yok")
                        : settingsStore.localized("projects.form.status.placeholder", defaultValue: "Durum seçin"),
                    items: statusOptions,
                    selectedId: $statusId,
                    isDisabled: activeStatuses.isEmpty,
                    showsSearch: activeStatuses.count > 8,
                    systemImage: "rectangle.3.group",
                    itemTitle: { item in
                        item.title
                    },
                    itemSubtitle: { item in
                        item.subtitle
                    },
                    itemColor: { item in
                        ProWorkColors.fromName(item.systemColorName)
                    },
                    matchesSearch: { item, searchText in
                        item.title.localizedCaseInsensitiveContains(searchText) ||
                        (item.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                    }
                )
                .frame(width: formW(320))
            }

            formRow(label: settingsStore.localized("todoForm.priority", defaultValue: "Öncelik"), alignment: .center) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("todoForm.priority.placeholder", defaultValue: "Öncelik seçin"),
                    items: priorityOptions,
                    selectedId: $priority,
                    isDisabled: false,
                    showsSearch: false,
                    systemImage: "flag",
                    itemTitle: { item in
                        item.title
                    },
                    itemSubtitle: { item in
                        item.subtitle
                    },
                    itemColor: { item in
                        ProWorkColors.fromName(item.systemColorName)
                    },
                    matchesSearch: { item, searchText in
                        item.title.localizedCaseInsensitiveContains(searchText)
                    }
                )
                .frame(width: formW(240))
            }

            formRow(label: settingsStore.localized("todoForm.estimated", defaultValue: "Tahmini Süre"), alignment: .center) {
                HStack(spacing: formW(8)) {
                    ProWorkNumberField(
                        placeholder: settingsStore.localized("todoForm.estimated.placeholder", defaultValue: "60"),
                        text: $estimatedMinutesText,
                        style: .integer(),
                        minHeight: 40
                    )
                    .frame(width: formW(100))

                    Text(settingsStore.localized("todoForm.estimated.minutes", defaultValue: "dk"))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            formRow(label: settingsStore.localized("todoForm.plannedDate", defaultValue: "Planlanan Tarih"), alignment: .center) {
                optionalDateField(
                    isEnabled: $hasPlannedDate,
                    date: $plannedDate,
                    placeholder: settingsStore.localized("todoForm.plannedDate.placeholder", defaultValue: "Planlanan tarih seçin")
                )
            }

            formRow(label: settingsStore.localized("todoForm.dueDate", defaultValue: "Termin"), alignment: .center) {
                optionalDateField(
                    isEnabled: $hasDueDate,
                    date: $dueDate,
                    placeholder: settingsStore.localized("todoForm.dueDate.placeholder", defaultValue: "Termin seçin")
                )
            }

            formRow(label: settingsStore.localized("todoForm.billing", defaultValue: "Faturalandırma"), alignment: .center) {
                ProWorkCheckbox(
                    settingsStore.localized("todos.billable", defaultValue: "Faturalandırılır"),
                    isOn: $isBillable,
                    boxSize: 22
                )
            }

            // Özel Ücret — yalnızca düzenleme modunda (todo henüz DB'de yoksa override eklenemez)
            if isEditMode, isBillable {
                formRow(label: settingsStore.localized("todoForm.billingOverride", defaultValue: "Özel Ücret"), alignment: .top) {
                    billingOverrideField
                }
            }

            formRow(label: settingsStore.localized("todoForm.description", defaultValue: "Açıklama"), alignment: .top) {
                ProWorkTextEditor(
                    placeholder: settingsStore.localized("todoForm.description.placeholder", defaultValue: "Opsiyonel açıklama"),
                    text: $description,
                    minHeight: 92
                )
                .frame(width: formW(430))
            }
        }
    }

    private var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    @ViewBuilder
    private var billingOverrideField: some View {
        VStack(alignment: .leading, spacing: formH(8)) {
            ProWorkCheckbox(
                settingsStore.localized("todoForm.billingOverride.toggle", defaultValue: "Bu görev için özel ücret kullan"),
                isOn: $hasBillingOverride,
                boxSize: 22
            )

            if hasBillingOverride {
                Picker("", selection: $billingOverrideType) {
                    Text(settingsStore.localized("todoForm.billingOverride.unitPrice", defaultValue: "Birim Ücret")).tag(TodoBillingOverrideType.unitPrice)
                    Text(settingsStore.localized("todoForm.billingOverride.fixedFee", defaultValue: "Sabit Tutar")).tag(TodoBillingOverrideType.fixedFee)
                }
                .pickerStyle(.segmented)
                .frame(width: formW(360))

                HStack(spacing: formW(8)) {
                    Text(
                        billingOverrideType == .unitPrice
                        ? settingsStore.localized("todoForm.billingOverride.hourly", defaultValue: "Saatlik:")
                        : settingsStore.localized("todoForm.billingOverride.total", defaultValue: "Toplam:")
                    )
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)

                    ProWorkNumberField(
                        placeholder: "",
                        text: $billingOverrideAmountText,
                        style: .decimal(maxFractionDigits: 4),
                        minHeight: 32
                    )
                    .frame(width: formW(150))

                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("todoForm.billingOverride.currency", defaultValue: "Para birimi"),
                        items: currencyOptions,
                        selectedId: billingOverrideCurrencyBinding,
                        isDisabled: false,
                        showsSearch: false,
                        systemImage: "banknote",
                        itemTitle: { item in
                            item.title
                        },
                        itemSubtitle: { item in
                            item.subtitle
                        },
                        itemColor: { item in
                            ProWorkColors.fromName(item.systemColorName)
                        },
                        matchesSearch: { item, searchText in
                            item.title.localizedCaseInsensitiveContains(searchText) ||
                            (item.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                        }
                    )
                    .frame(width: formW(180))
                }

                Text(
                    billingOverrideType == .unitPrice
                    ? settingsStore.localized("todoForm.billingOverride.help.unitPrice", defaultValue: "Bu görevdeki çalışmalar fiyat listesi yerine bu saatlik ücretle hesaplanır.")
                    : settingsStore.localized("todoForm.billingOverride.help.fixedFee", defaultValue: "Bu görev için süre fark etmeksizin tek tutar uygulanır.")
                )
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: formW(430), alignment: .leading)
            }
        }
    }

    private func formRow<Content: View>(
        label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: formW(16)) {
            Text(label)
                .proWorkTextStyle(.callout, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: formW(150), alignment: .leading)

            HStack {
                content()
                Spacer(minLength: 0)
            }
            .frame(width: formW(450), alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionalDateField(
        isEnabled: Binding<Bool>,
        date: Binding<Date>,
        placeholder: String
    ) -> some View {
        HStack(spacing: formW(10)) {
            ProWorkCheckbox(
                isOn: isEnabled,
                boxSize: 22
            )

            if isEnabled.wrappedValue {
                ProWorkDateField(
                    title: "",
                    date: date
                )
                .frame(width: formW(240), alignment: .leading)
            } else {
                HStack(spacing: formW(8)) {
                    Image(systemName: "calendar.badge.clock")
                        .proWorkFont(size: 15)
                        .foregroundStyle(.secondary)

                    Text(placeholder)
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, formW(12))
                .padding(.vertical, formH(6))
                .frame(minHeight: formH(40), alignment: .leading)
                .frame(width: formW(240), alignment: .leading)
                .background(.background.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: formW(10)))
                .overlay(
                    RoundedRectangle(cornerRadius: formW(10))
                        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                )
            }
        }
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
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !categoryId.isEmpty
    }

    private func statusSubtitle(_ status: TodoStatus) -> String? {
        var parts: [String] = []

        if status.startsTimer {
            parts.append(settingsStore.localized("todoForm.status.startsTimer", defaultValue: "Süre başlatır"))
        }

        if status.stopsTimer {
            parts.append(settingsStore.localized("todoForm.status.stopsTimer", defaultValue: "Süre durdurur"))
        }

        if status.marksCompleted {
            parts.append(settingsStore.localized("projects.status.completed", defaultValue: "Tamamlandı"))
        }

        if status.marksCancelled {
            parts.append(settingsStore.localized("todoForm.status.cancelled", defaultValue: "İptal"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func loadInitialValues() {
        if categoryId.isEmpty {
            categoryId = categories.first?.id ?? ""
        }

        if statusId.isEmpty || !statuses.contains(where: { $0.id == statusId }) {
            statusId = statuses.first(where: { $0.id == BuiltInTodoStatusId.waiting })?.id
                ?? statuses.first?.id
                ?? BuiltInTodoStatusId.waiting
        }

        guard case .edit(let todo) = mode else {
            return
        }

        id = todo.id
        customerId = todo.customerId ?? ""
        projectId = todo.projectId ?? ""
        categoryId = todo.categoryId
        statusId = todo.statusId

        if !statuses.contains(where: { $0.id == statusId }) {
            statusId = statuses.first(where: { $0.id == BuiltInTodoStatusId.waiting })?.id
                ?? statuses.first?.id
                ?? BuiltInTodoStatusId.waiting
        }

        title = todo.title
        description = todo.description ?? ""
        priority = todo.priority
        estimatedMinutesText = todo.estimatedMinutes.map(String.init) ?? ""
        isBillable = todo.isBillable
        createdAt = todo.createdAt
        completedAt = todo.completedAt

        if let planned = todo.plannedDate {
            hasPlannedDate = true
            plannedDate = planned
        }

        if let due = todo.dueDate {
            hasDueDate = true
            dueDate = due
        }

        // Mevcut billing override varsa yükle
        if let override = try? billingOverrideRepository.fetch(todoId: todo.id) {
            billingOverrideRecord = override
            hasBillingOverride = true
            billingOverrideType = override.overrideType
            billingOverrideCurrency = override.currency
            hasCustomBillingOverrideCurrency = true
            switch override.overrideType {
            case .unitPrice:
                if let m = override.unitPriceMinor {
                    billingOverrideAmountText = ProWorkFormatters.moneyAmount(
                        Money(minorUnits: m, currency: override.currency)
                    )
                }
            case .fixedFee:
                if let m = override.fixedFeeMinor {
                    billingOverrideAmountText = ProWorkFormatters.moneyAmount(
                        Money(minorUnits: m, currency: override.currency)
                    )
                }
            }
        }

        refreshSuggestedBillingOverrideCurrency(force: !hasCustomBillingOverrideCurrency)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimatedMinutes = Int(estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !cleanTitle.isEmpty, !categoryId.isEmpty else {
            return
        }

        let selectedStatus = statuses.first { $0.id == statusId }

        let finalCompletedAt: Date?
        if selectedStatus?.marksCompleted == true {
            finalCompletedAt = completedAt ?? Date()
        } else {
            finalCompletedAt = nil
        }

        let todo = Todo(
            id: id,
            customerId: customerId.isEmpty ? nil : customerId,
            projectId: projectId.isEmpty ? nil : projectId,
            categoryId: categoryId,
            title: cleanTitle,
            description: cleanDescription.isEmpty ? nil : cleanDescription,
            statusId: statusId,
            priority: priority,
            plannedDate: hasPlannedDate ? plannedDate : nil,
            dueDate: hasDueDate ? dueDate : nil,
            estimatedMinutes: estimatedMinutes,
            isBillable: isBillable,
            completedAt: finalCompletedAt,
            createdAt: createdAt,
            updatedAt: Date()
        )

        switch mode {
        case .create:
            onSave(todo)

        case .edit:
            confirmation = ProWorkConfirmation(
                title: settingsStore.localized("todoForm.confirm.title", defaultValue: "Değişiklikler kaydedilsin mi?"),
                message: String(format: settingsStore.localized("todoForm.confirm.message", defaultValue: "“%@” yapılacak iş kaydındaki değişiklikler kaydedilecek."), todo.title),
                confirmTitle: settingsStore.localized("common.save", defaultValue: "Kaydet"),
                cancelTitle: settingsStore.localized("common.cancel", defaultValue: "Vazgeç")
            ) {
                persistBillingOverride(for: todo.id)
                onSave(todo)
            }
        }
    }

    /// Düzenleme modunda billing override'ı upsert/remove eder.
    private func persistBillingOverride(for todoId: String) {
        guard isEditMode else { return }

        if hasBillingOverride && isBillable {
            // Tutar parse
            let formatter = NumberFormatter()
            formatter.locale = settingsStore.locale
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 4

            guard let n = formatter.number(from: billingOverrideAmountText), n.decimalValue >= 0 else {
                return  // sessizce yoksay; UI seviyesi validation yok
            }
            let money = Money(amount: n.decimalValue, currency: billingOverrideCurrency)
            let minor = money.minorUnits

            let override = TodoBillingOverride(
                id: billingOverrideRecord?.id ?? UUID().uuidString,
                todoId: todoId,
                overrideType: billingOverrideType,
                unitPriceMinor: billingOverrideType == .unitPrice ? minor : nil,
                fixedFeeMinor: billingOverrideType == .fixedFee ? minor : nil,
                currency: billingOverrideCurrency,
                organizationId: BuiltInOrganizationId.default,
                createdAt: billingOverrideRecord?.createdAt ?? Date()
            )
            try? billingOverrideRepository.upsert(override)
        } else {
            // Override kapatıldı veya billable=false → soft-delete
            try? billingOverrideRepository.remove(todoId: todoId)
        }
    }

    private func refreshSuggestedBillingOverrideCurrency(force: Bool = false) {
        guard force || !hasCustomBillingOverrideCurrency else {
            return
        }

        let suggestedCurrency: String

        if !projectId.isEmpty,
           let project = projects.first(where: { $0.id == projectId }) {
            suggestedCurrency = (try? currencyResolver.resolveProjectCurrency(
                projectId: project.id,
                customerId: project.customerId,
                organizationId: BuiltInOrganizationId.default
            )) ?? "TRY"
        } else if !customerId.isEmpty {
            suggestedCurrency = (try? currencyResolver.resolveCustomerCurrency(
                customerId: customerId,
                organizationId: BuiltInOrganizationId.default
            )) ?? "TRY"
        } else {
            suggestedCurrency = (try? organizationRepository.fetchDefault()?.masterCurrency) ?? "TRY"
        }

        billingOverrideCurrency = suggestedCurrency
    }
}

private struct TodoFormSelectOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemColorName: String?
}
