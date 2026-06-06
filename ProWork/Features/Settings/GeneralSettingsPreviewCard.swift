//  GeneralSettingsPreviewCard.swift
//  ProWork
//  Created by Pronomi.
// extracted from GeneralSettingsView so the preview
//  section is independently testable / previewable. The split
//  cuts ~100 lines from the parent file and lets a designer iterate
//  on the formatter chips without scrolling past the settings rows.

import SwiftUI

struct GeneralSettingsPreviewCard: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Text(settingsStore.localized("general.section.preview", defaultValue: "Önizleme"))
                .proWorkTextStyle(.headline)

            HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                previewItem(
                    title: settingsStore.localized("general.preview.date", defaultValue: "Tarih"),
                    value: settingsStore.formatDate(Date()),
                    systemImage: "calendar"
                )
                previewItem(
                    title: settingsStore.localized("general.preview.time", defaultValue: "Saat"),
                    value: settingsStore.formatTime(Date()),
                    systemImage: "clock"
                )
                previewItem(
                    title: settingsStore.localized("general.preview.dateTime", defaultValue: "Tarih + Saat"),
                    value: settingsStore.formatDateTime(Date()),
                    systemImage: "calendar.badge.clock"
                )
            }
        }
        .padding(ProWorkLayout.scaled(18, using: settingsStore))
        .frame(maxWidth: ProWorkLayout.scaled(820, using: settingsStore), alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(16, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func previewItem(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: 18)
                .foregroundStyle(.blue)
                .frame(width: ProWorkLayout.scaled(22, using: settingsStore))

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(3, using: settingsStore)) {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .proWorkTextStyle(.headline)
                    .monospacedDigit()
            }
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(235, using: settingsStore), alignment: .leading)
        .background(.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
    }
}
