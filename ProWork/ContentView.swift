//
//  ContentView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var selectedSection: AppSection? = .home
    /// Settings/Definitions full-screen modundan çıkınca dönülecek bölüm.
    @State private var previousSection: AppSection = .home
    @State private var isSettingsOpen: Bool = false
    @State private var isDefinitionsOpen: Bool = false

    var body: some View {
        Group {
            if isSettingsOpen {
                SettingsView(onClose: closeSettings)
            } else if isDefinitionsOpen {
                DefinitionsView(onClose: closeDefinitions)
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(
                            min: sidebarMinWidth,
                            ideal: sidebarIdealWidth,
                            max: sidebarMaxWidth
                        )
                } detail: {
                    selectedContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(
            minWidth: appMinWidth,
            minHeight: appMinHeight
        )
        .onChange(of: selectedSection) { _, newValue in
            if newValue == .settings {
                isSettingsOpen = true
            } else if newValue == .definitions {
                isDefinitionsOpen = true
            } else if let newValue {
                previousSection = newValue
            }
        }
    }

    private func closeSettings() {
        isSettingsOpen = false
        selectedSection = previousSection
    }

    private func closeDefinitions() {
        isDefinitionsOpen = false
        selectedSection = previousSection
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section {
                    ForEach(AppSection.mainSections) { section in
                        NavigationLink(value: section) {
                            sidebarItem(section)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
                .padding(.vertical, ProWorkLayout.scaled(8, using: settingsStore))
            
            List(selection: $selectedSection) {
                ForEach(AppSection.bottomSections) { section in
                    NavigationLink(value: section) {
                        sidebarItem(section)
                    }
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    sidebarItem(
                        title: settingsStore.localized("app.nav.quit", defaultValue: "Çıkış"),
                        systemImage: "power"
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
            .frame(height: bottomListHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebarItem(_ section: AppSection) -> some View {
        sidebarItem(
            title: section.title(using: settingsStore),
            systemImage: section.systemImage
        )
    }

    private func sidebarItem(title: String, systemImage: String) -> some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: 15, weight: .medium)
                .frame(width: ProWorkLayout.scaled(20, using: settingsStore))

            Text(title)
                .proWorkFont(size: 14, weight: .medium)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, ProWorkLayout.scaled(5, using: settingsStore))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .home:
            HomeView(onNavigate: handleHomeNavigation)

        case .todos:
            TodosView()

        case .workSessions:
            WorkSessionsView()

        case .billing:
            BillingRunsView()

        case .reports:
            ReportsView()

        case .definitions:
            // Sidebar seçimi yapıldığında full-screen Definitions açılır;
            // bu dal yalnızca geçiş anında görünür.
            Color.clear

        case .settings:
            SettingsView()

        case nil:
            ContentUnavailableView(
                settingsStore.localized("app.nav.placeholder.title", defaultValue: "Bölüm seçin"),
                systemImage: "sidebar.left",
                description: Text(settingsStore.localized("app.nav.placeholder.description", defaultValue: "Sol menüden bir bölüm seçerek devam edin."))
            )
        }
    }

    private func handleHomeNavigation(_ target: HomeNavigationTarget) {
        switch target {
        case .todos:
            selectedSection = .todos
        case .workSessions:
            selectedSection = .workSessions
        case .billing:
            selectedSection = .billing
        case .reports:
            selectedSection = .reports
        case .definitions:
            selectedSection = .definitions
        }
    }

    private var fontScale: CGFloat {
        ProWorkLayout.scale(using: settingsStore)
    }

    private var appMinWidth: CGFloat {
        switch settingsStore.settings.fontSize {
        case .small:
            return 1305
        case .normal:
            return 1392
        case .large:
            return 1525
        case .extraLarge:
            return 1669
        }
    }

    private var appMinHeight: CGFloat {
        switch settingsStore.settings.fontSize {
        case .small:
            return 850
        case .normal:
            return 920
        case .large:
            return 1024
        case .extraLarge:
            return 1140
        }
    }

    private var sidebarMinWidth: CGFloat {
        min(280, ProWorkLayout.scaled(240, using: settingsStore))
    }

    private var sidebarIdealWidth: CGFloat {
        min(300, ProWorkLayout.scaled(260, using: settingsStore))
    }

    private var sidebarMaxWidth: CGFloat {
        min(340, ProWorkLayout.scaled(320, using: settingsStore))
    }

    private var bottomListHeight: CGFloat {
        ProWorkLayout.scaled(124, using: settingsStore)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case home
    case todos
    case workSessions
    case billing
    case reports
    case definitions
    case settings

    var id: String {
        rawValue
    }

    static var mainSections: [AppSection] {
        [
            .home,
            .todos,
            .workSessions,
            .billing,
            .reports
        ]
    }

    static var bottomSections: [AppSection] {
        [
            .definitions,
            .settings
        ]
    }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .home:
            return settingsStore.localized("app.section.home", defaultValue: "Anasayfa")
        case .todos:
            return settingsStore.localized("app.section.todos", defaultValue: "Yapılacak Listesi")
        case .workSessions:
            return settingsStore.localized("app.section.workSessions", defaultValue: "Çalışma Kayıtları")
        case .billing:
            return settingsStore.localized("app.section.billing", defaultValue: "Hizmet Dökümleri")
        case .reports:
            return settingsStore.localized("app.section.reports", defaultValue: "Raporlar")
        case .definitions:
            return settingsStore.localized("app.section.definitions", defaultValue: "Tanımlar")
        case .settings:
            return settingsStore.localized("app.section.settings", defaultValue: "Ayarlar")
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .todos:
            return "checklist"
        case .workSessions:
            return "clock"
        case .billing:
            return "doc.text"
        case .reports:
            return "chart.bar"
        case .definitions:
            return "tray.full"
        case .settings:
            return "gearshape"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let settingsStore = AppSettingsStore()

        ContentView()
            .environmentObject(settingsStore)
            .environmentObject(ProWorkToastStore.shared)
    }
}
