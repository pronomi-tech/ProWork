//
//  GeneralSettingsViewModel.swift
//  ProWork
//
//  Created by Pronomi.
//

import Combine
import Foundation

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    @Published private(set) var timerStartingStatuses: [TodoStatus] = []

    private let statusRepository: TodoStatusRepository

    init(services: AppServices = .shared) {
        self.statusRepository = services.statusRepository
    }

    /// MenuBar quick-timer dropdown'ı için zamanlayıcı başlatabilen aktif
    /// statüleri sıralı şekilde döner.
    func loadTimerStartingStatuses() {
        let loaded = (try? statusRepository.fetchAll()) ?? []
        timerStartingStatuses = loaded
            .filter { $0.isActive && $0.startsTimer }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
