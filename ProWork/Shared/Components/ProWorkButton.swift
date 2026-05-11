//
//  ProWorkButton.swift
//  ProWork
//
//  Created by Pronomi.
//

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
            .frame(maxWidth: style == .plain ? nil : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(buttonStyle)
    }

    private var buttonStyle: some PrimitiveButtonStyle {
        switch style {
        case .primary:
            return AnyPrimitiveButtonStyle(.borderedProminent)
        case .secondary:
            return AnyPrimitiveButtonStyle(.bordered)
        case .destructive:
            return AnyPrimitiveButtonStyle(.bordered)
        case .plain:
            return AnyPrimitiveButtonStyle(.plain)
        }
    }
}

private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let makeBody: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration)
    }
}
