//
//  ProjectReportView.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Spec §12 — Tüm projelerin dönem bazlı kırılımı.
//  Opsiyonel müşteri filtresi ile sınırlandırılabilir.
//

import SwiftUI

struct ProjectReportView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var customers: [Customer] = []
    @State private var customerFilter: String = ""
    @State private var period: DateRangeFilter = .thisMonth
    @State private var customStart: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var customEnd: Date = Date()

    @State private var rows: [ProjectReportRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let customerRepository = CustomerRepository()
    private let computation = BillingComputationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            filtersCard

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        ProgressView(settingsStore.localized("reports.loading", defaultValue: "Hesaplanıyor…"))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if rows.isEmpty {
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
        .proWorkToastNotifications(errorMessage: errorMessage)
        .onAppear { load() }
        .onChange(of: customerFilter) { _, _ in compute() }
        .onChange(of: period) { _, _ in compute() }
        .onChange(of: customStart) { _, _ in if period == .custom { compute() } }
        .onChange(of: customEnd) { _, _ in if period == .custom { compute() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settingsStore.localized("reports.project.title", defaultValue: "Proje Raporu"))
                .proWorkTextStyle(.title2)
                .bold()
            Text(settingsStore.localized("reports.project.subtitle", defaultValue: "Dönem içerisinde her projenin toplam süresi ve tutarı."))
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
                        showsSearch: customers.count > 6,
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
                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var customerOptions: [PickerOption] {
        [PickerOption(id: "", title: settingsStore.localized("dateRange.all", defaultValue: "Tümü"))] +
            customers.map { PickerOption(id: $0.id, title: $0.name) }
    }

    private var summary: some View {
        let totalActual = rows.reduce(0) { $0 + $1.actualSeconds }
        let totalAmount = rows.reduce(0) { $0 + $1.totalMinor }
        let currency = rows.first?.currency ?? "TRY"
        return HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settingsStore.localized("reports.project.summary.projectCount", defaultValue: "Proje Sayısı")).proWorkTextStyle(.caption).foregroundStyle(.secondary)
                Text("\(rows.count)").proWorkTextStyle(.title3, weight: .semibold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(settingsStore.localized("workSessions.summary.totalTime", defaultValue: "Toplam Süre")).proWorkTextStyle(.caption).foregroundStyle(.secondary)
                Text(ProWorkFormatters.durationHM(totalActual)).proWorkTextStyle(.title3, weight: .semibold)
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
            ForEach(rows) { row in
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
            Text(settingsStore.localized("projects.form.customer", defaultValue: "Müşteri")).frame(width: 200, alignment: .leading)
            Text(settingsStore.localized("priceLists.owner.project", defaultValue: "Proje")).frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("reports.table.actual", defaultValue: "Gerçek")).frame(width: 90, alignment: .trailing)
            Text(settingsStore.localized("reports.table.billable", defaultValue: "Ücretli")).frame(width: 90, alignment: .trailing)
            Text(settingsStore.localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 140, alignment: .trailing)
        }
        .proWorkTextStyle(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func tableRow(_ row: ProjectReportRow) -> some View {
        HStack(spacing: 12) {
            Text(row.customerName)
                .proWorkTextStyle(.callout)
                .frame(width: 200, alignment: .leading).lineLimit(1)
            Text(row.projectName)
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(ProWorkFormatters.durationHM(row.actualSeconds))
                .proWorkTextStyle(.callout)
                .frame(width: 90, alignment: .trailing)
            Text(ProWorkFormatters.durationHM(row.billableMinutes * 60))
                .proWorkTextStyle(.callout)
                .frame(width: 90, alignment: .trailing)
            Text(ProWorkFormatters.money(Money(minorUnits: row.totalMinor, currency: row.currency)))
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .proWorkFont(size: 32)
                .foregroundStyle(.secondary)
            Text(settingsStore.localized("reports.project.empty.title", defaultValue: "Bu dönemde proje kaydı yok"))
                .proWorkTextStyle(.headline)
            Text(settingsStore.localized("reports.empty.tryFilters", defaultValue: "Filtreleri değiştirerek farklı bir dönem deneyin."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Actions

    private func load() {
        do {
            customers = try customerRepository.fetchAll()
            compute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func compute() {
        isLoading = true
        errorMessage = nil
        do {
            let lines = try computation.computePeriod(
                from: period.startDate(custom: customStart),
                to: period.endDate(custom: customEnd)
            )
            let filteredLines = customerFilter.isEmpty ? lines : lines.filter { $0.customerId == customerFilter }

            // Proje bazlı grupla
            let grouped = Dictionary(grouping: filteredLines) {
                "\($0.customerId)|\($0.projectId ?? "_none")"
            }

            rows = grouped.map { _, lines -> ProjectReportRow in
                let first = lines[0]
                return ProjectReportRow(
                    id: "\(first.customerId)|\(first.projectId ?? "_none")",
                    customerId: first.customerId,
                    customerName: first.customerName,
                    projectId: first.projectId,
                    projectName: first.projectName ?? settingsStore.localized("reports.project.noProject", defaultValue: "Projesiz"),
                    actualSeconds: lines.reduce(0) { $0 + $1.actualSeconds },
                    billableMinutes: lines.reduce(0) { $0 + $1.billableMinutes },
                    subtotalMinor: lines.reduce(0) { $0 + $1.amountMinor },
                    vatMinor: lines.reduce(0) { $0 + $1.vatMinor },
                    totalMinor: lines.reduce(0) { $0 + $1.totalMinor },
                    currency: first.currency
                )
            }
            .sorted {
                if $0.customerName != $1.customerName {
                    return $0.customerName.localizedCompare($1.customerName) == .orderedAscending
                }
                return $0.projectName.localizedCompare($1.projectName) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
            rows = []
        }
        isLoading = false
    }
}

struct ProjectReportRow: Identifiable, Hashable {
    let id: String
    let customerId: String
    let customerName: String
    let projectId: String?
    let projectName: String
    let actualSeconds: Int
    let billableMinutes: Int
    let subtotalMinor: Int
    let vatMinor: Int
    let totalMinor: Int
    let currency: String
}
