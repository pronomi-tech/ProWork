//
//  BillingPdfFormatters.swift
//  ProWork
//
//  Created by Pronomi.
//
//  BillingPdfDocument'in tarih / para / başlık / özet metin yardımcıları.
//  Saf veri dönüşümleri; CGContext / NSColor / NSFont kullanılmıyor.
//

import AppKit
import Foundation

@MainActor
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

    func displayMoney(_ money: Money) -> String {
        ProWorkFormatters.money(money)
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

    // MARK: - Satır metni

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

    // MARK: - Belge başlığı

    var companyDisplayName: String {
        clean(bundle.companyProfile?.tradeName) ??
        clean(bundle.companyProfile?.legalName) ??
        "ProWork"
    }

    var documentNumber: String {
        // Finalize edilmiş çalışmalar için kalıcı, yıl bazlı sayaçtan tüketilmiş
        // belge numarasını gösteriyoruz (örn. "HD-2026-000123").
        // Draft önizlemelerinde henüz numara atanmadığı için id'nin 12 hex
        // prefix'inden çakışmaya dayanıklı bir geçici numara üretiyoruz; bu
        // sadece PDF üstünde görüntülenir, DB'ye yazılmaz.
        if let number = bundle.run.documentNumber, !number.isEmpty {
            return number
        }
        let year = bundle.run.periodStart.prefix(4)
        return "HD-\(year)-\(bundle.run.id.replacingOccurrences(of: "-", with: "").prefix(12).uppercased())"
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

    // MARK: - KDV / Özet

    /// Tüm satırlar muafsa muafiyet etiketi gösterilir.
    var allLinesExempt: Bool {
        !bundle.lines.isEmpty && bundle.lines.allSatisfy { $0.isVatExempt }
    }

    var vatLabel: String {
        if allLinesExempt {
            return localized("pdf.summary.vatExempt", defaultValue: "KDV (Muaf)")
        }
        if let firstRate = bundle.lines.first?.vatRate, firstRate > 0 {
            let percentage = NSDecimalNumber(decimal: firstRate * 100).stringValue
            return String(format: localized("pdf.summary.vatRate", defaultValue: "KDV (%%%@)"), percentage)
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
        var balances: [String: Int] = [:]

        for line in bundle.lines {
            balances[line.currency, default: 0] += line.totalMinor
        }

        for payment in bundle.payments {
            balances[payment.currency, default: 0] -= payment.amountMinor
        }

        return balances.values.contains { $0 > 0 }
    }

    var currentBalanceMonies: [Money] {
        var balances: [String: Int] = [:]

        for line in bundle.lines {
            balances[line.currency, default: 0] += line.totalMinor
        }

        for payment in bundle.payments {
            balances[payment.currency, default: 0] -= payment.amountMinor
        }

        return balances
            .filter { $0.value != 0 }
            .map { Money(minorUnits: $0.value, currency: $0.key) }
    }

    // MARK: - Para birimi grupları

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
