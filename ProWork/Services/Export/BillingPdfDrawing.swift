//  BillingPdfDrawing.swift
//  ProWork
//  Created by Pronomi.
//  The CGContext drawing layer of BillingPdfDocument: header / title /
//  info cards / line blocks / payment blocks / footer / colour / font
//  helpers. All pagination decisions have already been made by the caller.

import AppKit
import Foundation

extension BillingPdfDocument {
    func draw(page: RenderPage, pageIndex: Int, totalPages: Int) {
        // PriceListQuotePdfRenderer already wraps each
        // page in an autoreleasepool to bound NSImage / CoreText
        // allocations; multi-page BillingPdf exports leaked the same
        // transient objects until the entire render finished. Wrap a
        // matching pool here so peak memory stays bounded by one page.
        autoreleasepool {
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
    }

    private func drawHeader(at y: CGFloat) -> CGFloat {
        let logoFrame = CGRect(x: marginLeft, y: y, width: 220, height: 52)
        // Y6: logoImage is an NSImage downsampled once in init; we no
        // longer decode it again via NSImage(data:) on every page.
        let showsLogo = logoImage != nil

        if let image = logoImage {
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
        // Shared with PriceListQuotePdfRenderer.
        PDFDrawingPrimitives.drawRoundedRect(rect, fill: fill, stroke: stroke, radius: radius)
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
    func drawText(
        _ text: String,
        at rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        // Shared with PriceListQuotePdfRenderer.
        PDFDrawingPrimitives.drawText(text, at: rect, font: font, color: color, alignment: alignment)
    }

    func measureText(_ text: String, width: CGFloat, font: NSFont) -> CGSize {
        // Y5: pagination and drawing ask for the same measurement on the
        // same row repeatedly. We memoize on (text, ceil(width),
        // fontDescriptor) to avoid the allocation. The document instance
        // is short-lived (one render); the cache stays very shallow.
        return measureTextCached(text, width: width, font: font)
    }

    private func measureTextCached(_ text: String, width: CGFloat, font: NSFont) -> CGSize {
        let key = MeasureCacheKey(
            text: text,
            width: ceil(width),
            fontName: font.fontName,
            fontSize: font.pointSize,
            bold: font.fontDescriptor.symbolicTraits.contains(.bold)
        )
        if let cached = lookupMeasureCache(key) {
            return cached
        }
        let computed = computeTextSize(text, width: width, font: font)
        storeMeasureCache(key, computed)
        return computed
    }

    private func computeTextSize(_ text: String, width: CGFloat, font: NSFont) -> CGSize {
        // Shared with PriceListQuotePdfRenderer.
        PDFDrawingPrimitives.measureText(text, width: width, font: font)
    }

    // MARK: - Table columns
    // `lineColumns()` and `paymentColumns()` were being recomputed for
    // every row — fixed metrics + localized header generation each time.
    // Since they don't change during the document's lifetime we memoize
    // them on the first call.

    /// Column widths share the same numeric constants. Previously
    /// the description-column arithmetic subtracted `50` while the
    /// duration column was declared at `46`, drifting the row layout by
    /// 4pt and silently overflowing on long quote titles. Single source
    /// per column eliminates the drift.
    private enum LineColumnWidth {
        static let no: CGFloat = 20
        static let duration: CGFloat = 46
        static let unitPrice: CGFloat = 74
        static let amount: CGFloat = 74
    }

    func lineColumns() -> [TableColumn] {
        if let cached = cachedLineColumns { return cached }
        let descriptionWidth = contentWidth
            - LineColumnWidth.no
            - LineColumnWidth.duration
            - LineColumnWidth.unitPrice
            - LineColumnWidth.amount
            - (lineGap * 4)
        let columns: [TableColumn] = [
            .init(id: "no", title: localized("pdf.column.no", defaultValue: "No"), width: LineColumnWidth.no),
            .init(id: "description", title: localized("pdf.column.serviceDescription", defaultValue: "Hizmet / İş Tanımı"), width: descriptionWidth),
            .init(id: "duration", title: localized("workSessions.column.duration", defaultValue: "Süre"), width: LineColumnWidth.duration, alignment: .right),
            .init(id: "unitPrice", title: localized("pdf.column.unitPrice", defaultValue: "Birim Fiyat"), width: LineColumnWidth.unitPrice, alignment: .right),
            .init(id: "amount", title: localized("reports.table.amount", defaultValue: "Tutar"), width: LineColumnWidth.amount, alignment: .right)
        ]
        cachedLineColumns = columns
        return columns
    }

    func paymentColumns() -> [TableColumn] {
        if let cached = cachedPaymentColumns { return cached }
        let columns: [TableColumn] = [
            .init(id: "no", title: localized("pdf.column.no", defaultValue: "No"), width: 24),
            .init(id: "date", title: localized("exchangeRates.column.date", defaultValue: "Tarih"), width: 118),
            .init(id: "method", title: localized("payment.column.method", defaultValue: "Yöntem"), width: 88),
            .init(id: "reference", title: localized("todoForm.description", defaultValue: "Açıklama"), width: contentWidth - 24 - 118 - 88 - 84 - (lineGap * 4)),
            .init(id: "amount", title: localized("reports.table.amount", defaultValue: "Tutar"), width: 84, alignment: .right)
        ]
        cachedPaymentColumns = columns
        return columns
    }

    func columnFrames(for columns: [TableColumn], in rect: CGRect) -> [ColumnFrame] {
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

    // MARK: - Renkler ve font'lar

    var accentColor: NSColor {
        nsColor(from: settings.normalizedAccentHexColor) ?? NSColor.systemBlue
    }

    var primaryTextColor: NSColor {
        NSColor(calibratedWhite: 0.12, alpha: 1)
    }

    var bodyTextColor: NSColor {
        NSColor(calibratedWhite: 0.20, alpha: 1)
    }

    var secondaryTextColor: NSColor {
        NSColor(calibratedWhite: 0.42, alpha: 1)
    }

    var mutedPrimaryTextColor: NSColor {
        NSColor(calibratedWhite: 0.30, alpha: 1)
    }

    var footerTextColor: NSColor {
        NSColor(calibratedWhite: 0.42, alpha: 1)
    }

    var footerMutedTextColor: NSColor {
        NSColor(calibratedWhite: 0.56, alpha: 1)
    }

    private func nsColor(from hex: String) -> NSColor? {
        // Shared with PriceListQuotePdfRenderer.
        PDFDrawingPrimitives.nsColor(fromHex: hex)
    }

    func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size * settings.normalizedFontScale, weight: weight)
    }
}
