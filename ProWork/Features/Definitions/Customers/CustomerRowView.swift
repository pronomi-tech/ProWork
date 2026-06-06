//  CustomerRowView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct CustomerRowView: View {
    let customer: Customer
    let effectiveCurrency: String
    let vatLabel: String?
    let onEdit: () -> Void
    let onPricing: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge

            customerInfo

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
        Circle()
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "person.2.fill")
                    .proWorkFont(size: 15)
                    .foregroundStyle(Color.accentColor)
            )
    }

    private var customerInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(customer.name)
                    .proWorkTextStyle(.headline)

                if let code = customer.code, !code.isEmpty {
                    Text(code)
                        .proWorkTextStyle(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Text(customer.isActive ? settingsStore.localized("customers.status.active", defaultValue: "Aktif") : settingsStore.localized("customers.status.inactive", defaultValue: "Pasif"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(customer.isActive ? .green : .secondary)
            }

            Text(String(format: settingsStore.localized("customers.row.summary", defaultValue: "Fiyat listesi para birimi: %@ • Min. pencere: %@ • Hizmet: %@"), effectiveCurrency, billingWindowTitle(customer.defaultMinBillingMinutes), serviceTypeTitle(customer.defaultServiceType)))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            if let vatLabel, !vatLabel.isEmpty {
                Text("\(settingsStore.localized("reports.summary.vat", defaultValue: "KDV")): \(vatLabel)")
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            if let notes = customer.notes, !notes.isEmpty {
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
            .help(settingsStore.localized("customers.action.pricing", defaultValue: "Fiyatlandırma"))

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
            .help(settingsStore.localized("customers.delete.confirm", defaultValue: "Sil"))
        }
    }

    private func actionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .proWorkFont(size: 13)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func serviceTypeTitle(_ value: String) -> String {
        ServiceType(rawValue: value)?.title ?? ServiceType.default.title
    }

    private func billingWindowTitle(_ value: Int) -> String {
        String(format: settingsStore.localized("customers.form.minutes", defaultValue: "%d dk"), value)
    }
}
