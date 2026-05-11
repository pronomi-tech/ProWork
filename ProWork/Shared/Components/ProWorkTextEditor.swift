//
//  ProWorkTextEditor.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProWorkTextEditor: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat

    init(
        title: String = "",
        placeholder: String = "",
        text: Binding<String>,
        minHeight: CGFloat = 90
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            if !title.isEmpty {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(
                        ProWorkFonts.font(
                            size: 15,
                            weight: .regular,
                            using: settingsStore
                        )
                    )
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, ProWorkLayout.scaled(8, using: settingsStore))
                    .padding(.vertical, ProWorkLayout.scaled(7, using: settingsStore))

                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, ProWorkLayout.scaled(13, using: settingsStore))
                        .padding(.vertical, ProWorkLayout.scaled(13, using: settingsStore))
                        .allowsHitTesting(false)
                }
            }
            .frame(
                minHeight: ProWorkLayout.scaled(minHeight, using: settingsStore),
                alignment: .topLeading
            )
            .background(.background.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
            .overlay(
                RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
    }
}
