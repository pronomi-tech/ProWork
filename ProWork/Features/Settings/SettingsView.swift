//
//  SettingsView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    let onClose: () -> Void

    @State private var selectedTab: SettingsTab = .general

    init(onClose: @escaping () -> Void = {}) {
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

            Text(settingsStore.localized("settings.title", defaultValue: "Ayarlar"))
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
            VStack(alignment: .leading, spacing: 4) {
                section(settingsStore.localized("settings.section.app", defaultValue: "Uygulama Ayarları"), tabs: SettingsTab.appGroup)
                section(settingsStore.localized("settings.section.corporate", defaultValue: "Kurumsal Ayarlar"), tabs: SettingsTab.corporateGroup)
            }
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity)
    }

    private func section(_ title: String, tabs: [SettingsTab]) -> some View {
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

    private func sidebarItem(_ tab: SettingsTab) -> some View {
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
        case .general:
            GeneralSettingsView()
        case .exchangeRates:
            ExchangeRatesView()
        case .dataBackup:
            DataBackupSettingsView()
        case .corporate:
            CorporateSettingsView()
        }
    }
}

// MARK: - SettingsTab

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case exchangeRates
    case dataBackup
    case corporate

    var id: String { rawValue }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .general: return settingsStore.localized("settings.tab.general", defaultValue: "Genel")
        case .exchangeRates: return settingsStore.localized("settings.tab.exchangeRates", defaultValue: "Döviz Kurları")
        case .dataBackup: return settingsStore.localized("settings.tab.dataBackup", defaultValue: "Veri ve Yedekleme")
        case .corporate: return settingsStore.localized("settings.tab.corporate", defaultValue: "Kurumsal Merkez")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .exchangeRates: return "arrow.left.arrow.right.circle"
        case .dataBackup: return "externaldrive"
        case .corporate: return "building.2.crop.circle"
        }
    }

    static let appGroup: [SettingsTab] = [.general, .exchangeRates, .dataBackup]
    static let corporateGroup: [SettingsTab] = [.corporate]
}

struct CorporateSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @State private var selectedPanel: CorporateSettingsPanel = .companyProfile

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
                .background(.regularMaterial)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.background)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settingsStore.localized("settings.corporate.title", defaultValue: "Kurumsal Ayarlar"))
                        .proWorkTextStyle(.headline)

                    Text(settingsStore.localized("settings.corporate.subtitle", defaultValue: "Şirket kimliği, belge tercihleri, finansal tanımlar ve erişim ayarlarını tek akıştan yönetin."))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)

                ForEach(CorporateSettingsPanel.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title(using: settingsStore).uppercased())
                            .proWorkFont(size: 11, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)

                        ForEach(group.panels) { panel in
                            sidebarItem(panel)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
    }

    private func sidebarItem(_ panel: CorporateSettingsPanel) -> some View {
        let isSelected = selectedPanel == panel

        return Button {
            selectedPanel = panel
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: panel.systemImage)
                    .proWorkFont(size: 13, weight: .medium)
                    .foregroundStyle(isSelected ? Color.white : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(panel.title(using: settingsStore))
                        .proWorkFont(size: 13, weight: isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.white : .primary)

                    Text(panel.subtitle(using: settingsStore))
                        .proWorkFont(size: 11)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.86) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedPanel {
        case .companyProfile:
            CompanyProfileView()
        case .workCalendar:
            BillingRulesView()
        case .holidays:
            HolidaysView()
        case .priceLists:
            GlobalPriceListsView()
        case .vat:
            VatRatesView()
        case .documentTemplate:
            DocumentTemplatesView()
        }
    }
}

private enum CorporateSettingsPanel: String, CaseIterable, Identifiable {
    case companyProfile
    case documentTemplate
    case workCalendar
    case holidays
    case priceLists
    case vat

    var id: String { rawValue }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .companyProfile: return settingsStore.localized("settings.corporate.panel.companyProfile.title", defaultValue: "Şirket Profili")
        case .workCalendar: return settingsStore.localized("settings.corporate.panel.workCalendar.title", defaultValue: "Mesai Kuralları")
        case .holidays: return settingsStore.localized("settings.corporate.panel.holidays.title", defaultValue: "Resmi Tatiller")
        case .priceLists: return settingsStore.localized("settings.corporate.panel.priceLists.title", defaultValue: "Fiyat Listeleri")
        case .vat: return settingsStore.localized("settings.corporate.panel.vat.title", defaultValue: "KDV Kuralları")
        case .documentTemplate: return settingsStore.localized("settings.corporate.panel.documentTemplate.title", defaultValue: "PDF Şablonları")
        }
    }

    func subtitle(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .companyProfile:
            return settingsStore.localized("settings.corporate.panel.companyProfile.subtitle", defaultValue: "Kimlik, iletişim, banka ve temel belge bilgileri.")
        case .workCalendar:
            return settingsStore.localized("settings.corporate.panel.workCalendar.subtitle", defaultValue: "Mesai tanımları ve faturalanabilir çalışma kuralları.")
        case .holidays:
            return settingsStore.localized("settings.corporate.panel.holidays.subtitle", defaultValue: "Resmi tatil günleri ve takvim istisnaları.")
        case .priceLists:
            return settingsStore.localized("settings.corporate.panel.priceLists.subtitle", defaultValue: "Müşteri ve kapsam bazlı fiyat listesi tanımları.")
        case .vat:
            return settingsStore.localized("settings.corporate.panel.vat.subtitle", defaultValue: "Vergi oranları ve tarihsel KDV kural setleri.")
        case .documentTemplate:
            return settingsStore.localized("settings.corporate.panel.documentTemplate.subtitle", defaultValue: "Hizmet dökümü ve teklif PDF'lerinin görünümü, metinleri ve şartları.")
        }
    }

    var systemImage: String {
        switch self {
        case .companyProfile: return "building.2"
        case .documentTemplate: return "doc.text.image"
        case .workCalendar: return "calendar.badge.clock"
        case .holidays: return "calendar"
        case .priceLists: return "list.bullet.rectangle.portrait"
        case .vat: return "percent"
        }
    }

    static let groups: [CorporateSettingsGroup] = [
        CorporateSettingsGroup(
            title: "Genel",
            panels: [.companyProfile]
        ),
        CorporateSettingsGroup(
            title: "Operasyon",
            panels: [.workCalendar, .holidays]
        ),
        CorporateSettingsGroup(
            title: "Finans",
            panels: [.priceLists, .vat, .documentTemplate]
        )
    ]
}

private struct CorporateSettingsGroup {
    let title: String
    let panels: [CorporateSettingsPanel]

    func title(using settingsStore: AppSettingsStore) -> String {
        switch title {
        case "Genel":
            return settingsStore.localized("settings.corporate.group.general", defaultValue: "Genel")
        case "Operasyon":
            return settingsStore.localized("settings.corporate.group.operations", defaultValue: "Operasyon")
        case "Finans":
            return settingsStore.localized("settings.corporate.group.finance", defaultValue: "Finans")
        default:
            return title
        }
    }
}

// MARK: - Placeholder

struct SettingsPlaceholderView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        SettingsScreenScaffold(
            title: title,
            subtitle: message
        ) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 26)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Text(settingsStore.localized("settings.placeholder.soon.title", defaultValue: "Yakında"))
                        .proWorkTextStyle(.headline)

                    Text(settingsStore.localized("settings.placeholder.soon.message", defaultValue: "Bu bölümün ekranları sonraki adımlarda eklenecek."))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 560)
        }
    }
}
