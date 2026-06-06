//  ProWorkColors.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import os

/// Persisted color names are now enumerated in the `Named` enum. The old
/// `fromName(_:)` API still accepts a raw string (DB rows and test
/// fixtures continue to write strings), but the internal conversion goes
/// through the enum — there's a single source of truth for adding or
/// removing a color.
enum ProWorkColors {
    enum Named: String, CaseIterable {
        case blue, orange, purple, cyan, red, green, yellow, indigo, mint, pink

        var color: Color {
            switch self {
            case .blue: return .blue
            case .orange: return .orange
            case .purple: return .purple
            case .cyan: return .cyan
            case .red: return .red
            case .green: return .green
            case .yellow: return .yellow
            case .indigo: return .indigo
            case .mint: return .mint
            case .pink: return .pink
            }
        }
    }

    static func fromName(_ color: String?) -> Color {
        guard let color else { return .gray }
        guard let named = Named(rawValue: color) else {
            // previously an unknown color name silently
            // fell back to gray. That hides typos and stale colour
            // configurations from old DB rows; log so an unexpected value
            // surfaces in diagnostics.
            ProWorkLog.app.warning(
                "ProWorkColors.fromName: unknown color name \(color, privacy: .public); falling back to .gray"
            )
            return .gray
        }
        return named.color
    }

    static let activeHighlight = Color.green
    static let activeHighlightFill = Color.green.opacity(0.12)
    static let activeHighlightBorder = Color.green.opacity(0.38)
    static let activeHighlightSurface = Color.mint.opacity(0.10)
    static let startAction = Color.green
    static let stopAction = Color.red
}
