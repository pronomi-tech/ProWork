//  ProWorkFormatters.swift
//  ProWork
//  Created by Pronomi.

import Foundation

enum ProWorkFormatters {
    /// Centralised assertion for duration helpers.
    private static func assertionFailureIfNegative(_ seconds: Int) {
        assert(seconds >= 0, "Duration formatter received negative seconds: \(seconds)")
    }

    /// silently clamping a negative duration to zero
    /// masked logic bugs that fed in deltas with reversed start/end
    /// ordering. Trip an assertion in debug builds so the caller notices;
    /// release builds still display "00:00" gracefully.
    static func durationHHmm(_ seconds: Int) -> String {
        assertionFailureIfNegative(seconds)
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        return String(format: "%02d:%02d", hours, minutes)
    }

    static func durationHM(_ seconds: Int) -> String {
        assertionFailureIfNegative(seconds)
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)s \(minutes)dk"
        }

        return "\(minutes)dk"
    }

    // MARK: - Cached DateFormatter pool
    // `DateFormatter` compiles its ICU pattern lazily on first use; each new
    // instance costs 0.5–2 ms. Views that tick once per second (HomeView,
    // TodoRowView, BillingRunsView headers) were re-allocating formatters
    // per `body` evaluation, which showed up as a measurable redraw cost
    //. The cache is keyed by (locale identifier, pattern
    // descriptor) so different views can share the same warm formatter.
    // Thread-safety: SwiftUI bodies run on the main actor; we still use a
    // lock so off-main callers (e.g. PDF rendering background tasks) are
    // safe.

    /// `nonisolated`: the outer namespace is MainActor-isolated so
    /// inner structs were inheriting that isolation. The `cache` and
    /// `numberCache` dictionary'leri `nonisolated(unsafe)` ile lock'lu
    /// are also read from off-main threads, so the Hashable
    /// conformance must be usable from a nonisolated context.
    nonisolated private struct CacheKey: Hashable {
        let localeIdentifier: String
        let descriptor: String
    }

    nonisolated(unsafe) private static var cache: [CacheKey: DateFormatter] = [:]
    nonisolated(unsafe) private static var numberCache: [CacheKey: NumberFormatter] = [:]
    private static let cacheLock = NSLock()

    /// Returns a cached `DateFormatter` configured for `localeIdentifier`
    /// with the given `dateFormat` pattern (e.g. "EEE", "d MMM").
    /// (formatter cache lock contention): formatter creation
    /// is now performed *outside* the lock. The critical section is just the
    /// dictionary read/write; if two threads race we may briefly create two
    /// equivalent formatters, but only one is retained in the cache and the
    /// other is discarded. Avoids holding a lock across DateFormatter init
    /// which can do non-trivial CFLocale work.
    static func cachedDateFormatter(localeIdentifier: String, dateFormat: String) -> DateFormatter {
        let key = CacheKey(localeIdentifier: localeIdentifier, descriptor: "fmt:\(dateFormat)")
        if let cached = readDateCache(for: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateFormat = dateFormat
        return writeDateCache(formatter, for: key)
    }

    /// Returns a cached `DateFormatter` configured with `dateStyle` /
    /// `timeStyle`. Use this when you need locale-aware presentation
    /// (e.g. `.full`, `.short`).
    static func cachedDateFormatter(
        localeIdentifier: String,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style = .none
    ) -> DateFormatter {
        let key = CacheKey(
            localeIdentifier: localeIdentifier,
            descriptor: "style:\(dateStyle.rawValue):\(timeStyle.rawValue)"
        )
        if let cached = readDateCache(for: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return writeDateCache(formatter, for: key)
    }

    /// Returns a cached decimal `NumberFormatter` for the given locale and
    /// fraction-digit window. Lets row-heavy views (ExchangeRatesView etc.)
    /// avoid allocating a fresh NSFormatter per row per body render.
    static func cachedDecimalFormatter(
        localeIdentifier: String,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> NumberFormatter {
        let key = CacheKey(
            localeIdentifier: localeIdentifier,
            descriptor: "dec:\(minimumFractionDigits):\(maximumFractionDigits)"
        )
        cacheLock.lock()
        if let cached = numberCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits

        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = numberCache[key] {
            return existing
        }
        numberCache[key] = formatter
        return formatter
    }

    private static func readDateCache(for key: CacheKey) -> DateFormatter? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func writeDateCache(_ formatter: DateFormatter, for key: CacheKey) -> DateFormatter {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = cache[key] {
            return existing
        }
        cache[key] = formatter
        return formatter
    }
}
