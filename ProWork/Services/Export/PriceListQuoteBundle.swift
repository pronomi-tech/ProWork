//  PriceListQuoteBundle.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// All values required to render a price-list quote PDF.
struct PriceListQuoteBundle: Hashable {
    var quoteNumber: String
    var issueDate: Date
    var validUntil: Date
    var recipientName: String
    var recipientContact: String?
    var recipientAddress: String?
    var recipientCode: String?
    var titleText: String
    var sections: [Section]
    var companyProfile: CompanyProfile?
    var priceList: PriceList
    var customer: Customer?
    var settings: PriceListQuoteTemplateSettings
}

extension PriceListQuoteBundle {
    /// A single quote line item (one row in the PDF table).
    struct Line: Hashable, Identifiable {
        var id: String { rowId }
        var rowId: String
        var primaryDescription: String
        var secondaryDescription: String?
        var quantityLabel: String
        var unitPrice: Money
    }

    /// A group of rows under the same `ServiceType`.
    struct Section: Hashable, Identifiable {
        var id: String { title }
        var title: String
        var subtitle: String?
        var lines: [Line]
    }

    /// Assumes every line uses the same currency; returns the first line's currency.
    var currency: String {
        sections.first?.lines.first?.unitPrice.currency ?? priceList.currency
    }
}
