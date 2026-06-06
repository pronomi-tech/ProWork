//  SettingsScreenScaffold.swift
//  ProWork
//  Created by Pronomi.
//  Shared scaffold for all Settings screens.
//  - Sticky header (title + description + top-right toolbar area)
//  - Divider
//  - Content (inside ScrollView, standard padding)
//  - Notice/error rows below header, above content

import SwiftUI
import AppKit

/// Invisible helper that locates the `NSScrollView` underlying SwiftUI's
/// `ScrollView` and completely removes the vertical scroller.
///
/// MacOS "legacy" scroller (when a mouse is connected / "Show scroll bars:
/// Always") adds a permanent gutter to the right of the content, narrowing
/// its width; this was causing the right edges of the non-scrolling header
/// and the scrolling content to diverge. On launch, the scroller also
/// appeared large momentarily before disappearing (flash).
///
/// `hasVerticalScroller = false` removes the scroller from the start → no
/// gutter, no visible bar, no flash; the content still scrolls via
/// trackpad / wheel. The configuration is applied in
/// `viewDidMoveToWindow` — as soon as the view enters the hierarchy,
/// before the first paint — so the first-frame flash previously caused
/// by a deferred `DispatchQueue.async` is also eliminated.
private struct OverlayScrollerEnforcer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollerSuppressorProbe()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollerSuppressorProbe)?.suppressEnclosingScroller()
    }

    /// Invisible probe that removes the enclosing NSScrollView's scroller
    /// as soon as it joins the hierarchy.
    private final class ScrollerSuppressorProbe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            suppressEnclosingScroller()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            suppressEnclosingScroller()
        }

        func suppressEnclosingScroller() {
            var current: NSView? = self
            while let node = current {
                if let scrollView = node.enclosingScrollView {
                    scrollView.scrollerStyle = .overlay
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                    scrollView.autohidesScrollers = true
                    return
                }
                current = node.superview
            }
        }
    }
}

/// Caller still owns the `savedNotice` / `errorMessage`
/// state today, but the scaffold now does the heavy lifting:
/// `proWorkToastNotifications` clears the toast on its own timer, so
/// each Settings screen has stopped re-implementing the same
/// `DispatchQueue.main.asyncAfter` snapshot pattern. The architectural
/// root cause flagged in the audit (clear ownership in caller) is
/// resolved at the layer that all callers share. New views should
/// route saves through the shared `NoticeScheduler`
/// which writes into the @Published var the scaffold reads.
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
        // Header is always OUTSIDE the scroll, full width (W), button
        // pinned at W-28. Content is inside the scroll. Sole problem:
        // macOS "legacy" scrollbar (mouse connected / "Always" setting)
        // added a permanent gutter on the right, narrowing the content
        // → the button overflowed.
        //
        // SOLUTION: add an `OverlayScrollerEnforcer` background to the
        // ScrollView; this forces the underlying NSScrollView's
        // `scrollerStyle` to `.overlay`. Overlay scroller does NOT add a
        // gutter — it floats over the content. Thus the content stays
        // at full width (W) and meets the fixed-width header at the
        // same right edge (W-28). Scroll still works; the indicator
        // appears during scrolling.
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            switch contentScrollBehavior {
            case .scrolls:
                ScrollView {
                    scaffoldContent
                        // The enforcer must be INSIDE the scroll (document
                        // view) so `enclosingScrollView` can locate the
                        // underlying NSScrollView. When placed on the
                        // ScrollView's `.background`, the probe stayed
                        // outside the scroll and couldn't find the
                        // NSScrollView — that's why the earlier attempt
                        // had no effect.
                        .background(OverlayScrollerEnforcer())
                }
                .scrollIndicators(.hidden)
            case .fixed:
                scaffoldContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .proWorkToastNotifications(
            errorMessage: errorMessage,
            successMessage: savedNotice
        )
    }

    private var header: some View {
        // Subtitle is one line (`.lineLimit(1) + truncationMode(.tail)`)
        // — multi-line wrapping used to shift the header height. On the
        // width side the inner VStack fills the left area with
        // `.frame(maxWidth: .infinity)`, the toolbar sticks to its
        // right edge; since the header takes the full detail width (W),
        // the button is always at W-28.
        HStack(alignment: .top, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(title)
                    .proWorkTextStyle(.title2)
                    .bold()
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            toolbar()
        }
        .padding(.horizontal, ProWorkLayout.scaled(28, using: settingsStore))
        .padding(.top, ProWorkLayout.scaled(20, using: settingsStore))
        .padding(.bottom, ProWorkLayout.scaled(16, using: settingsStore))
    }

    private var scaffoldContent: some View {
        // Same width logic as the header: `maxWidth: .infinity` + 28
        // padding. In `.scrolls` mode the header is also inside the
        // same ScrollView (pinned), so both take the same gutter-aware
        // width → right edges always match.
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, ProWorkLayout.scaled(28, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(20, using: settingsStore))
    }
}

/// Shared helper for "card"-style framed content in Settings screens.
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

/// Shared framed container for table header + content.
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

/// Empty-state card.
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
