//  TaskCategoryFormMode.swift
//  ProWork
//  Created by Pronomi.
//  Type-alias over the generic `FormMode<Entity>`. Existing call sites can
//  keep using `TaskCategoryFormMode` while new code can reach for the
//  generic directly.

import Foundation

typealias TaskCategoryFormMode = FormMode<TaskCategory>

extension FormMode where Entity == TaskCategory {
    func title(using settingsStore: AppSettingsStore) -> String {
        title(
            using: settingsStore,
            createKey: "taskCategories.form.mode.createTitle",
            createDefault: "Yeni Görev Kategorisi",
            editKey: "taskCategories.form.mode.editTitle",
            editDefault: "Görev Kategorisi Düzenle"
        )
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        saveButtonTitle(
            using: settingsStore,
            createKey: "taskCategories.form.action.save",
            createDefault: "Kaydet",
            editKey: "taskCategories.form.action.update",
            editDefault: "Güncelle"
        )
    }
}
