//
//  TodoRowView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct TodoRowView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    
    let todo: TodoListItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            todoInfo

            Spacer()

            actionButtons
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var todoInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ProWorkColors.fromName(todo.categoryColor))
                    .proWorkFrame(width: 10, height: 10)

                Text(todo.title)
                    .proWorkTextStyle(.headline)

                Text(todo.statusName)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(ProWorkColors.fromName(todo.statusColor))

                Text(ProWorkLabels.priorityTitle(todo.priority))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(ProWorkLabels.priorityColor(todo.priority))

                if todo.isBillable {
                    Text(settingsStore.localized("todos.billable", defaultValue: "Faturalandırılır"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(settingsStore.localized("todos.administrative", defaultValue: "İdari"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(subtitle)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            if let description = todo.description, !description.isEmpty {
                Text(description)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []

        if let customerName = todo.customerName, !customerName.isEmpty {
            parts.append(String(format: settingsStore.localized("todos.subtitle.customer", defaultValue: "Müşteri: %@"), customerName))
        } else {
            parts.append(settingsStore.localized("todos.administrative", defaultValue: "İdari"))
        }

        if let projectName = todo.projectName, !projectName.isEmpty {
            parts.append(String(format: settingsStore.localized("todos.subtitle.project", defaultValue: "Proje: %@"), projectName))
        }

        parts.append(String(format: settingsStore.localized("todos.subtitle.category", defaultValue: "Kategori: %@"), todo.categoryName))

        if let dueDate = todo.dueDate {
            parts.append(String(format: settingsStore.localized("todos.subtitle.dueDate", defaultValue: "Termin: %@"), settingsStore.makeDateFormatter().string(from: dueDate)))
        }

        if let estimatedMinutes = todo.estimatedMinutes {
            parts.append(String(format: settingsStore.localized("todos.subtitle.estimate", defaultValue: "Tahmin: %d dk"), estimatedMinutes))
        }

        return parts.joined(separator: " • ")
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(settingsStore.localized("customers.action.edit", defaultValue: "Düzenle"))

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(settingsStore.localized("todos.delete.confirm", defaultValue: "Sil"))
        }
    }
}

extension DateFormatter {
    static let proWorkDisplayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let proWorkDisplayDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
