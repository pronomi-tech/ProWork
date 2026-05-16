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
    // Bundle çözümlemesi her `localized(...)` çağrısında diskten path arıyor
    // ve yeni Bundle instance'ı yaratıyordu; SwiftUI body içinde frame başına
    // yüzlerce çağrı olur, ciddi bir overhead. Dil başına bir kez resolve edip
    // saklıyoruz; `update(language:)` cache'i geçersiz kılar.
    private var cachedBundles: [AppLanguage: [Bundle]] = [:]

    private init() {}

    func update(language: AppLanguage) {
        lock.lock()
        storedLanguage = language
        cachedBundles.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    var language: AppLanguage {
        lock.lock()
        let language = storedLanguage
        lock.unlock()
        return language
    }

    func string(_ key: String, defaultValue: String) -> String {
        for bundle in candidateBundles() {
            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            if value != key {
                return value
            }
        }

        return defaultValue
    }

    private func candidateBundles() -> [Bundle] {
        lock.lock()
        defer { lock.unlock() }

        let currentLanguage = storedLanguage
        if let cached = cachedBundles[currentLanguage] {
            return cached
        }

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

        let resolved = bundles.isEmpty ? [.main] : bundles
        cachedBundles[currentLanguage] = resolved
        return resolved
    }
}
