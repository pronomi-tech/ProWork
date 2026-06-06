//  BillingReportBuilderTests.swift
//  ProWorkTests
//  BillingReportLine listesinden müşteri/proje/todo kırılımı üretir.
//  Toplama saymalarının (saniye, dakika, tutar, KDV, total) doğruluğunu doğrular.

import XCTest
@testable import ProWork

final class BillingReportBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func line(
        customerId: String = "C1",
        customerName: String = "Müşteri A",
        projectId: String? = nil,
        projectName: String? = nil,
        todoId: String = "T1",
        todoTitle: String = "İş",
        categoryName: String? = "Geliştirme",
        serviceType: ServiceType = .remote,
        timeType: TimeType = .regular,
        actualSeconds: Int = 3600,
        billableMinutes: Int = 60,
        amountMinor: Int = 150_000,
        vatMinor: Int = 30_000,
        totalMinor: Int = 180_000,
        currency: String = "TRY",
        isBillable: Bool = true,
        isManual: Bool = false
    ) -> BillingReportLine {
        BillingReportLine(
            runId: "run1",
            sessionId: UUID().uuidString,
            todoId: todoId,
            todoTitle: todoTitle,
            projectId: projectId,
            projectName: projectName,
            customerId: customerId,
            customerName: customerName,
            categoryId: nil,
            categoryName: categoryName,
            serviceType: serviceType,
            timeType: timeType,
            actualSeconds: actualSeconds,
            billableMinutes: billableMinutes,
            amountMinor: amountMinor,
            currency: currency,
            vatMinor: vatMinor,
            totalMinor: totalMinor,
            isBillable: isBillable,
            isManual: isManual
        )
    }

    // MARK: - Summary toplamı

    func test_summary_aggregatesMonetaryFields() {
        let lines = [
            line(amountMinor: 100_000, vatMinor: 20_000, totalMinor: 120_000),
            line(amountMinor: 50_000, vatMinor: 10_000, totalMinor: 60_000)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.summary.subtotalMinor, 150_000)
        XCTAssertEqual(report.summary.vatMinor, 30_000)
        XCTAssertEqual(report.summary.totalMinor, 180_000)
        XCTAssertEqual(report.summary.lineCount, 2)
    }

    func test_summary_billableVsNonBillable_separation() {
        let lines = [
            line(actualSeconds: 3600, billableMinutes: 60, isBillable: true),
            line(actualSeconds: 1800, billableMinutes: 0, amountMinor: 0, vatMinor: 0, totalMinor: 0, isBillable: false)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.summary.totalActualSeconds, 5400)
        // Yalnızca billable satırların dakikası billable'a sayılır
        XCTAssertEqual(report.summary.billableMinutes, 60)
        // Non-billable satırın actualSeconds'ı non-billable bucket'a gider
        XCTAssertEqual(report.summary.nonBillableSeconds, 1800)
    }

    func test_summary_manualVsAutomatic_separation() {
        let lines = [
            line(actualSeconds: 3600, isManual: false),
            line(actualSeconds: 1200, isManual: true),
            line(actualSeconds: 600, isManual: true)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.summary.automaticSeconds, 3600)
        XCTAssertEqual(report.summary.manualSeconds, 1800)
        XCTAssertEqual(report.summary.manualLineCount, 2)
    }

    func test_summary_serviceTypeBuckets() {
        let lines = [
            line(serviceType: .remote, actualSeconds: 3600),
            line(serviceType: .onsite, actualSeconds: 1800),
            line(serviceType: .onsite, actualSeconds: 900)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.summary.remoteSeconds, 3600)
        XCTAssertEqual(report.summary.onsiteSeconds, 2700)
    }

    func test_summary_timeTypeBuckets() {
        let lines = [
            line(timeType: .regular, actualSeconds: 3600),
            line(timeType: .afterHours, actualSeconds: 1800),
            line(timeType: .weekend, actualSeconds: 1200),
            line(timeType: .holiday, actualSeconds: 600)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.summary.regularSeconds, 3600)
        XCTAssertEqual(report.summary.afterHoursSeconds, 1800)
        XCTAssertEqual(report.summary.weekendSeconds, 1200)
        XCTAssertEqual(report.summary.holidaySeconds, 600)
    }

    // MARK: - Müşteri filtresi

    func test_customerReport_filtersOnlyMatchingCustomer() {
        let lines = [
            line(customerId: "C1", amountMinor: 100_000, totalMinor: 120_000),
            line(customerId: "C2", amountMinor: 999_999, totalMinor: 1_199_999),
            line(customerId: "C1", amountMinor: 50_000, totalMinor: 60_000)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.summary.subtotalMinor, 150_000)
        XCTAssertEqual(report.summary.lineCount, 2)
    }

    // MARK: - Proje kırılımı

    func test_projectBreakdown_groupsByProjectId() {
        let lines = [
            line(projectId: "P1", projectName: "Alfa", amountMinor: 100_000, totalMinor: 120_000),
            line(projectId: "P1", projectName: "Alfa", amountMinor: 80_000, totalMinor: 96_000),
            line(projectId: "P2", projectName: "Beta", amountMinor: 50_000, totalMinor: 60_000)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.projectBreakdown.count, 2)
        let alfa = report.projectBreakdown.first { $0.projectId == "P1" }
        let beta = report.projectBreakdown.first { $0.projectId == "P2" }
        XCTAssertEqual(alfa?.summary.subtotalMinor, 180_000)
        XCTAssertEqual(beta?.summary.subtotalMinor, 50_000)
    }

    func test_projectBreakdown_nilProjectGroup_isLabeledAsProjesiz() {
        let lines = [
            line(projectId: nil, amountMinor: 100_000, totalMinor: 120_000)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        XCTAssertEqual(report.projectBreakdown.count, 1)
        XCTAssertNil(report.projectBreakdown[0].projectId)
    }

    func test_projectBreakdown_sortsByNameCaseInsensitive() {
        let lines = [
            line(projectId: "P1", projectName: "zeta"),
            line(projectId: "P2", projectName: "Alfa"),
            line(projectId: "P3", projectName: "beta")
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        let names = report.projectBreakdown.map { $0.projectName }
        XCTAssertEqual(names, ["Alfa", "beta", "zeta"])
    }

    // MARK: - Todo kırılımı

    func test_todoBreakdown_groupsByTodoId() {
        let lines = [
            line(projectId: "P1", projectName: "Alfa", todoId: "T1", todoTitle: "Bir", amountMinor: 100_000, totalMinor: 120_000),
            line(projectId: "P1", projectName: "Alfa", todoId: "T1", todoTitle: "Bir", amountMinor: 50_000, totalMinor: 60_000),
            line(projectId: "P1", projectName: "Alfa", todoId: "T2", todoTitle: "İki", amountMinor: 30_000, totalMinor: 36_000)
        ]
        let report = BillingReportBuilder.buildCustomerReport(
            customerId: "C1", customerName: "Müşteri A", lines: lines, currency: "TRY"
        )
        let project = report.projectBreakdown.first { $0.projectId == "P1" }!
        XCTAssertEqual(project.todoBreakdown.count, 2)
        let bir = project.todoBreakdown.first { $0.todoId == "T1" }
        XCTAssertEqual(bir?.summary.subtotalMinor, 150_000)
    }

    // MARK: - Organization report

    func test_organizationReport_groupsByCustomerAndSorts() {
        let lines = [
            line(customerId: "C1", customerName: "zeta"),
            line(customerId: "C2", customerName: "Alfa"),
            line(customerId: "C3", customerName: "beta")
        ]
        let reports = BillingReportBuilder.buildOrganizationReport(lines: lines, masterCurrency: "TRY")
        let names = reports.map { $0.customerName }
        XCTAssertEqual(names, ["Alfa", "beta", "zeta"])
    }

    func test_organizationReport_emptyLines_returnsEmpty() {
        let reports = BillingReportBuilder.buildOrganizationReport(lines: [], masterCurrency: "TRY")
        XCTAssertEqual(reports.count, 0)
    }
}
