//
//  SettingsFormHelpers.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Settings sheet form'larında ortak label/content hizası.
//  Footer ve hata banner'ı için generic Shared/Components/ProWorkFormFooter kullanılır.
//

import SwiftUI

/// Sheet form'larında etiket + içerik tek satır.
/// Label sabit (default 140) genişlik, içerik esnek.
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

// Geriye dönük uyumluluk: eski SettingsFormFooter/SettingsFormError isimleri yeni
// generic ProWork* tiplerine yönlendirir.
typealias SettingsFormFooter = ProWorkFormFooter
typealias SettingsFormSingleFooter = ProWorkFormSingleFooter
typealias SettingsFormError = ProWorkFormError
