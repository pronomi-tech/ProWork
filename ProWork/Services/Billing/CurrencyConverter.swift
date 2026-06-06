//  CurrencyConverter.swift
//  ProWork
//  Created by Pronomi.
//  Per the Q5 + Q5b decisions:
//  - Report totals are computed in the organization's master currency.
//  - Other currencies are converted using TCMB rates; if TCMB is
//    unreachable, fall back to the last manual/cached rate.
//  This service runs against the "rate table". TCMB download lives in
//  `TCMBExchangeRateClient` (separate file, Phase 5 — with the UI).

import Foundation
import os

enum CurrencyConversionError: LocalizedError {
    case noRateAvailable(from: String, to: String, on: String)

    var errorDescription: String? {
        switch self {
        case .noRateAvailable(let from, let to, let on):
            return String(
                format: ProWorkLocalizer.shared.string(
                    "currency.error.noRateAvailable",
                    defaultValue: "%@ → %@ için %@ tarihine kadar kayıtlı kur bulunamadı."
                ),
                from,
                to,
                on
            )
        }
    }
}

/// `CurrencyConverter` performs no UI work and holds only
/// repository handles + a private LRU cache. Marking it `@MainActor` blocked
/// long report calculations on the main thread. Drop the isolation and serialize
/// cache mutations through `cacheLock` instead so background billing
/// computations can run off-main.
final class CurrencyConverter {
    private let rateRepository: ExchangeRateRepository
    private let organizationId: String
    private let masterCurrency: String
    private let sourcePriority: [ExchangeRateSource]

    private struct RateCacheKey: Hashable {
        let from: String
        let to: String
        let date: String
        /// Bridged (via-master) results used to share the
        /// same cache key as direct rates. If a direct rate landed in the DB
        /// later, the cache kept serving the stale bridged value. Mark the
        /// path explicitly so direct and bridged results live in disjoint
        /// slots; an invalidate() call still clears both.
        let isBridged: Bool
    }

    /// Insertion-ordered cache + simple LRU promotion. Foundation has no
    /// native ordered dictionary on macOS that combines both, but a
    /// dictionary + array keeps lookups O(1) and eviction O(n) where n
    /// is bounded by `cacheLimit`.
    private var rateCache: [RateCacheKey: Decimal] = [:]
    private var rateCacheOrder: [RateCacheKey] = []
    /// Upper bound: on a typical long-running screen, 30 days × 5
    /// currencies cross = 750 rows. 1024 leaves comfortable headroom;
    /// once exceeded, the LRU element is evicted. Cache is
    /// per-converter-instance; for
    /// dashboards that show many runs concurrently, a single
    /// AppServices-owned shared converter would be more efficient
    /// . Documented here so the next refactor knows where
    /// to start; not promoted yet because every ViewModel currently
    /// supplies its own organizationId/masterCurrency combo and the
    /// shared-cache invariants would need careful design.
    private let cacheLimit = 1024
    /// Serialise cache mutations now that the class is no longer pinned to
    /// the main actor. NSLock is cheap; the critical
    /// sections are O(1)/O(n) bounded by `cacheLimit`.
    private let cacheLock = NSLock()
    /// Token returned by NotificationCenter for the
    /// `.proWorkExchangeRatesDidChange` subscription. Held so we can
    /// `removeObserver` in deinit and avoid leaking a closure that keeps
    /// the converter alive after its owning ViewModel is gone.
    private var cacheInvalidationObserver: NSObjectProtocol?

    /// `preferredAutoSource` is mandatory. Constructor used to
    /// fall back to a synchronous `AppSettingsRepository().fetch()` —
    /// from non-MainActor contexts that hit DB locks at the worst time,
    /// and from a freshly-spawned ViewModel that hadn't yet wired
    /// dependencies. Callers MUST resolve the user preference up-front
    /// (typically via `AppServices` or `AppSettingsStore`) and inject it.
    /// A nil-preference branch survives only for the `nil → .tcmb`
    /// fallback that mirrors the previous default.
    init(
        rateRepository: ExchangeRateRepository? = nil,
        organizationId: String,
        masterCurrency: String,
        preferredAutoSource: ExchangeRateAutoSource
    ) {
        self.rateRepository = rateRepository ?? ExchangeRateRepository()
        self.organizationId = organizationId
        // An empty masterCurrency caused infinite recursion in the
        // master-bridge branch (f != "" && t != "" was always true).
        // Falling back to "TRY" is both safe and the app's default.
        let normalizedMaster = masterCurrency.uppercased()
        self.masterCurrency = normalizedMaster.isEmpty ? BillingDefaults.fallbackCurrency : normalizedMaster
        self.sourcePriority = [.manual, preferredAutoSource.source, preferredAutoSource.fallbackSource]
        // Subscribe to global rate-change broadcasts (TCMB/global sync,
        // manual edits) so long-lived converter instances drop stale
        // cached rates rather than serving them for the rest of the
        // session.
        self.cacheInvalidationObserver = NotificationCenter.default.addObserver(
            forName: .proWorkExchangeRatesDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidateCache()
        }
    }

