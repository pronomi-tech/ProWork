//  BillingPdfPreviewSheet.swift
//  ProWork
//   Created by Pronomi.

import PDFKit
import SwiftUI

struct BillingPdfPreviewSheet: View {
    let title: String
    let data: Data
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .proWorkTextStyle(.headline)
                    Text(localized("billing.preview.subtitle", defaultValue: "Canlı PDF önizleme"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    ProWorkButtonLabel(title: localized("common.close", defaultValue: "Kapat"), systemImage: "xmark", minHeight: 30)
                }
                .buttonStyle(.bordered)

                Button {
                    onSave()
                } label: {
                    ProWorkButtonLabel(title: localized("billing.preview.savePdf", defaultValue: "PDF Kaydet"), systemImage: "square.and.arrow.down", minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)

            Divider()

            BillingPdfPreviewDocumentView(data: data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

private struct BillingPdfPreviewDocumentView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(data: data)
    }
}
