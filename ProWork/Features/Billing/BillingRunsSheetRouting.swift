//  BillingRunsSheetRouting.swift
//  ProWork
//  Single-source-of-truth sheet routing for BillingRunsView.
//  Extracted from the host view so the orchestration
//  file stays focused on action delegates.
//  the view used to carry five separate @State
//  flags / optionals plus four `.sheet(...)` modifiers — setting one
//  without explicitly clearing the others let the view briefly be in
//  an undefined "two sheets requested" state. `ActiveSheet` collapses
//  the four cases into one mutually-exclusive enum that drives a
//  single `.sheet(item:)`.

import Foundation

struct BillingRunsPaymentSheetContext: Identifiable {
    let id = UUID()
    let mode: PaymentFormView.Mode
}

struct BillingRunsDocumentInfoEditContext: Identifiable {
    let runId: String
    let referenceNumber: String
    let dueDate: Date
    var id: String { runId }
}

struct BillingRunsPdfPreviewDocument: Identifiable {
    let id = UUID()
    let title: String
    let data: Data
    let defaultFilename: String
}

enum BillingRunsActiveSheet: Identifiable {
    case create
    case payment(BillingRunsPaymentSheetContext)
    case documentInfo(BillingRunsDocumentInfoEditContext)
    case pdfPreview(BillingRunsPdfPreviewDocument)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .payment(let ctx):
            return "payment-\(ctx.id.uuidString)"
        case .documentInfo(let ctx):
            return "documentInfo-\(ctx.id)"
        case .pdfPreview(let doc):
            return "pdfPreview-\(doc.id.uuidString)"
        }
    }
}
