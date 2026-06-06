//  DatabaseFilePickerSheet.swift
//  ProWork
//  Created by Pronomi.
//  List sheet shown during the open flow when the selected folder
//  contains more than one `.sqlite` file, letting the user choose
//  which one to open.

import SwiftUI

struct DatabaseFilePickerSheet: View {
    let selection: DatabaseSessionController.PendingDatabaseSelection
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(settingsStore.localized("database.picker.title", defaultValue: "Veri Dosyası Seç"))
                    .proWorkTextStyle(.title3)
                    .bold()

                Text(String(
                    format: settingsStore.localized("database.picker.subtitle", defaultValue: "%@ klasöründe birden fazla veri dosyası var. Açmak istediğinizi seçin."),
                    selection.folder.lastPathComponent
                ))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(selection.files, id: \.self) { file in
                        Button {
                            onPick(file)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "cylinder.split.1x2")
                                    .foregroundStyle(.secondary)
                                Text(file.lastPathComponent)
                                    .proWorkTextStyle(.callout)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .proWorkFont(size: 11)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)

            HStack {
                Spacer()
                Button(settingsStore.localized("common.cancel", defaultValue: "Vazgeç")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
