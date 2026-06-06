//  CustomerFormMode.swift
//  ProWork
//  Type-alias over the generic `FormMode<Entity>`.

import Foundation

typealias CustomerFormMode = FormMode<Customer>

extension FormMode where Entity == Customer {
    func title(using settingsStore: AppSettingsStore) -> String {
        title(
            using: settingsStore,
            createKey: "customers.form.mode.create",
            createDefault: "Yeni Müşteri",
            editKey: "customers.form.mode.edit",
            editDefault: "Müşteri Düzenle"
        )
    }

    func saveButtonTitle(using settingsStore: AppSettingsStore) -> String {
        saveButtonTitle(
            using: settingsStore,
            createKey: "common.save",
            createDefault: "Kaydet",
            editKey: "customers.form.save.update",
            editDefault: "Güncelle"
        )
    }
}
