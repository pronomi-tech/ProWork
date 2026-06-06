//  PriceListsLoader.swift
//  ProWork
//  Created by Pronomi.
//  GlobalPriceListsView and ScopedPriceListsView each
//  re-implemented the same fetch flow (list fetch + bulk rows). The
//  shared loader makes future bulk-fetch changes land in one place.

import Foundation

enum PriceListsLoader {
    struct Result {
        let lists: [PriceList]
        let rowsByListId: [String: [PriceListRow]]
    }

    /// Common load path: fetch lists scoped by `ownerType`+`ownerId`
    /// (or all global lists if `ownerType` is nil), then bulk-fetch
    /// every list's rows in one chunked SQL pass.
    static func load(
        organizationId: String,
        ownerType: PriceListOwnerType?,
        ownerId: String?,
        listRepository: PriceListRepository,
        rowRepository: PriceListRowRepository
    ) throws -> Result {
        let lists: [PriceList]
        if let ownerType {
            lists = try listRepository.fetchOwned(
                organizationId: organizationId,
                ownerType: ownerType,
                ownerId: ownerId
            )
        } else {
            lists = try listRepository.fetchAll(organizationId: organizationId)
        }
        let rowsByListId = try rowRepository.fetchAll(priceListIds: lists.map(\.id))
        return Result(lists: lists, rowsByListId: rowsByListId)
    }
}