    deinit {
        if let token = cacheInvalidationObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Converts a `Money` value to the target currency. Returns it unchanged when the currency already matches.
    func convert(_ amount: Money, to targetCurrency: String, on date: String) throws -> Money {
        let target = targetCurrency.uppercased()
        if amount.currency == target {
            return amount
        }

        let rate = try resolveRate(from: amount.currency, to: target, on: date)
        var product = amount.amount * rate
        // K8: Banker's round the converted result to the target
        // currency's minor-unit precision. Otherwise, after chained
        // convert + sum, decimal tails accumulate in the accumulator
        // and the report total diverges from the DB total. Money.minorUnits
        // will round again when writing to the DB, but early truncation
        // here stabilises intermediate computations (especially in
        // `sumInMaster`).
        // Currency.info(for:) defaults unknown codes to 2
        // decimal places, which silently truncated 3-decimal precision
        // currencies (KWD, BHD, OMR, JOD, TND, LYD, IQD) to a coarser
        // decimal precision — a real 0.123 dinar would have been
        // written to the DB as 0.12.
        // Log unknown codes AND preserve up to 4 decimal places; a safe
        // upper bound for future expansions of Currency.registry.
        var rounded = Decimal()
        let info = Currency.info(for: target)
        let places: Int
        if Currency.knownCodes.contains(target) {
            places = max(0, info.decimalPlaces)
        } else {
            ProWorkLog.billing.warning(
                "CurrencyConverter.convert: unknown currency \(target, privacy: .public); preserving 4 decimal places to avoid silent precision loss"
            )
            places = 4
        }
        NSDecimalRound(&rounded, &product, places, .bankers)
        return Money(amount: rounded, currency: target)
    }

    /// Shortcut for converting to the master currency.
    func convertToMaster(_ amount: Money, on date: String) throws -> Money {
        try convert(amount, to: masterCurrency, on: date)
    }

    /// Sums multiple `Money` values in the master currency.
    /// Same-currency items are summed directly; different currencies are converted first.
    func sumInMaster(_ amounts: [Money], on date: String) throws -> Money {
        var total = Money.zero(masterCurrency)
        for amount in amounts {
            let converted = try convertToMaster(amount, on: date)
            total = total + converted
        }
        return total
    }

    // MARK: - Rate resolution

    /// Maximum number of decimal places kept for FX rates in the cache.
    /// Rates are stored in the DB as raw strings so direct records keep
    /// their precision; in the reverse/master-bridge path, `1/x` or
    /// `a*b` operations can extend the decimal tail indefinitely.
    /// 8 decimal places is the international FX standard
    /// (banker's-friendly) and keeps the cache stable while preserving
    /// reasonable FX precision.
    private static let cachedRateScale: Int = 8

    /// Resolves the rate between two currencies:
    /// 1. Use the direct record (from→to) if present
    /// 2. Otherwise, take the inverse of the reverse record (to→from)
    /// 3. Otherwise, bridge via master: from → master → to
    /// 4. Otherwise, throw
    func resolveRate(from: String, to: String, on date: String) throws -> Decimal {
        try resolveRate(from: from, to: to, on: date, depth: 0)
    }

    /// Internal entry point. `depth` is an explicit recursion guard for the
    /// master-bridge fallback; top-level callers start at
    /// 0 and the bridge legs pass `depth + 1`. We hard-cap at 2 so a
    /// pathological chain (e.g. master itself missing direct rates) never
    /// loops.
    private func resolveRate(
        from: String,
        to: String,
        on date: String,
        depth: Int
    ) throws -> Decimal {
        let f = from.uppercased()
        let t = to.uppercased()
        if f == t { return 1 }

        let cacheKey = RateCacheKey(from: f, to: t, date: date, isBridged: depth > 0)
        if let cached = lookupCachedRate(cacheKey) {
            return cached
        }

        var resolved = try computeRate(from: f, to: t, on: date, depth: depth)
        var capped = Decimal()
        NSDecimalRound(&capped, &resolved, Self.cachedRateScale, .bankers)
        storeInCache(key: cacheKey, value: capped)
        return capped
    }

    /// Call after the user adds/changes a manual rate.
    /// Invalidation is parameter-free — since we know exactly what we
    /// returned for which (from,to,date) over the converter's lifetime,
    /// the whole cache is dropped instead of selectively removing
    /// entries; FX changes are typically a daily event so the refetch
    /// cost is small.
    func invalidateCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        rateCache.removeAll(keepingCapacity: true)
        rateCacheOrder.removeAll(keepingCapacity: true)
    }

