//  GeneralSettingsViewModel.swift
//  ProWork
//  Created by Pronomi.

import Combine
import Foundation
import os

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    @Published private(set) var timerStartingStatuses: [TodoStatus] = []

    private let statusRepository: TodoStatusRepository

    init(services: AppServices = .shared) {
        self.statusRepository = services.statusRepository
    }

    /// Returns the timer-starting active statuses, ordered, for the
    /// MenuBar quick-timer dropdown.
    ///
    /// Fetch errors are no longer swallowed by a silent `try?`; we log
    /// and leave the list empty. The dropdown has no inline error banner
    /// channel, so the error stays hidden in the UI but visible in
    /// Console.app — surfaced for the operator rather than a quiet reset.
    func loadTimerStartingStatuses() {
        let loaded: [TodoStatus]
        do {
            loaded = try statusRepository.fetchAll()
        } catch {
            ProWorkLog.app.error(
                "GeneralSettingsViewModel.loadTimerStartingStatuses fetch failed: \(error.localizedDescription, privacy: .private)"
            )
            loaded = []
        }
        timerStartingStatuses = loaded
            .filter { $0.isActive && $0.startsTimer }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
