//  ExchangeRateSyncSupport.swift
//  ProWork
//  Created by Pronomi.
//  TCMBExchangeRateSyncService and
//  GlobalExchangeRateSyncService each spelled out the same retry, session,
//  carry-forward, and active-task plumbing — ~80% common code in 1000+
//  lines. Pulling the truly identical pieces into a single support file
//  lets each per-source service focus on its unique URL/parsing/error
//  surface while ensuring the shared semantics (5xx retry, 7-day
//  carry-forward, dedup) cannot drift between sources.
//  What stays per-service:
//   • Error enum (TCMB vs Global) — caller-visible messaging
//   • URL construction (TCMB monthly XML vs Frankfurter JSON endpoint)
//   • Response parsing (XML vs JSON)
//   • Default currency list (currently both `Currency.allCodes`)
//  What lives here:
//   • URLSession configuration with shorter timeouts than the system
//     default (15s request / 30s resource).
//   • Exponential backoff retry policy (1s/2s/4s) honouring 5xx as
//     transient.
//   • `shouldRetry` shared classifier for URLError codes and the
//     internal TransientHTTPError marker.

import Foundation

/// Marker used by `fetchWithRetry` callers to signal that a 5xx upstream
/// response should be treated as transient — the retry loop inspects this
/// error type and reschedules instead of failing fast.
struct TransientHTTPError: Error {
    let statusCode: Int
}

enum ExchangeRateSyncSupport {
    /// URLSession tuned for exchange-rate fetching: 15s per request, 30s
    /// resource ceiling. The system default of 60s lets a single hung
    /// request stall a yearly sync for over an hour before retry kicks
    /// in. Sync services receive an injectable session (for tests) and
    /// fall back to this default.
    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    /// Exponential backoff steps: 1s, 2s, 4s. Three attempts cover the
    /// vast majority of upstream gateway hiccups while staying well under
    /// the surrounding UI's tolerance for "Fetch" button feedback.
    static let retryDelaysNanoseconds: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        4_000_000_000
    ]

    /// Returns `true` when the error is worth retrying (transient HTTP
    /// 5xx or a known-flaky URLError). Anything else is permanent and
    /// should bubble immediately.
    static func shouldRetry(error: Error) -> Bool {
        if error is TransientHTTPError {
            return true
        }
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

    /// Wraps `URLSession.data(from:)` with the shared retry policy:
    ///   • 5xx HTTP responses are converted into TransientHTTPError so
    ///     the retry classifier can pick them up.
    ///   • Transient errors back off according to
    ///     `retryDelaysNanoseconds` and re-check Task cancellation
    ///     between sleeps.
    ///   • An exhausted 5xx run is rethrown as URLError(.badServerResponse)
    ///     with the statusCode in userInfo so callers' status-code
    ///     handlers render a familiar message.
    static func fetchWithRetry(
        url: URL,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                let result = try await session.data(from: url)
                if let http = result.1 as? HTTPURLResponse,
                   (500...599).contains(http.statusCode) {
                    throw TransientHTTPError(statusCode: http.statusCode)
                }
                return result
            } catch {
                attempt += 1
                guard attempt <= retryDelaysNanoseconds.count,
                      shouldRetry(error: error) else {
                    if let transient = error as? TransientHTTPError {
                        throw URLError(.badServerResponse, userInfo: [
                            "statusCode": transient.statusCode
                        ])
                    }
                    throw error
                }
                try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt - 1])
                try Task.checkCancellation()
            }
        }
    }
}
