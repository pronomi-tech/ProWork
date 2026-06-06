//  DataBackupSettingsView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct DataBackupSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var sessionController: DatabaseSessionController

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("dataBackup.title", defaultValue: "Veri ve Yedekleme"),
            subtitle: settingsStore.localized("dataBackup.subtitle", defaultValue: "Aktif veri dosyasını görüntüleyin veya farklı bir veri dosyasına geçin."),
            savedNotice: sessionController.settingsMessage
        ) {
            SettingsCard {
                Text(settingsStore.localized("dataBackup.activeFile", defaultValue: "Aktif Veri Dosyası"))
                    .proWorkTextStyle(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text(activeDatabaseName)
                        .proWorkTextStyle(.callout, weight: .semibold)

                    Text(activeDatabasePath)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button {
                        sessionController.revealActiveDatabaseInFinder()
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("dataBackup.reveal", defaultValue: "Finder'da Göster"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        sessionController.promptToOpenExistingDatabase()
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("dataBackup.switch", defaultValue: "Farklı Dosyaya Geç"), systemImage: "arrow.trianglehead.2.clockwise")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        sessionController.promptToCreateDatabase()
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("dataBackup.newFile", defaultValue: "Yeni Veri Dosyası"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                Text(settingsStore.localized("dataBackup.restartNote", defaultValue: "Veri dosyası değiştirildiğinde uygulama yeni dosyayla temiz biçimde yeniden başlatılır."))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeDatabaseName: String {
        sessionController.activeDatabaseURL?.lastPathComponent ?? settingsStore.localized("dataBackup.noFileSelected", defaultValue: "Veri dosyası seçilmedi")
    }

    private var activeDatabasePath: String {
        sessionController.activeDatabaseURL?.path ?? settingsStore.localized("dataBackup.noActivePath", defaultValue: "Aktif veri dosyası bulunmuyor.")
    }
}
