//  SettingsFormHelpers.swift
//  ProWork
//  Created by Pronomi.
//  Shared label/content alignment used by Settings sheet forms.
//  The footer and error banner come from the generic
//  Shared/Components/ProWorkFormFooter.

import SwiftUI

/// One-line label + content pair used in sheet forms.
/// Label has a fixed width (default 140); the content is flexible.
struct SettingsFormRow<Content: View>: View {
    let label: String
    let alignment: VerticalAlignment
    let isRequired: Bool
    let labelWidth: CGFloat
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var settingsStore: AppSettingsStore

    init(
        _ label: String,
        alignment: VerticalAlignment = .center,
        required: Bool = false,
        labelWidth: CGFloat = 140,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.alignment = alignment
        self.isRequired = required
        self.labelWidth = labelWidth
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            HStack(spacing: 2) {
                Text(label)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }
            .frame(width: ProWorkLayout.formScaled(labelWidth, using: settingsStore), alignment: .leading)

            HStack(spacing: 0) {
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Backward compatibility: the old SettingsFormFooter/SettingsFormError
// names route to the new generic ProWork* types.
typealias SettingsFormFooter = ProWorkFormFooter
typealias SettingsFormSingleFooter = ProWorkFormSingleFooter
typealias SettingsFormError = ProWorkFormError
