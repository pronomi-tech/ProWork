//
//  BillingPdfRenderer.swift
//  ProWork
//
//  Created by Pronomi.
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
private struct BillingPdfDocument {
    let bundle: BillingRunBundle
    let settings: ServiceDocumentTemplateSettings

    private let pageSize = CGSize(width: 595, height: 842)
    private let marginLeft: CGFloat = 42
    private let marginRight: CGFloat = 42
    private let marginTop: CGFloat = 20
    private let marginBottom: CGFloat = 22
    private let footerHeight: CGFloat = 44
    private let lineGap: CGFloat = 10
    private let sectionGap: CGFloat = 18
    private let tableSectionGap: CGFloat = 12
    private let currencyTableTitleHeight: CGFloat = 22

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    private var selectedLocale: Locale {
        Locale(identifier: ProWorkLocalizer.shared.language.localeIdentifier)
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

    private func paginate() -> [RenderPage] {
        var pages: [RenderPage] = [.init()]
        var remainingHeights: [CGFloat] = [firstPageAvailableHeight]
        var currentPageIndex = 0

        allocateLines(
            pages: &pages,
            remainingHeights: &remainingHeights,
            currentPageIndex: &currentPageIndex
        )

        allocatePayments(
            pages: &pages,
            remainingHeights: &remainingHeights,
            currentPageIndex: &currentPageIndex
        )

        return pages
    }

    private func allocateLines(
        pages: inout [RenderPage],
        remainingHeights: inout [CGFloat],
        currentPageIndex: inout Int
    ) {
        let sectionHeader = linesSectionHeaderHeight

        if bundle.lines.isEmpty {
            let needed = sectionHeader + emptyLinesHeight + lineTotalsHeight
            ensureSpace(
                for: needed,
                pages: &pages,
                remainingHeights: &remainingHeights,
                currentPageIndex: &currentPageIndex
            )
            pages[currentPageIndex].showsEmptyLines = true
            pages[currentPageIndex].showsLineTotals = true
            remainingHeights[currentPageIndex] -= needed
            return
        }

        ensureSpace(
            for: sectionHeader,
            pages: &pages,
            remainingHeights: &remainingHeights,
            currentPageIndex: &currentPageIndex
        )
        pages[currentPageIndex].showsLineSection = true
        remainingHeights[currentPageIndex] -= sectionHeader

        for section in groupedLineSections {
            var remainingIndices = ArraySlice(section.indices)
            var isContinuation = false

            while !remainingIndices.isEmpty {
                let blockHeaderHeight = lineTableBlockHeaderHeight(
                    hasExistingTableOnPage: !pages[currentPageIndex].lineTables.isEmpty
                )

                if blockHeaderHeight > remainingHeights[currentPageIndex] {
                    appendLinePage(
                        pages: &pages,
                        remainingHeights: &remainingHeights,
                        currentPageIndex: &currentPageIndex
                    )
                }

                pages[currentPageIndex].lineTables.append(
                    CurrencyTableChunk(currency: section.currency, isContinuation: isContinuation)
                )
                remainingHeights[currentPageIndex] -= blockHeaderHeight

                while let lineIndex = remainingIndices.first {
                    let rowHeight = estimatedLineHeight(for: bundle.lines[lineIndex])
                    let chunkIndex = pages[currentPageIndex].lineTables.count - 1

                    if rowHeight > remainingHeights[currentPageIndex],
                       !pages[currentPageIndex].lineTables[chunkIndex].indices.isEmpty {
                        appendLinePage(
                            pages: &pages,
                            remainingHeights: &remainingHeights,
                            currentPageIndex: &currentPageIndex
                        )
                        isContinuation = true
                        break
                    }

                    pages[currentPageIndex].lineTables[chunkIndex].indices.append(lineIndex)
                    remainingHeights[currentPageIndex] -= rowHeight
                    remainingIndices.removeFirst()
                }

                if !remainingIndices.isEmpty {
                    isContinuation = true
                }
            }
        }

        if lineTotalsHeight > remainingHeights[currentPageIndex] {
            appendLinePage(
                pages: &pages,
                remainingHeights: &remainingHeights,
                currentPageIndex: &currentPageIndex
            )
        }
        pages[currentPageIndex].showsLineTotals = true
        remainingHeights[currentPageIndex] -= lineTotalsHeight
    }

    private func allocatePayments(
        pages: inout [RenderPage],
        remainingHeights: inout [CGFloat],
        currentPageIndex: inout Int
    ) {
        let hasLineContent = pages[currentPageIndex].showsLineSection || pages[currentPageIndex].showsEmptyLines
        let spacingBeforePayments = hasLineContent ? sectionGap : 0

        if bundle.payments.isEmpty {
            let required = spacingBeforePayments + paymentsHeaderHeight + emptyPaymentsHeight + paymentTotalsHeight
            ensureSpace(
                for: required,
                pages: &pages,
                remainingHeights: &remainingHeights,
                currentPageIndex: &currentPageIndex
            )
            pages[currentPageIndex].showsPaymentsSection = true
            pages[currentPageIndex].showsEmptyPayments = true
            pages[currentPageIndex].showsPaymentTotals = shouldShowPaymentTotals
            remainingHeights[currentPageIndex] -= required
            return
        }

        let headerNeed = spacingBeforePayments + paymentsHeaderHeight
        ensureSpace(
            for: headerNeed,
            pages: &pages,
            remainingHeights: &remainingHeights,
            currentPageIndex: &currentPageIndex
        )
        pages[currentPageIndex].showsPaymentsSection = true
        remainingHeights[currentPageIndex] -= headerNeed

        for section in groupedPaymentSections {
            var remainingIndices = ArraySlice(section.indices)
            var isContinuation = false

            while !remainingIndices.isEmpty {
                let blockHeaderHeight = paymentTableBlockHeaderHeight(
                    hasExistingTableOnPage: !pages[currentPageIndex].paymentTables.isEmpty
                )

                if blockHeaderHeight > remainingHeights[currentPageIndex] {
                    appendPaymentPage(
                        pages: &pages,
                        remainingHeights: &remainingHeights,
                        currentPageIndex: &currentPageIndex
                    )
                }

                pages[currentPageIndex].paymentTables.append(
                    CurrencyTableChunk(currency: section.currency, isContinuation: isContinuation)
                )
                remainingHeights[currentPageIndex] -= blockHeaderHeight

                while let paymentIndex = remainingIndices.first {
                    let rowHeight = estimatedPaymentHeight(for: bundle.payments[paymentIndex])
                    let chunkIndex = pages[currentPageIndex].paymentTables.count - 1

                    if rowHeight > remainingHeights[currentPageIndex],
                       !pages[currentPageIndex].paymentTables[chunkIndex].indices.isEmpty {
                        appendPaymentPage(
                            pages: &pages,
                            remainingHeights: &remainingHeights,
                            currentPageIndex: &currentPageIndex
                        )
                        isContinuation = true
                        break
                    }

                    pages[currentPageIndex].paymentTables[chunkIndex].indices.append(paymentIndex)
                    remainingHeights[currentPageIndex] -= rowHeight
                    remainingIndices.removeFirst()
                }

                if !remainingIndices.isEmpty {
                    isContinuation = true
                }
            }
        }

        if shouldShowPaymentTotals {
            if paymentTotalsHeight > remainingHeights[currentPageIndex] {
                appendPaymentPage(
                    pages: &pages,
                    remainingHeights: &remainingHeights,
                    currentPageIndex: &currentPageIndex
                )
            }
            pages[currentPageIndex].showsPaymentTotals = true
            remainingHeights[currentPageIndex] -= paymentTotalsHeight
        }
    }

    private func appendLinePage(
        pages: inout [RenderPage],
        remainingHeights: inout [CGFloat],
        currentPageIndex: inout Int
    ) {
        pages.append(.init(
            showsLineSection: true,
            linePageIndex: pages[currentPageIndex].linePageIndex + 1
        ))
        remainingHeights.append(continuationPageAvailableHeight - linesSectionHeaderHeight)
        currentPageIndex = pages.count - 1
    }

    private func appendPaymentPage(
        pages: inout [RenderPage],
        remainingHeights: inout [CGFloat],
        currentPageIndex: inout Int
    ) {
        pages.append(.init(
            showsPaymentsSection: true,
            paymentPageIndex: pages[currentPageIndex].paymentPageIndex + 1
        ))
        remainingHeights.append(continuationPageAvailableHeight - paymentsHeaderHeight)
        currentPageIndex = pages.count - 1
    }

    private func ensureSpace(
        for needed: CGFloat,
        pages: inout [RenderPage],
        remainingHeights: inout [CGFloat],
        currentPageIndex: inout Int
    ) {
        if needed > remainingHeights[currentPageIndex] {
            pages.append(.init())
            remainingHeights.append(continuationPageAvailableHeight)
            currentPageIndex = pages.count - 1
        }
    }

    private var contentWidth: CGFloat {
        pageSize.width - marginLeft - marginRight
    }

    private var firstPageAvailableHeight: CGFloat {
        pageSize.height - marginTop - marginBottom - footerHeight - firstPageReservedHeight
    }

    private var continuationPageAvailableHeight: CGFloat {
        pageSize.height - marginTop - marginBottom - footerHeight - repeatedPageReservedHeight
    }

    private var firstPageReservedHeight: CGFloat {
        let header: CGFloat = settings.showHeaderDivider ? 56 : 44
        let title: CGFloat = 52
        let cards: CGFloat = 112
        let summary: CGFloat = settings.showFinancialSummary ? summarySectionHeight : 0
        return header + title + cards + summary + sectionGap
    }

    private var repeatedPageReservedHeight: CGFloat {
        let header: CGFloat = settings.showHeaderDivider ? 56 : 44
        return header + 8
    }

    private var linesSectionHeaderHeight: CGFloat { 36 }
    private var paymentsHeaderHeight: CGFloat { 34 }
    private var paymentTableHeaderHeight: CGFloat { 30 }
    private var emptyLinesHeight: CGFloat { 26 }
    private var emptyPaymentsHeight: CGFloat { 26 }
    private var lineTotalsHeight: CGFloat { 10 + lineTotalsPanelHeight }
    private var paymentTotalsHeight: CGFloat {
        shouldShowPaymentTotals ? 10 + paymentTotalsPanelHeight : 0
    }
    private func lineTableBlockHeaderHeight(hasExistingTableOnPage: Bool) -> CGFloat {
        (hasExistingTableOnPage ? tableSectionGap : 0)
        + (shouldShowLineCurrencyTitles ? currencyTableTitleHeight : 0)
        + paymentTableHeaderHeight
    }

    private func paymentTableBlockHeaderHeight(hasExistingTableOnPage: Bool) -> CGFloat {
        (hasExistingTableOnPage ? tableSectionGap : 0)
        + (shouldShowPaymentCurrencyTitles ? currencyTableTitleHeight : 0)
        + paymentTableHeaderHeight
    }

    private func draw(page: RenderPage, pageIndex: Int, totalPages: Int) {
        var cursorY = drawHeader(at: marginTop)

        if pageIndex == 0 {
            cursorY = drawTitle(at: cursorY)
            cursorY = drawInfoCards(at: cursorY)

            if settings.showFinancialSummary {
                cursorY = drawSummary(at: cursorY)
            }
        } else {
            cursorY += 8
        }

        if page.showsLineSection || page.showsEmptyLines {
            cursorY = drawLinesSection(page: page, startY: cursorY)
        }

        if page.showsPaymentsSection || page.showsEmptyPayments {
            if page.showsLineSection || page.showsEmptyLines {
                cursorY += sectionGap
            }
            _ = drawPaymentsSection(page: page, startY: cursorY)
        }

        drawFooter(pageIndex: pageIndex, totalPages: totalPages)
    }

    private func drawHeader(at y: CGFloat) -> CGFloat {
        let logoFrame = CGRect(x: marginLeft, y: y, width: 220, height: 52)
        let showsLogo = settings.showLogo &&
            bundle.companyProfile?.logoData != nil

        if settings.showLogo,
           let data = bundle.companyProfile?.logoData,
           let image = NSImage(data: data) {
            image.draw(in: fitRect(sourceSize: image.size, inside: logoFrame))
        } else {
            _ = drawText(
                companyDisplayName,
                at: CGRect(x: marginLeft, y: y + 3, width: contentWidth * 0.6, height: 28),
                font: font(18, weight: .bold),
                color: accentColor
            )
        }

        let dividerY = y + (showsLogo ? 58 : 44)
        if settings.showHeaderDivider {
            drawHorizontalSeparator(y: dividerY)
            return dividerY + 8
        }

        return dividerY + 2
    }

    private func drawTitle(at y: CGFloat) -> CGFloat {
        let titleWidth = contentWidth * 0.72
        _ = drawText(
            settings.title,
            at: CGRect(x: marginLeft, y: y, width: titleWidth, height: 28),
            font: font(17.5, weight: .bold),
            color: primaryTextColor
        )

        let badgeText = bundle.run.status.title
        let badgeSize = measureText(badgeText, width: 120, font: font(8.5, weight: .bold))
        let badgeWidth = max(86, badgeSize.width + 24)
        let badgeRect = CGRect(x: pageSize.width - marginRight - badgeWidth, y: y + 1, width: badgeWidth, height: 24)
        drawRoundedRect(
            badgeRect,
            fill: NSColor(calibratedRed: 0.92, green: 0.96, blue: 0.99, alpha: 1),
            stroke: .clear,
            radius: 12
        )
        _ = drawText(
            badgeText,
            at: badgeRect.insetBy(dx: 10, dy: 5),
            font: font(8.5, weight: .bold),
            color: accentColor,
            alignment: .center
        )

        _ = drawText(
            periodLabel,
            at: CGRect(x: marginLeft, y: y + 26, width: titleWidth, height: 14),
            font: font(8.6),
            color: secondaryTextColor
        )

        return y + 44
    }

    private func drawInfoCards(at y: CGFloat) -> CGFloat {
        let gap: CGFloat = 12
        let leftWidth = (contentWidth - gap) * 0.52
        let rightWidth = contentWidth - gap - leftWidth
        let cardHeight: CGFloat = 96
        let dueDate = displayOptionalDay(bundle.run.dueDate)
        let documentRows = [
            (localized("pdf.document.number", defaultValue: "Belge No"), documentNumber),
            (localized("pdf.document.issueDate", defaultValue: "Düzenleme Tarihi"), displayDate(bundle.run.finalizedAt ?? bundle.run.updatedAt)),
            (localized("pdf.document.referenceNumber", defaultValue: "Referans No"), bundle.run.invoiceNumber ?? "—")
        ] + (dueDate.map { [(localized("pdf.document.dueDate", defaultValue: "Vade"), $0)] } ?? [])

        let customerRect = CGRect(x: marginLeft, y: y, width: leftWidth, height: cardHeight)
        let documentRect = CGRect(x: customerRect.maxX + gap, y: y, width: rightWidth, height: cardHeight)

        drawCard(
            in: customerRect,
            title: localized("pdf.section.customerInfo", defaultValue: "Müşteri Bilgileri"),
            rows: [
                (localized("projects.form.customer", defaultValue: "Müşteri"), bundle.customer?.name ?? bundle.run.customerId),
                (localized("pdf.customer.code", defaultValue: "Kod"), bundle.customer?.code ?? "—"),
                (localized("export.column.currency", defaultValue: "Para Birimi"), documentCurrenciesText)
            ],
            alignRight: false
        )

        drawCard(
            in: documentRect,
            title: localized("pdf.section.documentInfo", defaultValue: "Belge Bilgileri"),
            rows: documentRows,
            alignRight: true
        )

        return y + cardHeight + sectionGap
    }

    private func drawSummary(at y: CGFloat) -> CGFloat {
        let gap: CGFloat = 8
        let items = summaryItems
        let itemWidth = (contentWidth - (gap * CGFloat(max(items.count - 1, 0)))) / CGFloat(max(items.count, 1))
        let itemHeight = summaryCardHeight

        _ = drawText(
            localized("pdf.section.financialSummary", defaultValue: "Finansal Özet"),
            at: CGRect(x: marginLeft, y: y, width: 180, height: 16),
            font: font(10, weight: .bold),
            color: primaryTextColor
        )

        let rowY = y + 20
        for (index, item) in items.enumerated() {
            let rect = CGRect(
                x: marginLeft + CGFloat(index) * (itemWidth + gap),
                y: rowY,
                width: itemWidth,
                height: itemHeight
            )
            drawRoundedRect(
                rect,
                fill: item.2 ? NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.99, alpha: 1) : .white,
                stroke: item.2 ? accentColor : NSColor(calibratedWhite: 0.90, alpha: 1),
                radius: 12
            )
            _ = drawText(
                item.0,
                at: CGRect(x: rect.minX + 10, y: rect.minY + 10, width: rect.width - 20, height: 12),
                font: font(7.8),
                color: secondaryTextColor
            )
            _ = drawText(
                item.1,
                at: CGRect(x: rect.minX + 10, y: rect.minY + 29, width: rect.width - 20, height: 20),
                font: font(item.2 ? 10.4 : 9.6, weight: .bold),
                color: item.2 ? accentColor : primaryTextColor
            )
        }

        return rowY + itemHeight + sectionGap
    }

