//  BillingReportBuilder.swift
//  ProWork
//  Created by Pronomi.
//  Spec §10–14 — Aggregation service for customer / project / todo reports.
//  Groups the lines coming from BillingCalculator and produces summaries.

import Foundation
import os

// MARK: - Unit-tagged aliases

/// Wall-clock duration in seconds. Used for "how long was the session"
/// metrics that have no rounding policy attached.
typealias ActualSeconds = Int

/// Billable duration in whole minutes after the billing-window rounding
/// rules have been applied. Different scale than ActualSeconds — never
/// add them together without going through BillingCalculator.
typealias BillableMinutes = Int

/// Monetary amount in the smallest currency unit (kuruş, cent, fils).
/// Pairing this with the currency string yields a Money value.
typealias MinorUnits = Int

// MARK: - Output structures

struct BillingPeriodSummary: Hashable {
    let totalActualSeconds: ActualSeconds
    let billableMinutes: BillableMinutes
    let nonBillableSeconds: ActualSeconds

    let manualSeconds: ActualSeconds
    let automaticSeconds: ActualSeconds

    let remoteSeconds: ActualSeconds
    let onsiteSeconds: ActualSeconds

    let regularSeconds: ActualSeconds
    let afterHoursSeconds: ActualSeconds
    let weekendSeconds: ActualSeconds
    let holidaySeconds: ActualSeconds

    let subtotalMinor: MinorUnits
    let vatMinor: MinorUnits
    let totalMinor: MinorUnits
    let currency: String

    let lineCount: Int
    let manualLineCount: Int
}

struct CustomerReport: Hashable {
    let customerId: String
    let customerName: String
    let summary: BillingPeriodSummary
    let projectBreakdown: [ProjectBreakdown]
}

struct ProjectBreakdown: Hashable {
    let projectId: String?
    let projectName: String
    let summary: BillingPeriodSummary
    let todoBreakdown: [TodoBreakdown]
}

struct TodoBreakdown: Hashable {
    let todoId: String
    let todoTitle: String
    let categoryName: String?
    let summary: BillingPeriodSummary
}

// MARK: - Builder

enum BillingReportBuilder {
    /// Produces a customer breakdown from the given lines (for a single customer).
    static func buildCustomerReport(
        customerId: String,
        customerName: String,
        lines: [BillingReportLine],
        currency: String
    ) -> CustomerReport {
        let customerLines = lines.filter { $0.customerId == customerId }
        let summary = summarize(lines: customerLines, currency: currency)

        // Project breakdown
        let projectGroups = Dictionary(grouping: customerLines) { $0.projectId ?? "" }
        let projectBreakdown = projectGroups.map { (key, projectLines) -> ProjectBreakdown in
            let projectName = projectLines.first?.projectName ?? ProWorkLocalizer.shared.string("reports.project.noProject", defaultValue: "Projesiz")
            let projectSummary = summarize(lines: projectLines, currency: currency)
            return ProjectBreakdown(
                projectId: key.isEmpty ? nil : key,
                projectName: projectName,
                summary: projectSummary,
                todoBreakdown: buildTodoBreakdown(lines: projectLines, currency: currency)
            )
        }
        .sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }

