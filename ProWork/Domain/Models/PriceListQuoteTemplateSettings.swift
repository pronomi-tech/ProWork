//
//  PriceListQuoteTemplateSettings.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Fiyat listesini Teklif PDF'i olarak dışa aktarırken kullanılan şablon ayarları.
/// `ServiceDocumentTemplateSettings` ile paralel; sadece teklif belgesine özgüdür.
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
}
