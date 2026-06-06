//  ServiceType.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Service type: remote or on-site.
/// Raw value is persisted as TEXT in the DB; written
/// explicitly so a case rename can't break the contract.
enum ServiceType: String, CaseIterable, Identifiable, Hashable {
    case remote = "remote"
    case onsite = "onsite"

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

    /// Sort priority in the UI (smaller = first). On-site first, then remote.
    var sortOrder: Int {
        switch self {
        case .onsite: return 10
        case .remote: return 20
        }
    }

    static let `default`: ServiceType = .remote
}
