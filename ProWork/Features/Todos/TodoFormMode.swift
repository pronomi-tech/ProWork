//
//  TodoFormMode.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum TodoFormMode {
    case create
    case edit(TodoListItem)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("todoForm.mode.create", defaultValue: "Yeni Görev")
        case .edit:
            return settingsStore.localized("todoForm.mode.edit", defaultValue: "Görev Düzenle")
        }
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("common.save", defaultValue: "Kaydet")
        case .edit:
            return settingsStore.localized("todoForm.save.update", defaultValue: "Güncelle")
        }
    }
}
