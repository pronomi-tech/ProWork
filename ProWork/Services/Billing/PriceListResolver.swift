//
//  PriceListResolver.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Spec §3 — Fiyat öncelik sırası:
//      1. Task özel fiyat / override varsa onu kullan (TodoBillingOverride)
//      2. Proje özel fiyat listesi varsa onu kullan
//      3. Müşteri fiyat listesi varsa onu kullan
//      4. Genel varsayılan fiyat listesine düş
//
//  Bir oturum + segment için doğru `PriceListRow`'u çözer.
//

import Foundation

/// Çözümleme sonucu.
enum PriceResolution: Hashable {
    /// Bir fiyat satırı bulundu — saatlik ücret üzerinden hesaplanır.
    case row(PriceListRow, ownerType: PriceListOwnerType)
    /// Todo'da `unitPrice` override var — fiyat satırını yerine geçer.
    case todoUnitPriceOverride(unitPriceMinor: Int, currency: String)
    /// Todo'da sabit fee override var — süre ne olursa olsun bu tutar.
    case todoFixedFee(amountMinor: Int, currency: String)
    /// Eşleşen fiyat bulunamadı.
    case noMatch
}

/// Çözümleme kaynaklarını gruplayan input.
struct PriceResolutionContext {
    var todoOverride: TodoBillingOverride?
    var projectPriceLists: [PriceList]    // Proje sahipli aktif listeler
    var customerPriceLists: [PriceList]   // Müşteri sahipli aktif listeler
    var globalPriceLists: [PriceList]     // Genel aktif listeler
    var customerDefaultPriceListId: String?
    var organizationCurrency: String
    /// Liste ID → o listeye ait aktif satırlar.
    var rowsByListId: [String: [PriceListRow]]

    func effectiveCurrency(dateString: String? = nil) -> String {
        PricingCurrencyResolver.resolveProjectCurrency(
            projectLists: projectPriceLists,
            customerLists: customerPriceLists,
            globalLists: globalPriceLists,
            customerDefaultPriceListId: customerDefaultPriceListId,
            organizationCurrency: organizationCurrency,
            dateString: dateString
        )
    }
}

struct PricingCurrencyResolver {
    private let organizationRepository: OrganizationRepository
    private let customerRepository: CustomerRepository
    private let priceListRepository: PriceListRepository

    init(
        organizationRepository: OrganizationRepository? = nil,
        customerRepository: CustomerRepository? = nil,
        priceListRepository: PriceListRepository? = nil
    ) {
        self.organizationRepository = organizationRepository ?? OrganizationRepository()
        self.customerRepository = customerRepository ?? CustomerRepository()
        self.priceListRepository = priceListRepository ?? PriceListRepository()
    }

    func resolveCustomerCurrency(
        customerId: String,
        organizationId: String = BuiltInOrganizationId.default
    ) throws -> String {
        let organizationCurrency = try organizationRepository.fetch(id: organizationId)?.masterCurrency ?? "TRY"
        let customer = try customerRepository.fetch(id: customerId)
        let customerLists = try priceListRepository.fetchOwned(
            organizationId: organizationId,
            ownerType: .customer,
            ownerId: customerId
        )
        let globalLists = try priceListRepository.fetchOwned(
            organizationId: organizationId,
            ownerType: .global,
            ownerId: nil
        )

        return Self.resolveCustomerCurrency(
            customerDefaultPriceListId: customer?.defaultPriceListId,
            customerLists: customerLists,
            globalLists: globalLists,
            organizationCurrency: organizationCurrency
        )
    }

    func resolveProjectCurrency(
        projectId: String,
        customerId: String,
        organizationId: String = BuiltInOrganizationId.default
    ) throws -> String {
        let organizationCurrency = try organizationRepository.fetch(id: organizationId)?.masterCurrency ?? "TRY"
        let customer = try customerRepository.fetch(id: customerId)
        let projectLists = try priceListRepository.fetchOwned(
            organizationId: organizationId,
            ownerType: .project,
            ownerId: projectId
        )
        let customerLists = try priceListRepository.fetchOwned(
            organizationId: organizationId,
            ownerType: .customer,
            ownerId: customerId
        )
        let globalLists = try priceListRepository.fetchOwned(
            organizationId: organizationId,
            ownerType: .global,
            ownerId: nil
        )

        return Self.resolveProjectCurrency(
            projectLists: projectLists,
            customerLists: customerLists,
            globalLists: globalLists,
            customerDefaultPriceListId: customer?.defaultPriceListId,
            organizationCurrency: organizationCurrency
        )
    }

