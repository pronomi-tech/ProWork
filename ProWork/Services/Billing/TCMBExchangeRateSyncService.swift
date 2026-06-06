//  TCMBExchangeRateSyncService.swift
//  ProWork
//  Created by Pronomi

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

    /// The currently in-flight sync task. Y12: if the user clicks the
    /// button twice or two UI sites trigger it, the second call awaits
    /// the first's result instead of starting a new network flow — the
    /// same date range is never fetched twice.
    private var activeSyncTask: Task<TCMBExchangeRateSyncResult, Error>?

    /// Maximum number of days to walk backward when "carrying forward"
    /// a rate after a 404. TCMB doesn't publish rates on weekends or
    /// public holidays; in practice the previous business day's rate
    /// is used. 7 days comfortably covers consecutive public-holiday +
    /// weekend combinations.
    private static let carryForwardLookbackDays = BillingDefaults.exchangeRateCarryForwardDays

    init(
        repository: ExchangeRateRepository? = nil,
        organizationId: String? = nil,
        userId: String? = nil,
        session: URLSession? = nil
    ) {
        self.repository = repository ?? ExchangeRateRepository()
        self.organizationId = organizationId ?? BuiltInOrganizationId.default
        self.userId = userId ?? BuiltInUserId.defaultOwner
        // TLS certificate pinning for TCMB is not active right now.
        // To add it, a URLSessionDelegate would validate the host's
        // public-key SHA-256 hash against pinned constants inside
        // `urlSession(_:didReceive:completionHandler:)`. Certificate
        // rotation isn't tracked, so for now we trust the system trust
        // store; backend MITM risk is low in production (TCMB doesn't
        // serve its HTTPS endpoints without a certificate), but a
        // future e-Invoice flow may require this.
        // Session configuration is now shared via ExchangeRateSyncSupport
        // so TCMB and Global services cannot drift on
        // timeout values.
        if let session {
            self.session = session
        } else {
            self.session = ExchangeRateSyncSupport.makeDefaultSession()
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
        // Y12: parallel sync deduplication. @MainActor already provides
        // thread isolation, but at await points a second sync call
        // could interleave and refetch the same date range.
        if let active = activeSyncTask {
            return try await active.value
        }
        let task = Task<TCMBExchangeRateSyncResult, Error> { [weak self] in
            // the previous version cleared activeSyncTask
            // from a detached Task inside `defer`, which could run before the
            // outer `task.value` resumed — a third caller could then start a
            // parallel sync. Cleanup is now performed in the @MainActor caller
            // below, after task.value resolves, with an identity check so we
            // never clobber a freshly-installed task.
            return try await self?.performSync(
                from: startDate,
                to: endDate,
                currencies: currencies
            ) ?? TCMBExchangeRateSyncResult(importedRateCount: 0, importedDayCount: 0, skippedDates: [])
        }
        activeSyncTask = task
        defer {
            // Task identity via Equatable; if the slot was overwritten by a
            // fresher caller while we awaited, leave it alone.
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
                // Try the requested day first; on 404, walk back up to N
                // days and "carry forward" the first published rate.
                // This simulates TCMB's weekend / holiday behaviour on
                // the application side.
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

            cursor = AppCalendar.istanbul.date(byAdding: .day, value: 1, to: cursor) ?? normalizedEnd.addingTimeInterval(1)
        }

        return TCMBExchangeRateSyncResult(
            importedRateCount: importedRateCount,
            importedDayCount: importedDayCount,
            skippedDates: skippedDates
        )
    }

    /// Tries the requested date first. On 404, walks back up to
    /// `carryForwardLookbackDays` days and returns the first published
    /// rate. If nothing was published in any of those days,
    /// `.ratesNotPublished` is thrown. The second tuple element is the
    /// source date when a rate was "carried forward".
    private func fetchRatesWithCarryForward(
        for date: Date,
        currencies: Set<String>
    ) async throws -> ([String: ExchangeRateQuote], carriedFromDate: String?) {
        do {
            let rates = try await fetchPublishedTRYRates(for: date, currencies: currencies)
            return (rates, nil)
        } catch TCMBExchangeRateSyncError.ratesNotPublished {
            // Weekend / holiday — find the nearest preceding business day.
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
        // explicitly reject any external entity / DTD
        // reference in the TCMB payload — defence in depth against an
        // upstream that gets compromised or trojaned with an XXE-style
        // DOCTYPE. TCMB never returns external entities legitimately.
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.shouldReportNamespacePrefixes = false
        xmlParser.shouldProcessNamespaces = false

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

            // On carry-forward, combine the source and TCMB's original
            // note so we can surface both to the user.
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

    /// On transient network errors, retries up to 3 times with
    /// 1s → 2s → 4s backoff. Persistent errors (404 etc. HTTP
    /// responses) aren't retried; the caller layer already skips them.
    /// 5xx HTTP responses are now included in the retry scope — TCMB
    /// upstream gateway transient errors usually resolve on their own
    /// within the backoff window.
    /// (DRY): retry/backoff implementation is now shared
    /// across TCMB and Global sync services via ExchangeRateSyncSupport
    /// so the two sources cannot drift on transient-error handling.
    private func fetchWithRetry(url: URL) async throws -> (Data, URLResponse) {
        try await ExchangeRateSyncSupport.fetchWithRetry(url: url, session: session)
    }

    private func makeURLs(for date: Date) -> [URL] {
        let monthFolder = Self.monthFolderFormatter.string(from: date)
        let fileName = Self.fileNameFormatter.string(from: date)
        var candidates = [
            "https://www.tcmb.gov.tr/kurlar/\(monthFolder)/\(fileName).xml"
        ]

        if AppCalendar.istanbul.isDate(date, inSameDayAs: Date()) {
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
        formatter.timeZone = AppCalendar.istanbul.timeZone
        formatter.dateFormat = "yyyyMM"
        return formatter
    }()

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = AppCalendar.istanbul.timeZone
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
