//  BillingPdfFormatters.swift
//  ProWork
//  Created by Pronomi.
//  Date / money / title / summary text helpers for BillingPdfDocument.
//  Pure data conversions; no CGContext / NSColor / NSFont used.

import AppKit
import Foundation

extension BillingPdfDocument {
    // MARK: - Tarih

    func displayDate(_ date: Date) -> String {
        displayDateFormatter.string(from: date)
    }

    func displayDateTimeWithSeconds(_ date: Date?) -> String {
        guard let date else { return "—" }
        return displayDateTimeWithSecondsFormatter.string(from: date)
    }

    func displayDay(_ raw: String?) -> String {
        guard let raw,
              let date = AppDateFormatters.sqliteDay.date(from: raw) else {
            return "—"
        }
        return displayDate(date)
    }

    func displayOptionalDay(_ raw: String?) -> String? {
        guard let raw,
              let date = AppDateFormatters.sqliteDay.date(from: raw) else {
            return nil
        }
        return displayDate(date)
    }

    // MARK: - Para

    /// Single-line amounts were being written with `ProWorkFormatters.money`
    /// (with a minus sign) and grouped amounts with
    /// `ProWorkFormatters.moneyAccounting` (parentheses).
    /// The different rendering of negatives was inconsistent for the
    /// reader — inside the PDF, both now route through the same
    /// `moneyAccounting` style (formal accounting). The single-line
    /// CSV/Excel flow uses its own formatter and is unaffected.
    func displayMoney(_ money: Money) -> String {
        ProWorkFormatters.moneyAccounting(money)
    }

    func groupedMoneyText(from monies: [Money]) -> String {
        guard !monies.isEmpty else {
            return displayMoney(Money.zero(bundle.run.currency))
        }

        let parts = groupedMoneyLines(from: monies)
        return parts.isEmpty ? displayMoney(Money.zero(bundle.run.currency)) : parts.joined(separator: "\n")
    }

    func groupedMoneyLines(from monies: [Money]) -> [String] {
        let grouped = Dictionary(grouping: monies, by: \.currency)
        return grouped.keys.sorted().compactMap { currency -> String? in
            guard let items = grouped[currency] else { return nil }
            let totalMinor = items.reduce(0) { $0 + $1.minorUnits }
            return ProWorkFormatters.moneyAccounting(Money(minorUnits: totalMinor, currency: currency))
        }
    }

    // MARK: - Line text

    func lineMetaText(for line: BillingReportLine) -> String {
        if line.isFixedFee {
            let fixedFee = line.fixedFeeMinor.map {
                displayMoney(Money(minorUnits: $0, currency: line.currency))
            } ?? displayMoney(line.amount)
            return String(format: localized("pdf.line.fixedFeeMeta", defaultValue: "Fiyatlandırma: Sabit Tutar | Tutar: %@"), fixedFee)
        }

        return String(
            format: localized("pdf.line.serviceMeta", defaultValue: "Hizmet: %@ | Zaman: %@"),
            line.serviceType.title,
            line.timeType.title
        )
    }

    func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Document title

    /// Fallback used to be hardcoded "ProWork" so whitelabel
    /// builds shipped the upstream brand name on every PDF whenever
    /// the company profile was unset. Pull the fallback through the
    /// localiser; default stays "ProWork" so existing TR installations
    /// see no change. Custom deployments override
    /// `export.companyDisplayName.fallback` once and every renderer
    /// follows.
    var companyDisplayName: String {
        clean(bundle.companyProfile?.tradeName) ??
        clean(bundle.companyProfile?.legalName) ??
        ProWorkLocalizer.shared.string(
            "export.companyDisplayName.fallback",
            defaultValue: "ProWork"
        )
    }

    var documentNumber: String {
        // For finalized runs we show the durable, year-based counter-consumed
        // document number (e.g. "HD-2026-000123").
        if let number = bundle.run.documentNumber, !number.isEmpty {
            return number
        }
        // Draft prefix used to be a hardcoded "HD-" string at
        // this site (and again in BillingRunLifecycleService.consume…).
        // Pull it through the localiser so multi-tenant / i18n
        // installations can override the visible identifier without
        // touching the formatter; default "HD-" preserves the existing
        // appearance on every TR installation. Both the formatter draft
        // path and finalize numbering MUST stay in sync — if one site
        // changes the prefix, the other has to follow (see
        // BillingRunLifecycleService.consumeNextBillingDocumentNumber).
        let year = bundle.run.periodStart.prefix(4)
        let prefix = ProWorkLocalizer.shared.string(
            "export.documentNumber.prefix",
            defaultValue: "HD"
        )
        let draftLabel = ProWorkLocalizer.shared.string(
            "export.documentNumber.draft",
            defaultValue: "TASLAK"
        )
        return "\(prefix)-\(year)-\(draftLabel)"
    }

    var periodLabel: String {
        "\(displayDay(bundle.run.periodStart)) - \(displayDay(bundle.run.periodEnd))"
    }

    var documentCurrenciesText: String {
        let codes = Set(
            bundle.lines.map(\.currency) +
            bundle.payments.map(\.currency)
        )
        .filter { !$0.isEmpty }
        .sorted()

        if codes.isEmpty {
            return bundle.run.currency
        }

        if codes.count == 1 {
            return codes[0]
        }

        return codes.joined(separator: "\n")
    }

