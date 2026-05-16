//
//  BillingPdfPagination.swift
//  ProWork
//
//  Created by Pronomi.
//
//  BillingPdfDocument'in sayfa alokasyon ve yükseklik hesabı katmanı.
//  Sayfa başına satır/ödeme bloklarını kaç parçada dağıtacağını burada
//  belirliyoruz; gerçek `draw*` çağrıları BillingPdfDrawing.swift'te.
//

import AppKit
import Foundation

@MainActor
extension BillingPdfDocument {
    func paginate() -> [RenderPage] {
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

    // MARK: - Yükseklik hesapları

    var contentWidth: CGFloat {
        pageSize.width - marginLeft - marginRight
    }

    var firstPageAvailableHeight: CGFloat {
        pageSize.height - marginTop - marginBottom - footerHeight - firstPageReservedHeight
    }

    var continuationPageAvailableHeight: CGFloat {
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

    var linesSectionHeaderHeight: CGFloat { 36 }
    var paymentsHeaderHeight: CGFloat { 34 }
    var paymentTableHeaderHeight: CGFloat { 30 }
    var emptyLinesHeight: CGFloat { 26 }
    var emptyPaymentsHeight: CGFloat { 26 }
    var lineTotalsHeight: CGFloat { 10 + lineTotalsPanelHeight }
    var paymentTotalsHeight: CGFloat {
        shouldShowPaymentTotals ? 10 + paymentTotalsPanelHeight : 0
    }

    func lineTableBlockHeaderHeight(hasExistingTableOnPage: Bool) -> CGFloat {
        (hasExistingTableOnPage ? tableSectionGap : 0)
        + (shouldShowLineCurrencyTitles ? currencyTableTitleHeight : 0)
        + paymentTableHeaderHeight
    }

    func paymentTableBlockHeaderHeight(hasExistingTableOnPage: Bool) -> CGFloat {
        (hasExistingTableOnPage ? tableSectionGap : 0)
        + (shouldShowPaymentCurrencyTitles ? currencyTableTitleHeight : 0)
        + paymentTableHeaderHeight
    }

    var summarySectionHeight: CGFloat {
        20 + summaryCardHeight + sectionGap
    }

    var summaryCardHeight: CGFloat {
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

    var lineTotalsPanelHeight: CGFloat {
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

    var paymentTotalsPanelHeight: CGFloat {
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

    func estimatedLineHeight(for line: BillingReportLine) -> CGFloat {
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

    func estimatedPaymentHeight(for payment: Payment) -> CGFloat {
        let width = paymentColumns().first(where: { $0.id == "reference" })?.width ?? 160
        let reference = payment.reference ?? payment.note ?? "—"
        let height = measureText(reference, width: width, font: font(8.6)).height
        return max(28, height + 16)
    }
}