    private func lookupCachedRate(_ key: RateCacheKey) -> Decimal? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = rateCache[key] else { return nil }
        if let idx = rateCacheOrder.firstIndex(of: key) {
            rateCacheOrder.remove(at: idx)
        }
        rateCacheOrder.append(key)
        return cached
    }

    private func storeInCache(key: RateCacheKey, value: Decimal) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if rateCache[key] != nil {
            if let idx = rateCacheOrder.firstIndex(of: key) {
                rateCacheOrder.remove(at: idx)
            }
        }
        rateCache[key] = value
        rateCacheOrder.append(key)
        while rateCacheOrder.count > cacheLimit {
            let oldest = rateCacheOrder.removeFirst()
            rateCache.removeValue(forKey: oldest)
        }
    }

    /// `try?` would have swallowed every fetch error,
    /// flattening a DB lock or schema corruption into
    /// `.noRateAvailable` — exactly the same signal a missing rate
    /// emits, so the UI can't distinguish "no rate" from "DB is
    /// broken". Now we surface the underlying error and only treat a
    /// genuine "no row" (nil result) as a miss to be retried via the
    /// other branches.
    private func computeRate(from f: String, to t: String, on date: String, depth: Int) throws -> Decimal {
        // 1. Direct
        if let direct = try rateRepository.fetchLatest(
            organizationId: organizationId,
            from: f, to: t, on: date,
            sourcePriority: sourcePriority
        ), direct.operationalRate > 0 {
            return direct.operationalRate
        }

        // 2. Reverse
        if let reverse = try rateRepository.fetchLatest(
            organizationId: organizationId,
            from: t, to: f, on: date,
            sourcePriority: sourcePriority
        ), reverse.operationalRate > 0 {
            return 1 / reverse.operationalRate
        }

        // 3. Bridge via master — triggered only by a top-level call.
        // `depth + 1` prevents the recursive resolveRate from
        // attempting another bridge (depth > 0 also disambiguates the
        // cache key). The recursive call now propagates errors as well;
        // bridging only catches the inner `.noRateAvailable` so a
        // partially missing leg downgrades cleanly into the outer
        // noRateAvailable rather than silently producing a wrong rate.
        if f != masterCurrency && t != masterCurrency && depth < 1 {
            let toMaster: Decimal?
            do {
                toMaster = try resolveRate(from: f, to: masterCurrency, on: date, depth: depth + 1)
            } catch CurrencyConversionError.noRateAvailable {
                toMaster = nil
            }
            let fromMaster: Decimal?
            do {
                fromMaster = try resolveRate(from: masterCurrency, to: t, on: date, depth: depth + 1)
            } catch CurrencyConversionError.noRateAvailable {
                fromMaster = nil
            }
            if let toMaster, let fromMaster {
                return toMaster * fromMaster
            }
        }

        throw CurrencyConversionError.noRateAvailable(from: f, to: t, on: date)
    }
}

// MARK: - Cache invalidation broadcast

extension Notification.Name {
    /// Posted when exchange-rate data changes (TCMB/global sync, manual rate
    /// add/edit/delete). Long-lived `CurrencyConverter` instances observe this
    /// to flush their per-instance rate cache; without invalidation, view
    /// models holding a converter would continue serving pre-sync rates.
    static let proWorkExchangeRatesDidChange = Notification.Name("ProWorkExchangeRatesDidChange")
}
