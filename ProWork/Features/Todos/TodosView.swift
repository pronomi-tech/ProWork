//  TodosView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct TodosView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = TodosViewModel()

    @State private var quickTitle: String = ""
    @State private var isShowingCreateForm = false
    @State private var editingTodo: TodoListItem?
    @State private var showingSessionsForTodo: TodoListItem?

    @State private var pendingWorkStart: PendingWorkStart?
    @State private var confirmation: ProWorkConfirmation?

    /// View mode — Board (Kanban) or List (Grid).
    /// The user's selection is kept in state for the session;
    /// defaults back to .board when the page reopens.
    @State private var viewMode: TodoViewMode = .board

    private var canQuickAdd: Bool {
        !quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.quickCategoryId.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            header

            quickAddBar

            todoList
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
        .proWorkFrame(minWidth: 760, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $isShowingCreateForm) {
            TodoFormView(
                mode: .create,
                customers: viewModel.customers,
                projects: viewModel.projects,
                categories: viewModel.categories,
                statuses: viewModel.statuses
            ) { todo in
                if viewModel.create(todo) {
                    isShowingCreateForm = false
                }
            }
        }
        .sheet(item: $editingTodo) { todo in
            TodoFormView(
                mode: .edit(todo),
                customers: viewModel.customers,
                projects: viewModel.projects,
                categories: viewModel.categories,
                statuses: viewModel.statuses
            ) { updatedTodo in
                if viewModel.update(updatedTodo) {
                    editingTodo = nil
                }
            }
        }
        .sheet(item: $showingSessionsForTodo) { todo in
            TodoTimeSessionsView(todo: todo)
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var header: some View {
        // Three-zone toolbar: left identity (title+subtitle), centre
        // navigation (Board/List), right primary action. Picker is
        // centred between two Spacers; Apple Music / Photos pattern.
        // Title can inflate the left zone on long localised text, so
        // we give the picker `.layoutPriority(1)` to keep it centred.
        HStack(alignment: .center, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("todos.title", defaultValue: "Yapılacak Listesi"))
                    .proWorkTextStyle(.largeTitle)

                Text(settingsStore.localized("todos.subtitle", defaultValue: "Yapılacak işleri müşteri, proje, kategori ve statü kırılımıyla yönetin."))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            viewModePicker
                .layoutPriority(1)

            Spacer()

            Button {
                isShowingCreateForm = true
            } label: {
                ProWorkButtonLabel(
                    title: settingsStore.localized("todos.action.detailed", defaultValue: "Detaylı Kayıt"),
                    systemImage: "plus",
                    minHeight: 32
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.categories.isEmpty)
            .help(viewModel.categories.isEmpty ? settingsStore.localized("todos.help.needCategory", defaultValue: "Önce görev kategorisi eklemelisiniz") : settingsStore.localized("todos.help.addDetailed", defaultValue: "Detaylı yapılacak iş ekle"))
        }
    }

    private var quickAddBar: some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            ProWorkTextField(
                placeholder: settingsStore.localized("todos.quick.placeholder", defaultValue: "Yeni yapılacak iş yaz ve Enter'a bas"),
                text: $quickTitle,
                minHeight: 40,
                submitLabel: .done
            )

            ProWorkSearchPickerField(
                placeholder: viewModel.categories.isEmpty ? settingsStore.localized("todos.quick.category.none", defaultValue: "Kategori yok") : settingsStore.localized("todos.quick.category.placeholder", defaultValue: "Kategori seçin"),
                items: viewModel.categories,
                selectedId: $viewModel.quickCategoryId,
                isDisabled: viewModel.categories.isEmpty,
                showsSearch: viewModel.categories.count > 8,
                systemImage: "tag",
                itemTitle: { category in
                    category.name
                },
                itemSubtitle: { category in
                    category.isBillableDefault ? settingsStore.localized("todos.quick.category.billableDefault", defaultValue: "Varsayılan: Faturalandırılır") : settingsStore.localized("todos.quick.category.administrativeDefault", defaultValue: "Varsayılan: İdari")
                },
                itemColor: { _ in
                    nil
                },
                matchesSearch: { category, searchText in
                    category.name.localizedCaseInsensitiveContains(searchText)
                }
            )
            .proWorkFrame(width: 240)

            Button {
                viewModel.quickAdd(title: quickTitle)
                quickTitle = ""
            } label: {
                ProWorkButtonLabel(
                    title: settingsStore.localized("todos.action.add", defaultValue: "Ekle"),
                    systemImage: "plus",
                    minHeight: 30
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canQuickAdd)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(ProWorkLayout.scaled(12, using: settingsStore))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    /// Modern pill-style tab picker. The system `.segmented` Picker
    /// looked narrow and flat on macOS; this structure provides a wide
    /// clickable area, accent fill for the selected pill, hover and
    /// focus states.
    /// Pattern, WorkSessions filter chip'lerinden esinleniyor — uygulama
    /// uses the same geometry/spacing for cross-screen consistency.
    private var viewModePicker: some View {
        HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            ForEach(TodoViewMode.allCases) { mode in
                viewModePill(for: mode)
            }
        }
        .padding(ProWorkLayout.scaled(4, using: settingsStore))
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
    }

    private func viewModePill(for mode: TodoViewMode) -> some View {
        let isSelected = viewMode == mode

        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                viewMode = mode
            }
        } label: {
            HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                Image(systemName: mode.systemImage)
                    .proWorkFont(size: 13, weight: .medium)
                // Weight stays `.medium` — switching between bold/regular
                // changed the pill width and shifted the parent layout.
                // Vurguyu accent dolgu + beyaz foreground veriyor.
                Text(mode.title(using: settingsStore))
                    .proWorkTextStyle(.callout, weight: .medium)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, ProWorkLayout.scaled(14, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(7, using: settingsStore))
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore))
                            .fill(Color.accentColor)
                    } else {
                        RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore))
                            .fill(Color.clear)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(mode.title(using: settingsStore))
    }

    @ViewBuilder
    private var todoList: some View {
        if viewModel.categories.isEmpty {
            emptyState(
                systemImage: "tag",
                title: settingsStore.localized("todos.empty.noCategory.title", defaultValue: "Görev kategorisi yok"),
                message: settingsStore.localized("todos.empty.noCategory.message", defaultValue: "Yapılacak iş oluşturabilmek için önce Ayarlar > Görev Kategorileri bölümünde kategori tanımlayın.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.boardStatuses.isEmpty && viewMode == .board {
            emptyState(
                systemImage: "rectangle.3.group",
                title: settingsStore.localized("todos.empty.noBoardStatus.title", defaultValue: "İş panosu statüsü yok"),
                message: settingsStore.localized("todos.empty.noBoardStatus.message", defaultValue: "Yapılacak listesi için Ayarlar > İş Akışı Statüleri bölümünde panoda gösterilecek en az bir statü tanımlayın.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewMode {
            case .board:
                workBoard
            case .grid:
                todoGrid
            }
        }
    }

    private var todoGrid: some View {
        ProWorkGrid(
            items: viewModel.todos,
            header: { todoTableHeader },
            emptyContent: {
                ProWorkGridEmptyState(
                    systemImage: "checklist",
                    title: settingsStore.localized("todos.empty.grid.title", defaultValue: "Henüz yapılacak iş yok"),
                    message: settingsStore.localized("todos.empty.grid.message", defaultValue: "Üstteki hızlı ekleme veya 'Detaylı Kayıt' ile iş oluşturabilirsiniz.")
                )
            },
            row: { todo in todoGridRow(todo) }
        )
    }

    private var todoTableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("todos.column.title", defaultValue: "Başlık"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("todos.column.customerProject", defaultValue: "Müşteri / Proje"))
                .frame(width: 200, alignment: .leading)
            Text(settingsStore.localized("todos.column.category", defaultValue: "Kategori"))
                .frame(width: 140, alignment: .leading)
            Text(settingsStore.localized("todos.column.status", defaultValue: "Statü"))
                .frame(width: 130, alignment: .leading)
            Text(settingsStore.localized("todos.column.dueDate", defaultValue: "Vade"))
                .frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("todos.column.tracked", defaultValue: "Süre"))
                .frame(width: 80, alignment: .trailing)
            Color.gridHeaderSpacer(width: 130)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func isOverdue(_ todo: TodoListItem) -> Bool {
        guard let due = todo.dueDate, todo.completedAt == nil else { return false }
        return due < Date()
    }

    private func todoGridRow(_ todo: TodoListItem) -> some View {
        let parts = [todo.customerName, todo.projectName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " / ")
        let customerProject = parts.isEmpty
            ? settingsStore.localized("todos.administrative", defaultValue: "İdari")
            : parts
        let dueText = todo.dueDate.map { settingsStore.formatDate($0) } ?? "—"
        let trackedText = ProWorkFormatters.durationHHmm(todo.totalTrackedSeconds)
        let isRunning = todo.activeSessionStartedAt != nil

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .lineLimit(1)
                if let description = todo.description, !description.isEmpty {
                    Text(description)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(customerProject)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(ProWorkColors.fromName(todo.categoryColor ?? "gray"))
                    .frame(width: 8, height: 8)
                Text(todo.categoryName)
                    .proWorkTextStyle(.caption)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(ProWorkColors.fromName(todo.statusColor ?? "gray"))
                    .frame(width: 8, height: 8)
                Text(todo.statusName)
                    .proWorkTextStyle(.caption)
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)

            Text(dueText)
                .proWorkTextStyle(.caption)
                .foregroundStyle(isOverdue(todo) ? Color.red : Color.secondary)
                .frame(width: 110, alignment: .leading)

            Text(trackedText)
                .proWorkTextStyle(.callout)
                .monospacedDigit()
                .foregroundStyle(isRunning ? ProWorkColors.activeHighlight : .primary)
                .frame(width: 80, alignment: .trailing)

            HStack(spacing: 6) {
                Button {
                    if isRunning {
                        viewModel.stopWork(for: todo)
                    } else {
                        requestStartWork(for: todo)
                    }
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isRunning ? .red : .accentColor)
                .help(isRunning ? settingsStore.localized("todos.action.stop", defaultValue: "Durdur") : settingsStore.localized("todos.action.start", defaultValue: "Başlat"))

                Button {
                    showingSessionsForTodo = todo
                } label: {
                    Image(systemName: "clock.arrow.circlepath").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help(settingsStore.localized("todos.action.sessions", defaultValue: "Çalışma kayıtları"))

                Button {
                    editingTodo = todo
                } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button {
                    askDeleteTodo(todo)
                } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var workBoard: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
                ForEach(viewModel.boardStatuses) { status in
                    TodoBoardColumnView(
                        status: status,
                        todos: viewModel.todosForStatus(status),
                        onEdit: { todo in
                            editingTodo = todo
                        },
                        onShowSessions: { todo in
                            showingSessionsForTodo = todo
                        },
                        onStartWork: { todo in
                            requestStartWork(for: todo)
                        },
                        onStopWork: { todo in
                            viewModel.stopWork(for: todo)
                        },
                        onDelete: { todo in
                            askDeleteTodo(todo)
                        },
                        onMoveTodo: { todo, targetStatus in
                            handleMoveTodo(todo, to: targetStatus)
                        }
                    )
                }
            }
            .padding(.vertical, ProWorkLayout.scaled(4, using: settingsStore))
            .padding(.trailing, ProWorkLayout.scaled(12, using: settingsStore))
            .animation(.snappy, value: viewModel.todos)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func emptyState(
        systemImage: String,
        title: String,
        message: String
    ) -> some View {
        VStack(alignment: .center, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: 34)
                .foregroundStyle(.secondary)

            Text(title)
                .proWorkTextStyle(.title2)

            Text(message)
                .proWorkTextStyle(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .proWorkFrame(maxWidth: 460)
    }

    // MARK: - UI orchestration
    // All DB / mutation work lives in TodosViewModel. The view only:
    //   - Triggers a start-work confirmation dialog on "startsTimer"
    //     transitions after drag-drop
    //   - Wires confirmation flows like askDelete / confirmPendingWorkStart

    private func handleMoveTodo(_ todo: TodoListItem, to targetStatus: TodoStatus) {
        let result = viewModel.moveTodo(todo, to: targetStatus)
        if result == .needsWorkStart {
            requestStartWork(todoId: todo.id, targetStatus: targetStatus)
        }
    }

    private func requestStartWork(for todo: TodoListItem) {
        guard todo.statusStartsTimer else { return }
        guard let status = viewModel.statuses.first(where: { $0.id == todo.statusId }) else { return }
        requestStartWork(todoId: todo.id, targetStatus: status)
    }

    private func requestStartWork(todoId: String, targetStatus: TodoStatus) {
        if let active = viewModel.activeSessionConflicting(with: todoId) {
            pendingWorkStart = PendingWorkStart(
                todoId: todoId,
                targetStatus: targetStatus,
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
            todoId: todoId,
            targetStatus: targetStatus,
            stoppingActiveSessionId: nil
        )
    }

    private func confirmPendingWorkStart() {
        guard let pendingWorkStart else { return }
        viewModel.startWork(
            todoId: pendingWorkStart.todoId,
            targetStatus: pendingWorkStart.targetStatus,
            stoppingActiveSessionId: pendingWorkStart.activeSessionId
        )
        self.pendingWorkStart = nil
    }

    private func askDeleteTodo(_ todo: TodoListItem) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("todos.delete.title", defaultValue: "Yapılacak iş silinsin mi?"),
            message: String(format: settingsStore.localized("todos.delete.message", defaultValue: "“%@” yapılacak iş kaydı silinecek. Bu işlem geri alınamaz."), todo.title),
            confirmTitle: settingsStore.localized("todos.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("todos.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.delete(id: todo.id)
        }
    }
}

private struct PendingWorkStart {
    let todoId: String
    let targetStatus: TodoStatus
    let activeSessionId: String
    let activeTodoTitle: String
}
