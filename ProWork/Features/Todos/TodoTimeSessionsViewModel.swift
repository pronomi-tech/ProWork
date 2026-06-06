//  TodoTimeSessionsViewModel.swift
//  ProWork
//  Created by Pronomi.
//  Domain state and repository orchestration for TodoTimeSessionsView.

import Combine
import Foundation

@MainActor
final class TodoTimeSessionsViewModel: ObservableObject {
    @Published private(set) var sessions: [TodoTimeSession] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [ProjectListItem] = []
    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var statuses: [TodoStatus] = []
    @Published var errorMessage: String?

    private let sessionRepository: TodoTimeSessionRepository
    private let customerRepository: CustomerRepository
    private let projectRepository: ProjectRepository
    private let categoryRepository: TaskCategoryRepository
    private let statusRepository: TodoStatusRepository

    init(services: AppServices = .shared) {
        self.sessionRepository = services.todoTimeSessionRepository
        self.customerRepository = services.customerRepository
        self.projectRepository = services.projectRepository
        self.categoryRepository = services.categoryRepository
        self.statusRepository = services.statusRepository
    }

    func load(todoId: String) {
        do {
            sessions = try sessionRepository.fetchSessions(todoId: todoId)
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            categories = try categoryRepository.fetchAll()
            statuses = try statusRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createManualSession(
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?
    ) -> Bool {
        do {
            try sessionRepository.insertManualSession(
                todoId: todoId,
                startedAt: startedAt,
                endedAt: endedAt,
                note: note
            )
            load(todoId: todoId)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateSession(
        id: String,
        todoId: String,
        startedAt: Date,
        endedAt: Date,
        note: String?,
        isManual: Bool
    ) -> Bool {
        do {
            try sessionRepository.updateSession(
                id: id,
                todoId: todoId,
                startedAt: startedAt,
                endedAt: endedAt,
                note: note,
                isManual: isManual
            )
            load(todoId: todoId)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSession(id: String, refreshFor todoId: String) {
        do {
            try sessionRepository.softDelete(id: id, by: AppServices.currentUserId)
            load(todoId: todoId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
