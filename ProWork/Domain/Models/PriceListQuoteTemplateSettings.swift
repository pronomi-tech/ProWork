//  PriceListQuoteTemplateSettings.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Template settings used when exporting a price list as a Quote PDF.
/// Parallel to `ServiceDocumentTemplateSettings`; specific to the quote document.
///
/// Bumps a `schemaVersion` on every persisted instance so a
/// future field rename/removal can detect a payload it can't decode
/// rather than silently dropping it via `decodeIfPresent` (the
/// rename target would land at the default while the renamed key
/// silently disappears). Current shape is version 1; encode/decode
/// keep accepting unversioned payloads as v1 for backward compat.
///
/// The literal Turkish defaults are kept for
/// backward compat with the existing on-disk JSON, but the
/// `defaultTemplate(for:)` factory below seeds an English variant
/// when `AppLanguage` is `.english`. Switching language in Settings
/// stamps the new defaults only when the user explicitly resets;
/// existing customisations are preserved.
struct PriceListQuoteTemplateSettings: Hashable, Codable {
    var documentLabel: String
    var titleTemplate: String
    var quoteNumberPrefix: String
    var validityDays: Int
    var introParagraph: String
    var closing: String
    var signerName: String
    var signerTitle: String
    var commercialTerms: [String]
    var serviceTerms: [String]
    var showCoverPage: Bool
    var showFromToBlock: Bool
    var showFinancialSummaryBar: Bool
    var showSignatureBlock: Bool
    var showHeaderDivider: Bool
    var showLogo: Bool
    var showFooter: Bool
    var fontScale: Double
    var accentHexColor: String
    var footerCenterLine: String

    /// Schema marker. Bump when the field set changes in a
    /// non-additive way (rename, removal). The decoder rejects
    /// payloads with a higher version than the runtime supports so a
    /// downgrade can't silently mis-restore.
    static let currentSchemaVersion = 1

    /// Locale-aware factory. The default-template
    /// constant remains TR-only for backward compat; new English
    /// installations get TR-language UI today, so the existing
    /// constant stays canonical. Calls that want a language-specific
    /// reset should use this factory.
    static func defaultTemplate(for language: AppLanguage) -> PriceListQuoteTemplateSettings {
        switch language {
        case .turkish:
            return defaultTemplate
        case .english:
            return PriceListQuoteTemplateSettings(
                documentLabel: "QUOTE",
                titleTemplate: "{customerName} – Service Quote",
                quoteNumberPrefix: "QTE",
                validityDays: 7,
                introParagraph: "The pricing for the services requested by your company is detailed below. We hope this proposal meets your expectations and look forward to a successful collaboration.",
                closing: "Best regards",
                signerName: "",
                signerTitle: "",
                commercialTerms: [
                    "Prices are exclusive of VAT.",
                    "This proposal is valid for {validityDays} days.",
                    "An invoice is issued on the 10th of the following month for each month of service."
                ],
                serviceTerms: [
                    "Service fees correspond to one hour of work by one staff member.",
                    "Working time is rounded up to the next full hour.",
                    "Travel time is included in the on-site service scope.",
                    "Off-hours and holiday work requires prior approval."
                ],
                showCoverPage: true,
                showFromToBlock: true,
                showFinancialSummaryBar: true,
                showSignatureBlock: false,
                showHeaderDivider: true,
                showLogo: true,
                showFooter: true,
                fontScale: 1.0,
                accentHexColor: "#1F4E79",
                footerCenterLine: "{address} • {phone} • {website}"
            )
        }
    }

