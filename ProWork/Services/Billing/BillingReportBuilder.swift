//
//  BillingReportBuilder.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Spec §10–14 — Müşteri / proje / todo bazlı raporlamaların toplama servisi.
//  BillingCalculator'dan gelen satırları gruplayıp özetler üretir.
//

import Foundation

// MARK: - Çıktı yapıları

struct BillingPeriodSummary: Hashable {
    let totalActualSeconds: Int
    let billableMinutes: Int
    let nonBillableSeconds: Int

    let manualSeconds: Int
    let automaticSeconds: Int

    let remoteSeconds: Int
    let onsiteSeconds: Int

    let regularSeconds: Int
    let afterHoursSeconds: Int
    let weekendSeconds: Int
    let holidaySeconds: Int

    let subtotalMinor: Int
    let vatMinor: Int
    let totalMinor: Int
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
    /// Verilen satırlardan müşteri kırılımı üretir (tek müşteri için).
    static func buildCustomerReport(
        customerId: String,
        customerName: String,
        lines: [BillingReportLine],
        currency: String
    ) -> CustomerReport {
        let customerLines = lines.filter { $0.customerId == customerId }
        let summary = summarize(lines: customerLines, currency: currency)

        // Proje kırılımı
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
        let todoGroups = Dictionary(grouping: lines) { $0.todoId }
        return todoGroups.map { (todoId, todoLines) -> TodoBreakdown in
            let title = todoLines.first?.todoTitle ?? ""
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

    /// Birden fazla müşteri için kırılım — Faturalandırma Özeti ekranı için.
    static func buildOrganizationReport(
        lines: [BillingReportLine],
        masterCurrency: String
    ) -> [CustomerReport] {
        let customerGroups = Dictionary(grouping: lines) { $0.customerId }
        return customerGroups.map { (customerId, customerLines) -> CustomerReport in
            buildCustomerReport(
                customerId: customerId,
                customerName: customerLines.first?.customerName ?? "",
                lines: customerLines,
                currency: customerLines.first?.currency ?? masterCurrency
            )
        }
        .sorted { $0.customerName.localizedCaseInsensitiveCompare($1.customerName) == .orderedAscending }
    }

    // MARK: - Summarize

    private static func summarize(lines: [BillingReportLine], currency: String) -> BillingPeriodSummary {
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
