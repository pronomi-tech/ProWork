//  TodoViewMode.swift
//  ProWork
//  Created by Pronomi.
//  View modes for the Todos screen (Kanban board vs. flat list grid).
//  The segmented picker selects through this enum; each case provides
//  its own title and SF Symbol icon.

import Foundation

enum TodoViewMode: String, CaseIterable, Identifiable {
    case board
    case grid

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .board: return "rectangle.3.group"
        case .grid: return "list.bullet"
        }
    }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .board:
            return settingsStore.localized("todos.viewMode.board", defaultValue: "Pano")
        case .grid:
            return settingsStore.localized("todos.viewMode.grid", defaultValue: "Liste")
        }
    }
}
