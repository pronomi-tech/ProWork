//  TodoStatusFormMode.swift
//  ProWork
//  Type-alias over the generic `FormMode<Entity>`.

import Foundation

typealias TodoStatusFormMode = FormMode<TodoStatus>

extension FormMode where Entity == TodoStatus {
    func title(using settingsStore: AppSettingsStore) -> String {
        title(
            using: settingsStore,
            createKey: "todoStatuses.form.mode.createTitle",
            createDefault: "Yeni Statü",
            editKey: "todoStatuses.form.mode.editTitle",
            editDefault: "Statü Düzenle"
        )
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        saveButtonTitle(
            using: settingsStore,
            createKey: "todoStatuses.form.action.save",
            createDefault: "Kaydet",
            editKey: "todoStatuses.form.action.update",
            editDefault: "Güncelle"
        )
    }
}
