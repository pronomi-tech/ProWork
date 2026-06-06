//  BillingPdfRenderer.swift
//  ProWork
//  Created by Pronomi.
//  Entry point of the PDF generation flow. The original 1.5K-line file was
//  split into four parts — this one keeps only type declarations, stored
//  state, and the `makePDFData` orchestration. Details:
//    - BillingPdfPagination.swift   — sayfa alokasyonu (allocateLines, allocatePayments)
//    - BillingPdfDrawing.swift      — every `draw*` call, colors, fonts
//    - BillingPdfFormatters.swift   — date / money / title text helpers

import AppKit
import Foundation

/// User-facing localised error. Previously, when the PDF render failed
/// we threw `CocoaError(.fileWriteUnknown)` — the user only saw an
/// unhelpful "The operation could not be completed" message. We now
/// expose a domain-specific LocalizedError instead.
enum BillingPdfRendererError: LocalizedError {
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return ProWorkLocalizer.shared.string(
                "pdf.error.contextFailed",
                defaultValue: "PDF render bağlamı oluşturulamadı. Yeterli bellek olduğundan emin olun ve yeniden deneyin."
            )
        }
    }
}

final class BillingPdfRenderer: Sendable {
    func render(bundle: BillingRunBundle) async throws -> Data {
        try await render(bundle: bundle, settings: .defaultTemplate)
    }

    /// Runs the PDF render off the main thread via `Task.detached`. AppKit
    /// `NSGraphicsContext.current` thread-local; renderer kendi context'ini
    /// is set up inside the detached task itself, so we don't hit thread-
    /// isolation issues. This keeps a long invoice from holding the
    /// main thread for seconds.
    func render(
        bundle: BillingRunBundle,
        settings: ServiceDocumentTemplateSettings
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            // Under default-MainActor isolation BillingPdfDocument gets implicit
            // MainActor; Task.detached nonisolated context'inden init/call
            // async actor hop gerektiriyor. `await` ile explicit.
            try await BillingPdfDocument(bundle: bundle, settings: settings).makePDFData()
        }.value
    }
}

final class BillingPdfDocument {
    let bundle: BillingRunBundle
    let settings: ServiceDocumentTemplateSettings

    // While rendering the PDF, allocating a fresh DateFormatter per row
    // was costing milliseconds (300+ formatters on a 100-row invoice).
    // The locale stays constant for the rendering lifetime; we build
    // the formatters once in init and reuse them.
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

    // Table column definitions don't change during the render — we
    // compute them on the first call and stash them here. `lineColumns()` /
    // `paymentColumns()` in the extension file read this cache.
    var cachedLineColumns: [TableColumn]?
    var cachedPaymentColumns: [TableColumn]?

    /// `currentBalanceMonies` and `hasOutstandingBalance` used
    /// to walk the same line + payment vectors twice. Computed once
    /// here and shared between the formatter accessors so a 1000-row
    /// invoice doesn't pay the dictionary build cost twice.
    private var cachedBalancesByCurrency: [String: Int]?
    func balancesByCurrency() -> [String: Int] {
        if let cached = cachedBalancesByCurrency {
            return cached
        }
        var balances: [String: Int] = [:]
        for line in bundle.lines {
            balances[line.currency, default: 0] += line.totalMinor
        }
        for payment in bundle.payments {
            balances[payment.currency, default: 0] -= payment.amountMinor
        }
        cachedBalancesByCurrency = balances
        return balances
    }

    // The same (text, width, font) measurement was being repeated 3-4
    // times across pagination + drawing. As a reference type we can now
    // memoize the measurements on the instance; on 1000-row reports
    // the allocate + boundingRect cost drops noticeably. The cache
    // accessors (`lookupMeasureCache`, `storeMeasureCache`) are called
    // from the extension files.
    //
    // Thread safety: `BillingPdfDocument` instances are
    // **not** Sendable and the `measureCache` is intentionally
    // unsynchronised. Every PDF render call constructs its own document
    // inside the renderer's `Task.detached` block (see
    // `BillingPdfRenderer.render`); the document is then accessed only
    // by that single task and discarded when `makePDFData()` returns.
    // Sharing a document across tasks would race on this dictionary.
    // If a future caller needs to reuse a document, wrap the cache in
    // an NSLock or convert to a concurrent map first.
    struct MeasureCacheKey: Hashable {
        let text: String
        let width: CGFloat
        let fontName: String
        let fontSize: CGFloat
        let bold: Bool
    }
    private var measureCache: [MeasureCacheKey: CGSize] = [:]

    func lookupMeasureCache(_ key: MeasureCacheKey) -> CGSize? {
        measureCache[key]
    }

    func storeMeasureCache(_ key: MeasureCacheKey, _ value: CGSize) {
        measureCache[key] = value
    }

    /// Logo image downsampled once at init time (Y6). Multi-page renders
    /// previously re-decoded the raw `logoData` on every header draw.
    let logoImage: NSImage?

    init(bundle: BillingRunBundle, settings: ServiceDocumentTemplateSettings) {
        self.bundle = bundle
        self.settings = settings

        let locale = Locale(identifier: ProWorkLocalizer.shared.language.localeIdentifier)

        // Previously these inline DateFormatters omitted
        // timezone, so PDF rendering on a non-Istanbul host could shift
        // displayed dates by ±a day at boundary times. Pin to Istanbul to
        // match the rest of the billing pipeline.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = AppCalendar.istanbul.timeZone
        dateFormatter.dateFormat = "dd.MM.yyyy"
        self.displayDateFormatter = dateFormatter

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = locale
        dateTimeFormatter.timeZone = AppCalendar.istanbul.timeZone
        dateTimeFormatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        self.displayDateTimeWithSecondsFormatter = dateTimeFormatter

        // LogoImage tek bir NSImage olarak tutuluyor, ama
        // When drawn as a CGImage per page, it gets embedded into the
        // PDF as a fresh XObject each time. The current `image.draw(in:)`
        // call (BillingPdfDrawing.swift) reuses a single bitmap; using
        // an NSImage flow with an API like CGPDFContextDrawPDFPage would
        // let a single XObject be shared inside the PDF. Worth revisiting
        // later for file-size optimisation — at today's typical logo size
        // (8-20 KB) the difference is small.
        self.logoImage = settings.showLogo
            ? PDFLogoLoader.downsampledImage(from: bundle.companyProfile?.logoData)
            : nil
    }

    func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    func makePDFData() throws -> Data {
        let mutableData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: mutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw BillingPdfRendererError.contextCreationFailed
        }

        let pages = paginate()

        for (pageIndex, page) in pages.enumerated() {
            // Y5: wrapping each page's `NSAttributedString` / `NSFont`
            // allocations in an autoreleasepool keeps peak memory in check;
            // makes a difference on multi-page reports.
            autoreleasepool {
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
        }

        context.closePDF()
        return mutableData as Data
    }
}

// MARK: - Support types
// Declared as nested inside BillingPdfDocument. Other types in the same module
// `PriceListQuotePdfRenderer.swift` de kendi `private struct RenderPage`'ini
// stays scoped; if these types were file-scope (internal), name collisions could occur.

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
