//
//  BillingRunsView.swift
//  ProWork
//
//   Created by Pronomi.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct BillingSummaryMoneyMetric: Identifiable {
    let title: String
    let value: Money
    let prominent: Bool

    var id: String { title }
}

struct BillingRunsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = BillingRunsViewModel()

    @State private var selectedRunId: String?
    @State private var isShowingCreateSheet = false
    @State private var paymentSheetContext: PaymentSheetContext?
    @State private var editingPayment: Payment?
    @State private var documentInfoEditContext: DocumentInfoEditContext?
    @State private var confirmation: ProWorkConfirmation?
    @State private var previewDocument: PdfPreviewDocument?
    @State private var isPreparingPdfPreview = false

    private var lifecycleService: BillingRunLifecycleService { viewModel.lifecycleService }
    private var exportService: BillingRunExportService { viewModel.exportService }

    // ViewModel'a proxy — view body 80+ noktada bu adları kullanıyor.
    // ViewModel @StateObject olduğu için yeniden render'lar @Published üzerinden
    // tetiklenir; bu computed proxy'ler sadece okuma kolaylığı sağlar.
    private var runs: [BillingReportRun] { viewModel.runs }
    private var customers: [Customer] { viewModel.customers }
    private var customerCurrencies: [String: String] { viewModel.customerCurrencies }
    private var selectedBundle: BillingRunBundle? {
        get { viewModel.selectedBundle }
        nonmutating set { viewModel.selectedBundle = newValue }
    }
    private var errorMessage: String? {
        get { viewModel.errorMessage }
        nonmutating set { viewModel.errorMessage = newValue }
    }
    private var savedNotice: String? {
        get { viewModel.savedNotice }
        nonmutating set { viewModel.savedNotice = newValue }
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                runsSidebar
                Divider()
                detailPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .proWorkToastNotifications(
            errorMessage: errorMessage,
            successMessage: savedNotice
        )
        .onAppear(perform: load)
        .sheet(isPresented: $isShowingCreateSheet) {
            BillingRunCreateSheet(
                customers: customers,
                customerCurrencies: customerCurrencies
            ) { customerId, startDate, endDate, title, selectedLineKeys in
                try createDraft(
                    customerId: customerId,
                    startDate: startDate,
                    endDate: endDate,
                    title: title,
                    selectedLineKeys: selectedLineKeys
                )
            }
            .environmentObject(settingsStore)
        }
        .sheet(item: $paymentSheetContext) { context in
            PaymentFormView(mode: context.mode) { paidAt, amountMinor, currency, method, reference, note in
                if let payment = editingPayment {
                    updatePayment(
                        payment: payment,
                        paidAt: paidAt,
                        amountMinor: amountMinor,
                        currency: currency,
                        method: method,
                        reference: reference,
                        note: note
                    )
                } else if let selectedRunId {
                    addPayment(
                        runId: selectedRunId,
                        paidAt: paidAt,
                        amountMinor: amountMinor,
                        currency: currency,
                        method: method,
                        reference: reference,
                        note: note
                    )
                }
            }
            .environmentObject(settingsStore)
        }
        .sheet(item: $previewDocument) { document in
            BillingPdfPreviewSheet(
                title: document.title,
                data: document.data
            ) {
                saveExportData(
                    document.data,
                    format: .pdf,
                    defaultFilename: document.defaultFilename
                )
            }
            .environmentObject(settingsStore)
        }
        .sheet(item: $documentInfoEditContext) { context in
            BillingRunDocumentInfoSheet(
                referenceNumber: context.referenceNumber,
                dueDate: context.dueDate
            ) { referenceNumber, dueDate in
                saveDocumentInfo(runId: context.runId, referenceNumber: referenceNumber, dueDate: dueDate)
            }
            .environmentObject(settingsStore)
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("billing.title", defaultValue: "Hizmet Dökümleri"))
                    .proWorkTextStyle(.largeTitle)
                Text(localized("billing.subtitle", defaultValue: "Dönem bazlı hizmet dökümü kayıtlarını yönetin, kesinleştirin, dışa aktarın ve ödeme takibi yapın."))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedBundle?.run.status == .draft {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    ProWorkButtonLabel(title: localized("billing.action.newRun", defaultValue: "Yeni Döküm"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    ProWorkButtonLabel(title: localized("billing.action.newRun", defaultValue: "Yeni Döküm"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
    }

    private var runsSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(localized("billing.sidebar.runs", defaultValue: "Kayıtlar")) (\(runs.count))")
                    .proWorkTextStyle(.headline)
                Spacer()

                if selectedBundle?.run.status == .draft {
                    Button(role: .destructive) {
                        askDeleteSelectedRun()
                    } label: {
                        Image(systemName: "trash")
                            .proWorkFont(size: 13)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .help(localized("billing.action.deleteDraftHelp", defaultValue: "Seçili taslağı sil"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if runs.isEmpty {
                VStack(spacing: 0) {
                    SettingsEmptyState(
                        systemImage: "doc.text.magnifyingglass",
                        title: localized("billing.empty.title", defaultValue: "Henüz hizmet dökümü yok"),
                        message: localized("billing.empty.message", defaultValue: "Sağ üstten yeni taslak oluşturup hesaplamayı başlatın.")
                    )
                    .padding(16)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(runs) { run in
                            sidebarRow(run)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func sidebarRow(_ run: BillingReportRun) -> some View {
        let isSelected = selectedRunId == run.id
        let customerName = customers.first(where: { $0.id == run.customerId })?.name ?? run.customerId

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.title ?? customerName)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .lineLimit(2)
                Spacer(minLength: 8)
                statusChip(run.status)
            }

            Text(customerName)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Text(displayPeriod(start: run.periodStart, end: run.periodEnd))
                Spacer()
                Text(ProWorkFormatters.money(run.total))
            }
            .proWorkTextStyle(.caption)
            .foregroundStyle(.secondary)

            HStack {
                paymentStatusChip(run.paymentStatus)
                Spacer()
                if let invoiceNumber = run.invoiceNumber {
                    Text(invoiceNumber)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectRun(run.id)
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedBundle {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overviewCard(selectedBundle)
                    exportCard(selectedBundle)
                    linesCard(selectedBundle)
                    paymentsCard(selectedBundle)
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

    private func overviewCard(_ bundle: BillingRunBundle) -> some View {
        SettingsCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bundle.run.title ?? bundle.customer?.name ?? bundle.run.customerId)
                        .proWorkTextStyle(.title3)
                        .bold()
                    Text("\(localized("reports.filter.period", defaultValue: "Dönem")): \(displayPeriod(start: bundle.run.periodStart, end: bundle.run.periodEnd))")
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                    Text("\(localized("projects.form.customer", defaultValue: "Müşteri")): \(bundle.customer?.name ?? bundle.run.customerId)")
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        openDocumentInfoEditor(bundle)
                    } label: {
                        ProWorkButtonLabel(title: localized("billing.action.documentInfo", defaultValue: "Belge Bilgileri"), systemImage: "pencil", minHeight: 30)
                    }
                    .buttonStyle(.bordered)

                    if bundle.run.status == .draft {
                        Button {
                            refreshSelectedRun()
                        } label: {
                            ProWorkButtonLabel(title: localized("billing.action.refreshDraft", defaultValue: "Taslağı Yenile"), systemImage: "arrow.clockwise", minHeight: 30)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            finalizeSelectedRun()
                        } label: {
                            ProWorkButtonLabel(title: localized("billing.action.finalize", defaultValue: "Kesinleştir"), systemImage: "lock.fill", minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if bundle.run.status == .final {
                        Button(role: .destructive) {
                            askCancelSelectedRun()
                        } label: {
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

            HStack(spacing: 24) {
                ForEach(summaryMoneyMetrics(for: bundle)) { item in
                    moneyMetric(item.title, item.value, prominent: item.prominent)
                }
                Spacer()
            }
        }
    }

    private func exportCard(_ bundle: BillingRunBundle) -> some View {
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

                Button {
                    previewPDF(bundle)
                } label: {
                    if isPreparingPdfPreview {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 30, height: 30)
                    } else {
                        ProWorkButtonLabel(title: localized("billing.action.preview", defaultValue: "Önizle"), systemImage: "eye", minHeight: 30)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isPreparingPdfPreview)
            }

            HStack(spacing: 10) {
                ForEach(BillingExportFormat.allCases) { format in
                    Button {
                        export(bundle, format: format)
                    } label: {
                        ProWorkButtonLabel(
                            title: format.title,
                            systemImage: exportSystemImage(for: format),
                            minHeight: 30
                        )
                    }
                    .buttonStyle(.bordered)
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

                        Divider()

                        ForEach(bundle.lines) { line in
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

                            Divider()
                        }
                    }
                }
            }
        }
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
                    editingPayment = nil
                    paymentSheetContext = PaymentSheetContext(mode: .create(currency: bundle.run.currency))
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
                    HStack(spacing: 12) {
                        Text(localized("exchangeRates.column.date", defaultValue: "Tarih")).frame(width: 150, alignment: .leading)
                        Text(localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 140, alignment: .trailing)
                        Text(localized("payment.column.method", defaultValue: "Yöntem")).frame(width: 160, alignment: .leading)
                        Text(localized("payment.column.reference", defaultValue: "Referans")).frame(maxWidth: .infinity, alignment: .leading)
                        Text("").frame(width: 90)
                    }
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.35))

                    Divider()

                    ForEach(bundle.payments) { payment in
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
                                    editingPayment = payment
                                    paymentSheetContext = PaymentSheetContext(mode: .edit(payment))
                                } label: {
                                    Image(systemName: "pencil").proWorkFont(size: 12)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!canManagePayments)
                                .help(canManagePayments ? localized("customers.action.edit", defaultValue: "Düzenle") : paymentActionHelp)

                                Button(role: .destructive) {
                                    askDeletePayment(payment)
                                } label: {
                                    Image(systemName: "trash").proWorkFont(size: 12)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!canManagePayments)
                                .help(canManagePayments ? localized("common.delete", defaultValue: "Sil") : paymentActionHelp)
                            }
                            .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider()
                    }
                }
            }
        }
    }

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

        if let convertedTotal = convertedCompanyCurrencyMoney(for: bundle.run.total, in: bundle) {
            items.append(
                .init(
                    title: String(format: localized("pdf.summary.grandTotalCurrency", defaultValue: "Genel Toplam (%@)"), convertedTotal.currency),
                    value: convertedTotal,
                    prominent: true
                )
            )
        }

        if let convertedBalance = convertedCompanyCurrencyMoney(for: bundle.run.balance, in: bundle) {
            items.append(
                .init(
                    title: String(format: localized("pdf.summary.balanceCurrency", defaultValue: "Bakiye (%@)"), convertedBalance.currency),
                    value: convertedBalance,
                    prominent: bundle.run.balanceMinor > 0
                )
            )
        }

        return items
    }

    private func convertedCompanyCurrencyMoney(for value: Money, in bundle: BillingRunBundle) -> Money? {
        let targetCurrency = viewModel.masterCurrency(for: bundle.run.organizationId)
        guard value.currency.uppercased() != targetCurrency else {
            return nil
        }

        let converter = CurrencyConverter(
            organizationId: bundle.run.organizationId,
            masterCurrency: targetCurrency
        )

        guard let converted = try? converter.convertToMaster(value, on: conversionReferenceDate(for: bundle)) else {
            return nil
        }

        return converted
    }

    private func conversionReferenceDate(for bundle: BillingRunBundle) -> String {
        if let finalizedAt = bundle.run.finalizedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: finalizedAt)
        }

        return bundle.run.periodEnd
    }

    private func statusChip(_ status: BillingRunStatus) -> some View {
        Text(status.title)
            .proWorkTextStyle(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.14))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func paymentStatusChip(_ status: PaymentStatus) -> some View {
        Text(status.title)
            .proWorkTextStyle(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(paymentStatusColor(status).opacity(0.14))
            .foregroundStyle(paymentStatusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: BillingRunStatus) -> Color {
        switch status {
        case .draft: return .orange
        case .final: return .green
        case .cancelled: return .red
        }
    }

    private func paymentStatusColor(_ status: PaymentStatus) -> Color {
        switch status {
        case .unpaid: return .secondary
        case .partial: return .orange
        case .paid: return .green
        case .overdue: return .red
        }
    }

    private func exportSystemImage(for format: BillingExportFormat) -> String {
        switch format {
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .excel: return "tablecells.badge.ellipsis"
        case .json: return "curlybraces"
        }
    }

    private func load() {
        viewModel.load(reselect: selectedRunId ?? viewModel.runs.first?.id)
        if let bundleId = viewModel.selectedBundle?.run.id {
            selectedRunId = bundleId
        } else if !viewModel.runs.contains(where: { $0.id == selectedRunId }) {
            selectedRunId = viewModel.runs.first?.id
            if let newId = selectedRunId {
                viewModel.selectRun(id: newId)
            }
        }
    }

    private func selectRun(_ runId: String) {
        selectedRunId = runId
        do {
            setSelectedBundle(try lifecycleService.loadBundle(runId: runId))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createDraft(
        customerId: String,
        startDate: Date,
        endDate: Date,
        title: String?,
        selectedLineKeys: [String]
    ) throws {
        let bundles = try lifecycleService.createDrafts(
            customerId: customerId,
            periodStart: startDate,
            periodEnd: endDate,
            title: title,
            selectedLineKeys: selectedLineKeys
        )

        guard let firstBundle = bundles.first else {
            throw BillingRunLifecycleError.noBillableLinesForPeriod
        }

        selectedRunId = firstBundle.run.id
        setSelectedBundle(firstBundle)
        setSavedNotice(draftCreationNotice(for: bundles))
        load()
    }

    private func draftCreationNotice(for bundles: [BillingRunBundle]) -> String {
        guard bundles.count > 1 else {
            return localized("billing.notice.draftCreated", defaultValue: "Taslak oluşturuldu.")
        }

        let currencies = bundles.map(\.run.currency).sorted().joined(separator: ", ")
        return String(
            format: localized("billing.notice.draftsCreated", defaultValue: "%d taslak oluşturuldu: %@."),
            bundles.count,
            currencies
        )
    }

    private func refreshSelectedRun() {
        guard let selectedRunId else { return }
        do {
            setSelectedBundle(try lifecycleService.refreshRun(runId: selectedRunId))
            setSavedNotice(localized("billing.notice.draftRefreshed", defaultValue: "Taslak güncellendi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finalizeSelectedRun() {
        guard let selectedRunId else { return }
        do {
            setSelectedBundle(try lifecycleService.finalizeRun(runId: selectedRunId))
            setSavedNotice(localized("billing.notice.finalized", defaultValue: "Hizmet dökümü kesinleştirildi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askCancelSelectedRun() {
        guard let selectedBundle else { return }
        confirmation = ProWorkConfirmation(
            title: localized("billing.confirm.cancelRun.title", defaultValue: "Kayıt iptal edilsin mi?"),
            message: localized("billing.confirm.cancelRun.message", defaultValue: "Kesinleşmiş hizmet dökümü kaydı iptal statüsüne alınacak."),
            confirmTitle: localized("billing.confirm.cancelRun.confirm", defaultValue: "İptal Et"),
            cancelTitle: localized("common.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            cancelSelectedRun(bundle: selectedBundle)
        }
    }

    private func askDeleteSelectedRun() {
        guard let selectedBundle else { return }
        confirmation = ProWorkConfirmation(
            title: localized("billing.confirm.deleteDraft.title", defaultValue: "Taslak silinsin mi?"),
            message: localized("billing.confirm.deleteDraft.message", defaultValue: "Kesinleşmemiş hizmet dökümü kaydı kalıcı olarak silinecek."),
            confirmTitle: localized("common.delete", defaultValue: "Sil"),
            cancelTitle: localized("common.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            deleteSelectedRun(bundle: selectedBundle)
        }
    }

    private func cancelSelectedRun(bundle: BillingRunBundle) {
        do {
            setSelectedBundle(try lifecycleService.cancelRun(runId: bundle.run.id))
            setSavedNotice(localized("billing.notice.cancelled", defaultValue: "Kayıt iptal edildi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedRun(bundle: BillingRunBundle) {
        do {
            try lifecycleService.deleteRun(runId: bundle.run.id)
            if selectedRunId == bundle.run.id {
                selectedRunId = nil
                setSelectedBundle(nil)
            }
            setSavedNotice(localized("billing.notice.draftDeleted", defaultValue: "Taslak kayıt silindi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPayment(
        runId: String,
        paidAt: Date,
        amountMinor: Int,
        currency: String,
        method: PaymentMethod,
        reference: String?,
        note: String?
    ) {
        do {
            setSelectedBundle(try lifecycleService.addPayment(
                runId: runId,
                paidAt: paidAt,
                amountMinor: amountMinor,
                currency: currency,
                method: method,
                reference: reference,
                note: note
            ))
            setSavedNotice(localized("billing.notice.paymentAdded", defaultValue: "Ödeme kaydı eklendi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updatePayment(
        payment: Payment,
        paidAt: Date,
        amountMinor: Int,
        currency: String,
        method: PaymentMethod,
        reference: String?,
        note: String?
    ) {
        do {
            var updated = payment
            updated.paidAt = paidAt
            updated.amountMinor = amountMinor
            updated.currency = currency
            updated.method = method
            updated.reference = reference
            updated.note = note
            updated.updatedAt = Date()
            setSelectedBundle(try lifecycleService.updatePayment(updated))
            setSavedNotice(localized("billing.notice.paymentUpdated", defaultValue: "Ödeme kaydı güncellendi."))
            editingPayment = nil
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askDeletePayment(_ payment: Payment) {
        confirmation = ProWorkConfirmation(
            title: localized("billing.confirm.deletePayment.title", defaultValue: "Ödeme silinsin mi?"),
            message: localized("billing.confirm.deletePayment.message", defaultValue: "Bu tahsilat kaydı silinecek."),
            confirmTitle: localized("common.delete", defaultValue: "Sil"),
            cancelTitle: localized("common.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            deletePayment(payment)
        }
    }

    private func deletePayment(_ payment: Payment) {
        do {
            setSelectedBundle(try lifecycleService.deletePayment(payment))
            setSavedNotice(localized("billing.notice.paymentDeleted", defaultValue: "Ödeme kaydı silindi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDocumentInfoEditor(_ bundle: BillingRunBundle) {
        documentInfoEditContext = DocumentInfoEditContext(
            runId: bundle.run.id,
            referenceNumber: bundle.run.invoiceNumber ?? "",
            dueDate: resolvedDueDate(for: bundle)
        )
    }

    private func saveDocumentInfo(runId: String, referenceNumber: String, dueDate: Date) {
        do {
            setSelectedBundle(try lifecycleService.updateDocumentInfo(
                runId: runId,
                invoiceNumber: referenceNumber,
                dueDate: dueDate
            ))
            setSavedNotice(localized("billing.notice.documentInfoSaved", defaultValue: "Belge bilgileri kaydedildi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func previewPDF(_ bundle: BillingRunBundle) {
        isPreparingPdfPreview = true

        Task { @MainActor in
            defer { isPreparingPdfPreview = false }

            do {
                let data = try await makePDFData(bundle: bundle)
                previewDocument = PdfPreviewDocument(
                    title: bundle.run.title ?? bundle.customer?.name ?? localized("billing.document.defaultTitle", defaultValue: "Hizmet Dökümü"),
                    data: data,
                    defaultFilename: exportService.suggestedFilename(format: .pdf, bundle: bundle)
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func export(_ bundle: BillingRunBundle, format: BillingExportFormat) {
        Task { @MainActor in
            do {
                let data: Data
                if format == .pdf {
                    data = try await makePDFData(bundle: bundle)
                } else {
                    data = try exportService.export(format: format, bundle: bundle)
                }

                saveExportData(
                    data,
                    format: format,
                    defaultFilename: exportService.suggestedFilename(format: format, bundle: bundle)
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func makePDFData(bundle: BillingRunBundle) async throws -> Data {
        try await exportService.exportPDF(
            bundle: bundle,
            settings: settingsStore.settings.serviceDocumentTemplateSettings
        )
    }

    @MainActor
    private func saveExportData(_ data: Data, format: BillingExportFormat, defaultFilename: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename

        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url)
            setSavedNotice(String(format: localized("billing.notice.exported", defaultValue: "%@ dışa aktarıldı."), format.title))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setSavedNotice(_ message: String) {
        savedNotice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if savedNotice == message {
                savedNotice = nil
            }
        }
    }

    private func setSelectedBundle(_ bundle: BillingRunBundle?) {
        selectedBundle = bundle
    }

    private func displayPeriod(start: String, end: String) -> String {
        "\(displayStoredDate(start)) – \(displayStoredDate(end))"
    }

    private func displayStoredDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            return "—"
        }
        guard let date = Self.dayFormatter.date(from: raw) else {
            return raw
        }
        return settingsStore.formatDate(date)
    }

    private func resolvedDueDate(for bundle: BillingRunBundle) -> Date {
        if let raw = bundle.run.dueDate,
           let date = Self.dayFormatter.date(from: raw) {
            return date
        }
        let paymentTermsDays = bundle.companyProfile?.paymentTermsDays ?? 30
        let baseDate = bundle.run.finalizedAt ?? bundle.run.updatedAt
        return Calendar.current.date(byAdding: .day, value: paymentTermsDays, to: baseDate) ?? baseDate
    }

    private struct PaymentSheetContext: Identifiable {
        let id = UUID()
        let mode: PaymentFormView.Mode
    }

    private struct DocumentInfoEditContext: Identifiable {
        let runId: String
        let referenceNumber: String
        let dueDate: Date
        var id: String { runId }
    }

    private struct PdfPreviewDocument: Identifiable {
        let id = UUID()
        let title: String
        let data: Data
        let defaultFilename: String
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct BillingRunCreateSheet: View {
    let customers: [Customer]
    let customerCurrencies: [String: String]
    let onSave: (String, Date, Date, String?, [String]) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = BillingDraftPickerViewModel()

    @State private var selectedCustomerId: String = ""
    @State private var selectedLineKeys: Set<String> = []
    @State private var title: String = ""
    @State private var range: DateRangeFilter = .thisMonth
    @State private var customStart: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var customEnd: Date = Date()

    // ViewModel'a proxy — sheet body 30+ noktada bu adları kullanıyor.
    private var availableCustomers: [Customer] { viewModel.availableCustomers }
    private var availableCustomerCurrencies: [String: String] { viewModel.availableCustomerCurrencies }
    private var preview: BillingDraftPreview? { viewModel.preview }
    private var isLoadingPreview: Bool { viewModel.isLoadingPreview }
    private var isImportingTodayRates: Bool { viewModel.isImportingTodayRates }
    private var previewErrorMessage: String? {
        get { viewModel.previewErrorMessage }
        nonmutating set { viewModel.previewErrorMessage = newValue }
    }
    private var previewNoticeMessage: String? {
        get { viewModel.previewNoticeMessage }
        nonmutating set { viewModel.previewNoticeMessage = newValue }
    }
    private var lifecycleService: BillingRunLifecycleService { viewModel.lifecycleService }

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            ProWorkFormHeader(
                title: localized("billing.create.title", defaultValue: "Yeni Hizmet Dökümü Taslağı"),
                subtitle: localized("billing.create.subtitle", defaultValue: "Müşteri ve dönem seçin, ardından gönderilecek hizmet satırlarını işaretleyin."),
                systemImage: "doc.text.magnifyingglass"
            )

            formFields

            Divider()

            footer
        }
        .padding(ProWorkLayout.formScaled(24, using: settingsStore))
        .frame(
            width: ProWorkLayout.formScaled(980, using: settingsStore),
            height: ProWorkLayout.formScaled(860, using: settingsStore),
            alignment: .topLeading
        )
        .onAppear {
            loadCustomers()
        }
        .onChange(of: selectedCustomerId) { _, _ in loadPreview() }
        .onChange(of: range) { _, _ in loadPreview() }
        .onChange(of: customStart) { _, _ in loadPreview() }
        .onChange(of: customEnd) { _, _ in loadPreview() }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(18, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                formRow(label: localized("projects.form.customer", defaultValue: "Müşteri")) {
                    ProWorkSearchPickerField(
                        placeholder: localized("billing.create.customerPlaceholder", defaultValue: "Müşteri seçin"),
                        items: availableCustomers,
                        selectedId: $selectedCustomerId,
                        isDisabled: availableCustomers.isEmpty,
                        showsSearch: availableCustomers.count > 8,
                        systemImage: "person.2",
                        itemTitle: { $0.name },
                        itemSubtitle: { availableCustomerCurrencies[$0.id] ?? "TRY" },
                        matchesSearch: { item, text in
                            item.name.localizedCaseInsensitiveContains(text)
                        }
                    )
                    .frame(width: ProWorkLayout.formScaled(360, using: settingsStore))
                }

                formRow(label: localized("billing.create.runTitle", defaultValue: "Döküm Başlığı")) {
                    ProWorkTextField(
                        placeholder: "",
                        text: $title,
                        minHeight: 40
                    )
                    .frame(width: ProWorkLayout.formScaled(420, using: settingsStore))
                }

                formRow(label: localized("reports.filter.period", defaultValue: "Dönem"), alignment: .top) {
                    ProWorkDateRangePicker(
                        range: $range,
                        customStart: $customStart,
                        customEnd: $customEnd,
                        defaultRange: .thisMonth
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            previewSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var footer: some View {
        ProWorkFormFooter(
            onCancel: { dismiss() },
            onSave: { saveDraft() },
            saveTitle: localized("common.create", defaultValue: "Oluştur"),
            saveDisabled: selectedCustomerId.isEmpty || selectedLineKeys.isEmpty || isLoadingPreview
        )
    }

    @ViewBuilder
    private var previewSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(12, using: settingsStore)) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("billing.previewSelection.title", defaultValue: "Satır Seçimi"))
                            .proWorkTextStyle(.headline)
                        Text(localized("billing.previewSelection.subtitle", defaultValue: "Aynı hesap satırı birden fazla hizmet dökümünde kullanılamaz. Kilitli satırlar görünür ama seçilemez."))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoadingPreview {
                        ProgressView()
                            .controlSize(.small)
                    } else if !selectablePreviewLines.isEmpty {
                        HStack(spacing: 10) {
                            Button(localized("common.selectAll", defaultValue: "Tümünü Seç")) {
                                selectedLineKeys = Set(selectablePreviewLines.map(\.selectionKey))
                            }
                            .buttonStyle(.borderless)

                            Button(localized("common.clear", defaultValue: "Temizle")) {
                                selectedLineKeys.removeAll()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                ProWorkFormError(message: previewErrorMessage)
                Color.clear
                    .frame(height: 0)
                    .proWorkToastNotifications(successMessage: previewNoticeMessage)

                if let preview {
                HStack(spacing: 18) {
                    previewMetric(localized("billing.previewMetric.available", defaultValue: "Uygun Satır"), "\(preview.availableLines.count)")
                    previewMetric(localized("billing.previewMetric.blocked", defaultValue: "Engelli Satır"), "\(preview.blockedLineCount)")
                    previewMetric(localized("billing.previewMetric.selected", defaultValue: "Seçilen"), "\(selectedLineKeys.count)")
                    previewMetric(localized("billing.previewMetric.drafts", defaultValue: "Taslak"), "\(selectedDraftCount)")
                    previewMetric(localized("billing.previewMetric.selectedAmount", defaultValue: "Seçili Tutar"), selectedTotalsDisplay)
                    masterTotalMetric
                    Spacer()
                }

                if selectedDraftCount > 1 {
                    Text(String(format: localized("billing.previewSelection.multipleCurrencies", defaultValue: "Seçili satırlar %d farklı para birimine dağılıyor. Oluşturma işleminde her para birimi için ayrı hizmet dökümü taslağı açılacak."), selectedDraftCount))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                if preview.lines.isEmpty {
                    SettingsEmptyState(
                            systemImage: "list.bullet.clipboard",
                            title: localized("billing.previewSelection.empty.title", defaultValue: "Satır bulunamadı"),
                            message: localized("billing.previewSelection.empty.message", defaultValue: "Seçilen dönem için hesaplanabilir hizmet satırı bulunamadı.")
                        )
                    } else {
                        ScrollView(.horizontal) {
                            previewTable(preview.lines)
                        }
                    }
                } else if isLoadingPreview {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(localized("billing.previewSelection.loading", defaultValue: "Hizmet satırları hazırlanıyor..."))
                            .proWorkTextStyle(.callout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func previewTable(_ lines: [BillingDraftPreviewLine]) -> some View {
        SettingsTableContainer {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("").frame(width: 36)
                    Text(localized("reports.todo.table.todo", defaultValue: "Görev")).frame(width: 260, alignment: .leading)
                    Text(localized("projects.title.single", defaultValue: "Proje")).frame(width: 150, alignment: .leading)
                    Text(localized("priceLists.rows.form.serviceType", defaultValue: "Hizmet")).frame(width: 90, alignment: .leading)
                    Text(localized("priceLists.rows.form.timeType", defaultValue: "Zaman")).frame(width: 100, alignment: .leading)
                    Text(localized("workSessions.column.start", defaultValue: "Başlangıç")).frame(width: 150, alignment: .leading)
                    Text(localized("reports.table.billable", defaultValue: "Ücretli")).frame(width: 70, alignment: .trailing)
                    Text(localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 130, alignment: .trailing)
                    Text(localized("projects.form.status", defaultValue: "Durum")).frame(width: 180, alignment: .leading)
                }
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.35))

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(lines) { line in
                            previewRow(line)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1210, maxHeight: .infinity, alignment: .leading)
    }

    private func previewRow(_ previewLine: BillingDraftPreviewLine) -> some View {
        let line = previewLine.line
        let isOpenSession = line.endedAt == nil

        return HStack(spacing: 12) {
            ProWorkCheckbox(
                isOn: selectionBinding(for: previewLine.selectionKey),
                isDisabled: !previewLine.isSelectable,
                boxSize: 20
            )
            .frame(width: 36, alignment: .leading)

            Text(line.todoTitle)
                .proWorkTextStyle(.callout)
                .frame(width: 260, alignment: .leading)
                .lineLimit(1)
            Text(line.projectName ?? "—")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            Text(line.isFixedFee ? localized("export.column.fixedFee", defaultValue: "Sabit") : line.serviceType.title)
                .proWorkTextStyle(.caption)
                .frame(width: 90, alignment: .leading)
            Text(line.isFixedFee ? "—" : line.timeType.title)
                .proWorkTextStyle(.caption)
                .frame(width: 100, alignment: .leading)
            Text(line.startedAt.map(settingsStore.formatDateTime) ?? "—")
                .proWorkTextStyle(.caption)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            Text(
                isOpenSession
                ? "—"
                : (
                    line.isFixedFee
                    ? String(format: localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), 0)
                    : String(format: localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), line.billableMinutes)
                )
            )
                .proWorkTextStyle(.caption)
                .frame(width: 70, alignment: .trailing)
            Text(isOpenSession ? "—" : ProWorkFormatters.money(line.total))
                .proWorkTextStyle(.caption, weight: .medium)
                .frame(width: 130, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.isManual
                     ? localized("workSessions.source.manual", defaultValue: "Manuel")
                     : localized("workSessions.source.automatic", defaultValue: "Otomatik"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(line.isManual ? .orange : .secondary)

                if let blockingRunLabel = previewLine.blockingRunLabel {
                    Text("\(localized("billing.previewSelection.locked", defaultValue: "Kilitli")): \(blockingRunLabel)")
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .frame(width: 180, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(previewLine.isSelectable ? 1 : 0.6)
    }

    private func formRow<Content: View>(
        label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.callout, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: ProWorkLayout.formScaled(170, using: settingsStore), alignment: .leading)

            HStack {
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .proWorkTextStyle(.callout, weight: .medium)
        }
    }

    @ViewBuilder
    private var masterTotalMetric: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("billing.previewMetric.masterCurrency", defaultValue: "Ana Para Birimi"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            switch selectedTotalInMasterState {
            case .ready(let value):
                Text(value)
                    .proWorkTextStyle(.callout, weight: .medium)
            case .missingRate:
                Button {
                    importTodayRatesForPreview()
                } label: {
                    HStack(spacing: 6) {
                        if isImportingTodayRates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: settingsStore.settings.preferredExchangeRateSource.systemImage)
                                .proWorkFont(size: 12)
                        }
                        Text(
                            isImportingTodayRates
                            ? localized("billing.previewMetric.fetchingRates", defaultValue: "Çekiliyor...")
                            : localized("billing.previewMetric.rateMissing", defaultValue: "Kur eksik")
                        )
                            .proWorkTextStyle(.callout, weight: .medium)
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(isImportingTodayRates)
                .help(localized("billing.previewMetric.fetchRatesHelp", defaultValue: "Bugün için varsayılan kur kaynağını çek, gerekirse fallback kaynağı dene"))
            }
        }
    }

    private func selectionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedLineKeys.contains(key) },
            set: { isSelected in
                if isSelected {
                    selectedLineKeys.insert(key)
                } else {
                    selectedLineKeys.remove(key)
                }
            }
        )
    }

    private func saveDraft() {
        do {
            try onSave(
                selectedCustomerId,
                effectiveStartDate,
                inclusiveEndDate,
                title.nilIfEmpty,
                Array(selectedLineKeys)
            )
            dismiss()
        } catch {
            previewErrorMessage = error.localizedDescription
        }
    }

    private func loadPreview() {
        guard !selectedCustomerId.isEmpty else {
            viewModel.clearPreview()
            selectedLineKeys.removeAll()
            return
        }

        viewModel.loadPreview(
            customerId: selectedCustomerId,
            periodStart: effectiveStartDate,
            periodEnd: inclusiveEndDate
        )

        if let loaded = viewModel.preview {
            selectedLineKeys = Set(loaded.availableLines.map(\.selectionKey))
        } else {
            selectedLineKeys.removeAll()
        }
    }

    private var selectablePreviewLines: [BillingDraftPreviewLine] {
        preview?.availableLines ?? []
    }

    private var selectedLineMonies: [Money] {
        selectablePreviewLines
            .filter { selectedLineKeys.contains($0.selectionKey) }
            .map { Money(minorUnits: $0.line.totalMinor, currency: $0.line.currency) }
    }

    private var selectedDraftCount: Int {
        Set(
            selectablePreviewLines
                .filter { selectedLineKeys.contains($0.selectionKey) }
                .map(\.line.currency)
        ).count
    }

    private var selectedTotalsDisplay: String {
        let grouped = Dictionary(grouping: selectedLineMonies, by: \.currency)
        let parts = grouped.keys.sorted().compactMap { currency -> String? in
            guard let monies = grouped[currency] else { return nil }
            let totalMinor = monies.reduce(0) { $0 + $1.minorUnits }
            return ProWorkFormatters.money(Money(minorUnits: totalMinor, currency: currency))
        }

        if parts.isEmpty {
            return ProWorkFormatters.money(Money.zero(availableCustomerCurrencies[selectedCustomerId] ?? "TRY"))
        }

        return parts.joined(separator: " + ")
    }

    private func loadCustomers() {
        viewModel.loadCustomers(fallback: customers, fallbackCurrencies: customerCurrencies)

        let loaded = viewModel.availableCustomers
        let availableIds = Set(loaded.map(\.id))
        if selectedCustomerId.isEmpty || !availableIds.contains(selectedCustomerId) {
            selectedCustomerId = loaded.first?.id ?? ""
        } else {
            loadPreview()
        }

        if loaded.isEmpty {
            viewModel.clearPreview()
            selectedLineKeys.removeAll()
        }
    }

    private var selectedTotalInMasterState: MasterTotalState {
        let masterCurrency = viewModel.masterCurrency()
        guard !selectedLineMonies.isEmpty else {
            return .ready(ProWorkFormatters.money(Money.zero(masterCurrency)))
        }

        let converter = CurrencyConverter(
            organizationId: BuiltInOrganizationId.default,
            masterCurrency: masterCurrency,
            preferredAutoSource: settingsStore.settings.preferredExchangeRateSource
        )

        do {
            let total = try converter.sumInMaster(
                selectedLineMonies,
                on: Self.dayFormatter.string(from: inclusiveEndDate)
            )
            return .ready(ProWorkFormatters.money(total))
        } catch {
            return .missingRate
        }
    }

    private func importTodayRatesForPreview() {
        let preferredSource = settingsStore.settings.preferredExchangeRateSource
        let currencies = previewRequiredCurrencyCodes

        Task { @MainActor in
            if let outcome = await viewModel.importTodayRates(
                currencies: currencies,
                preferredSource: preferredSource
            ) {
                loadPreview()
                viewModel.previewNoticeMessage = makeTodayRateNotice(from: outcome.result, source: outcome.source)
            }
        }
    }

    private func makeTodayRateNotice(
        from result: TCMBExchangeRateSyncResult,
        source: ExchangeRateAutoSource
    ) -> String {
        if result.importedDayCount > 0 {
            return String(
                format: localized("billing.notice.ratesImported", defaultValue: "Bugün için %d adet %@ kur kaydı çekildi."),
                result.importedRateCount,
                source.title
            )
        }
        return String(
            format: localized("billing.notice.ratesUnavailable", defaultValue: "Bugün için %@ kuru yayımlanmadı."),
            source.title
        )
    }

    private var previewRequiredCurrencyCodes: [String] {
        let masterCurrency = viewModel.masterCurrency()
        var currencies = Set(
            selectedLineMonies
                .map(\.currency)
                .map { $0.uppercased() }
        )
        currencies.insert(masterCurrency)
        currencies.remove("TRY")
        return currencies.sorted()
    }

    private var effectiveStartDate: Date {
        range.startDate(custom: customStart)
    }

    private var inclusiveEndDate: Date {
        if range == .custom {
            return customEnd
        }

        let exclusive = range.endDate(custom: customEnd)
        return Calendar.current.date(byAdding: .day, value: -1, to: exclusive) ?? customEnd
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private enum MasterTotalState {
        case ready(String)
        case missingRate
    }

    // CompositeRateImportError BillingDraftPickerViewModel.swift'e taşındı.
}

private struct BillingRunDocumentInfoSheet: View {
    let onSave: (String, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var referenceNumber: String
    @State private var dueDate: Date

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    init(
        referenceNumber: String,
        dueDate: Date,
        onSave: @escaping (String, Date) -> Void
    ) {
        self.onSave = onSave
        _referenceNumber = State(initialValue: referenceNumber)
        _dueDate = State(initialValue: dueDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(18, using: settingsStore)) {
            Text(localized("billing.documentInfo.title", defaultValue: "Belge Bilgilerini Düzenle"))
                .proWorkTextStyle(.title2)
                .bold()

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
                Text(localized("export.row.referenceNumber", defaultValue: "Referans No"))
                    .proWorkTextStyle(.callout, weight: .medium)
                ProWorkTextField(
                    placeholder: localized("billing.documentInfo.referencePlaceholder", defaultValue: "Referans numarası"),
                    text: $referenceNumber
                )

                Text(localized("pdf.document.dueDate", defaultValue: "Vade"))
                    .proWorkTextStyle(.callout, weight: .medium)
                ProWorkDateField(title: "", date: $dueDate)
                    .frame(width: 220)
            }

            HStack {
                Spacer()

                Button(localized("common.cancel", defaultValue: "Vazgeç")) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button {
                    onSave(referenceNumber, dueDate)
                    dismiss()
                } label: {
                    ProWorkButtonLabel(title: localized("common.save", defaultValue: "Kaydet"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
        .frame(width: 420)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
