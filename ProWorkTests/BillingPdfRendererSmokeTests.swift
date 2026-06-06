//  BillingPdfRendererSmokeTests.swift
//  ProWorkTests
//  Smoke test added after the code-review pass. Renders a small but
//  representative BillingRunBundle through BillingPdfRenderer and
//  confirms the output is a syntactically valid PDF with at least one
//  page. Does NOT assert visual correctness — that still needs human
//  review — but catches obvious regressions like context-creation
//  failure, MainActor crashes, or empty-data returns.

import XCTest
@testable import ProWork

final class BillingPdfRendererSmokeTests: XCTestCase {

    func test_billingPdfRenderer_producesValidPDFForMinimalBundle() async throws {
        let bundle = Self.makeBundle()
        let renderer = BillingPdfRenderer()
        let data = try await renderer.render(bundle: bundle)

        XCTAssertGreaterThan(data.count, 1000, "Even a 1-line invoice PDF should be >1KB once headers/footers render.")
        XCTAssertTrue(Self.startsWithPDFMagicBytes(data), "Renderer output is not a PDF (missing %PDF header).")
        XCTAssertTrue(Self.endsWithEOFMarker(data), "Renderer output is missing the %%EOF marker.")
    }

    func test_billingPdfRenderer_handlesEmptyLineList() async throws {
        var bundle = Self.makeBundle()
        bundle.lines = []
        let renderer = BillingPdfRenderer()
        let data = try await renderer.render(bundle: bundle)

        XCTAssertGreaterThan(data.count, 500, "Empty-line PDF should still emit a header page.")
        XCTAssertTrue(Self.startsWithPDFMagicBytes(data))
    }

    func test_billingPdfRenderer_handlesMultiLineBundle() async throws {
        var bundle = Self.makeBundle()
        // 25 lines exercises the pagination path.
        bundle.lines = (1...25).map { Self.makeLine(runId: bundle.run.id, index: $0) }
        // Update totals so the summary numbers match what the lines say.
        bundle.run.subtotalMinor = bundle.lines.reduce(0) { $0 + $1.amountMinor }
        bundle.run.vatMinor = bundle.lines.reduce(0) { $0 + $1.vatMinor }
        bundle.run.totalMinor = bundle.run.subtotalMinor + bundle.run.vatMinor

        let renderer = BillingPdfRenderer()
        let data = try await renderer.render(bundle: bundle)
        XCTAssertGreaterThan(data.count, 5000, "25-line PDF should be multiple KB.")
        XCTAssertTrue(Self.startsWithPDFMagicBytes(data))
    }

    // MARK: - Helpers

    private static func makeBundle() -> BillingRunBundle {
        let run = BillingReportRun(
            id: "smoke-run-1",
            customerId: "smoke-customer-1",
            periodStart: "2026-05-01",
            periodEnd: "2026-05-31",
            status: .final,
            title: "Smoke Test Run",
            invoiceNumber: "SMOKE-001",
            documentNumber: "HD-2026-000001",
            currency: "TRY",
            subtotalMinor: 100_000,
            vatMinor: 20_000,
            totalMinor: 120_000,
            finalizedAt: Date()
        )
        let customer = Customer(
            id: "smoke-customer-1",
            name: "Acme A.Ş.",
            code: "ACME",
            isActive: true,
            defaultServiceType: "remote",
            defaultMinBillingMinutes: 60,
            meta: RecordMetadata.new()
        )
        let companyProfile = CompanyProfile(
            id: "smoke-company",
            legalName: "Smoke Ltd.",
            paymentTermsDays: 30,
            organizationId: BuiltInOrganizationId.default
        )
        let line = makeLine(runId: run.id, index: 1)
        return BillingRunBundle(
            run: run,
            customer: customer,
            companyProfile: companyProfile,
            lines: [line],
            payments: []
        )
    }

    private static func makeLine(runId: String, index: Int) -> BillingReportLine {
        BillingReportLine(
            id: "smoke-line-\(index)",
            runId: runId,
            sessionId: "smoke-session-\(index)",
            todoId: "smoke-todo-\(index)",
            todoTitle: "Test Work Item #\(index)",
            customerId: "smoke-customer-1",
            customerName: "Acme A.Ş.",
            serviceType: .remote,
            timeType: .regular,
            actualSeconds: 3600,
            billableMinutes: 60,
            unitPriceMinor: 100_000,
            amountMinor: 100_000,
            currency: "TRY",
            // `Decimal(0.20)` constructed from Double silently introduces
            // float imprecision (the exact stored value is ≈ 0.200000000…00111).
            // Use the string init so the fixture matches the canonical
            // production path.
            vatRate: Decimal(string: "0.20")!,
            vatMinor: 20_000,
            totalMinor: 120_000
        )
    }

    private static func startsWithPDFMagicBytes(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        // "%PDF" header — every valid PDF starts here.
        return data.starts(with: [0x25, 0x50, 0x44, 0x46])
    }

    private static func endsWithEOFMarker(_ data: Data) -> Bool {
        // Search the last 64 bytes for "%%EOF".
        let tail = data.suffix(64)
        guard let asString = String(data: tail, encoding: .ascii) else { return false }
        return asString.contains("%%EOF")
    }
}
