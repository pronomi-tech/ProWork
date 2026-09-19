import XCTest
@testable import ProWork

final class TodoHourlyRateOptionBuilderTests: XCTestCase {
    func testBuildIncludesOnlyMatchingActiveScopesAndCategory() {
        let projectList = makeList(id: "project", ownerType: .project, ownerId: "project-1")
        let otherProjectList = makeList(id: "other-project", ownerType: .project, ownerId: "project-2")
        let customerList = makeList(id: "customer", ownerType: .customer, ownerId: "customer-1")
        let globalList = makeList(id: "global", ownerType: .global)
        let inactiveList = makeList(id: "inactive", ownerType: .global, isActive: false)

        let options = TodoHourlyRateOptionBuilder.build(
            priceLists: [globalList, inactiveList, customerList, otherProjectList, projectList],
            rowsByListId: [
                "project": [makeRow(id: "project-match", listId: "project", categoryId: "category-1")],
                "other-project": [makeRow(id: "other-project-row", listId: "other-project")],
                "customer": [
                    makeRow(id: "customer-general", listId: "customer"),
                    makeRow(id: "customer-other-category", listId: "customer", categoryId: "category-2")
                ],
                "global": [makeRow(id: "global-general", listId: "global")],
                "inactive": [makeRow(id: "inactive-row", listId: "inactive")]
            ],
            customerId: "customer-1",
            projectId: "project-1",
            categoryId: "category-1",
            dateString: "2026-09-19"
        )

        XCTAssertEqual(options.map(\.id), ["project-match", "customer-general", "global-general"])
    }

    func testBuildExcludesExpiredListsAndRows() {
        let expiredList = makeList(
            id: "expired-list",
            ownerType: .global,
            validTo: "2026-09-18"
        )
        let currentList = makeList(id: "current-list", ownerType: .global)

        let options = TodoHourlyRateOptionBuilder.build(
            priceLists: [expiredList, currentList],
            rowsByListId: [
                "expired-list": [makeRow(id: "expired-list-row", listId: "expired-list")],
                "current-list": [
                    makeRow(id: "expired-row", listId: "current-list", validTo: "2026-09-18"),
                    makeRow(id: "future-row", listId: "current-list", validFrom: "2026-09-20"),
                    makeRow(id: "current-row", listId: "current-list")
                ]
            ],
            customerId: nil,
            projectId: nil,
            categoryId: nil,
            dateString: "2026-09-19"
        )

        XCTAssertEqual(options.map(\.id), ["current-row"])
    }

    private func makeList(
        id: String,
        ownerType: PriceListOwnerType,
        ownerId: String? = nil,
        isActive: Bool = true,
        validFrom: String? = nil,
        validTo: String? = nil
    ) -> PriceList {
        PriceList(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            name: id,
            isActive: isActive,
            validFrom: validFrom,
            validTo: validTo
        )
    }

    private func makeRow(
        id: String,
        listId: String,
        categoryId: String? = nil,
        validFrom: String? = nil,
        validTo: String? = nil
    ) -> PriceListRow {
        PriceListRow(
            id: id,
            priceListId: listId,
            serviceType: .remote,
            categoryId: categoryId,
            unitPriceMinor: 100_000,
            validFrom: validFrom,
            validTo: validTo
        )
    }
}