        return CustomerReport(
            customerId: customerId,
            customerName: customerName,
            summary: summary,
            projectBreakdown: projectBreakdown
        )
    }

    private static func buildTodoBreakdown(lines: [BillingReportLine], currency: String) -> [TodoBreakdown] {
        // Localized fallbacks; the silent "" used to leak into
        // PDF/CSV exports as a blank row that looked like a data bug.
        let fallbackTitle = ProWorkLocalizer.shared.string(
            "billingReport.fallback.todoTitle",
            defaultValue: "İsimsiz iş"
        )
        let todoGroups = Dictionary(grouping: lines) { $0.todoId }
        return todoGroups.map { (todoId, todoLines) -> TodoBreakdown in
            let title = todoLines.first?.todoTitle ?? fallbackTitle
            let categoryName = todoLines.first?.categoryName
            return TodoBreakdown(
                todoId: todoId,
                todoTitle: title,
                categoryName: categoryName,
                summary: summarize(lines: todoLines, currency: currency)
            )
        }
        .sorted { $0.todoTitle.localizedCaseInsensitiveCompare($1.todoTitle) == .orderedAscending }
    }

    /// Breakdown across multiple customers — for the Billing Summary screen.
    static func buildOrganizationReport(
        lines: [BillingReportLine],
        masterCurrency: String
    ) -> [CustomerReport] {
        let fallbackName = ProWorkLocalizer.shared.string(
            "billingReport.fallback.customerName",
            defaultValue: "İsimsiz müşteri"
        )
        let customerGroups = Dictionary(grouping: lines) { $0.customerId }
        return customerGroups.map { (customerId, customerLines) -> CustomerReport in
            buildCustomerReport(
                customerId: customerId,
                customerName: customerLines.first?.customerName ?? fallbackName,
                lines: customerLines,
                currency: customerLines.first?.currency ?? masterCurrency
            )
        }
        .sorted { $0.customerName.localizedCaseInsensitiveCompare($1.customerName) == .orderedAscending }
    }

    // MARK: - Summarize

    /// Aggregates a set of `BillingReportLine` into a `BillingPeriodSummary`.
    ///
    /// - Important: This summary treats the `minorAmount` columns as
    ///   additive in a single currency. Callers MUST pass lines that all
    ///   share `currency` (or be intentionally summing within one). If
    ///   the input mixes currencies, the totals are nonsense (you can't
    ///   sum TRY kuruş with USD cent). Heterogeneous mixes are logged
    ///   loudly so the bug surfaces during diagnosis — matching the
    ///   discipline `BillingRunLifecycleService.summarize` already
    /// enforces.
    private static func summarize(lines: [BillingReportLine], currency: String) -> BillingPeriodSummary {
        let distinctCurrencies = Set(lines.map(\.currency))
        if distinctCurrencies.count > 1 {
            ProWorkLog.billing.error(
                "BillingReportBuilder.summarize: heterogeneous currency mix \(distinctCurrencies.sorted().joined(separator: ","), privacy: .public); minor unit totals will be nonsensical. Bundle the input into per-currency groups before summarising."
            )
        }
        var totalActual = 0
        var billable = 0
        var nonBillableSeconds = 0
        var manual = 0, automatic = 0
        var remote = 0, onsite = 0
        var regular = 0, after = 0, weekend = 0, holiday = 0
        var subtotal = 0, vat = 0, total = 0
        var manualCount = 0

        for line in lines {
            totalActual += line.actualSeconds
            if line.isBillable {
                billable += line.billableMinutes
            } else {
                nonBillableSeconds += line.actualSeconds
            }

            if line.isManual {
                manual += line.actualSeconds
                manualCount += 1
            } else {
                automatic += line.actualSeconds
            }

            switch line.serviceType {
            case .remote: remote += line.actualSeconds
            case .onsite: onsite += line.actualSeconds
            }

            switch line.timeType {
            case .regular: regular += line.actualSeconds
            case .afterHours: after += line.actualSeconds
            case .weekend: weekend += line.actualSeconds
            case .holiday: holiday += line.actualSeconds
            }

            subtotal += line.amountMinor
            vat += line.vatMinor
            total += line.totalMinor
        }

        return BillingPeriodSummary(
            totalActualSeconds: totalActual,
            billableMinutes: billable,
            nonBillableSeconds: nonBillableSeconds,
            manualSeconds: manual,
            automaticSeconds: automatic,
            remoteSeconds: remote,
            onsiteSeconds: onsite,
            regularSeconds: regular,
            afterHoursSeconds: after,
            weekendSeconds: weekend,
            holidaySeconds: holiday,
            subtotalMinor: subtotal,
            vatMinor: vat,
            totalMinor: total,
            currency: currency,
            lineCount: lines.count,
            manualLineCount: manualCount
        )
    }
}
