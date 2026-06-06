//  ProWorkSecureField.swift
//  ProWork
//  Created by Pronomi.

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
                .proWorkFieldContainer(minHeight: minHeight, verticalPadding: 9)
        }
    }
}
