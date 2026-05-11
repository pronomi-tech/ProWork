//
//  TimeType.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Zaman tipi: ücretlendirme için çalışma süresinin hangi mesai dilimine düştüğünü belirtir.
/// Spec §2 ve §5'e göre bir oturum birden fazla zaman tipine bölünebilir.
enum TimeType: String, CaseIterable, Identifiable, Hashable {
    case regular     // mesai içi
    case afterHours  // mesai dışı
    case weekend     // hafta sonu
    case holiday     // resmi tatil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return ProWorkLocalizer.shared.string("timeType.regular", defaultValue: "Mesai İçi")
        case .afterHours: return ProWorkLocalizer.shared.string("timeType.afterHours", defaultValue: "Mesai Dışı")
        case .weekend: return ProWorkLocalizer.shared.string("timeType.weekend", defaultValue: "Hafta Sonu")
        case .holiday: return ProWorkLocalizer.shared.string("timeType.holiday", defaultValue: "Resmi Tatil")
        }
    }

    var sortOrder: Int {
        switch self {
        case .regular: return 10
        case .afterHours: return 20
        case .weekend: return 30
        case .holiday: return 40
        }
    }

    /// Fiyat çözümlemesinde fallback önceliği:
    /// Tatil → Hafta sonu → Mesai dışı → Mesai içi.
    /// Üstte tanımlanan tipler özelden genele doğru aranır; bulunmazsa bir alt tipe düşer.
    var fallbackOrder: [TimeType] {
        switch self {
        case .holiday:
            return [.holiday, .weekend, .afterHours, .regular]
        case .weekend:
            return [.weekend, .afterHours, .regular]
        case .afterHours:
            return [.afterHours, .regular]
        case .regular:
            return [.regular]
        }
    }

    static let `default`: TimeType = .regular
}
