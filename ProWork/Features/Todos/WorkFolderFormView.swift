//  WorkFolderFormView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct WorkFolderFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var name: String
    @State private var parentFolderId: String

    let existingFolder: WorkFolder?
    let projectId: String?
    let folders: [WorkFolder]
    let onSave: (WorkFolder) -> Void

    init(
        existingFolder: WorkFolder? = nil,
        projectId: String?,
        parentFolderId: String? = nil,
        folders: [WorkFolder],
        onSave: @escaping (WorkFolder) -> Void
    ) {
        self.existingFolder = existingFolder
        self.projectId = projectId
        self.folders = folders
        self.onSave = onSave
        _name = State(initialValue: existingFolder?.name ?? "")
        _parentFolderId = State(
            initialValue: existingFolder?.parentFolderId ?? parentFolderId ?? ""
        )
    }

    private var excludedIds: Set<String> {
        guard let existingFolder else { return [] }
        return WorkFolderHierarchy.descendantIds(of: existingFolder.id, in: folders)
    }

    private var parentOptions: [WorkFolderTreeItem] {
        WorkFolderHierarchy.flattened(
            folders,
            projectId: projectId,
            excluding: excludedIds
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ProWorkFormShell(
            title: existingFolder == nil
                ? settingsStore.localized("workFolders.form.create", defaultValue: "Yeni Klasör")
                : settingsStore.localized("workFolders.form.edit", defaultValue: "Klasörü Düzenle"),
            subtitle: settingsStore.localized(
                "workFolders.form.subtitle",
                defaultValue: "Çalışmaları sınırsız alt klasörlerle düzenleyin."
            ),
            systemImage: "folder",
            width: 560,
            height: 300
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ProWorkTextField(
                    title: settingsStore.localized("workFolders.form.name", defaultValue: "Klasör Adı"),
                    placeholder: settingsStore.localized("workFolders.form.name.placeholder", defaultValue: "Örn. Teklif"),
                    text: $name
                )

                Picker(
                    settingsStore.localized("workFolders.form.parent", defaultValue: "Üst Klasör"),
                    selection: $parentFolderId
                ) {
                    Text(settingsStore.localized("workFolders.form.parent.none", defaultValue: "Ana düzey"))
                        .tag("")
                    ForEach(parentOptions) { item in
                        Text(String(repeating: "  ", count: item.depth) + item.folder.name)
                            .tag(item.id)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        } footer: {
            ProWorkFormFooter(
                onCancel: { dismiss() },
                onSave: { save() },
                saveTitle: settingsStore.localized("common.save", defaultValue: "Kaydet"),
                saveDisabled: !canSave
            )
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let now = Date()
        let folder = WorkFolder(
            id: existingFolder?.id ?? UUID().uuidString,
            projectId: projectId,
            parentFolderId: parentFolderId.isEmpty ? nil : parentFolderId,
            name: cleanName,
            sortOrder: existingFolder?.sortOrder ?? 0,
            organizationId: existingFolder?.organizationId ?? BuiltInOrganizationId.default,
            createdByUserId: existingFolder?.createdByUserId ?? AppServices.currentUserId,
            updatedByUserId: AppServices.currentUserId,
            createdAt: existingFolder?.createdAt ?? now,
            updatedAt: now,
            rowVersion: existingFolder?.rowVersion ?? 0,
            syncStatus: .local,
            lastSyncedAt: existingFolder?.lastSyncedAt,
            originDeviceId: existingFolder?.originDeviceId ?? DeviceIdentity.current
        )
        onSave(folder)
    }
}