    private func drawLinesSection(page: RenderPage, startY: CGFloat) -> CGFloat {
        var y = startY
        _ = drawText(
            page.linePageIndex > 0
                ? localized("pdf.section.serviceLines.continued", defaultValue: "Hizmet Satırları (Devam)")
                : localized("pdf.section.serviceLines", defaultValue: "Hizmet Satırları"),
            at: CGRect(x: marginLeft, y: y, width: 220, height: 16),
            font: font(10, weight: .bold),
            color: primaryTextColor
        )
        y += 20

        if page.showsEmptyLines {
            _ = drawText(
                localized("pdf.empty.serviceLines", defaultValue: "Bu belge için hizmet satırı bulunmamaktadır."),
                at: CGRect(x: marginLeft, y: y, width: contentWidth, height: 16),
                font: font(8.8),
                color: secondaryTextColor
            )
            y += emptyLinesHeight
        } else {
            let columns = lineColumns()

            for (tableIndex, table) in page.lineTables.enumerated() {
                if tableIndex > 0 {
                    y += tableSectionGap
                }

                if shouldShowLineCurrencyTitles {
                    y = drawCurrencyTableTitle(
                        currency: table.currency,
                        isContinuation: table.isContinuation,
                        at: y
                    )
                }
                drawTableHeader(columns: columns, y: y)
                y += paymentTableHeaderHeight

                for (offset, lineIndex) in table.indices.enumerated() {
                    let rowHeight = estimatedLineHeight(for: bundle.lines[lineIndex])
                    let rowRect = CGRect(x: marginLeft, y: y, width: contentWidth, height: rowHeight)

                    if offset % 2 == 1 {
                        NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
                        rowRect.fill()
                    }

                    drawLineRow(
                        bundle.lines[lineIndex],
                        lineNumber: lineOrdinalByIndex[lineIndex] ?? (offset + 1),
                        in: rowRect,
                        columns: columns
                    )
                    drawHorizontalSeparator(y: rowRect.maxY)
                    y += rowHeight
                }
            }
        }

        if page.showsLineTotals {
            y += 10
            y = drawLineTotals(at: y)
        }

        return y
    }

