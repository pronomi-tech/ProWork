//
//  PriceListRowsEditView.swift
//  ProWork
//
//  Created by Pronomi.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PriceListRowsEditView: View {
    let list: PriceList
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = PriceListRowsEditViewModel()

    @State private var isShowingNewRow = false
    @State private var editingRow: PriceListRow?
    @State private var confirmation: ProWorkConfirmation?

    @State private var isShowingQuoteRecipientSheet = false
    @State private var quotePreviewDocument: QuotePreviewDocument?
    private let quoteBuilder = PriceListQuoteBundleBuilder()
    private let quoteRenderer = PriceListQuotePdfRenderer()

    var body: some View {
        ProWorkFormShell(
            title: list.name,
            subtitle: String(format: settingsStore.localized("priceLists.rows.subtitle", defaultValue: "%@ — %d satır"), list.currency, viewModel.rows.count),
            systemImage: "list.bullet.rectangle.portrait",
            width: 880,
            height: 640,
            headerTrailing: {
                HStack(spacing: 10) {
                    Button {
                        isShowingQuoteRecipientSheet = true
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("priceLists.rows.action.quote", defaultValue: "Teklif PDF'i"), systemImage: "doc.text.fill", minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.rows.filter(\.isActive).isEmpty)
                    .help(settingsStore.localized("priceLists.rows.action.quote.help", defaultValue: "Fiyat listesini kurumsal teklif PDF'i olarak dışa aktar"))

                    Button {
                        isShowingNewRow = true
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("priceLists.rows.action.new", defaultValue: "Yeni Satır"), systemImage: "plus", minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.rows.isEmpty {
                    emptyState
                } else {
                    rowsTable
                }
            }
        } footer: {
            SettingsFormSingleFooter(onPrimary: { dismiss() }, title: settingsStore.localized("common.close", defaultValue: "Kapat"), systemImage: "xmark")
        }
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear { viewModel.load(priceListId: list.id) }
        .sheet(isPresented: $isShowingNewRow) {
            PriceListRowFormView(
                mode: .create,
                priceListId: list.id,
                listCurrency: list.currency,
                categories: viewModel.categories
            ) { row in
                if viewModel.add(row, priceListId: list.id) {
                    isShowingNewRow = false
                    onChange()
                }
            }
        }
        .sheet(item: $editingRow) { row in
            PriceListRowFormView(
                mode: .edit(row),
                priceListId: list.id,
                listCurrency: list.currency,
                categories: viewModel.categories
            ) { updated in
                if viewModel.update(updated, priceListId: list.id) {
                    editingRow = nil
                    onChange()
                }
            }
        }
        .proWorkConfirmationDialog($confirmation)
        .sheet(isPresented: $isShowingQuoteRecipientSheet) {
            let year = Calendar.current.component(.year, from: Date())
            let nextSequence = settingsStore.peekNextQuoteSequence(year: year)
            let prefix = settingsStore.settings.priceListQuoteTemplateSettings.quoteNumberPrefix
            let suggestedQuoteNumber = PriceListQuoteNumberFormatter.format(
                prefix: prefix,
                year: year,
                sequence: nextSequence
            )
            PriceListQuoteRecipientSheet(
                list: list,
                customers: viewModel.loadCustomers(),
                suggestedCustomerId: list.ownerType == .customer ? list.ownerId : nil,
                suggestedQuoteNumber: suggestedQuoteNumber,
                suggestedSequence: nextSequence
            ) { result in
                generateQuote(using: result)
            }
            .environmentObject(settingsStore)
        }
        .sheet(item: $quotePreviewDocument) { document in
            BillingPdfPreviewSheet(
                title: document.title,
                data: document.data
            ) {
                saveQuoteData(document.data, defaultFilename: document.defaultFilename)
            }
            .environmentObject(settingsStore)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .proWorkFont(size: 28)
                .foregroundStyle(.secondary)
            Text(settingsStore.localized("priceLists.rows.empty.title", defaultValue: "Bu listede henüz satır yok"))
                .proWorkTextStyle(.headline)
            Text(settingsStore.localized("priceLists.rows.empty.message", defaultValue: "Sağ üstten yeni fiyat satırı ekleyin."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .proWorkFrame(minHeight: 240, maxWidth: .infinity)
    }

    private var rowsTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        rowView(row)
                        Divider()
                    }
                }
            }
        }
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("priceLists.rows.column.service", defaultValue: "Hizmet")).frame(width: 100, alignment: .leading)
            Text(settingsStore.localized("priceLists.rows.column.timeType", defaultValue: "Zaman Tipi")).frame(width: 130, alignment: .leading)
            Text(settingsStore.localized("priceLists.rows.column.category", defaultValue: "Kategori")).frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("priceLists.rows.column.unitPrice", defaultValue: "Birim Ücret")).frame(width: 160, alignment: .trailing)
            Text(settingsStore.localized("priceLists.column.active", defaultValue: "Aktif")).frame(width: 60, alignment: .center)
            Text("").frame(width: 80)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func rowView(_ row: PriceListRow) -> some View {
        let categoryName = row.categoryId.flatMap { id in
            viewModel.categories.first(where: { $0.id == id })?.name
        } ?? settingsStore.localized("priceLists.rows.allCategories", defaultValue: "Tüm kategoriler")

        let unitPrice = Money(minorUnits: row.unitPriceMinor, currency: row.currency)
        let unitText = formattedHourlyRate(unitPrice)

        return HStack(spacing: 12) {
            Text(row.serviceType.title)
                .proWorkTextStyle(.callout)
                .frame(width: 100, alignment: .leading)

            Text(row.timeType.title)
                .proWorkTextStyle(.callout)
                .frame(width: 130, alignment: .leading)

            Text(categoryName)
                .proWorkTextStyle(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(unitText)
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(width: 160, alignment: .trailing)

            Image(systemName: row.isActive ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(row.isActive ? .green : .secondary)
                .frame(width: 60, alignment: .center)

            HStack(spacing: 6) {
                Button {
                    editingRow = row
                } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button {
                    askDelete(row)
                } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func askDelete(_ row: PriceListRow) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("priceLists.rows.delete.title", defaultValue: "Satır silinsin mi?"),
            message: settingsStore.localized("priceLists.rows.delete.message", defaultValue: "Bu fiyat satırı silinecek."),
            confirmTitle: settingsStore.localized("priceLists.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("priceLists.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.softDelete(id: row.id, priceListId: list.id)
            onChange()
        }
    }

    // MARK: - Quote export

    private func generateQuote(using result: PriceListQuoteRecipientSheet.Result) {
        do {
            let (companyProfile, customer) = try viewModel.loadQuoteContext(
                organizationId: list.organizationId,
                ownerType: list.ownerType,
                ownerId: list.ownerId
            )

            let bundle = quoteBuilder.build(
                priceList: list,
                rows: viewModel.rows,
                categories: viewModel.categories,
                recipient: result.recipient,
                quoteNumber: result.quoteNumber,
                issueDate: result.issueDate,
                companyProfile: companyProfile,
                customer: customer,
                settings: settingsStore.settings.priceListQuoteTemplateSettings
            )

            if result.sequenceConsumed {
                let year = Calendar.current.component(.year, from: result.issueDate)
                _ = settingsStore.consumeNextQuoteSequence(year: year)
            }

            Task { @MainActor in
                do {
                    let data = try await quoteRenderer.render(bundle: bundle)
                    let safeName = result.quoteNumber
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: " ", with: "_")
                    quotePreviewDocument = QuotePreviewDocument(
                        title: bundle.titleText,
                        defaultFilename: "Teklif-\(safeName).pdf",
                        data: data
                    )
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveQuoteData(_ data: Data, defaultFilename: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename
        if let type = UTType(filenameExtension: "pdf") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func formattedHourlyRate(_ value: Money) -> String {
        let formatter = NumberFormatter()
        let info = Currency.info(for: value.currency)
        formatter.locale = settingsStore.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = info.decimalPlaces
        formatter.maximumFractionDigits = info.decimalPlaces
        formatter.usesGroupingSeparator = true

        let number = NSDecimalNumber(decimal: value.amount)
        let amount = formatter.string(from: number) ?? "0"
        let symbol = Currency.info(for: value.currency).symbol
        return String(format: settingsStore.localized("priceLists.rows.unitPerHour", defaultValue: "%@ %@ / saat"), amount, symbol)
    }
}

private struct QuotePreviewDocument: Identifiable {
    let id = UUID()
    let title: String
    let defaultFilename: String
    let data: Data
}
