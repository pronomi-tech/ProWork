//
//  AppLanguage.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .turkish:
            return ProWorkLocalizer.shared.string("app.language.turkish", defaultValue: "Türkçe")
        case .english:
            return ProWorkLocalizer.shared.string("app.language.english", defaultValue: "English")
        }
    }

    var localeIdentifier: String {
        switch self {
        case .turkish:
            return "tr_TR"
        case .english:
            return "en_US"
        }
    }
}
