//
//  ProWorkButtonLabel.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProWorkButtonLabel: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let systemImage: String
    let fontSize: CGFloat
    let iconSize: CGFloat
    let minHeight: CGFloat
    let horizontalPadding: CGFloat

    init(
        title: String,
        systemImage: String,
        fontSize: CGFloat = 14,
        iconSize: CGFloat = 14,
        minHeight: CGFloat = 32,
        horizontalPadding: CGFloat = 10
    ) {
        self.title = title
        self.systemImage = systemImage
        self.fontSize = fontSize
        self.iconSize = iconSize
        self.minHeight = minHeight
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        HStack(spacing: ProWorkLayout.scaled(7, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: iconSize, weight: .semibold)

            Text(title)
                .proWorkFont(size: fontSize, weight: .medium)
        }
        .padding(.horizontal, ProWorkLayout.scaled(horizontalPadding, using: settingsStore))
        .frame(
            minHeight: ProWorkLayout.scaled(minHeight, using: settingsStore),
            alignment: .center
        )
    }
}
