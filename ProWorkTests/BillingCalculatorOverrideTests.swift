//
//  BillingCalculatorOverrideTests.swift
//  ProWorkTests
//
//  TodoBillingOverride akışları: fixedFee ve unitPriceOverride senaryoları.
//

import XCTest
@testable import ProWork

final class BillingCalculatorOverrideTests: XCTestCase {

    private let calendar = TimeWindowSplitter.istanbulCalendar

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = mi
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return calendar.date(from: c)!
    }

    private func standardRule() -> BillingRule {
        let workHours = DailyWorkHours(
            start: TimeOfDay(hour: 9, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0)
        )
        return BillingRule(
            scope: .global,
            weekdayHours: [
                .monday: workHours, .tuesday: workHours, .wednesday: workHours,
                .thursday: workHours, .friday: workHours
            ],
            weekendDays: [.saturday, .sunday]
        )
    }

    // MARK: - Fixed fee override

    func test_fixedFeeOverride_producesSingleLine_regardlessOfDuration() {
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 12, 30) // 150 dk gerçek süre

        let category = TaskCategory(id: "dev", name: "Geliştirme")
        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60)
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "Sabit ücretli iş", isBillable: true)
        let session = TodoTimeSession(
            todoId: todo.id, startedAt: start, endedAt: end,
            durationSeconds: Int(end.timeIntervalSince(start))
        )

        let override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .fixedFee,
            fixedFeeMinor: 1_000_000, // 10.000,00 TRY
            currency: "TRY"
        )

        let context = PriceResolutionContext(
            todoOverride: override,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: [:]
        )

        let vat = VATCalculator(rates: [VatRate(id: "std", name: "Std", rate: Decimal(string: "0.20")!, isDefault: true)])

        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: category,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        XCTAssertEqual(output.lines.count, 1)
        let line = output.lines[0]
        XCTAssertTrue(line.isFixedFee)
        XCTAssertEqual(line.amountMinor, 1_000_000)
        XCTAssertEqual(line.fixedFeeMinor, 1_000_000)
        XCTAssertEqual(line.billableMinutes, 0, "Sabit fee'de billableMinutes 0 olmalı")
        XCTAssertEqual(line.unitPriceMinor, 0)
        XCTAssertEqual(line.currency, "TRY")
        // %20 KDV → 200_000
        XCTAssertEqual(line.vatMinor, 200_000)
        XCTAssertEqual(line.totalMinor, 1_200_000)
        XCTAssertEqual(output.subtotalMinor, 1_000_000)
        XCTAssertEqual(output.totalMinor, 1_200_000)
    }

    func test_fixedFeeOverride_usesOverrideCurrency_notListCurrency() {
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 11, 0)

        let customer = Customer(id: "C1", name: "ABC")
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "EUR'da sabit fee", isBillable: true)
        let session = TodoTimeSession(
            todoId: todo.id, startedAt: start, endedAt: end,
            durationSeconds: 3600
        )

        let override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .fixedFee,
            fixedFeeMinor: 50_000, // 500,00 EUR
            currency: "EUR"
        )

        // Liste TRY'de ama override EUR — override kazanmalı
        let list = PriceList(id: "L", ownerType: .global, name: "Genel", currency: "TRY")
        let row = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 999_999)

        let context = PriceResolutionContext(
            todoOverride: override,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [list],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [row]]
        )

        let vat = VATCalculator(rates: [])
        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: nil,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        XCTAssertEqual(output.lines.count, 1)
        XCTAssertEqual(output.currency, "EUR")
        XCTAssertEqual(output.lines[0].currency, "EUR")
        XCTAssertEqual(output.lines[0].amountMinor, 50_000)
    }

    func test_fixedFeeOverride_nonBillableTodo_yieldsZeroAmount() {
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 11, 0)

        let category = TaskCategory(id: "admin", name: "İdari", isBillableDefault: false)
        let customer = Customer(id: "C1", name: "ABC")
        let todo = Todo(customerId: "C1", categoryId: "admin", title: "İdari", isBillable: false)
        let session = TodoTimeSession(todoId: todo.id, startedAt: start, endedAt: end, durationSeconds: 3600)

        let override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .fixedFee,
            fixedFeeMinor: 100_000,
            currency: "TRY"
        )

        let context = PriceResolutionContext(
            todoOverride: override,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: [:]
        )
        let vat = VATCalculator(rates: [VatRate(id: "std", name: "Std", rate: Decimal(string: "0.20")!, isDefault: true)])

        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: category,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        XCTAssertEqual(output.lines.count, 1)
        XCTAssertEqual(output.lines[0].amountMinor, 0)
        XCTAssertEqual(output.lines[0].vatMinor, 0)
        XCTAssertFalse(output.lines[0].isBillable)
        // Fixed fee bayrağı kalır — snapshot için
        XCTAssertTrue(output.lines[0].isFixedFee)
    }

    func test_fixedFeeOverride_softDeleted_isIgnored() {
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 11, 0)

        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60)
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(todoId: todo.id, startedAt: start, endedAt: end, durationSeconds: 3600)

        var override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .fixedFee,
            fixedFeeMinor: 99_999_999,
            currency: "TRY"
        )
        override.deletedAt = Date() // soft delete

        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "M", currency: "TRY")
        let row = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 100_000)

        let context = PriceResolutionContext(
            todoOverride: override,
            projectPriceLists: [],
            customerPriceLists: [list],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [row]]
        )

        let vat = VATCalculator(rates: [VatRate(id: "zero", name: "0", rate: 0, isDefault: true)])
        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: nil,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        // Override yokmuş gibi davranır → liste satırından fiyat alır
        XCTAssertFalse(output.lines.allSatisfy { $0.isFixedFee })
        XCTAssertEqual(output.lines[0].unitPriceMinor, 100_000)
        XCTAssertEqual(output.lines[0].amountMinor, 100_000)
    }

    // MARK: - Unit price override

    func test_unitPriceOverride_replacesListPrice() {
        // 1 saatlik mesai içi iş; liste 100_000 TRY/saat, override 250_000 TRY/saat
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 11, 0)

        let category = TaskCategory(id: "dev", name: "Geliştirme")
        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60)
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(todoId: todo.id, startedAt: start, endedAt: end, durationSeconds: 3600)

        let override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .unitPrice,
            unitPriceMinor: 250_000,
            currency: "TRY"
        )

        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "M", currency: "TRY")
        let row = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 100_000)

        let context = PriceResolutionContext(
            todoOverride: override,
            projectPriceLists: [],
            customerPriceLists: [list],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [row]]
        )

        let vat = VATCalculator(rates: [VatRate(id: "std", name: "Std", rate: Decimal(string: "0.20")!, isDefault: true)])
        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: category,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        XCTAssertEqual(output.lines.count, 1)
        XCTAssertEqual(output.lines[0].unitPriceMinor, 250_000, "Liste fiyatı değil override kullanılmalı")
        XCTAssertEqual(output.lines[0].amountMinor, 250_000, "60 dk × 250_000/saat = 250_000")
        XCTAssertFalse(output.lines[0].isFixedFee)
        // %20 KDV
        XCTAssertEqual(output.lines[0].vatMinor, 50_000)
        XCTAssertEqual(output.lines[0].totalMinor, 300_000)
    }

    func test_unitPriceOverride_appliesPerSegment_acrossTimeTypes() {
        // 17:30–18:30 → 30 dk regular + 30 dk afterHours; override saatlik = 100_000
        let start = date(2026, 5, 7, 17, 30)
        let end = date(2026, 5, 7, 18, 30)

        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60)
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(todoId: todo.id, startedAt: start, endedAt: end, durationSeconds: 3600)

        let override = TodoBillingOverride(
            todoId: todo.id,
            overrideType: .unitPrice,
            unitPriceMinor: 100_000,
            currency: "TRY"
        )

        // Liste hem regular hem afterHours satırı içeriyor — override hepsini ezsin
        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "M", currency: "TRY")
        let reg = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 999)
        let aft = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .afterHours, unitPriceMinor: 999)

        let context = PriceResolutionContext(
            todoOverride: override,
            projectPriceLists: [],
            customerPriceLists: [list],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [reg, aft]]
        )

        let vat = VATCalculator(rates: [VatRate(id: "zero", name: "0", rate: 0, isDefault: true)])
        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: nil,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        // Override saatlik 100_000 → 60 dk toplamda 100_000
        XCTAssertEqual(output.subtotalMinor, 100_000)
        XCTAssertGreaterThanOrEqual(output.lines.count, 2)
        for line in output.lines {
            XCTAssertEqual(line.unitPriceMinor, 100_000)
        }
    }
}
