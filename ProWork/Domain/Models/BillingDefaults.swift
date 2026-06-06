//  BillingDefaults.swift
//  ProWork
//  Created by Pronomi.
//  Central home for the small handful of magic numbers and fallback strings
//  that previously lived inline across the billing / FX pipeline (code
//  review O19). Tuning these used to require hunting through repositories
//  and services; they now live in one place.

import Foundation

/// `nonisolated`: every value is an immutable `static let` constant —
/// must be referenceable from any actor context (e.g. background
/// `Task.detached` veya non-MainActor service).
nonisolated enum BillingDefaults {
    /// Default invoice payment window (days) when neither the customer nor
    /// the company profile specifies one. 30 days is the Turkish commercial
    /// norm for B2B invoicing.
    static let paymentTermsDays: Int = 30

    /// How far back the FX sync services look when carrying a missing
    /// day's rate forward (e.g. TCMB weekends, missed scheduler days).
    /// Increasing this also widens the cache footprint, so keep it tight.
    static let exchangeRateCarryForwardDays: Int = 7

    /// How many years into the future Diyanet Islamic-holiday seed runs
    /// extend by default. The seed is idempotent, so increasing this only
    /// inserts new rows; existing rows are left untouched.
    static let islamicHolidayYearsAhead: Int = 5

    /// Application-wide fallback currency. Used by `CurrencyConverter`,
    /// `PriceListResolver`, and exchange rate sync services when the
    /// organisation's `masterCurrency` is blank or unknown.
    static let fallbackCurrency: String = "TRY"
}
