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
    /// All time-based records in the same service statement share one minimum window total.
    case report

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline:
            return ProWorkLocalizer.shared.string("billingWindow.timeline.title", defaultValue: "Zaman Akışı Bazlı")
        case .session:
            return ProWorkLocalizer.shared.string("billingWindow.session.title", defaultValue: "Kayıt Bazlı")
        case .report:
            return ProWorkLocalizer.shared.string("billingWindow.report.title", defaultValue: "Döküm Bazlı")
        }
    }

    var subtitle: String {
        switch self {
        case .timeline:
            return ProWorkLocalizer.shared.string("billingWindow.timeline.subtitle", defaultValue: "Kayıtlar, çalışmaların kapladığı açık zaman pencerelerinde zincirlenir.")
        case .session:
            return ProWorkLocalizer.shared.string("billingWindow.session.subtitle", defaultValue: "Her kayıt minimum pencereyi bağımsız olarak açar.")
        case .report:
            return ProWorkLocalizer.shared.string("billingWindow.report.subtitle", defaultValue: "Dökümdeki süreler birlikte değerlendirilir; yuvarlama farkı son kayda eklenir.")
        }
    }
}
