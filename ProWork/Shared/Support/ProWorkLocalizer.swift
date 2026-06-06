//  ProWorkLocalizer.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import os

/// `@unchecked Sendable`: every piece of mutable state is enclosed in a
/// single `OSAllocatedUnfairLock<State>`; the lock provides the actual
/// synchronization. Because `Bundle` is not Sendable, the lock uses the
/// `uncheckedState` init + `withLockUnchecked`. Once the class is Sendable
/// its methods become nonisolated and can be safely called from
/// background contexts like PDF rendering (via ProWorkMoneyFormatter).
final class ProWorkLocalizer: @unchecked Sendable {
    static let shared = ProWorkLocalizer()

    /// Non-immutable state owned by the lock. Its contents are only
    /// mutated inside `withLockUnchecked` blocks.
    private struct State {
        var storedLanguage: AppLanguage = .turkish
        // Bundle resolution used to read paths from disk and allocate a
        // new Bundle on every `localized(...)` call; with hundreds of
        // calls per frame inside a SwiftUI body that was a real overhead.
        // Resolve once per language and store.
        var cachedBundles: [AppLanguage: [Bundle]] = [:]
        // Hot paths like enum `.title` return the same value for the same
        // (key, language); cache the resolved string by `(language, key)`.
        var resolvedStrings: [AppLanguage: [String: String]] = [:]
    }

    /// macOS 13+'s `OSAllocatedUnfairLock` has lower contention cost than
    /// `NSLock`. `uncheckedState` is used because `State` contains a
    /// non-Sendable `Bundle`; the lock itself provides the synchronization
    /// guarantee.
    private let lockedState = OSAllocatedUnfairLock(uncheckedState: State())

    private init() {}

    func update(language: AppLanguage) {
        lockedState.withLockUnchecked { state in
            state.storedLanguage = language
            state.cachedBundles.removeAll(keepingCapacity: true)
            state.resolvedStrings.removeAll(keepingCapacity: true)
        }
    }

    var language: AppLanguage {
        lockedState.withLockUnchecked { $0.storedLanguage }
    }

    func string(_ key: String, defaultValue: String) -> String {
        // Cache hit fast path: single lock acquire + dict read.
        let (currentLanguage, cached): (AppLanguage, String?) = lockedState.withLockUnchecked { state in
            (state.storedLanguage, state.resolvedStrings[state.storedLanguage]?[key])
        }
        if let cached { return cached }

        // The language is threaded through so the entire resolution
        // belongs to a single `currentLanguage` snapshot; if
        // `update(language:)` runs in between, the cache-write guard
        // prevents writing to the old language.
        let bundles = candidateBundles(for: currentLanguage)
        var resolved = defaultValue
        for bundle in bundles {
            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            if value != key {
                resolved = value
                break
            }
        }

        let resolvedSnapshot = resolved
        lockedState.withLockUnchecked { state in
            if state.storedLanguage == currentLanguage {
                // Only write to the cache if the language hasn't changed since.
                state.resolvedStrings[currentLanguage, default: [:]][key] = resolvedSnapshot
            }
        }

        return resolved
    }

    private func candidateBundles(for language: AppLanguage) -> [Bundle] {
        lockedState.withLockUnchecked { state in
            if let cached = state.cachedBundles[language] {
                return cached
            }

            let fallbacks: [AppLanguage] = {
                var languages: [AppLanguage] = [language]
                if language != .turkish {
                    languages.append(.turkish)
                }
                if language != .english {
                    languages.append(.english)
                }
                return languages
            }()

            let bundles = fallbacks.compactMap { lang -> Bundle? in
                guard let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj") else {
                    return nil
                }

                return Bundle(path: path)
            }

            let resolved = bundles.isEmpty ? [.main] : bundles
            state.cachedBundles[language] = resolved
            return resolved
        }
    }
}

// many features/repositories carry their own
// `private func localized(_:defaultValue:)` wrapper around
// `ProWorkLocalizer.shared.string(_:defaultValue:)`. The static shortcut
// below lets callers reach for `ProWorkLocalizer.localized(...)` directly
// without redeclaring the helper, paving the way to delete the per-type
// duplicates incrementally.
extension ProWorkLocalizer {
    static func localized(_ key: String, defaultValue: String) -> String {
        shared.string(key, defaultValue: defaultValue)
    }
}
