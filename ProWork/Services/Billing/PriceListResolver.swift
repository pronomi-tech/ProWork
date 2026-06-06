//  PriceListResolver.swift
//  ProWork
//  Created by Pronomi.
//  Spec §3 — Price priority order:
//      1. If a task-specific price / override exists, use it (TodoBillingOverride)
//      2. Otherwise, use a project-specific price list if present
//      3. Otherwise, use a customer-specific price list if present
//      4. Otherwise, fall back to the global default price list
//  Resolves the correct `PriceListRow` for a session + segment.

import Foundation

/// Resolution result.
enum PriceResolution: Hashable {
    /// A price row was found — computed from the hourly rate.
    case row(PriceListRow, ownerType: PriceListOwnerType)
    /// The todo has a `unitPrice` override — replaces the price row.
    case todoUnitPriceOverride(unitPriceMinor: Int, currency: String)
    /// The todo has a fixed-fee override — this amount regardless of duration.
    case todoFixedFee(amountMinor: Int, currency: String)
    /// No matching price found.
    case noMatch
}

/// Input grouping the resolution sources.
struct PriceResolutionContext {
    var todoOverride: TodoBillingOverride?
    var projectPriceLists: [PriceList]    // Active project-owned lists
    var customerPriceLists: [PriceList]   // Active customer-owned lists
    var globalPriceLists: [PriceList]     // Active global lists
    var customerDefaultPriceListId: String?
    var organizationCurrency: String
    /// List ID → active rows belonging to that list.
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

/// Currency resolver for customers/projects.
///
/// Note: — this type exposes **both** instance methods
///   (`resolveCustomerCurrency(_:)`, `resolveProjectCurrency(_:)`)
///   and static counterparts (`PricingCurrencyResolver.resolveCustomerCurrency(...)`
///   below). The static variants short-circuit when the caller already
///   has the relevant repositories loaded (e.g. billing computation
///   batches); the instance variants are the canonical API for ViewModels
///   that go through `AppServices.pricingCurrencyResolver`. Both surfaces
///   exist intentionally but DO NOT drift independently — every behaviour
///   change MUST update both. New API additions should land on the
///   instance side and only be lifted to a static helper when a
///   stateless caller actually needs it.
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
        let organizationCurrency = try organizationRepository.fetch(id: organizationId)?.masterCurrency ?? BillingDefaults.fallbackCurrency
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
        let organizationCurrency = try organizationRepository.fetch(id: organizationId)?.masterCurrency ?? BillingDefaults.fallbackCurrency
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

    /// `preferredEffectiveCurrency` and `preferredCustomerLevel` both
    /// implement the "if the customer has a `defaultPriceListId`, find
    /// the matching entry in the customer + global lists" logic
    /// separately. They aren't merged into a shared helper
    /// (`preferredPriceList(in:matching:)`) because the two sides need
    /// different side checks (currency needs an `isWithin` date check,
    /// level needs the owner of the chosen list). The logical pairing
    /// is documented here so the two stay in sync as either changes.
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
    /// Returns a single price row / override per §3 priority.
    /// - Parameters:
    ///   - context: Every potential source (caller pre-fetches them from the DB).
    ///   - serviceType: Requested service type (remote/onsite).
    ///   - timeType: Requested time type (regular/afterHours/weekend/holiday).
    ///   - categoryId: Requested category (nil = no category filter).
    ///   - weekday: Which weekday (weekdayMask filter).
    ///   - timeOfDay: Which hour (startTime/endTime filter).
    ///   - dateString: "yyyy-MM-dd" — for the price row's validFrom/validTo range.
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

