//  CustomerReportView.swift
//  ProWork
//  Created by Pronomi.
//  Spec §10–11: Period-detail report for a single customer.
//  Select customer + period → BillingComputationService → CustomerReport summary.

import SwiftUI

struct CustomerReportView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = CustomerReportViewModel()

    @State private var selectedCustomerId: String = ""
    @State private var range: DateRangeFilter = .thisMonth
    @State private var customStart: Date = AppCalendar.istanbul.date(from: AppCalendar.istanbul.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var customEnd: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            filtersCard

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView(settingsStore.localized("reports.loading", defaultValue: "Hesaplanıyor…"))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let report = viewModel.report {
                        summaryCard(report)
                        if !report.projectBreakdown.isEmpty {
                            projectSection(report)
                        }
                    } else {
                        emptyState
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
        .onChange(of: selectedCustomerId) { _, _ in recompute() }
        .onChange(of: range) { _, _ in recompute() }
        .onChange(of: customStart) { _, _ in if range == .custom { recompute() } }
        .onChange(of: customEnd) { _, _ in if range == .custom { recompute() } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settingsStore.localized("reports.customer.title", defaultValue: "Müşteri Raporu"))
                .proWorkTextStyle(.title2)
                .bold()

            Text(settingsStore.localized("reports.customer.subtitle", defaultValue: "Bir müşteri ve dönem seçerek detaylı süre + tutar kırılımı görüntüleyin."))
                .proWorkTextStyle(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filters

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsStore.localized("projects.form.customer", defaultValue: "Müşteri"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("reports.customer.filter.selectCustomer", defaultValue: "Müşteri seçin"),
                        items: customerOptions,
                        selectedId: $selectedCustomerId,
                        showsSearch: viewModel.customers.count > 6,
                        systemImage: "person.2",
                        itemTitle: { $0.title },
                        matchesSearch: { $0.title.localizedCaseInsensitiveContains($1) }
                    )
                    .frame(width: 280)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(settingsStore.localized("reports.filter.period", defaultValue: "Dönem"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                    ProWorkDateRangePicker(
                        range: $range,
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
        [PickerOption(id: "", title: settingsStore.localized("reports.customer.filter.selectCustomer", defaultValue: "Müşteri seçin"))] +
            viewModel.customers.map { PickerOption(id: $0.id, title: $0.name) }
    }

    // MARK: - Summary

    private func summaryCard(_ report: CustomerReport) -> some View {
        let s = report.summary
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.customerName)
                        .proWorkTextStyle(.title3, weight: .semibold)
                    Text(periodLabel)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(settingsStore.localized("reports.summary.totalAmount", defaultValue: "Toplam Tutar"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                    Text(ProWorkFormatters.money(Money(minorUnits: s.totalMinor, currency: s.currency)))
                        .proWorkTextStyle(.title2, weight: .bold)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Divider()

            // Durations block
            HStack(alignment: .top, spacing: 24) {
                metricColumn(settingsStore.localized("reports.customer.group.durations", defaultValue: "Süreler")) {
                    metricRow(settingsStore.localized("reports.customer.metric.totalActual", defaultValue: "Toplam gerçek"), ProWorkFormatters.durationHM(s.totalActualSeconds))
                    metricRow(settingsStore.localized("reports.customer.metric.billable", defaultValue: "Ücretlendirilecek"), durationFromMinutes(s.billableMinutes))
                    metricRow(settingsStore.localized("reports.customer.metric.chargeable", defaultValue: "Faturalandırılabilir"), ProWorkFormatters.durationHM(s.totalActualSeconds - s.nonBillableSeconds))
                    metricRow(settingsStore.localized("todos.administrative", defaultValue: "İdari"), ProWorkFormatters.durationHM(s.nonBillableSeconds))
                }
                Divider()
                metricColumn(settingsStore.localized("reports.customer.group.service", defaultValue: "Hizmet")) {
                    metricRow(settingsStore.localized("serviceType.remote", defaultValue: "Uzaktan"), ProWorkFormatters.durationHM(s.remoteSeconds))
                    metricRow(settingsStore.localized("serviceType.onsite", defaultValue: "Yerinde"), ProWorkFormatters.durationHM(s.onsiteSeconds))
                }
                Divider()
                metricColumn(settingsStore.localized("reports.customer.group.timeType", defaultValue: "Zaman Tipi")) {
                    metricRow(settingsStore.localized("timeType.regular", defaultValue: "Mesai içi"), ProWorkFormatters.durationHM(s.regularSeconds))
                    metricRow(settingsStore.localized("timeType.afterHours", defaultValue: "Mesai dışı"), ProWorkFormatters.durationHM(s.afterHoursSeconds))
                    metricRow(settingsStore.localized("timeType.weekend", defaultValue: "Hafta sonu"), ProWorkFormatters.durationHM(s.weekendSeconds))
                    metricRow(settingsStore.localized("timeType.holiday", defaultValue: "Tatil"), ProWorkFormatters.durationHM(s.holidaySeconds))
                }
                Divider()
                metricColumn(settingsStore.localized("reports.customer.group.sessions", defaultValue: "Kayıt")) {
                    metricRow(settingsStore.localized("workSessions.source.automatic", defaultValue: "Otomatik"), ProWorkFormatters.durationHM(s.automaticSeconds))
                    metricRow(settingsStore.localized("workSessions.source.manual", defaultValue: "Manuel"), ProWorkFormatters.durationHM(s.manualSeconds), highlight: s.manualSeconds > 0)
                    metricRow(settingsStore.localized("reports.customer.metric.manualCount", defaultValue: "Manuel adet"), "\(s.manualLineCount)")
                }
                Spacer()
            }

            Divider()

            // Mali toplamlar
            HStack(spacing: 24) {
                moneyMetric(settingsStore.localized("reports.summary.subtotal", defaultValue: "Ara Toplam (Net)"), Money(minorUnits: s.subtotalMinor, currency: s.currency))
                moneyMetric(settingsStore.localized("reports.summary.vat", defaultValue: "KDV"), Money(minorUnits: s.vatMinor, currency: s.currency))
                moneyMetric(settingsStore.localized("reports.summary.grandTotal", defaultValue: "Genel Toplam"), Money(minorUnits: s.totalMinor, currency: s.currency), prominent: true)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func metricColumn<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .proWorkFont(size: 10, weight: .semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func metricRow(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .proWorkTextStyle(.callout, weight: highlight ? .semibold : .regular)
                .foregroundStyle(highlight ? Color.orange : Color.primary)
        }
    }

    private func moneyMetric(_ label: String, _ money: Money, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
            Text(ProWorkFormatters.money(money))
                .proWorkTextStyle(prominent ? .title3 : .callout, weight: prominent ? .bold : .medium)
                .foregroundStyle(prominent ? Color.accentColor : Color.primary)
        }
    }

    // MARK: - Project breakdown

    private func projectSection(_ report: CustomerReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settingsStore.localized("reports.customer.projectBreakdown", defaultValue: "Proje Kırılımı"))
                .proWorkTextStyle(.headline)

            VStack(spacing: 0) {
                projectTableHeader
                Divider()
                ForEach(report.projectBreakdown, id: \.projectId) { project in
                    projectRow(project)
                    Divider()
                }
            }
            .background(.background)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var projectTableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("priceLists.owner.project", defaultValue: "Proje")).frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("reports.table.actual", defaultValue: "Gerçek")).frame(width: 90, alignment: .trailing)
            Text(settingsStore.localized("reports.table.billable", defaultValue: "Ücretli")).frame(width: 90, alignment: .trailing)
            Text(settingsStore.localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 140, alignment: .trailing)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func projectRow(_ project: ProjectBreakdown) -> some View {
        let s = project.summary
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.projectName)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .lineLimit(1)
                Text(String(format: settingsStore.localized("reports.customer.todoCount", defaultValue: "%d iş"), project.todoBreakdown.count))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ProWorkFormatters.durationHM(s.totalActualSeconds))
                .proWorkTextStyle(.callout)
                .frame(width: 90, alignment: .trailing)

            Text(durationFromMinutes(s.billableMinutes))
                .proWorkTextStyle(.callout)
                .frame(width: 90, alignment: .trailing)

            Text(ProWorkFormatters.money(Money(minorUnits: s.totalMinor, currency: s.currency)))
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.gobackward")
                .proWorkFont(size: 32)
                .foregroundStyle(.secondary)
            Text(
                selectedCustomerId.isEmpty
                ? settingsStore.localized("reports.customer.empty.selectCustomer", defaultValue: "Müşteri seçin")
                : settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok")
            )
                .proWorkTextStyle(.headline)
            Text(settingsStore.localized("reports.customer.empty.message", defaultValue: "Sol üstten müşteri ve dönem seçtiğinizde detaylı rapor burada görünecek."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    // MARK: - Period

    private var periodStart: Date {
        range.startDate(custom: customStart)
    }

    private var periodEnd: Date {
        range.endDate(custom: customEnd)
    }

    private var periodLabel: String {
        switch range {
        case .all:
            return settingsStore.localized("reports.period.all", defaultValue: "Tüm dönem")
        default:
            let start = settingsStore.formatDate(periodStart)
            let end = settingsStore.formatDate(AppCalendar.istanbul.date(byAdding: .day, value: -1, to: periodEnd) ?? periodEnd)
            return "\(start) – \(end)"
        }
    }

    private func durationFromMinutes(_ minutes: Int) -> String {
        ProWorkFormatters.durationHM(minutes * 60)
    }

    // MARK: - Actions

    private func recompute() {
        viewModel.compute(
            selectedCustomerId: selectedCustomerId,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }
}
