//
//  ReportsView.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Raporlama wrapper'ı. Üstte sekme seçimi, altında ilgili rapor ekranı.
//

import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var selectedTab: ReportTab = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ReportTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func tabButton(_ tab: ReportTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .proWorkFont(size: 13)
                Text(tab.title(using: settingsStore))
                    .proWorkTextStyle(.callout, weight: isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? Color.white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .dashboard:
            ReportsDashboardView()
        case .customer:
            CustomerReportView()
        case .project:
            ProjectReportView()
        case .todo:
            TodoReportView()
        }
    }
}

enum ReportTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case customer
    case project
    case todo

    var id: String { rawValue }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .dashboard:
            return settingsStore.localized("reports.tab.dashboard", defaultValue: "Genel Bakış")
        case .customer:
            return settingsStore.localized("reports.tab.customer", defaultValue: "Müşteri Raporu")
        case .project:
            return settingsStore.localized("reports.tab.project", defaultValue: "Proje Raporu")
        case .todo:
            return settingsStore.localized("reports.tab.todo", defaultValue: "İş Raporu")
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar"
        case .customer: return "person.2"
        case .project: return "folder"
        case .todo: return "checklist"
        }
    }
}
