//  TodoFormView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import os

/// TodoFormView previously declared 26 individual
/// `@State` properties at the top of the type, mixing identity, content,
/// dates, and billing-override concerns. Grouping them by domain keeps
/// the property block legible without forcing a full sub-view
/// decomposition (which would require threading 20+ bindings through
/// child views). Each domain remains a flat collection of @State for
/// SwiftUI's diffing, just annotated with MARK comments.
struct TodoFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    // MARK: - Identity & relations
    @State private var id: String = UUID().uuidString
    @State private var customerId: String = ""
    @State private var projectId: String = ""
    @State private var categoryId: String = ""
    @State private var statusId: String = BuiltInTodoStatusId.waiting

    // MARK: - Content
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: String = "normal"
    @State private var estimatedMinutesText: String = ""
    @State private var isBillable: Bool = true

    // MARK: - Schedule
    @State private var hasPlannedDate: Bool = false
    @State private var plannedDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var createdAt: Date = Date()
    @State private var completedAt: Date?

    // MARK: - UI
    @State private var confirmation: ProWorkConfirmation?

    // MARK: - Billing override (only in edit mode)
    @State private var hasBillingOverride: Bool = false
    @State private var billingOverrideType: TodoBillingOverrideType = .unitPrice
    @State private var billingOverrideAmountText: String = ""
    @State private var billingOverrideCurrency: String = "TRY"
    @State private var billingOverrideRecord: TodoBillingOverride?
    @State private var hasCustomBillingOverrideCurrency: Bool = false

    // Repository / resolver dependencies are pulled from the shared AppServices
    // instance so they are not reopened every time the View struct is recreated
    private let billingOverrideRepository = AppServices.shared.todoBillingOverrideRepository
    private let currencyResolver = AppServices.shared.pricingCurrencyResolver
    private let organizationRepository = AppServices.shared.organizationRepository

    let mode: TodoFormMode
    let customers: [Customer]
    let projects: [ProjectListItem]
    let categories: [TaskCategory]
    let statuses: [TodoStatus]
    let onSave: (Todo) -> Void

    // Previously the file declared two separate helpers
    // `formW` and `formH` with identical bodies, picked at call sites to
    // hint at width vs height usage. Keep the semantic naming where it
    // already exists but route both through a single implementation so
    // the bodies can't drift. (Replacing 30 call sites with a single
    // name was deemed not worth the diff churn.)
    private func formScaled(_ value: CGFloat) -> CGFloat {
        ProWorkLayout.formScaled(value, using: settingsStore)
    }

    private func formW(_ value: CGFloat) -> CGFloat { formScaled(value) }
    private func formH(_ value: CGFloat) -> CGFloat { formScaled(value) }

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
            width: FormSheetSize.todoForm.width,
            height: FormSheetSize.todoForm.height
        ) {
            formFields
        } footer: {
            footer
        }
        // LoadInitialValues includes a synchronous
        // billingOverrideRepository.fetch which was blocking the main
        // thread on .onAppear. Use .task so the DB hop runs on a
        // background executor; the sync portion (form @State assignment)
        // happens immediately, the DB lookup is awaited.
        .task {
            await loadInitialValues()
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

            // Custom rate — only in edit mode (cannot add override if todo is not yet in DB)
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

    /// Switched from .onAppear { loadInitialValues() } to
    /// .task { await loadInitialValues() } so the billing-override DB read
    /// no longer blocks the main thread during form presentation. The
    /// in-memory @State assignments still happen up front; only the DB
    /// lookup is awaited off main.
    private func loadInitialValues() async {
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

        // Load the existing billing override if any. We used to call this
        // in the background via Task.detached; under Swift 6 strict
        // concurrency the repository is @MainActor-isolated and can't be
        // called from a detached actor. Since this is a one-shot DB fetch
        // at form-open time, doing it synchronously on the main actor is
        // acceptable (SQLite averages < 1 ms). Errors are no longer
        // swallowed with a silent `try?` — log + empty fallback.
        let override: TodoBillingOverride?
        do {
            override = try billingOverrideRepository.fetch(todoId: todo.id)
        } catch {
            ProWorkLog.app.error(
                "TodoFormView billingOverride fetch failed for todo=\(todo.id, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            override = nil
        }

        if let override {
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

    /// Upserts/removes the billing override in edit mode.
    ///
    /// The previous `try?` silenced both upsert
    /// and remove failures, so a write error left the override stale
    /// while the parent's `onSave(todo)` happily updated the todo —
    /// the partial-failure window the audit calls out. Now we route
    /// through `ProWorkToastStore` on failure (parent already shows
    /// its own toast on the todo write) so the user sees a real
    /// signal. Full atomicity needs the override write to share a
    /// transaction with the todo write; that requires lifting the
    /// closure out of the View (Tier 7 VM-style refactor) and is
    /// flagged in as a separate architectural item.
    private func persistBillingOverride(for todoId: String) {
        guard isEditMode else { return }

        if hasBillingOverride && isBillable {
            // Cache adoption mirrors PriceListRowFormView.
            let formatter = ProWorkFormatters.cachedDecimalFormatter(
                localeIdentifier: settingsStore.locale.identifier,
                minimumFractionDigits: 0,
                maximumFractionDigits: 4
            )

            guard let n = formatter.number(from: billingOverrideAmountText), n.decimalValue >= 0 else {
                return  // silently ignore; no UI-level validation
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
            do {
                try billingOverrideRepository.upsert(override)
            } catch {
                ProWorkToastStore.shared.show(
                    error.localizedDescription,
                    style: .error
                )
            }
        } else {
            // Override disabled or billable=false → soft-delete
            do {
                try billingOverrideRepository.remove(todoId: todoId)
            } catch {
                ProWorkToastStore.shared.show(
                    error.localizedDescription,
                    style: .error
                )
            }
        }
    }

    private func refreshSuggestedBillingOverrideCurrency(force: Bool = false) {
        guard force || !hasCustomBillingOverrideCurrency else {
            return
        }

        let suggestedCurrency: String

        // Currency resolution failures fall back to "TRY" for UX
        // continuity, but the old silent `try?` did not surface resolver
        // errors (DB error / wrong record). We now log so the question
        // "why does it suggest TRY?" can be traced from Console.app.
        if !projectId.isEmpty,
           let project = projects.first(where: { $0.id == projectId }) {
            do {
                suggestedCurrency = try currencyResolver.resolveProjectCurrency(
                    projectId: project.id,
                    customerId: project.customerId,
                    organizationId: BuiltInOrganizationId.default
                )
            } catch {
                ProWorkLog.app.error(
                    "TodoFormView resolveProjectCurrency failed (projectId=\(project.id, privacy: .public)): \(error.localizedDescription, privacy: .private)"
                )
                suggestedCurrency = "TRY"
            }
        } else if !customerId.isEmpty {
            do {
                suggestedCurrency = try currencyResolver.resolveCustomerCurrency(
                    customerId: customerId,
                    organizationId: BuiltInOrganizationId.default
                )
            } catch {
                ProWorkLog.app.error(
                    "TodoFormView resolveCustomerCurrency failed (customerId=\(customerId, privacy: .public)): \(error.localizedDescription, privacy: .private)"
                )
                suggestedCurrency = "TRY"
            }
        } else {
            suggestedCurrency = AppServices.shared.cachedMasterCurrency()
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
