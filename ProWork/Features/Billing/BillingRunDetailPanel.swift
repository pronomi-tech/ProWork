//  BillingRunDetailPanel.swift
//  ProWork
//  Right-hand panel of BillingRunsView. Shows either an empty state
//  prompting the user to pick a run or, for a selected bundle, four
//  stacked cards: overview, export, lines, payments. Extracted from
//  BillingRunsView so the host view stays under the
//  500-LOC target and so the cards can be diff'd independently.
//  All mutation flows are passed in as closures; the panel itself
//  holds no state. The lookups it needs from the parent VM (master
//  currency for the converted total) come through `masterCurrencyForOrg`.

import SwiftUI
import os

private struct BillingSummaryMoneyMetric: Identifiable {
    let title: String
    let value: Money
    let prominent: Bool

    var id: String { title }
}

struct BillingRunDetailPanel: View {
    let bundle: BillingRunBundle?
    let isPreparingPdfPreview: Bool
    let masterCurrencyForOrg: (String) -> String
    let displayStoredDate: (String?) -> String
    let displayPeriod: (String, String) -> String

    let onEditDocumentInfo: (BillingRunBundle) -> Void
    let onRefreshDraft: () -> Void
    let onFinalize: () -> Void
    let onCancelRun: () -> Void
    let onPreviewPDF: (BillingRunBundle) -> Void
    let onExport: (BillingRunBundle, BillingExportFormat) -> Void
    let onAddPayment: (BillingRunBundle) -> Void
    let onEditPayment: (Payment) -> Void
    let onDeletePayment: (Payment) -> Void

    @EnvironmentObject private var settingsStore: AppSettingsStore

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        if let bundle {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overviewCard(bundle)
                    exportCard(bundle)
                    linesCard(bundle)
                    paymentsCard(bundle)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.richtext")
                    .proWorkFont(size: 34)
                    .foregroundStyle(.secondary)
                Text(localized("billing.detail.selectTitle", defaultValue: "Hizmet dökümü kaydı seçin"))
                    .proWorkTextStyle(.headline)
                Text(localized("billing.detail.selectMessage", defaultValue: "Soldan bir kayıt seçtiğinizde satırlar, export işlemleri ve ödeme takibi burada görünecek."))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Cards

    private func overviewCard(_ bundle: BillingRunBundle) -> some View {
        SettingsCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bundle.run.title ?? bundle.customer?.name ?? bundle.run.customerId)
                        .proWorkTextStyle(.title3)
                        .bold()
                    Text("\(localized("reports.filter.period", defaultValue: "Dönem")): \(displayPeriod(bundle.run.periodStart, bundle.run.periodEnd))")
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                    Text("\(localized("projects.form.customer", defaultValue: "Müşteri")): \(bundle.customer?.name ?? bundle.run.customerId)")
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        onEditDocumentInfo(bundle)
                    } label: {
                        ProWorkButtonLabel(title: localized("billing.action.documentInfo", defaultValue: "Belge Bilgileri"), systemImage: "pencil", minHeight: 30)
                    }
                    .buttonStyle(.bordered)

                    if bundle.run.status == .draft {
                        Button(action: onRefreshDraft) {
                            ProWorkButtonLabel(title: localized("billing.action.refreshDraft", defaultValue: "Taslağı Yenile"), systemImage: "arrow.clockwise", minHeight: 30)
                        }
                        .buttonStyle(.bordered)

                        Button(action: onFinalize) {
                            ProWorkButtonLabel(title: localized("billing.action.finalize", defaultValue: "Kesinleştir"), systemImage: "lock.fill", minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if bundle.run.status == .final {
                        Button(role: .destructive, action: onCancelRun) {
                            ProWorkButtonLabel(title: localized("common.cancelAction", defaultValue: "İptal"), systemImage: "xmark.circle", minHeight: 30)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Divider()

            HStack(spacing: 24) {
                metric(localized("projects.form.status", defaultValue: "Durum"), bundle.run.status.title)
                metric(localized("billing.metric.payment", defaultValue: "Ödeme"), bundle.run.paymentStatus.title)
                metric(localized("billing.metric.lines", defaultValue: "Satır"), "\(bundle.lines.count)")
                metric(localized("export.row.referenceNumber", defaultValue: "Referans No"), bundle.run.invoiceNumber ?? "—")
                metric(localized("pdf.document.dueDate", defaultValue: "Vade"), displayStoredDate(bundle.run.dueDate))
                Spacer()
            }

            Divider()

            // With 5 base metrics + up to 2 converted-currency
            // metrics the HStack would overflow horizontally on a
            // narrow detail panel (e.g. when the user collapses the
            // sidebar). Switch to a wrapping LazyVGrid sized by the
            // available width so the columns flow onto a second row
            // when needed; minimum 180pt per cell keeps long labels
            // ("Genel Toplam (EUR)") legible.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 24, alignment: .leading)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(summaryMoneyMetrics(for: bundle)) { item in
                    moneyMetric(item.title, item.value, prominent: item.prominent)
                }
            }
        }
    }

    private func exportCard(_ bundle: BillingRunBundle) -> some View {
        // (DRY): preview + format buttons all share the
        // same .bordered + minHeight 30 + ProWorkButtonLabel shape. Route
        // through BillingActionButton so a future tweak (e.g. controlSize)
        // is a one-line change.
        SettingsCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("billing.export.title", defaultValue: "Dışa Aktar"))
                        .proWorkTextStyle(.headline)
                    Text(localized("billing.export.subtitle", defaultValue: "PDF önizlemesi mevcut şablon ayarlarıyla üretilir."))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                BillingActionButton(
                    title: localized("billing.action.preview", defaultValue: "Önizle"),
                    systemImage: "eye",
                    isLoading: isPreparingPdfPreview
                ) {
                    onPreviewPDF(bundle)
                }
            }

