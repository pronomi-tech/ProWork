//  ServiceDocumentTemplateSettings.swift
//  ProWork
//   Created by Pronomi.

import Foundation

struct ServiceDocumentTemplateSettings: Hashable, Codable {
    var title: String
    var showLogo: Bool
    var showHeaderDivider: Bool
    var showFooter: Bool
    var showLineNotes: Bool
    var showFinancialSummary: Bool
    var fontScale: Double
    var accentHexColor: String
    var footerNote: String

    nonisolated static let defaultTemplate = ServiceDocumentTemplateSettings(
        title: "Dönemsel Hizmet Dökümü",
        showLogo: true,
        showHeaderDivider: true,
        showFooter: true,
        showLineNotes: true,
        showFinancialSummary: true,
        fontScale: 1.0,
        accentHexColor: "#1F4E79",
        footerNote: "Bu belge, hizmet dökümü ve cari bilgilendirme amacıyla hazırlanmıştır. Fatura yerine geçmez."
    )

    var normalizedAccentHexColor: String {
        let trimmed = accentHexColor.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let candidate = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let isValid = candidate.count == 6 && candidate.allSatisfy { $0.isHexDigit }
        return isValid ? "#\(candidate)" : Self.defaultTemplate.accentHexColor
    }

    var normalizedFontScale: Double {
        min(max(fontScale, 0.9), 1.15)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case showLogo
        case showHeaderDivider
        case showFooter
        case showLineNotes
        case showFinancialSummary
        case fontScale
        case accentHexColor
        case footerNote
    }

    init(
        title: String,
        showLogo: Bool,
        showHeaderDivider: Bool,
        showFooter: Bool,
        showLineNotes: Bool,
        showFinancialSummary: Bool,
        fontScale: Double,
        accentHexColor: String,
        footerNote: String
    ) {
        self.title = title
        self.showLogo = showLogo
        self.showHeaderDivider = showHeaderDivider
        self.showFooter = showFooter
        self.showLineNotes = showLineNotes
        self.showFinancialSummary = showFinancialSummary
        self.fontScale = fontScale
        self.accentHexColor = accentHexColor
        self.footerNote = footerNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultTemplate

        title = try container.decodeIfPresent(String.self, forKey: .title) ?? defaults.title
        showLogo = try container.decodeIfPresent(Bool.self, forKey: .showLogo) ?? defaults.showLogo
        showHeaderDivider = try container.decodeIfPresent(Bool.self, forKey: .showHeaderDivider) ?? defaults.showHeaderDivider
        showFooter = try container.decodeIfPresent(Bool.self, forKey: .showFooter) ?? defaults.showFooter
        showLineNotes = try container.decodeIfPresent(Bool.self, forKey: .showLineNotes) ?? defaults.showLineNotes
        showFinancialSummary = try container.decodeIfPresent(Bool.self, forKey: .showFinancialSummary) ?? defaults.showFinancialSummary
        fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? defaults.fontScale
        accentHexColor = try container.decodeIfPresent(String.self, forKey: .accentHexColor) ?? defaults.accentHexColor
        footerNote = try container.decodeIfPresent(String.self, forKey: .footerNote) ?? defaults.footerNote
    }
}
