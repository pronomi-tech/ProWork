//
//  GlobalExchangeRateSyncService.swift
//  ProWork
//
//  Created by Pronomi
//

import Foundation

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

    init(
        repository: ExchangeRateRepository? = nil,
        organizationId: String? = nil,
        userId: String? = nil,
        session: URLSession = .shared
    ) {
        self.repository = repository ?? ExchangeRateRepository()
        self.organizationId = organizationId ?? BuiltInOrganizationId.default
        self.userId = userId ?? BuiltInUserId.defaultOwner
        self.session = session
    }

    func sync(day: Date, currencies: [String]? = nil) async throws -> TCMBExchangeRateSyncResult {
        try await sync(from: day, to: day, currencies: currencies)
    }

    func sync(
        from startDate: Date,
        to endDate: Date,
        currencies: [String]? = nil
    ) async throws -> TCMBExchangeRateSyncResult {
        let normalizedStart = Calendar.current.startOfDay(for: startDate)
        let normalizedEnd = Calendar.current.startOfDay(for: endDate)
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
            let dayString = Self.storageFormatter.string(from: cursor)
            do {
                let quotes = try await fetchPublishedTRYRates(for: cursor, currencies: requestedCurrencies)
                try persistPublishedRates(quotes, on: dayString)
                importedDayCount += 1
                importedRateCount += quotes.count
            } catch GlobalExchangeRateSyncError.ratesNotPublished {
                skippedDates.append(dayString)
            }

            cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor) ?? normalizedEnd.addingTimeInterval(1)
        }

        return TCMBExchangeRateSyncResult(
            importedRateCount: importedRateCount,
            importedDayCount: importedDayCount,
            skippedDates: skippedDates
        )
    }

    private func fetchPublishedTRYRates(
        for date: Date,
        currencies: Set<String>
    ) async throws -> [String: ExchangeRateQuote] {
        let requestedDay = Self.storageFormatter.string(from: date)
        let candidateURLs = makeURLs(for: date)
        var lastError: Error?
        var responsePayload: (Data, URLResponse)?

        for url in candidateURLs {
            do {
                responsePayload = try await session.data(from: url)
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

        let decoder = JSONDecoder()
        let payload: FrankfurterRatesPayload
        do {
            payload = try decoder.decode(FrankfurterRatesPayload.self, from: data)
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

    private func persistPublishedRates(_ rates: [String: ExchangeRateQuote], on dayString: String) throws {
        let now = Date()

        for (currency, quote) in rates.sorted(by: { $0.key < $1.key }) {
            guard let operationalRate = quote.operationalRate, operationalRate > 0 else {
                continue
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
                note: quote.note,
                organizationId: organizationId,
                createdByUserId: userId,
                updatedByUserId: userId,
                createdAt: now,
                updatedAt: now
            )
            try repository.upsert(rate)
        }
    }

    private func makeURLs(for date: Date) -> [URL] {
        let requestedDay = Self.storageFormatter.string(from: date)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.frankfurter.dev"
        components.path = "/v1/\(requestedDay)"
        components.queryItems = [
            URLQueryItem(name: "base", value: "TRY")
        ]

        var urls = components.url.map { [$0] } ?? []

        if Calendar.current.isDate(date, inSameDayAs: Date()) {
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

    private static let storageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct FrankfurterRatesPayload: Decodable {
    let date: String
    let rates: [String: Decimal]
}
