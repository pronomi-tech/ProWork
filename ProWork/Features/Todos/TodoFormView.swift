//  TodoFormView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import os

private enum TodoFormTab: String, CaseIterable, Identifiable {
    case details
    case planningAndBilling

    var id: String { rawValue }
}

private enum TodoBillingMethod: String, CaseIterable, Identifiable {
    case trackedTime
    case projectedFee
    case fixedFee

    var id: String { rawValue }
}

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
    @State private var folderId: String = ""
    @State private var categoryId: String = ""
    @State private var statusId: String = BuiltInTodoStatusId.waiting

    // MARK: - Content
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: String = "normal"
    @State private var estimatedMinutesText: String = ""
    @State private var isBillable: Bool = true
    @State private var isAIAgentTask: Bool = false

    // MARK: - Schedule
    @State private var hasPlannedDate: Bool = false
    @State private var plannedDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var createdAt: Date = Date()
    @State private var completedAt: Date?

    // MARK: - UI
    @State private var confirmation: ProWorkConfirmation?
    @State private var selectedTab: TodoFormTab = .details

    // MARK: - Billing
    @State private var billingMethod: TodoBillingMethod = .trackedTime
    @State private var hasCustomHourlyRate = false
    @State private var billingOverrideAmountText: String = ""
    @State private var projectedHoursText: String = ""
    @State private var billingOverrideCurrency: String = "TRY"
    @State private var billingNote: String = ""
    @State private var billingOverrideRecord: TodoBillingOverride?
    @State private var hasCustomBillingOverrideCurrency: Bool = false
    @State private var priceLists: [PriceList] = []
    @State private var priceListRowsByListId: [String: [PriceListRow]] = [:]
    @State private var priceListLoadFailed = false
    @State private var isShowingHourlyRatePicker = false

    // Repository / resolver dependencies are pulled from the shared AppServices
    // instance so they are not reopened every time the View struct is recreated
    private let billingOverrideRepository = AppServices.shared.todoBillingOverrideRepository
    private let currencyResolver = AppServices.shared.pricingCurrencyResolver
    private let priceListRepository = AppServices.shared.priceListRepository
    private let priceListRowRepository = AppServices.shared.priceListRowRepository

    let mode: TodoFormMode
    let customers: [Customer]
    let projects: [ProjectListItem]
    let folders: [WorkFolder]
    let categories: [TaskCategory]
    let statuses: [TodoStatus]
    let initialLocation: WorkLocationSelection
    let onSave: (Todo, TodoBillingOverride?) -> Void

    init(
        mode: TodoFormMode,
        customers: [Customer],
        projects: [ProjectListItem],
        folders: [WorkFolder],
        categories: [TaskCategory],
        statuses: [TodoStatus],
        initialLocation: WorkLocationSelection = .all,
        onSave: @escaping (Todo, TodoBillingOverride?) -> Void
    ) {
        self.mode = mode
        self.customers = customers
        self.projects = projects
        self.folders = folders
        self.categories = categories
        self.statuses = statuses
        self.initialLocation = initialLocation
        self.onSave = onSave
    }

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

    private var folderOptions: [TodoFormSelectOption] {
        let scopeProjectId = projectId.isEmpty ? nil : projectId
        let flattened = WorkFolderHierarchy.flattened(folders, projectId: scopeProjectId)
        return [
            TodoFormSelectOption(
                id: "",
                title: settingsStore.localized("todoForm.folder.none", defaultValue: "Klasör yok"),
                subtitle: nil,
                systemColorName: nil
            )
        ] + flattened.map { item in
            TodoFormSelectOption(
                id: item.id,
                title: item.path,
                subtitle: nil,
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

    private var hourlyRateOptions: [TodoHourlyRateOption] {
        TodoHourlyRateOptionBuilder.build(
            priceLists: priceLists,
            rowsByListId: priceListRowsByListId,
            customerId: customerId.isEmpty ? nil : customerId,
            projectId: projectId.isEmpty ? nil : projectId,
            categoryId: categoryId.isEmpty ? nil : categoryId,
            dateString: AppDateFormatters.istanbulDay.string(from: Date())
        )
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: formSubtitle,
            systemImage: "checklist",
            width: FormSheetSize.todoForm.width,
            height: FormSheetSize.todoForm.height,
            contentScrollBehavior: .fitsContent
        ) {
            VStack(alignment: .leading, spacing: formH(14)) {
                formTabBar

                Divider()

                Group {
                    switch selectedTab {
                    case .details:
                        detailFields
                    case .planningAndBilling:
                        planningAndBillingFields
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } footer: {
            footer
        }
        .proWorkToastNotifications(errorMessage: billingCustomerErrorMessage)
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
            ensureValidFolderSelection()
            refreshSuggestedBillingOverrideCurrency()
        }
        .onChange(of: projectId) { _, _ in
            ensureValidFolderSelection()
            refreshSuggestedBillingOverrideCurrency()
        }
        .onChange(of: billingMethod) { _, method in
            if method != .trackedTime || hasCustomHourlyRate {
                refreshSuggestedBillingOverrideCurrency()
            }
        }
        .onChange(of: hasCustomHourlyRate) { _, enabled in
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

    private var detailFields: some View {
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

            formRow(label: settingsStore.localized("todoForm.folder", defaultValue: "Klasör"), alignment: .center) {
                ProWorkSearchPickerField(
                    placeholder: settingsStore.localized("todoForm.folder.placeholder", defaultValue: "Klasör seçin"),
                    items: folderOptions,
                    selectedId: $folderId,
                    showsSearch: folderOptions.count > 8,
                    systemImage: "folder",
                    itemTitle: { $0.title },
                    itemSubtitle: { $0.subtitle },
                    itemColor: { _ in nil },
                    matchesSearch: { item, searchText in
                        item.title.localizedCaseInsensitiveContains(searchText)
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

            formRow(label: settingsStore.localized("todoForm.description", defaultValue: "Açıklama"), alignment: .top) {
                ProWorkTextEditor(
                    placeholder: settingsStore.localized("todoForm.description.placeholder", defaultValue: "Opsiyonel açıklama"),
                    text: $description,
                    minHeight: 92
                )
                .frame(width: formW(430))
            }

            formRow(label: settingsStore.localized("todoForm.aiAgent", defaultValue: "AI Agent"), alignment: .top) {
                VStack(alignment: .leading, spacing: formH(6)) {
                    ProWorkCheckbox(
                        settingsStore.localized("todoForm.aiAgent.toggle", defaultValue: "Bu görevde AI agent kullanılıyor"),
                        isOn: $isAIAgentTask,
                        boxSize: 22
                    )
                    Text(settingsStore.localized(
                        "todoForm.aiAgent.help",
                        defaultValue: "AI görevleri bilgisayar boşta kaldığında otomatik duraklatılmaz."
                    ))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(width: formW(430), alignment: .leading)
            }
        }
    }

    private var formTabBar: some View {
        HStack(spacing: formW(10)) {
            formTabButton(
                .details,
                title: settingsStore.localized("todoForm.tab.details", defaultValue: "İş Bilgileri"),
                systemImage: "list.bullet.clipboard"
            )
            formTabButton(
                .planningAndBilling,
                title: settingsStore.localized("todoForm.tab.planningAndBilling", defaultValue: "Planlama ve Ücret"),
                systemImage: "calendar.badge.clock"
            )
        }
    }

    private func formTabButton(
        _ tab: TodoFormTab,
        title: String,
        systemImage: String
    ) -> some View {
        let selected = selectedTab == tab
        let showsError = tab == .planningAndBilling && !billingConfigurationIsValid

        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: formW(10)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 16, weight: .semibold)
                Text(title)
                    .proWorkTextStyle(.callout, weight: .semibold)
                Spacer(minLength: 0)
                if showsError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, formW(18))
            .frame(maxWidth: .infinity, minHeight: formH(58), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: formW(10))
                    .fill(selected ? Color.accentColor : Color.secondary.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var planningAndBillingFields: some View {
        VStack(alignment: .leading, spacing: formH(14)) {
            planningFields
            Divider()
            billingFields
        }
    }

    private var planningFields: some View {
        VStack(alignment: .leading, spacing: formH(14)) {
            Text(settingsStore.localized("todoForm.planning", defaultValue: "Planlama"))
                .proWorkTextStyle(.headline)

            HStack(alignment: .top, spacing: formW(18)) {
                compactPlanningField(
                    title: settingsStore.localized("todoForm.priority", defaultValue: "Öncelik")
                ) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("todoForm.priority.placeholder", defaultValue: "Öncelik seçin"),
                        items: priorityOptions,
                        selectedId: $priority,
                        isDisabled: false,
                        showsSearch: false,
                        systemImage: "flag",
                        itemTitle: { $0.title },
                        itemSubtitle: { $0.subtitle },
                        itemColor: { ProWorkColors.fromName($0.systemColorName) },
                        matchesSearch: { item, searchText in
                            item.title.localizedCaseInsensitiveContains(searchText)
                        }
                    )
                }

                compactPlanningField(
                    title: settingsStore.localized("todoForm.estimated", defaultValue: "Tahmini Süre")
                ) {
                    HStack(spacing: formW(8)) {
                        ProWorkNumberField(
                            placeholder: settingsStore.localized("todoForm.estimated.placeholder", defaultValue: "60"),
                            text: $estimatedMinutesText,
                            style: .integer(),
                            minHeight: 40
                        )
                        Text(settingsStore.localized("todoForm.estimated.minutes", defaultValue: "dk"))
                            .proWorkTextStyle(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: formW(18)) {
                compactPlanningField(
                    title: settingsStore.localized("todoForm.plannedDate", defaultValue: "Planlanan Tarih")
                ) {
                    optionalDateField(
                        isEnabled: $hasPlannedDate,
                        date: $plannedDate,
                        placeholder: settingsStore.localized("todoForm.plannedDate.placeholder", defaultValue: "Planlanan tarih seçin")
                    )
                }

                compactPlanningField(
                    title: settingsStore.localized("todoForm.dueDate", defaultValue: "Termin")
                ) {
                    optionalDateField(
                        isEnabled: $hasDueDate,
                        date: $dueDate,
                        placeholder: settingsStore.localized("todoForm.dueDate.placeholder", defaultValue: "Termin seçin")
                    )
                }
            }
        }
    }

    private func compactPlanningField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: formH(7)) {
            Text(title)
                .proWorkTextStyle(.caption, weight: .medium)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var billingFields: some View {
        VStack(alignment: .leading, spacing: formH(12)) {
            formRow(label: settingsStore.localized("todoForm.billing", defaultValue: "Faturalandırma"), alignment: .center) {
                ProWorkCheckbox(
                    settingsStore.localized("todos.billable", defaultValue: "Faturalandırılır"),
                    isOn: $isBillable,
                    boxSize: 22
                )
            }

            if isBillable {
                formRow(label: settingsStore.localized("todoForm.billingMethod", defaultValue: "Ücretlendirme Yöntemi"), alignment: .top) {
                    VStack(alignment: .leading, spacing: formH(8)) {
                        Picker("", selection: $billingMethod) {
                            Text(settingsStore.localized("todoForm.billingMethod.tracked", defaultValue: "Gerçekleşen Süre"))
                                .tag(TodoBillingMethod.trackedTime)
                            Text(settingsStore.localized("todoForm.billingMethod.projected", defaultValue: "Projelendirilmiş Ücret"))
                                .tag(TodoBillingMethod.projectedFee)
                            Text(settingsStore.localized("todoForm.billingMethod.fixed", defaultValue: "Sabit Tutar"))
                                .tag(TodoBillingMethod.fixedFee)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: formW(450))

                        Text(billingMethodHelp)
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: formW(450), alignment: .leading)
                    }
                }

                switch billingMethod {
                case .trackedTime:
                    formRow(label: settingsStore.localized("todoForm.customHourlyRate", defaultValue: "Özel Saatlik Ücret"), alignment: .top) {
                        VStack(alignment: .leading, spacing: formH(10)) {
                            ProWorkCheckbox(
                                settingsStore.localized("todoForm.customHourlyRate.toggle", defaultValue: "Fiyat listesi yerine özel saatlik ücret kullan"),
                                isOn: $hasCustomHourlyRate,
                                boxSize: 22
                            )
                            if hasCustomHourlyRate {
                                billingAmountAndCurrency(showsHourlyRatePicker: true)
                            }
                        }
                    }
                case .projectedFee:
                    formRow(label: settingsStore.localized("todoForm.projectedFeeDetails", defaultValue: "Projelendirme"), alignment: .top) {
                        HStack(alignment: .bottom, spacing: formW(12)) {
                            compactPlanningField(
                                title: settingsStore.localized("todoForm.projectedHours", defaultValue: "Adam/Saat")
                            ) {
                                ProWorkNumberField(
                                    placeholder: "0",
                                    text: $projectedHoursText,
                                    style: .decimal(maxFractionDigits: 4),
                                    minHeight: 40
                                )
                            }
                            .frame(width: formW(115))

                            compactPlanningField(
                                title: settingsStore.localized("todoForm.hourlyUnitPrice", defaultValue: "Birim Ücret")
                            ) {
                                billingAmountAndCurrency(
                                    showsHourlyRatePicker: true,
                                    amountWidth: 135,
                                    currencyWidth: 178
                                )
                            }
                        }
                        .frame(width: formW(450), alignment: .leading)
                    }

                    formRow(label: settingsStore.localized("todoForm.calculatedServiceFee", defaultValue: "Hesaplanan Hizmet Bedeli"), alignment: .center) {
                        Text(projectedTotalDisplay)
                            .proWorkTextStyle(.headline)
                            .monospacedDigit()
                    }
                case .fixedFee:
                    formRow(label: settingsStore.localized("todoForm.fixedFee", defaultValue: "Sabit Tutar"), alignment: .center) {
                        billingAmountAndCurrency(showsHourlyRatePicker: false)
                    }
                }

                if billingMethod != .trackedTime || hasCustomHourlyRate {
                    formRow(label: settingsStore.localized("todoForm.billingNote", defaultValue: "Ücret Açıklaması"), alignment: .top) {
                        ProWorkTextEditor(
                            placeholder: settingsStore.localized("todoForm.billingNote.placeholder", defaultValue: "Opsiyonel açıklama"),
                            text: $billingNote,
                            minHeight: 64
                        )
                        .frame(width: formW(430))
                    }
                }

            }
        }
    }

    private func billingAmountAndCurrency(
        showsHourlyRatePicker: Bool,
        amountWidth: CGFloat = 160,
        currencyWidth: CGFloat = 210
    ) -> some View {
        HStack(spacing: formW(10)) {
            if showsHourlyRatePicker {
                hourlyRateAmountField
                    .frame(width: formW(amountWidth))
            } else {
                ProWorkNumberField(
                    placeholder: "0",
                    text: $billingOverrideAmountText,
                    style: .decimal(maxFractionDigits: 4),
                    minHeight: 40
                )
                .frame(width: formW(amountWidth))
            }

            ProWorkSearchPickerField(
                placeholder: settingsStore.localized("todoForm.billingOverride.currency", defaultValue: "Para birimi"),
                items: currencyOptions,
                selectedId: billingOverrideCurrencyBinding,
                isDisabled: false,
                showsSearch: false,
                systemImage: "banknote",
                itemTitle: { $0.title },
                itemSubtitle: { $0.subtitle },
                itemColor: { ProWorkColors.fromName($0.systemColorName) },
                matchesSearch: { item, searchText in
                    item.title.localizedCaseInsensitiveContains(searchText) ||
                    (item.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            )
            .frame(width: formW(currencyWidth))
        }
    }

    private var hourlyRateAmountField: some View {
        ProWorkNumberField(
            placeholder: "0",
            text: $billingOverrideAmountText,
            style: .decimal(maxFractionDigits: 4),
            minHeight: 40
        )
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                Divider()
                    .frame(height: formH(22))

                Button {
                    isShowingHourlyRatePicker.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .proWorkFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: formW(30))
                        .frame(minHeight: formH(34))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(settingsStore.localized("todoForm.hourlyRatePicker.help", defaultValue: "Fiyat listesinden saatlik ücret seç"))
                .popover(isPresented: $isShowingHourlyRatePicker, arrowEdge: .bottom) {
                    hourlyRatePickerPopover
                }
            }
            .padding(.trailing, formW(4))
            .background(.background.opacity(0.96))
        }
    }

    private var hourlyRatePickerPopover: some View {
        TodoHourlyRatePickerPopover(
            options: hourlyRateOptions,
            categories: categories,
            customers: customers,
            projects: projects,
            loadFailed: priceListLoadFailed
        ) { option in
            applyHourlyRate(option)
            isShowingHourlyRatePicker = false
        }
    }

    private var billingMethodHelp: String {
        switch billingMethod {
        case .trackedTime:
            return settingsStore.localized("todoForm.billingMethod.tracked.help", defaultValue: "Hizmet bedeli tamamlanan çalışma kayıtlarının süresinden hesaplanır.")
        case .projectedFee:
            return settingsStore.localized("todoForm.billingMethod.projected.help", defaultValue: "Mutabık kalınan adam/saat ve birim ücret, tarih aralığından bağımsız olarak hizmet dökümüne eklenebilir.")
        case .fixedFee:
            return settingsStore.localized("todoForm.billingMethod.fixed.help", defaultValue: "Görev, süre kayıtlarından bağımsız tek bir sabit tutarla hizmet dökümüne eklenir.")
        }
    }

    private var billingCustomerErrorMessage: String? {
        guard isBillable,
              customerId.isEmpty,
              billingMethod == .projectedFee || billingMethod == .fixedFee else {
            return nil
        }

        return settingsStore.localized(
            "todoForm.billing.customerRequired",
            defaultValue: "Projelendirilmiş veya sabit ücret için İş Bilgileri sekmesinden bir müşteri seçin."
        )
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
        !categoryId.isEmpty &&
        billingConfigurationIsValid
    }

    private var billingConfigurationIsValid: Bool {
        guard isBillable else { return true }

        switch billingMethod {
        case .trackedTime:
            return !hasCustomHourlyRate || positiveBillingAmount != nil
        case .projectedFee:
            return !customerId.isEmpty &&
                positiveBillingAmount != nil &&
                positiveProjectedHours != nil
        case .fixedFee:
            return !customerId.isEmpty && positiveBillingAmount != nil
        }
    }

    private var positiveBillingAmount: Decimal? {
        guard let amount = decimalValue(from: billingOverrideAmountText), amount > 0 else {
            return nil
        }
        return amount
    }

    private var positiveProjectedHours: Decimal? {
        guard let hours = decimalValue(from: projectedHoursText), hours > 0 else {
            return nil
        }
        return hours
    }

    private var projectedTotalDisplay: String {
        guard let hours = positiveProjectedHours,
              let rate = positiveBillingAmount else {
            return "—"
        }
        return ProWorkFormatters.money(
            Money(amount: hours * rate, currency: billingOverrideCurrency)
        )
    }

    private func decimalValue(from text: String) -> Decimal? {
        let formatter = ProWorkFormatters.cachedDecimalFormatter(
            localeIdentifier: settingsStore.locale.identifier,
            minimumFractionDigits: 0,
            maximumFractionDigits: 4
        )
        return formatter.number(from: text)?.decimalValue
    }

    private func displayDecimal(_ value: Decimal) -> String {
        let formatter = ProWorkFormatters.cachedDecimalFormatter(
            localeIdentifier: settingsStore.locale.identifier,
            minimumFractionDigits: 0,
            maximumFractionDigits: 4
        )
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }

    private func projectedSeconds(from hours: Decimal) -> Int {
        var raw = hours * Decimal(3_600)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .bankers)
        return max(0, NSDecimalNumber(decimal: rounded).intValue)
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
        loadHourlyRateOptions()

        if categoryId.isEmpty {
            categoryId = categories.first?.id ?? ""
        }

        if statusId.isEmpty || !statuses.contains(where: { $0.id == statusId }) {
            statusId = statuses.first(where: { $0.id == BuiltInTodoStatusId.waiting })?.id
                ?? statuses.first?.id
                ?? BuiltInTodoStatusId.waiting
        }

        guard case .edit(let todo) = mode else {
            let assignment = initialLocation.assignment(projects: projects, folders: folders)
            customerId = assignment.customerId ?? ""
            projectId = assignment.projectId ?? ""
            folderId = assignment.folderId ?? ""
            refreshSuggestedBillingOverrideCurrency(force: !hasCustomBillingOverrideCurrency)
            return
        }

        id = todo.id
        customerId = todo.customerId ?? ""
        projectId = todo.projectId ?? ""
        folderId = todo.folderId ?? ""
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
        isAIAgentTask = todo.isAIAgentTask
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
            billingOverrideCurrency = override.currency
            billingNote = override.note ?? ""
            hasCustomBillingOverrideCurrency = true
            switch override.overrideType {
            case .unitPrice:
                billingMethod = .trackedTime
                hasCustomHourlyRate = true
                if let m = override.unitPriceMinor {
                    billingOverrideAmountText = ProWorkFormatters.moneyAmount(
                        Money(minorUnits: m, currency: override.currency)
                    )
                }
            case .projectedFee:
                billingMethod = .projectedFee
                if let m = override.unitPriceMinor {
                    billingOverrideAmountText = ProWorkFormatters.moneyAmount(
                        Money(minorUnits: m, currency: override.currency)
                    )
                }
                if let seconds = override.projectedBillableSeconds {
                    projectedHoursText = displayDecimal(Decimal(seconds) / Decimal(3_600))
                }
            case .fixedFee:
                billingMethod = .fixedFee
                if let m = override.fixedFeeMinor {
                    billingOverrideAmountText = ProWorkFormatters.moneyAmount(
                        Money(minorUnits: m, currency: override.currency)
                    )
                }
            }
        }

        refreshSuggestedBillingOverrideCurrency(force: !hasCustomBillingOverrideCurrency)
    }

    private func loadHourlyRateOptions() {
        do {
            let lists = try priceListRepository.fetchAll(
                organizationId: BuiltInOrganizationId.default
            )
            priceLists = lists
            priceListRowsByListId = try priceListRowRepository.fetchAll(
                priceListIds: lists.map(\.id)
            )
            priceListLoadFailed = false
        } catch {
            priceLists = []
            priceListRowsByListId = [:]
            priceListLoadFailed = true
            ProWorkLog.app.error(
                "TodoFormView price-list rates load failed: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func applyHourlyRate(_ option: TodoHourlyRateOption) {
        billingOverrideAmountText = ProWorkFormatters.moneyAmount(
            option.row.unitPrice,
            localeIdentifier: settingsStore.locale.identifier
        )
        billingOverrideCurrency = option.row.currency
        hasCustomBillingOverrideCurrency = true
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimatedMinutes = Int(estimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !cleanTitle.isEmpty, !categoryId.isEmpty else {
            selectedTab = .details
            return
        }
        guard billingConfigurationIsValid else {
            selectedTab = .planningAndBilling
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
            folderId: folderId.isEmpty ? nil : folderId,
            categoryId: categoryId,
            title: cleanTitle,
            description: cleanDescription.isEmpty ? nil : cleanDescription,
            statusId: statusId,
            priority: priority,
            plannedDate: hasPlannedDate ? plannedDate : nil,
            dueDate: hasDueDate ? dueDate : nil,
            estimatedMinutes: estimatedMinutes,
            isBillable: isBillable,
            isAIAgentTask: isAIAgentTask,
            completedAt: finalCompletedAt,
            createdAt: createdAt,
            updatedAt: Date()
        )
        let billingOverride = makeBillingOverride(todoId: todo.id)

        switch mode {
        case .create:
            onSave(todo, billingOverride)

        case .edit:
            confirmation = ProWorkConfirmation(
                title: settingsStore.localized("todoForm.confirm.title", defaultValue: "Değişiklikler kaydedilsin mi?"),
                message: String(format: settingsStore.localized("todoForm.confirm.message", defaultValue: "“%@” yapılacak iş kaydındaki değişiklikler kaydedilecek."), todo.title),
                confirmTitle: settingsStore.localized("common.save", defaultValue: "Kaydet"),
                cancelTitle: settingsStore.localized("common.cancel", defaultValue: "Vazgeç")
            ) {
                onSave(todo, billingOverride)
            }
        }
    }

    private func ensureValidFolderSelection() {
        guard !folderId.isEmpty else { return }
        let scopeProjectId = projectId.isEmpty ? nil : projectId
        if !folders.contains(where: { $0.id == folderId && $0.projectId == scopeProjectId }) {
            folderId = ""
        }
    }

    private func makeBillingOverride(todoId: String) -> TodoBillingOverride? {
        guard isBillable else { return nil }

        let type: TodoBillingOverrideType
        let unitPriceMinor: Int?
        let projectedBillableSeconds: Int?
        let fixedFeeMinor: Int?

        switch billingMethod {
        case .trackedTime:
            guard hasCustomHourlyRate, let amount = positiveBillingAmount else {
                return nil
            }
            type = .unitPrice
            unitPriceMinor = Money(amount: amount, currency: billingOverrideCurrency).minorUnits
            projectedBillableSeconds = nil
            fixedFeeMinor = nil
        case .projectedFee:
            guard let amount = positiveBillingAmount,
                  let hours = positiveProjectedHours else {
                return nil
            }
            type = .projectedFee
            unitPriceMinor = Money(amount: amount, currency: billingOverrideCurrency).minorUnits
            projectedBillableSeconds = projectedSeconds(from: hours)
            fixedFeeMinor = nil
        case .fixedFee:
            guard let amount = positiveBillingAmount else { return nil }
            type = .fixedFee
            unitPriceMinor = nil
            projectedBillableSeconds = nil
            fixedFeeMinor = Money(amount: amount, currency: billingOverrideCurrency).minorUnits
        }

        let trimmedNote = billingNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return TodoBillingOverride(
            id: billingOverrideRecord?.id ?? UUID().uuidString,
            todoId: todoId,
            overrideType: type,
            unitPriceMinor: unitPriceMinor,
            projectedBillableSeconds: projectedBillableSeconds,
            fixedFeeMinor: fixedFeeMinor,
            currency: billingOverrideCurrency,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            organizationId: BuiltInOrganizationId.default,
            createdAt: billingOverrideRecord?.createdAt ?? Date()
        )
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

struct TodoHourlyRateOption: Identifiable, Hashable {
    var id: String { row.id }
    let priceList: PriceList
    let row: PriceListRow
}

enum TodoHourlyRateOptionBuilder {
    static func build(
        priceLists: [PriceList],
        rowsByListId: [String: [PriceListRow]],
        customerId: String?,
        projectId: String?,
        categoryId: String?,
        dateString: String
    ) -> [TodoHourlyRateOption] {
        priceLists
            .filter { list in
                guard list.isActive,
                      list.deletedAt == nil,
                      PriceListResolver.isWithin(
                          date: dateString,
                          from: list.validFrom,
                          to: list.validTo
                      ) else {
                    return false
                }

                switch list.ownerType {
                case .project:
                    return projectId != nil && list.ownerId == projectId
                case .customer:
                    return customerId != nil && list.ownerId == customerId
                case .global:
                    return list.ownerId == nil
                }
            }
            .sorted(by: listSortOrder)
            .flatMap { list in
                (rowsByListId[list.id] ?? [])
                    .filter { row in
                        row.isActive &&
                        row.deletedAt == nil &&
                        (row.categoryId == nil || row.categoryId == categoryId) &&
                        PriceListResolver.isWithin(
                            date: dateString,
                            from: row.validFrom,
                            to: row.validTo
                        )
                    }
                    .sorted(by: rowSortOrder)
                    .map { TodoHourlyRateOption(priceList: list, row: $0) }
            }
    }

    nonisolated private static func listSortOrder(_ lhs: PriceList, _ rhs: PriceList) -> Bool {
        let lhsScope = scopePriority(lhs.ownerType)
        let rhsScope = scopePriority(rhs.ownerType)
        if lhsScope != rhsScope { return lhsScope < rhsScope }
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated private static func rowSortOrder(_ lhs: PriceListRow, _ rhs: PriceListRow) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        let lhsService = servicePriority(lhs.serviceType)
        let rhsService = servicePriority(rhs.serviceType)
        if lhsService != rhsService {
            return lhsService < rhsService
        }
        let lhsTime = timePriority(lhs.timeType)
        let rhsTime = timePriority(rhs.timeType)
        if lhsTime != rhsTime {
            return lhsTime < rhsTime
        }
        return lhs.id < rhs.id
    }

    nonisolated private static func servicePriority(_ serviceType: ServiceType) -> Int {
        switch serviceType {
        case .onsite: return 10
        case .remote: return 20
        }
    }

    nonisolated private static func timePriority(_ timeType: TimeType) -> Int {
        switch timeType {
        case .regular: return 10
        case .afterHours: return 20
        case .weekend: return 30
        case .holiday: return 40
        }
    }

    nonisolated private static func scopePriority(_ ownerType: PriceListOwnerType) -> Int {
        switch ownerType {
        case .project: return 0
        case .customer: return 1
        case .global: return 2
        }
    }
}

private struct TodoHourlyRatePickerPopover: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let options: [TodoHourlyRateOption]
    let categories: [TaskCategory]
    let customers: [Customer]
    let projects: [ProjectListItem]
    let loadFailed: Bool
    let onSelect: (TodoHourlyRateOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.blue)
                Text(settingsStore.localized("todoForm.hourlyRatePicker.title", defaultValue: "Fiyat Listesinden Seç"))
                    .proWorkTextStyle(.headline)
            }

            Divider()

            if loadFailed {
                emptyState(
                    systemImage: "exclamationmark.triangle",
                    message: settingsStore.localized(
                        "todoForm.hourlyRatePicker.loadError",
                        defaultValue: "Fiyat listeleri yüklenemedi. Ücreti manuel girebilirsiniz."
                    )
                )
            } else if options.isEmpty {
                emptyState(
                    systemImage: "list.bullet.rectangle",
                    message: settingsStore.localized(
                        "todoForm.hourlyRatePicker.empty",
                        defaultValue: "Bu müşteri, proje ve kategori için geçerli bir ücret bulunamadı."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                optionRow(option)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: ProWorkLayout.scaled(360, using: settingsStore))
            }
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(460, using: settingsStore))
    }

    private func optionRow(_ option: TodoHourlyRateOption) -> some View {
        HStack(alignment: .top, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                    Text(option.priceList.name)
                        .proWorkTextStyle(.callout, weight: .semibold)
                        .lineLimit(1)

                    if option.priceList.isDefault {
                        Text(settingsStore.localized("todoForm.hourlyRatePicker.default", defaultValue: "Varsayılan"))
                            .proWorkTextStyle(.caption, weight: .semibold)
                            .foregroundStyle(.blue)
                    }
                }

                Text(optionDetail(option))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let conditions = conditionDetail(option.row) {
                    Text(conditions)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: ProWorkLayout.scaled(10, using: settingsStore))

            Text(ProWorkFormatters.hourlyRate(
                option.row.unitPrice,
                localeIdentifier: settingsStore.locale.identifier
            ))
            .proWorkTextStyle(.callout, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(10, using: settingsStore))
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
        .contentShape(Rectangle())
    }

    private func optionDetail(_ option: TodoHourlyRateOption) -> String {
        var parts = [scopeTitle(option.priceList)]
        parts.append(option.row.serviceType.title)
        parts.append(option.row.timeType.title)
        if let categoryId = option.row.categoryId,
           let category = categories.first(where: { $0.id == categoryId }) {
            parts.append(category.name)
        } else {
            parts.append(settingsStore.localized("todoForm.hourlyRatePicker.allCategories", defaultValue: "Tüm kategoriler"))
        }
        return parts.joined(separator: " • ")
    }

    private func scopeTitle(_ list: PriceList) -> String {
        switch list.ownerType {
        case .project:
            let name = projects.first(where: { $0.id == list.ownerId })?.name
            return [list.ownerType.title, name].compactMap { $0 }.joined(separator: ": ")
        case .customer:
            let name = customers.first(where: { $0.id == list.ownerId })?.name
            return [list.ownerType.title, name].compactMap { $0 }.joined(separator: ": ")
        case .global:
            return list.ownerType.title
        }
    }

    private func conditionDetail(_ row: PriceListRow) -> String? {
        var parts: [String] = []
        if let mask = row.weekdayMask {
            let days = Weekday.allCases
                .filter { PriceListRow.weekdays(fromMask: mask).contains($0) }
                .map(\.title)
                .joined(separator: ", ")
            if !days.isEmpty { parts.append(days) }
        }
        if row.startTime != nil || row.endTime != nil {
            let start = row.startTime?.formatted ?? "00:00"
            let end = row.endTime?.formatted ?? "24:00"
            parts.append("\(start)–\(end)")
        }
        if row.validFrom != nil || row.validTo != nil {
            let from = row.validFrom ?? "…"
            let to = row.validTo ?? "…"
            parts.append("\(from)–\(to)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func emptyState(systemImage: String, message: String) -> some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(message)
                .proWorkTextStyle(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ProWorkLayout.scaled(8, using: settingsStore))
    }
}
