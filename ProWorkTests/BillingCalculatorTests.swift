//
//  BillingCalculatorTests.swift
//  ProWorkTests
//
//  Spec §8 — Uçtan uca senaryolar.
//

import XCTest
@testable import ProWork

final class BillingCalculatorTests: XCTestCase {

    private let calendar = TimeWindowSplitter.istanbulCalendar

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var components = DateComponents()
        components.year = y; components.month = m; components.day = d
        components.hour = h; components.minute = mi; components.second = s
        components.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return calendar.date(from: components)!
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

    // MARK: - Senaryo 1: Tek mesai içi, 10 dk çalışma, 60 dk pencere → 60 dk billable

    func test_simpleRegularSession_with10MinutesAnd60MinWindow_billsOneFullHour() {
        // 7 Mayıs 2026 Perşembe 10:00–10:10
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 10, 10)

        let category = TaskCategory(id: "dev", name: "Geliştirme", isBillableDefault: true)
        let customer = Customer(
            id: "C1", name: "ABC",
            defaultServiceType: "remote",
            defaultMinBillingMinutes: 60
        )
        let todo = Todo(
            customerId: "C1", categoryId: "dev",
            title: "Test todo", isBillable: true
        )
        let session = TodoTimeSession(
            todoId: todo.id,
            startedAt: start,
            endedAt: end,
            durationSeconds: Int(end.timeIntervalSince(start)),
            isManual: false
        )

