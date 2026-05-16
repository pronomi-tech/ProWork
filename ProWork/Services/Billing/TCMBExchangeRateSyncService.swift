//
//  TCMBExchangeRateSyncService.swift
//  ProWork
//
//  Created by Pronomi
//

import Foundation

private let tcmbDefaultCurrencyCodes = Currency.allCodes

struct ExchangeRateQuote: Hashable {
    let forexBuying: Decimal?
    let forexSelling: Decimal?
    let banknoteBuying: Decimal?
    let banknoteSelling: Decimal?
    let note: String?

    var operationalRate: Decimal? {
        forexSelling ?? forexBuying ?? banknoteSelling ?? banknoteBuying
    }
}

struct TCMBExchangeRateSyncResult: Hashable {
    let importedRateCount: Int
    let importedDayCount: Int
    let skippedDates: [String]
}

enum TCMBExchangeRateSyncError: LocalizedError {
    case invalidDateRange
    case invalidResponse
    case requestFailed(statusCode: Int, date: String)
    case ratesNotPublished(date: String)
    case noSupportedCurrencies(date: String)
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
            return localized("tcmb.error.invalidDateRange", defaultValue: "Başlangıç tarihi bitiş tarihinden sonra olamaz.")
        case .invalidResponse:
            return localized("tcmb.error.invalidResponse", defaultValue: "TCMB yanıtı okunamadı.")
        case .requestFailed(let statusCode, let date):
            return String(format: localized("tcmb.error.requestFailed", defaultValue: "%@ için TCMB isteği başarısız oldu (%d)."), date, statusCode)
        case .ratesNotPublished(let date):
            return String(format: localized("tcmb.error.ratesNotPublished", defaultValue: "%@ için TCMB kuru yayımlanmamış."), date)
        case .noSupportedCurrencies(let date):
            return String(format: localized("tcmb.error.noSupportedCurrencies", defaultValue: "%@ için desteklenen para birimlerinde TCMB kuru bulunamadı."), date)
        case .parseFailed(let date):
            return String(format: localized("tcmb.error.parseFailed", defaultValue: "%@ için TCMB veri formatı çözülemedi."), date)
        case .networkUnavailable:
            return localized("tcmb.error.networkUnavailable", defaultValue: "İnternet bağlantısı kurulamadı. Uygulamanın ağ erişimini ve bağlantınızı kontrol edin.")
        case .hostNotFound:
            return localized("tcmb.error.hostNotFound", defaultValue: "TCMB sunucusuna ulaşılamadı. Ağ erişimi veya DNS çözümlemesi başarısız oldu.")
        case .timedOut:
            return localized("tcmb.error.timedOut", defaultValue: "TCMB isteği zaman aşımına uğradı. Birkaç saniye sonra yeniden deneyin.")
        }
    }
}

@MainActor
final class TCMBExchangeRateSyncService {
    private let repository: ExchangeRateRepository
    private let organizationId: String
    private let userId: String
    private let session: URLSession

    /// 404 sonrası kuru "ileri taşımak" için en fazla geriye gidilecek gün
    /// sayısı. TCMB hafta sonu ve resmi tatillerde kur yayımlamaz; pratik
    /// olarak bir önceki iş gününün kuru kullanılır. 7 gün, art arda gelen
    /// resmi tatil + hafta sonu kombinasyonlarını rahatlıkla karşılar.
    private static let carryForwardLookbackDays = 7

