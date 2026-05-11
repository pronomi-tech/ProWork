//
//  ProWorkColors.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

enum ProWorkColors {
    static func fromName(_ color: String?) -> Color {
        switch color {
        case "blue":
            return .blue
        case "orange":
            return .orange
        case "purple":
            return .purple
        case "cyan":
            return .cyan
        case "red":
            return .red
        case "green":
            return .green
        case "yellow":
            return .yellow
        case "indigo":
            return .indigo
        case "mint":
            return .mint
        case "pink":
            return .pink
        default:
            return .gray
        }
    }

    static let activeHighlight = Color.green
    static let activeHighlightFill = Color.green.opacity(0.12)
    static let activeHighlightBorder = Color.green.opacity(0.38)
    static let activeHighlightSurface = Color.mint.opacity(0.10)
    static let startAction = Color.green
    static let stopAction = Color.red
}
