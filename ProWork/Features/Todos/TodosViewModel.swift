//
//  TodosViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//
//  TodosView için domain state ve repository orkestrasyonu.
//  Pattern (Madde 7 — Mimari Refactor):
//    - Repository erişimi View'dan tamamen kalkıyor; View yalnızca UI state
//      (sheet açık mı, hangi confirmation dialog gösteriliyor) tutar.
//    - Domain state ve mutasyonlar `@ObservableObject` ViewModel'e taşındı.
//    - Bağımlılıklar `AppServices` üzerinden inject ediliyor; testte alternatif
//      AppServices instance'ı verilebilir.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TodosViewModel: ObservableObject {
    @Published private(set) var todos: [TodoListItem] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [ProjectListItem] = []
    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var statuses: [TodoStatus] = []
    @Published var quickCategoryId: String = ""
    @Published var errorMessage: String?

    private let todoRepository: TodoRepository
    private let customerRepository: CustomerRepository
    private let projectRepository: ProjectRepository
    private let categoryRepository: TaskCategoryRepository
    private let statusRepository: TodoStatusRepository
    private let timeSessionRepository: TodoTimeSessionRepository

    init(services: AppServices = .shared) {
        self.todoRepository = services.todoRepository
        self.customerRepository = services.customerRepository
        self.projectRepository = services.projectRepository
        self.categoryRepository = services.categoryRepository
        self.statusRepository = services.statusRepository
        self.timeSessionRepository = services.todoTimeSessionRepository
    }

    // MARK: - Derived

    var boardStatuses: [TodoStatus] {
        statuses
            .filter { $0.isActive && $0.showInBoard }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var defaultTodoStatusId: String {
        statuses.first(where: { $0.id == BuiltInTodoStatusId.waiting })?.id
            ?? statuses.first(where: { $0.isActive })?.id
            ?? BuiltInTodoStatusId.waiting
    }

    func categoryDefaultBillable(categoryId: String) -> Bool {
        categories.first(where: { $0.id == categoryId })?.isBillableDefault ?? true
    }

    func todosForStatus(_ status: TodoStatus) -> [TodoListItem] {
        todos.filter { $0.statusId == status.id }
    }

    // MARK: - Load

    func load() {
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

    // MARK: - CRUD

    func quickAdd(title: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
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

        create(todo)
    }

    /// `create` başarılıysa `true` döner; View dialog'u kapatma kararını buna göre verir.
    @discardableResult
    func create(_ todo: Todo) -> Bool {
        do {
            try todoRepository.insert(todo)
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ todo: Todo) -> Bool {
        do {
            try todoRepository.update(todo)
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(id: String) {
        do {
            // Soft delete kullanıyoruz: kaydın açık çalışma session'ı veya
            // finalize edilmiş billing line'ları varsa hard delete yetim satır
            // bırakırdı. `softDelete` `deletedAt` damgalar; raporlar etkilenmez.
            try todoRepository.softDelete(id: id)
            load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Status moves

    /// Kullanıcı board'da bir todo'yu farklı statüye sürüklediğinde çağrılır.
    /// `targetStatus.startsTimer` ise View, bir confirmation flow başlatmalı;
    /// bu metod sadece DB tarafını yürütür.
    func moveTodo(
        _ todo: TodoListItem,
        to targetStatus: TodoStatus
    ) -> MoveTodoResult {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else {
            return .skipped
        }

        let previousTodo = todos[index]
        guard previousTodo.statusId != targetStatus.id else {
            return .skipped
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

        todos[index] = updatedTodo

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
            return targetStatus.startsTimer ? .needsWorkStart : .moved
        } catch {
            todos[index] = previousTodo
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    enum MoveTodoResult {
        case moved
        case needsWorkStart
        case failed
        case skipped
    }

    // MARK: - Work session control

    /// Aktif (paused olmayan) ve farklı bir todo üzerinde çalışan session varsa döner.
    /// View bunu confirmation dialog tetiklemek için kullanır.
    func activeSessionConflicting(with todoId: String) -> ActiveTodoTimeSession? {
        do {
            if let active = try timeSessionRepository.fetchActiveSession(),
               active.session.todoId != todoId {
                return active
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }

    func startWork(
        todoId: String,
        targetStatus: TodoStatus,
        stoppingActiveSessionId: String?
    ) {
        do {
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
                todos[index] = updatedTodo
            }

            errorMessage = nil
            scheduleReload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopWork(for todo: TodoListItem) {
        do {
            try timeSessionRepository.stopOpenSession(
                todoId: todo.id,
                endStatusId: todo.statusId
            )

            if let index = todos.firstIndex(where: { $0.id == todo.id }) {
                var updatedTodo = todos[index]
                updatedTodo.activeSessionStartedAt = nil
                updatedTodo.updatedAt = Date()
                todos[index] = updatedTodo
            }

            errorMessage = nil
            scheduleReload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Status değiştirme / start work sonrası kısa bir gecikme ile listeyi yenile.
    /// DB tarafı güncellendikten sonra UI özet alanları (active session etc.) için
    /// yeniden çekim gerekiyor.
    private func scheduleReload() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.load()
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
}
