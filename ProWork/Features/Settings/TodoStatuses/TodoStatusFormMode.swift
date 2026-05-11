//
//  TodoStatusFormMode.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum TodoStatusFormMode {
    case create
    case edit(TodoStatus)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("todoStatuses.form.mode.createTitle", defaultValue: "Yeni Statü")
        case .edit:
            return settingsStore.localized("todoStatuses.form.mode.editTitle", defaultValue: "Statü Düzenle")
        }
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("todoStatuses.form.action.save", defaultValue: "Kaydet")
        case .edit:
            return settingsStore.localized("todoStatuses.form.action.update", defaultValue: "Güncelle")
        }
    }
}