    nonisolated static let defaultTemplate = PriceListQuoteTemplateSettings(
        documentLabel: "TEKLİF",
        titleTemplate: "{customerName} – Hizmet Teklifi",
        quoteNumberPrefix: "TKL",
        validityDays: 7,
        introParagraph: "Talepleriniz doğrultusunda firmanıza sunacağımız hizmetlere ilişkin fiyat teklifimiz aşağıda detaylarıyla yer almaktadır. Teklifimizin beklentilerinizi karşılayacağını ümit eder, başarılı bir iş birliği temenni ederiz.",
        closing: "Saygılarımızla",
        signerName: "",
        signerTitle: "",
        commercialTerms: [
            "Fiyatlarımıza KDV dâhil değildir.",
            "Teklifimiz {validityDays} gün süre ile geçerlidir.",
            "Hizmet verilen her ay için sonraki ayın 10. günü fatura kesilir."
        ],
        serviceTerms: [
            "Hizmet bedeli bir personelin saatlik çalışması karşılığıdır.",
            "Çalışma süresi çözünürlüğü bir saattir. Bir saatin altında kalan süre bir saate tamamlanarak toplam harcanan süreye ulaşılır.",
            "Yerinde verilen hizmetlerde ulaşım süreleri hizmet kapsamında değerlendirilir.",
            "Tatil ve mesai dışı hizmetler için önceden onay alınması gerekmektedir."
        ],
        showCoverPage: true,
        showFromToBlock: true,
        showFinancialSummaryBar: true,
        showSignatureBlock: false,
        showHeaderDivider: true,
        showLogo: true,
        showFooter: true,
        fontScale: 1.0,
        accentHexColor: "#1F4E79",
        footerCenterLine: "{address} • {phone} • {website}"
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

    var normalizedValidityDays: Int {
        max(1, validityDays)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case documentLabel
        case titleTemplate
        case quoteNumberPrefix
        case validityDays
        case introParagraph
        case closing
        case signerName
        case signerTitle
        case commercialTerms
        case serviceTerms
        case showCoverPage
        case showFromToBlock
        case showFinancialSummaryBar
        case showSignatureBlock
        case showHeaderDivider
        case showLogo
        case showFooter
        case fontScale
        case accentHexColor
        case footerCenterLine
    }

    init(
        documentLabel: String,
        titleTemplate: String,
        quoteNumberPrefix: String,
        validityDays: Int,
        introParagraph: String,
        closing: String,
        signerName: String,
        signerTitle: String,
        commercialTerms: [String],
        serviceTerms: [String],
        showCoverPage: Bool,
        showFromToBlock: Bool,
        showFinancialSummaryBar: Bool,
        showSignatureBlock: Bool,
        showHeaderDivider: Bool,
        showLogo: Bool,
        showFooter: Bool,
        fontScale: Double,
        accentHexColor: String,
        footerCenterLine: String
    ) {
        self.documentLabel = documentLabel
        self.titleTemplate = titleTemplate
        self.quoteNumberPrefix = quoteNumberPrefix
        self.validityDays = validityDays
        self.introParagraph = introParagraph
        self.closing = closing
        self.signerName = signerName
        self.signerTitle = signerTitle
        self.commercialTerms = commercialTerms
        self.serviceTerms = serviceTerms
        self.showCoverPage = showCoverPage
        self.showFromToBlock = showFromToBlock
        self.showFinancialSummaryBar = showFinancialSummaryBar
        self.showSignatureBlock = showSignatureBlock
        self.showHeaderDivider = showHeaderDivider
        self.showLogo = showLogo
        self.showFooter = showFooter
        self.fontScale = fontScale
        self.accentHexColor = accentHexColor
        self.footerCenterLine = footerCenterLine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaultTemplate

        // Schema-version forward-compat refusal. Same pattern
        // as DraftLineSelectionState: an unknown future version is
        // rejected with a typed decoding error so callers don't get
        // an "every field reset" silent regression.
        let decodedVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        if decodedVersion > Self.currentSchemaVersion {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported PriceListQuoteTemplateSettings schemaVersion \(decodedVersion); maximum supported is \(Self.currentSchemaVersion)."
            )
        }
        // Synthesised encode(to:) would try to read a stored
        // `schemaVersion` property; we own the encoder below so
        // there's no field on the struct. Decoded versions are
        // accepted into the runtime model implicitly as v1.
        documentLabel = try container.decodeIfPresent(String.self, forKey: .documentLabel) ?? d.documentLabel
        titleTemplate = try container.decodeIfPresent(String.self, forKey: .titleTemplate) ?? d.titleTemplate
        quoteNumberPrefix = try container.decodeIfPresent(String.self, forKey: .quoteNumberPrefix) ?? d.quoteNumberPrefix
        validityDays = try container.decodeIfPresent(Int.self, forKey: .validityDays) ?? d.validityDays
        introParagraph = try container.decodeIfPresent(String.self, forKey: .introParagraph) ?? d.introParagraph
        closing = try container.decodeIfPresent(String.self, forKey: .closing) ?? d.closing
        signerName = try container.decodeIfPresent(String.self, forKey: .signerName) ?? d.signerName
        signerTitle = try container.decodeIfPresent(String.self, forKey: .signerTitle) ?? d.signerTitle
        commercialTerms = try container.decodeIfPresent([String].self, forKey: .commercialTerms) ?? d.commercialTerms
        serviceTerms = try container.decodeIfPresent([String].self, forKey: .serviceTerms) ?? d.serviceTerms
        showCoverPage = try container.decodeIfPresent(Bool.self, forKey: .showCoverPage) ?? d.showCoverPage
        showFromToBlock = try container.decodeIfPresent(Bool.self, forKey: .showFromToBlock) ?? d.showFromToBlock
        showFinancialSummaryBar = try container.decodeIfPresent(Bool.self, forKey: .showFinancialSummaryBar) ?? d.showFinancialSummaryBar
        showSignatureBlock = try container.decodeIfPresent(Bool.self, forKey: .showSignatureBlock) ?? d.showSignatureBlock
        showHeaderDivider = try container.decodeIfPresent(Bool.self, forKey: .showHeaderDivider) ?? d.showHeaderDivider
        showLogo = try container.decodeIfPresent(Bool.self, forKey: .showLogo) ?? d.showLogo
        showFooter = try container.decodeIfPresent(Bool.self, forKey: .showFooter) ?? d.showFooter
        fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? d.fontScale
        accentHexColor = try container.decodeIfPresent(String.self, forKey: .accentHexColor) ?? d.accentHexColor
        footerCenterLine = try container.decodeIfPresent(String.self, forKey: .footerCenterLine) ?? d.footerCenterLine
    }

