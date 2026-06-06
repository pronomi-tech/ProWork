//  GlobalExchangeRateSyncService.swift
//  ProWork
//  Created by Pronomi

import Foundation
import os

private let globalDefaultCurrencyCodes = Currency.allCodes

enum GlobalExchangeRateSyncError: LocalizedError {
    case invalidDateRange
    case invalidResponse
    case noSupportedCurrencies(date: String)
    case ratesNotPublished(date: String)
    case requestFailed(statusCode: Int, date: String)
    case parseFailed(date: String)
    case networkUnavailable
    case hostNotFound
    case timedOut

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return localized("globalRates.error.invalidDateRange", defaultValue: "Başlangıç tarihi bitiş tarihinden sonra olamaz.")
        case .invalidResponse:
            return localized("globalRates.error.invalidResponse", defaultValue: "Global kur kaynağı yanıtı okunamadı.")
        case .noSupportedCurrencies(let date):
            return String(format: localized("globalRates.error.noSupportedCurrencies", defaultValue: "%@ için desteklenen para birimlerinde global referans kur bulunamadı."), date)
        case .ratesNotPublished(let date):
            return String(format: localized("globalRates.error.ratesNotPublished", defaultValue: "%@ için global referans kur yayımlanmamış."), date)
        case .requestFailed(let statusCode, let date):
            return String(format: localized("globalRates.error.requestFailed", defaultValue: "%@ için global kur isteği başarısız oldu (%d)."), date, statusCode)
        case .parseFailed(let date):
            return String(format: localized("globalRates.error.parseFailed", defaultValue: "%@ için global kur verisi çözülemedi."), date)
        case .networkUnavailable:
            return localized("globalRates.error.networkUnavailable", defaultValue: "İnternet bağlantısı kurulamadı. Uygulamanın ağ erişimini ve bağlantınızı kontrol edin.")
        case .hostNotFound:
            return localized("globalRates.error.hostNotFound", defaultValue: "Global kur sunucusuna ulaşılamadı. Ağ erişimi veya DNS çözümlemesi başarısız oldu.")
        case .timedOut:
            return localized("globalRates.error.timedOut", defaultValue: "Global kur isteği zaman aşımına uğradı. Birkaç saniye sonra yeniden deneyin.")
        }
    }
}

@MainActor
final class GlobalExchangeRateSyncService {
    private let repository: ExchangeRateRepository
    private let organizationId: String
    private let userId: String
    private let session: URLSession

    /// Y12 parallel-sync guard: while one sync is active, a second call
    /// awaits the same Task instead of starting a new one.
    private var activeSyncTask: Task<TCMBExchangeRateSyncResult, Error>?

    /// Uses Frankfurter ECB reference rates; the ECB does not publish on
    /// weekends or public holidays. We "carry forward" the most recently
    /// published day's rate by searching up to 7 days backwards.
    private static let carryForwardLookbackDays = BillingDefaults.exchangeRateCarryForwardDays

    // (DRY): retry policy and URLSession defaults are now
    // shared with TCMBExchangeRateSyncService via ExchangeRateSyncSupport.

    init(
        repository: ExchangeRateRepository? = nil,
        organizationId: String? = nil,
        userId: String? = nil,
        session: URLSession? = nil
    ) {
        self.repository = repository ?? ExchangeRateRepository()
        self.organizationId = organizationId ?? BuiltInOrganizationId.default
        self.userId = userId ?? BuiltInUserId.defaultOwner
        self.session = session ?? ExchangeRateSyncSupport.makeDefaultSession()
    }

    func sync(day: Date, currencies: [String]? = nil) async throws -> TCMBExchangeRateSyncResult {
        try await sync(from: day, to: day, currencies: currencies)
    }

    func sync(
        from startDate: Date,
        to endDate: Date,
        currencies: [String]? = nil
    ) async throws -> TCMBExchangeRateSyncResult {
        if let active = activeSyncTask {
            return try await active.value
        }
        let task = Task<TCMBExchangeRateSyncResult, Error> { [weak self] in
            // See TCMBExchangeRateSyncService — clearing
            // activeSyncTask from inside the task's defer raced against the
            // outer awaiter. Cleanup is now done in the caller after
            // task.value resolves with an identity guard.
            return try await self?.performSync(
                from: startDate,
                to: endDate,
                currencies: currencies
            ) ?? TCMBExchangeRateSyncResult(importedRateCount: 0, importedDayCount: 0, skippedDates: [])
        }
        activeSyncTask = task
        defer {
            // Task is a value type but its hashable identity comes from the
            // underlying task handle. Compare via `==` against the captured
            // task; if the slot was overwritten by a fresher caller we
            // leave it alone.
            if activeSyncTask == task {
                activeSyncTask = nil
            }
        }
        return try await task.value
    }

