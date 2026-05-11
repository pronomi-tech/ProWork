//
//  ProWorkFormShell.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProWorkFormShell<Content: View, Footer: View, HeaderTrailing: View>: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let subtitle: String?
    let systemImage: String
    let width: CGFloat
    let height: CGFloat
    let headerTrailing: HeaderTrailing
    let content: Content
    let footer: Footer

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "doc.text",
        width: CGFloat = 680,
        height: CGFloat = 700,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.width = width
        self.height = height
        self.headerTrailing = headerTrailing()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            ProWorkFormHeader(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage
            ) {
                headerTrailing
            }

            ScrollView {
                VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ProWorkLayout.formScaled(2, using: settingsStore))
            }

            Divider()

            footer
        }
        .padding(ProWorkLayout.formScaled(24, using: settingsStore))
        .frame(
            width: ProWorkLayout.formScaled(width, using: settingsStore),
            height: ProWorkLayout.formScaled(height, using: settingsStore)
        )
    }
}

extension ProWorkFormShell where HeaderTrailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "doc.text",
        width: CGFloat = 680,
        height: CGFloat = 700,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.width = width
        self.height = height
        self.headerTrailing = EmptyView()
        self.content = content()
        self.footer = footer()
    }
}
