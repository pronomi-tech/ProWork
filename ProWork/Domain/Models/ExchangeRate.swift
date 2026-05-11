//
//  ExchangeRate.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

enum ExchangeRateSource: String, CaseIterable, Identifiable, Hashable {
    case tcmb
    case global
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcmb: return ProWorkLocalizer.shared.string("exchangeRates.source.tcmb", defaultValue: "TCMB")
        case .global: return ProWorkLocalizer.shared.string("exchangeRates.source.global", defaultValue: "Global")
        case .manual: return ProWorkLocalizer.shared.string("exchangeRates.source.manual", defaultValue: "Manuel")
        }
    }

    var systemImage: String {
        switch self {
        case .tcmb: return "building.columns"
        case .global: return "globe.europe.africa"
        case .manual: return "hand.raised"
        }
    }
}

enum ExchangeRateAutoSource: String, CaseIterable, Identifiable, Hashable, Codable {
    case tcmb
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcmb: return ProWorkLocalizer.shared.string("exchangeRates.source.tcmb", defaultValue: "TCMB")
        case .global: return ProWorkLocalizer.shared.string("exchangeRates.source.global", defaultValue: "Global")
        }
    }

    var subtitle: String {
        switch self {
        case .tcmb: return ProWorkLocalizer.shared.string("exchangeRates.autoSource.tcmb.subtitle", defaultValue: "TCMB alış/satış ve efektif kurları")
        case .global: return ProWorkLocalizer.shared.string("exchangeRates.autoSource.global.subtitle", defaultValue: "Global referans kur yedek kaynağı")
        }
    }

    var systemImage: String {
        switch self {
        case .tcmb: return "building.columns"
        case .global: return "globe.europe.africa"
        }
    }

    var source: ExchangeRateSource {
        switch self {
        case .tcmb: return .tcmb
        case .global: return .global
        }
    }

    var fallbackSource: ExchangeRateSource {
        switch self {
        case .tcmb: return .global
        case .global: return .tcmb
        }
    }
}

/// Bir tarih için iki para birimi arası kur. TCMB'den otomatik veya manuel girilebilir.
struct ExchangeRate: Identifiable, Hashable {
    let id: String
    var fromCurrency: String
    var toCurrency: String
    /// "1 fromCurrency = rate toCurrency" anlamında.
    var rate: Decimal
    var forexBuying: Decimal?
    var forexSelling: Decimal?
    var banknoteBuying: Decimal?
    var banknoteSelling: Decimal?
    /// "yyyy-MM-dd"
    var rateDate: String
    var source: ExchangeRateSource
    var fetchedAt: Date
    var note: String?

    var organizationId: String
    var createdByUserId: String?
    var updatedByUserId: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var rowVersion: Int
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?
    var originDeviceId: String?

    init(
        id: String = UUID().uuidString,
        fromCurrency: String,
        toCurrency: String,
        rate: Decimal,
        forexBuying: Decimal? = nil,
        forexSelling: Decimal? = nil,
        banknoteBuying: Decimal? = nil,
        banknoteSelling: Decimal? = nil,
        rateDate: String,
        source: ExchangeRateSource,
        fetchedAt: Date = Date(),
        note: String? = nil,
        organizationId: String = BuiltInOrganizationId.default,
        createdByUserId: String? = BuiltInUserId.defaultOwner,
        updatedByUserId: String? = BuiltInUserId.defaultOwner,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        rowVersion: Int = 0,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil,
        originDeviceId: String? = nil
    ) {
        self.id = id
        self.fromCurrency = fromCurrency.uppercased()
        self.toCurrency = toCurrency.uppercased()
        self.rate = rate
        self.forexBuying = forexBuying
        self.forexSelling = forexSelling
        self.banknoteBuying = banknoteBuying
        self.banknoteSelling = banknoteSelling
        self.rateDate = rateDate
        self.source = source
        self.fetchedAt = fetchedAt
        self.note = note
        self.organizationId = organizationId
        self.createdByUserId = createdByUserId
        self.updatedByUserId = updatedByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.rowVersion = rowVersion
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
        self.originDeviceId = originDeviceId
    }
}

extension ExchangeRate {
    var operationalRate: Decimal {
        forexSelling ?? forexBuying ?? banknoteSelling ?? banknoteBuying ?? rate
    }

    var meta: RecordMetadata {
        RecordMetadata(
            organizationId: organizationId,
            createdByUserId: createdByUserId,
            updatedByUserId: updatedByUserId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowVersion: rowVersion,
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt,
            originDeviceId: originDeviceId
        )
    }

    init(
        id: String = UUID().uuidString,
        fromCurrency: String,
        toCurrency: String,
        rate: Decimal,
        forexBuying: Decimal? = nil,
        forexSelling: Decimal? = nil,
        banknoteBuying: Decimal? = nil,
        banknoteSelling: Decimal? = nil,
        rateDate: String,
        source: ExchangeRateSource,
        fetchedAt: Date = Date(),
        note: String? = nil,
        meta: RecordMetadata
    ) {
        self.init(
            id: id,
            fromCurrency: fromCurrency,
            toCurrency: toCurrency,
            rate: rate,
            forexBuying: forexBuying,
            forexSelling: forexSelling,
            banknoteBuying: banknoteBuying,
            banknoteSelling: banknoteSelling,
            rateDate: rateDate,
            source: source,
            fetchedAt: fetchedAt,
            note: note,
            organizationId: meta.organizationId,
            createdByUserId: meta.createdByUserId,
            updatedByUserId: meta.updatedByUserId,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
            deletedAt: meta.deletedAt,
            rowVersion: meta.rowVersion,
            syncStatus: meta.syncStatus,
            lastSyncedAt: meta.lastSyncedAt,
            originDeviceId: meta.originDeviceId
        )
    }
}
