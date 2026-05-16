//
//  WorkSessionFormView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

enum WorkSessionFormMode {
    case create
    case edit(WorkSessionListItem)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("workSessions.form.mode.create", defaultValue: "Manuel Çalışma Ekle")
        case .edit:
            return settingsStore.localized("workSessions.form.mode.edit", defaultValue: "Çalışma Kaydı Düzenle")
        }
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("common.save", defaultValue: "Kaydet")
        case .edit:
            return settingsStore.localized("workSessions.form.save.update", defaultValue: "Güncelle")
        }
    }
}

struct WorkSessionFormView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    let mode: WorkSessionFormMode
    let todos: [TodoListItem]
    let customers: [Customer]
    let projects: [ProjectListItem]
    let categories: [TaskCategory]
    let statuses: [TodoStatus]
    let fixedTodo: TodoListItem?

    let onTodosChanged: (([TodoListItem]) -> Void)?

    let onSave: (
        _ sessionId: String?,
        _ todoId: String,
        _ startedAt: Date,
        _ endedAt: Date,
        _ note: String?,
        _ isManual: Bool
    ) -> Void

    @State private var localTodos: [TodoListItem]
    @State private var selectedTodoId: String = ""
    @State private var workDate: Date = Date()
    @State private var startedAt: Date = Date().addingTimeInterval(-3600)
    @State private var endedAt: Date = Date()
    @State private var endDayOffset: Int = 0
    @State private var note: String = ""
    @State private var isManual: Bool = true
    @State private var isShowingCreateTodoForm = false
    @StateObject private var viewModel = WorkSessionFormViewModel()

    init(
        mode: WorkSessionFormMode,
        todos: [TodoListItem],
        customers: [Customer],
        projects: [ProjectListItem],
        categories: [TaskCategory],
        statuses: [TodoStatus],
        fixedTodo: TodoListItem? = nil,
        onTodosChanged: (([TodoListItem]) -> Void)? = nil,
        onSave: @escaping (
            _ sessionId: String?,
            _ todoId: String,
            _ startedAt: Date,
            _ endedAt: Date,
            _ note: String?,
            _ isManual: Bool
        ) -> Void
    ) {
        self.mode = mode
        self.todos = todos
        self.customers = customers
        self.projects = projects
        self.categories = categories
        self.statuses = statuses
        self.fixedTodo = fixedTodo
        self.onTodosChanged = onTodosChanged
        self.onSave = onSave
        _localTodos = State(initialValue: todos)
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: headerSubtitle,
            systemImage: "clock.badge",
            width: 760,
            height: 768
        ) {
            headerDurationSummary
        } content: {
            todoSection

            dateSection

            timeCards

            quickDurationsCompact

            noteSection
        } footer: {
            footer
        }
        .proWorkToastNotifications(
            errorMessage: viewModel.errorMessage,
            warningMessage: isActiveEditMode ? settingsStore.localized("workSessions.form.error.activeEdit", defaultValue: "Aktif çalışma kaydı düzenlenemez. Önce çalışmayı durdurmalısınız.") : nil
        )
        .onAppear {
            loadInitialValues()
        }
        .onChange(of: workDate) { _, newValue in
            syncDatesToWorkDate(newValue)
        }
        .onChange(of: endDayOffset) { _, newValue in
            syncEndDateToOffset(newValue)
        }
        .onChange(of: todos) { _, newValue in
            localTodos = newValue
            ensureValidTodoSelection()
        }
        .sheet(isPresented: $isShowingCreateTodoForm) {
            TodoFormView(
                mode: .create,
                customers: customers,
                projects: projects,
                categories: categories,
                statuses: statuses
            ) { todo in
                createTodoFromForm(todo)
            }
        }
    }

    private var headerSubtitle: String? {
        switch mode {
        case .create:
            return settingsStore.localized("workSessions.form.subtitle.create", defaultValue: "Çalışma başlangıç ve bitiş zamanını girin.")
        case .edit:
            return settingsStore.localized("workSessions.form.subtitle.edit", defaultValue: "Çalışma kaydının tarih, süre ve not bilgisini düzenleyin.")
        }
    }

    private var isActiveEditMode: Bool {
        guard case .edit(let session) = mode else {
            return false
        }

        return session.endedAt == nil
    }

    private var headerDurationSummary: some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: isValidDateRange ? "checkmark.circle" : "exclamationmark.triangle")
                .proWorkFont(size: 22)
                .foregroundStyle(isValidDateRange ? AnyShapeStyle(.blue) : AnyShapeStyle(.red))

            VStack(alignment: .trailing, spacing: ProWorkLayout.scaled(2, using: settingsStore)) {
                Text(settingsStore.localized("workSessions.summary.totalTime", defaultValue: "Toplam Süre"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                Text(ProWorkFormatters.durationHHmm(durationSeconds))
                    .proWorkFont(size: 28, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(isValidDateRange ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
            }
        }
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(8, using: settingsStore))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                .stroke(isValidDateRange ? Color.secondary.opacity(0.16) : Color.red.opacity(0.4), lineWidth: 1)
        )
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Text(settingsStore.localized("workSessions.column.todo", defaultValue: "Yapılacak İş"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            if let fixedTodo {
                fixedTodoCard(fixedTodo)
            } else {
                HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                    ProWorkSearchPickerField(
                        title: "",
                        placeholder: settingsStore.localized("workSessions.form.todo.placeholder", defaultValue: "Yapılacak iş seçin"),
                        items: localTodos,
                        selectedId: $selectedTodoId,
                        isDisabled: isActiveEditMode,
                        systemImage: "checklist",
                        itemTitle: { todo in
                            todo.title
                        },
                        itemSubtitle: { todo in
                            todoSubtitle(todo)
                        },
                        itemColor: { todo in
                            ProWorkColors.fromName(todo.statusColor)
                        },
                        matchesSearch: { todo, searchText in
                            todo.title.localizedCaseInsensitiveContains(searchText) ||
                            todo.statusName.localizedCaseInsensitiveContains(searchText) ||
                            (todo.customerName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                            (todo.projectName?.localizedCaseInsensitiveContains(searchText) ?? false)
                        }
                    )
                    .frame(maxWidth: .infinity)

                    Button {
                        isShowingCreateTodoForm = true
                    } label: {
                        Image(systemName: "plus")
                            .proWorkFont(size: 16, weight: .semibold)
                            .frame(
                                width: ProWorkLayout.scaled(34, using: settingsStore),
                                height: ProWorkLayout.scaled(34, using: settingsStore)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .help(settingsStore.localized("workSessions.form.todo.add", defaultValue: "Yeni yapılacak iş ekle"))
                    .disabled(categories.isEmpty || isActiveEditMode)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(ProWorkLayout.scaled(12, using: settingsStore))
        .frame(
            maxWidth: .infinity,
            minHeight: ProWorkLayout.scaled(96, using: settingsStore),
            alignment: .leading
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func fixedTodoCard(_ todo: TodoListItem) -> some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: "checklist")
                .proWorkFont(size: 15)
                .foregroundStyle(.secondary)

            Circle()
                .fill(ProWorkColors.fromName(todo.statusColor))
                .frame(
                    width: ProWorkLayout.scaled(9, using: settingsStore),
                    height: ProWorkLayout.scaled(9, using: settingsStore)
                )

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(2, using: settingsStore)) {
                Text(todo.title)
                    .proWorkTextStyle(.callout)
                    .lineLimit(1)

                Text(todoSubtitle(todo))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(9, using: settingsStore))
        .frame(
            maxWidth: .infinity,
            minHeight: ProWorkLayout.scaled(44, using: settingsStore),
            alignment: .leading
        )
        .background(.background.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var dateSection: some View {
        HStack(spacing: ProWorkLayout.scaled(18, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
                Image(systemName: "calendar")
                    .proWorkFont(size: 24)
                    .foregroundStyle(.secondary)
                    .frame(width: ProWorkLayout.scaled(34, using: settingsStore))

                VStack(alignment: .leading, spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                    Text(settingsStore.localized("workSessions.form.workDate", defaultValue: "Çalışma Tarihi"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)

                    ProWorkDateField(
                        title: "",
                        date: $workDate
                    )
                    .frame(width: ProWorkLayout.scaled(280, using: settingsStore), alignment: .leading)
                    .disabled(isActiveEditMode)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: ProWorkLayout.scaled(56, using: settingsStore))

            HStack(spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
                Image(systemName: "moon.stars")
                    .proWorkFont(size: 22)
                    .foregroundStyle(.secondary)
                    .frame(width: ProWorkLayout.scaled(34, using: settingsStore))

                VStack(alignment: .leading, spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                    Text(settingsStore.localized("workSessions.form.endDay", defaultValue: "Bitiş Günü"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $endDayOffset) {
                        Text(settingsStore.localized("workSessions.form.endDay.same", defaultValue: "Aynı gün")).tag(0)
                        Text(settingsStore.localized("workSessions.form.endDay.next", defaultValue: "Ertesi gün")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: ProWorkLayout.scaled(230, using: settingsStore))
                    .disabled(isActiveEditMode)
                }
            }
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var timeCards: some View {
        HStack(spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
            timeCard(
                title: settingsStore.localized("workSessions.column.start", defaultValue: "Başlangıç"),
                systemImage: "play.circle",
                date: $startedAt
            )

            timeCard(
                title: settingsStore.localized("workSessions.column.end", defaultValue: "Bitiş"),
                systemImage: "stop.circle",
                date: $endedAt
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func timeCard(
        title: String,
        systemImage: String,
        date: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 17)
                    .foregroundStyle(.secondary)

                Text(title)
                    .proWorkTextStyle(.headline)

                Spacer()
            }

            ProWorkTimeField(
                title: "",
                date: date
            )
            .disabled(isActiveEditMode)
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(
            maxWidth: .infinity,
            minHeight: ProWorkLayout.scaled(96, using: settingsStore),
            alignment: .topLeading
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var quickDurationsCompact: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            HStack(alignment: .bottom, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                    Text(settingsStore.localized("workSessions.column.start", defaultValue: "Başlangıç"))
                        .proWorkTextStyle(.caption2)
                        .foregroundStyle(.secondary)

                    Text(settingsStore.formatDateTime(startedAt))
                        .proWorkTextStyle(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: ProWorkLayout.scaled(150, using: settingsStore), alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                    quickDurationButton(String(format: settingsStore.localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), 15), minutes: 15)
                    quickDurationButton(String(format: settingsStore.localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), 30), minutes: 30)
                    quickDurationButton(String(format: settingsStore.localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), 45), minutes: 45)
                    quickDurationButton(String(format: settingsStore.localized("workSessions.form.duration.hours", defaultValue: "%d saat"), 1), minutes: 60)
                    quickDurationButton(String(format: settingsStore.localized("workSessions.form.duration.hours", defaultValue: "%d saat"), 2), minutes: 120)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                    Text(settingsStore.localized("workSessions.column.end", defaultValue: "Bitiş"))
                        .proWorkTextStyle(.caption2)
                        .foregroundStyle(.secondary)

                    Text(settingsStore.formatDateTime(endedAt))
                        .proWorkTextStyle(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: ProWorkLayout.scaled(150, using: settingsStore), alignment: .trailing)
            }
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(
            maxWidth: .infinity,
            minHeight: ProWorkLayout.scaled(60, using: settingsStore),
            alignment: .topLeading
        )
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func quickDurationButton(
        _ title: String,
        minutes: Int
    ) -> some View {
        Button {
            applyDuration(minutes: minutes)
        } label: {
            Text(title)
                .proWorkTextStyle(.caption, weight: .medium)
                .frame(width: ProWorkLayout.scaled(52, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
        }
        .buttonStyle(.bordered)
        .disabled(isActiveEditMode)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            ProWorkTextEditor(
                title: settingsStore.localized("vat.form.note", defaultValue: "Not"),
                placeholder: settingsStore.localized("workSessions.form.note.placeholder", defaultValue: "Opsiyonel not"),
                text: $note,
                minHeight: 78
            )
            .disabled(isActiveEditMode)
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var footer: some View {
        ProWorkFormFooter(
            onCancel: { dismiss() },
            onSave: { save() },
            saveTitle: mode.saveButtonTitle(using: settingsStore),
            saveDisabled: !canSave || isActiveEditMode
        )
    }

    private func todoSubtitle(_ todo: TodoListItem) -> String {
        var parts: [String] = []

        if let customerName = todo.customerName, !customerName.isEmpty {
            parts.append(customerName)
        }

        if let projectName = todo.projectName, !projectName.isEmpty {
            parts.append(projectName)
        }

        parts.append(todo.statusName)

        return parts.joined(separator: " • ")
    }

    private var effectiveTodoId: String {
        fixedTodo?.id ?? selectedTodoId
    }

    private var canSave: Bool {
        !effectiveTodoId.isEmpty && isValidDateRange
    }

    private var isValidDateRange: Bool {
        endedAt > startedAt
    }

    private var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }

    private func loadInitialValues() {
        switch mode {
        case .create:
            selectedTodoId = fixedTodo?.id ?? ""
            startedAt = roundedToFiveMinutes(Date().addingTimeInterval(-3600))
            endedAt = roundedToFiveMinutes(Date())
            workDate = startedAt
            isManual = true

            if endedAt <= startedAt {
                applyDuration(minutes: 60)
            }

        case .edit(let session):
            selectedTodoId = fixedTodo?.id ?? session.todoId
            startedAt = roundedToFiveMinutes(session.startedAt)
            endedAt = roundedToFiveMinutes(session.endedAt ?? Date())
            workDate = startedAt
            note = session.note ?? ""
            isManual = session.isManual

            if !Calendar.current.isDate(endedAt, inSameDayAs: startedAt) {
                endDayOffset = 1
            } else {
                endDayOffset = 0
            }
        }

        ensureValidTodoSelection()
    }

    private func ensureValidTodoSelection() {
        if let fixedTodo {
            selectedTodoId = fixedTodo.id
            return
        }

        guard !selectedTodoId.isEmpty else {
            return
        }

        if !localTodos.contains(where: { $0.id == selectedTodoId }) {
            selectedTodoId = ""
        }
    }

    private func createTodoFromForm(_ todo: Todo) {
        guard let refreshedTodos = viewModel.createTodo(todo) else { return }

        localTodos = refreshedTodos
        selectedTodoId = todo.id
        onTodosChanged?(refreshedTodos)
        isShowingCreateTodoForm = false
    }

    private func applyDuration(minutes: Int) {
        let newEnd = startedAt.addingTimeInterval(TimeInterval(minutes * 60))
        endedAt = newEnd

        if !Calendar.current.isDate(newEnd, inSameDayAs: workDate) {
            endDayOffset = 1
        } else {
            endDayOffset = 0
        }
    }

    private func syncDatesToWorkDate(_ newWorkDate: Date) {
        startedAt = replacingDatePart(
            of: startedAt,
            with: newWorkDate
        )

        let endBaseDate = Calendar.current.date(
            byAdding: .day,
            value: endDayOffset,
            to: newWorkDate
        ) ?? newWorkDate

        endedAt = replacingDatePart(
            of: endedAt,
            with: endBaseDate
        )
    }

    private func syncEndDateToOffset(_ offset: Int) {
        let targetDate = Calendar.current.date(
            byAdding: .day,
            value: offset,
            to: workDate
        ) ?? workDate

        endedAt = replacingDatePart(
            of: endedAt,
            with: targetDate
        )
    }

    private func replacingDatePart(
        of source: Date,
        with targetDate: Date
    ) -> Date {
        var dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: targetDate
        )

        let timeComponents = Calendar.current.dateComponents(
            [.hour, .minute],
            from: source
        )

        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = 0

        return Calendar.current.date(from: dateComponents) ?? source
    }

    private func roundedToFiveMinutes(_ date: Date) -> Date {
        let calendar = Calendar.current

        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )

        let minute = components.minute ?? 0
        components.minute = (minute / 5) * 5
        components.second = 0

        return calendar.date(from: components) ?? date
    }

    private func save() {
        guard canSave else {
            viewModel.errorMessage = settingsStore.localized("workSessions.form.error.invalidRange", defaultValue: "Yapılacak iş seçilmeli ve bitiş zamanı başlangıçtan sonra olmalıdır.")
            return
        }

        guard !isActiveEditMode else {
            viewModel.errorMessage = settingsStore.localized("workSessions.form.error.activeEdit", defaultValue: "Aktif çalışma kaydı düzenlenemez. Önce çalışmayı durdurmalısınız.")
            return
        }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let sessionId: String?
        switch mode {
        case .create:
            sessionId = nil
        case .edit(let session):
            sessionId = session.id
        }

        onSave(
            sessionId,
            effectiveTodoId,
            startedAt,
            endedAt,
            cleanNote.isEmpty ? nil : cleanNote,
            isManual
        )

        dismiss()
    }
}
