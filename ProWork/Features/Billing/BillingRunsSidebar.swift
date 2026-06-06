//  BillingRunsSidebar.swift
//  ProWork
//  Left-hand sidebar of BillingRunsView: header row with delete-draft
//  affordance, scrollable list of run rows, empty state. Extracted from
//  BillingRunsView so the sidebar only re-renders
//  when its bound inputs change.

import SwiftUI

struct BillingRunsSidebar: View {
    let runs: [BillingReportRun]
    let selectedRunId: String?
    let customerLookup: [String: Customer]
    let selectedRunIsDraft: Bool
    let displayPeriod: (String, String) -> String
    let onSelectRun: (String) -> Void
    let onDeleteSelectedDraft: () -> Void

    @EnvironmentObject private var settingsStore: AppSettingsStore

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(localized("billing.sidebar.runs", defaultValue: "Kayıtlar")) (\(runs.count))")
                    .proWorkTextStyle(.headline)
                Spacer()

                if selectedRunIsDraft {
                    Button(role: .destructive, action: onDeleteSelectedDraft) {
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
                            row(run)
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

    private func row(_ run: BillingReportRun) -> some View {
        // The row body only sees the inputs it cares
        // about (resolved customer name, selection flag, tap callback),
        // so SwiftUI doesn't re-evaluate the row whenever an unrelated
        // viewModel publisher fires.
        // if the customer was deleted between finalize and
        // this render (rare but real for archived workspaces), fall
        // back to a localised "deleted customer" label instead of
        // exposing the raw UUID. The run.title already carries the
        // user's chosen label in most cases; this just covers the
        // path where the sidebar falls through to customerName.
        let resolvedCustomerName = customerLookup[run.customerId]?.name
            ?? ProWorkLocalizer.shared.string(
                "billing.customer.deletedFallback",
                defaultValue: "Silinmiş müşteri"
            )
        return BillingRunSidebarRowView(
            run: run,
            customerName: resolvedCustomerName,
            isSelected: selectedRunId == run.id,
            displayPeriod: displayPeriod(run.periodStart, run.periodEnd),
            invoiceNumber: run.invoiceNumber,
            statusChip: { BillingRunStatusChip(status: run.status) },
            paymentStatusChip: { BillingPaymentStatusChip(status: run.paymentStatus) },
            onSelect: { onSelectRun(run.id) }
        )
    }
}

/// Extracted from BillingRunsView so the row's body only
/// re-evaluates when its bound inputs change, instead of every time any
/// state on the parent view's `viewModel` publishes.
struct BillingRunSidebarRowView<StatusChip: View, PaymentStatusChip: View>: View {
    let run: BillingReportRun
    let customerName: String
    let isSelected: Bool
    let displayPeriod: String
    let invoiceNumber: String?
    let statusChip: () -> StatusChip
    let paymentStatusChip: () -> PaymentStatusChip
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.title ?? customerName)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .lineLimit(2)
                Spacer(minLength: 8)
                statusChip()
            }

            Text(customerName)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Text(displayPeriod)
                Spacer()
                Text(ProWorkFormatters.money(run.total))
            }
            .proWorkTextStyle(.caption)
            .foregroundStyle(.secondary)

            HStack {
                paymentStatusChip()
                Spacer()
                if let invoiceNumber {
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
        .onTapGesture(perform: onSelect)
    }
}
