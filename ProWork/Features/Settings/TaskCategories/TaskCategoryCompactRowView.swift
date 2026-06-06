//  TaskCategoryRowView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct TaskCategoryCompactRowView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let category: TaskCategory
    let vatLabel: String?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ProWorkColors.fromName(category.color))
                .proWorkFrame(width: 10, height: 10)
                .proWorkFrame(width: 24)

            HStack(spacing: 8) {
                Text(category.name)
                    .proWorkTextStyle(.callout)

                if let vatLabel, !vatLabel.isEmpty {
                    Text("\(settingsStore.localized("reports.summary.vat", defaultValue: "KDV")): \(vatLabel)")
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
            .proWorkFrame(maxWidth: .infinity, alignment: .leading)

            Text(category.isBillableDefault ? settingsStore.localized("taskCategories.type.billable", defaultValue: "Faturalandırılır") : settingsStore.localized("taskCategories.type.admin", defaultValue: "İdari"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(category.isBillableDefault ? .green : .secondary)
                .proWorkFrame(width: 150, alignment: .leading)

            Text("\(category.sortOrder)")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .proWorkFrame(width: 60, alignment: .trailing)

            Text(category.isSystem ? settingsStore.localized("taskCategories.source.system", defaultValue: "Sistem") : settingsStore.localized("taskCategories.source.custom", defaultValue: "Özel"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(category.isSystem ? .secondary : .primary)
                .proWorkFrame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(settingsStore.localized("taskCategories.action.edit", defaultValue: "Düzenle"))

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(category.isSystem)
                .help(category.isSystem ? settingsStore.localized("taskCategories.action.deleteDisabled", defaultValue: "Sistem kategorileri silinemez") : settingsStore.localized("taskCategories.action.delete", defaultValue: "Sil"))
            }
            .proWorkFrame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