            HStack(spacing: 10) {
                ForEach(BillingExportFormat.allCases) { format in
                    BillingActionButton(
                        title: format.title,
                        systemImage: Self.exportSystemImage(for: format)
                    ) {
                        onExport(bundle, format)
                    }
                }
            }
        }
    }

    private func linesCard(_ bundle: BillingRunBundle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("billing.lines.title", defaultValue: "Hizmet Satırları"))
                .proWorkTextStyle(.headline)

            if bundle.lines.isEmpty {
                SettingsCard {
                    SettingsEmptyState(
                        systemImage: "list.bullet.rectangle",
                        title: localized("billing.lines.empty.title", defaultValue: "Satır yok"),
                        message: localized("billing.lines.empty.message", defaultValue: "Bu dönem için hesaplanmış hizmet satırı bulunamadı.")
                    )
                }
            } else {
                ScrollView(.horizontal) {
                    SettingsTableContainer {
                        linesHeader
                        Divider()
                        ForEach(bundle.lines) { line in
                            linesRow(line)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var linesHeader: some View {
        HStack(spacing: 12) {
            Text(localized("reports.todo.table.todo", defaultValue: "Görev")).frame(width: 240, alignment: .leading)
            Text(localized("reports.todo.table.category", defaultValue: "Kategori")).frame(width: 120, alignment: .leading)
            Text(localized("priceLists.rows.form.serviceType", defaultValue: "Hizmet")).frame(width: 90, alignment: .leading)
            Text(localized("priceLists.rows.form.timeType", defaultValue: "Zaman")).frame(width: 100, alignment: .leading)
            Text(localized("reports.table.actual", defaultValue: "Gerçek")).frame(width: 70, alignment: .trailing)
            Text(localized("reports.table.billable", defaultValue: "Ücretli")).frame(width: 70, alignment: .trailing)
            Text(localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 110, alignment: .trailing)
            Text(localized("reports.summary.vat", defaultValue: "KDV")).frame(width: 110, alignment: .trailing)
            Text(localized("reports.summary.grandTotal", defaultValue: "Toplam")).frame(width: 110, alignment: .trailing)
            Text(localized("workSessions.column.source", defaultValue: "Kaynak")).frame(width: 80, alignment: .leading)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func linesRow(_ line: BillingReportLine) -> some View {
        HStack(spacing: 12) {
            Text(line.todoTitle)
                .proWorkTextStyle(.callout)
                .frame(width: 240, alignment: .leading)
                .lineLimit(1)
            Text(line.categoryName ?? "—")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(line.serviceType.title)
                .proWorkTextStyle(.caption)
                .frame(width: 90, alignment: .leading)
            Text(line.timeType.title)
                .proWorkTextStyle(.caption)
                .frame(width: 100, alignment: .leading)
            Text(String(format: localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), line.actualSeconds / 60))
                .proWorkTextStyle(.caption)
                .frame(width: 70, alignment: .trailing)
            Text(String(format: localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), line.billableMinutes))
                .proWorkTextStyle(.caption)
                .frame(width: 70, alignment: .trailing)
            Text(ProWorkFormatters.money(Money(minorUnits: line.amountMinor, currency: line.currency)))
                .proWorkTextStyle(.caption)
                .frame(width: 110, alignment: .trailing)
            Text(ProWorkFormatters.money(Money(minorUnits: line.vatMinor, currency: line.currency)))
                .proWorkTextStyle(.caption)
                .frame(width: 110, alignment: .trailing)
            Text(ProWorkFormatters.money(Money(minorUnits: line.totalMinor, currency: line.currency)))
                .proWorkTextStyle(.caption, weight: .medium)
                .frame(width: 110, alignment: .trailing)
            Text(line.isManual
                 ? localized("workSessions.source.manual", defaultValue: "Manuel")
                 : localized("workSessions.source.automatic", defaultValue: "Otomatik"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(line.isManual ? .orange : .secondary)
                .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func paymentsCard(_ bundle: BillingRunBundle) -> some View {
        let canManagePayments = bundle.run.status == .final
        let paymentActionHelp = canManagePayments
            ? localized("billing.action.addPayment", defaultValue: "Ödeme Ekle")
            : localized("billing.help.paymentsRequireFinalizedRun", defaultValue: "Ödeme eklemek için hizmet dökümü önce kesinleştirilmelidir.")

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("billing.payments.title", defaultValue: "Ödeme Takibi"))
                    .proWorkTextStyle(.headline)
                Spacer()
                Button {
                    onAddPayment(bundle)
                } label: {
                    ProWorkButtonLabel(title: localized("billing.action.addPayment", defaultValue: "Ödeme Ekle"), systemImage: "plus", minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(!canManagePayments)
                .help(paymentActionHelp)
            }

            if bundle.payments.isEmpty {
                SettingsCard {
                    SettingsEmptyState(
                        systemImage: "creditcard",
                        title: localized("billing.payments.empty.title", defaultValue: "Henüz ödeme kaydı yok"),
                        message: localized("billing.payments.empty.message", defaultValue: "Tahsilatları buraya işleyerek bakiye ve ödeme durumunu takip edin.")
                    )
                }
            } else {
                SettingsTableContainer {
                    paymentsHeader
                    Divider()
                    ForEach(bundle.payments) { payment in
                        paymentsRow(payment, canManagePayments: canManagePayments, help: paymentActionHelp)
                        Divider()
                    }
                }
            }
        }
    }

    private var paymentsHeader: some View {
        HStack(spacing: 12) {
            Text(localized("exchangeRates.column.date", defaultValue: "Tarih")).frame(width: 150, alignment: .leading)
            Text(localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 140, alignment: .trailing)
            Text(localized("payment.column.method", defaultValue: "Yöntem")).frame(width: 160, alignment: .leading)
            Text(localized("payment.column.reference", defaultValue: "Referans")).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 90)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func paymentsRow(_ payment: Payment, canManagePayments: Bool, help: String) -> some View {
        HStack(spacing: 12) {
            Text(settingsStore.formatDate(payment.paidAt))
                .proWorkTextStyle(.callout)
                .frame(width: 150, alignment: .leading)
            Text(ProWorkFormatters.money(payment.amount))
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(width: 140, alignment: .trailing)
            Text(payment.method.title)
                .proWorkTextStyle(.callout)
                .frame(width: 160, alignment: .leading)
            Text(payment.reference ?? "—")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    onEditPayment(payment)
                } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canManagePayments)
                .help(canManagePayments ? localized("customers.action.edit", defaultValue: "Düzenle") : help)

                Button(role: .destructive) {
                    onDeletePayment(payment)
                } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canManagePayments)
                .help(canManagePayments ? localized("common.delete", defaultValue: "Sil") : help)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Metric helpers

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .proWorkTextStyle(.callout, weight: .medium)
                .lineLimit(1)
        }
    }

    private func moneyMetric(_ title: String, _ value: Money, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
            Text(ProWorkFormatters.money(value))
                .proWorkTextStyle(prominent ? .headline : .callout, weight: prominent ? .bold : .medium)
                .foregroundStyle(prominent ? Color.accentColor : .primary)
                .lineLimit(1)
        }
    }

    private func summaryMoneyMetrics(for bundle: BillingRunBundle) -> [BillingSummaryMoneyMetric] {
        var items: [BillingSummaryMoneyMetric] = [
            .init(title: localized("reports.summary.subtotal", defaultValue: "Ara Toplam"), value: bundle.run.subtotal, prominent: false),
            .init(title: localized("reports.summary.vat", defaultValue: "KDV"), value: bundle.run.vat, prominent: false),
            .init(title: localized("reports.summary.grandTotal", defaultValue: "Genel Toplam"), value: bundle.run.total, prominent: true),
            .init(title: localized("pdf.summary.collected", defaultValue: "Tahsil Edilen"), value: bundle.run.paid, prominent: false),
            .init(title: localized("pdf.summary.balance", defaultValue: "Bakiye"), value: bundle.run.balance, prominent: bundle.run.balanceMinor > 0)
        ]

        // Allocate the CurrencyConverter once per metrics
        // build instead of twice (once per
        // `convertedCompanyCurrencyMoney` call). Each allocation set
        // up its own NotificationCenter observer and 1024-entry cache
        // that lasted only for the converter's stack frame — pure
        // waste on every panel render.
        if let converter = makeConverterIfNeeded(for: bundle) {
            let dateString = conversionReferenceDate(for: bundle)
            if let convertedTotal = convert(value: bundle.run.total, using: converter, on: dateString, runId: bundle.run.id) {
                items.append(
                    .init(
                        title: String(format: localized("pdf.summary.grandTotalCurrency", defaultValue: "Genel Toplam (%@)"), convertedTotal.currency),
                        value: convertedTotal,
                        prominent: true
                    )
                )
            }
            if let convertedBalance = convert(value: bundle.run.balance, using: converter, on: dateString, runId: bundle.run.id) {
                items.append(
                    .init(
                        title: String(format: localized("pdf.summary.balanceCurrency", defaultValue: "Bakiye (%@)"), convertedBalance.currency),
                        value: convertedBalance,
                        prominent: bundle.run.balanceMinor > 0
                    )
                )
            }
        }

        return items
    }

    private func makeConverterIfNeeded(for bundle: BillingRunBundle) -> CurrencyConverter? {
        let targetCurrency = masterCurrencyForOrg(bundle.run.organizationId)
        guard bundle.run.currency.uppercased() != targetCurrency else { return nil }
        return CurrencyConverter(
            organizationId: bundle.run.organizationId,
            masterCurrency: targetCurrency,
            preferredAutoSource: settingsStore.settings.preferredExchangeRateSource
        )
    }

    private func convert(value: Money, using converter: CurrencyConverter, on dateString: String, runId: String) -> Money? {
        guard !value.currency.isEmpty else { return nil }
        do {
            return try converter.convertToMaster(value, on: dateString)
        } catch CurrencyConversionError.noRateAvailable {
            return nil
        } catch {
            ProWorkLog.billing.error(
                "BillingRunDetailPanel.summaryMoneyMetrics convert failed for run \(runId, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    private func convertedCompanyCurrencyMoney(for value: Money, in bundle: BillingRunBundle) -> Money? {
        let targetCurrency = masterCurrencyForOrg(bundle.run.organizationId)
        guard value.currency.uppercased() != targetCurrency else {
            return nil
        }

        let converter = CurrencyConverter(
            organizationId: bundle.run.organizationId,
            masterCurrency: targetCurrency,
            preferredAutoSource: settingsStore.settings.preferredExchangeRateSource
        )

        // Distinguish "no rate available" (returns nil, the
        // panel just hides the secondary-currency line) from a real
        // DB/IO error (logs so support can investigate). Previously
        // `try?` collapsed both into the same nil and the user never
        // saw a signal that the converter was failing for a different
        // reason than missing rates.
        do {
            return try converter.convertToMaster(value, on: conversionReferenceDate(for: bundle))
        } catch CurrencyConversionError.noRateAvailable {
            return nil
        } catch {
            ProWorkLog.billing.error(
                "BillingRunDetailPanel.convertedCompanyCurrencyMoney failed for run \(bundle.run.id, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    private func conversionReferenceDate(for bundle: BillingRunBundle) -> String {
        if let finalizedAt = bundle.run.finalizedAt {
            // K16: cached POSIX yyyy-MM-dd formatter — instead of allocating per bundle row.
            // tekrar allocate edilmiyor.
            return ProWorkFormatters
                .cachedDateFormatter(localeIdentifier: "en_US_POSIX", dateFormat: "yyyy-MM-dd")
                .string(from: finalizedAt)
        }

        return bundle.run.periodEnd
    }

    private static func exportSystemImage(for format: BillingExportFormat) -> String {
        switch format {
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .excel: return "tablecells.badge.ellipsis"
        case .json: return "curlybraces"
        }
    }
}
