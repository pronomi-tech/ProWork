//
//  DefinitionsView.swift
//  ProWork
//
//  Created by Pronomi.
//
//  "Tanımlar" tam ekran sayfası. SettingsView ile aynı kalıbı kullanır:
//  üstte geri butonlu bar, solda sidebar, sağda seçilen tanım ekranı.
//

import SwiftUI

struct DefinitionsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    let onClose: () -> Void

    @State private var selectedTab: DefinitionsTab

    init(initialTab: DefinitionsTab = .customers, onClose: @escaping () -> Void = {}) {
        self._selectedTab = State(initialValue: initialTab)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 240)
                    .background(.regularMaterial)

                Divider()

                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .proWorkFont(size: 13, weight: .semibold)
                    Text(settingsStore.localized("settings.back", defaultValue: "Geri"))
                        .proWorkTextStyle(.callout)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Divider().frame(height: 18)

            Text(settingsStore.localized("definitions.title", defaultValue: "Tanımlar"))
                .proWorkTextStyle(.headline)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(DefinitionsTabGroup.allCases) { group in
                    section(group.title(using: settingsStore), tabs: group.tabs)
                }
            }
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity)
    }

    private func section(_ title: String, tabs: [DefinitionsTab]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .proWorkFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(tabs) { tab in
                sidebarItem(tab)
            }
        }
    }

    private func sidebarItem(_ tab: DefinitionsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .proWorkFont(size: 13, weight: .medium)
                    .foregroundStyle(isSelected ? Color.white : .secondary)
                    .frame(width: 18)

                Text(tab.title(using: settingsStore))
                    .proWorkFont(size: 13, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .customers:
            CustomersView()
        case .projects:
            ProjectsView()
        case .taskCategories:
            TaskCategoriesView()
        case .todoStatuses:
            TodoStatusesView()
        }
    }
}

private enum DefinitionsTabGroup: String, CaseIterable, Identifiable {
    case masterData
    case workflow

    var id: String { rawValue }

    var tabs: [DefinitionsTab] {
        switch self {
        case .masterData:
            return [.customers, .projects]
        case .workflow:
            return [.taskCategories, .todoStatuses]
        }
    }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .masterData:
            return settingsStore.localized("definitions.section.master", defaultValue: "Tanımlamalar")
        case .workflow:
            return settingsStore.localized("definitions.section.workflow", defaultValue: "Görev Akışı")
        }
    }
}

// MARK: - DefinitionsTab

enum DefinitionsTab: String, CaseIterable, Identifiable, Hashable {
    case customers
    case projects
    case taskCategories
    case todoStatuses

    var id: String { rawValue }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .customers:
            return settingsStore.localized("app.section.customers", defaultValue: "Müşteriler")
        case .projects:
            return settingsStore.localized("app.section.projects", defaultValue: "Projeler")
        case .taskCategories:
            return settingsStore.localized("taskCategories.title", defaultValue: "Görev Kategorileri")
        case .todoStatuses:
            return settingsStore.localized("todoStatuses.title", defaultValue: "İş Akışı Statüleri")
        }
    }

    var systemImage: String {
        switch self {
        case .customers: return "person.2"
        case .projects: return "folder"
        case .taskCategories: return "tag"
        case .todoStatuses: return "rectangle.3.group"
        }
    }
}