    /// Geçici ağ hataları için exponential backoff: 1s, 2s, 4s.
    private static let retryDelaysNanoseconds: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        4_000_000_000
    ]

    init(
        repository: ExchangeRateRepository? = nil,
        organizationId: String? = nil,
        userId: String? = nil,
        session: URLSession? = nil
    ) {
        self.repository = repository ?? ExchangeRateRepository()
        self.organizationId = organizationId ?? BuiltInOrganizationId.default
        self.userId = userId ?? BuiltInUserId.defaultOwner
        // Varsayılan URLSession.shared timeout'u 60s. Yıllık sync ~365 istek
        // demek; tek bir hata 6+ saat bekleme yaratabiliyor. 15s istek / 30s
        // resource limitiyle hızlı başarısızlık + retry akışına geçiyoruz.
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
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
            throw TCMBExchangeRateSyncError.invalidDateRange
        }

        let effectiveCurrencies = currencies ?? tcmbDefaultCurrencyCodes
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
                // Önce talep edilen güne dene; 404 ise N gün geriye doğru
                // yürüyüp ilk yayımlanmış kuru "ileri taşı". Bu, TCMB'nin
                // hafta sonu / tatil davranışını uygulama tarafında simüle eder.
                let (rates, carriedFromDate) = try await fetchRatesWithCarryForward(
                    for: cursor,
                    currencies: requestedCurrencies
                )
                try persistPublishedRates(
                    rates,
                    on: dayString,
                    carriedFromDate: carriedFromDate
                )
                importedDayCount += 1
                importedRateCount += rates.count
            } catch TCMBExchangeRateSyncError.ratesNotPublished {
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

    /// Önce talep edilen tarihi dener. 404 ile karşılaşırsa
    /// `carryForwardLookbackDays` kadar geriye yürüyüp ilk yayımlanmış kuru
    /// döner. Hiçbir gün yayımlanmamışsa `.ratesNotPublished` fırlatır.
    /// İkinci tuple elemanı, kur "ileri taşındıysa" kaynak tarihtir.
    private func fetchRatesWithCarryForward(
        for date: Date,
        currencies: Set<String>
    ) async throws -> ([String: ExchangeRateQuote], carriedFromDate: String?) {
        do {
            let rates = try await fetchPublishedTRYRates(for: date, currencies: currencies)
            return (rates, nil)
        } catch TCMBExchangeRateSyncError.ratesNotPublished {
            // Hafta sonu / tatil — geriye doğru en yakın iş gününü bul.
        }

        var probe = date
        for _ in 1...Self.carryForwardLookbackDays {
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: probe) else {
                break
            }
            probe = previous
            do {
                let rates = try await fetchPublishedTRYRates(for: probe, currencies: currencies)
                let carriedFromDate = AppDateFormatters.sqliteDay.string(from: probe)
                return (rates, carriedFromDate)
            } catch TCMBExchangeRateSyncError.ratesNotPublished {
                continue
            }
        }

        throw TCMBExchangeRateSyncError.ratesNotPublished(
            date: AppDateFormatters.sqliteDay.string(from: date)
        )
    }

    private func fetchPublishedTRYRates(
        for date: Date,
        currencies: Set<String>
    ) async throws -> [String: ExchangeRateQuote] {
        let dayString = AppDateFormatters.sqliteDay.string(from: date)
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
            throw TCMBExchangeRateSyncError.invalidResponse
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TCMBExchangeRateSyncError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw TCMBExchangeRateSyncError.ratesNotPublished(date: dayString)
        default:
            throw TCMBExchangeRateSyncError.requestFailed(statusCode: httpResponse.statusCode, date: dayString)
        }

        let parser = TCMBRatesXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser

        guard xmlParser.parse() else {
            throw TCMBExchangeRateSyncError.parseFailed(date: dayString)
        }

        let filtered = parser.rates.filter { currencies.contains($0.key) }
        guard !filtered.isEmpty else {
            throw TCMBExchangeRateSyncError.noSupportedCurrencies(date: dayString)
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
                    "tcmb.note.carriedForward",
                    defaultValue: "%@ tarihinde yayımlanan kur, kur yayımlanmamış güne taşındı."
                ),
                source
            )
        }

        for (currency, quote) in rates.sorted(by: { $0.key < $1.key }) {
            guard let operationalRate = quote.operationalRate, operationalRate > 0 else {
                continue
            }

            // Carry-forward durumunda hem kaynak hem de TCMB'nin orijinal
            // notunu kullanıcıya gösterebilmek için birleştiriyoruz.
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

            let direct = ExchangeRate(
                fromCurrency: currency,
                toCurrency: "TRY",
                rate: operationalRate,
                forexBuying: quote.forexBuying,
                forexSelling: quote.forexSelling,
                banknoteBuying: quote.banknoteBuying,
                banknoteSelling: quote.banknoteSelling,
                rateDate: dayString,
                source: .tcmb,
                fetchedAt: now,
                note: combinedNote,
                organizationId: organizationId,
                createdByUserId: userId,
                updatedByUserId: userId,
                createdAt: now,
                updatedAt: now
            )
            try repository.upsert(direct)
        }
    }

    /// Geçici ağ hatalarında 1s → 2s → 4s backoff ile en fazla 3 kez tekrar
    /// dener. Persistent hatalar (404 vb. HTTP cevapları) retry'a sokulmaz;
    /// onları çağıran katman zaten skip'liyor.
    private func fetchWithRetry(url: URL) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                return try await session.data(from: url)
            } catch {
                attempt += 1
                guard attempt <= Self.retryDelaysNanoseconds.count,
                      Self.shouldRetry(error: error) else {
                    throw error
                }
                try? await Task.sleep(nanoseconds: Self.retryDelaysNanoseconds[attempt - 1])
            }
        }
    }

    private static func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func makeURLs(for date: Date) -> [URL] {
        let monthFolder = Self.monthFolderFormatter.string(from: date)
        let fileName = Self.fileNameFormatter.string(from: date)
        var candidates = [
            "https://www.tcmb.gov.tr/kurlar/\(monthFolder)/\(fileName).xml"
        ]

        if Calendar.current.isDate(date, inSameDayAs: Date()) {
            candidates.append("https://www.tcmb.gov.tr/kurlar/today.xml")
        }

        return candidates.compactMap(URL.init(string:))
    }

    private func mapNetworkError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return TCMBExchangeRateSyncError.hostNotFound
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
            return TCMBExchangeRateSyncError.networkUnavailable
        case .timedOut:
            return TCMBExchangeRateSyncError.timedOut
        default:
            return error
        }
    }


    private static let monthFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMM"
        return formatter
    }()

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "ddMMyyyy"
        return formatter
    }()
}

