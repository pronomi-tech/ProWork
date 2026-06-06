//  TodoStatusCompactRowView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct TodoStatusCompactRowView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let status: TodoStatus
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ProWorkColors.fromName(status.color))
                .proWorkFrame(width: 10, height: 10)
                .proWorkFrame(width: 24)

            Text(status.name)
                .proWorkTextStyle(.callout)
                .proWorkFrame(maxWidth: .infinity, alignment: .leading)

            Text(status.sortOrder.description)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .proWorkFrame(width: 50, alignment: .trailing)

            behaviorBadges
                .proWorkFrame(width: 340, alignment: .leading)

            Text(status.isSystem ? settingsStore.localized("todoStatuses.source.system", defaultValue: "Sistem") : settingsStore.localized("todoStatuses.source.custom", defaultValue: "Özel"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(status.isSystem ? .secondary : .primary)
                .proWorkFrame(width: 70, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(settingsStore.localized("todoStatuses.action.edit", defaultValue: "Düzenle"))

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(status.isSystem)
                .help(status.isSystem ? settingsStore.localized("todoStatuses.action.deleteDisabled", defaultValue: "Sistem statüleri silinemez") : settingsStore.localized("todoStatuses.action.delete", defaultValue: "Sil"))
            }
            .proWorkFrame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var behaviorBadges: some View {
        HStack(spacing: 6) {
            if status.showInBoard {
                badge(settingsStore.localized("todoStatuses.badge.board", defaultValue: "Pano"))
            }

            if status.marksOpen {
                badge(settingsStore.localized("todoStatuses.badge.open", defaultValue: "Açık"))
            }

            if status.startsTimer {
                badge(settingsStore.localized("todoStatuses.badge.startsTimer", defaultValue: "Başlatır"))
            }

            if status.stopsTimer {
                badge(settingsStore.localized("todoStatuses.badge.stopsTimer", defaultValue: "Durdurur"))
            }

            if status.marksCompleted {
                badge(settingsStore.localized("todoStatuses.badge.completes", defaultValue: "Tamamlar"))
            }

            if status.marksCancelled {
                badge(settingsStore.localized("todoStatuses.badge.cancelled", defaultValue: "İptal"))
            }

            if !status.isActive {
                badge(settingsStore.localized("todoStatuses.badge.inactive", defaultValue: "Pasif"))
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .proWorkTextStyle(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