        // 2-4. List levels (project → customer → global)
        // (DRY): the "exclude the preferred default" filter
        // was inlined twice with the same predicate. Extract a single
        // helper so adding a new level can't drift.
        let preferredId = context.customerDefaultPriceListId
        let levels: [(lists: [PriceList], owner: PriceListOwnerType)] = [
            (context.projectPriceLists, .project),
            preferredCustomerLevel(from: context),
            (excludingPreferredId(context.customerPriceLists, preferredId: preferredId), .customer),
            (excludingPreferredId(context.globalPriceLists, preferredId: preferredId), .global)
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

    /// DRY helper for the "exclude the preferred customer-default list at
    /// this level so we don't try it twice" filter.
    private static func excludingPreferredId(
        _ lists: [PriceList],
        preferredId: String?
    ) -> [PriceList] {
        guard let preferredId else { return lists }
        return lists.filter { $0.id != preferredId }
    }

    // MARK: - Find the best row within a list level

    /// The fallback outer loop runs over `timeType`, the inner loop runs
    /// over `activeLists`. Preserving the **list order** for the same
    /// timeType, we first scan the most specific bucket (holiday) across
    /// every list, then fall back to the next general bucket (weekend).
    /// This ordering produces the behaviour
    /// "if both a customer-specific list and a global list are applicable,
    /// customer-specific holiday → global holiday → customer-specific
    /// weekend → global weekend …"; since the caller orders `lists` by
    /// this priority, the intuitive result is returned.
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
        // Scan active lists — keep those within the validity date range
        let activeLists = lists.filter {
            $0.isActive && $0.deletedAt == nil &&
            isWithin(date: dateString, from: $0.validFrom, to: $0.validTo)
        }

        // TimeType fallback (holiday → weekend → afterHours → regular)
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

    /// Picks the most specific matching row from the rows in a list.
    /// Scoring: category match > weekdayMask specificity > time-range specificity.
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

            // Category filter: if row.categoryId is nil it applies to every category
            if let rowCat = row.categoryId, rowCat != categoryId { return false }

            // Weekday mask
            if !row.appliesTo(weekday: weekday) { return false }

            // Time range
            if let start = row.startTime, timeOfDay < start { return false }
            if let end = row.endTime, timeOfDay >= end { return false }

            // Validity date
            if !isWithin(date: dateString, from: row.validFrom, to: row.validTo) {
                return false
            }

            return true
        }

        // Pick the most specific row — on ties, the lower sortOrder wins
        let sorted = candidates.sorted { lhs, rhs in
            let lhsScore = specificity(lhs, categoryId: categoryId)
            let rhsScore = specificity(rhs, categoryId: categoryId)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.sortOrder < rhs.sortOrder
        }
        return sorted.first
    }

    /// Higher score = more specific match.
    private static func specificity(_ row: PriceListRow, categoryId: String?) -> Int {
        var score = 0
        if let rowCat = row.categoryId, rowCat == categoryId { score += 8 }
        if row.weekdayMask != nil { score += 4 }
        if row.startTime != nil || row.endTime != nil { score += 2 }
        return score
    }

    // MARK: - Tarih helper

    /// Previously this used plain `<` / `>` on String, which
    /// is technically correct for ISO 8601 "yyyy-MM-dd" because that format
    /// is lexicographically sortable. The hazard is silent — a future change
    /// to the persisted format (e.g. switching to localized "dd.MM.yyyy")
    /// would compile fine but produce nonsense comparisons. Lock the contract
    /// behind a precondition so a malformed input fails loudly in DEBUG.
    static func isWithin(date: String, from: String?, to: String?) -> Bool {
        assert(isIsoDay(date), "isWithin expects yyyy-MM-dd; got \(date)")
        if let from {
            assert(isIsoDay(from), "isWithin lower bound expects yyyy-MM-dd; got \(from)")
            if date < from { return false }
        }
        if let to {
            assert(isIsoDay(to), "isWithin upper bound expects yyyy-MM-dd; got \(to)")
            if date > to { return false }
        }
        return true
    }

    /// Cheap "looks like yyyy-MM-dd" check — does not validate calendar
    /// semantics, just shape. Reused by `isWithin` for debug assertions.
    private static func isIsoDay(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let chars = Array(value)
        guard chars[4] == "-" && chars[7] == "-" else { return false }
        return chars.indices.allSatisfy { idx in
            idx == 4 || idx == 7 ? true : chars[idx].isNumber
        }
    }
}
