//  WorkSessionsView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import Combine

struct WorkSessionsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = WorkSessionsViewModel()

    @State private var isShowingCreateForm = false
    @State private var editingSession: WorkSessionListItem?

    @State private var pendingWorkStart: PendingWorkStart?
    @State private var confirmation: ProWorkConfirmation?
    // Removed @State now mirror; the open-session duration
    // reads `clockTicker.halfMinute` directly so SwiftUI subscribes
    // only when an open session is actually present, mirroring the
    // TodoBoardCardView fix.

    // Filtreler
    @State private var filterRange: DateRangeFilter = .all
    @State private var filterCustomerId: String = ""
    @State private var filterProjectId: String = ""
    @State private var filterTodoId: String = ""
    @State private var filterSource: FilterSource = .all
    @State private var filterStatus: FilterActiveStatus = .all
    @State private var filterStartDate: Date = AppCalendar.istanbul.startOfDay(for: Date())
    @State private var filterEndDate: Date = Date()
    @State private var isShowingFilters: Bool = false
    /// Cached filter result. Body used to call
    /// `filteredSessions` (a `O(n_session × n_todo)` lookup) on every
    /// re-evaluation including clockTicker ticks. Now it's recomputed
    /// only when the inputs actually change.
    @State private var cachedFilteredSessions: [WorkSessionListItem] = []

    @EnvironmentObject private var clockTicker: ProWorkClockTicker

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
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.loadData()
            rebuildFilteredSessionsCache()
        }
        // ClockTicker is consumed directly by the
        // open-session row via `clockTicker.halfMinute`. The previous
        // .onReceive ran on every tick even when no session was open
        // (`guard … else { return }` was the gate, but the subscription
        // itself was always active and woke the view).
        // rebuild filtered cache on filter / data changes.
        .onChange(of: viewModel.sessions) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: viewModel.todos) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterRange) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterCustomerId) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterProjectId) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterTodoId) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterSource) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterStatus) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterStartDate) { _, _ in rebuildFilteredSessionsCache() }
        .onChange(of: filterEndDate) { _, _ in rebuildFilteredSessionsCache() }
        .sheet(isPresented: $isShowingCreateForm) {
            WorkSessionFormView(
                mode: .create,
                todos: viewModel.todos,
                customers: viewModel.customers,
                projects: viewModel.projects,
                categories: viewModel.categories,
                statuses: viewModel.statuses,
                onTodosChanged: { _ in
                    viewModel.loadData()
                }
            ) { _, todoId, startedAt, endedAt, note, _ in
                if viewModel.createManualSession(
                    todoId: todoId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    note: note
                ) {
                    isShowingCreateForm = false
                }
            }
        }
        .sheet(item: $editingSession) { session in
            WorkSessionFormView(
                mode: .edit(session),
                todos: viewModel.todos,
                customers: viewModel.customers,
                projects: viewModel.projects,
                categories: viewModel.categories,
                statuses: viewModel.statuses,
                onTodosChanged: { _ in
                    viewModel.loadData()
                }
            ) { sessionId, todoId, startedAt, endedAt, note, isManual in
                guard let sessionId else { return }

                if viewModel.updateSession(
                    id: sessionId,
                    todoId: todoId,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    note: note,
                    isManual: isManual
                ) {
                    editingSession = nil
                }
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    // MARK: - Filtered Sessions

    private var filteredSessions: [WorkSessionListItem] {
        cachedFilteredSessions
    }

    private func rebuildFilteredSessionsCache() {
        // ID-based filter via the todo lookup. The previous
        // name-based predicates (`session.customerName == expected`)
        // mixed two same-named customers and missed sessions where
        // the persisted snapshot diverged from the current name
        // .
        let todoLookup = Dictionary(uniqueKeysWithValues: viewModel.todos.map { ($0.id, $0) })
        let filterByCustomer = !filterCustomerId.isEmpty
        let filterByProject = !filterProjectId.isEmpty

        cachedFilteredSessions = viewModel.sessions.filter { session in
            guard matchesRange(session) else { return false }
            if filterByCustomer || filterByProject {
                guard let todo = todoLookup[session.todoId] else { return false }
                if filterByCustomer, todo.customerId != filterCustomerId {
                    return false
                }
                if filterByProject, todo.projectId != filterProjectId {
                    return false
                }
            }
            return matchesTodo(session)
                && matchesSource(session)
                && matchesActiveStatus(session)
        }
    }

    private func matchesRange(_ session: WorkSessionListItem) -> Bool {
        filterRange.contains(
            session.startedAt,
            customStart: filterStartDate,
            customEnd: filterEndDate
        )
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
            .disabled(viewModel.categories.isEmpty)
            .help(viewModel.categories.isEmpty ? settingsStore.localized("todos.help.needCategory", defaultValue: "Önce görev kategorisi eklemelisiniz") : settingsStore.localized("workSessions.help.addManual", defaultValue: "Manuel çalışma ekle"))
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
        viewModel.customers.map { FilterOption(id: $0.id, title: $0.name) }
    }

    private var projectFilterOptions: [FilterOption] {
        let filtered = filterCustomerId.isEmpty
            ? viewModel.projects
            : viewModel.projects.filter { $0.customerId == filterCustomerId }
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
                        showsSearch: viewModel.customers.count > 8,
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
        ProWorkGrid(
            items: filteredSessions,
            minTableWidth: tableMinWidth,
            cornerRadius: ProWorkLayout.scaled(12, using: settingsStore),
            header: { tableHeader },
            emptyContent: { emptyState },
            row: { session in row(session) }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Color.gridHeaderSpacer(width: 80)

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
                    viewModel.stopWork(for: session)
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
            Color.clear
        }
    }

    private var emptyState: some View {
        // Sits immediately below the header, taking only as much space as
        // its content needs. Previously `Spacer + maxHeight: .infinity`
        // centred it vertically, and when the table card stretched to
        // fill the page a large empty band opened up in between.
        VStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ProWorkLayout.scaled(36, using: settingsStore))
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

        return max(0, Int(clockTicker.halfMinute.timeIntervalSince(session.startedAt)))
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
        viewModel.sessions.contains { $0.todoId == todoId && $0.endedAt == nil }
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
        filterStartDate = AppCalendar.istanbul.startOfDay(for: Date())
        filterEndDate = Date()
        filterCustomerId = ""
        filterProjectId = ""
        filterTodoId = ""
        filterSource = .all
        filterStatus = .all
    }

    // MARK: - UI orkestrasyonu

    private func requestStartWork(for session: WorkSessionListItem) {
        guard session.statusStartsTimer else { return }

        if let active = viewModel.activeSessionConflicting(with: session.todoId) {
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

        viewModel.startWork(
            todoId: session.todoId,
            targetStatusId: session.statusId,
            stoppingActiveSessionId: nil
        )
    }

    private func confirmPendingWorkStart() {
        guard let pendingWorkStart else { return }
        viewModel.startWork(
            todoId: pendingWorkStart.todoId,
            targetStatusId: pendingWorkStart.targetStatusId,
            stoppingActiveSessionId: pendingWorkStart.activeSessionId
        )
        self.pendingWorkStart = nil
    }

    private func askDeleteSession(_ session: WorkSessionListItem) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("workSessions.delete.title", defaultValue: "Çalışma kaydı silinsin mi?"),
            message: settingsStore.localized("workSessions.delete.message", defaultValue: "Bu çalışma kaydı silinecek. Bu işlem geri alınamaz."),
            confirmTitle: settingsStore.localized("workSessions.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("workSessions.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.deleteSession(id: session.id)
        }
    }
}

private enum FilterSource: String {
    case all, manual, automatic
}

private enum FilterActiveStatus: String {
    case all, active, completed
}

/// Three identical `(id, title)` Identifiable structs were
/// declared inline to satisfy SwiftUI's `ForEach`/`Picker` requirements
/// with type-specific picker bindings. Collapsed into one generic
/// shape; aliases preserve the call-site readability and let a future
/// change to one filter's payload (e.g. adding `subtitle`) happen
/// without touching the others.
private struct WorkSessionFilterOption: Identifiable {
    let id: String
    let title: String
}

private typealias FilterOption = WorkSessionFilterOption
private typealias FilterSourceOption = WorkSessionFilterOption
private typealias FilterStatusOption = WorkSessionFilterOption

private struct PendingWorkStart {
    let todoId: String
    let targetStatusId: String
    let activeSessionId: String
    let activeTodoTitle: String
}
