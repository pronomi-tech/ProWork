//
//  SettingsScreenScaffold.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Tüm Settings ekranları için ortak iskelet.
//  - Sticky header (başlık + açıklama + sağ üst toolbar alanı)
//  - Divider
//  - Content (ScrollView içinde, padding standart)
//  - Notice/error satırları başlık altında, content üstünde
//

import SwiftUI

struct SettingsScreenScaffold<Content: View, Toolbar: View>: View {
    enum ContentScrollBehavior {
        case scrolls
        case fixed
    }

    let title: String
    let subtitle: String?
    let errorMessage: String?
    let savedNotice: String?
    let contentScrollBehavior: ContentScrollBehavior
    @ViewBuilder var toolbar: () -> Toolbar
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var settingsStore: AppSettingsStore

    init(
        title: String,
        subtitle: String? = nil,
        errorMessage: String? = nil,
        savedNotice: String? = nil,
        contentScrollBehavior: ContentScrollBehavior = .scrolls,
        @ViewBuilder toolbar: @escaping () -> Toolbar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.errorMessage = errorMessage
        self.savedNotice = savedNotice
        self.contentScrollBehavior = contentScrollBehavior
        self.toolbar = toolbar
        self.content = content
    }

    init(
        title: String,
        subtitle: String? = nil,
        errorMessage: String? = nil,
        savedNotice: String? = nil,
        contentScrollBehavior: ContentScrollBehavior = .scrolls,
        @ViewBuilder content: @escaping () -> Content
    ) where Toolbar == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.errorMessage = errorMessage
        self.savedNotice = savedNotice
        self.contentScrollBehavior = contentScrollBehavior
        self.toolbar = { EmptyView() }
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding = ProWorkLayout.scaled(28, using: settingsStore)
            let verticalPadding = ProWorkLayout.scaled(20, using: settingsStore)
            let contentWidth = max(proxy.size.width - (horizontalPadding * 2), 0)

            VStack(alignment: .leading, spacing: 0) {
                header

                Divider()

                switch contentScrollBehavior {
                case .scrolls:
                    ScrollView {
                        scaffoldContent(width: contentWidth, horizontalPadding: horizontalPadding, verticalPadding: verticalPadding)
                    }
                case .fixed:
                    scaffoldContent(width: contentWidth, horizontalPadding: horizontalPadding, verticalPadding: verticalPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)
            .proWorkToastNotifications(
                errorMessage: errorMessage,
                successMessage: savedNotice
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(title)
                    .proWorkTextStyle(.title2)
                    .bold()

                if let subtitle {
                    Text(subtitle)
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            toolbar()
        }
        .padding(.horizontal, ProWorkLayout.scaled(28, using: settingsStore))
        .padding(.top, ProWorkLayout.scaled(20, using: settingsStore))
        .padding(.bottom, ProWorkLayout.scaled(16, using: settingsStore))
    }

    private func scaffoldContent(
        width: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
            content()
        }
        .frame(width: width, alignment: .topLeading)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Settings ekranlarında "kart" tarzı çerçeveli içerik için ortak helper.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            content()
        }
        .padding(ProWorkLayout.scaled(18, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

/// Tablo başlığı + içerik için ortak çerçeveli kapsayıcı.
struct SettingsTableContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Boş durum kartı.
struct SettingsEmptyState: View {
    let systemImage: String
    let title: String
    let message: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .proWorkFont(size: 28)
                .foregroundStyle(.secondary)
            Text(title)
                .proWorkTextStyle(.headline)
            if let message {
                Text(message)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}
