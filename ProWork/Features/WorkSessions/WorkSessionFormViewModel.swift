//  WorkSessionFormViewModel.swift
//  ProWork
//  Created by Pronomi.
//  WorkSessionFormView only makes one repository call: TodoRepository.insert
//  when creating an inline todo from the form.
//  This ViewModel has a small scope; the goal is still to move repository
//  access into AppServices and centralise the refresh.
//
// This VM is thin (one mutation + reportError). The audit
//  flagged it as a merge candidate into WorkSessionsViewModel; kept
//  separate because:
//   - WorkSessionFormView's lifecycle differs (sheet vs list), so a
//     merged VM would carry list state into a transient form context;
//   - testability is preserved by the `services: AppServices` init
// which is the more important DI lever.
//  If the form gains state or the merged form/list flow stabilises,
//  reconsider the merge; otherwise the current split is intentional.

import Combine
import Foundation

@MainActor
final class WorkSessionFormViewModel: ObservableObject {
    /// Views push errors through `reportError(_:)`; the
    /// stored property is read-only outside the VM so callers cannot
    /// accidentally write garbage into the alert text.
    @Published private(set) var errorMessage: String?

    func reportError(_ message: String?) {
        errorMessage = message
    }

    private let todoRepository: TodoRepository

    init(services: AppServices = .shared) {
        self.todoRepository = services.todoRepository
    }

    /// Creates an inline todo from the form, refetches the entire list and
    /// returns it. On failure errorMessage is set and nil is returned.
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
