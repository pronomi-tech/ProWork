//
//  ReportsView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ReportsDashboardView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var sessions: [WorkSessionListItem] = []
    @State private var todos: [TodoListItem] = []
    @State private var customers: [Customer] = []
    @State private var projects: [ProjectListItem] = []
    @State private var errorMessage: String?

    @State private var filterRange: DateRangeFilter = .thisMonth
    @State private var filterStartDate: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var filterEndDate: Date = Date()
    @State private var filterCustomerId: String = ""
    @State private var filterProjectId: String = ""
    @State private var isShowingFilters: Bool = false

    private let sessionRepository = TodoTimeSessionRepository()
    private let todoRepository = TodoRepository()
    private let customerRepository = CustomerRepository()
    private let projectRepository = ProjectRepository()

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
        .proWorkToastNotifications(errorMessage: errorMessage)
        .onAppear {
            loadData()
        }
    }

    // MARK: - Filtered Sessions

    private var filteredSessions: [WorkSessionListItem] {
        return sessions.filter { session in
            let matchesRange = filterRange.contains(
                session.startedAt,
                customStart: filterStartDate,
                customEnd: filterEndDate
            )

            let matchesCustomer: Bool = {
                guard !filterCustomerId.isEmpty else { return true }
                guard let name = customers.first(where: { $0.id == filterCustomerId })?.name else { return false }
                return session.customerName == name
            }()

            let matchesProject: Bool = {
                guard !filterProjectId.isEmpty else { return true }
                guard let name = projects.first(where: { $0.id == filterProjectId })?.name else { return false }
                return session.projectName == name
            }()

            return matchesRange && matchesCustomer && matchesProject
        }
        .filter { $0.endedAt != nil }
    }

    private var totalSeconds: Int {
        filteredSessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    private var hasActiveFilters: Bool {
        filterRange != .thisMonth ||
        !filterCustomerId.isEmpty ||
        !filterProjectId.isEmpty
    }

    private func clearFilters() {
        filterRange = .thisMonth
        filterStartDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
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

            Text(String(format: settingsStore.localized("common.recordCount", defaultValue: "%d kayıt"), filteredSessions.count))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter Panel

    private var customerFilterOptions: [FilterOption] {
        [FilterOption(id: "", title: settingsStore.localized("dateRange.all", defaultValue: "Tümü"))] +
        customers.map { FilterOption(id: $0.id, title: $0.name) }
    }

    private var projectFilterOptions: [FilterOption] {
        let filtered = filterCustomerId.isEmpty
            ? projects
            : projects.filter { $0.customerId == filterCustomerId }
        return [FilterOption(id: "", title: settingsStore.localized("dateRange.all", defaultValue: "Tümü"))] +
            filtered.map { FilterOption(id: $0.id, title: $0.name) }
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
                        showsSearch: customers.count > 8,
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
                    value: ProWorkFormatters.durationHHmm(totalSeconds),
                    subtitle: String(format: settingsStore.localized("common.recordCount", defaultValue: "%d kayıt"), filteredSessions.count),
                    systemImage: "clock.fill",
                    color: .blue
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.manual", defaultValue: "Manuel Kayıtlar"),
                    value: ProWorkFormatters.durationHHmm(manualSeconds),
                    subtitle: String(format: settingsStore.localized("reports.dashboard.card.manualCount", defaultValue: "%d manuel"), filteredSessions.filter { $0.isManual }.count),
                    systemImage: "hand.point.up.left.fill",
                    color: .orange
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.automatic", defaultValue: "Otomatik Kayıtlar"),
                    value: ProWorkFormatters.durationHHmm(automaticSeconds),
                    subtitle: String(format: settingsStore.localized("reports.dashboard.card.automaticCount", defaultValue: "%d otomatik"), filteredSessions.filter { !$0.isManual }.count),
                    systemImage: "play.fill",
                    color: .green
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.customerCount", defaultValue: "Müşteri Sayısı"),
                    value: "\(uniqueCustomerCount)",
                    subtitle: settingsStore.localized("reports.dashboard.card.uniqueCustomer", defaultValue: "farklı müşteri"),
                    systemImage: "person.2.fill",
                    color: .purple
                )

                overviewCard(
                    title: settingsStore.localized("reports.dashboard.card.projectCount", defaultValue: "Proje Sayısı"),
                    value: "\(uniqueProjectCount)",
                    subtitle: settingsStore.localized("reports.dashboard.card.uniqueProject", defaultValue: "farklı proje"),
                    systemImage: "folder.fill",
                    color: .cyan
                )
            }
        }
    }

    private var manualSeconds: Int {
        filteredSessions.filter { $0.isManual }.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    private var automaticSeconds: Int {
        filteredSessions.filter { !$0.isManual }.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    private var uniqueCustomerCount: Int {
        Set(filteredSessions.compactMap { $0.customerName }).count
    }

    private var uniqueProjectCount: Int {
        Set(filteredSessions.compactMap { $0.projectName }).count
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

    private var todoLookup: [String: TodoListItem] {
        Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
    }

    private var categoryBreakdownRows: [DonutBreakdownRow] {
        SessionBreakdownBuilder.categoryRows(
            sessions: filteredSessions,
            todoLookup: todoLookup,
            unknownTitle: settingsStore.localized("home.pie.unknownCategory", defaultValue: "Kategorisiz"),
            otherTitle: settingsStore.localized("home.pie.other", defaultValue: "Diğer")
        )
    }

    private var customerBreakdownRows: [DonutBreakdownRow] {
        SessionBreakdownBuilder.customerRows(
            sessions: filteredSessions,
            noCustomerTitle: settingsStore.localized("home.pie.noCustomer", defaultValue: "Müşterisiz"),
            otherTitle: settingsStore.localized("home.pie.other", defaultValue: "Diğer")
        )
    }

    private var breakdownCharts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                ProWorkDonutBreakdownCard(
                    title: settingsStore.localized("reports.dashboard.chart.category", defaultValue: "Kategori Dağılımı"),
                    systemImage: "tag.fill",
                    rows: categoryBreakdownRows,
                    emptyMessage: settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok")
                )

                ProWorkDonutBreakdownCard(
                    title: settingsStore.localized("reports.dashboard.chart.customer", defaultValue: "Müşteri Dağılımı"),
                    systemImage: "person.2.fill",
                    rows: customerBreakdownRows,
                    emptyMessage: settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok")
                )
            }

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                ProWorkDonutBreakdownCard(
                    title: settingsStore.localized("reports.dashboard.chart.category", defaultValue: "Kategori Dağılımı"),
                    systemImage: "tag.fill",
                    rows: categoryBreakdownRows,
                    emptyMessage: settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok")
                )

                ProWorkDonutBreakdownCard(
                    title: settingsStore.localized("reports.dashboard.chart.customer", defaultValue: "Müşteri Dağılımı"),
                    systemImage: "person.2.fill",
                    rows: customerBreakdownRows,
                    emptyMessage: settingsStore.localized("reports.empty.period", defaultValue: "Bu dönemde kayıt yok")
                )
            }
        }
    }

    private var customerBreakdownData: [(name: String, seconds: Int)] {
        var map: [String: Int] = [:]
        for session in filteredSessions {
            let key = session.customerName ?? settingsStore.localized("todos.administrative", defaultValue: "İdari")
            map[key, default: 0] += session.durationSeconds ?? 0
        }
        return map.map { (name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var customerBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.customer", defaultValue: "Müşteri Bazlı"),
            systemImage: "person.2",
            rows: customerBreakdownData.map { ($0.name, $0.seconds) },
            total: totalSeconds
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Billable Breakdown

    private var billableBreakdownData: [(name: String, seconds: Int)] {
        let billable = filteredSessions.filter { $0.statusStartsTimer }.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        let administrative = totalSeconds - billable
        return [
            (settingsStore.localized("reports.dashboard.breakdown.billable", defaultValue: "Faturalandırılabilir"), billable),
            (settingsStore.localized("todos.administrative", defaultValue: "İdari"), administrative)
        ]
        .filter { $0.1 > 0 }
    }

    private var billableBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.billing", defaultValue: "Faturalandırma"),
            systemImage: "creditcard",
            rows: billableBreakdownData.map { ($0.name, $0.seconds) },
            total: totalSeconds
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Project Breakdown

    private var projectBreakdownData: [(name: String, seconds: Int)] {
        var map: [String: Int] = [:]
        for session in filteredSessions {
            let key: String
            if let project = session.projectName, !project.isEmpty {
                key = project
            } else if let customer = session.customerName, !customer.isEmpty {
                key = String(format: settingsStore.localized("reports.dashboard.project.noProject", defaultValue: "%@ (Proje yok)"), customer)
            } else {
                key = settingsStore.localized("todos.administrative", defaultValue: "İdari")
            }
            map[key, default: 0] += session.durationSeconds ?? 0
        }
        return map.map { (name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var projectBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.project", defaultValue: "Proje Bazlı"),
            systemImage: "folder",
            rows: projectBreakdownData.map { ($0.name, $0.seconds) },
            total: totalSeconds
        )
    }

    // MARK: - Todo Breakdown

    private var todoBreakdownData: [(name: String, seconds: Int)] {
        var map: [String: Int] = [:]
        for session in filteredSessions {
            map[session.todoTitle, default: 0] += session.durationSeconds ?? 0
        }
        return map.map { (name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(20)
            .map { $0 }
    }

    private var todoBreakdown: some View {
        breakdownTable(
            title: settingsStore.localized("reports.dashboard.breakdown.todo", defaultValue: "Yapılacak İş Bazlı"),
            systemImage: "checklist",
            rows: todoBreakdownData.map { ($0.name, $0.seconds) },
            total: totalSeconds
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
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    breakdownRow(name: row.0, seconds: row.1, total: total)

                    Divider()
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

    // MARK: - Data

    private func loadData() {
        do {
            sessions = try sessionRepository.fetchAllListItems()
            todos = try todoRepository.fetchAll()
            customers = try customerRepository.fetchAll()
            projects = try projectRepository.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FilterOption: Identifiable {
    let id: String
    let title: String
}
