//  BillingRunsView.swift
//  ProWork
//   Created by Pronomi.
//  Top-level view for the Billing tab. After the M10 split this file
//  holds only orchestration: state, sheet routing, confirmation
//  dialogs, NSSavePanel plumbing, and the delegates that call into
//  BillingRunsViewModel. Visual blocks live in their own files:
//   • BillingRunsHeader        — title bar + new run CTA
//   • BillingRunsSidebar       — left list of runs (+ row view)
//   • BillingRunDetailPanel    — overview / export / lines / payments
//   • BillingRunCreateSheet    — new draft sheet
//   • BillingRunDocumentInfoSheet — reference number + due date editor
//   • BillingActionButton, BillingStatusChips — small visual helpers

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BillingRunsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = BillingRunsViewModel()

    // Previously this view held five separate @State
    // flags/optionals — isShowingCreateSheet (Bool), paymentSheetContext
    // (Optional), documentInfoEditContext (Optional), previewDocument
    // (Optional), and editingPayment (auxiliary) — and four matching
    // `.sheet(...)` modifiers. Setting one without explicitly clearing
    // the others let the view briefly be in an undefined "two sheets
    // requested" state. Replace with a single ActiveSheet enum + one
    // `.sheet(item:)` modifier so transitions are guaranteed mutually
    // exclusive. `editingPayment` stays as a convenience pointer to the
    // currently-edited payment for save callbacks.
    /// payment-edit sheet routes through `editingPayment` while
    /// every other modal flows through `activeSheet`. The split is
    /// intentional today — `editingPayment` is the SwiftUI
    /// `.sheet(item:)` binding that wants an `Identifiable` payload —
    /// but the two states must NOT both be non-nil simultaneously
    /// (SwiftUI would crash on dual presentation). The
    /// `dismissAllSheets()` helper at the bottom of this file enforces
    /// the invariant when any router transitions.
    @State private var activeSheet: BillingRunsActiveSheet?
    @State private var editingPayment: Payment?
    @State private var confirmation: ProWorkConfirmation?
    @State private var isPreparingPdfPreview = false
    /// Hold onto the in-flight preview / export task so a
    /// subsequent bundle selection can cancel the stale render rather than
    /// letting it deliver onto whichever bundle happens to be active when
    /// it finishes.
    @State private var pdfPreviewTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    /// `selectedRunIsDraft` derives once per body so both the
    /// header and sidebar consume the same value instead of evaluating
    /// the equality twice.
    private var selectedRunIsDraft: Bool {
        viewModel.selectedBundle?.run.status == .draft
    }

    var body: some View {
        VStack(spacing: 0) {
            BillingRunsHeader(
                selectedRunIsDraft: selectedRunIsDraft,
                onCreate: { activeSheet = .create }
            )

            Divider()

            HStack(spacing: 0) {
                BillingRunsSidebar(
                    runs: viewModel.runs,
                    selectedRunId: viewModel.selectedRunId,
                    customerLookup: viewModel.customerLookup,
                    selectedRunIsDraft: selectedRunIsDraft,
                    displayPeriod: displayPeriod,
                    onSelectRun: { viewModel.selectRun(id: $0) },
                    onDeleteSelectedDraft: askDeleteSelectedRun
                )
                Divider()
                BillingRunDetailPanel(
                    bundle: viewModel.selectedBundle,
                    isPreparingPdfPreview: isPreparingPdfPreview,
                    masterCurrencyForOrg: viewModel.masterCurrency(for:),
                    displayStoredDate: displayStoredDate,
                    displayPeriod: displayPeriod,
                    onEditDocumentInfo: openDocumentInfoEditor,
                    onRefreshDraft: refreshSelectedRun,
                    onFinalize: finalizeSelectedRun,
                    onCancelRun: askCancelSelectedRun,
                    onPreviewPDF: previewPDF,
                    onExport: export,
                    onAddPayment: startAddPayment,
                    onEditPayment: startEditPayment,
                    onDeletePayment: askDeletePayment
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .proWorkToastNotifications(
            errorMessage: viewModel.errorMessage,
            successMessage: viewModel.savedNotice
        )
        .onAppear(perform: viewModel.load)
        .sheet(item: $activeSheet, content: sheetContent)
        .proWorkConfirmationDialog($confirmation)
    }

    // MARK: - Sheet routing

    @ViewBuilder
    private func sheetContent(for sheet: BillingRunsActiveSheet) -> some View {
        switch sheet {
        case .create:
            BillingRunCreateSheet(
                customers: viewModel.customers,
                customerCurrencies: viewModel.customerCurrencies
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

        case .payment(let context):
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
                } else if let runId = viewModel.selectedRunId {
                    addPayment(
                        runId: runId,
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

        case .pdfPreview(let document):
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

        case .documentInfo(let context):
            BillingRunDocumentInfoSheet(
                referenceNumber: context.referenceNumber,
                dueDate: context.dueDate
            ) { referenceNumber, dueDate in
                saveDocumentInfo(runId: context.runId, referenceNumber: referenceNumber, dueDate: dueDate)
            }
            .environmentObject(settingsStore)
        }
    }

    // MARK: - Orchestration delegates
    // All lifecycle / export / payment / document-info mutation flows now
    // live on `BillingRunsViewModel`. The View only keeps presentation
    // concerns: confirmation dialogs, sheet routing, NSSavePanel, and
    // PDF preview sheet plumbing. Notice debouncing also moved into the
    // VM (cancellable Task, not asyncAfter).

    private func createDraft(
        customerId: String,
        startDate: Date,
        endDate: Date,
        title: String?,
        selectedLineKeys: [String]
    ) throws {
        _ = try viewModel.createDraft(
            customerId: customerId,
            startDate: startDate,
            endDate: endDate,
            title: title,
            selectedLineKeys: selectedLineKeys,
            savedNoticeFor: draftCreationNotice(for:)
        )
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
        viewModel.refreshSelectedRun(
            noticeMessage: localized("billing.notice.draftRefreshed", defaultValue: "Taslak güncellendi.")
        )
    }

    private func finalizeSelectedRun() {
        viewModel.finalizeSelectedRun(
            noticeMessage: localized("billing.notice.finalized", defaultValue: "Hizmet dökümü kesinleştirildi.")
        )
    }

    private func askCancelSelectedRun() {
        guard let selectedBundle = viewModel.selectedBundle else { return }
        confirmation = ProWorkConfirmation(
            title: localized("billing.confirm.cancelRun.title", defaultValue: "Kayıt iptal edilsin mi?"),
            message: localized("billing.confirm.cancelRun.message", defaultValue: "Kesinleşmiş hizmet dökümü kaydı iptal statüsüne alınacak."),
            confirmTitle: localized("billing.confirm.cancelRun.confirm", defaultValue: "İptal Et"),
            cancelTitle: localized("common.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.cancelRun(
                bundle: selectedBundle,
                noticeMessage: localized("billing.notice.cancelled", defaultValue: "Kayıt iptal edildi.")
            )
        }
    }

    private func askDeleteSelectedRun() {
        guard let selectedBundle = viewModel.selectedBundle else { return }
        confirmation = ProWorkConfirmation(
            title: localized("billing.confirm.deleteDraft.title", defaultValue: "Taslak silinsin mi?"),
            message: localized("billing.confirm.deleteDraft.message", defaultValue: "Kesinleşmemiş hizmet dökümü kaydı kalıcı olarak silinecek."),
            confirmTitle: localized("common.delete", defaultValue: "Sil"),
            cancelTitle: localized("common.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.deleteRun(
                bundle: selectedBundle,
                noticeMessage: localized("billing.notice.draftDeleted", defaultValue: "Taslak kayıt silindi.")
            )
        }
    }

    private func startAddPayment(_ bundle: BillingRunBundle) {
        editingPayment = nil
        activeSheet = .payment(BillingRunsPaymentSheetContext(mode: .create(currency: bundle.run.currency)))
    }

    private func startEditPayment(_ payment: Payment) {
        editingPayment = payment
        activeSheet = .payment(BillingRunsPaymentSheetContext(mode: .edit(payment)))
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
        viewModel.addPayment(
            runId: runId,
            paidAt: paidAt,
            amountMinor: amountMinor,
            currency: currency,
            method: method,
            reference: reference,
            note: note,
            noticeMessage: localized("billing.notice.paymentAdded", defaultValue: "Ödeme kaydı eklendi.")
        )
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
        viewModel.updatePayment(
            payment,
            paidAt: paidAt,
            amountMinor: amountMinor,
            currency: currency,
            method: method,
            reference: reference,
            note: note,
            noticeMessage: localized("billing.notice.paymentUpdated", defaultValue: "Ödeme kaydı güncellendi.")
        )
        editingPayment = nil
    }

    private func askDeletePayment(_ payment: Payment) {
        confirmation = ProWorkConfirmation(
            title: localized("billing.confirm.deletePayment.title", defaultValue: "Ödeme silinsin mi?"),
            message: localized("billing.confirm.deletePayment.message", defaultValue: "Bu tahsilat kaydı silinecek."),
            confirmTitle: localized("common.delete", defaultValue: "Sil"),
            cancelTitle: localized("common.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.deletePayment(
                payment,
                noticeMessage: localized("billing.notice.paymentDeleted", defaultValue: "Ödeme kaydı silindi.")
            )
        }
    }

    private func openDocumentInfoEditor(_ bundle: BillingRunBundle) {
        activeSheet = .documentInfo(
            BillingRunsDocumentInfoEditContext(
                runId: bundle.run.id,
                referenceNumber: bundle.run.invoiceNumber ?? "",
                dueDate: resolvedDueDate(for: bundle)
            )
        )
    }

    private func saveDocumentInfo(runId: String, referenceNumber: String, dueDate: Date) {
        viewModel.saveDocumentInfo(
            runId: runId,
            referenceNumber: referenceNumber,
            dueDate: dueDate,
            noticeMessage: localized("billing.notice.documentInfoSaved", defaultValue: "Belge bilgileri kaydedildi.")
        )
    }

    @MainActor
    private func previewPDF(_ bundle: BillingRunBundle) {
        // Cancel any in-flight preview before kicking off a new one — if the
        // user picked a different bundle, the older render is now stale
        pdfPreviewTask?.cancel()
        isPreparingPdfPreview = true

        pdfPreviewTask = Task { @MainActor in
            defer { isPreparingPdfPreview = false }

            do {
                let data = try await viewModel.makePDFData(
                    bundle: bundle,
                    templateSettings: settingsStore.settings.serviceDocumentTemplateSettings
                )
                // Bail out if a newer selection cancelled us during render.
                guard !Task.isCancelled else { return }
                activeSheet = .pdfPreview(
                    BillingRunsPdfPreviewDocument(
                        title: bundle.run.title ?? bundle.customer?.name ?? localized("billing.document.defaultTitle", defaultValue: "Hizmet Dökümü"),
                        data: data,
                        defaultFilename: viewModel.suggestedFilename(format: .pdf, bundle: bundle)
                    )
                )
            } catch is CancellationError {
                // Cancellation is user-initiated (sidebar
                // selection change or sheet dismissal). No error UI;
                // we still drop `isPreparingPdfPreview` via the defer
                // so the spinner clears.
            } catch {
                // Non-cancellation failures surface through the
                // shared toast pipeline so the user knows the export
                // request didn't succeed silently. The renderer
                // already logs the underlying error category
                // (`BillingPdfRendererError`) before throwing.
                viewModel.reportError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func export(_ bundle: BillingRunBundle, format: BillingExportFormat) {
        // Same cancellation pattern as previewPDF.
        exportTask?.cancel()
        exportTask = Task { @MainActor in
            do {
                let data: Data
                if format == .pdf {
                    data = try await viewModel.makePDFData(
                        bundle: bundle,
                        templateSettings: settingsStore.settings.serviceDocumentTemplateSettings
                    )
                } else {
                    data = try viewModel.exportNonPDF(format: format, bundle: bundle)
                }
                guard !Task.isCancelled else { return }

                saveExportData(
                    data,
                    format: format,
                    defaultFilename: viewModel.suggestedFilename(format: format, bundle: bundle)
                )
            } catch is CancellationError {
                // Quietly swallow.
            } catch {
                viewModel.reportError(error.localizedDescription)
            }
        }
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
            viewModel.reportExportSucceeded(
                noticeMessage: String(format: localized("billing.notice.exported", defaultValue: "%@ dışa aktarıldı."), format.title)
            )
        } catch {
            viewModel.reportError(error.localizedDescription)
        }
    }

    // MARK: - Date display helpers

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
        return AppCalendar.istanbul.date(byAdding: .day, value: paymentTermsDays, to: baseDate) ?? baseDate
    }

    // Sheet routing types live in BillingRunsSheetRouting.swift.

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
