//  ProWorkGrid.swift
//  ProWork
//  Created by Pronomi.
//  Shared scaffold for the column-header + row-list pattern that was
//  previously duplicated across ~14 feature views (WorkSessions,
//  TodoTimeSessions, Customers, Projects, VAT, TaskCategories,
//  TodoStatuses, ExchangeRates, Holidays, PriceLists ×3, Reports ×3).
//  Each copy reproduced — and could regress — the same layout traps:
//    • `Color.clear.frame(width:)` placeholders being vertically
//      flexible, causing the column header to drift to the centre of
//      the card when the row list was empty.
//    • The empty state being either dropped under the header with no
//      breathing room, or vertically centred so far below it that the
//      header looked detached.
//    • Horizontal-scroll fallback for wide tables being implemented
//      inline differently in every view.
//
//  `ProWorkGrid` centralises all three concerns:
//    • Always renders the column header at the top, divider, then the
//      row list (or empty content) below.
//    • Uses an internal placeholder helper that pins `Color.clear`
//      vertically so it never steals header height.
//    • Empty state sits vertically centred between two `Spacer`s while
//      the card fills the available vertical space.
//    • Optional `minTableWidth` enables horizontal scrolling for wide
//      tables; left at `0` the grid skips the outer h-scroll entirely.

import SwiftUI

struct ProWorkGrid<Item: Identifiable, Header: View, EmptyContent: View, Row: View>: View {

    let items: [Item]
    let minTableWidth: CGFloat
    let cornerRadius: CGFloat

    @ViewBuilder let header: () -> Header
    @ViewBuilder let emptyContent: () -> EmptyContent
    @ViewBuilder let row: (Item) -> Row

    init(
        items: [Item],
        minTableWidth: CGFloat = 0,
        cornerRadius: CGFloat = 10,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.items = items
        self.minTableWidth = minTableWidth
        self.cornerRadius = cornerRadius
        self.header = header
        self.emptyContent = emptyContent
        self.row = row
    }

    var body: some View {
        if minTableWidth > 0 {
            horizontalScrollBody
        } else {
            standardBody
        }
    }

    // MARK: - Layout variants

    /// Default layout used by most settings/feature tables. No
    /// horizontal scroll; columns are expected to fit the available
    /// width via flexible columns inside the header HStack.
    private var standardBody: some View {
        VStack(spacing: 0) {
            header()

            Divider()

            if items.isEmpty {
                Spacer(minLength: 0)
                emptyContent()
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    /// Wide-table variant — wraps the entire grid body in a
    /// horizontal scroll view so the column header + rows stay
    /// aligned even when the viewport is narrower than the
    /// configured `minTableWidth`.
    private var horizontalScrollBody: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header()

                    Divider()

                    if items.isEmpty {
                        Spacer(minLength: 0)
                        emptyContent()
                        Spacer(minLength: 0)
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { item in
                                    row(item)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(
                    width: max(geometry.size.width, minTableWidth),
                    alignment: .leading
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.quaternary, lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Header placeholder helper

extension Color {
    /// Use in place of `Color.clear.frame(width:)` inside a grid
    /// header HStack. The plain `Color.clear` is vertically infinite-
    /// flex, which lets it absorb the grid's residual height and drift
    /// the header text to the middle of the empty card. This helper
    /// pins the cell height to a single point so the HStack collapses
    /// back to its intrinsic text height while the column's horizontal
    /// width slot is preserved.
    static func gridHeaderSpacer(width: CGFloat) -> some View {
        Color.clear.frame(width: width, height: 1)
    }
}

// MARK: - Standard empty state body

/// Convenience wrapper for the common "icon + headline + caption"
/// empty-state body used by ~9 views. Pass it as the `emptyContent`
/// closure when the view doesn't need a custom layout.
struct ProWorkGridEmptyState: View {
    let systemImage: String
    let title: String
    let message: String?

    init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 36)
    }
}
