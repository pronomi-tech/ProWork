//  BillingRunDocumentInfoSheet.swift
//  ProWork
//  Extracted from BillingRunsView. Inline reference
//  number + due-date editor for an existing billing run; the host view
//  only needs a typed `onSave` callback so the sheet is fully
//  self-contained.

import SwiftUI

struct BillingRunDocumentInfoSheet: View {
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
