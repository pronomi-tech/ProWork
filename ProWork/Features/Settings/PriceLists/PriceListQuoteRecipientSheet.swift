//
//  PriceListQuoteRecipientSheet.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

/// Teklif PDF'i üretmeden önce alıcı bilgisi + belge numarasını toplayan sheet.
struct PriceListQuoteRecipientSheet: View {
    struct Result {
        var recipient: PriceListQuoteBundleBuilder.RecipientInput
        var quoteNumber: String
        var issueDate: Date
        var sequenceConsumed: Bool
    }

    let list: PriceList
    let customers: [Customer]
    let suggestedCustomerId: String?
    let suggestedQuoteNumber: String
    let suggestedSequence: Int
    let onSubmit: (Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var selectedCustomerId: String = ""
    @State private var recipientName: String = ""
    @State private var contactPerson: String = ""
    @State private var recipientAddress: String = ""
    @State private var recipientCode: String = ""
    @State private var quoteNumber: String = ""
    @State private var issueDate: Date = Date()
    @State private var manualQuoteNumber: Bool = false

    private let manualOptionId = "__manual__"

    var body: some View {
        ProWorkFormShell(
            title: settingsStore.localized("quote.recipientSheet.title", defaultValue: "Teklif Bilgileri"),
            subtitle: settingsStore.localized("quote.recipientSheet.subtitle", defaultValue: "PDF'te kullanılacak alıcı ve belge bilgilerini girin."),
            systemImage: "person.text.rectangle",
            width: 600,
            height: 620
        ) {
            VStack(alignment: .leading, spacing: 14) {
                section(title: settingsStore.localized("quote.recipientSheet.section.recipient", defaultValue: "Alıcı")) {
                    SettingsFormRow(settingsStore.localized("quote.recipientSheet.field.customer", defaultValue: "Müşteri")) {
                        ProWorkSearchPickerField(
                            placeholder: settingsStore.localized("quote.recipientSheet.field.customer.placeholder", defaultValue: "Müşteri seç veya manuel gir"),
                            items: customerOptions,
                            selectedId: $selectedCustomerId,
                            isDisabled: false,
                            showsSearch: customers.count > 6,
                            systemImage: "person.2",
                            itemTitle: { $0.title },
                            itemSubtitle: { $0.subtitle },
                            itemColor: { _ in nil },
                            matchesSearch: { item, query in
                                item.title.localizedCaseInsensitiveContains(query) ||
                                (item.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
                            }
                        )
                        .frame(width: 380)
                        .onChange(of: selectedCustomerId) { _, newValue in
                            applyCustomer(id: newValue)
                        }
                    }

                    SettingsFormRow(settingsStore.localized("quote.recipientSheet.field.name", defaultValue: "Firma / Müşteri"), required: true) {
                        ProWorkTextField(placeholder: "", text: $recipientName)
                            .frame(width: 380)
                    }
                    SettingsFormRow(settingsStore.localized("quote.recipientSheet.field.contact", defaultValue: "İlgili Kişi")) {
                        ProWorkTextField(
                            placeholder: "",
                            text: $contactPerson
                        )
                        .frame(width: 380)
                    }
                    SettingsFormRow(settingsStore.localized("quote.recipientSheet.field.address", defaultValue: "Adres")) {
                        ProWorkTextField(placeholder: "", text: $recipientAddress)
                            .frame(width: 380)
                    }
                    SettingsFormRow(settingsStore.localized("quote.recipientSheet.field.code", defaultValue: "Müşteri Kodu")) {
                        ProWorkTextField(placeholder: "", text: $recipientCode)
                            .frame(width: 200)
                    }
                }

                section(title: settingsStore.localized("quote.recipientSheet.section.document", defaultValue: "Belge")) {
                    SettingsFormRow(settingsStore.localized("quote.recipientSheet.field.quoteNumber", defaultValue: "Teklif No"), required: true) {
                        HStack(spacing: 8) {
                            ProWorkTextField(placeholder: suggestedQuoteNumber, text: $quoteNumber)
                                .frame(width: 200)
                                .onChange(of: quoteNumber) { _, newValue in
                                    manualQuoteNumber = newValue != suggestedQuoteNumber
                                }
                            Button {
                                quoteNumber = suggestedQuoteNumber
                                manualQuoteNumber = false
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help(settingsStore.localized("quote.recipientSheet.field.quoteNumber.reset", defaultValue: "Otomatik öneriye dön"))
                        }
                    }
                    SettingsFormRow(settingsStore.localized("quote.recipientSheet.field.issueDate", defaultValue: "Düzenleme Tarihi")) {
                        ProWorkDateField(date: $issueDate)
                    }
                }
            }
        } footer: {
            SettingsFormFooter(
                onCancel: { dismiss() },
                onSave: { submit() },
                cancelTitle: settingsStore.localized("common.cancel", defaultValue: "Vazgeç"),
                saveTitle: settingsStore.localized("quote.recipientSheet.action.generate", defaultValue: "PDF Oluştur"),
                saveSystemImage: "doc.text.fill",
                saveDisabled: !canSubmit
            )
        }
        .onAppear {
            if quoteNumber.isEmpty {
                quoteNumber = suggestedQuoteNumber
            }
            if let suggestedId = suggestedCustomerId,
               customers.contains(where: { $0.id == suggestedId }) {
                selectedCustomerId = suggestedId
                applyCustomer(id: suggestedId)
            } else {
                selectedCustomerId = manualOptionId
            }
        }
    }

    private var customerOptions: [CustomerOption] {
        var options: [CustomerOption] = [
            CustomerOption(
                id: manualOptionId,
                title: settingsStore.localized("quote.recipientSheet.field.customer.manual", defaultValue: "Manuel giriş"),
                subtitle: settingsStore.localized("quote.recipientSheet.field.customer.manual.subtitle", defaultValue: "Alıcı bilgilerini elle gir")
            )
        ]
        options.append(contentsOf: customers
            .filter(\.isActive)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { customer in
                CustomerOption(
                    id: customer.id,
                    title: customer.name,
                    subtitle: customer.code
                )
            }
        )
        return options
    }

    private func applyCustomer(id: String) {
        guard id != manualOptionId, let customer = customers.first(where: { $0.id == id }) else {
            return
        }
        recipientName = customer.name
        recipientCode = customer.code ?? ""
        contactPerson = customer.contactPerson ?? ""
        recipientAddress = customer.address ?? ""
    }

    private var canSubmit: Bool {
        !recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !quoteNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let recipient = PriceListQuoteBundleBuilder.RecipientInput(
            name: recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
            contactPerson: contactPerson.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            address: recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            code: recipientCode.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let result = Result(
            recipient: recipient,
            quoteNumber: quoteNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            issueDate: issueDate,
            sequenceConsumed: !manualQuoteNumber
        )
        dismiss()
        onSubmit(result)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .proWorkTextStyle(.headline)
            content()
        }
    }
}

private struct CustomerOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
