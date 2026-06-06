//  BillingWindowMode.swift
//  ProWork
//  Created by Pronomi

import Foundation

/// Controls how the minimum billing window is applied.
enum BillingWindowMode: String, CaseIterable, Identifiable, Codable, Hashable {
    /// Records for the same customer that share a window width share common timeline windows.
    case timeline
    /// Each work record opens its own minimum billing window independently.
    case session

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline:
            return ProWorkLocalizer.shared.string("billingWindow.timeline.title", defaultValue: "Zaman Akışı Bazlı")
        case .session:
            return ProWorkLocalizer.shared.string("billingWindow.session.title", defaultValue: "Kayıt Bazlı")
        }
    }

    var subtitle: String {
        switch self {
        case .timeline:
            return ProWorkLocalizer.shared.string("billingWindow.timeline.subtitle", defaultValue: "Aynı açık pencere içine düşen kayıtlar ortak ücretlendirilir.")
        case .session:
            return ProWorkLocalizer.shared.string("billingWindow.session.subtitle", defaultValue: "Her kayıt minimum pencereyi bağımsız olarak açar.")
        }
    }
}
