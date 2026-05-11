//
//  DocumentTemplatesView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

/// Hizmet dökümü ve teklif PDF şablonlarını tek ekranda tablar altında sunan kapsayıcı.
struct DocumentTemplatesView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @State private var selectedTab: Tab = .service

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title(using: settingsStore)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: 480, alignment: .leading)

            switch selectedTab {
            case .service:
                ServiceDocumentTemplateSettingsView()
            case .quote:
                PriceListQuoteTemplateSettingsView()
            }
        }
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case service
        case quote

        var id: String { rawValue }

        func title(using settingsStore: AppSettingsStore) -> String {
            switch self {
            case .service:
                return settingsStore.localized("documentTemplate.tab.service", defaultValue: "Hizmet Dökümü")
            case .quote:
                return settingsStore.localized("documentTemplate.tab.quote", defaultValue: "Teklif")
            }
        }
    }
}
