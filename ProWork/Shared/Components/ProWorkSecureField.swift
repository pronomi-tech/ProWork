//
//  ProWorkSecureField.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProWorkSecureField: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let placeholder: String
    @Binding var text: String
    let minHeight: CGFloat
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?

    init(
        title: String = "",
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 44,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            if !title.isEmpty {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(
                    ProWorkFonts.font(
                        size: 15,
                        weight: .regular,
                        using: settingsStore
                    )
                )
                .submitLabel(submitLabel)
                .onSubmit {
                    onSubmit?()
                }
                .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(9, using: settingsStore))
                .frame(
                    minHeight: ProWorkLayout.scaled(minHeight, using: settingsStore),
                    alignment: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
                .background(.background.opacity(0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                        .stroke(.quaternary, lineWidth: 1)
                )
        }
    }
}