    private func performSync(
        from startDate: Date,
        to endDate: Date,
        currencies: [String]?
    ) async throws -> TCMBExchangeRateSyncResult {
        let normalizedStart = AppCalendar.istanbul.startOfDay(for: startDate)
        let normalizedEnd = AppCalendar.istanbul.startOfDay(for: endDate)
        guard normalizedStart <= normalizedEnd else {
            throw GlobalExchangeRateSyncError.invalidDateRange
        }

        let effectiveCurrencies = currencies ?? globalDefaultCurrencyCodes
        let requestedCurrencies = Set(effectiveCurrencies.map { $0.uppercased() }).subtracting(["TRY"])
        guard !requestedCurrencies.isEmpty else {
            return TCMBExchangeRateSyncResult(importedRateCount: 0, importedDayCount: 0, skippedDates: [])
        }

        var importedRateCount = 0
        var importedDayCount = 0
        var skippedDates: [String] = []
        var cursor = normalizedStart

        while cursor <= normalizedEnd {
            let dayString = AppDateFormatters.sqliteDay.string(from: cursor)
            do {
                let (quotes, carriedFromDate) = try await fetchRatesWithCarryForward(
                    for: cursor,
                    currencies: requestedCurrencies
                )
                try persistPublishedRates(
                    quotes,
                    on: dayString,
                    carriedFromDate: carriedFromDate
                )
                importedDayCount += 1
                importedRateCount += quotes.count
            } catch GlobalExchangeRateSyncError.ratesNotPublished {
                skippedDates.append(dayString)
            }

            cursor = AppCalendar.istanbul.date(byAdding: .day, value: 1, to: cursor) ?? normalizedEnd.addingTimeInterval(1)
        }

        return TCMBExchangeRateSyncResult(
            importedRateCount: importedRateCount,
            importedDayCount: importedDayCount,
            skippedDates: skippedDates
        )
    }

    private func fetchRatesWithCarryForward(
        for date: Date,
        currencies: Set<String>
    ) async throws -> ([String: ExchangeRateQuote], carriedFromDate: String?) {
        do {
            let rates = try await fetchPublishedTRYRates(for: date, currencies: currencies)
            return (rates, nil)
        } catch GlobalExchangeRateSyncError.ratesNotPublished {
            // ECB holiday / weekend — walk backwards to the nearest published day.
        }

        var probe = date
        for _ in 1...Self.carryForwardLookbackDays {
            guard let previous = AppCalendar.istanbul.date(byAdding: .day, value: -1, to: probe) else {
                break
            }
            probe = previous
            do {
                let rates = try await fetchPublishedTRYRates(for: probe, currencies: currencies)
                let carriedFromDate = AppDateFormatters.sqliteDay.string(from: probe)
                return (rates, carriedFromDate)
            } catch GlobalExchangeRateSyncError.ratesNotPublished {
                continue
            }
        }

        throw GlobalExchangeRateSyncError.ratesNotPublished(
            date: AppDateFormatters.sqliteDay.string(from: date)
        )
    }

