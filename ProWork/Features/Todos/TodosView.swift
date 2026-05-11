//
//  TodosView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct TodosView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var todos: [TodoListItem] = []
    @State private var customers: [Customer] = []
    @State private var projects: [ProjectListItem] = []
    @State private var categories: [TaskCategory] = []
    @State private var statuses: [TodoStatus] = []

    @State private var quickTitle: String = ""
    @State private var quickCategoryId: String = ""

    @State private var isShowingCreateForm = false
    @State private var editingTodo: TodoListItem?
    @State private var showingSessionsForTodo: TodoListItem?

    @State private var pendingWorkStart: PendingWorkStart?
    @State private var confirmation: ProWorkConfirmation?
    @State private var errorMessage: String?

    private let todoRepository = TodoRepository()
    private let customerRepository = CustomerRepository()
    private let projectRepository = ProjectRepository()
    private let categoryRepository = TaskCategoryRepository()
    private let statusRepository = TodoStatusRepository()
    private let timeSessionRepository = TodoTimeSessionRepository()

    private var canQuickAdd: Bool {
        !quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !quickCategoryId.isEmpty
    }

    private var boardStatuses: [TodoStatus] {
        statuses
            .filter { $0.isActive && $0.showInBoard }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var defaultTodoStatusId: String {
        statuses.first(where: { $0.id == BuiltInTodoStatusId.waiting })?.id
            ?? statuses.first(where: { $0.isActive })?.id
            ?? BuiltInTodoStatusId.waiting
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
        .proWorkToastNotifications(errorMessage: errorMessage)
        .onAppear {
            loadData()
        }
        .sheet(isPresented: $isShowingCreateForm) {
            TodoFormView(
                mode: .create,
                customers: customers,
                projects: projects,
                categories: categories,
                statuses: statuses
            ) { todo in
                createTodo(todo)
            }
        }
        .sheet(item: $editingTodo) { todo in
            TodoFormView(
                mode: .edit(todo),
                customers: customers,
                projects: projects,
                categories: categories,
                statuses: statuses
            ) { updatedTodo in
                updateTodo(updatedTodo)
            }
        }
        .sheet(item: $showingSessionsForTodo) { todo in
            TodoTimeSessionsView(todo: todo)
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("todos.title", defaultValue: "Yapılacak Listesi"))
                    .proWorkTextStyle(.largeTitle)

                Text(settingsStore.localized("todos.subtitle", defaultValue: "Yapılacak işleri müşteri, proje, kategori ve statü kırılımıyla yönetin."))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
            }

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
            .disabled(categories.isEmpty)
            .help(categories.isEmpty ? settingsStore.localized("todos.help.needCategory", defaultValue: "Önce görev kategorisi eklemelisiniz") : settingsStore.localized("todos.help.addDetailed", defaultValue: "Detaylı yapılacak iş ekle"))
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
                placeholder: categories.isEmpty ? settingsStore.localized("todos.quick.category.none", defaultValue: "Kategori yok") : settingsStore.localized("todos.quick.category.placeholder", defaultValue: "Kategori seçin"),
                items: categories,
                selectedId: $quickCategoryId,
                isDisabled: categories.isEmpty,
                showsSearch: categories.count > 8,
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
                quickAddTodo()
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

    private var todoList: some View {
        Group {
            if categories.isEmpty {
                emptyState(
                    systemImage: "tag",
                    title: settingsStore.localized("todos.empty.noCategory.title", defaultValue: "Görev kategorisi yok"),
                    message: settingsStore.localized("todos.empty.noCategory.message", defaultValue: "Yapılacak iş oluşturabilmek için önce Ayarlar > Görev Kategorileri bölümünde kategori tanımlayın.")
                )
            } else if boardStatuses.isEmpty {
                emptyState(
                    systemImage: "rectangle.3.group",
                    title: settingsStore.localized("todos.empty.noBoardStatus.title", defaultValue: "İş panosu statüsü yok"),
                    message: settingsStore.localized("todos.empty.noBoardStatus.message", defaultValue: "Yapılacak listesi için Ayarlar > İş Akışı Statüleri bölümünde panoda gösterilecek en az bir statü tanımlayın.")
                )
            } else {
                workBoard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workBoard: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
                ForEach(boardStatuses) { status in
                    TodoBoardColumnView(
                        status: status,
                        todos: todosForStatus(status),
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
                            stopWork(for: todo)
                        },
                        onDelete: { todo in
                            askDeleteTodo(todo)
                        },
                        onMoveTodo: { todo, targetStatus in
                            moveTodo(todo, to: targetStatus)
                        }
                    )
                }
            }
            .padding(.vertical, ProWorkLayout.scaled(4, using: settingsStore))
            .padding(.trailing, ProWorkLayout.scaled(12, using: settingsStore))
            .animation(.snappy, value: todos)
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

    private func todosForStatus(_ status: TodoStatus) -> [TodoListItem] {
        todos.filter { $0.statusId == status.id }
    }

    private func loadData() {
        do {
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            categories = try categoryRepository.fetchAll()
            statuses = try statusRepository.fetchAll()
            todos = try todoRepository.fetchAll()

            if quickCategoryId.isEmpty {
                quickCategoryId = categories.first?.id ?? ""
            }

            if !quickCategoryId.isEmpty,
               !categories.contains(where: { $0.id == quickCategoryId }) {
                quickCategoryId = categories.first?.id ?? ""
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quickAddTodo() {
        let cleanTitle = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty, !quickCategoryId.isEmpty else {
            return
        }

        let todo = Todo(
            categoryId: quickCategoryId,
            title: cleanTitle,
            statusId: defaultTodoStatusId,
            priority: "normal",
            isBillable: categoryDefaultBillable(categoryId: quickCategoryId)
        )

        createTodo(todo)

        quickTitle = ""
    }

    private func categoryDefaultBillable(categoryId: String) -> Bool {
        categories.first(where: { $0.id == categoryId })?.isBillableDefault ?? true
    }

    private func createTodo(_ todo: Todo) {
        do {
            try todoRepository.insert(todo)
            loadData()
            isShowingCreateForm = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateTodo(_ todo: Todo) {
        do {
            try todoRepository.update(todo)
            loadData()
            editingTodo = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveTodo(_ todo: TodoListItem, to targetStatus: TodoStatus) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else {
            return
        }

        let previousTodo = todos[index]

        guard previousTodo.statusId != targetStatus.id else {
            return
        }

        let completedAt: Date?
        if targetStatus.marksCompleted {
            completedAt = previousTodo.completedAt ?? Date()
        } else {
            completedAt = nil
        }

        let updatedTodo = makeUpdatedTodo(
            previousTodo,
            targetStatus: targetStatus,
            completedAt: completedAt,
            activeSessionStartedAt: nil
        )

        withAnimation(.snappy) {
            todos[index] = updatedTodo
        }

        do {
            if targetStatus.stopsTimer {
                try timeSessionRepository.stopOpenSession(
                    todoId: previousTodo.id,
                    endStatusId: targetStatus.id
                )
            }

            try todoRepository.updateStatus(
                id: previousTodo.id,
                statusId: targetStatus.id,
                completedAt: completedAt
            )

            errorMessage = nil

            if targetStatus.startsTimer {
                requestStartWorkAfterStatusMove(
                    todoId: previousTodo.id,
                    targetStatus: targetStatus
                )
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    loadData()
                }
            }
        } catch {
            withAnimation(.snappy) {
                todos[index] = previousTodo
            }

            errorMessage = error.localizedDescription
        }
    }

    private func requestStartWork(for todo: TodoListItem) {
        guard todo.statusStartsTimer else {
            return
        }

        guard let status = statuses.first(where: { $0.id == todo.statusId }) else {
            return
        }

        requestStartWork(
            todoId: todo.id,
            targetStatus: status
        )
    }

    private func requestStartWorkAfterStatusMove(
        todoId: String,
        targetStatus: TodoStatus
    ) {
        requestStartWork(
            todoId: todoId,
            targetStatus: targetStatus
        )
    }

    private func requestStartWork(
        todoId: String,
        targetStatus: TodoStatus
    ) {
        do {
            if let active = try timeSessionRepository.fetchActiveSession(),
               active.session.todoId != todoId {
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

            try startWork(
                todoId: todoId,
                targetStatus: targetStatus,
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
                targetStatus: pendingWorkStart.targetStatus,
                stoppingActiveSessionId: pendingWorkStart.activeSessionId
            )

            self.pendingWorkStart = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startWork(
        todoId: String,
        targetStatus: TodoStatus,
        stoppingActiveSessionId: String?
    ) throws {
        if let stoppingActiveSessionId {
            try timeSessionRepository.stopSession(
                sessionId: stoppingActiveSessionId,
                endStatusId: targetStatus.id
            )
        }

        try timeSessionRepository.startSession(
            todoId: todoId,
            startStatusId: targetStatus.id
        )

        if let index = todos.firstIndex(where: { $0.id == todoId }) {
            var updatedTodo = todos[index]
            updatedTodo.activeSessionStartedAt = Date()
            updatedTodo.updatedAt = Date()

            withAnimation(.snappy) {
                todos[index] = updatedTodo
            }
        }

        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            loadData()
        }
    }

    private func stopWork(for todo: TodoListItem) {
        do {
            try timeSessionRepository.stopOpenSession(
                todoId: todo.id,
                endStatusId: todo.statusId
            )

            if let index = todos.firstIndex(where: { $0.id == todo.id }) {
                var updatedTodo = todos[index]
                updatedTodo.activeSessionStartedAt = nil
                updatedTodo.updatedAt = Date()

                withAnimation(.snappy) {
                    todos[index] = updatedTodo
                }
            }

            errorMessage = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                loadData()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeUpdatedTodo(
        _ todo: TodoListItem,
        targetStatus: TodoStatus,
        completedAt: Date?,
        activeSessionStartedAt: Date?
    ) -> TodoListItem {
        var updatedTodo = todo
        updatedTodo.statusId = targetStatus.id
        updatedTodo.statusName = targetStatus.name
        updatedTodo.statusColor = targetStatus.color
        updatedTodo.statusStartsTimer = targetStatus.startsTimer
        updatedTodo.statusStopsTimer = targetStatus.stopsTimer
        updatedTodo.statusMarksOpen = targetStatus.marksOpen
        updatedTodo.statusMarksCompleted = targetStatus.marksCompleted
        updatedTodo.statusMarksCancelled = targetStatus.marksCancelled
        updatedTodo.completedAt = completedAt
        updatedTodo.activeSessionStartedAt = activeSessionStartedAt
        updatedTodo.updatedAt = Date()
        return updatedTodo
    }

    private func askDeleteTodo(_ todo: TodoListItem) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("todos.delete.title", defaultValue: "Yapılacak iş silinsin mi?"),
            message: String(format: settingsStore.localized("todos.delete.message", defaultValue: "“%@” yapılacak iş kaydı silinecek. Bu işlem geri alınamaz."), todo.title),
            confirmTitle: settingsStore.localized("todos.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("todos.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            deleteTodo(todo)
        }
    }

    private func deleteTodo(_ todo: TodoListItem) {
        do {
            try todoRepository.delete(id: todo.id)
            loadData()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PendingWorkStart {
    let todoId: String
    let targetStatus: TodoStatus
    let activeSessionId: String
    let activeTodoTitle: String
}