    static func resolveCustomerCurrency(
        customer: Customer?,
        priceLists: [PriceList],
        organizationCurrency: String,
        dateString: String? = nil
    ) -> String {
        let customerLists = priceLists.filter {
            $0.ownerType == .customer && $0.ownerId == customer?.id
        }
        let globalLists = priceLists.filter { $0.ownerType == .global }

        return resolveCustomerCurrency(
            customerDefaultPriceListId: customer?.defaultPriceListId,
            customerLists: customerLists,
            globalLists: globalLists,
            organizationCurrency: organizationCurrency,
            dateString: dateString
        )
    }

    static func resolveProjectCurrency(
        projectId: String,
        customer: Customer?,
        priceLists: [PriceList],
        organizationCurrency: String,
        dateString: String? = nil
    ) -> String {
        let projectLists = priceLists.filter {
            $0.ownerType == .project && $0.ownerId == projectId
        }
        let customerLists = priceLists.filter {
            $0.ownerType == .customer && $0.ownerId == customer?.id
        }
        let globalLists = priceLists.filter { $0.ownerType == .global }

        return resolveProjectCurrency(
            projectLists: projectLists,
            customerLists: customerLists,
            globalLists: globalLists,
            customerDefaultPriceListId: customer?.defaultPriceListId,
            organizationCurrency: organizationCurrency,
            dateString: dateString
        )
    }

    static func resolveCustomerCurrency(
        customerDefaultPriceListId: String? = nil,
        customerLists: [PriceList],
        globalLists: [PriceList],
        organizationCurrency: String,
        dateString: String? = nil
    ) -> String {
        preferredEffectiveCurrency(
            customerDefaultPriceListId: customerDefaultPriceListId,
            customerLists: customerLists,
            globalLists: globalLists,
            dateString: dateString
        )
            ?? effectiveCurrency(from: customerLists, excluding: customerDefaultPriceListId, dateString: dateString)
            ?? effectiveCurrency(from: globalLists, excluding: customerDefaultPriceListId, dateString: dateString)
            ?? organizationCurrency
    }

    static func resolveProjectCurrency(
        projectLists: [PriceList],
        customerLists: [PriceList],
        globalLists: [PriceList],
        customerDefaultPriceListId: String? = nil,
        organizationCurrency: String,
        dateString: String? = nil
    ) -> String {
        effectiveCurrency(from: projectLists, dateString: dateString)
            ?? preferredEffectiveCurrency(
                customerDefaultPriceListId: customerDefaultPriceListId,
                customerLists: customerLists,
                globalLists: globalLists,
                dateString: dateString
            )
            ?? effectiveCurrency(from: customerLists, excluding: customerDefaultPriceListId, dateString: dateString)
            ?? effectiveCurrency(from: globalLists, excluding: customerDefaultPriceListId, dateString: dateString)
            ?? organizationCurrency
    }

    private static func preferredEffectiveCurrency(
        customerDefaultPriceListId: String?,
        customerLists: [PriceList],
        globalLists: [PriceList],
        dateString: String?
    ) -> String? {
        guard let customerDefaultPriceListId else {
            return nil
        }

        return (customerLists + globalLists).first { list in
            guard list.id == customerDefaultPriceListId,
                  list.isActive,
                  list.deletedAt == nil else {
                return false
            }

            guard let dateString else {
                return true
            }

            return PriceListResolver.isWithin(date: dateString, from: list.validFrom, to: list.validTo)
        }?.currency
    }

    private static func effectiveCurrency(
        from lists: [PriceList],
        excluding excludedListId: String? = nil,
        dateString: String?
    ) -> String? {
        lists.first { list in
            guard list.id != excludedListId else {
                return false
            }

            guard list.isActive, list.deletedAt == nil else {
                return false
            }

            guard let dateString else {
                return true
            }

            return PriceListResolver.isWithin(date: dateString, from: list.validFrom, to: list.validTo)
        }?.currency
    }
}

enum PriceListResolver {
    /// §3'teki önceliğe göre tek bir fiyat satırı/override döner.
    /// - Parameters:
    ///   - context: Tüm potansiyel kaynaklar (caller veritabanından önceden çekmiş olur).
    ///   - serviceType: Aranan hizmet tipi (uzaktan/yerinde).
    ///   - timeType: Aranan zaman tipi (regular/afterHours/weekend/holiday).
    ///   - categoryId: Aranan kategori (nil = kategori filtresi yok).
    ///   - weekday: Hangi haftagünü için (weekdayMask filtresi).
    ///   - timeOfDay: Hangi saat (startTime/endTime filtresi).
    ///   - dateString: "yyyy-MM-dd" — fiyat satırının validFrom/validTo aralığı.
    static func resolve(
        context: PriceResolutionContext,
        serviceType: ServiceType,
        timeType: TimeType,
        categoryId: String?,
        weekday: Weekday,
        timeOfDay: TimeOfDay,
        dateString: String
    ) -> PriceResolution {
        // 1. Task override
        if let override = context.todoOverride, override.deletedAt == nil {
            switch override.overrideType {
            case .fixedFee:
                if let fee = override.fixedFeeMinor {
                    return .todoFixedFee(amountMinor: fee, currency: override.currency)
                }
            case .unitPrice:
                if let unit = override.unitPriceMinor {
                    return .todoUnitPriceOverride(
                        unitPriceMinor: unit,
                        currency: override.currency
                    )
                }
            }
        }

        // 2-4. Liste seviyeleri (project → customer → global)
        let levels: [(lists: [PriceList], owner: PriceListOwnerType)] = [
            (context.projectPriceLists, .project),
            preferredCustomerLevel(from: context),
            (context.customerPriceLists.filter { $0.id != context.customerDefaultPriceListId }, .customer),
            (context.globalPriceLists.filter { $0.id != context.customerDefaultPriceListId }, .global)
        ]

        for level in levels {
            if let row = bestRow(
                in: level.lists,
                rowsByListId: context.rowsByListId,
                serviceType: serviceType,
                timeType: timeType,
                categoryId: categoryId,
                weekday: weekday,
                timeOfDay: timeOfDay,
                dateString: dateString
            ) {
                return .row(row, ownerType: level.owner)
            }
        }

        return .noMatch
    }

