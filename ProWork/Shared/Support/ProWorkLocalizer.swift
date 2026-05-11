//
//  ProWorkLocalizer.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

final class ProWorkLocalizer {
    static let shared = ProWorkLocalizer()

    private let lock = NSLock()
    private var storedLanguage: AppLanguage = .turkish

    private init() {}

    func update(language: AppLanguage) {
        lock.lock()
        storedLanguage = language
        lock.unlock()
    }

    var language: AppLanguage {
        lock.lock()
        let language = storedLanguage
        lock.unlock()
        return language
    }

    func string(_ key: String, defaultValue: String) -> String {
        for bundle in candidateBundles {
            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            if value != key {
                return value
            }
        }

        return defaultValue
    }

    private var candidateBundles: [Bundle] {
        lock.lock()
        let currentLanguage = storedLanguage
        lock.unlock()

        let fallbacks: [AppLanguage] = {
            var languages: [AppLanguage] = [currentLanguage]
            if currentLanguage != .turkish {
                languages.append(.turkish)
            }
            if currentLanguage != .english {
                languages.append(.english)
            }
            return languages
        }()

        let bundles = fallbacks.compactMap { language -> Bundle? in
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
                return nil
            }

            return Bundle(path: path)
        }

        return bundles.isEmpty ? [.main] : bundles
    }
}
