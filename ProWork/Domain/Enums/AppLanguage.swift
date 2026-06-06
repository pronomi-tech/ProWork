//  AppLanguage.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// The UI language enum. Adding a new case (e.g. German)
/// requires three changes at minimum:
///   1. New `Localizable.strings` bundle in `<lang>.lproj/`.
///   2. New `localeIdentifier` mapping below.
///   3. New default-template entry in
///      `PriceListQuoteTemplateSettings.defaultTemplate(for:)` and
///      `ServiceDocumentTemplateSettings.defaultTemplate(for:)` so a
///      fresh install in that language doesn't surface Turkish
///      template copy. The compiler enforces (3) once the switch
///      becomes exhaustive — keep the factories switch-exhaustive
///      on every change.
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
