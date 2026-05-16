//
//  TodosView.swift
//  ProWork
//
//  Created by Pronomi.
//

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

    private var todoList: some View {
        Group {
            if viewModel.categories.isEmpty {
                emptyState(
                    systemImage: "tag",
                    title: settingsStore.localized("todos.empty.noCategory.title", defaultValue: "Görev kategorisi yok"),
                    message: settingsStore.localized("todos.empty.noCategory.message", defaultValue: "Yapılacak iş oluşturabilmek için önce Ayarlar > Görev Kategorileri bölümünde kategori tanımlayın.")
                )
            } else if viewModel.boardStatuses.isEmpty {
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

    // MARK: - UI orkestrasyonu
    //
    // Tüm DB / mutation işleri TodosViewModel'de. View burada yalnızca:
    //   - Drag-drop sonrası "startsTimer" geçişlerinde start-work confirmation
    //     dialog'unu tetikler
    //   - askDelete / confirmPendingWorkStart gibi confirmation akışlarını kurar

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
