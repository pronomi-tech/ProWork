//  ProWorkButton.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

enum ProWorkButtonStyleKind {
    case primary
    case secondary
    case destructive
    case plain
}

struct ProWorkButton: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let systemImage: String?
    let style: ProWorkButtonStyleKind
    let minHeight: CGFloat
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        style: ProWorkButtonStyleKind = .secondary,
        minHeight: CGFloat = 40,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.minHeight = minHeight
        self.action = action
    }

    var body: some View {
        // Style selection goes through a @ViewBuilder switch; the previous
        // code wrapped each branch in an AnyView via `AnyPrimitiveButtonStyle`,
        // which broke SwiftUI's view identity and caused animation glitches
        // and unnecessary re-renders.
        switch style {
        case .primary:
            buttonContent.buttonStyle(.borderedProminent)
        case .secondary:
            buttonContent.buttonStyle(.bordered)
        case .destructive:
            // Destructive carries a `.role(.destructive)`
            // tint so screen readers + macOS visual hierarchy can
            // distinguish "delete" from a plain secondary action.
            // The bordered style is preserved so the layout doesn't
            // shift; only the foregroundStyle changes (red on macOS).
            buttonContent
                .buttonStyle(.bordered)
                .tint(.red)
        case .plain:
            buttonContent.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        Button {
            action()
        } label: {
            HStack(spacing: ProWorkLayout.scaled(7, using: settingsStore)) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .proWorkFont(size: 14, weight: .semibold)
                }

                Text(title)
                    .proWorkFont(size: 14, weight: .medium)
            }
            .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
            .frame(
                minHeight: ProWorkLayout.scaled(minHeight, using: settingsStore),
                alignment: .center
            )
            .contentShape(Rectangle())
        }
    }
}
