//  TodoStatusesViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation

@MainActor
final class TodoStatusesViewModel: ObservableObject, CRUDListViewModel {
    @Published private(set) var statuses: [TodoStatus] = []
    @Published var errorMessage: String?

    private let statusRepository: TodoStatusRepository

    init(services: AppServices = .shared) {
        self.statusRepository = services.statusRepository
    }

    func load() {
        do {
            statuses = try statusRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func create(_ status: TodoStatus) -> Bool {
        performMutation { try statusRepository.insert(status) }
    }

    @discardableResult
    func update(_ status: TodoStatus) -> Bool {
        performMutation { try statusRepository.update(status) }
    }

    func delete(id: String) {
        performMutation { try statusRepository.softDelete(id: id, by: AppServices.currentUserId) }
    }
}
