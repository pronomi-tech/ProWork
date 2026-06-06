//  PriceListQuoteTemplateSettingsView.swift
//  ProWork
//  Created by Pronomi.

import AppKit
import SwiftUI

struct PriceListQuoteTemplateSettingsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    /// Parent'tan gelen pulse trigger'lar — bkz. ServiceDocumentTemplate
    /// Explanation shown in SettingsView.
    let savePulse: UUID
    let resetPulse: UUID

    @State private var draft: PriceListQuoteTemplateSettings = .defaultTemplate
    /// The parent scaffold shows a single savedNotice; both views share the same binding.
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
        // Scaffold wrapping is in the parent DocumentTemplatesView; this view is content only.
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
            SettingsCard {
                Text(settingsStore.localized("quoteTemplate.section.general", defaultValue: "Belge Bilgileri"))
                    .proWorkTextStyle(.headline)

                formField(label: settingsStore.localized("quoteTemplate.field.documentLabel", defaultValue: "Belge Etiketi")) {
                    ProWorkTextField(placeholder: "TEKLİF", text: $draft.documentLabel)
                        .frame(maxWidth: 280)
                }

                formField(label: settingsStore.localized("quoteTemplate.field.titleTemplate", defaultValue: "Başlık Şablonu")) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProWorkTextField(placeholder: "{customerName} – Hizmet Teklifi", text: $draft.titleTemplate)
                            .frame(maxWidth: 480)
                        Text(settingsStore.localized("quoteTemplate.field.titleTemplate.hint", defaultValue: "Kullanılabilir: {customerName}, {year}, {priceListName}"))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                formField(label: settingsStore.localized("quoteTemplate.field.quoteNumberPrefix", defaultValue: "Teklif No Öneki")) {
                    ProWorkTextField(placeholder: "TKL", text: $draft.quoteNumberPrefix)
                        .frame(maxWidth: 160)
                }

                formField(label: settingsStore.localized("quoteTemplate.field.validityDays", defaultValue: "Geçerlilik (gün)")) {
                    Stepper(value: $draft.validityDays, in: 1...60) {
                        Text("\(draft.validityDays)")
                            .proWorkTextStyle(.callout, weight: .medium)
                            .frame(width: 40, alignment: .leading)
                    }
                    .frame(maxWidth: 180)
                }
            }

            SettingsCard {
                Text(settingsStore.localized("quoteTemplate.section.message", defaultValue: "Açılış ve İmza"))
                    .proWorkTextStyle(.headline)

                formField(label: settingsStore.localized("quoteTemplate.field.intro", defaultValue: "Açılış Paragrafı")) {
                    ProWorkTextEditor(text: $draft.introParagraph, minHeight: 90)
                        .frame(maxWidth: 760)
                }

                formField(label: settingsStore.localized("quoteTemplate.field.closing", defaultValue: "Kapanış")) {
                    ProWorkTextField(placeholder: "Saygılarımızla", text: $draft.closing)
                        .frame(maxWidth: 280)
                }

                formField(label: settingsStore.localized("quoteTemplate.field.signerName", defaultValue: "İmza Atan")) {
                    ProWorkTextField(placeholder: "", text: $draft.signerName)
                        .frame(maxWidth: 320)
                }

                formField(label: settingsStore.localized("quoteTemplate.field.signerTitle", defaultValue: "Ünvan")) {
                    ProWorkTextField(placeholder: "", text: $draft.signerTitle)
                        .frame(maxWidth: 320)
                }
            }

            SettingsCard {
                Text(settingsStore.localized("quoteTemplate.section.terms", defaultValue: "Şartlar"))
                    .proWorkTextStyle(.headline)

                Text(settingsStore.localized("quoteTemplate.terms.hint", defaultValue: "Her satır ayrı madde olarak görünür. Kullanılabilir: {validityDays}, {validUntil}, {quoteNumber}."))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                formField(label: settingsStore.localized("quoteTemplate.field.commercialTerms", defaultValue: "Ticari Şartlar")) {
                    bulletListEditor(items: $draft.commercialTerms)
                }

                formField(label: settingsStore.localized("quoteTemplate.field.serviceTerms", defaultValue: "Hizmet Koşulları")) {
                    bulletListEditor(items: $draft.serviceTerms)
                }
            }

            SettingsCard {
                Text(settingsStore.localized("quoteTemplate.section.appearance", defaultValue: "Görünüm"))
                    .proWorkTextStyle(.headline)

                formField(label: settingsStore.localized("documentTemplate.field.fontScale", defaultValue: "Font Ölçeği")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Slider(value: $draft.fontScale, in: 0.9...1.15, step: 0.05)
                        Text("%\(Int(draft.normalizedFontScale * 100))")
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
                                    draft.accentHexColor = hex
                                } label: {
                                    Circle()
                                        .fill(color(for: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Circle()
                                                .stroke(draft.normalizedAccentHexColor == hex ? Color.primary : .clear, lineWidth: 2)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ProWorkTextField(placeholder: "#1F4E79", text: $draft.accentHexColor)
                            .frame(maxWidth: 180)
                    }
                }

                toggleRow(settingsStore.localized("quoteTemplate.toggle.showCoverPage", defaultValue: "Kapak sayfası göster"), isOn: $draft.showCoverPage)
                toggleRow(settingsStore.localized("quoteTemplate.toggle.showFromToBlock", defaultValue: "Kimden / Kime kartları"), isOn: $draft.showFromToBlock)
                toggleRow(settingsStore.localized("quoteTemplate.toggle.showSummaryBar", defaultValue: "Özet şeridi"), isOn: $draft.showFinancialSummaryBar)
                toggleRow(settingsStore.localized("quoteTemplate.toggle.showSignatureBlock", defaultValue: "İmza bloğu"), isOn: $draft.showSignatureBlock)
                toggleRow(settingsStore.localized("documentTemplate.toggle.showLogo", defaultValue: "Logo göster"), isOn: $draft.showLogo)
                toggleRow(settingsStore.localized("documentTemplate.toggle.showHeaderDivider", defaultValue: "Antet ayırıcı çizgisi"), isOn: $draft.showHeaderDivider)
                toggleRow(settingsStore.localized("documentTemplate.toggle.showFooter", defaultValue: "Footer göster"), isOn: $draft.showFooter)
            }

            SettingsCard {
                Text(settingsStore.localized("quoteTemplate.section.footer", defaultValue: "Footer Satırı"))
                    .proWorkTextStyle(.headline)

                Text(settingsStore.localized("quoteTemplate.footer.hint", defaultValue: "Kullanılabilir: {address}, {phone}, {email}, {website}"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                ProWorkTextField(placeholder: "{address} • {phone} • {website}", text: $draft.footerCenterLine)
                    .frame(maxWidth: 760)
            }
        }
        .onAppear {
            draft = settingsStore.settings.priceListQuoteTemplateSettings
        }
        // Parent pulse triggers — save/reset when this is the active tab.
        .onChange(of: savePulse) { _, _ in
            save()
        }
        .onChange(of: resetPulse) { _, _ in
            // Language-appropriate factory.
            draft = .defaultTemplate(for: settingsStore.settings.language)
            save()
        }
    }

    private func bulletListEditor(items: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .proWorkFont(size: 5)
                        .foregroundStyle(.secondary)
                    ProWorkTextField(placeholder: "", text: items[index])
                    Button {
                        var array = items.wrappedValue
                        array.remove(at: index)
                        items.wrappedValue = array
                    } label: {
                        Image(systemName: "minus.circle").proWorkFont(size: 14)
                    }
                    .buttonStyle(.borderless)
                    .help(settingsStore.localized("common.remove", defaultValue: "Kaldır"))
                }
            }
            Button {
                var array = items.wrappedValue
                array.append("")
                items.wrappedValue = array
            } label: {
                ProWorkButtonLabel(title: settingsStore.localized("quoteTemplate.terms.add", defaultValue: "Madde ekle"), systemImage: "plus", minHeight: 26)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func save() {
        draft.commercialTerms = draft.commercialTerms.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        draft.serviceTerms = draft.serviceTerms.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        draft.accentHexColor = draft.normalizedAccentHexColor
        if draft.documentLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.documentLabel = PriceListQuoteTemplateSettings.defaultTemplate.documentLabel
        }
        if draft.titleTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.titleTemplate = PriceListQuoteTemplateSettings.defaultTemplate.titleTemplate
        }
        if draft.quoteNumberPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.quoteNumberPrefix = PriceListQuoteTemplateSettings.defaultTemplate.quoteNumberPrefix
        }
        settingsStore.updatePriceListQuoteTemplateSettings(draft)
        setSavedNotice(settingsStore.localized("quoteTemplate.notice.saved", defaultValue: "Teklif şablonu kaydedildi."))
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

    /// Shared hex parser supports #RGB / #RRGGBB / #RRGGBBAA
    /// since widened `PDFDrawingPrimitives.nsColor(fromHex:)`.
    private func color(for hex: String) -> Color {
        guard let nsColor = PDFDrawingPrimitives.nsColor(fromHex: hex) else {
            return .accentColor
        }
        return Color(nsColor: nsColor)
    }
}
