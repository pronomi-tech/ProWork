//  DatabaseDurabilityBanner.swift
//  ProWork
//  Created by Pronomi.
//  Persistent warning banner shown when the database fell back to
//  the MEMORY journal (sidecar files couldn't be created — usually in
//  a cloud-sync folder like OneDrive/iCloud). Informs the user there
//  is no crash-safety and provides a button to move the data file to
//  a local folder.

import SwiftUI

struct DatabaseDurabilityBanner: View {
    let message: String
    let onRelocate: () -> Void

    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .proWorkFont(size: 16, weight: .semibold)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("database.durabilityWarning.title", defaultValue: "Veri güvenliği uyarısı"))
                    .proWorkTextStyle(.callout, weight: .semibold)

                Text(message)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onRelocate()
            } label: {
                ProWorkButtonLabel(
                    title: settingsStore.localized("database.durabilityWarning.relocate", defaultValue: "Veri Dosyasını Taşı"),
                    systemImage: "externaldrive.badge.plus",
                    minHeight: 30
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, ProWorkLayout.scaled(20, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(12, using: settingsStore))
        .background(.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