    private func fetchPublishedTRYRates(
        for date: Date,
        currencies: Set<String>
    ) async throws -> [String: ExchangeRateQuote] {
        let requestedDay = AppDateFormatters.sqliteDay.string(from: date)
        let candidateURLs = makeURLs(for: date)
        var lastError: Error?
        var responsePayload: (Data, URLResponse)?

        for url in candidateURLs {
            do {
                responsePayload = try await fetchWithRetry(url: url)
                lastError = nil
                break
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw mapNetworkError(lastError)
        }

        guard let (data, response) = responsePayload else {
            throw GlobalExchangeRateSyncError.invalidResponse
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GlobalExchangeRateSyncError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw GlobalExchangeRateSyncError.ratesNotPublished(date: requestedDay)
        default:
            throw GlobalExchangeRateSyncError.requestFailed(statusCode: httpResponse.statusCode, date: requestedDay)
        }

        let payload: FrankfurterRatesPayload
        do {
            payload = try FrankfurterRatesPayload.decode(from: data)
        } catch {
            throw GlobalExchangeRateSyncError.parseFailed(date: requestedDay)
        }

        guard payload.date == requestedDay else {
            throw GlobalExchangeRateSyncError.ratesNotPublished(date: requestedDay)
        }

        let filtered = payload.rates
            .filter { currencies.contains($0.key.uppercased()) }
            .compactMapValues { quotedPerTRY -> ExchangeRateQuote? in
                guard quotedPerTRY > 0 else { return nil }
                let foreignToTry = 1 / quotedPerTRY
                return ExchangeRateQuote(
                    forexBuying: foreignToTry,
                    forexSelling: foreignToTry,
                    banknoteBuying: foreignToTry,
                    banknoteSelling: foreignToTry,
                    note: ProWorkLocalizer.shared.string("globalRates.note.referenceRate", defaultValue: "Global referans kur")
                )
            }

        guard !filtered.isEmpty else {
            throw GlobalExchangeRateSyncError.noSupportedCurrencies(date: requestedDay)
        }

        return filtered
    }

    private func persistPublishedRates(
        _ rates: [String: ExchangeRateQuote],
        on dayString: String,
        carriedFromDate: String?
    ) throws {
        let now = Date()
        let carryForwardNote: String? = carriedFromDate.map { source in
            String(
                format: ProWorkLocalizer.shared.string(
                    "globalRates.note.carriedForward",
                    defaultValue: "%@ tarihinde yayımlanan global referans kur, kur yayımlanmamış güne taşındı."
                ),
                source
            )
        }

        for (currency, quote) in rates.sorted(by: { $0.key < $1.key }) {
            guard let operationalRate = quote.operationalRate, operationalRate > 0 else {
                continue
            }

            let combinedNote: String?
            switch (carryForwardNote, quote.note) {
            case let (carry?, original?):
                combinedNote = "\(carry) (\(original))"
            case let (carry?, nil):
                combinedNote = carry
            case let (nil, original?):
                combinedNote = original
            default:
                combinedNote = nil
            }

            let rate = ExchangeRate(
                fromCurrency: currency,
                toCurrency: "TRY",
                rate: operationalRate,
                forexBuying: quote.forexBuying,
                forexSelling: quote.forexSelling,
                banknoteBuying: quote.banknoteBuying,
                banknoteSelling: quote.banknoteSelling,
                rateDate: dayString,
                source: .global,
                fetchedAt: now,
                note: combinedNote,
                organizationId: organizationId,
                createdByUserId: userId,
                updatedByUserId: userId,
                createdAt: now,
                updatedAt: now
            )
            try repository.upsert(rate)
        }
    }

    /// (DRY): retry/backoff implementation is now shared
    /// with TCMBExchangeRateSyncService via ExchangeRateSyncSupport so
    /// both sources honour the same 5xx handling and URLError classifier.
    /// As a side-effect Global now also retries on transient 5xx upstream
    /// responses (previously it skipped them).
    private func fetchWithRetry(url: URL) async throws -> (Data, URLResponse) {
        try await ExchangeRateSyncSupport.fetchWithRetry(url: url, session: session)
    }

    private func makeURLs(for date: Date) -> [URL] {
        let requestedDay = AppDateFormatters.sqliteDay.string(from: date)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.frankfurter.dev"
        components.path = "/v1/\(requestedDay)"
        components.queryItems = [
            URLQueryItem(name: "base", value: "TRY")
        ]

        var urls = components.url.map { [$0] } ?? []

        if AppCalendar.istanbul.isDate(date, inSameDayAs: Date()) {
            var latest = URLComponents()
            latest.scheme = "https"
            latest.host = "api.frankfurter.dev"
            latest.path = "/v1/latest"
            latest.queryItems = [
                URLQueryItem(name: "base", value: "TRY")
            ]
            if let url = latest.url {
                urls.append(url)
            }
        }

        return urls
    }

    private func mapNetworkError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return GlobalExchangeRateSyncError.hostNotFound
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
            return GlobalExchangeRateSyncError.networkUnavailable
        case .timedOut:
            return GlobalExchangeRateSyncError.timedOut
        default:
            return error
        }
    }

}

struct FrankfurterRatesPayload {
    let date: String
    let rates: [String: Decimal]

    /// Parses the Frankfurter response while preserving full `Decimal`
    /// precision. `JSONDecoder` decodes JSON numbers through `Double`, so
    /// `0.0234` would round-trip into `0.02339999…`. Going through
    /// `JSONSerialization` + `NSNumber.stringValue` gives us the canonical
    /// shortest round-trippable text, and `Decimal(string:)` reconstructs
    /// it without ever crossing `Double`.
    static func decode(from data: Data) throws -> FrankfurterRatesPayload {
        guard let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw GlobalExchangeRateSyncError.invalidResponse
        }
        guard let date = root["date"] as? String else {
            throw GlobalExchangeRateSyncError.invalidResponse
        }
        guard let rawRates = root["rates"] as? [String: Any] else {
            throw GlobalExchangeRateSyncError.invalidResponse
        }

        let posix = Locale(identifier: "en_US_POSIX")
        var rates: [String: Decimal] = [:]
        rates.reserveCapacity(rawRates.count)

        for (code, value) in rawRates {
            let text: String
            if let n = value as? NSNumber {
                text = n.stringValue
            } else if let s = value as? String {
                text = s
            } else {
                // Surface non-numeric / non-string entries so a
                // payload shape change (e.g. provider switching to a
                // nested object per currency) is debuggable instead of
                // silently dropping the affected codes.
                let typeName = String(describing: type(of: value))
                ProWorkLog.billing.debug(
                    "FrankfurterRatesPayload: skipping non-numeric/non-string entry code=\(code, privacy: .public) type=\(typeName, privacy: .public)"
                )
                continue
            }
            if let decimal = Decimal(string: text, locale: posix) {
                rates[code] = decimal
            } else {
                ProWorkLog.billing.debug(
                    "FrankfurterRatesPayload: unparseable decimal for code=\(code, privacy: .public) text=\(text, privacy: .public)"
                )
            }
        }

        return FrankfurterRatesPayload(date: date, rates: rates)
    }
}
