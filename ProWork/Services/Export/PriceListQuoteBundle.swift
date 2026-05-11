//
//  PriceListQuoteBundle.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Bir fiyat listesi teklif PDF'inin render edilebilmesi için gereken tüm değerler.
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
    /// Tek bir teklif kalemi (PDF tablosunda bir satır).
    struct Line: Hashable, Identifiable {
        var id: String { rowId }
        var rowId: String
        var primaryDescription: String
        var secondaryDescription: String?
        var quantityLabel: String
        var unitPrice: Money
    }

    /// Aynı `ServiceType` altındaki satırların grubu.
    struct Section: Hashable, Identifiable {
        var id: String { title }
        var title: String
        var subtitle: String?
        var lines: [Line]
    }

    /// Tüm satırların aynı para biriminde olduğu varsayılır; ilk satırın para birimini döner.
    var currency: String {
        sections.first?.lines.first?.unitPrice.currency ?? priceList.currency
    }
}
