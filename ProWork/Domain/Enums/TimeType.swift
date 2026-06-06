//  TimeType.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Time type: indicates which working-hours bracket the work duration falls into for billing.
/// Per spec §2 and §5, a session can be split across multiple time types.
// Raw value is persisted as TEXT in the DB; written
// explicitly to guard against renames.
enum TimeType: String, CaseIterable, Identifiable, Hashable {
    case regular = "regular"        // regular hours
    case afterHours = "afterHours"  // after hours
    case weekend = "weekend"        // weekend
    case holiday = "holiday"        // public holiday

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

    /// Fallback priority during price resolution:
    /// Holiday → Weekend → After-hours → Regular.
    /// Types are searched from specific to general; if no match, falls back to the next lower type.
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