    private static func preferredCustomerLevel(
        from context: PriceResolutionContext
    ) -> (lists: [PriceList], owner: PriceListOwnerType) {
        guard let defaultListId = context.customerDefaultPriceListId,
              let preferred = (context.customerPriceLists + context.globalPriceLists).first(where: { $0.id == defaultListId }) else {
            return ([], .customer)
        }

        return ([preferred], preferred.ownerType)
    }

    // MARK: - Liste seviyesi içinde en iyi satırı bul

    private static func bestRow(
        in lists: [PriceList],
        rowsByListId: [String: [PriceListRow]],
        serviceType: ServiceType,
        timeType: TimeType,
        categoryId: String?,
        weekday: Weekday,
        timeOfDay: TimeOfDay,
        dateString: String
    ) -> PriceListRow? {
        // Aktif listeleri tara — geçerlilik tarihi içinde olanları al
        let activeLists = lists.filter {
            $0.isActive && $0.deletedAt == nil &&
            isWithin(date: dateString, from: $0.validFrom, to: $0.validTo)
        }

        // timeType fallback (holiday → weekend → afterHours → regular)
        for fallback in timeType.fallbackOrder {
            for list in activeLists {
                guard let rows = rowsByListId[list.id] else { continue }
                if let row = pickRow(
                    from: rows,
                    serviceType: serviceType,
                    timeType: fallback,
                    categoryId: categoryId,
                    weekday: weekday,
                    timeOfDay: timeOfDay,
                    dateString: dateString
                ) {
                    return row
                }
            }
        }
        return nil
    }

    /// Bir liste içindeki satırlardan, eşleşmeye en spesifik olanı seçer.
    /// Skorlama: kategori eşleşmesi > weekdayMask spesifikliği > saat aralığı spesifikliği.
    private static func pickRow(
        from rows: [PriceListRow],
        serviceType: ServiceType,
        timeType: TimeType,
        categoryId: String?,
        weekday: Weekday,
        timeOfDay: TimeOfDay,
        dateString: String
    ) -> PriceListRow? {
        let candidates = rows.filter { row in
            guard row.isActive, row.deletedAt == nil else { return false }
            guard row.serviceType == serviceType else { return false }
            guard row.timeType == timeType else { return false }

            // Kategori filtresi: row.categoryId nil ise tüm kategoriler için geçerli
            if let rowCat = row.categoryId, rowCat != categoryId { return false }

            // Weekday mask
            if !row.appliesTo(weekday: weekday) { return false }

            // Saat aralığı
            if let start = row.startTime, timeOfDay < start { return false }
            if let end = row.endTime, timeOfDay >= end { return false }

            // Geçerlilik tarihi
            if !isWithin(date: dateString, from: row.validFrom, to: row.validTo) {
                return false
            }

            return true
        }

        // En spesifik satırı seç — eşitlikte daha düşük sortOrder kazanır
        let sorted = candidates.sorted { lhs, rhs in
            let lhsScore = specificity(lhs, categoryId: categoryId)
            let rhsScore = specificity(rhs, categoryId: categoryId)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.sortOrder < rhs.sortOrder
        }
        return sorted.first
    }

    /// Daha yüksek skor = daha spesifik eşleşme.
    private static func specificity(_ row: PriceListRow, categoryId: String?) -> Int {
        var score = 0
        if let rowCat = row.categoryId, rowCat == categoryId { score += 8 }
        if row.weekdayMask != nil { score += 4 }
        if row.startTime != nil || row.endTime != nil { score += 2 }
        return score
    }

    // MARK: - Tarih helper

    static func isWithin(date: String, from: String?, to: String?) -> Bool {
        if let from, date < from { return false }
        if let to, date > to { return false }
        return true
    }
}