    private func drawPaymentsSection(page: RenderPage, startY: CGFloat) -> CGFloat {
        var y = startY
        _ = drawText(
            page.paymentPageIndex > 0
                ? localized("pdf.section.payments.continued", defaultValue: "Ödeme Bilgileri (Devam)")
                : localized("pdf.section.payments", defaultValue: "Ödeme Bilgileri"),
            at: CGRect(x: marginLeft, y: y, width: 200, height: 16),
            font: font(10, weight: .bold),
            color: primaryTextColor
        )
        y += 20

        if page.showsEmptyPayments {
            _ = drawText(
                localized("pdf.empty.payments", defaultValue: "Bu belgeye ait tahsilat kaydı bulunmamaktadır."),
                at: CGRect(x: marginLeft, y: y, width: contentWidth, height: 16),
                font: font(8.8),
                color: secondaryTextColor
            )
            y += emptyPaymentsHeight
        } else {
            let columns = paymentColumns()

            for (tableIndex, table) in page.paymentTables.enumerated() {
                if tableIndex > 0 {
                    y += tableSectionGap
                }

                if shouldShowPaymentCurrencyTitles {
                    y = drawCurrencyTableTitle(
                        currency: table.currency,
                        isContinuation: table.isContinuation,
                        at: y
                    )
                }
                drawTableHeader(columns: columns, y: y)
                y += paymentTableHeaderHeight

                for (offset, paymentIndex) in table.indices.enumerated() {
                    let rowHeight = estimatedPaymentHeight(for: bundle.payments[paymentIndex])
                    let rowRect = CGRect(x: marginLeft, y: y, width: contentWidth, height: rowHeight)

                    if offset % 2 == 1 {
                        NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
                        rowRect.fill()
                    }

                    drawPaymentRow(
                        bundle.payments[paymentIndex],
                        number: paymentOrdinalByIndex[paymentIndex] ?? (offset + 1),
                        in: rowRect,
                        columns: columns
                    )
                    drawHorizontalSeparator(y: rowRect.maxY)
                    y += rowHeight
                }
            }
        }

        if page.showsPaymentTotals {
            y += 10
            y = drawPaymentTotals(at: y)
        }

        return y
    }

