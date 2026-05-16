//
//  BillingPdfRenderer.swift
//  ProWork
//
//  Created by Pronomi.
//
//  PDF üretim akışının giriş noktası. 1.5K satırlık tek dosyayı dört parçaya
//  böldük — bu dosyada yalnızca tip bildirimleri, stored state ve `makePDFData`
//  orkestrasyonu kalıyor. Detaylar:
//    - BillingPdfPagination.swift   — sayfa alokasyonu (allocateLines, allocatePayments)
//    - BillingPdfDrawing.swift      — tüm `draw*` çağrıları, renkler, font'lar
//    - BillingPdfFormatters.swift   — tarih / para / başlık metin yardımcıları
//

import AppKit
import Foundation

final class BillingPdfRenderer {
    @MainActor
    func render(bundle: BillingRunBundle) async throws -> Data {
        try await render(bundle: bundle, settings: .defaultTemplate)
    }

    @MainActor
    func render(
        bundle: BillingRunBundle,
        settings: ServiceDocumentTemplateSettings
    ) async throws -> Data {
        try BillingPdfDocument(bundle: bundle, settings: settings).makePDFData()
    }
}

@MainActor
struct BillingPdfDocument {
    let bundle: BillingRunBundle
    let settings: ServiceDocumentTemplateSettings

    // PDF render edilirken her satır için yeni DateFormatter yaratmak
    // milisaniyeler harcıyordu (100 satırlık invoice'ta 300+ formatter).
    // Locale rendering ömrü boyunca sabit; formatter'ları init'te bir kez
    // kurup tekrar kullanıyoruz.
    let displayDateFormatter: DateFormatter
    let displayDateTimeWithSecondsFormatter: DateFormatter

    let pageSize = CGSize(width: 595, height: 842)
    let marginLeft: CGFloat = 42
    let marginRight: CGFloat = 42
    let marginTop: CGFloat = 20
    let marginBottom: CGFloat = 22
    let footerHeight: CGFloat = 44
    let lineGap: CGFloat = 10
    let sectionGap: CGFloat = 18
    let tableSectionGap: CGFloat = 12
    let currencyTableTitleHeight: CGFloat = 22

    init(bundle: BillingRunBundle, settings: ServiceDocumentTemplateSettings) {
        self.bundle = bundle
        self.settings = settings

        let locale = Locale(identifier: ProWorkLocalizer.shared.language.localeIdentifier)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateFormat = "dd.MM.yyyy"
        self.displayDateFormatter = dateFormatter

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = locale
        dateTimeFormatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        self.displayDateTimeWithSecondsFormatter = dateTimeFormatter
    }

    func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    func makePDFData() throws -> Data {
        let mutableData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: mutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let pages = paginate()

        for (pageIndex, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            draw(page: page, pageIndex: pageIndex, totalPages: pages.count)

            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return mutableData as Data
    }
}

// MARK: - Support types
//
// BillingPdfDocument içinde nested olarak tanımlıyoruz. Aynı modüldeki
// `PriceListQuotePdfRenderer.swift` de kendi `private struct RenderPage`'ini
// tutuyor; tipler dosya kapsamında olsaydı (internal) ad çakışması olurdu.

extension BillingPdfDocument {
    struct RenderPage {
        var showsLineSection = false
        var linePageIndex = 0
        var lineTables: [CurrencyTableChunk] = []
        var showsEmptyLines = false
        var showsLineTotals = false
        var showsPaymentsSection = false
        var paymentPageIndex = 0
        var paymentTables: [CurrencyTableChunk] = []
        var showsEmptyPayments = false
        var showsPaymentTotals = false
    }

    struct CurrencyIndexedSection {
        let currency: String
        let indices: [Int]
    }

    struct CurrencyTableChunk {
        let currency: String
        let isContinuation: Bool
        var indices: [Int] = []
    }

    struct TableColumn {
        let id: String
        let title: String
        let width: CGFloat
        var alignment: NSTextAlignment = .left
    }

    struct ColumnFrame {
        let id: String
        let title: String
        let rect: CGRect
        let alignment: NSTextAlignment
    }
}
