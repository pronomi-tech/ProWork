//  PaymentFormView.swift
//  ProWork
//   Created by Pronomi.

import SwiftUI

struct PaymentFormView: View {
    enum Mode {
        case create(currency: String)
        case edit(Payment)

        func title(using settingsStore: AppSettingsStore) -> String {
            switch self {
            case .create:
                return settingsStore.localized("billing.paymentForm.createTitle", defaultValue: "Ödeme Ekle")
            case .edit:
                return settingsStore.localized("billing.paymentForm.editTitle", defaultValue: "Ödeme Düzenle")
            }
        }

        var currency: String {
            switch self {
            case .create(let currency): return currency
            case .edit(let payment): return payment.currency
            }
        }
    }

    let mode: Mode
    let onSave: (Date, Int, String, PaymentMethod, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var paidAt: Date
    @State private var amountText: String
    @State private var currency: String
    @State private var method: PaymentMethod
    @State private var reference: String
    @State private var note: String
    @State private var errorMessage: String?

    /// With fixed, `Currency.allCodes` now derives
    /// from `Currency.registry.keys` (8 codes), so the workaround is
    /// no longer needed to surface CHF/JPY/AED/SAR. The append-if-
    /// missing branch stays around for runs that persisted a truly
    /// non-standard ISO code (e.g. a future BRL that pre-dates
    /// registry support) so the picker doesn't strip it.
    private var currencyOptions: [PickerOption] {
        let codes = if Currency.allCodes.contains(currency) {
            Currency.allCodes
        } else {
            Currency.allCodes + [currency]
        }

        return codes.map {
            PickerOption(id: $0, title: "\($0) — \(Currency.info(for: $0).displayName)")
        }
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    init(
        mode: Mode,
        onSave: @escaping (Date, Int, String, PaymentMethod, String?, String?) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .create:
            _paidAt = State(initialValue: Date())
            _amountText = State(initialValue: "")
            _currency = State(initialValue: mode.currency)
            _method = State(initialValue: .bankTransfer)
            _reference = State(initialValue: "")
            _note = State(initialValue: "")
        case .edit(let payment):
            _paidAt = State(initialValue: payment.paidAt)
            _amountText = State(initialValue: ProWorkFormatters.moneyAmount(payment.amount))
            _currency = State(initialValue: payment.currency)
            _method = State(initialValue: payment.method)
            _reference = State(initialValue: payment.reference ?? "")
            _note = State(initialValue: payment.note ?? "")
        }
    }

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: localized("billing.paymentForm.subtitle", defaultValue: "Tahsilat kaydı"),
            systemImage: "creditcard",
            width: FormSheetSize.paymentForm.width,
            height: FormSheetSize.paymentForm.height
        ) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                SettingsFormError(message: errorMessage)

                SettingsFormRow(localized("billing.paymentForm.paidAt", defaultValue: "Ödeme Tarihi"), required: true) {
                    ProWorkDateField(title: "", date: $paidAt)
                        .frame(maxWidth: 220)
                }

                SettingsFormRow(localized("reports.table.amount", defaultValue: "Tutar"), required: true) {
                    ProWorkNumberField(
                        placeholder: "0,00",
                        text: $amountText,
                        style: .decimal(maxFractionDigits: 4)
                    )
                    .frame(width: ProWorkLayout.formScaled(180, using: settingsStore))
                }

                SettingsFormRow(localized("export.column.currency", defaultValue: "Para Birimi"), required: true) {
                    ProWorkSearchPickerField(
                        placeholder: "TRY",
                        items: currencyOptions,
                        selectedId: $currency,
                        showsSearch: true,
                        systemImage: "banknote",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in
                            item.title.localizedCaseInsensitiveContains(text)
                        }
                    )
                    .frame(maxWidth: 320)
                }

                SettingsFormRow(localized("payment.column.method", defaultValue: "Yöntem"), required: true) {
                    ProWorkSearchPickerField(
                        placeholder: localized("billing.paymentForm.methodPlaceholder", defaultValue: "Yöntem seçin"),
                        items: PaymentMethod.allCases,
                        selectedId: Binding(
                            get: { method.rawValue },
                            set: { method = PaymentMethod(rawValue: $0) ?? .bankTransfer }
                        ),
                        isDisabled: false,
                        showsSearch: false,
                        systemImage: "creditcard",
                        itemTitle: { $0.title },
                        itemSubtitle: { $0.rawValue },
                        matchesSearch: { item, text in
                            item.title.localizedCaseInsensitiveContains(text)
                        }
                    )
                    .frame(maxWidth: 280)
                }

                SettingsFormRow(localized("payment.column.reference", defaultValue: "Referans")) {
                    ProWorkTextField(
                        placeholder: localized("billing.paymentForm.referencePlaceholder", defaultValue: "Dekont / işlem referansı"),
                        text: $reference
                    )
                    .frame(maxWidth: 340)
                }

                SettingsFormRow(localized("vat.form.note", defaultValue: "Not"), alignment: .top) {
                    ProWorkTextEditor(
                        placeholder: localized("billing.paymentForm.notePlaceholder", defaultValue: "Opsiyonel not"),
                        text: $note,
                        minHeight: 80
                    )
                    .frame(maxWidth: 480)
                }

                Spacer(minLength: 0)
            }
        } footer: {
            SettingsFormFooter(onCancel: { dismiss() }, onSave: save)
        }
    }

    private func save() {
        guard let amountMinor = parseMinorUnits(
            from: amountText,
            currency: currency
        ) else {
            errorMessage = localized("billing.paymentForm.error.invalidAmount", defaultValue: "Tutar geçerli değil.")
            return
        }

        // Payment day is the TR accounting day — independent of the device TZ (K3).
        let paidDate = AppCalendar.istanbul.startOfDay(for: paidAt)

        onSave(
            paidDate,
            amountMinor,
            currency,
            method,
            reference.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        dismiss()
    }

    /// Parse via the active locale's decimal formatter
    /// instead of TR-specific `.` / `,` swapping. The previous logic
    /// treated `1.000` as one thousand under TR conventions but the
    /// same input from an en-US user (where `.` is the decimal
    /// separator) meant 1.000 = one. We try the locale formatter
    /// first, then fall back to POSIX (canonical machine form) so
    /// `1000.50` always parses regardless of locale.
    private func parseMinorUnits(from text: String, currency: String) -> Int? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let localeFormatter = ProWorkFormatters.cachedDecimalFormatter(
            localeIdentifier: settingsStore.locale.identifier,
            minimumFractionDigits: 0,
            maximumFractionDigits: 6
        )
        if let number = localeFormatter.number(from: raw)?.decimalValue, number >= 0 {
            return Money(amount: number, currency: currency).minorUnits
        }
        if let posix = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), posix >= 0 {
            return Money(amount: posix, currency: currency).minorUnits
        }
        return nil
    }
}