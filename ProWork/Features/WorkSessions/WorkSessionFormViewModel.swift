//
//  WorkSessionFormViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//
//  WorkSessionFormView yalnızca tek bir repository çağrısı yapar:
//  formdan inline todo oluştururken TodoRepository.insert.
//  Bu ViewModel kapsam olarak küçük; amaç yine de repository erişimini
//  AppServices'e taşımak ve refresh'i tek noktada toplamak.
//

import Combine
import Foundation

@MainActor
final class WorkSessionFormViewModel: ObservableObject {
    @Published var errorMessage: String?

    private let todoRepository: TodoRepository

    init(services: AppServices = .shared) {
        self.todoRepository = services.todoRepository
    }

    /// Formdan inline todo oluşturur, tüm listeyi tekrar çeker ve döner.
    /// Başarısızsa errorMessage set edilir ve nil dönülür.
    func createTodo(_ todo: Todo) -> [TodoListItem]? {
        do {
            try todoRepository.insert(todo)
            let refreshed = try todoRepository.fetchAll()
            errorMessage = nil
            return refreshed
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
