//
//  WorkSessionsView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI
import Combine

struct WorkSessionsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var sessions: [WorkSessionListItem] = []
    @State private var todos: [TodoListItem] = []
    @State private var customers: [Customer] = []
    @State private var projects: [ProjectListItem] = []
    @State private var categories: [TaskCategory] = []
    @State private var statuses: [TodoStatus] = []

    @State private var isShowingCreateForm = false
    @State private var editingSession: WorkSessionListItem?

    @State private var pendingWorkStart: PendingWorkStart?
    @State private var confirmation: ProWorkConfirmation?
    @State private var errorMessage: String?
    @State private var now: Date = Date()

    // Filtreler
    @State private var filterRange: DateRangeFilter = .all
    @State private var filterCustomerId: String = ""
    @State private var filterProjectId: String = ""
    @State private var filterTodoId: String = ""
    @State private var filterSource: FilterSource = .all
    @State private var filterStatus: FilterActiveStatus = .all
    @State private var filterStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var filterEndDate: Date = Date()
    @State private var isShowingFilters: Bool = false

    private let sessionRepository = TodoTimeSessionRepository()
    private let todoRepository = TodoRepository()
    private let customerRepository = CustomerRepository()
    private let projectRepository = ProjectRepository()
    private let categoryRepository = TaskCategoryRepository()
    private let statusRepository = TodoStatusRepository()

    private let timer = Timer.publish(
        every: 30,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            header

            filterBar

            if isShowingFilters {
                filterPanel
            }

            summary

            table
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
        .proWorkFrame(minWidth: 760, minHeight: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .proWorkToastNotifications(errorMessage: errorMessage)
        .onAppear {
            loadData()
        }
        .onReceive(timer) { value in
            guard sessions.contains(where: { $0.endedAt == nil }) else {
                return
            }

            now = value
        }
        .sheet(isPresented: $isShowingCreateForm) {
            WorkSessionFormView(
                mode: .create,
                todos: todos,
                customers: customers,
                projects: projects,
                categories: categories,
                statuses: statuses,
                onTodosChanged: { updatedTodos in
                    todos = updatedTodos
                }
            ) { _, todoId, startedAt, endedAt, note, _ in
                createManualSession(
                    todoId: todoId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    note: note
                )
            }
        }
        .sheet(item: $editingSession) { session in
            WorkSessionFormView(
                mode: .edit(session),
                todos: todos,
                customers: customers,
                projects: projects,
                categories: categories,
                statuses: statuses,
                onTodosChanged: { updatedTodos in
                    todos = updatedTodos
                }
            ) { sessionId, todoId, startedAt, endedAt, note, isManual in
                guard let sessionId else {
                    return
                }

                updateSession(
                    id: sessionId,
                    todoId: todoId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    note: note,
                    isManual: isManual
                )
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    // MARK: - Filtered Sessions

    private var filteredSessions: [WorkSessionListItem] {
        sessions.filter { session in
            matchesRange(session) &&
            matchesCustomer(session) &&
            matchesProject(session) &&
            matchesTodo(session) &&
            matchesSource(session) &&
            matchesActiveStatus(session)
        }
    }

    private func matchesRange(_ session: WorkSessionListItem) -> Bool {
        filterRange.contains(
            session.startedAt,
            customStart: filterStartDate,
            customEnd: filterEndDate
        )
    }

    private func matchesCustomer(_ session: WorkSessionListItem) -> Bool {
        guard !filterCustomerId.isEmpty else { return true }
        guard let customerName = customers.first(where: { $0.id == filterCustomerId })?.name else { return false }
        return session.customerName == customerName
    }

    private func matchesProject(_ session: WorkSessionListItem) -> Bool {
        guard !filterProjectId.isEmpty else { return true }
        guard let projectName = projects.first(where: { $0.id == filterProjectId })?.name else { return false }
        return session.projectName == projectName
    }

    private func matchesTodo(_ session: WorkSessionListItem) -> Bool {
        guard !filterTodoId.isEmpty else { return true }
        return session.todoId == filterTodoId
    }

    private func matchesSource(_ session: WorkSessionListItem) -> Bool {
        switch filterSource {
        case .all: return true
        case .manual: return session.isManual
        case .automatic: return !session.isManual
        }
    }

    private func matchesActiveStatus(_ session: WorkSessionListItem) -> Bool {
        switch filterStatus {
        case .all: return true
        case .active: return session.endedAt == nil
        case .completed: return session.endedAt != nil
        }
    }

    private var hasActiveFilters: Bool {
        filterRange != .all ||
        !filterCustomerId.isEmpty ||
        !filterProjectId.isEmpty ||
        !filterTodoId.isEmpty ||
        filterSource != .all ||
        filterStatus != .all
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("workSessions.title", defaultValue: "Çalışma Kayıtları"))
                    .proWorkTextStyle(.largeTitle)

                Text(settingsStore.localized("workSessions.subtitle", defaultValue: "Tüm otomatik ve manuel çalışma kayıtlarını buradan takip edin."))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingCreateForm = true
            } label: {
                ProWorkButtonLabel(
                    title: settingsStore.localized("workSessions.action.addManual", defaultValue: "Manuel Çalışma Ekle"),
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(categories.isEmpty)
            .help(categories.isEmpty ? settingsStore.localized("todos.help.needCategory", defaultValue: "Önce görev kategorisi eklemelisiniz") : settingsStore.localized("workSessions.help.addManual", defaultValue: "Manuel çalışma ekle"))
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingFilters.toggle()
                }
            } label: {
                HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .proWorkFont(size: 15)
                        .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.secondary)

                    Text(settingsStore.localized("common.filter", defaultValue: "Filtrele"))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.primary)
                }
                .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                .background(hasActiveFilters ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore)))
            }
            .buttonStyle(.plain)

            ProWorkDateRangePicker(
                range: $filterRange,
                customStart: $filterStartDate,
                customEnd: $filterEndDate,
                showsAllOption: true,
                defaultRange: .all
            )

            if hasActiveFilters {
                Button {
                    clearFilters()
                } label: {
                    HStack(spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                        Image(systemName: "xmark")
                            .proWorkFont(size: 11)
                        Text(settingsStore.localized("common.clear", defaultValue: "Temizle"))
                            .proWorkTextStyle(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
                    .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(String(format: settingsStore.localized("common.recordCount", defaultValue: "%d kayıt"), filteredSessions.count))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter Panel

    private var customerFilterOptions: [FilterOption] {
        [FilterOption(id: "", title: settingsStore.localized("dateRange.all", defaultValue: "Tümü"))] +
        customers.map { FilterOption(id: $0.id, title: $0.name) }
    }

    private var projectFilterOptions: [FilterOption] {
        let filtered = filterCustomerId.isEmpty
            ? projects
            : projects.filter { $0.customerId == filterCustomerId }
        return [FilterOption(id: "", title: settingsStore.localized("dateRange.all", defaultValue: "Tümü"))] +
            filtered.map { FilterOption(id: $0.id, title: $0.name) }
    }

    private var filterSourceOptions: [FilterSourceOption] {
        [
            FilterSourceOption(id: FilterSource.all.rawValue, title: settingsStore.localized("dateRange.all", defaultValue: "Tümü")),
            FilterSourceOption(id: FilterSource.manual.rawValue, title: settingsStore.localized("workSessions.source.manual", defaultValue: "Manuel")),
            FilterSourceOption(id: FilterSource.automatic.rawValue, title: settingsStore.localized("workSessions.source.automatic", defaultValue: "Otomatik"))
        ]
    }

    private var filterStatusOptions: [FilterStatusOption] {
        [
            FilterStatusOption(id: FilterActiveStatus.all.rawValue, title: settingsStore.localized("dateRange.all", defaultValue: "Tümü")),
            FilterStatusOption(id: FilterActiveStatus.active.rawValue, title: settingsStore.localized("workSessions.status.active", defaultValue: "Aktif")),
            FilterStatusOption(id: FilterActiveStatus.completed.rawValue, title: settingsStore.localized("workSessions.status.completed", defaultValue: "Tamamlanmış"))
        ]
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
                filterColumn(label: settingsStore.localized("projects.form.customer", defaultValue: "Müşteri")) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("dateRange.all", defaultValue: "Tümü"),
                        items: customerFilterOptions,
                        selectedId: $filterCustomerId,
                        isDisabled: false,
                        showsSearch: customers.count > 8,
                        systemImage: "person.2",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.scaled(180, using: settingsStore))
                }

                filterColumn(label: settingsStore.localized("priceLists.owner.project", defaultValue: "Proje")) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("dateRange.all", defaultValue: "Tümü"),
                        items: projectFilterOptions,
                        selectedId: $filterProjectId,
                        isDisabled: false,
                        showsSearch: projectFilterOptions.count > 9,
                        systemImage: "folder",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.scaled(180, using: settingsStore))
                }

                filterColumn(label: settingsStore.localized("workSessions.column.source", defaultValue: "Kaynak")) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("dateRange.all", defaultValue: "Tümü"),
                        items: filterSourceOptions,
                        selectedId: Binding(
                            get: { filterSource.rawValue },
                            set: { filterSource = FilterSource(rawValue: $0) ?? .all }
                        ),
                        isDisabled: false,
                        showsSearch: false,
                        systemImage: "hand.point.up.left",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.scaled(160, using: settingsStore))
                }

                filterColumn(label: settingsStore.localized("projects.form.status", defaultValue: "Durum")) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("dateRange.all", defaultValue: "Tümü"),
                        items: filterStatusOptions,
                        selectedId: Binding(
                            get: { filterStatus.rawValue },
                            set: { filterStatus = FilterActiveStatus(rawValue: $0) ?? .all }
                        ),
                        isDisabled: false,
                        showsSearch: false,
                        systemImage: "circle.lefthalf.filled",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.scaled(160, using: settingsStore))
                }

                Spacer(minLength: 0)
            }

        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func filterColumn<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            content()
        }
    }

    // MARK: - Summary

    private var summary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                summaryCard(
                    title: settingsStore.localized("workSessions.summary.totalTime", defaultValue: "Toplam Süre"),
                    value: ProWorkFormatters.durationHHmm(totalSeconds),
                    systemImage: "clock"
                )

                summaryCard(
                    title: settingsStore.localized("workSessions.summary.count", defaultValue: "Kayıt Sayısı"),
                    value: "\(filteredSessions.count)",
                    systemImage: "list.bullet.rectangle"
                )

                summaryCard(
                    title: settingsStore.localized("workSessions.source.manual", defaultValue: "Manuel"),
                    value: "\(filteredSessions.filter { $0.isManual }.count)",
                    systemImage: "hand.point.up.left"
                )

                summaryCard(
                    title: settingsStore.localized("workSessions.status.active", defaultValue: "Aktif"),
                    value: "\(filteredSessions.filter { $0.endedAt == nil }.count)",
                    systemImage: "play.circle",
                    isHighlighted: true
                )
            }
            .padding(.vertical, 1)
        }
    }

    private func summaryCard(
        title: String,
        value: String,
        systemImage: String,
        isHighlighted: Bool = false
    ) -> some View {
        return HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: 20)
                .foregroundStyle(isHighlighted ? ProWorkColors.activeHighlight : .blue)
                .proWorkFrame(width: 24)

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(3, using: settingsStore)) {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .proWorkTextStyle(.headline)
                    .monospacedDigit()
            }
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .proWorkFrame(width: 165, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - Table

    private var table: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    tableHeader

                    Divider()

                    if filteredSessions.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredSessions) { session in
                                    row(session)

                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: max(geometry.size.width, tableMinWidth), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
                .overlay(
                    RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                        .stroke(.quaternary, lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Text("")
                .proWorkFrame(width: 80, alignment: .center)
            
            Text(settingsStore.localized("exchangeRates.column.date", defaultValue: "Tarih"))
                .proWorkFrame(width: 95, alignment: .leading)

            Text(settingsStore.localized("workSessions.column.start", defaultValue: "Başlangıç"))
                .proWorkFrame(width: 60, alignment: .center)

            Text(settingsStore.localized("workSessions.column.end", defaultValue: "Bitiş"))
                .proWorkFrame(width: 60, alignment: .center)

            Text(settingsStore.localized("workSessions.column.duration", defaultValue: "Süre"))
                .proWorkFrame(width: 60, alignment: .center)

            Text(settingsStore.localized("workSessions.column.todo", defaultValue: "Yapılacak İş"))
                .proWorkFrame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            Text(settingsStore.localized("workSessions.column.customerProject", defaultValue: "Müşteri / Proje"))
                .proWorkFrame(width: 190, alignment: .leading)

            Text(settingsStore.localized("workSessions.column.source", defaultValue: "Kaynak"))
                .proWorkFrame(width: 60, alignment: .leading)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(9, using: settingsStore))
        .background(.quaternary.opacity(0.35))
    }

    private func row(_ session: WorkSessionListItem) -> some View {
        HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            rowActions(session)
                .proWorkFrame(width: 80, alignment: .center)
            
            Text(settingsStore.formatDate(session.startedAt))
                .proWorkTextStyle(.caption)
                .monospacedDigit()
                .proWorkFrame(width: 95, alignment: .leading)

            Text(settingsStore.formatTime(session.startedAt))
                .proWorkTextStyle(.caption)
                .monospacedDigit()
                .proWorkFrame(width: 60, alignment: .center)

            Text(endTimeText(session))
                .proWorkTextStyle(.caption)
                .monospacedDigit()
                .foregroundStyle(session.endedAt == nil ? ProWorkColors.activeHighlight : .secondary)
                .proWorkFrame(width: 60, alignment: .center)

            Text(ProWorkFormatters.durationHHmm(durationSeconds(session)))
                .proWorkTextStyle(.caption)
                .monospacedDigit()
                .proWorkFrame(width: 60, alignment: .center)

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(2, using: settingsStore)) {
                HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                    Text(session.todoTitle)
                        .proWorkTextStyle(.callout)
                        .lineLimit(1)

                    if session.endedAt == nil {
                        activeSessionBadge
                    }
                }

                if let note = session.note, !note.isEmpty {
                    Text(note)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .proWorkFrame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            Text(customerProjectText(session))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .proWorkFrame(width: 190, alignment: .leading)

            sourceBadge(session)
                .proWorkFrame(width: 60, alignment: .leading)
        }
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(9, using: settingsStore))
        .background(rowBackground(session))
    }

    private func rowActions(_ session: WorkSessionListItem) -> some View {
        HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            if session.endedAt == nil {
                Button {
                    stopWork(for: session)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .proWorkFont(size: 16)
                        .foregroundStyle(ProWorkColors.stopAction)
                }
                .buttonStyle(.borderless)
                .help(settingsStore.localized("workSessions.action.stop", defaultValue: "Çalışmayı durdur"))
            } else if session.statusStartsTimer && !hasActiveSession(for: session.todoId) {
                Button {
                    requestStartWork(for: session)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .proWorkFont(size: 16)
                        .foregroundStyle(ProWorkColors.startAction)
                }
                .buttonStyle(.borderless)
                .help(settingsStore.localized("workSessions.action.start", defaultValue: "Çalışmayı başlat"))
            }

            Button {
                editingSession = session
            } label: {
                Image(systemName: "pencil")
                    .proWorkFont(size: 15)
            }
            .buttonStyle(.borderless)
            .disabled(session.endedAt == nil)
            .help(session.endedAt == nil ? settingsStore.localized("workSessions.form.error.activeEdit", defaultValue: "Aktif çalışma düzenlenemez. Önce çalışmayı durdurmalısınız.") : settingsStore.localized("customers.action.edit", defaultValue: "Düzenle"))

            Button(role: .destructive) {
                askDeleteSession(session)
            } label: {
                Image(systemName: "trash")
                    .proWorkFont(size: 15)
            }
            .buttonStyle(.borderless)
            .help(settingsStore.localized("workSessions.delete.confirm", defaultValue: "Sil"))
        }
    }

    private var activeSessionBadge: some View {
        Text(settingsStore.localized("workSessions.status.active", defaultValue: "Aktif"))
            .proWorkTextStyle(.caption2)
            .foregroundStyle(ProWorkColors.activeHighlight)
            .padding(.horizontal, ProWorkLayout.scaled(7, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(2, using: settingsStore))
            .background(ProWorkColors.activeHighlightFill)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func sourceBadge(_ session: WorkSessionListItem) -> some View {
        if session.isManual {
            Text(settingsStore.localized("workSessions.source.manual", defaultValue: "Manuel"))
                .proWorkTextStyle(.caption2)
                .padding(.horizontal, ProWorkLayout.scaled(7, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(3, using: settingsStore))
                .background(.orange.opacity(0.16))
                .clipShape(Capsule())
        } else {
            Text("")
        }
    }

    private var emptyState: some View {
        VStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Spacer(minLength: 0)

            Image(systemName: "clock")
                .proWorkFont(size: 32)
                .foregroundStyle(.secondary)

            Text(hasActiveFilters ? settingsStore.localized("workSessions.empty.filtered", defaultValue: "Filtreyle eşleşen kayıt yok") : settingsStore.localized("workSessions.empty.title", defaultValue: "Henüz çalışma kaydı yok"))
                .proWorkTextStyle(.headline)

            Text(
                hasActiveFilters
                    ? settingsStore.localized("workSessions.empty.filteredMessage", defaultValue: "Farklı filtre seçenekleri deneyebilirsiniz.")
                    : settingsStore.localized("workSessions.empty.message", defaultValue: "Yapılacak işleri çalıştırdıkça veya manuel çalışma girdikçe burada görünecek.")
            )
            .proWorkTextStyle(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed

    private var tableMinWidth: CGFloat {
        ProWorkLayout.scaled(960, using: settingsStore)
    }

    private var totalSeconds: Int {
        filteredSessions.reduce(0) { $0 + durationSeconds($1) }
    }

    private func durationSeconds(_ session: WorkSessionListItem) -> Int {
        if let durationSeconds = session.durationSeconds {
            return durationSeconds
        }

        guard session.endedAt == nil else {
            return 0
        }

        return max(0, Int(now.timeIntervalSince(session.startedAt)))
    }

    private func endTimeText(_ session: WorkSessionListItem) -> String {
        guard let endedAt = session.endedAt else {
            return settingsStore.localized("workSessions.status.active", defaultValue: "Aktif")
        }

        return settingsStore.formatTime(endedAt)
    }

    private func customerProjectText(_ session: WorkSessionListItem) -> String {
        var parts: [String] = []

        if let customerName = session.customerName, !customerName.isEmpty {
            parts.append(customerName)
        }

        if let projectName = session.projectName, !projectName.isEmpty {
            parts.append(projectName)
        }

        return parts.isEmpty ? settingsStore.localized("todos.administrative", defaultValue: "İdari") : parts.joined(separator: " / ")
    }

    private func hasActiveSession(for todoId: String) -> Bool {
        sessions.contains { $0.todoId == todoId && $0.endedAt == nil }
    }

    @ViewBuilder
    private func rowBackground(_ session: WorkSessionListItem) -> some View {
        if session.endedAt == nil {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ProWorkColors.activeHighlight)
                    .frame(width: ProWorkLayout.scaled(4, using: settingsStore))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ProWorkColors.activeHighlightFill,
                                ProWorkColors.activeHighlightSurface,
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        } else {
            Color.clear
        }
    }

    private func clearFilters() {
        filterRange = .all
        filterStartDate = Calendar.current.startOfDay(for: Date())
        filterEndDate = Date()
        filterCustomerId = ""
        filterProjectId = ""
        filterTodoId = ""
        filterSource = .all
        filterStatus = .all
    }

    // MARK: - Data

    private func loadData() {
        do {
            sessions = try sessionRepository.fetchAllListItems()
            todos = try todoRepository.fetchAll()
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            categories = try categoryRepository.fetchAll()
            statuses = try statusRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createManualSession(
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?
    ) {
        do {
            try sessionRepository.insertManualSession(
                todoId: todoId,
                startedAt: startedAt,
                endedAt: endedAt,
                note: note
            )

            loadData()
            isShowingCreateForm = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateSession(
        id: String,
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?,
        isManual: Bool
    ) {
        do {
            try sessionRepository.updateSession(
                id: id,
                todoId: todoId,
                startedAt: startedAt,
                endedAt: endedAt,
                note: note,
                isManual: isManual
            )

            loadData()
            editingSession = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestStartWork(for session: WorkSessionListItem) {
        guard session.statusStartsTimer else {
            return
        }

        do {
            if let active = try sessionRepository.fetchActiveSession(),
               active.session.todoId != session.todoId {
                pendingWorkStart = PendingWorkStart(
                    todoId: session.todoId,
                    targetStatusId: session.statusId,
                    activeSessionId: active.session.id,
                    activeTodoTitle: active.todoTitle
                )

                confirmation = ProWorkConfirmation(
                    title: settingsStore.localized("workSessions.confirm.activeExists.title", defaultValue: "Devam eden çalışma var"),
                    message: String(format: settingsStore.localized("workSessions.confirm.activeExists.message", defaultValue: "Şu anda “%@” üzerinde çalışma devam ediyor. Bu çalışmayı durdurup yeni çalışmayı başlatmak ister misiniz?"), active.todoTitle),
                    confirmTitle: settingsStore.localized("workSessions.confirm.activeExists.confirm", defaultValue: "Durdur ve Başlat"),
                    cancelTitle: settingsStore.localized("workSessions.confirm.activeExists.cancel", defaultValue: "Mevcut Çalışma Devam Etsin")
                ) {
                    confirmPendingWorkStart()
                }

                return
            }

            try startWork(
                todoId: session.todoId,
                targetStatusId: session.statusId,
                stoppingActiveSessionId: nil
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmPendingWorkStart() {
        guard let pendingWorkStart else {
            return
        }

        do {
            try startWork(
                todoId: pendingWorkStart.todoId,
                targetStatusId: pendingWorkStart.targetStatusId,
                stoppingActiveSessionId: pendingWorkStart.activeSessionId
            )

            self.pendingWorkStart = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startWork(
        todoId: String,
        targetStatusId: String,
        stoppingActiveSessionId: String?
    ) throws {
        if let stoppingActiveSessionId {
            try sessionRepository.stopSession(
                sessionId: stoppingActiveSessionId,
                endStatusId: targetStatusId
            )
        }

        try sessionRepository.startSession(
            todoId: todoId,
            startStatusId: targetStatusId
        )

        loadData()
        errorMessage = nil
    }

    private func stopWork(for session: WorkSessionListItem) {
        do {
            try sessionRepository.stopOpenSession(
                todoId: session.todoId,
                endStatusId: session.statusId
            )

            loadData()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askDeleteSession(_ session: WorkSessionListItem) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("workSessions.delete.title", defaultValue: "Çalışma kaydı silinsin mi?"),
            message: settingsStore.localized("workSessions.delete.message", defaultValue: "Bu çalışma kaydı silinecek. Bu işlem geri alınamaz."),
            confirmTitle: settingsStore.localized("workSessions.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("workSessions.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            deleteSession(session)
        }
    }

    private func deleteSession(_ session: WorkSessionListItem) {
        do {
            try sessionRepository.delete(id: session.id)
            loadData()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum FilterSource: String {
    case all, manual, automatic
}

private enum FilterActiveStatus: String {
    case all, active, completed
}

private struct FilterOption: Identifiable {
    let id: String
    let title: String
}

private struct FilterSourceOption: Identifiable {
    let id: String
    let title: String
}

private struct FilterStatusOption: Identifiable {
    let id: String
    let title: String
}

private struct PendingWorkStart {
    let todoId: String
    let targetStatusId: String
    let activeSessionId: String
    let activeTodoTitle: String
}
