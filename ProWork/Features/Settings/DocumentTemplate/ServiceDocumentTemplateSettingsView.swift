//  ServiceDocumentTemplateSettingsView.swift
//  ProWork
//   Created by Pronomi.

import AppKit
import SwiftUI

struct ServiceDocumentTemplateSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    /// Pulse trigger UUIDs from the parent DocumentTemplatesView.
    /// Save/Reset buttons live in the parent toolbar; on click the
    /// parent emits a new UUID, this view catches it via `.onChange`
    /// and calls `save()`/`reset()`. The UUID approach is safer than
    /// closure binding — compatible with struct value semantics, does
    /// not cause @State capture issues.
    let savePulse: UUID
    let resetPulse: UUID

    @State private var draftSettings: ServiceDocumentTemplateSettings = .defaultTemplate
    /// `savedNotice` is now read by the parent scaffold through a
    /// `Binding<String?>` — the outer scaffold shows a single savedNotice.
    @Binding var savedNotice: String?
    /// Shared notice scheduler.
    @State private var savedNoticeScheduler = NoticeScheduler()

    private let accentPresets = [
        "#1F4E79",
        "#0F766E",
        "#7C2D12",
        "#334155",
        "#7C3AED",
        "#BE123C"
    ]

    var body: some View {
        // This view no longer wraps its own scaffold — the parent
        // DocumentTemplatesView tek bir outer SettingsScreenScaffold'da
        // renders the title + picker + toolbar. The content below
        // is placed directly into that scaffold's body.
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
            SettingsCard {
                Text(settingsStore.localized("documentTemplate.section.general", defaultValue: "Genel Görünüm"))
                    .proWorkTextStyle(.headline)

                formField(label: settingsStore.localized("documentTemplate.field.title", defaultValue: "Belge Başlığı")) {
                    ProWorkTextField(
                        placeholder: settingsStore.localized("documentTemplate.default.title", defaultValue: "Dönemsel Hizmet Dökümü"),
                        text: $draftSettings.title
                    )
                    .frame(maxWidth: 420)
                }

                formField(label: settingsStore.localized("documentTemplate.field.fontScale", defaultValue: "Font Ölçeği")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Slider(
                            value: $draftSettings.fontScale,
                            in: 0.9...1.15,
                            step: 0.05
                        )
                        Text("%\(Int(draftSettings.normalizedFontScale * 100))")
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 280)
                }

                formField(label: settingsStore.localized("documentTemplate.field.accentColor", defaultValue: "Vurgu Rengi")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(accentPresets, id: \.self) { hex in
                                Button {
                                    draftSettings.accentHexColor = hex
                                } label: {
                                    Circle()
                                        .fill(color(for: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    draftSettings.normalizedAccentHexColor == hex ? Color.primary : Color.clear,
                                                    lineWidth: 2
                                                )
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ProWorkTextField(
                            placeholder: "#1F4E79",
                            text: $draftSettings.accentHexColor
                        )
                        .frame(maxWidth: 180)
                    }
                }
            }

            SettingsCard {
                Text(settingsStore.localized("documentTemplate.section.sections", defaultValue: "Bölümler"))
                    .proWorkTextStyle(.headline)

                toggleRow(settingsStore.localized("documentTemplate.toggle.showLogo", defaultValue: "Logo göster"), isOn: $draftSettings.showLogo)
                toggleRow(settingsStore.localized("documentTemplate.toggle.showHeaderDivider", defaultValue: "Antet ayırıcı çizgisi"), isOn: $draftSettings.showHeaderDivider)
                toggleRow(settingsStore.localized("documentTemplate.toggle.showFinancialSummary", defaultValue: "Finansal özet kartları"), isOn: $draftSettings.showFinancialSummary)
                toggleRow(settingsStore.localized("documentTemplate.toggle.showLineNotes", defaultValue: "Satır notlarını göster"), isOn: $draftSettings.showLineNotes)
                toggleRow(settingsStore.localized("documentTemplate.toggle.showFooter", defaultValue: "Footer göster"), isOn: $draftSettings.showFooter)
            }

            SettingsCard {
                Text(settingsStore.localized("documentTemplate.section.footer", defaultValue: "Belge Alt Notu"))
                    .proWorkTextStyle(.headline)

                // `TextEditor` is vertically greedy; without a maxHeight inside
                // a ScrollView it balloons. We pin it to the 90-120 pt range.
                ProWorkTextEditor(text: $draftSettings.footerNote, minHeight: 90)
                    .frame(maxWidth: 760, maxHeight: 120)
            }
        }
        .onAppear {
            draftSettings = localizedTemplate(from: settingsStore.settings.serviceDocumentTemplateSettings)
        }
        // Parent toolbar'dan gelen pulse trigger'lar — aktif tab buysa
        // save/reset is applied. UUID changes are detected via `.onChange`;
        // independent of closure-binding's struct value-semantics pitfalls.
        .onChange(of: savePulse) { _, _ in
            save()
        }
        .onChange(of: resetPulse) { _, _ in
            draftSettings = localizedDefaultTemplate
            save()
        }
    }

    private func save() {
        let trimmedTitle = draftSettings.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draftSettings.title = trimmedTitle.isEmpty ? localizedDefaultTemplate.title : trimmedTitle
        if draftSettings.footerNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftSettings.footerNote = localizedDefaultTemplate.footerNote
        }
        draftSettings.accentHexColor = draftSettings.normalizedAccentHexColor
        settingsStore.updateServiceDocumentTemplateSettings(draftSettings)
        setSavedNotice(settingsStore.localized("documentTemplate.notice.saved", defaultValue: "PDF şablonu kaydedildi."))
    }

    private func setSavedNotice(_ message: String) {
        savedNoticeScheduler.show(message) { value in
            savedNotice = value
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .proWorkTextStyle(.callout)
        }
        .toggleStyle(.switch)
    }

    private func formField<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .proWorkTextStyle(.caption, weight: .medium)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Route through `PDFDrawingPrimitives.nsColor(fromHex:)`
    /// which (after ) accepts #RGB / #RRGGBB / #RRGGBBAA. The
    /// previous hand-rolled parser was 6-char only and silently
    /// fell back to accentColor on a 3-char user input.
    private func color(for hex: String) -> Color {
        let normalized = ServiceDocumentTemplateSettings(
            title: "",
            showLogo: true,
            showHeaderDivider: true,
            showFooter: true,
            showLineNotes: true,
            showFinancialSummary: true,
            fontScale: 1,
            accentHexColor: hex,
            footerNote: ""
        ).normalizedAccentHexColor
        guard let nsColor = PDFDrawingPrimitives.nsColor(fromHex: normalized) else {
            return .accentColor
        }
        return Color(nsColor: nsColor)
    }

    private var localizedDefaultTemplate: ServiceDocumentTemplateSettings {
        ServiceDocumentTemplateSettings(
            title: settingsStore.localized("documentTemplate.default.title", defaultValue: "Dönemsel Hizmet Dökümü"),
            showLogo: true,
            showHeaderDivider: true,
            showFooter: true,
            showLineNotes: true,
            showFinancialSummary: true,
            fontScale: 1.0,
            accentHexColor: "#1F4E79",
            footerNote: settingsStore.localized("documentTemplate.default.footer", defaultValue: "Bu belge, hizmet dökümü ve cari bilgilendirme amacıyla hazırlanmıştır. Fatura yerine geçmez.")
        )
    }

    private func localizedTemplate(from settings: ServiceDocumentTemplateSettings) -> ServiceDocumentTemplateSettings {
        var localized = settings
        if settings.title == ServiceDocumentTemplateSettings.defaultTemplate.title {
            localized.title = localizedDefaultTemplate.title
        }
        if settings.footerNote == ServiceDocumentTemplateSettings.defaultTemplate.footerNote {
            localized.footerNote = localizedDefaultTemplate.footerNote
        }
        return localized
    }
}
