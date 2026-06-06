//  FormMode.swift
//  ProWork
//  Created by Pronomi.
//  Generic create-or-edit enum that replaces the per-feature `*FormMode`
//  copies. Each feature previously rewrote the same
//  `case create / case edit(Entity)` enum with a per-key title and save
//  button label; the generic version takes the localisation keys as
//  parameters so the localisation strings remain feature-specific while
//  the structural code lives once.

import Foundation

/// `create` or `edit(Entity)` discriminator for any feature form.
enum FormMode<Entity> {
    case create
    case edit(Entity)

    /// The associated `Entity` if this is an edit, otherwise `nil`. Mirrors
    /// the convenience accessor every per-feature enum used to ship.
    var editingEntity: Entity? {
        if case .edit(let entity) = self { return entity }
        return nil
    }

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }

    /// Resolve the form title for the current mode. Pass two localisation
    /// keys (with defaults) — one for create, one for edit. Callers can
    /// keep their existing keys, this just lifts the if/else.
    func title(
        using settingsStore: AppSettingsStore,
        createKey: String,
        createDefault: String,
        editKey: String,
        editDefault: String
    ) -> String {
        switch self {
        case .create:
            return settingsStore.localized(createKey, defaultValue: createDefault)
        case .edit:
            return settingsStore.localized(editKey, defaultValue: editDefault)
        }
    }

    /// Resolve the save-button label using the same two-key convention.
    func saveButtonTitle(
        using settingsStore: AppSettingsStore,
        createKey: String,
        createDefault: String,
        editKey: String,
        editDefault: String
    ) -> String {
        switch self {
        case .create:
            return settingsStore.localized(createKey, defaultValue: createDefault)
        case .edit:
            return settingsStore.localized(editKey, defaultValue: editDefault)
        }
    }
}