private final class TCMBRatesXMLParser: NSObject, XMLParserDelegate {
    private(set) var rates: [String: ExchangeRateQuote] = [:]

    private var currentCurrencyCode: String?
    private var currentElement: String?
    private var currentUnitText = ""
    private var currentForexSellingText = ""
    private var currentForexBuyingText = ""
    private var currentBanknoteSellingText = ""
    private var currentBanknoteBuyingText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        currentElement = elementName

        if elementName == "Currency" {
            currentCurrencyCode = attributeDict["CurrencyCode"]?.uppercased() ?? attributeDict["Kod"]?.uppercased()
            currentUnitText = ""
            currentForexSellingText = ""
            currentForexBuyingText = ""
            currentBanknoteSellingText = ""
            currentBanknoteBuyingText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentCurrencyCode != nil else { return }

        switch currentElement {
        case "Unit":
            currentUnitText += string
        case "ForexSelling":
            currentForexSellingText += string
        case "ForexBuying":
            currentForexBuyingText += string
        case "BanknoteSelling":
            currentBanknoteSellingText += string
        case "BanknoteBuying":
            currentBanknoteBuyingText += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "Currency" {
            defer {
                currentCurrencyCode = nil
                currentElement = nil
            }

            guard let code = currentCurrencyCode else { return }
            let unit = max(Int(trimmed(currentUnitText)) ?? 1, 1)
            let divisor = Decimal(unit)
            let forexBuying = decimalValue(from: currentForexBuyingText).map { $0 / divisor }
            let forexSelling = decimalValue(from: currentForexSellingText).map { $0 / divisor }
            let banknoteBuying = decimalValue(from: currentBanknoteBuyingText).map { $0 / divisor }
            let banknoteSelling = decimalValue(from: currentBanknoteSellingText).map { $0 / divisor }

            guard forexBuying != nil || forexSelling != nil || banknoteBuying != nil || banknoteSelling != nil else {
                return
            }

            rates[code] = ExchangeRateQuote(
                forexBuying: forexBuying,
                forexSelling: forexSelling,
                banknoteBuying: banknoteBuying,
                banknoteSelling: banknoteSelling,
                note: ProWorkLocalizer.shared.string("tcmb.note.referenceRates", defaultValue: "TCMB referans kurları")
            )
            return
        }

        currentElement = nil
    }

    private func decimalValue(from text: String) -> Decimal? {
        let raw = trimmed(text)
        let normalized: String
        if raw.contains(",") {
            normalized = raw
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = raw
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