    // MARK: - VAT / Summary

    /// If every line is exempt, the exemption label is shown.
    var allLinesExempt: Bool {
        !bundle.lines.isEmpty && bundle.lines.allSatisfy { $0.isVatExempt }
    }

    /// Percentage formatting goes through `NumberFormatter.percent`
    /// in the active locale instead of hand-rolling "%20". Some locales
    /// (fr_FR, sv_SE, …) expect a space before the percent sign, others
    /// place the sign on the left ("20%" vs "%20"); the formatter
    /// reproduces the conventional shape automatically. The fallback
    /// localised template still ships with the TR "KDV (%%%@)" shape
    /// so existing strings catalogs need no change.
    var vatLabel: String {
        if allLinesExempt {
            return localized("pdf.summary.vatExempt", defaultValue: "KDV (Muaf)")
        }
        if let firstRate = bundle.lines.first?.vatRate, firstRate > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .percent
            formatter.maximumFractionDigits = 2
            let percentage = formatter.string(from: NSDecimalNumber(decimal: firstRate))
                ?? "\(NSDecimalNumber(decimal: firstRate * 100).stringValue)%"
            return String(format: localized("pdf.summary.vatRate", defaultValue: "KDV (%@)"), percentage)
        }
        return localized("reports.summary.vat", defaultValue: "KDV")
    }

    var summaryItems: [(String, String, Bool)] {
        [
            (localized("reports.summary.subtotal", defaultValue: "Ara Toplam"), lineSubtotalText, false),
            (vatLabel, lineVatText, false),
            (localized("reports.summary.grandTotal", defaultValue: "Genel Toplam"), lineGrandTotalText, true),
            (localized("pdf.summary.collected", defaultValue: "Tahsil Edilen"), paymentTotalsText, false),
            (localized("pdf.summary.balance", defaultValue: "Kalan Bakiye"), balanceTotalsText, hasOutstandingBalance)
        ]
    }

    var lineTotalsRows: [(String, String)] {
        [
            (localized("pdf.lineTotals.subtotal", defaultValue: "Tutarlar Toplamı"), lineSubtotalText),
            (localized("pdf.lineTotals.vat", defaultValue: "KDV Tutarı"), lineVatText),
            (localized("reports.summary.grandTotal", defaultValue: "Genel Toplam"), lineGrandTotalText)
        ]
    }

    var lineSubtotalText: String {
        groupedMoneyText(from: bundle.lines.map { Money(minorUnits: $0.amountMinor, currency: $0.currency) })
    }

    var lineVatText: String {
        if allLinesExempt {
            return localized("vat.exemptBadge", defaultValue: "Muaf")
        }
        return groupedMoneyText(from: bundle.lines.map { Money(minorUnits: $0.vatMinor, currency: $0.currency) })
    }

    var lineGrandTotalText: String {
        groupedMoneyText(from: bundle.lines.map { Money(minorUnits: $0.totalMinor, currency: $0.currency) })
    }

    var paymentTotalsText: String {
        groupedMoneyText(from: bundle.payments.map { Money(minorUnits: $0.amountMinor, currency: $0.currency) })
    }

    var balanceTotalsText: String {
        groupedMoneyText(from: currentBalanceMonies)
    }

    var hasOutstandingBalance: Bool {
        balancesByCurrency().values.contains { $0 > 0 }
    }

    var currentBalanceMonies: [Money] {
        balancesByCurrency()
            .filter { $0.value != 0 }
            .map { Money(minorUnits: $0.value, currency: $0.key) }
    }

    // MARK: - Currency groups

    var groupedLineSections: [CurrencyIndexedSection] {
        makeCurrencySections(from: bundle.lines.map(\.currency))
    }

    var groupedPaymentSections: [CurrencyIndexedSection] {
        makeCurrencySections(from: bundle.payments.map(\.currency))
    }

    var lineOrdinalByIndex: [Int: Int] {
        makeOrdinalMap(from: groupedLineSections)
    }

    var paymentOrdinalByIndex: [Int: Int] {
        makeOrdinalMap(from: groupedPaymentSections)
    }

    var shouldShowLineCurrencyTitles: Bool {
        groupedLineSections.count > 1
    }

    var shouldShowPaymentCurrencyTitles: Bool {
        groupedPaymentSections.count > 1
    }

    var shouldShowPaymentTotals: Bool {
        bundle.payments.count > 1
    }

    private func makeCurrencySections(from currencies: [String]) -> [CurrencyIndexedSection] {
        let grouped = Dictionary(grouping: Array(currencies.enumerated()), by: \.element)

        return grouped.keys.sorted().map { currency in
            CurrencyIndexedSection(
                currency: currency,
                indices: grouped[currency]?.map(\.offset) ?? []
            )
        }
    }

    private func makeOrdinalMap(from sections: [CurrencyIndexedSection]) -> [Int: Int] {
        var result: [Int: Int] = [:]

        for section in sections {
            for (ordinal, index) in section.indices.enumerated() {
                result[index] = ordinal + 1
            }
        }

        return result
    }
}
