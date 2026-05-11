//
//  ServiceDocumentTemplateSettingsView.swift
//  ProWork
//
//   Created by Pronomi.
//

import AppKit
import SwiftUI

struct ServiceDocumentTemplateSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var draftSettings: ServiceDocumentTemplateSettings = .defaultTemplate
    @State private var savedNotice: String?

    private let accentPresets = [
        "#1F4E79",
        "#0F766E",
        "#7C2D12",
        "#334155",
        "#7C3AED",
        "#BE123C"
    ]

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("documentTemplate.title", defaultValue: "PDF Şablonu"),
            subtitle: settingsStore.localized("documentTemplate.subtitle", defaultValue: "Hizmet dökümü PDF çıktısının başlık, renk, bölüm ve kolon görünümünü yönetin."),
            savedNotice: savedNotice,
            toolbar: {
                HStack(spacing: 10) {
                    Button {
                        draftSettings = localizedDefaultTemplate
                        save()
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("documentTemplate.reset", defaultValue: "Sıfırla"), systemImage: "arrow.counterclockwise", minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        save()
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("common.save", defaultValue: "Kaydet"), systemImage: "checkmark", minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        ) {
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

                ProWorkTextEditor(text: $draftSettings.footerNote, minHeight: 90)
                    .frame(maxWidth: 760)
            }
        }
        .onAppear {
            draftSettings = localizedTemplate(from: settingsStore.settings.serviceDocumentTemplateSettings)
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
        savedNotice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if savedNotice == message {
                savedNotice = nil
            }
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

        let cleaned = normalized.replacingOccurrences(of: "#", with: "")
        guard let value = UInt64(cleaned, radix: 16) else {
            return .accentColor
        }

        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0
        return Color(nsColor: NSColor(red: red, green: green, blue: blue, alpha: 1))
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
