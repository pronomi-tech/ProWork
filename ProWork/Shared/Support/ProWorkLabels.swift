//  ProWorkLabels.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

enum ProWorkLabels {
    static func priorityTitle(_ value: String) -> String {
        switch value {
        case "low":
            return ProWorkLocalizer.shared.string("priority.low", defaultValue: "Düşük")
        case "high":
            return ProWorkLocalizer.shared.string("priority.high", defaultValue: "Yüksek")
        case "urgent":
            return ProWorkLocalizer.shared.string("priority.urgent", defaultValue: "Acil")
        default:
            return ProWorkLocalizer.shared.string("priority.normal", defaultValue: "Normal")
        }
    }

    static func priorityColor(_ value: String) -> Color {
        switch value {
        case "low":
            return .secondary
        case "high":
            return .orange
        case "urgent":
            return .red
        default:
            return .secondary
        }
    }
}