    private func drawFooter(pageIndex: Int, totalPages: Int) {
        let topY = pageSize.height - marginBottom - footerHeight
        drawHorizontalSeparator(y: topY)

        let address = clean(bundle.companyProfile?.address) ?? "—"
        let contacts = [
            clean(bundle.companyProfile?.website),
            clean(bundle.companyProfile?.email),
            clean(bundle.companyProfile?.phone)
        ]
        .compactMap { $0 }
        .joined(separator: " • ")

        _ = drawText(
            address,
            at: CGRect(x: marginLeft, y: topY + 8, width: contentWidth - 90, height: 12),
            font: font(7.3),
            color: footerTextColor
        )
        _ = drawText(
            contacts.isEmpty ? "—" : contacts,
            at: CGRect(x: marginLeft, y: topY + 21, width: contentWidth - 90, height: 12),
            font: font(7.3),
            color: footerMutedTextColor
        )
        _ = drawText(
            String(format: localized("pdf.page", defaultValue: "Sayfa %d / %d"), pageIndex + 1, totalPages),
            at: CGRect(x: pageSize.width - marginRight - 80, y: topY + 21, width: 80, height: 12),
            font: font(7.2),
            color: footerMutedTextColor,
            alignment: .right
        )
    }

    private func drawLineRow(
        _ line: BillingReportLine,
        lineNumber: Int,
        in rect: CGRect,
        columns: [TableColumn]
    ) {
        let frames = columnFrames(for: columns, in: rect)
        let noFrame = frames.first(where: { $0.id == "no" })?.rect ?? rect
        let descriptionFrame = frames.first(where: { $0.id == "description" })?.rect ?? rect

        _ = drawText(
            "\(lineNumber)",
            at: CGRect(x: noFrame.minX, y: rect.minY + 10, width: noFrame.width, height: 16),
            font: font(8.8),
            color: secondaryTextColor
        )

        var descY = rect.minY + 10
        let titleHeight = drawText(
            line.todoTitle,
            at: CGRect(x: descriptionFrame.minX, y: descY, width: descriptionFrame.width, height: 36),
            font: font(9.2, weight: .bold),
            color: primaryTextColor
        )
        descY += titleHeight + 4

        let timing = String(
            format: localized("pdf.line.timing", defaultValue: "Başlangıç: %@ | Bitiş: %@"),
            displayDateTimeWithSeconds(line.startedAt),
            displayDateTimeWithSeconds(line.endedAt)
        )
        let timingHeight = drawText(
            timing,
            at: CGRect(x: descriptionFrame.minX, y: descY, width: descriptionFrame.width, height: 26),
            font: font(8.1),
            color: secondaryTextColor
        )
        descY += timingHeight + 2

        let serviceMeta = lineMetaText(for: line)
        let metaHeight = drawText(
            serviceMeta,
            at: CGRect(x: descriptionFrame.minX, y: descY, width: descriptionFrame.width, height: 28),
            font: font(8.1),
            color: secondaryTextColor
        )
        descY += metaHeight

        if settings.showLineNotes, let note = clean(line.note) {
            let noteText = String(format: localized("pdf.line.note", defaultValue: "Not: %@"), note)
            let noteContentHeight = measureText(noteText, width: descriptionFrame.width - 20, font: font(8.4)).height
            let noteRect = CGRect(
                x: descriptionFrame.minX,
                y: descY + 8,
                width: descriptionFrame.width,
                height: noteContentHeight + 16
            )
            drawRoundedRect(
                noteRect,
                fill: NSColor(calibratedWhite: 0.95, alpha: 1),
                stroke: .clear,
                radius: 8
            )
            _ = drawText(
                noteText,
                at: noteRect.insetBy(dx: 10, dy: 8),
                font: font(8.4),
                color: mutedPrimaryTextColor
            )
        }

        drawColumnText(
            line.isFixedFee ? "-" : String(format: localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), line.billableMinutes),
            id: "duration",
            frames: frames,
            rect: rect,
            alignment: .right
        )
        drawColumnText(line.isFixedFee ? "-" : displayMoney(line.unitPrice), id: "unitPrice", frames: frames, rect: rect, alignment: .right)
        drawColumnText(displayMoney(line.amount), id: "amount", frames: frames, rect: rect, alignment: .right, bold: true)
    }

    private func drawPaymentRow(
        _ payment: Payment,
        number: Int,
        in rect: CGRect,
        columns: [TableColumn]
    ) {
        let frames = columnFrames(for: columns, in: rect)
        drawColumnText("\(number)", id: "no", frames: frames, rect: rect)
        drawColumnText(displayDate(payment.paidAt), id: "date", frames: frames, rect: rect)
        drawColumnText(payment.method.title, id: "method", frames: frames, rect: rect)
        drawColumnText(payment.reference ?? payment.note ?? "—", id: "reference", frames: frames, rect: rect)
        drawColumnText(
            displayMoney(Money(minorUnits: payment.amountMinor, currency: payment.currency)),
            id: "amount",
            frames: frames,
            rect: rect,
            alignment: .right,
            bold: true
        )
    }

    private func drawColumnText(
        _ value: String,
        id: String,
        frames: [ColumnFrame],
        rect: CGRect,
        alignment: NSTextAlignment = .left,
        bold: Bool = false
    ) {
        guard let frame = frames.first(where: { $0.id == id }) else { return }

        _ = drawText(
            value,
            at: CGRect(x: frame.rect.minX, y: rect.minY + 10, width: frame.rect.width, height: rect.height - 16),
            font: font(8.6, weight: bold ? .semibold : .regular),
            color: bold ? primaryTextColor : bodyTextColor,
            alignment: alignment
        )
    }

    private func drawTableHeader(columns: [TableColumn], y: CGFloat) {
        let rect = CGRect(x: marginLeft, y: y, width: contentWidth, height: 28)
        NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.97, alpha: 1).setFill()
        rect.fill()

        for frame in columnFrames(for: columns, in: rect) {
            _ = drawText(
                frame.title,
                at: CGRect(x: frame.rect.minX, y: rect.minY + 7, width: frame.rect.width, height: 12),
                font: font(8.2, weight: .bold),
                color: mutedPrimaryTextColor,
                alignment: frame.alignment
            )
        }

        drawHorizontalSeparator(y: rect.maxY)
    }

    private func drawLineTotals(at y: CGFloat) -> CGFloat {
        let width: CGFloat = 248
        let amountFrame = columnFrames(
            for: lineColumns(),
            in: CGRect(x: marginLeft, y: 0, width: contentWidth, height: 0)
        )
        .first(where: { $0.id == "amount" })?.rect
        let amountRect = amountFrame ?? CGRect(x: pageSize.width - marginRight - 74, y: 0, width: 74, height: 0)
        let panelRight = amountFrame?.maxX ?? (pageSize.width - marginRight)
        let rect = CGRect(x: panelRight - width, y: y, width: width, height: lineTotalsPanelHeight)
        let labelWidth = max(60, amountRect.minX - rect.minX - 20)
        let valueX = amountRect.minX
        let valueWidth = amountRect.width
        drawLocalSeparator(fromX: rect.minX, toX: rect.maxX, y: rect.minY)

        let rows = lineTotalsRows

        var rowY = rect.minY + 8
        for (index, row) in rows.enumerated() {
            if index > 0 {
                drawLocalSeparator(
                    fromX: rect.minX,
                    toX: rect.maxX,
                    y: rowY - 4
                )
            }
            let valueHeight = max(
                18,
                measureText(
                    row.1,
                    width: valueWidth,
                    font: font(8.5, weight: index == 2 ? .bold : .semibold)
                ).height
            )
            _ = drawText(
                row.0,
                at: CGRect(x: rect.minX + 10, y: rowY, width: labelWidth - 10, height: valueHeight),
                font: font(8.4, weight: index == 2 ? .semibold : .regular),
                color: secondaryTextColor
            )
            _ = drawText(
                row.1,
                at: CGRect(x: valueX, y: rowY, width: valueWidth, height: valueHeight),
                font: font(8.5, weight: index == 2 ? .bold : .semibold),
                color: index == 2 ? accentColor : primaryTextColor,
                alignment: .right
            )
            rowY += valueHeight + 4
        }

        drawLocalSeparator(fromX: rect.minX, toX: rect.maxX, y: rect.maxY)

        return rect.maxY
    }

    private func drawCurrencyTableTitle(
        currency: String,
        isContinuation: Bool,
        at y: CGFloat
    ) -> CGFloat {
        let text = isContinuation
            ? String(format: localized("pdf.currency.continued", defaultValue: "Para Birimi: %@ (Devam)"), currency)
            : String(format: localized("pdf.currency", defaultValue: "Para Birimi: %@"), currency)

        _ = drawText(
            text,
            at: CGRect(x: marginLeft, y: y, width: contentWidth, height: 16),
            font: font(8.6, weight: .bold),
            color: accentColor
        )
        return y + currencyTableTitleHeight
    }

    private func drawPaymentTotals(at y: CGFloat) -> CGFloat {
        let width: CGFloat = 248
        let amountFrame = columnFrames(
            for: paymentColumns(),
            in: CGRect(x: marginLeft, y: 0, width: contentWidth, height: 0)
        )
        .first(where: { $0.id == "amount" })?.rect
        let amountRect = amountFrame ?? CGRect(x: pageSize.width - marginRight - 84, y: 0, width: 84, height: 0)
        let panelRight = amountFrame?.maxX ?? (pageSize.width - marginRight)
        let rect = CGRect(x: panelRight - width, y: y, width: width, height: paymentTotalsPanelHeight)
        let labelWidth = max(60, amountRect.minX - rect.minX - 20)
        let valueX = amountRect.minX
        let valueWidth = amountRect.width
        drawLocalSeparator(fromX: rect.minX, toX: rect.maxX, y: rect.minY)

        let paymentValueHeight = max(
            18,
            measureText(
                paymentTotalsText,
                width: valueWidth,
                font: font(8.6, weight: .bold)
            ).height
        )
        _ = drawText(
            localized("pdf.payment.totalCollected", defaultValue: "Tahsilat Toplamı"),
            at: CGRect(x: rect.minX + 10, y: rect.minY + 8, width: labelWidth - 10, height: paymentValueHeight),
            font: font(8.4, weight: .semibold),
            color: secondaryTextColor
        )
        _ = drawText(
            paymentTotalsText,
            at: CGRect(x: valueX, y: rect.minY + 8, width: valueWidth, height: paymentValueHeight),
            font: font(8.6, weight: .bold),
            color: accentColor,
            alignment: .right
        )

        drawLocalSeparator(fromX: rect.minX, toX: rect.maxX, y: rect.maxY)

        return rect.maxY
    }

    private func drawCard(
        in rect: CGRect,
        title: String,
        rows: [(String, String)],
        alignRight: Bool
    ) {
        drawRoundedRect(
            rect,
            fill: NSColor(calibratedWhite: 0.98, alpha: 1),
            stroke: NSColor(calibratedWhite: 0.90, alpha: 1),
            radius: 12
        )

        _ = drawText(
            title,
            at: CGRect(x: rect.minX + 14, y: rect.minY + 11, width: rect.width - 28, height: 14),
            font: font(10, weight: .bold),
            color: primaryTextColor
        )

        let rowHeight = rows.count > 4 ? 11.5 : 14.0
        var rowY = rect.minY + 30

        for row in rows {
            _ = drawText(
                row.0,
                at: CGRect(x: rect.minX + 14, y: rowY, width: rect.width * 0.34, height: rowHeight),
                font: font(8.3),
                color: secondaryTextColor
            )
            _ = drawText(
                row.1,
                at: CGRect(x: rect.minX + rect.width * 0.38, y: rowY, width: rect.width * 0.54 - 14, height: rowHeight),
                font: font(8.3, weight: .semibold),
                color: primaryTextColor,
                alignment: alignRight ? .right : .left
            )
            rowY += rowHeight + 2
        }
    }

    private func drawRoundedRect(_ rect: CGRect, fill: NSColor, stroke: NSColor, radius: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()

        if stroke != .clear {
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawHorizontalSeparator(y: CGFloat) {
        NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: marginLeft, y: y))
        path.line(to: CGPoint(x: pageSize.width - marginRight, y: y))
        path.stroke()
    }

    private func drawLocalSeparator(fromX: CGFloat, toX: CGFloat, y: CGFloat) {
        NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: fromX, y: y))
        path.line(to: CGPoint(x: toX, y: y))
        path.stroke()
    }

    @discardableResult
    private func drawText(
        _ text: String,
        at rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let measured = attributed.boundingRect(
            with: NSSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: ceil(measured.height))
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(measured.height)
    }

    private func measureText(_ text: String, width: CGFloat, font: NSFont) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]

        let rect = NSAttributedString(string: text, attributes: attributes).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private func lineMetaText(for line: BillingReportLine) -> String {
        if line.isFixedFee {
            let fixedFee = line.fixedFeeMinor.map {
                displayMoney(Money(minorUnits: $0, currency: line.currency))
            } ?? displayMoney(line.amount)
            return String(format: localized("pdf.line.fixedFeeMeta", defaultValue: "Fiyatlandırma: Sabit Tutar | Tutar: %@"), fixedFee)
        }

        return String(
            format: localized("pdf.line.serviceMeta", defaultValue: "Hizmet: %@ | Zaman: %@"),
            line.serviceType.title,
            line.timeType.title
        )
    }

    private func estimatedLineHeight(for line: BillingReportLine) -> CGFloat {
        let width = lineColumns().first(where: { $0.id == "description" })?.width ?? 240
        let titleHeight = measureText(line.todoTitle, width: width, font: font(9.2, weight: .bold)).height
        let timeHeight = measureText(
            String(
                format: localized("pdf.line.timing", defaultValue: "Başlangıç: %@ | Bitiş: %@"),
                displayDateTimeWithSeconds(line.startedAt),
                displayDateTimeWithSeconds(line.endedAt)
            ),
            width: width,
            font: font(8.1)
        ).height
        let metaHeight = measureText(
            lineMetaText(for: line),
            width: width,
            font: font(8.1)
        ).height
        let noteHeight: CGFloat
        if settings.showLineNotes, let note = clean(line.note) {
            noteHeight = measureText(
                String(format: localized("pdf.line.note", defaultValue: "Not: %@"), note),
                width: width - 20,
                font: font(8.4)
            ).height + 24
        } else {
            noteHeight = 0
        }

        return max(64, 18 + titleHeight + timeHeight + metaHeight + noteHeight + 10)
    }

    private func estimatedPaymentHeight(for payment: Payment) -> CGFloat {
        let width = paymentColumns().first(where: { $0.id == "reference" })?.width ?? 160
        let reference = payment.reference ?? payment.note ?? "—"
        let height = measureText(reference, width: width, font: font(8.6)).height
        return max(28, height + 16)
    }

    private func lineColumns() -> [TableColumn] {
        let columns: [TableColumn] = [
            .init(id: "no", title: localized("pdf.column.no", defaultValue: "No"), width: 20),
            .init(id: "description", title: localized("pdf.column.serviceDescription", defaultValue: "Hizmet / İş Tanımı"), width: contentWidth - 20 - 50 - 74 - 74 - (lineGap * 4)),
            .init(id: "duration", title: localized("workSessions.column.duration", defaultValue: "Süre"), width: 46, alignment: .right),
            .init(id: "unitPrice", title: localized("pdf.column.unitPrice", defaultValue: "Birim Fiyat"), width: 74, alignment: .right),
            .init(id: "amount", title: localized("reports.table.amount", defaultValue: "Tutar"), width: 74, alignment: .right)
        ]
        return columns
    }

    private func paymentColumns() -> [TableColumn] {
        [
            .init(id: "no", title: localized("pdf.column.no", defaultValue: "No"), width: 24),
            .init(id: "date", title: localized("exchangeRates.column.date", defaultValue: "Tarih"), width: 118),
            .init(id: "method", title: localized("payment.column.method", defaultValue: "Yöntem"), width: 88),
            .init(id: "reference", title: localized("todoForm.description", defaultValue: "Açıklama"), width: contentWidth - 24 - 118 - 88 - 84 - (lineGap * 4)),
            .init(id: "amount", title: localized("reports.table.amount", defaultValue: "Tutar"), width: 84, alignment: .right)
        ]
    }

    private func columnFrames(for columns: [TableColumn], in rect: CGRect) -> [ColumnFrame] {
        var currentX = rect.minX
        return columns.map { column in
            let frame = CGRect(x: currentX, y: rect.minY, width: column.width, height: rect.height)
            currentX += column.width + lineGap
            return ColumnFrame(id: column.id, title: column.title, rect: frame, alignment: column.alignment)
        }
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

    private var accentColor: NSColor {
        nsColor(from: settings.normalizedAccentHexColor) ?? NSColor.systemBlue
    }

    private var primaryTextColor: NSColor {
        NSColor(calibratedWhite: 0.12, alpha: 1)
    }

    private var bodyTextColor: NSColor {
        NSColor(calibratedWhite: 0.20, alpha: 1)
    }

    private var secondaryTextColor: NSColor {
        NSColor(calibratedWhite: 0.42, alpha: 1)
    }

    private var mutedPrimaryTextColor: NSColor {
        NSColor(calibratedWhite: 0.30, alpha: 1)
    }

    private var footerTextColor: NSColor {
        NSColor(calibratedWhite: 0.42, alpha: 1)
    }

    private var footerMutedTextColor: NSColor {
        NSColor(calibratedWhite: 0.56, alpha: 1)
    }

    private func nsColor(from hex: String) -> NSColor? {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }

    private func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size * settings.normalizedFontScale, weight: weight)
    }

    private var companyDisplayName: String {
        clean(bundle.companyProfile?.tradeName) ??
        clean(bundle.companyProfile?.legalName) ??
        "ProWork"
    }

    /// Tüm satırlar muafsa muafiyet etiketi gösterilir.
    private var allLinesExempt: Bool {
        !bundle.lines.isEmpty && bundle.lines.allSatisfy { $0.isVatExempt }
    }

    private var vatLabel: String {
        if allLinesExempt {
            return localized("pdf.summary.vatExempt", defaultValue: "KDV (Muaf)")
        }
        if let firstRate = bundle.lines.first?.vatRate, firstRate > 0 {
            let percentage = NSDecimalNumber(decimal: firstRate * 100).stringValue
            return String(format: localized("pdf.summary.vatRate", defaultValue: "KDV (%%%@)"), percentage)
        }
        return localized("reports.summary.vat", defaultValue: "KDV")
    }

    private var summaryItems: [(String, String, Bool)] {
        [
            (localized("reports.summary.subtotal", defaultValue: "Ara Toplam"), lineSubtotalText, false),
            (vatLabel, lineVatText, false),
            (localized("reports.summary.grandTotal", defaultValue: "Genel Toplam"), lineGrandTotalText, true),
            (localized("pdf.summary.collected", defaultValue: "Tahsil Edilen"), paymentTotalsText, false),
            (localized("pdf.summary.balance", defaultValue: "Kalan Bakiye"), balanceTotalsText, hasOutstandingBalance)
        ]
    }

    private var summarySectionHeight: CGFloat {
        20 + summaryCardHeight + sectionGap
    }

    private var summaryCardHeight: CGFloat {
        let gap: CGFloat = 8
        let itemWidth = (contentWidth - (gap * CGFloat(max(summaryItems.count - 1, 0)))) / CGFloat(max(summaryItems.count, 1))
        let valueWidth = itemWidth - 20
        let maxValueHeight = summaryItems.map { item in
            measureText(
                item.1,
                width: valueWidth,
                font: font(item.2 ? 10.4 : 9.6, weight: .bold)
            ).height
        }.max() ?? 20

        return max(66, 41 + maxValueHeight)
    }

    private var documentNumber: String {
        let year = bundle.run.periodStart.prefix(4)
        return "HD-\(year)-\(bundle.run.id.prefix(6).uppercased())"
    }

    private var periodLabel: String {
        "\(displayDay(bundle.run.periodStart)) - \(displayDay(bundle.run.periodEnd))"
    }

    private var groupedLineSections: [CurrencyIndexedSection] {
        makeCurrencySections(from: bundle.lines.map(\.currency))
    }

    private var groupedPaymentSections: [CurrencyIndexedSection] {
        makeCurrencySections(from: bundle.payments.map(\.currency))
    }

    private var lineOrdinalByIndex: [Int: Int] {
        makeOrdinalMap(from: groupedLineSections)
    }

    private var paymentOrdinalByIndex: [Int: Int] {
        makeOrdinalMap(from: groupedPaymentSections)
    }

    private var shouldShowLineCurrencyTitles: Bool {
        groupedLineSections.count > 1
    }

    private var shouldShowPaymentCurrencyTitles: Bool {
        groupedPaymentSections.count > 1
    }

    private var shouldShowPaymentTotals: Bool {
        bundle.payments.count > 1
    }

    private var lineTotalsRows: [(String, String)] {
        [
            (localized("pdf.lineTotals.subtotal", defaultValue: "Tutarlar Toplamı"), lineSubtotalText),
            (localized("pdf.lineTotals.vat", defaultValue: "KDV Tutarı"), lineVatText),
            (localized("reports.summary.grandTotal", defaultValue: "Genel Toplam"), lineGrandTotalText)
        ]
    }

    private var lineTotalsPanelHeight: CGFloat {
        let valueWidth: CGFloat = 124
        let rowHeights = lineTotalsRows.enumerated().map { index, row in
            max(
                18,
                measureText(
                    row.1,
                    width: valueWidth,
                    font: font(8.5, weight: index == 2 ? .bold : .semibold)
                ).height
            )
        }
        let contentHeight = rowHeights.reduce(0, +) + (CGFloat(rowHeights.count) * 4) + 12
        return max(66, contentHeight)
    }

    private var paymentTotalsPanelHeight: CGFloat {
        let valueWidth: CGFloat = 124
        let valueHeight = max(
            18,
            measureText(
                paymentTotalsText,
                width: valueWidth,
                font: font(8.6, weight: .bold)
            ).height
        )
        return max(34, valueHeight + 16)
    }

    private var lineSubtotalText: String {
        groupedMoneyText(from: bundle.lines.map { Money(minorUnits: $0.amountMinor, currency: $0.currency) })
    }

    private var lineVatText: String {
        if allLinesExempt {
            return localized("vat.exemptBadge", defaultValue: "Muaf")
        }
        return groupedMoneyText(from: bundle.lines.map { Money(minorUnits: $0.vatMinor, currency: $0.currency) })
    }

    private var lineGrandTotalText: String {
        groupedMoneyText(from: bundle.lines.map { Money(minorUnits: $0.totalMinor, currency: $0.currency) })
    }

    private var paymentTotalsText: String {
        groupedMoneyText(from: bundle.payments.map { Money(minorUnits: $0.amountMinor, currency: $0.currency) })
    }

    private var balanceTotalsText: String {
        groupedMoneyText(from: currentBalanceMonies)
    }

    private var hasOutstandingBalance: Bool {
        var balances: [String: Int] = [:]

        for line in bundle.lines {
            balances[line.currency, default: 0] += line.totalMinor
        }

        for payment in bundle.payments {
            balances[payment.currency, default: 0] -= payment.amountMinor
        }

        return balances.values.contains { $0 > 0 }
    }

    private var documentCurrenciesText: String {
        let codes = Set(
            bundle.lines.map(\.currency) +
            bundle.payments.map(\.currency)
        )
        .filter { !$0.isEmpty }
        .sorted()

        if codes.isEmpty {
            return bundle.run.currency
        }

        if codes.count == 1 {
            return codes[0]
        }

        return codes.joined(separator: "\n")
    }

    private func groupedMoneyText(from monies: [Money]) -> String {
        guard !monies.isEmpty else {
            return displayMoney(Money.zero(bundle.run.currency))
        }

        let parts = groupedMoneyLines(from: monies)
        return parts.isEmpty ? displayMoney(Money.zero(bundle.run.currency)) : parts.joined(separator: "\n")
    }

    private func groupedMoneyLines(from monies: [Money]) -> [String] {
        let grouped = Dictionary(grouping: monies, by: \.currency)
        return grouped.keys.sorted().compactMap { currency -> String? in
            guard let items = grouped[currency] else { return nil }
            let totalMinor = items.reduce(0) { $0 + $1.minorUnits }
            return ProWorkFormatters.moneyAccounting(Money(minorUnits: totalMinor, currency: currency))
        }
    }

    private func makeCurrencySections(from currencies: [String]) -> [CurrencyIndexedSection] {
        let grouped = Dictionary(grouping: Array(currencies.enumerated()), by: \.element)

        return grouped.keys.sorted().map { currency in
            CurrencyIndexedSection(
                currency: currency,
                indices: grouped[currency]?.map(\.offset) ?? []
            )
        }
    }

    private func makeOrdinalMap(from sections: [CurrencyIndexedSection]) -> [Int: Int] {
        var result: [Int: Int] = [:]

        for section in sections {
            for (ordinal, index) in section.indices.enumerated() {
                result[index] = ordinal + 1
            }
        }

        return result
    }

    private func displayMoney(_ money: Money) -> String {
        ProWorkFormatters.money(money)
    }

    private var currentBalanceMonies: [Money] {
        var balances: [String: Int] = [:]

        for line in bundle.lines {
            balances[line.currency, default: 0] += line.totalMinor
        }

        for payment in bundle.payments {
            balances[payment.currency, default: 0] -= payment.amountMinor
        }

        return balances
            .filter { $0.value != 0 }
            .map { Money(minorUnits: $0.value, currency: $0.key) }
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = selectedLocale
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func displayDateTimeWithSeconds(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = selectedLocale
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter.string(from: date)
    }

    private func displayDay(_ raw: String?) -> String {
        guard let raw,
              let date = Self.sqliteDayFormatter.date(from: raw) else {
            return "—"
        }
        return displayDate(date)
    }

    private func displayOptionalDay(_ raw: String?) -> String? {
        guard let raw,
              let date = Self.sqliteDayFormatter.date(from: raw) else {
            return nil
        }
        return displayDate(date)
    }

    private func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let sqliteDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct RenderPage {
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

private struct CurrencyIndexedSection {
    let currency: String
    let indices: [Int]
}

private struct CurrencyTableChunk {
    let currency: String
    let isContinuation: Bool
    var indices: [Int] = []
}

private struct TableColumn {
    let id: String
    let title: String
    let width: CGFloat
    var alignment: NSTextAlignment = .left
}

private struct ColumnFrame {
    let id: String
    let title: String
    let rect: CGRect
    let alignment: NSTextAlignment
}
