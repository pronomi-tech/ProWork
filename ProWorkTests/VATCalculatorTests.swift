//  VATCalculatorTests.swift
//  ProWorkTests
//  Adlandırılmış VatRate çözümü:
//    project > customer > category > default; isExempt → %0 + "Muaf".

import XCTest
@testable import ProWork

final class VATCalculatorTests: XCTestCase {

    private func rate(_ id: String, _ value: String, isDefault: Bool = false, isExempt: Bool = false) -> VatRate {
        VatRate(
            id: id,
            name: id,
            rate: Decimal(string: value)!,
            isDefault: isDefault,
            isExempt: isExempt
        )
    }

    func test_default_appliesWhenNoAssignment() {
        let calc = VATCalculator(rates: [rate("std", "0.20", isDefault: true)])
        let result = calc.calculate(
            subtotalMinor: 100_000,
            customerVatRateId: nil,
            projectVatRateId: nil,
            categoryVatRateId: nil,
            dateString: ""
        )
        XCTAssertEqual(result.vatMinor, 20_000)
        XCTAssertEqual(result.totalMinor, 120_000)
        XCTAssertFalse(result.isExempt)
        XCTAssertEqual(result.origin, .default)
    }

    func test_categoryRate_overridesDefault() {
        let calc = VATCalculator(rates: [
            rate("std", "0.20", isDefault: true),
            rate("edu", "0.10")
        ])
        let result = calc.calculate(
            subtotalMinor: 100_000,
            customerVatRateId: nil,
            projectVatRateId: nil,
            categoryVatRateId: "edu",
            dateString: ""
        )
        XCTAssertEqual(result.vatMinor, 10_000)
        XCTAssertEqual(result.origin, .category)
    }

    func test_customerRate_overridesCategory() {
        let calc = VATCalculator(rates: [
            rate("std", "0.20", isDefault: true),
            rate("edu", "0.10"),
            rate("cust", "0.18")
        ])
        let result = calc.calculate(
            subtotalMinor: 100_000,
            customerVatRateId: "cust",
            projectVatRateId: nil,
            categoryVatRateId: "edu",
            dateString: ""
        )
        XCTAssertEqual(result.vatMinor, 18_000)
        XCTAssertEqual(result.origin, .customer)
    }

    func test_projectRate_overridesCustomer() {
        let calc = VATCalculator(rates: [
            rate("std", "0.20", isDefault: true),
            rate("cust", "0.18"),
            rate("proj", "0.08")
        ])
        let result = calc.calculate(
            subtotalMinor: 100_000,
            customerVatRateId: "cust",
            projectVatRateId: "proj",
            categoryVatRateId: nil,
            dateString: ""
        )
        XCTAssertEqual(result.vatMinor, 8_000)
        XCTAssertEqual(result.origin, .project)
    }

    func test_exemptRate_yieldsZeroAndExemptFlag() {
        let exempt = rate("muaf", "0", isExempt: true)
        let calc = VATCalculator(rates: [
            rate("std", "0.20", isDefault: true),
            exempt
        ])
        let result = calc.calculate(
            subtotalMinor: 100_000,
            customerVatRateId: "muaf",
            projectVatRateId: nil,
            categoryVatRateId: nil,
            dateString: ""
        )
        XCTAssertEqual(result.vatMinor, 0)
        XCTAssertEqual(result.totalMinor, 100_000)
        XCTAssertTrue(result.isExempt)
        XCTAssertEqual(result.origin, .customer)
    }

    func test_noDefault_yieldsZeroVat() {
        let calc = VATCalculator(rates: [])
        let result = calc.calculate(
            subtotalMinor: 100_000,
            customerVatRateId: nil,
            projectVatRateId: nil,
            categoryVatRateId: nil,
            dateString: ""
        )
        XCTAssertEqual(result.vatMinor, 0)
        XCTAssertEqual(result.origin, .none)
    }
}
