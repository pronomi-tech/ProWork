//  ProWorkLabeledFormRow.swift
//  ProWork
//  Created by Pronomi.
//  Shared "label + control" row used across every settings/definition form
//. Six different forms previously each duplicated a
//  private `formRow(label:content:)` helper plus hardcoded `width: 160/320/340`
//  magic numbers. Use this component instead so font-scaling, alignment, and
//  width tuning live in one place.

import SwiftUI

struct ProWorkLabeledFormRow<Content: View>: View {
    let label: String
    var verticalAlignment: VerticalAlignment = .center
    var labelWidth: CGFloat = 150
    var contentWidth: CGFloat = 340
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        HStack(alignment: verticalAlignment, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.callout, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(
                    width: ProWorkLayout.formScaled(labelWidth, using: settingsStore),
                    alignment: .leading
                )

            HStack {
                content()
                Spacer(minLength: 0)
            }
            .frame(
                width: ProWorkLayout.formScaled(contentWidth, using: settingsStore),
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
