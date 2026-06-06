//  DocumentTemplateTab.swift
//  ProWork
//  Created by Pronomi.
//  Shared tab enum and picker view for switching between the Service
//  Document and Quote templates. Previously the picker was rendered as
//  the top-level Picker inside DocumentTemplatesView; for UX consistency
//  it is now shown in each template view's own SettingsScreenScaffold
//  header center slot (between the title and the right-side actions).

import SwiftUI

enum DocumentTemplateTab: String, CaseIterable, Identifiable {
    case service
    case quote

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .service: return "doc.text"
        case .quote: return "doc.richtext"
        }
    }

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .service:
            return settingsStore.localized("documentTemplate.tab.service", defaultValue: "Hizmet Dökümü")
        case .quote:
            return settingsStore.localized("documentTemplate.tab.quote", defaultValue: "Teklif")
        }
    }
}

/// Modern pill-style picker shown in the scaffold header's center
/// region — same geometry and style as the TodosView Board/List
/// pattern. The selected pill uses accent fill; inactive ones are clear.
struct DocumentTemplateTabPicker: View {
    @Binding var selection: DocumentTemplateTab
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            ForEach(DocumentTemplateTab.allCases) { tab in
                pill(for: tab)
            }
        }
        .padding(ProWorkLayout.scaled(4, using: settingsStore))
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
    }

    private func pill(for tab: DocumentTemplateTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selection = tab
            }
        } label: {
            HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                Image(systemName: tab.systemImage)
                    .proWorkFont(size: 13, weight: .medium)
                // We keep `.medium` weight in both states; a bold ↔
                // regular transition changes text width, shifting the
                // picker 2-4 px during tab switches and breaking the
                // center alignment of centerContent in the parent
                // scaffold header. Emphasis is already conveyed by the
                // accent fill + white foreground.
                Text(tab.title(using: settingsStore))
                    .proWorkTextStyle(.callout, weight: .medium)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, ProWorkLayout.scaled(14, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(7, using: settingsStore))
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore))
                            .fill(Color.accentColor)
                    } else {
                        RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore))
                            .fill(Color.clear)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(tab.title(using: settingsStore))
    }
}
