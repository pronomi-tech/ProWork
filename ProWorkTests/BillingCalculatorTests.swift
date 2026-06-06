//  BillingCalculatorTests.swift
//  ProWorkTests
//  Spec §8 — Uçtan uca senaryolar.

import XCTest
@testable import ProWork

final class BillingCalculatorTests: XCTestCase {

    private let calendar = BillingFixtures.calendar

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        BillingFixtures.date(y, m, d, h, mi, s)
    }

    private func standardRule() -> BillingRule {
        BillingFixtures.standardRule()
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

    // MARK: - K2 regression: KDV oturum bazında tek seferlik hesaplanmalı

    /// Eski algoritma her segmente ayrı `subtotal × rate` + banker's round
    /// uyguladığı için çok-segmentli oturumlarda ±1-3 minor drift oluşuyordu.
    /// Yeni algoritma:
    ///   1. Tüm satır amount'larını üret.
    ///   2. KDV'yi `sum(amount) × rate` üzerinden tek kez banker's round et.
    ///   3. Toplam KDV'yi satırlara largest-remainder ile dağıt (sum invariant).
    /// Senaryo: 17:30–18:30 (mesai sınırını geçen 60 dk), saatlik ücret 60 minor,
    ///          KDV %18. İki eşit segment → amount [30, 30].
    ///   - Eski (per-segment): 30 × 0.18 = 5.4 → 5; 5 + 5 = 10
    ///   - Yeni (aggregate):  60 × 0.18 = 10.8 → 11; dağıtım [6, 5]
    /// Beklenen output.vatMinor = 11, satır toplamı = 11 (drift sıfır).
    func test_K2_vatComputedOnAggregate_notPerSegment() {
        let start = date(2026, 5, 7, 17, 30)
        let end = date(2026, 5, 7, 18, 30)

        let category = TaskCategory(id: "dev", name: "Geliştirme")
        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60)
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(
            todoId: todo.id, startedAt: start, endedAt: end,
            durationSeconds: Int(end.timeIntervalSince(start)), isManual: false
        )

        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "X", currency: "TRY")
        let regular = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 60)
        let after = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .afterHours, unitPriceMinor: 60)

        let context = PriceResolutionContext(
            todoOverride: nil,
            projectPriceLists: [],
            customerPriceLists: [list],
            globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [regular, after]]
        )
        let vat = VATCalculator(rates: [
            VatRate(id: "v18", name: "18", rate: Decimal(string: "0.18")!, isDefault: true)
        ])

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
        XCTAssertEqual(output.lines[0].amountMinor, 30)
        XCTAssertEqual(output.lines[1].amountMinor, 30)
        XCTAssertEqual(output.subtotalMinor, 60)

        // K2: aggregate KDV (eski: 10, yeni: 11)
        XCTAssertEqual(output.vatMinor, 11,
                       "KDV toplam üzerinden tek banker's round olmalı; segment bazlı 10 olurdu")
        // Largest-remainder dağıtımı: weights [30,30], total 11 → [6, 5]
        XCTAssertEqual(output.lines[0].vatMinor, 6)
        XCTAssertEqual(output.lines[1].vatMinor, 5)

        // Sum invariant
        XCTAssertEqual(output.lines.reduce(0) { $0 + $1.vatMinor }, output.vatMinor)
        XCTAssertEqual(output.lines.reduce(0) { $0 + $1.totalMinor },
                       output.subtotalMinor + output.vatMinor)

        // Rate her satırda eşit
        XCTAssertTrue(output.lines.allSatisfy { $0.vatRate == Decimal(string: "0.18")! })
    }

    /// Muafiyet (isExempt) tüm satırlara yansımalı; VAT toplamı 0.
    func test_K2_exemptRate_appliesToAllLines() {
        let start = date(2026, 5, 7, 17, 30)
        let end = date(2026, 5, 7, 18, 30)
        let category = TaskCategory(id: "dev", name: "Geliştirme")
        let customer = Customer(id: "C1", name: "ABC", defaultMinBillingMinutes: 60, vatRateId: "muaf")
        let todo = Todo(customerId: "C1", categoryId: "dev", title: "X", isBillable: true)
        let session = TodoTimeSession(
            todoId: todo.id, startedAt: start, endedAt: end,
            durationSeconds: Int(end.timeIntervalSince(start))
        )
        let list = PriceList(id: "L", ownerType: .customer, ownerId: "C1", name: "X", currency: "TRY")
        let regular = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .regular, unitPriceMinor: 60_000)
        let after = PriceListRow(priceListId: "L", serviceType: .remote, timeType: .afterHours, unitPriceMinor: 60_000)
        let context = PriceResolutionContext(
            todoOverride: nil, projectPriceLists: [],
            customerPriceLists: [list], globalPriceLists: [],
            organizationCurrency: "TRY",
            rowsByListId: ["L": [regular, after]]
        )
        let vat = VATCalculator(rates: [
            VatRate(id: "std", name: "Std", rate: Decimal(string: "0.20")!, isDefault: true),
            VatRate(id: "muaf", name: "Muaf", rate: 0, isExempt: true)
        ])

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
        XCTAssertEqual(output.vatMinor, 0)
        XCTAssertTrue(output.lines.allSatisfy { $0.vatMinor == 0 })
        XCTAssertTrue(output.lines.allSatisfy { $0.isVatExempt })
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