        let priceList = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "C1 Listesi", currency: "TRY")
        let row = PriceListRow(
            priceListId: "L",
            serviceType: .remote,
            timeType: .regular,
            unitPriceMinor: 150_000  // 1.500,00 TRY/saat
        )

        let priceContext = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [priceList],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [row]]
        )

        let vat = VATCalculator(rates: [VatRate(id: "std", name: "Std", rate: Decimal(string: "0.20")!, isDefault: true)])

        let input = BillingCalculationInput(
            session: session, todo: todo, customer: customer,
            project: nil, category: category,
            rule: standardRule(), holidays: [],
            priceContext: priceContext, vatCalculator: vat
        )

        let output = BillingCalculator.calculate(input: input, runId: "run1")

        XCTAssertEqual(output.lines.count, 1)
        let line = output.lines[0]
        XCTAssertEqual(line.timeType, .regular)
        XCTAssertEqual(line.billableMinutes, 60)
        XCTAssertEqual(line.unitPriceMinor, 150_000)
        // 150_000 * 60 / 60 = 150_000
        XCTAssertEqual(line.amountMinor, 150_000)
        // %20 KDV → 30_000
        XCTAssertEqual(line.vatMinor, 30_000)
        XCTAssertEqual(line.totalMinor, 180_000)
    }

    // MARK: - Senaryo 2: Mesai içi → mesai dışı geçiş (yeni algoritma — pencere session seviyesinde)

    /// Spec §4 + §5: 17:30–19:15 (105 dk gerçek), pencere 60 dk
    /// N = ceil(105/60) = 2 pencere → billable 120 dk → [17:30–19:30]
    /// Bu aralıkta zaman tipi dağılımı:
    ///   - 17:30–18:00 (30 dk) regular  → 30 * 100_000 / 60 = 50_000
    ///   - 18:00–19:30 (90 dk) afterHours → 90 * 200_000 / 60 = 300_000
    /// Toplam: 350_000
    func test_crossingWorkEnd_appliesWindowFirstThenSplitsByTimeType() {
        let start = date(2026, 5, 7, 17, 30)
        let end = date(2026, 5, 7, 19, 15)

        let category = TaskCategory(id: "dev", name: "Geliştirme")
        let customer = Customer(
            id: "C1", name: "ABC",
            defaultMinBillingMinutes: 60
        )
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(
            todoId: todo.id, startedAt: start, endedAt: end,
            durationSeconds: Int(end.timeIntervalSince(start)), isManual: false
        )

        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "X", currency: "TRY")
        let regular = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 100_000)
        let after = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .afterHours, unitPriceMinor: 200_000)

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [list],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [regular, after]]
        )

        let vat = VATCalculator(rates: [VatRate(id: "zero", name: "0", rate: 0, isDefault: true)])

        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: category,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        XCTAssertEqual(output.lines.count, 2)

        // Segment 1: 17:30–18:00 = 30 dk regular
        XCTAssertEqual(output.lines[0].timeType, .regular)
        XCTAssertEqual(output.lines[0].billableMinutes, 30)
        XCTAssertEqual(output.lines[0].amountMinor, 50_000)

        // Segment 2: 18:00–19:30 = 90 dk afterHours
        XCTAssertEqual(output.lines[1].timeType, .afterHours)
        XCTAssertEqual(output.lines[1].billableMinutes, 90)
        XCTAssertEqual(output.lines[1].amountMinor, 300_000)

        XCTAssertEqual(output.subtotalMinor, 350_000)
    }

    // MARK: - Senaryo 4: Kullanıcı raporlu bug — 1 saatlik kayıt mesai sınırını geçince
    /// 08:45–09:45 (60 dk), mesai 09:00, pencere 60 dk
    /// N = ceil(60/60) = 1 pencere → billable 60 dk → [08:45–09:45]
    ///   - 08:45–09:00 (15 dk) afterHours  → 15 * 280_000/60 = 70_000
    ///   - 09:00–09:45 (45 dk) regular     → 45 * 220_000/60 = 165_000
    /// Toplam: 235_000 (eski algoritmada 500_000 hatalı çıkıyordu)
    func test_oneHourCrossingWorkStart_doesNotDoublyApplyWindow() {
        let start = date(2026, 5, 7, 8, 45)
        let end = date(2026, 5, 7, 9, 45)

        let category = TaskCategory(id: "dev", name: "Geliştirme")
        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60)
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(
            todoId: todo.id, startedAt: start, endedAt: end,
            durationSeconds: 3600, isManual: true
        )

        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "X", currency: "TRY")
        let regular = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 220_000)
        let after = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .afterHours, unitPriceMinor: 280_000)

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [list],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [regular, after]]
        )
        let vat = VATCalculator(rates: [VatRate(id: "zero", name: "0", rate: 0, isDefault: true)])

        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: category,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        // 2 satır: 15 dk afterHours, 45 dk regular
        XCTAssertEqual(output.lines.count, 2)
        XCTAssertEqual(output.lines[0].timeType, .afterHours)
        XCTAssertEqual(output.lines[0].billableMinutes, 15)
        XCTAssertEqual(output.lines[0].amountMinor, 70_000)
        XCTAssertEqual(output.lines[1].timeType, .regular)
        XCTAssertEqual(output.lines[1].billableMinutes, 45)
        XCTAssertEqual(output.lines[1].amountMinor, 165_000)
        XCTAssertEqual(output.subtotalMinor, 235_000)
    }

    func test_secondPrecisionBoundarySplit_preservesSingleWindowTotal() {
        let start = date(2026, 5, 8, 17, 48, 8)
        let end = date(2026, 5, 8, 18, 48, 8)

        let category = TaskCategory(id: "dev", name: "Geliştirme")
        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60)
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(
            todoId: todo.id,
            startedAt: start,
            endedAt: end,
            durationSeconds: 3600,
            isManual: true
        )

        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "X", currency: "TRY")
        let regular = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 220_000)
        let after = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .afterHours, unitPriceMinor: 280_000)

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [list],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [regular, after]]
        )
        let vat = VATCalculator(rates: [VatRate(id: "zero", name: "0", rate: 0, isDefault: true)])

        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: category,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        XCTAssertEqual(output.lines.count, 2)
        XCTAssertEqual(output.lines[0].timeType, .regular)
        XCTAssertEqual(output.lines[0].billableMinutes, 12)
        XCTAssertEqual(output.lines[0].amountMinor, 44_000)
        XCTAssertEqual(output.lines[1].timeType, .afterHours)
        XCTAssertEqual(output.lines[1].billableMinutes, 48)
        XCTAssertEqual(output.lines[1].amountMinor, 224_000)
        XCTAssertEqual(output.lines.reduce(0) { $0 + $1.billableMinutes }, 60)
        XCTAssertEqual(output.subtotalMinor, 268_000)
    }

    // MARK: - Senaryo 3: Faturalandırılamaz todo → tutar 0

    func test_nonBillableTodo_producesZeroAmountLine() {
        let start = date(2026, 5, 7, 10, 0)
        let end = date(2026, 5, 7, 11, 0)

        let category = TaskCategory(id: "admin", name: "İdari", isBillableDefault: false)
        let customer = Customer(id: "C1", name: "ABC")
        let todo = Todo(customerId: "C1", categoryId: "admin", title: "İdari iş", isBillable: false)
        let session = TodoTimeSession(
            todoId: todo.id, startedAt: start, endedAt: end,
            durationSeconds: Int(end.timeIntervalSince(start))
        )

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: [:]
        )

        let vat = VATCalculator(rates: [])

        let output = BillingCalculator.calculate(
            input: BillingCalculationInput(
                session: session, todo: todo, customer: customer,
                project: nil, category: category,
                rule: standardRule(), holidays: [],
                priceContext: context, vatCalculator: vat
            ),
            runId: "run1"
        )

        XCTAssertEqual(output.subtotalMinor, 0)
        XCTAssertEqual(output.vatMinor, 0)
        for line in output.lines {
            XCTAssertFalse(line.isBillable)
            XCTAssertEqual(line.amountMinor, 0)
        }
    }
}
