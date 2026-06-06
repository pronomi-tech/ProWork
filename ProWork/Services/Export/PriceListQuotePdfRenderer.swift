//  PriceListQuotePdfRenderer.swift
//  ProWork
//  Created by Pronomi.

import AppKit
import Foundation
import os

/// Price list → Quote PDF renderer.
/// Produces cover page + service sections + commercial terms + (optional) signature block.
///
/// Render off-main via `Task.detached`, mirroring the
/// `BillingPdfRenderer` pattern. AppKit `NSGraphicsContext.current` is
/// thread-local and the renderer builds its own context, so the document
/// does not need MainActor isolation. The previous `@MainActor` pin
/// blocked the UI for the full render duration on multi-page quotes.
final class PriceListQuotePdfRenderer: Sendable {
    func render(bundle: PriceListQuoteBundle) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            // Under default-MainActor isolation PriceListQuotePdfDocument
            // gets implicit MainActor isolation; when called from
            // Task.detached's nonisolated context the actor hop becomes
            // async. We make it explicit with `await`.
            try await PriceListQuotePdfDocument(bundle: bundle).makePDFData()
        }.value
    }
}

private final class PriceListQuotePdfDocument {
    let bundle: PriceListQuoteBundle

    /// Y6: single decode, downsampled logo. Previously, `NSImage(data:)`
    /// was decoding the logo again on every header draw call.
    let logoImage: NSImage?

    private let pageSize = CGSize(width: 595, height: 842)
    private let marginLeft: CGFloat = 48
    private let marginRight: CGFloat = 48
    private let marginTop: CGFloat = 28
    private let marginBottom: CGFloat = 26
    private let footerHeight: CGFloat = 36
    private let sectionGap: CGFloat = 18

    private var settings: PriceListQuoteTemplateSettings { bundle.settings }

    init(bundle: PriceListQuoteBundle) {
        self.bundle = bundle
        self.logoImage = bundle.settings.showLogo
            ? PDFLogoLoader.downsampledImage(from: bundle.companyProfile?.logoData)
            : nil
    }

    func makePDFData() throws -> Data {
        let mutableData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: mutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            // Shared error type for a user-friendly message.
            throw BillingPdfRendererError.contextCreationFailed
        }

        let pages = paginate()

