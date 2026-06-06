//  PriceListQuoteBundleBuilder.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Converts `PriceList` + rows + recipient info into a renderable `PriceListQuoteBundle`.
struct PriceListQuoteBundleBuilder {
    /// Recipient information from the form field.
    struct RecipientInput {
        var name: String
        var contactPerson: String?
        var address: String?
        var code: String?
    }

    func build(
        priceList: PriceList,
        rows: [PriceListRow],
        categories: [TaskCategory],
        recipient: RecipientInput,
        quoteNumber: String,
        issueDate: Date,
        companyProfile: CompanyProfile?,
        customer: Customer?,
        settings: PriceListQuoteTemplateSettings
    ) -> PriceListQuoteBundle {
        let activeRows = rows.filter { $0.isActive }
        let sections = makeSections(rows: activeRows, categories: categories)
        // Previously Calendar.current; quote validity
        // computed on a non-Istanbul host could drift by a day at DST
        // boundaries. Use the pinned Istanbul calendar to match the rest
        // of the billing pipeline.
        let validUntil = AppCalendar.istanbul.date(
            byAdding: .day,
            value: settings.normalizedValidityDays,
            to: issueDate
        ) ?? issueDate

        let title = settings.titleTemplate
            .replacingOccurrences(of: "{customerName}", with: recipient.name)
            .replacingOccurrences(of: "{year}", with: yearString(from: issueDate))
            .replacingOccurrences(of: "{priceListName}", with: priceList.name)

        return PriceListQuoteBundle(
            quoteNumber: quoteNumber,
            issueDate: issueDate,
            validUntil: validUntil,
            recipientName: recipient.name,
            recipientContact: clean(recipient.contactPerson),
            recipientAddress: clean(recipient.address),
            recipientCode: clean(recipient.code),
            titleText: title,
            sections: sections,
            companyProfile: companyProfile,
            priceList: priceList,
            customer: customer,
            settings: settings
        )
    }

    private func makeSections(
        rows: [PriceListRow],
        categories: [TaskCategory]
    ) -> [PriceListQuoteBundle.Section] {
        let grouped = Dictionary(grouping: rows, by: \.serviceType)
        let orderedTypes: [ServiceType] = [.remote, .onsite]

        return orderedTypes.compactMap { type -> PriceListQuoteBundle.Section? in
            guard let typeRows = grouped[type], !typeRows.isEmpty else { return nil }
            let lines = typeRows
                .sorted(by: rowSortOrder)
                .map { row in
                    PriceListQuoteBundle.Line(
                        rowId: row.id,
                        primaryDescription: primaryDescription(for: row, in: type, categories: categories),
                        secondaryDescription: secondaryDescription(for: row, categories: categories),
                        quantityLabel: ProWorkLocalizer.shared.string("quote.quantity.hour", defaultValue: "1 saat"),
                        unitPrice: row.unitPrice
                    )
                }
            return PriceListQuoteBundle.Section(
                title: sectionTitle(for: type),
                subtitle: nil,
                lines: lines
            )
        }
    }

    private func sectionTitle(for type: ServiceType) -> String {
        switch type {
        case .remote:
            return ProWorkLocalizer.shared.string("quote.section.remote", defaultValue: "Uzak Servis Hizmeti")
        case .onsite:
            return ProWorkLocalizer.shared.string("quote.section.onsite", defaultValue: "Yerinde Servis Hizmeti")
        }
    }

    /// The default phrasing ("Saatlik uzaktan hizmet bedeli")
    /// pairs with `quote.quantity.hour` ("1 saat") to assume an hourly
    /// rate. Any deployment selling daily/piece-rate work must override
    /// **both** strings together via Localizable.strings; the keys are
    /// documented here so the assumption is visible at the call site
    /// rather than buried in the localiser bundle. A future tier might
    /// expose per-row unit types in the model so the wording follows
    /// `PriceListRow.unit` instead of static strings.
    private func primaryDescription(
        for row: PriceListRow,
        in type: ServiceType,
        categories: [TaskCategory]
    ) -> String {
        let baseKey: String
        switch type {
        case .remote:
            baseKey = "quote.line.remote.base"
        case .onsite:
            baseKey = "quote.line.onsite.base"
        }
        let base = ProWorkLocalizer.shared.string(
            baseKey,
            defaultValue: type == .remote
                ? "Saatlik uzaktan hizmet bedeli"
                : "Yerinde personel desteği"
        )
        return "\(base) – \(row.timeType.title)"
    }

    private func secondaryDescription(
        for row: PriceListRow,
        categories: [TaskCategory]
    ) -> String? {
        var parts: [String] = []

        if let start = row.startTime, let end = row.endTime {
            parts.append("\(format(time: start)) – \(format(time: end))")
        }

        if let mask = row.weekdayMask, mask != 0 {
            let days = PriceListRow.weekdays(fromMask: mask)
                .sorted(by: { $0.rawValue < $1.rawValue })
                .map(\.shortTitle)
                .joined(separator: ", ")
            if !days.isEmpty {
                parts.append(days)
            }
        }

        if let categoryId = row.categoryId,
           let category = categories.first(where: { $0.id == categoryId }) {
            parts.append(category.name)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func format(time: TimeOfDay) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    private func rowSortOrder(_ lhs: PriceListRow, _ rhs: PriceListRow) -> Bool {
        if lhs.timeType.sortOrder != rhs.timeType.sortOrder {
            return lhs.timeType.sortOrder < rhs.timeType.sortOrder
        }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Shared static formatter — instance allocation per call
    /// is wasteful and the locale/format never change. POSIX
    /// `yyyy` is required so the build year stays unambiguous regardless
    /// of the user's locale.
    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private func yearString(from date: Date) -> String {
        Self.yearFormatter.string(from: date)
    }
}

/// Produces a quote number from the given year + sequence number using the format template.
enum PriceListQuoteNumberFormatter {
    /// Emit a 4-digit year. The previous `%02d, year % 100`
    /// form would have made 2099 (`"99"`) and 2100 (`"00"`) collide for
    /// long-lived documents — and the same shortened year would have
    /// made 2026 ("26") and 1926 ("26") indistinguishable. Visible
    /// quote numbers (`TKL.YYYY.NN`) are unambiguous through the
    /// turn of the century.
    static func format(prefix: String, year: Int, sequence: Int) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrefix = trimmedPrefix.isEmpty ? "TKL" : trimmedPrefix
        let yearString = String(format: "%04d", year)
        let seqString = String(format: "%02d", sequence)
        return "\(cleanPrefix).\(yearString).\(seqString)"
    }
}
