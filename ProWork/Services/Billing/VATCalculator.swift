//  VATCalculator.swift
//  ProWork
//  Created by Pronomi.
//  Computes line-level VAT against named VAT definitions (VatRate).
//  Resolution order (most specific wins):
//    1. project.vatRateId       — definition assigned to the project
//    2. customer.vatRateId      — definition assigned to the customer
//    3. category.vatRateId      — definition assigned to the category
//    4. default                 — the `isDefault = true` definition (0 if missing)
//  When an `isExempt = true` definition applies the rate is treated as 0;
//  the caller uses `appliedExempt` for snapshotting (shown as "Exempt"
//  in the PDF/report).

import Foundation

enum VatRateOrigin: String, Hashable {
    case project
    case customer
    case category
    case `default`
    case none
}

struct VATCalculationResult: Hashable {
    /// Applied rate (e.g. 0.20); 0 when exempt.
    let rate: Decimal
    /// VAT amount (minor unit).
    let vatMinor: Int
    /// Total (subtotal + vat) (minor unit).
    let totalMinor: Int
    /// Whether an exempt definition was applied.
    let isExempt: Bool
    /// Which level it came from (debug/audit).
    let origin: VatRateOrigin
}

/// VATCalculator carries no identity, no observation
/// surface, and is constructed fresh per computation pass. Modelling it
/// as a struct removes pointless heap allocation and signals immutability
/// to callers.
struct VATCalculator {
    private let ratesById: [String: VatRate]
    private let defaultRate: VatRate?

    /// The caller must have loaded every active VAT definition for the organization.
    /// only one VAT rate is expected to carry
    /// `isDefault = true` at a time. If two slip through (e.g. a buggy
    /// migration or a stale UI write that didn't clear the previous
    /// default), `first(where:)` silently picks one and the run uses
    /// whichever the DB happened to return first. Assert the invariant
    /// in debug; in release the picked rate is still deterministic for
    /// the lifetime of this calculator instance.
    init(rates: [VatRate]) {
        let active = rates.filter { $0.isActive && $0.deletedAt == nil }
        self.ratesById = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let defaults = active.filter(\.isDefault)
        assert(defaults.count <= 1, "VATCalculator: \(defaults.count) active default VAT rates; expected at most one. Investigate VatRateRepository state.")
        self.defaultRate = defaults.first
    }

    /// Returns the VAT rate to apply and the result for the given
    /// customer/project/category.
    /// (VAT effectiveFrom): `dateString` is now actively used. If the
    /// resolved rate's `effectiveFrom` is after the given period date,
    /// that rate is not applied to the past period; the result returns
    /// zero VAT with `.none` origin. This prevents transitions like
    /// TR 18→20% from applying the wrong (future) rate when a
    /// back-dated invoice is finalised.
    /// `dateString` is now mandatory. The previous default of
    /// `""` made the effective-from check silently apply the current
    /// rate to historical periods (TR 18→20% migration: a backdated
    /// finalize would have used 20% for a pre-effective-date line).
    /// Callers MUST pass the period anchor (`run.periodStart`,
    /// finalize date, etc.) in YYYY-MM-DD form.
    func calculate(
        subtotalMinor: Int,
        customerVatRateId: String?,
        projectVatRateId: String?,
        categoryVatRateId: String?,
        dateString: String
    ) -> VATCalculationResult {
        let resolved = resolve(
            customerVatRateId: customerVatRateId,
            projectVatRateId: projectVatRateId,
            categoryVatRateId: categoryVatRateId,
            dateString: dateString
        )

        guard let rate = resolved.rate else {
            return VATCalculationResult(
                rate: 0,
                vatMinor: 0,
                totalMinor: subtotalMinor,
                isExempt: false,
                origin: .none
            )
        }

        let vatMinor = rate.vatMinor(forSubtotal: subtotalMinor)
        return VATCalculationResult(
            rate: rate.isExempt ? 0 : rate.rate,
            vatMinor: vatMinor,
            totalMinor: subtotalMinor + vatMinor,
            isExempt: rate.isExempt,
            origin: resolved.origin
        )
    }

    private struct Resolved {
        let rate: VatRate?
        let origin: VatRateOrigin
    }

    private func resolve(
        customerVatRateId: String?,
        projectVatRateId: String?,
        categoryVatRateId: String?,
        dateString: String
    ) -> Resolved {
        if let id = projectVatRateId, let rate = ratesById[id], isEffective(rate, on: dateString) {
            return Resolved(rate: rate, origin: .project)
        }
        if let id = customerVatRateId, let rate = ratesById[id], isEffective(rate, on: dateString) {
            return Resolved(rate: rate, origin: .customer)
        }
        if let id = categoryVatRateId, let rate = ratesById[id], isEffective(rate, on: dateString) {
            return Resolved(rate: rate, origin: .category)
        }
        if let rate = defaultRate, isEffective(rate, on: dateString) {
            return Resolved(rate: rate, origin: .default)
        }
        return Resolved(rate: nil, origin: .none)
    }

    /// If `effectiveFrom` is absent or empty, the rate is always valid.
    /// When `dateString` is empty (the caller doesn't know the date) we
    /// can't do a back-dated check; we keep the old behaviour.
    private func isEffective(_ rate: VatRate, on dateString: String) -> Bool {
        guard let effectiveFrom = rate.effectiveFrom?.trimmingCharacters(in: .whitespacesAndNewlines),
              !effectiveFrom.isEmpty,
              !dateString.isEmpty else {
            return true
        }
        // YYYY-MM-DD strings can be compared lexicographically (ISO 8601).
        return dateString >= effectiveFrom
    }
}
