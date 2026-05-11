//
//  CustomerFormMode.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum CustomerFormMode {
    case create
    case edit(Customer)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("customers.form.mode.create", defaultValue: "Yeni Müşteri")
        case .edit:
            return settingsStore.localized("customers.form.mode.edit", defaultValue: "Müşteri Düzenle")
        }
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create:
            return settingsStore.localized("common.save", defaultValue: "Kaydet")
        case .edit:
            return settingsStore.localized("customers.form.save.update", defaultValue: "Güncelle")
        }
    }
}
