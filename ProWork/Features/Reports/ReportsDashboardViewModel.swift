//
//  ReportsDashboardViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class ReportsDashboardViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkSessionListItem] = []
    @Published private(set) var todos: [TodoListItem] = []
    @Published private(set) var customers: [Customer] = []
    @Published private(set) var projects: [ProjectListItem] = []
    @Published var errorMessage: String?

    private let sessionRepository: TodoTimeSessionRepository
    private let todoRepository: TodoRepository
    private let customerRepository: CustomerRepository
    private let projectRepository: ProjectRepository

    init(services: AppServices = .shared) {
        self.sessionRepository = services.todoTimeSessionRepository
        self.todoRepository = services.todoRepository
        self.customerRepository = services.customerRepository
        self.projectRepository = services.projectRepository
    }

    func loadData() {
        do {
            sessions = try sessionRepository.fetchAllListItems()
            todos = try todoRepository.fetchAll()
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
