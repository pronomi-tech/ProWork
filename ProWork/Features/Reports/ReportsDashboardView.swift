//  ReportsView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct ReportsDashboardView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = ReportsDashboardViewModel()

    @State private var filterRange: DateRangeFilter = .thisMonth
    @State private var filterStartDate: Date = AppCalendar.istanbul.date(from: AppCalendar.istanbul.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var filterEndDate: Date = Date()
    @State private var filterCustomerId: String = ""
    @State private var filterProjectId: String = ""
    /// Cache backing.
    @State private var cachedCustomerFilterOptions: [FilterOption] = []
    @State private var cachedProjectFilterOptions: [FilterOption] = []
    @State private var isShowingFilters: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            header

            filterBar

            if isShowingFilters {
                filterPanel
            }

            ScrollView {
                VStack(alignment: .leading, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
                    overviewCards

                    breakdownCharts

                    HStack(alignment: .top, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                        customerBreakdown
                        billableBreakdown
                    }

                    projectBreakdown

                    todoBreakdown
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, ProWorkLayout.scaled(24, using: settingsStore))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.loadData()
            rebuildFilterOptionCaches()
            recompute()
        }
        .onChange(of: filterRange) { _, _ in recompute() }
        .onChange(of: filterStartDate) { _, _ in if filterRange == .custom { recompute() } }
        .onChange(of: filterEndDate) { _, _ in if filterRange == .custom { recompute() } }
        .onChange(of: filterCustomerId) { _, _ in
            rebuildFilterOptionCaches()
            recompute()
        }
        .onChange(of: filterProjectId) { _, _ in recompute() }
        .onChange(of: viewModel.customers) { _, _ in rebuildFilterOptionCaches() }
        .onChange(of: viewModel.projects) { _, _ in rebuildFilterOptionCaches() }
    }

    /// Re-runs the VM's filtered / breakdown sets whenever a filter or
    /// the data changes. The view body only reads from the VM's cache,
    /// so search-picker keystrokes don't re-run O(n·sessions) work.
    private func recompute() {
        let labels = ReportsDashboardViewModel.LabelBundle(
            noCustomerTitle: settingsStore.localized("home.pie.noCustomer", defaultValue: "Müşterisiz"),
            noProjectFormat: settingsStore.localized("reports.dashboard.project.noProject", defaultValue: "%@ (Proje yok)"),
            administrativeTitle: settingsStore.localized("todos.administrative", defaultValue: "İdari"),
            unknownCategoryTitle: settingsStore.localized("home.pie.unknownCategory", defaultValue: "Kategorisiz"),
            otherTitle: settingsStore.localized("home.pie.other", defaultValue: "Diğer"),
            billableTitle: settingsStore.localized("reports.dashboard.breakdown.billable", defaultValue: "Faturalandırılabilir")
        )
        viewModel.recompute(
            range: filterRange,
            customStart: filterStartDate,
            customEnd: filterEndDate,
            customerId: filterCustomerId,
            projectId: filterProjectId,
            labels: labels
        )
    }

    private var hasActiveFilters: Bool {
        filterRange != .thisMonth ||
        !filterCustomerId.isEmpty ||
        !filterProjectId.isEmpty
    }

    private func clearFilters() {
        filterRange = .thisMonth
        filterStartDate = AppCalendar.istanbul.date(from: AppCalendar.istanbul.dateComponents([.year, .month], from: Date())) ?? Date()
        filterEndDate = Date()
        filterCustomerId = ""
        filterProjectId = ""
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("reports.dashboard.title", defaultValue: "Raporlar"))
                    .proWorkTextStyle(.largeTitle)

                Text(settingsStore.localized("reports.dashboard.subtitle", defaultValue: "Çalışma sürelerinizi müşteri, proje ve iş bazında analiz edin."))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingFilters.toggle()
                }
            } label: {
                HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .proWorkFont(size: 15)
                        .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.secondary)

                    Text(settingsStore.localized("common.filter", defaultValue: "Filtrele"))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.primary)
                }
                .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                .background(hasActiveFilters ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore)))
            }
            .buttonStyle(.plain)

            ProWorkDateRangePicker(
                range: $filterRange,
                customStart: $filterStartDate,
                customEnd: $filterEndDate,
                defaultRange: .thisMonth
            )

            if hasActiveFilters {
                Button {
                    clearFilters()
                } label: {
                    HStack(spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                        Image(systemName: "xmark")
                            .proWorkFont(size: 11)
                        Text(settingsStore.localized("common.clear", defaultValue: "Temizle"))
                            .proWorkTextStyle(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
                    .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(String(format: settingsStore.localized("common.recordCount", defaultValue: "%d kayıt"), viewModel.filteredSessions.count))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter Panel

    /// Dropdown options now live in @State so they only
    /// rebuild when their inputs (`customers`, `projects`,
    /// `filterCustomerId`) actually change. The previous computed
    /// vars re-ran on every body eval — date-picker drag was
    /// recomputing the customer options on each render frame.
    private var customerFilterOptions: [FilterOption] {
        cachedCustomerFilterOptions
    }

    private var projectFilterOptions: [FilterOption] {
        cachedProjectFilterOptions
    }

    private func rebuildFilterOptionCaches() {
        let allTitle = settingsStore.localized("dateRange.all", defaultValue: "Tümü")
        cachedCustomerFilterOptions =
            [FilterOption(id: "", title: allTitle)]
            + viewModel.customers.map { FilterOption(id: $0.id, title: $0.name) }
        let scopedProjects = filterCustomerId.isEmpty
            ? viewModel.projects
            : viewModel.projects.filter { $0.customerId == filterCustomerId }
        cachedProjectFilterOptions =
            [FilterOption(id: "", title: allTitle)]
            + scopedProjects.map { FilterOption(id: $0.id, title: $0.name) }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
                filterColumn(label: settingsStore.localized("projects.form.customer", defaultValue: "Müşteri")) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("dateRange.all", defaultValue: "Tümü"),
                        items: customerFilterOptions,
                        selectedId: $filterCustomerId,
                        isDisabled: false,
                        showsSearch: viewModel.customers.count > 8,
                        systemImage: "person.2",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.scaled(180, using: settingsStore))
                }

                filterColumn(label: settingsStore.localized("priceLists.owner.project", defaultValue: "Proje")) {
                    ProWorkSearchPickerField(
                        placeholder: settingsStore.localized("dateRange.all", defaultValue: "Tümü"),
                        items: projectFilterOptions,
                        selectedId: $filterProjectId,
                        isDisabled: false,
                        showsSearch: projectFilterOptions.count > 9,
                        systemImage: "folder",
                        itemTitle: { $0.title },
                        matchesSearch: { item, text in item.title.localizedCaseInsensitiveContains(text) }
                    )
                    .frame(width: ProWorkLayout.scaled(180, using: settingsStore))
                }

                Spacer(minLength: 0)
            }

        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func filterColumn<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            content()
        }
    }

    // MARK: - Overview Cards

    private var overviewCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
                overviewCard(
                    title: settingsStore.localized("workSessions.summary.totalTime", defaultValue: "Toplam Süre"),
                    value: ProWorkFormatters.durationHHmm(viewModel.totalSeconds),
                    subtitle: String(format: settingsStore.localized("common.recordCount", defaultValue: "%d kayıt"), viewModel.filteredSessions.count),
                    systemImage: "clock.fill",
                    color: .blue
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.manual", defaultValue: "Manuel Kayıtlar"),
                    value: ProWorkFormatters.durationHHmm(viewModel.manualSeconds),
                    subtitle: String(format: settingsStore.localized("reports.dashboard.card.manualCount", defaultValue: "%d manuel"), viewModel.filteredSessions.filter(\.isManual).count),
                    systemImage: "hand.point.up.left.fill",
                    color: .orange
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.automatic", defaultValue: "Otomatik Kayıtlar"),
                    value: ProWorkFormatters.durationHHmm(viewModel.automaticSeconds),
                    subtitle: String(format: settingsStore.localized("reports.dashboard.card.automaticCount", defaultValue: "%d otomatik"), viewModel.filteredSessions.filter { !$0.isManual }.count),
                    systemImage: "play.fill",
                    color: .green
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.customerCount", defaultValue: "Müşteri Sayısı"),
                    value: "\(viewModel.uniqueCustomerCount)",
                    subtitle: settingsStore.localized("reports.dashboard.card.uniqueCustomer", defaultValue: "farklı müşteri"),
                    systemImage: "person.2.fill",
                    color: .purple
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.projectCount", defaultValue: "Proje Sayısı"),
                    value: "\(viewModel.uniqueProjectCount)",
                    subtitle: settingsStore.localized("reports.dashboard.card.uniqueProject", defaultValue: "farklı proje"),
                    systemImage: "folder.fill",
                    color: .cyan
                )
            }
        }
    }

    private func overviewCard(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 18)
                    .foregroundStyle(color)
                    .frame(width: ProWorkLayout.scaled(24, using: settingsStore))

                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .proWorkFont(size: 26, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(subtitle)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(200, using: settingsStore), alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - Customer Breakdown

    /// Extracted card builders to share between the
    /// horizontal and vertical branches of the ViewThatFits. The
    /// previous code duplicated each card's full configuration, so a
    /// localiser key change had to land in two places.
    @ViewBuilder
    private var breakdownCards: some View {
        ProWorkDonutBreakdownCard(
            title: settingsStore.localized("reports.dashboard.chart.category", defaultValue: "Kategori Dağılımı"),
            systemImage: "tag.fill",
            rows: viewModel.categoryBreakdownRows,
            emptyMessage: settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok")
        )

        ProWorkDonutBreakdownCard(
            title: settingsStore.localized("reports.dashboard.chart.customer", defaultValue: "Müşteri Dağılımı"),
            systemImage: "person.2.fill",
            rows: viewModel.customerBreakdownRows,
            emptyMessage: settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok")
        )
    }

    private var breakdownCharts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                breakdownCards
            }
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                breakdownCards
            }
        }
    }

    private var customerBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.customer", defaultValue: "Müşteri Bazlı"),
            systemImage: "person.2",
            rows: viewModel.customerBreakdownData.map { ($0.name, $0.seconds) },
            total: viewModel.totalSeconds
        )
        .frame(maxWidth: .infinity)
    }

    private var billableBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.billing", defaultValue: "Faturalandırma"),
            systemImage: "creditcard",
            rows: viewModel.billableBreakdownData.map { ($0.name, $0.seconds) },
            total: viewModel.totalSeconds
        )
        .frame(maxWidth: .infinity)
    }

    private var projectBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.project", defaultValue: "Proje Bazlı"),
            systemImage: "folder",
            rows: viewModel.projectBreakdownData.map { ($0.name, $0.seconds) },
            total: viewModel.totalSeconds
        )
    }

    private var todoBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.todo", defaultValue: "Yapılacak İş Bazlı"),
            systemImage: "checklist",
            rows: viewModel.todoBreakdownData.map { ($0.name, $0.seconds) },
            total: viewModel.totalSeconds
        )
    }

    // MARK: - Breakdown Table

    private func breakdownTable(
        title: String,
        systemImage: String,
        rows: [(String, Int)],
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 15)
                    .foregroundStyle(.secondary)

                Text(title)
                    .proWorkTextStyle(.headline)

                Spacer()

                Text(ProWorkFormatters.durationHHmm(total))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(ProWorkLayout.scaled(14, using: settingsStore))
            .background(.quaternary.opacity(0.35))

            Divider()

            if rows.isEmpty {
                HStack {
                    Text(settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok"))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(ProWorkLayout.scaled(16, using: settingsStore))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Previously rendered as a plain ForEach in
                // a VStack, so a long category breakdown materialised every
                // row even when off-screen. Wrap in LazyVStack so rendering
                // is bounded by what's actually visible.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        breakdownRow(name: row.0, seconds: row.1, total: total)

                        Divider()
                    }
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func breakdownRow(name: String, seconds: Int, total: Int) -> some View {
        HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            Text(name)
                .proWorkTextStyle(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                let ratio = total > 0 ? CGFloat(seconds) / CGFloat(total) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(maxWidth: .infinity)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(width: ProWorkLayout.scaled(120, using: settingsStore), height: ProWorkLayout.scaled(8, using: settingsStore))

            Text(ProWorkFormatters.durationHHmm(seconds))
                .proWorkTextStyle(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: ProWorkLayout.scaled(72, using: settingsStore), alignment: .trailing)

            let pct = total > 0 ? Int(Double(seconds) / Double(total) * 100) : 0
            Text("\(pct)%")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(width: ProWorkLayout.scaled(36, using: settingsStore), alignment: .trailing)
        }
        .padding(.horizontal, ProWorkLayout.scaled(14, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(10, using: settingsStore))
    }

}

/// Route through the canonical `SearchPickerOption`
/// shape so the dashboard filter and other (id, title) pickers can't
/// drift independently.
private typealias FilterOption = SearchPickerOption
