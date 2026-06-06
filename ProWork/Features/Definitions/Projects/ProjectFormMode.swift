//  ProjectFormMode.swift
//  ProWork
//  Created by Pronomi.

import Foundation

enum ProjectFormMode {
    case create
    case edit(ProjectListItem)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("projects.form.mode.create", defaultValue: "Yeni Proje")
        case .edit:
            return settingsStore.localized("projects.form.mode.edit", defaultValue: "Proje Düzenle")
        }
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("common.save", defaultValue: "Kaydet")
        case .edit:
            return settingsStore.localized("projects.form.save.update", defaultValue: "Güncelle")
        }
    }
}