        for (index, page) in pages.enumerated() {
            // Y5/Y6: per-page autoreleasepool to keep peak memory down.
            autoreleasepool {
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: 0, y: pageSize.height)
                context.scaleBy(x: 1, y: -1)

                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

                draw(page: page, pageIndex: index, totalPages: pages.count)

                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()
                context.endPDFPage()
            }
        }

        context.closePDF()
        return mutableData as Data
    }

    // MARK: - Pagination

    private func paginate() -> [RenderPage] {
        var pages: [RenderPage] = []

        if settings.showCoverPage {
            pages.append(.cover)
        }

        var current = RenderPage.content(blocks: [])
        var remaining = contentPageAvailableHeight

        func push(_ block: ContentBlock) {
            let needed = blockHeight(block)
            if needed > remaining, !current.blocks.isEmpty {
                pages.append(current)
                current = .content(blocks: [])
                remaining = contentPageAvailableHeight
            }
            current.blocks.append(block)
            remaining -= needed
        }

        // Page 1 (or post-cover): title + recipient block (if missing from cover)
        if !settings.showCoverPage {
            push(.documentTitle)
        }

        if settings.showFromToBlock && !settings.showCoverPage {
            push(.fromTo)
        }

        if settings.showFinancialSummaryBar && !settings.showCoverPage {
            push(.summaryBar)
        }

        push(.intro)

        for section in bundle.sections {
            push(.sectionHeader(section))
            push(.sectionTableHeader)
            for line in section.lines {
                push(.sectionRow(line))
            }
        }

        // Terms block renders as a single atomic card. When
        // height exceeds the available page space, pagination pushes
        // the whole block to the next page; if it exceeds an entire
        // page (rare today, plausible with a long custom-terms list)
        // the bottom content is silently clipped because the
        // single-block layout can't split. Splitting would require
        // breaking the card into a `RenderBlock.termsRow(item)`
        // sequence with per-item heights — deferred until a real
        // overflow shows up. Until then, oversized terms log a
        // warning at paginate time so the gap is debuggable.
        push(.terms)

        if settings.showSignatureBlock {
            push(.signature)
        }

        if !current.blocks.isEmpty {
            pages.append(current)
        }

        if pages.isEmpty {
            pages.append(.content(blocks: []))
        }

        return pages
    }

    private func blockHeight(_ block: ContentBlock) -> CGFloat {
        switch block {
        case .documentTitle:
            return 56
        case .fromTo:
            return fromToBlockHeight
        case .summaryBar:
            return 78
        case .intro:
            return introBlockHeight
        case .sectionHeader(let section):
            let subtitleExtra: CGFloat = (section.subtitle?.isEmpty == false) ? 16 : 0
            return 32 + subtitleExtra + 8
        case .sectionTableHeader:
            return 26
        case .sectionRow(let line):
            return rowHeight(for: line)
        case .terms:
            let height = termsBlockHeight
            let availableHeight = contentPageAvailableHeight
            if height > availableHeight {
                ProWorkLog.export.warning(
                    "PriceListQuotePdfRenderer: terms block height \(height, privacy: .public)pt exceeds available page \(availableHeight, privacy: .public)pt; bottom content will be clipped because the block is rendered atomically."
                )
            }
            return height
        case .signature:
            return 96
        }
    }

    private var contentPageAvailableHeight: CGFloat {
        pageSize.height - marginTop - marginBottom - footerHeight - headerHeight - 8
    }

    private var headerHeight: CGFloat {
        settings.showLogo ? 56 : 40
    }

    private var fromToBlockHeight: CGFloat {
        fromToCardHeight + sectionGap
    }

    private var fromToCardHeight: CGFloat {
        let cardWidth = (contentWidth - 12) / 2
        let senderHeight = cardContentHeight(for: senderRows(), cardWidth: cardWidth)
        let recipientHeight = cardContentHeight(for: recipientRows(), cardWidth: cardWidth)
        return max(senderHeight, recipientHeight)
    }

    /// Total height of a "From / To" card based on its content — title + name line +
    /// the measured height of each body line + top/bottom padding.
    private func cardContentHeight(for rows: [(String, String)], cardWidth: CGFloat) -> CGFloat {
        guard !rows.isEmpty else { return 64 }

        let nameValueWidth = cardWidth - 28
        let nameHeight = max(
            16,
            measureText(rows[0].1, width: nameValueWidth, font: font(10.5, weight: .bold)).height
        )

        var bodyHeight: CGFloat = 0
        for row in rows.dropFirst() {
            bodyHeight += cardBodyRowHeight(row: row, cardWidth: cardWidth)
        }

        // 12 top + 12 title + 8 gap + name + 6 gap + body + 12 bottom padding
        return 12 + 12 + 8 + nameHeight + 6 + bodyHeight + 12
    }

    /// Measured height of a single body line + bottom spacing.
    private func cardBodyRowHeight(row: (String, String), cardWidth: CGFloat) -> CGFloat {
        let label = row.0
        let value = row.1
        let valueWidth: CGFloat = label.isEmpty
            ? cardWidth - 28
            : cardWidth * 0.6 - 28
        let valueHeight = measureText(value, width: valueWidth, font: font(8.4, weight: label.isEmpty ? .regular : .medium)).height
        let labelHeight: CGFloat = label.isEmpty
            ? 0
            : measureText(label, width: cardWidth * 0.34, font: font(7.8)).height
        return max(14, max(valueHeight, labelHeight) + 4)
    }

    private var introBlockHeight: CGFloat {
        let width = contentWidth
        let intro = measureText(
            substituteTemplateVariables(settings.introParagraph),
            width: width,
            font: font(9.5)
        ).height
        let topSpacing: CGFloat = 18
        let greetingHeight: CGFloat = 20
        let introToClosingGap: CGFloat = 16

        // Total height of the closing line + (if present) the signature block + stamp allowance.
        var signatureBlockHeight: CGFloat = 14 // closing line
        if !settings.signerName.isEmpty {
            signatureBlockHeight += 18 + 14 // gap + name
            if !settings.signerTitle.isEmpty {
                signatureBlockHeight += 14 // title
            }
            signatureBlockHeight += 32 // stamp allowance
        } else {
            signatureBlockHeight += 12
        }

        return topSpacing + greetingHeight + intro + introToClosingGap + signatureBlockHeight + sectionGap
    }

    private var termsBlockHeight: CGFloat {
        // 14pt top spacing + card content
        return 14 + termsCardHeight + sectionGap
    }

    private var termsCardHeight: CGFloat {
        let columnWidth = (contentWidth - 16) / 2
        let commercialBody = settings.commercialTerms
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { substituteTemplateVariables($0) }
            .reduce(CGFloat(0)) { partial, item in
                partial + measureText(item, width: columnWidth - 44, font: font(8.6)).height + 6
            }
        let serviceBody = settings.serviceTerms
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { substituteTemplateVariables($0) }
            .reduce(CGFloat(0)) { partial, item in
                partial + measureText(item, width: columnWidth - 44, font: font(8.6)).height + 6
            }
        let bodyHeight = max(commercialBody, serviceBody)
        // 26 (header zone) + body + 12 (bottom padding)
        return 26 + bodyHeight + 12
    }

    private func rowHeight(for line: PriceListQuoteBundle.Line) -> CGFloat {
        let descColumnWidth = lineDescriptionWidth
        let primary = measureText(line.primaryDescription, width: descColumnWidth, font: font(9.5, weight: .semibold)).height
        let secondary: CGFloat = {
            guard let text = line.secondaryDescription, !text.isEmpty else { return 0 }
            return measureText(text, width: descColumnWidth, font: font(7.9)).height + 2
        }()
        return max(34, primary + secondary + 16)
    }

    // MARK: - Drawing

    private func draw(page: RenderPage, pageIndex: Int, totalPages: Int) {
        if page.isCover {
            drawCoverPage()
            return
        }

        var y = drawHeader(at: marginTop, pageIndex: pageIndex)
        y += 6

        for block in page.blocks {
            switch block {
            case .documentTitle:
                y = drawDocumentTitle(at: y)
            case .fromTo:
                y = drawFromTo(at: y)
            case .summaryBar:
                y = drawSummaryBar(at: y)
            case .intro:
                y = drawIntro(at: y)
            case .sectionHeader(let section):
                y = drawSectionHeader(section, at: y)
            case .sectionTableHeader:
                y = drawSectionTableHeader(at: y)
            case .sectionRow(let line):
                y = drawSectionRow(line, at: y)
            case .terms:
                y = drawTermsBlock(at: y)
            case .signature:
                y = drawSignatureBlock(at: y)
            }
        }

        drawFooter(pageIndex: pageIndex, totalPages: totalPages)
    }

    // MARK: - Cover

    private func drawCoverPage() {
        // Top accent band
        let bandRect = CGRect(x: 0, y: 0, width: pageSize.width, height: 130)
        accentColor.setFill()
        bandRect.fill()

        // Logo or company name (inside the band)
        if let image = logoImage {
            let logoFrame = CGRect(x: marginLeft, y: 38, width: 200, height: 56)
            // White background card
            drawRoundedRect(logoFrame.insetBy(dx: -8, dy: -8), fill: .white, stroke: .clear, radius: 12)
            image.draw(in: fitRect(sourceSize: image.size, inside: logoFrame))
        } else {
            _ = drawText(
                companyDisplayName,
                at: CGRect(x: marginLeft, y: 60, width: contentWidth, height: 32),
                font: font(22, weight: .bold),
                color: .white
            )
        }

        // Small company meta in the top-right
        if let companyMeta = coverCompanyMetaText {
            _ = drawText(
                companyMeta,
                at: CGRect(
                    x: pageSize.width - marginRight - 220,
                    y: 50,
                    width: 220,
                    height: 60
                ),
                font: font(8),
                color: .white.withAlphaComponent(0.85),
                alignment: .right
            )
        }

        // Cover content — middle
        var y: CGFloat = 196

        // Belge etiketi (caps)
        _ = drawText(
            settings.documentLabel.uppercased(),
            at: CGRect(x: marginLeft, y: y, width: contentWidth, height: 18),
            font: font(11, weight: .heavy),
            color: accentColor
        )
        y += 26

        // Title (large)
        let titleHeight = measureText(bundle.titleText, width: contentWidth, font: font(28, weight: .bold)).height
        _ = drawText(
            bundle.titleText,
            at: CGRect(x: marginLeft, y: y, width: contentWidth, height: titleHeight + 8),
            font: font(28, weight: .bold),
            color: primaryTextColor
        )
        y += titleHeight + 18

        // Quote no rozeti
        let badgeText = String(format: localized("quote.numberBadge", defaultValue: "Teklif No: %@"), bundle.quoteNumber)
        let badgeWidth: CGFloat = measureText(badgeText, width: 400, font: font(10, weight: .semibold)).width + 32
        let badgeRect = CGRect(x: marginLeft, y: y, width: badgeWidth, height: 28)
        drawRoundedRect(badgeRect, fill: accentBackgroundColor, stroke: .clear, radius: 14)
        _ = drawText(
            badgeText,
            at: badgeRect.insetBy(dx: 14, dy: 6),
            font: font(10, weight: .semibold),
            color: accentColor
        )
        y += 50

        // Cover From/To cards
        if settings.showFromToBlock {
            y = drawFromTo(at: y)
        } else {
            y += sectionGap
        }

        // Summary strip (also on the cover)
        if settings.showFinancialSummaryBar {
            _ = drawSummaryBar(at: y)
        }
    }

    // MARK: - Header / Footer

    private func drawHeader(at y: CGFloat, pageIndex: Int) -> CGFloat {
        // If there's a cover, post-cover pages use a plain header
        let logoFrame = CGRect(x: marginLeft, y: y, width: 180, height: 44)
        if let image = logoImage {
            image.draw(in: fitRect(sourceSize: image.size, inside: logoFrame))
        } else {
            _ = drawText(
                companyDisplayName,
                at: CGRect(x: marginLeft, y: y + 4, width: contentWidth * 0.55, height: 18),
                font: font(13, weight: .bold),
                color: accentColor
            )
            if let address = clean(bundle.companyProfile?.address) {
                _ = drawText(
                    address,
                    at: CGRect(x: marginLeft, y: y + 22, width: contentWidth * 0.55, height: 16),
                    font: font(7.8),
                    color: secondaryTextColor
                )
            }
        }

        // Quote number & date in the top-right
        let metaText = String(
            format: "%@\n%@",
            String(format: localized("quote.numberBadge", defaultValue: "Teklif No: %@"), bundle.quoteNumber),
            String(format: localized("quote.dateBadge", defaultValue: "Tarih: %@"), displayDate(bundle.issueDate))
        )
        _ = drawText(
            metaText,
            at: CGRect(x: pageSize.width - marginRight - 220, y: y + 4, width: 220, height: 36),
            font: font(8.5),
            color: secondaryTextColor,
            alignment: .right
        )

        let dividerY = y + 44
        if settings.showHeaderDivider {
            drawAccentRule(y: dividerY)
        }
        return dividerY
    }

    private func drawFooter(pageIndex: Int, totalPages: Int) {
        guard settings.showFooter else { return }

        let topY = pageSize.height - marginBottom - footerHeight
        drawHorizontalSeparator(y: topY)

        let center = resolvedFooterText
        if !center.isEmpty {
            _ = drawText(
                center,
                at: CGRect(x: marginLeft, y: topY + 10, width: contentWidth, height: 14),
                font: font(7.6),
                color: footerTextColor,
                alignment: .center
            )
        }

        _ = drawText(
            String(format: localized("pdf.page", defaultValue: "Sayfa %d / %d"), pageIndex + 1, totalPages),
            at: CGRect(x: pageSize.width - marginRight - 80, y: topY + 22, width: 80, height: 12),
            font: font(7.2),
            color: footerMutedColor,
            alignment: .right
        )
    }

    /// Middle line of the footer — fills the placeholders and joins only
    /// the non-empty ones with "•". Returns an empty string when every
    /// value is empty (no orphan "•" markers appear).
    private var resolvedFooterText: String {
        let parts: [String?] = [
            clean(bundle.companyProfile?.address),
            clean(bundle.companyProfile?.phone),
            clean(bundle.companyProfile?.email),
            clean(bundle.companyProfile?.website)
        ]
        // If the template carries placeholder markers we keep them under
        // user control; we still generate a plain fallback for empty
        // combinations.
        let template = settings.footerCenterLine
        let substituted = substituteTemplateVariables(template)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter content that consists only of separators like " • • "
        let stripped = substituted
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: " ", with: "")
        if stripped.isEmpty {
            return parts.compactMap { $0 }.joined(separator: " • ")
        }
        return substituted
    }

    // MARK: - Content blocks

    private func drawDocumentTitle(at y: CGFloat) -> CGFloat {
        _ = drawText(
            settings.documentLabel.uppercased(),
            at: CGRect(x: marginLeft, y: y, width: contentWidth, height: 14),
            font: font(10, weight: .heavy),
            color: accentColor
        )
        _ = drawText(
            bundle.titleText,
            at: CGRect(x: marginLeft, y: y + 16, width: contentWidth, height: 32),
            font: font(18, weight: .bold),
            color: primaryTextColor
        )
        return y + 56
    }

    private func drawFromTo(at y: CGFloat) -> CGFloat {
        let gap: CGFloat = 12
        let cardWidth = (contentWidth - gap) / 2
        let cardHeight = fromToCardHeight

        let fromRect = CGRect(x: marginLeft, y: y, width: cardWidth, height: cardHeight)
        let toRect = CGRect(x: marginLeft + cardWidth + gap, y: y, width: cardWidth, height: cardHeight)

        drawCard(
            in: fromRect,
            title: localized("quote.from.title", defaultValue: "Kimden"),
            rows: senderRows(),
            alignRight: false
        )

        drawCard(
            in: toRect,
            title: localized("quote.to.title", defaultValue: "Kime"),
            rows: recipientRows(),
            alignRight: false
        )

        return y + cardHeight + sectionGap
    }

    private func drawSummaryBar(at y: CGFloat) -> CGFloat {
        let height: CGFloat = 60
        let rect = CGRect(x: marginLeft, y: y, width: contentWidth, height: height)
        drawRoundedRect(rect, fill: accentColor, stroke: .clear, radius: 14)

        // Text colour adapts to the accent's luminance. With a
        // pale accent (e.g. "#F5F0E5"), white-on-accent rendered as
        // white-on-white and the summary bar lost its labels entirely.
        // Standard sRGB relative luminance threshold of 0.6 picks dark
        // text for light fills and white for dark ones.
        let textColor: NSColor = Self.relativeLuminance(of: accentColor) > 0.6
            ? NSColor.black.withAlphaComponent(0.86)
            : .white
        let separatorColor: NSColor = (textColor == .white)
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.12)

        let columns: [(String, String)] = [
            (localized("quote.summary.issueDate", defaultValue: "Düzenleme Tarihi"), displayDate(bundle.issueDate)),
            (localized("quote.summary.validity", defaultValue: "Geçerlilik"), validityText),
            (localized("quote.summary.currency", defaultValue: "Para Birimi"), currencyDisplay),
            (localized("quote.summary.lineCount", defaultValue: "Kalem Sayısı"), "\(totalLineCount)")
        ]

        let columnWidth = rect.width / CGFloat(columns.count)
        for (index, column) in columns.enumerated() {
            let columnRect = CGRect(
                x: rect.minX + CGFloat(index) * columnWidth,
                y: rect.minY,
                width: columnWidth,
                height: rect.height
            )

            if index > 0 {
                separatorColor.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 1
                path.move(to: CGPoint(x: columnRect.minX, y: columnRect.minY + 12))
                path.line(to: CGPoint(x: columnRect.minX, y: columnRect.maxY - 12))
                path.stroke()
            }

            _ = drawText(
                column.0,
                at: CGRect(x: columnRect.minX + 14, y: columnRect.minY + 10, width: columnRect.width - 28, height: 12),
                font: font(7.6),
                color: textColor.withAlphaComponent(0.78)
            )
            _ = drawText(
                column.1,
                at: CGRect(x: columnRect.minX + 14, y: columnRect.minY + 26, width: columnRect.width - 28, height: 22),
                font: font(11, weight: .bold),
                color: textColor
            )
        }

        return y + height + sectionGap
    }

    private func drawIntro(at y: CGFloat) -> CGFloat {
        var cursor = y + 18

        let greeting: String = {
            if let contact = bundle.recipientContact, !contact.isEmpty {
                return String(format: localized("quote.greeting.named", defaultValue: "Sayın %@,"), contact)
            }
            return localized("quote.greeting.fallback", defaultValue: "Sayın Yetkili,")
        }()

        _ = drawText(
            greeting,
            at: CGRect(x: marginLeft, y: cursor, width: contentWidth, height: 16),
            font: font(10, weight: .semibold),
            color: primaryTextColor
        )
        cursor += 20

        let intro = substituteTemplateVariables(settings.introParagraph)
        let introHeight = measureText(intro, width: contentWidth, font: font(9.5)).height
        _ = drawText(
            intro,
            at: CGRect(x: marginLeft, y: cursor, width: contentWidth, height: introHeight),
            font: font(9.5),
            color: bodyTextColor
        )
        cursor += introHeight + 16

        // Closing ("Best regards") — stays in its original position (left, full page width).
        let closing = clean(settings.closing) ?? localized("quote.closing.default", defaultValue: "Saygılarımızla")
        _ = drawText(
            closing,
            at: CGRect(x: marginLeft, y: cursor, width: contentWidth, height: 14),
            font: font(9, weight: .medium),
            color: bodyTextColor
        )
        cursor += 14

        if !settings.signerName.isEmpty {
            // Clear spacing between the closing and the signature block.
            cursor += 18

            // Signature block aligned right; sits just slightly in from the right edge.
            let signatureBlockWidth: CGFloat = 220
            let signatureRightInset: CGFloat = 30
            let signatureBlockX = pageSize.width - marginRight - signatureBlockWidth - signatureRightInset

            _ = drawText(
                settings.signerName,
                at: CGRect(x: signatureBlockX, y: cursor, width: signatureBlockWidth, height: 14),
                font: font(9.5, weight: .bold),
                color: primaryTextColor,
                alignment: .right
            )
            cursor += 14
            if !settings.signerTitle.isEmpty {
                _ = drawText(
                    settings.signerTitle,
                    at: CGRect(x: signatureBlockX, y: cursor, width: signatureBlockWidth, height: 14),
                    font: font(8.4),
                    color: secondaryTextColor,
                    alignment: .right
                )
                cursor += 14
            }
            // Stamp/signature allowance area between the title and the service lists.
            cursor += 32
        } else {
            cursor += 12
        }

        return cursor + sectionGap
    }

    private func drawSectionHeader(_ section: PriceListQuoteBundle.Section, at y: CGFloat) -> CGFloat {
        // Left accent vertical bar
        let barRect = CGRect(x: marginLeft, y: y + 2, width: 3, height: 18)
        accentColor.setFill()
        barRect.fill()

        _ = drawText(
            section.title,
            at: CGRect(x: marginLeft + 12, y: y, width: contentWidth - 12, height: 22),
            font: font(12, weight: .bold),
            color: primaryTextColor
        )

        var cursor = y + 24
        if let subtitle = section.subtitle, !subtitle.isEmpty {
            _ = drawText(
                subtitle,
                at: CGRect(x: marginLeft + 12, y: cursor, width: contentWidth - 12, height: 14),
                font: font(8.4),
                color: secondaryTextColor
            )
            cursor += 16
        }
        return cursor + 8
    }

    private func drawSectionTableHeader(at y: CGFloat) -> CGFloat {
        let rect = CGRect(x: marginLeft, y: y, width: contentWidth, height: 22)
        accentBackgroundColor.setFill()
        rect.fill()

        let descRect = CGRect(x: rect.minX + 12, y: rect.minY + 5, width: lineDescriptionWidth, height: 14)
        let qtyRect = CGRect(x: rect.minX + 12 + lineDescriptionWidth + 12, y: rect.minY + 5, width: lineQuantityWidth, height: 14)
        let priceRect = CGRect(x: pageSize.width - marginRight - 12 - lineUnitPriceWidth, y: rect.minY + 5, width: lineUnitPriceWidth, height: 14)

        _ = drawText(
            localized("quote.column.description", defaultValue: "Açıklama"),
            at: descRect,
            font: font(8.4, weight: .bold),
            color: accentColor
        )
        _ = drawText(
            localized("quote.column.quantity", defaultValue: "Miktar"),
            at: qtyRect,
            font: font(8.4, weight: .bold),
            color: accentColor,
            alignment: .center
        )
        _ = drawText(
            localized("quote.column.unitPrice", defaultValue: "Birim Fiyat"),
            at: priceRect,
            font: font(8.4, weight: .bold),
            color: accentColor,
            alignment: .right
        )

        return rect.maxY + 4
    }

    private func drawSectionRow(_ line: PriceListQuoteBundle.Line, at y: CGFloat) -> CGFloat {
        let height = rowHeight(for: line)
        let rect = CGRect(x: marginLeft, y: y, width: contentWidth, height: height)

        let primaryRect = CGRect(x: rect.minX + 12, y: rect.minY + 8, width: lineDescriptionWidth, height: 18)
        let primaryDrawn = drawText(
            line.primaryDescription,
            at: primaryRect,
            font: font(9.5, weight: .semibold),
            color: primaryTextColor
        )
        if let secondary = line.secondaryDescription, !secondary.isEmpty {
            _ = drawText(
                secondary,
                at: CGRect(x: primaryRect.minX, y: primaryRect.minY + primaryDrawn + 2, width: lineDescriptionWidth, height: 14),
                font: font(7.9),
                color: secondaryTextColor
            )
        }

        let qtyRect = CGRect(
            x: rect.minX + 12 + lineDescriptionWidth + 12,
            y: rect.minY + 10,
            width: lineQuantityWidth,
            height: 16
        )
        _ = drawText(
            line.quantityLabel,
            at: qtyRect,
            font: font(9),
            color: bodyTextColor,
            alignment: .center
        )

        let priceRect = CGRect(
            x: pageSize.width - marginRight - 12 - lineUnitPriceWidth,
            y: rect.minY + 8,
            width: lineUnitPriceWidth,
            height: 18
        )
        _ = drawText(
            ProWorkFormatters.money(line.unitPrice),
            at: priceRect,
            font: font(10.5, weight: .bold),
            color: accentColor,
            alignment: .right
        )

        drawHorizontalSeparator(y: rect.maxY - 2, color: NSColor(calibratedWhite: 0.90, alpha: 1))

        return rect.maxY
    }

    private func drawTermsBlock(at y: CGFloat) -> CGFloat {
        let topSpacing: CGFloat = 14
        let blockY = y + topSpacing
        let gap: CGFloat = 16
        let columnWidth = (contentWidth - gap) / 2
        let bodyTop = blockY + 26

        let cardHeight = termsCardHeight
        let leftRect = CGRect(x: marginLeft, y: blockY, width: columnWidth, height: cardHeight)
        let rightRect = CGRect(x: marginLeft + columnWidth + gap, y: blockY, width: columnWidth, height: cardHeight)

        drawRoundedRect(leftRect, fill: accentSoftBackgroundColor, stroke: .clear, radius: 12)
        drawRoundedRect(rightRect, fill: accentSoftBackgroundColor, stroke: .clear, radius: 12)

        _ = drawText(
            localized("quote.terms.commercial.title", defaultValue: "Ticari Şartlar"),
            at: CGRect(x: leftRect.minX + 14, y: leftRect.minY + 10, width: leftRect.width - 28, height: 14),
            font: font(9.5, weight: .bold),
            color: accentColor
        )
        _ = drawText(
            localized("quote.terms.service.title", defaultValue: "Hizmet Koşulları"),
            at: CGRect(x: rightRect.minX + 14, y: rightRect.minY + 10, width: rightRect.width - 28, height: 14),
            font: font(9.5, weight: .bold),
            color: accentColor
        )

        var leftCursor = bodyTop
        for item in settings.commercialTerms where !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            leftCursor = drawTermItem(
                substituteTemplateVariables(item),
                in: leftRect,
                cursor: leftCursor
            )
        }

        var rightCursor = bodyTop
        for item in settings.serviceTerms where !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rightCursor = drawTermItem(
                substituteTemplateVariables(item),
                in: rightRect,
                cursor: rightCursor
            )
        }

        return blockY + cardHeight
    }

    private func drawTermItem(_ text: String, in card: CGRect, cursor: CGFloat) -> CGFloat {
        let bulletSize: CGFloat = 5
        let bulletRect = CGRect(x: card.minX + 16, y: cursor + 5, width: bulletSize, height: bulletSize)
        accentColor.setFill()
        NSBezierPath(rect: bulletRect).fill()

        let textRect = CGRect(
            x: card.minX + 28,
            y: cursor,
            width: card.width - 44,
            height: 200
        )
        let drawn = drawText(
            text,
            at: textRect,
            font: font(8.6),
            color: bodyTextColor
        )
        return cursor + drawn + 6
    }

    private func drawSignatureBlock(at y: CGFloat) -> CGFloat {
        let gap: CGFloat = 16
        let boxWidth = (contentWidth - gap) / 2
        let boxHeight: CGFloat = 80

        let leftRect = CGRect(x: marginLeft, y: y, width: boxWidth, height: boxHeight)
        let rightRect = CGRect(x: marginLeft + boxWidth + gap, y: y, width: boxWidth, height: boxHeight)

        for (rect, title, name, jobTitle) in [
            (leftRect, localized("quote.signature.issuer", defaultValue: "Teklifi Veren"), settings.signerName, settings.signerTitle),
            (rightRect, localized("quote.signature.approver", defaultValue: "Onaylayan"), "", "")
        ] {
            drawRoundedRect(rect, fill: .clear, stroke: NSColor(calibratedWhite: 0.85, alpha: 1), radius: 10)
            _ = drawText(
                title,
                at: CGRect(x: rect.minX + 14, y: rect.minY + 10, width: rect.width - 28, height: 12),
                font: font(8, weight: .bold),
                color: secondaryTextColor
            )
            if !name.isEmpty {
                _ = drawText(
                    name,
                    at: CGRect(x: rect.minX + 14, y: rect.minY + 30, width: rect.width - 28, height: 14),
                    font: font(9.5, weight: .semibold),
                    color: primaryTextColor
                )
                _ = drawText(
                    jobTitle,
                    at: CGRect(x: rect.minX + 14, y: rect.minY + 44, width: rect.width - 28, height: 14),
                    font: font(8.2),
                    color: secondaryTextColor
                )
            }
            // Signature line
            NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
            let line = NSBezierPath()
            line.lineWidth = 0.6
            line.move(to: CGPoint(x: rect.minX + 14, y: rect.maxY - 14))
            line.line(to: CGPoint(x: rect.maxX - 14, y: rect.maxY - 14))
            line.stroke()
            _ = drawText(
                localized("quote.signature.date", defaultValue: "Tarih / İmza"),
                at: CGRect(x: rect.minX + 14, y: rect.maxY - 12, width: rect.width - 28, height: 10),
                font: font(7),
                color: footerMutedColor
            )
        }

        return y + boxHeight + sectionGap
    }

    // MARK: - Helpers

    private func drawCard(
        in rect: CGRect,
        title: String,
        rows: [(String, String)],
        alignRight: Bool
    ) {
        drawRoundedRect(
            rect,
            fill: NSColor(calibratedWhite: 0.985, alpha: 1),
            stroke: NSColor(calibratedWhite: 0.90, alpha: 1),
            radius: 10
        )

        _ = drawText(
            title,
            at: CGRect(x: rect.minX + 14, y: rect.minY + 10, width: rect.width - 28, height: 12),
            font: font(8, weight: .bold),
            color: accentColor
        )

        let nameValueWidth = rect.width - 28
        let nameHeight: CGFloat
        if let nameRow = rows.first {
            nameHeight = max(
                16,
                measureText(nameRow.1, width: nameValueWidth, font: font(10.5, weight: .bold)).height
            )
            _ = drawText(
                nameRow.1,
                at: CGRect(x: rect.minX + 14, y: rect.minY + 26, width: nameValueWidth, height: nameHeight),
                font: font(10.5, weight: .bold),
                color: primaryTextColor
            )
        } else {
            nameHeight = 0
        }

        var cursor = rect.minY + 26 + nameHeight + 6
        for row in rows.dropFirst() {
            let label = row.0
            let value = row.1
            let rowHeight = cardBodyRowHeight(row: row, cardWidth: rect.width)
            if !label.isEmpty {
                _ = drawText(
                    label,
                    at: CGRect(x: rect.minX + 14, y: cursor, width: rect.width * 0.34, height: rowHeight),
                    font: font(7.8),
                    color: secondaryTextColor
                )
                _ = drawText(
                    value,
                    at: CGRect(x: rect.minX + 14 + rect.width * 0.36, y: cursor, width: rect.width * 0.6 - 28, height: rowHeight),
                    font: font(8.4, weight: .medium),
                    color: bodyTextColor,
                    alignment: alignRight ? .right : .left
                )
            } else {
                _ = drawText(
                    value,
                    at: CGRect(x: rect.minX + 14, y: cursor, width: rect.width - 28, height: rowHeight),
                    font: font(8.4),
                    color: bodyTextColor
                )
            }
            cursor += rowHeight
        }
    }

    private func senderRows() -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("", companyDisplayName))
        if let address = clean(bundle.companyProfile?.address) {
            rows.append(("", address))
        }
        if let phone = clean(bundle.companyProfile?.phone) {
            rows.append((localized("quote.from.phone", defaultValue: "Tel"), phone))
        }
        if let email = clean(bundle.companyProfile?.email) {
            rows.append((localized("quote.from.email", defaultValue: "E-posta"), email))
        }
        if let website = clean(bundle.companyProfile?.website) {
            rows.append((localized("quote.from.website", defaultValue: "Web"), website))
        }
        if let tax = clean(bundle.companyProfile?.taxNumber) {
            let office = clean(bundle.companyProfile?.taxOffice).map { "\($0) " } ?? ""
            rows.append((localized("quote.from.tax", defaultValue: "Vergi"), "\(office)\(tax)"))
        }
        return rows
    }

    private func recipientRows() -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("", bundle.recipientName))
        if let address = bundle.recipientAddress {
            rows.append(("", address))
        }
        if let contact = bundle.recipientContact {
            rows.append((localized("quote.to.contact", defaultValue: "İlgili"), contact))
        }
        return rows
    }

    // MARK: - Layout constants

    private var contentWidth: CGFloat {
        pageSize.width - marginLeft - marginRight
    }

    private var lineUnitPriceWidth: CGFloat { 110 }
    private var lineQuantityWidth: CGFloat { 70 }
    private var lineDescriptionWidth: CGFloat {
        contentWidth - lineQuantityWidth - lineUnitPriceWidth - 36
    }

    // MARK: - Formatters

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    private var validityText: String {
        displayDate(bundle.validUntil)
    }

    private var currencyDisplay: String {
        bundle.currency
    }

    private var totalLineCount: Int {
        bundle.sections.reduce(0) { $0 + $1.lines.count }
    }

    private var companyDisplayName: String {
        clean(bundle.companyProfile?.tradeName) ??
        clean(bundle.companyProfile?.legalName) ??
        "ProWork"
    }

    private var coverCompanyMetaText: String? {
        var parts: [String] = []
        if let address = clean(bundle.companyProfile?.address) {
            parts.append(address)
        }
        if let phone = clean(bundle.companyProfile?.phone) {
            parts.append(phone)
        }
        if let website = clean(bundle.companyProfile?.website) {
            parts.append(website)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Previously called `replacingOccurrences` 8 times in a
    /// row, building intermediate strings for each pass. A single regex
    /// pass with a closure replacement substitutes every placeholder in
    /// one traversal. Variables not in the table are left untouched
    /// (matches the previous behaviour for unknown `{…}` tokens).
    private func substituteTemplateVariables(_ template: String) -> String {
        let phone = clean(bundle.companyProfile?.phone) ?? ""
        let email = clean(bundle.companyProfile?.email) ?? ""
        let address = clean(bundle.companyProfile?.address) ?? ""
        let website = clean(bundle.companyProfile?.website) ?? ""

        let substitutions: [String: String] = [
            "validityDays": "\(settings.normalizedValidityDays)",
            "validUntil": displayDate(bundle.validUntil),
            "quoteNumber": bundle.quoteNumber,
            "customerName": bundle.recipientName,
            "phone": phone,
            "email": email,
            "address": address,
            "website": website
        ]

        guard let regex = try? NSRegularExpression(pattern: #"\{([A-Za-z0-9_]+)\}"#) else {
            return template
        }
        let nsTemplate = template as NSString
        let fullRange = NSRange(location: 0, length: nsTemplate.length)
        let matches = regex.matches(in: template, options: [], range: fullRange)
        guard !matches.isEmpty else { return template }

        var result = String()
        result.reserveCapacity(template.count)
        var cursor = 0
        for match in matches {
            let matchRange = match.range
            // Append everything before this placeholder.
            if matchRange.location > cursor {
                result.append(nsTemplate.substring(with: NSRange(
                    location: cursor,
                    length: matchRange.location - cursor
                )))
            }
            let nameRange = match.range(at: 1)
            let name = nsTemplate.substring(with: nameRange)
            if let replacement = substitutions[name] {
                result.append(replacement)
            } else {
                result.append(nsTemplate.substring(with: matchRange))
            }
            cursor = matchRange.location + matchRange.length
        }
        if cursor < nsTemplate.length {
            result.append(nsTemplate.substring(from: cursor))
        }
        return result
    }

    /// Cached via `ProWorkFormatters.cachedDateFormatter` so a
    /// multi-page quote shares one formatter instance instead of
    /// allocating a fresh one on every header + signature + cover draw
    /// (4-5 per render call).
    private func displayDate(_ date: Date) -> String {
        let identifier = ProWorkLocalizer.shared.language.localeIdentifier.isEmpty
            ? Locale.current.identifier
            : ProWorkLocalizer.shared.language.localeIdentifier
        let formatter = ProWorkFormatters.cachedDateFormatter(
            localeIdentifier: identifier,
            dateFormat: "dd.MM.yyyy"
        )
        return formatter.string(from: date)
    }

    private func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Colors

    private var accentColor: NSColor {
        nsColor(from: settings.normalizedAccentHexColor) ?? NSColor.systemBlue
    }

    private var accentBackgroundColor: NSColor {
        accentColor.blended(withFraction: 0.88, of: .white) ?? NSColor(calibratedRed: 0.92, green: 0.96, blue: 0.99, alpha: 1)
    }

    private var accentSoftBackgroundColor: NSColor {
        accentColor.blended(withFraction: 0.94, of: .white) ?? NSColor(calibratedWhite: 0.97, alpha: 1)
    }

    private var primaryTextColor: NSColor { NSColor(calibratedWhite: 0.12, alpha: 1) }
    private var bodyTextColor: NSColor { NSColor(calibratedWhite: 0.22, alpha: 1) }
    private var secondaryTextColor: NSColor { NSColor(calibratedWhite: 0.42, alpha: 1) }
    private var footerTextColor: NSColor { NSColor(calibratedWhite: 0.42, alpha: 1) }
    private var footerMutedColor: NSColor { NSColor(calibratedWhite: 0.62, alpha: 1) }

    private func nsColor(from hex: String) -> NSColor? {
        // Shared with BillingPdfDocument.
        PDFDrawingPrimitives.nsColor(fromHex: hex)
    }

    private func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size * settings.normalizedFontScale, weight: weight)
    }

    /// SRGB relative luminance per WCAG 2.x. Used by `drawSummaryBar` to
    /// pick a readable text colour against the configurable accent
    /// .
    fileprivate static func relativeLuminance(of color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = component(rgb.redComponent)
        let g = component(rgb.greenComponent)
        let b = component(rgb.blueComponent)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func component(_ raw: CGFloat) -> CGFloat {
        raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
    }

    // MARK: - Drawing primitives

    // Drawing primitives delegated to PDFDrawingPrimitives
    // so a fix or tuning lives in one file.

    @discardableResult
    private func drawText(
        _ text: String,
        at rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        PDFDrawingPrimitives.drawText(text, at: rect, font: font, color: color, alignment: alignment)
    }

    /// Pagination + drawing measure the same (text, width, font)
    /// triple multiple times per page; memoize on the document instance
    /// to halve the CoreText boundingRect cost on long quotes. Cache key
    /// follows the BillingPdfDocument MeasureCacheKey layout.
    private struct MeasureCacheKey: Hashable {
        let text: String
        let width: CGFloat
        let fontName: String
        let fontSize: CGFloat
    }
    private var measureCache: [MeasureCacheKey: CGSize] = [:]

    private func measureText(_ text: String, width: CGFloat, font: NSFont) -> CGSize {
        let key = MeasureCacheKey(
            text: text,
            width: width,
            fontName: font.fontName,
            fontSize: font.pointSize
        )
        if let cached = measureCache[key] {
            return cached
        }
        let size = PDFDrawingPrimitives.measureText(text, width: width, font: font)
        measureCache[key] = size
        return size
    }

    private func drawRoundedRect(_ rect: CGRect, fill: NSColor, stroke: NSColor, radius: CGFloat) {
        PDFDrawingPrimitives.drawRoundedRect(rect, fill: fill, stroke: stroke, radius: radius)
    }

    private func drawHorizontalSeparator(y: CGFloat, color: NSColor = NSColor(calibratedWhite: 0.88, alpha: 1)) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: marginLeft, y: y))
        path.line(to: CGPoint(x: pageSize.width - marginRight, y: y))
        path.stroke()
    }

    private func drawAccentRule(y: CGFloat) {
        accentColor.setFill()
        CGRect(x: marginLeft, y: y, width: contentWidth, height: 2).fill()
    }

    private func fitRect(sourceSize: CGSize, inside target: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return target }
        let scale = min(target.width / sourceSize.width, target.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: target.minX,
            y: target.minY + (target.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Page model

private enum ContentBlock {
    case documentTitle
    case fromTo
    case summaryBar
    case intro
    case sectionHeader(PriceListQuoteBundle.Section)
    case sectionTableHeader
    case sectionRow(PriceListQuoteBundle.Line)
    case terms
    case signature
}

private struct RenderPage {
    var isCover: Bool
    var blocks: [ContentBlock]

    static let cover = RenderPage(isCover: true, blocks: [])

    static func content(blocks: [ContentBlock]) -> RenderPage {
        RenderPage(isCover: false, blocks: blocks)
    }
}
