//
//  AppFontSizeOption.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

enum AppFontSizeOption: String, CaseIterable, Identifiable {
    case small
    case normal
    case large
    case extraLarge

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .small:
            return ProWorkLocalizer.shared.string("fontSize.small", defaultValue: "Küçük")
        case .normal:
            return ProWorkLocalizer.shared.string("fontSize.normal", defaultValue: "Normal")
        case .large:
            return ProWorkLocalizer.shared.string("fontSize.large", defaultValue: "Büyük")
        case .extraLarge:
            return ProWorkLocalizer.shared.string("fontSize.extraLarge", defaultValue: "Çok Büyük")
        }
    }

    var scale: CGFloat {
        switch self {
        case .small:
            return 0.92
        case .normal:
            return 1.0
        case .large:
            return 1.12
        case .extraLarge:
            return 1.25
        }
    }
}
