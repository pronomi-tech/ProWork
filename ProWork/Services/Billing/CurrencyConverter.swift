//
//  CurrencyConverter.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Soru 5 + 5b kararı uyarınca:
//  - Organization ana para biriminde rapor toplamı yapılır.
//  - Diğer currency'ler TCMB kuru ile çevrilir; bağlanılamazsa son manuel/cache'lenmiş kura düşer.
//
//  Bu servis "kur tablosu" üzerinden çalışır. TCMB indirme `TCMBExchangeRateClient`
//  içinde olacak (ayrı dosya, Faz 5 — UI ile birlikte).
//

import Foundation

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

@MainActor
final class CurrencyConverter {
    private let rateRepository: ExchangeRateRepository
    private let organizationId: String
    private let masterCurrency: String
    private let sourcePriority: [ExchangeRateSource]

    private struct RateCacheKey: Hashable {
        let from: String
        let to: String
        let date: String
    }

    private var rateCache: [RateCacheKey: Decimal] = [:]

    init(
        rateRepository: ExchangeRateRepository? = nil,
        organizationId: String,
        masterCurrency: String,
        preferredAutoSource: ExchangeRateAutoSource? = nil
    ) {
        self.rateRepository = rateRepository ?? ExchangeRateRepository()
        self.organizationId = organizationId
        // Boş bir masterCurrency, master üzerinden zincirleme dalında sonsuz
        // rekürsiyona yol açıyordu (f != "" && t != "" hep doğru). "TRY"'ye
        // düşmek hem güvenli hem de uygulamanın default'u.
        let normalizedMaster = masterCurrency.uppercased()
        self.masterCurrency = normalizedMaster.isEmpty ? "TRY" : normalizedMaster
        let resolvedPreferredSource = preferredAutoSource
            ?? (try? AppSettingsRepository().fetch().preferredExchangeRateSource)
            ?? .tcmb
        self.sourcePriority = [.manual, resolvedPreferredSource.source, resolvedPreferredSource.fallbackSource]
    }

    /// Bir `Money` değerini hedef currency'ye çevirir. Aynı currency'de ise olduğu gibi döner.
    func convert(_ amount: Money, to targetCurrency: String, on date: String) throws -> Money {
        let target = targetCurrency.uppercased()
        if amount.currency == target {
            return amount
        }

        let rate = try resolveRate(from: amount.currency, to: target, on: date)
        return Money(amount: amount.amount * rate, currency: target)
    }

    /// Master currency'ye çevirmek için kısa yol.
    func convertToMaster(_ amount: Money, on date: String) throws -> Money {
        try convert(amount, to: masterCurrency, on: date)
    }

    /// Birden fazla `Money` değerini master currency'de toplar.
    /// Aynı currency'deki kalemleri toplar, farklı currency'leri çevirir.
    func sumInMaster(_ amounts: [Money], on date: String) throws -> Money {
        var total = Money.zero(masterCurrency)
        for amount in amounts {
            let converted = try convertToMaster(amount, on: date)
            total = total + converted
        }
        return total
    }

    // MARK: - Rate resolution

    /// İki currency arası kuru çözer:
    /// 1. Doğrudan kayıt (from→to) varsa kullan
    /// 2. Yoksa ters kayıt (to→from) varsa tersini al
    /// 3. Yoksa master üzerinden zincirle: from → master → to
    /// 4. Hiçbiri yoksa hata
    func resolveRate(from: String, to: String, on date: String) throws -> Decimal {
        let f = from.uppercased()
        let t = to.uppercased()
        if f == t { return 1 }

        // Aynı (from, to, date) üçlüsü dönem hesabında yüzlerce kez sorulabiliyor;
        // her seferinde DB sorgusu + (gerekirse) master üzerinden zincirleme bedeli
        // ödememek için sonuçları memoize ediyoruz. DB'de exchange_rate satırları
        // append-only akışta yazıldığından converter ömrü boyunca sabit kabul edilebilir.
        let cacheKey = RateCacheKey(from: f, to: t, date: date)
        if let cached = rateCache[cacheKey] {
            return cached
        }

        let resolved = try computeRate(from: f, to: t, on: date)
        rateCache[cacheKey] = resolved
        return resolved
    }

    private func computeRate(from f: String, to t: String, on date: String) throws -> Decimal {
        // 1. Doğrudan
        if let direct = try? rateRepository.fetchLatest(
            organizationId: organizationId,
            from: f, to: t, on: date,
            sourcePriority: sourcePriority
        ), direct.operationalRate > 0 {
            return direct.operationalRate
        }

        // 2. Ters
        if let reverse = try? rateRepository.fetchLatest(
            organizationId: organizationId,
            from: t, to: f, on: date,
            sourcePriority: sourcePriority
        ), reverse.operationalRate > 0 {
            return 1 / reverse.operationalRate
        }

        // 3. Master üzerinden zincirle
        if f != masterCurrency && t != masterCurrency {
            let toMaster = try? resolveRate(from: f, to: masterCurrency, on: date)
            let fromMaster = try? resolveRate(from: masterCurrency, to: t, on: date)
            if let toMaster, let fromMaster {
                return toMaster * fromMaster
            }
        }

        throw CurrencyConversionError.noRateAvailable(from: f, to: t, on: date)
    }
}
