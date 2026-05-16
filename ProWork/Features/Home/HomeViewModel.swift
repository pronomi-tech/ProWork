//
//  HomeViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var todos: [TodoListItem] = []
    @Published private(set) var sessions: [WorkSessionListItem] = []
    @Published var errorMessage: String?

    private let todoRepository: TodoRepository
    private let sessionRepository: TodoTimeSessionRepository

    init(services: AppServices = .shared) {
        self.todoRepository = services.todoRepository
        self.sessionRepository = services.todoTimeSessionRepository
    }

    func loadData() {
        do {
            todos = try todoRepository.fetchAll()
            sessions = try sessionRepository.fetchAllListItems()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
