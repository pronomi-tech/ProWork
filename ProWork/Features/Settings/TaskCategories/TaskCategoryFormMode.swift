
//
//  TaskCategoryFormMode.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum TaskCategoryFormMode {
    case create
    case edit(TaskCategory)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("taskCategories.form.mode.createTitle", defaultValue: "Yeni Görev Kategorisi")
        case .edit:
            return settingsStore.localized("taskCategories.form.mode.editTitle", defaultValue: "Görev Kategorisi Düzenle")
        }
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("taskCategories.form.action.save", defaultValue: "Kaydet")
        case .edit:
            return settingsStore.localized("taskCategories.form.action.update", defaultValue: "Güncelle")
        }
    }
}
