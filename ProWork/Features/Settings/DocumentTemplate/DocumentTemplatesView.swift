//  DocumentTemplatesView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

/// Container hosting the service-document and quote PDF templates inside a
/// **single** SettingsScreenScaffold. The title and the Reset/Save toolbar
/// render once; tab switches only swap the content ZStack. The tab picker
/// is placed as a top overlay on the scaffold — it doesn't interfere with
/// the scaffold header's layout pass, so the right-aligned toolbar matches
/// the position used by the other Settings screens exactly.
struct DocumentTemplatesView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @State private var selectedTab: DocumentTemplateTab = .service
    @State private var savePulse: UUID = UUID()
    @State private var resetPulse: UUID = UUID()
    @State private var savedNotice: String?

    var body: some View {
        SettingsScreenScaffold(
            title: title,
            subtitle: subtitle,
            savedNotice: savedNotice,
            toolbar: {
                HStack(spacing: 10) {
                    Button {
                        resetPulse = UUID()
                    } label: {
                        ProWorkButtonLabel(
                            title: settingsStore.localized("documentTemplate.reset", defaultValue: "Sıfırla"),
                            systemImage: "arrow.counterclockwise",
                            minHeight: 32
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        savePulse = UUID()
                    } label: {
                        ProWorkButtonLabel(
                            title: settingsStore.localized("common.save", defaultValue: "Kaydet"),
                            systemImage: "checkmark",
                            minHeight: 32
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        ) {
            // Only the active tab is rendered → each form takes
            // its natural height with no wasted space below. Previously
            // ZStack kept both children alive, but because ZStack grows
            // to the max child height the shorter form had blank space
            // equal to the taller form's footprint. On tab change the
            // inactive form's unsaved draft is reloaded from the store;
            // acceptable for a settings editor.
            switch selectedTab {
            case .service:
                ServiceDocumentTemplateSettingsView(
                    savePulse: savePulse,
                    resetPulse: resetPulse,
                    savedNotice: $savedNotice
                )
            case .quote:
                PriceListQuoteTemplateSettingsView(
                    savePulse: savePulse,
                    resetPulse: resetPulse,
                    savedNotice: $savedNotice
                )
            }
        }
        // The picker is drawn as an overlay on top of the scaffold.
        // ZStack alignment is top → picker aligns vertically with the
        // scaffold's header band; horizontal `.center` centres it in
        // the viewport. Does not touch the scaffold's own layout;
        // guarantees the same toolbar position as other Settings screens.
        .overlay(alignment: .top) {
            DocumentTemplateTabPicker(selection: $selectedTab)
                .padding(.top, ProWorkLayout.scaled(24, using: settingsStore))
        }
    }

    private var title: String {
        settingsStore.localized("documentTemplate.section.title", defaultValue: "PDF Şablonları")
    }

    private var subtitle: String {
        switch selectedTab {
        case .service:
            return settingsStore.localized("documentTemplate.subtitle", defaultValue: "Hizmet dökümü PDF çıktısının başlık, renk, bölüm ve kolon görünümünü yönetin.")
        case .quote:
            return settingsStore.localized("quoteTemplate.subtitle", defaultValue: "Fiyat listesinden üretilen Teklif PDF'inin yapısı, metinleri ve renkleri.")
        }
    }
}
