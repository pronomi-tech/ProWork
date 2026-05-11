
//
//  ProjectRowView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProjectRowView: View {
    let project: ProjectListItem
    let vatLabel: String?
    let onEdit: () -> Void
    let onPricing: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge

            projectInfo

            Spacer()

            actionButtons
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.blue.opacity(0.12))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "folder.fill")
                    .proWorkFont(size: 15)
                    .foregroundStyle(.blue)
            )
    }

    private var projectInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.name)
                    .proWorkTextStyle(.headline)

                if let code = project.code, !code.isEmpty {
                    Text(code)
                        .proWorkTextStyle(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Text(statusTitle(project.status))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(statusColor(project.status))
            }

            Text(String(format: settingsStore.localized("projects.row.customer", defaultValue: "Müşteri: %@"), project.customerName))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            Text(String(format: settingsStore.localized("projects.row.summary", defaultValue: "Hizmet: %@ • Min. pencere: %@ • Akış: %@"), serviceTypeTitle(project.defaultServiceType), billingWindowTitle(project.defaultMinBillingMinutes), billingWindowModeTitle(project.billingWindowMode)))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            if let vatLabel, !vatLabel.isEmpty {
                Text("\(settingsStore.localized("reports.summary.vat", defaultValue: "KDV")): \(vatLabel)")
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            if let notes = project.notes, !notes.isEmpty {
                Text(notes)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                onPricing()
            } label: {
                actionIcon("list.bullet.rectangle.portrait")
            }
            .buttonStyle(.borderless)
            .help(settingsStore.localized("projects.action.pricing", defaultValue: "Fiyat Override"))

            Button {
                onEdit()
            } label: {
                actionIcon("pencil")
            }
            .buttonStyle(.borderless)
            .help(settingsStore.localized("customers.action.edit", defaultValue: "Düzenle"))

            Button(role: .destructive) {
                onDelete()
            } label: {
                actionIcon("trash")
            }
            .buttonStyle(.borderless)
            .help(settingsStore.localized("projects.delete.confirm", defaultValue: "Sil"))
        }
    }

    private func actionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .proWorkFont(size: 13)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func serviceTypeTitle(_ value: String?) -> String {
        guard let value, let serviceType = ServiceType(rawValue: value) else {
            return settingsStore.localized("projects.row.inheritCustomer", defaultValue: "Müşteriden")
        }
        return serviceType.title
    }

    private func billingWindowTitle(_ value: Int?) -> String {
        guard let value else {
            return settingsStore.localized("projects.row.inheritCustomer", defaultValue: "Müşteriden")
        }

        return String(format: settingsStore.localized("projects.form.minutes", defaultValue: "%d dk"), value)
    }

    private func billingWindowModeTitle(_ value: BillingWindowMode?) -> String {
        value?.title ?? settingsStore.localized("projects.row.inheritOrganization", defaultValue: "Organizasyondan")
    }

    private func statusTitle(_ value: String) -> String {
        switch value {
        case "passive":
            return settingsStore.localized("projects.status.passive", defaultValue: "Pasif")
        case "completed":
            return settingsStore.localized("projects.status.completed", defaultValue: "Tamamlandı")
        case "suspended":
            return settingsStore.localized("projects.status.suspended", defaultValue: "Askıda")
        default:
            return settingsStore.localized("projects.status.active", defaultValue: "Aktif")
        }
    }

    private func statusColor(_ value: String) -> Color {
        switch value {
        case "passive":
            return .secondary
        case "completed":
            return .blue
        case "suspended":
            return .orange
        default:
            return .green
        }
    }
}
