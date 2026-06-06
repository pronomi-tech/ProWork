//  BillingStatusChips.swift
//  ProWork
//  Capsule chips for BillingRunStatus and PaymentStatus. Extracted from
//  BillingRunsView so the sidebar and the detail
//  panel can share a single visual definition instead of each carrying
//  its own colour-resolution copy.

import SwiftUI

struct BillingRunStatusChip: View {
    let status: BillingRunStatus

    var body: some View {
        Text(status.title)
            .proWorkTextStyle(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .draft: return .orange
        case .final: return .green
        case .cancelled: return .red
        }
    }
}

struct BillingPaymentStatusChip: View {
    let status: PaymentStatus

    var body: some View {
        Text(status.title)
            .proWorkTextStyle(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .unpaid: return .secondary
        case .partial: return .orange
        case .paid: return .green
        case .overdue: return .red
        }
    }
}
