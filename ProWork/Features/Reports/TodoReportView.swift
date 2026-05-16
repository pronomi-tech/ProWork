//
//  TodoReportView.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Spec §13 — Her yapılacak iş için süre + tutar kırılımı.
//  Manuel kayıtlar (§14) görünür şekilde işaretlenir.
//

import SwiftUI

struct TodoReportView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = TodoReportViewModel()

    @State private var customerFilter: String = ""
    @State private var period: DateRangeFilter = .thisMonth
    @State private var customStart: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var manualOnly: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            filtersCard

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView(settingsStore.localized("reports.loading", defaultValue: "Hesaplanıyor…"))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if filteredRows.isEmpty {
                        emptyState
                    } else {
                        summary
                        table
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.loadCustomers()
            recompute()
        }
        .onChange(of: customerFilter) { _, _ in recompute() }
        .onChange(of: period) { _, _ in recompute() }
        .onChange(of: customStart) { _, _ in if period == .custom { recompute() } }
        .onChange(of: customEnd) { _, _ in if period == .custom { recompute() } }
    }

    private var filteredRows: [TodoReportRow] {
        manualOnly ? viewModel.rows.filter { $0.hasManual } : viewModel.rows
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settingsStore.localized("reports.todo.title", defaultValue: "İş Raporu"))
                .proWorkTextStyle(.title2)
                .bold()
            Text(settingsStore.localized("reports.todo.subtitle", defaultValue: "Her yapılacak iş için süre, tutar ve manuel/otomatik vurgu."))
                .proWorkTextStyle(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsStore.localized("reports.filter.customerOptional", defaultValue: "Müşteri (opsiyonel)"))
                        .proWorkTextStyle(.caption).foregroundStyle(.secondary)
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("dateRange.all", defaultValue: "Tümü"),
                        items: customerOptions,
                        selectedId: $customerFilter,
                        showsSearch: viewModel.customers.count > 6,
                        systemImage: "person.2",
                        itemTitle: { $0.title },
                        matchesSearch: { $0.title.localizedCaseInsensitiveContains($1) }
                    )
                    .frame(width: 280)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsStore.localized("reports.filter.period", defaultValue: "Dönem"))
                        .proWorkTextStyle(.caption).foregroundStyle(.secondary)
                    ProWorkDateRangePicker(
                        range: $period,
                        customStart: $customStart,
                        customEnd: $customEnd
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsStore.localized("common.filter", defaultValue: "Filtrele"))
                        .proWorkTextStyle(.caption).foregroundStyle(.secondary)
                    Toggle(settingsStore.localized("reports.todo.filter.manualOnly", defaultValue: "Yalnızca manuel kayıtlı"), isOn: $manualOnly)
                        .toggleStyle(.switch)
                        .proWorkTextStyle(.callout)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var customerOptions: [PickerOption] {
        [PickerOption(id: "", title: settingsStore.localized("dateRange.all", defaultValue: "Tümü"))] +
            viewModel.customers.map { PickerOption(id: $0.id, title: $0.name) }
    }

    private var summary: some View {
        let visible = filteredRows
        let totalActual = visible.reduce(0) { $0 + $1.actualSeconds }
        let totalManual = visible.reduce(0) { $0 + $1.manualSeconds }
        let totalAmount = visible.reduce(0) { $0 + $1.totalMinor }
        let currency = visible.first?.currency ?? "TRY"

        return HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settingsStore.localized("reports.todo.summary.todoCount", defaultValue: "İş Sayısı")).proWorkTextStyle(.caption).foregroundStyle(.secondary)
                Text("\(visible.count)").proWorkTextStyle(.title3, weight: .semibold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(settingsStore.localized("workSessions.summary.totalTime", defaultValue: "Toplam Süre")).proWorkTextStyle(.caption).foregroundStyle(.secondary)
                Text(ProWorkFormatters.durationHM(totalActual)).proWorkTextStyle(.title3, weight: .semibold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(settingsStore.localized("reports.todo.summary.manualTime", defaultValue: "Manuel Süre")).proWorkTextStyle(.caption).foregroundStyle(.secondary)
                Text(ProWorkFormatters.durationHM(totalManual))
                    .proWorkTextStyle(.title3, weight: .semibold)
                    .foregroundStyle(totalManual > 0 ? .orange : .primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(settingsStore.localized("reports.summary.totalAmount", defaultValue: "Toplam Tutar")).proWorkTextStyle(.caption).foregroundStyle(.secondary)
                Text(ProWorkFormatters.money(Money(minorUnits: totalAmount, currency: currency)))
                    .proWorkTextStyle(.title3, weight: .bold)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var table: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            ForEach(filteredRows) { row in
                tableRow(row)
                Divider()
            }
        }
        .background(.background)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("reports.todo.table.todo", defaultValue: "İş")).frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("workSessions.column.customerProject", defaultValue: "Müşteri / Proje")).frame(width: 220, alignment: .leading)
            Text(settingsStore.localized("reports.todo.table.category", defaultValue: "Kategori")).frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("reports.table.actual", defaultValue: "Gerçek")).frame(width: 80, alignment: .trailing)
            Text(settingsStore.localized("reports.table.billable", defaultValue: "Ücretli")).frame(width: 80, alignment: .trailing)
            Text(settingsStore.localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 130, alignment: .trailing)
            Text(settingsStore.localized("workSessions.source.manual", defaultValue: "Manuel")).frame(width: 70, alignment: .center)
        }
        .proWorkTextStyle(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func tableRow(_ row: TodoReportRow) -> some View {
        HStack(spacing: 12) {
            Text(row.todoTitle)
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.customerName)
                    .proWorkTextStyle(.caption)
                    .lineLimit(1)
                if let p = row.projectName {
                    Text(p)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 220, alignment: .leading)

            Text(row.categoryName ?? settingsStore.localized("reports.common.none", defaultValue: "—"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading).lineLimit(1)

            Text(ProWorkFormatters.durationHM(row.actualSeconds))
                .proWorkTextStyle(.callout)
                .frame(width: 80, alignment: .trailing)

            Text(ProWorkFormatters.durationHM(row.billableMinutes * 60))
                .proWorkTextStyle(.callout)
                .frame(width: 80, alignment: .trailing)

            Text(ProWorkFormatters.money(Money(minorUnits: row.totalMinor, currency: row.currency)))
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(width: 130, alignment: .trailing)

            HStack(spacing: 4) {
                if row.hasManual {
                    Image(systemName: "hand.point.up.left.fill")
                        .proWorkFont(size: 11)
                        .foregroundStyle(.orange)
                    Text("\(row.manualLineCount)")
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(settingsStore.localized("reports.common.none", defaultValue: "—"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, alignment: .center)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .proWorkFont(size: 32)
                .foregroundStyle(.secondary)
            Text(
                manualOnly
                ? settingsStore.localized("reports.todo.empty.manualOnly", defaultValue: "Manuel kayıt yok")
                : settingsStore.localized("reports.todo.empty.title", defaultValue: "Bu dönemde iş kaydı yok")
            )
                .proWorkTextStyle(.headline)
            Text(settingsStore.localized("reports.empty.tryPeriodOrCustomer", defaultValue: "Filtreleri değiştirerek farklı bir dönem veya müşteri deneyin."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Actions

    private func recompute() {
        viewModel.compute(
            period: period,
            customStart: customStart,
            customEnd: customEnd,
            customerFilter: customerFilter
        )
    }
}

struct TodoReportRow: Identifiable, Hashable {
    let id: String
    let todoId: String
    let todoTitle: String
    let customerId: String
    let customerName: String
    let projectId: String?
    let projectName: String?
    let categoryName: String?
    let actualSeconds: Int
    let billableMinutes: Int
    let manualSeconds: Int
    let manualLineCount: Int
    let subtotalMinor: Int
    let vatMinor: Int
    let totalMinor: Int
    let currency: String

    var hasManual: Bool { manualLineCount > 0 }
}
