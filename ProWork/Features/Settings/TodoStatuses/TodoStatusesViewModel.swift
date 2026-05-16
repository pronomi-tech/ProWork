//
//  TodoStatusesViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class TodoStatusesViewModel: ObservableObject {
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
        do {
            try statusRepository.insert(status)
            load()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func update(_ status: TodoStatus) -> Bool {
        do {
            try statusRepository.update(status)
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
            try statusRepository.delete(id: id)
            load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
