//  ProWorkFormShell.swift
//  ProWork
//  Created by Pronomi.

import AppKit
import SwiftUI

struct ProWorkFormShell<Content: View, Footer: View, HeaderTrailing: View>: View {
    /// How the form content fills the available space. `.scrolls`
    /// (default) is correct for most forms — vertical scroll activates
    /// as fields grow. Forms containing a grid (`PriceListRowsEditView`)
    /// use `.fixed`; ProWorkGrid manages its own internal ScrollView
    /// and an outer wrapping ScrollView was overriding the grid's
    /// `maxHeight: .infinity` frame and pinning the table header to
    /// the surface.
    enum ContentScrollBehavior {
        case scrolls
        case fixed
        /// Sizes the sheet to its intrinsic content up to `height`, then
        /// falls back to scrolling when the content would exceed the active
        /// screen's visible frame.
        case fitsContent
    }

    @EnvironmentObject private var settingsStore: AppSettingsStore
    let title: String
    let subtitle: String?
    let systemImage: String
    let width: CGFloat
    let height: CGFloat
    let contentScrollBehavior: ContentScrollBehavior
    let headerTrailing: HeaderTrailing
    let content: Content
    let footer: Footer

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "doc.text",
        width: CGFloat = 680,
        height: CGFloat = 700,
        contentScrollBehavior: ContentScrollBehavior = .scrolls,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.width = width
        self.height = height
        self.contentScrollBehavior = contentScrollBehavior
        self.headerTrailing = headerTrailing()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        Group {
            switch contentScrollBehavior {
            case .fitsContent:
                shellBody
                    .frame(width: scaledWidth)
                    .frame(maxHeight: maximumFittedHeight)
            case .scrolls, .fixed:
                shellBody
                    .frame(width: scaledWidth, height: scaledHeight)
            }
        }
    }

    private var shellBody: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            ProWorkFormHeader(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage
            ) {
                headerTrailing
            }

            switch contentScrollBehavior {
            case .scrolls:
                ScrollView {
                    VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ProWorkLayout.formScaled(2, using: settingsStore))
                }
            case .fixed:
                VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .fitsContent:
                ViewThatFits(in: .vertical) {
                    contentContainer
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        contentContainer
                    }
                }
            }

            Divider()

            footer
        }
        .padding(ProWorkLayout.formScaled(24, using: settingsStore))
    }

    private var contentContainer: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, ProWorkLayout.formScaled(2, using: settingsStore))
    }

    private var scaledWidth: CGFloat {
        ProWorkLayout.formScaled(width, using: settingsStore)
    }

    private var scaledHeight: CGFloat {
        ProWorkLayout.formScaled(height, using: settingsStore)
    }

    private var maximumFittedHeight: CGFloat {
        guard let screenHeight = NSScreen.main?.visibleFrame.height else {
            return scaledHeight
        }

        let screenMargin = ProWorkLayout.formScaled(64, using: settingsStore)
        return min(scaledHeight, max(0, screenHeight - screenMargin))
    }
}

extension ProWorkFormShell where HeaderTrailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "doc.text",
        width: CGFloat = 680,
        height: CGFloat = 700,
        contentScrollBehavior: ContentScrollBehavior = .scrolls,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.width = width
        self.height = height
        self.contentScrollBehavior = contentScrollBehavior
        self.headerTrailing = EmptyView()
        self.content = content()
        self.footer = footer()
    }
}
