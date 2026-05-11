//
//  BillingWindowMode.swift
//  ProWork
//
//  Created by Pronomi
//

import Foundation

/// Minimum ücretlendirme penceresinin nasıl işletileceğini belirler.
enum BillingWindowMode: String, CaseIterable, Identifiable, Codable, Hashable {
    /// Aynı müşteri ve aynı pencere genişliğindeki kayıtlar ortak timeline pencerelerini paylaşır.
    case timeline
    /// Her çalışma kaydı kendi minimum ücretlendirme penceresini ayrı açar.
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