    /// Custom encode is required because `schemaVersion` is in CodingKeys
    /// without a stored property — the synthesised encoder would
    /// otherwise refuse to compile. Writes `currentSchemaVersion`
    /// explicitly so future loads can detect the format.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(documentLabel, forKey: .documentLabel)
        try container.encode(titleTemplate, forKey: .titleTemplate)
        try container.encode(quoteNumberPrefix, forKey: .quoteNumberPrefix)
        try container.encode(validityDays, forKey: .validityDays)
        try container.encode(introParagraph, forKey: .introParagraph)
        try container.encode(closing, forKey: .closing)
        try container.encode(signerName, forKey: .signerName)
        try container.encode(signerTitle, forKey: .signerTitle)
        try container.encode(commercialTerms, forKey: .commercialTerms)
        try container.encode(serviceTerms, forKey: .serviceTerms)
        try container.encode(showCoverPage, forKey: .showCoverPage)
        try container.encode(showFromToBlock, forKey: .showFromToBlock)
        try container.encode(showFinancialSummaryBar, forKey: .showFinancialSummaryBar)
        try container.encode(showSignatureBlock, forKey: .showSignatureBlock)
        try container.encode(showHeaderDivider, forKey: .showHeaderDivider)
        try container.encode(showLogo, forKey: .showLogo)
        try container.encode(showFooter, forKey: .showFooter)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(accentHexColor, forKey: .accentHexColor)
        try container.encode(footerCenterLine, forKey: .footerCenterLine)
    }
}
