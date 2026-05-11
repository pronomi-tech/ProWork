//
//  ServiceType.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Hizmet tipi: uzaktan ya da yerinde verilen hizmet.
enum ServiceType: String, CaseIterable, Identifiable, Hashable {
    case remote
    case onsite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: return ProWorkLocalizer.shared.string("serviceType.remote", defaultValue: "Uzaktan")
        case .onsite: return ProWorkLocalizer.shared.string("serviceType.onsite", defaultValue: "Yerinde")
        }
    }

    var systemImage: String {
        switch self {
        case .remote: return "wifi"
        case .onsite: return "location.fill"
        }
    }

    /// UI'da sıralama önceliği (küçük = önce). Yerinden önce, uzaktan sonra.
    var sortOrder: Int {
        switch self {
        case .onsite: return 10
        case .remote: return 20
        }
    }

    static let `default`: ServiceType = .remote
}
