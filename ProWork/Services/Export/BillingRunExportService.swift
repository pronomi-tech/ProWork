//  BillingRunExportService.swift
//  ProWork
//   Created by Pronomi.

import AppKit
import Compression
import Foundation

@MainActor
enum BillingExportFormat: String, CaseIterable, Identifiable, Hashable {
    case pdf
    case csv
    case excel
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .csv: return "CSV"
        case .excel: return ProWorkLocalizer.shared.string("export.format.excel", defaultValue: "Excel")
        case .json: return "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .csv: return "csv"
        case .excel: return "xlsx"
        case .json: return "json"
        }
    }
}

enum BillingRunExportError: LocalizedError {
    case pdfRequiresAsyncExport

    var errorDescription: String? {
        switch self {
        case .pdfRequiresAsyncExport:
            return ProWorkLocalizer.shared.string("export.error.pdfAsyncRequired", defaultValue: "PDF çıktısı yeni render motoru ile asenkron üretilmelidir.")
        }
    }
}

@MainActor
final class BillingRunExportService {
    private let pdfRenderer = BillingPdfRenderer()

    func export(format: BillingExportFormat, bundle: BillingRunBundle) throws -> Data {
        switch format {
        case .json:
            return try jsonData(for: bundle)
        case .csv:
            return csvData(for: bundle)
        case .excel:
            return try excelData(for: bundle)
        case .pdf:
            throw BillingRunExportError.pdfRequiresAsyncExport
        }
    }

    /// Previously @MainActor, which pinned the entire
    /// PDF render (CPU-heavy CoreText / NSGraphicsContext work) to the
    /// main actor even though BillingPdfRenderer itself is Sendable and
    /// non-isolated. Drop the isolation and forward directly to the
    /// renderer — `BillingPdfRenderer.render` already wraps its body in
    /// `Task.detached(priority: .userInitiated)`, so the outer detached
    /// task in this method was redundant double-wrapping.
    func exportPDF(
        bundle: BillingRunBundle,
        settings: ServiceDocumentTemplateSettings = .defaultTemplate
    ) async throws -> Data {
        try await pdfRenderer.render(bundle: bundle, settings: settings)
    }

    func suggestedFilename(format: BillingExportFormat, bundle: BillingRunBundle) -> String {
        let customerName = (bundle.customer?.name ?? bundle.run.customerId)
        let title = bundle.run.invoiceNumber ?? bundle.run.title ?? ProWorkLocalizer.shared.string("export.filename.default", defaultValue: "hizmet_dokumu")
        let stem = "\(BillingRunExportService.sanitizeFilenameComponent(customerName))_\(BillingRunExportService.sanitizeFilenameComponent(title))"
        return "\(stem).\(format.fileExtension)"
    }

    /// Filename sanitizer. Whitelist-only — keeps ASCII alnum and `-_.`
    /// plus Unicode letters / digits; everything else (control bytes,
    /// RTL/LTR overrides, spaces, path delimiters) collapses to `_`.
    /// the flow used to interleave filter / `..` collapse
    /// / trim / max-length / Windows-reserved-name prefix in an order that
    /// made the contract hard to read (and applied max-length *before*
    /// the reserved-name prefix, which could push the result one over).
    /// The pipeline is now an explicit, single-direction sequence:
    /// filter → collapse → trim → empty-fallback → Windows-reserve guard
    /// → cap to maxLength. Each step has a single responsibility and the
    /// final length cap is the last write, so the contract `result.count
    /// <= maxLength` always holds.
    static func sanitizeFilenameComponent(_ input: String, maxLength: Int = 120) -> String {
        // Step 1: whitelist filter — one pass over unicode scalars.
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_."))
        var filtered = String()
        filtered.reserveCapacity(input.unicodeScalars.count)
        for scalar in input.unicodeScalars {
            let isControl = scalar.value < 0x20 || scalar.value == 0x7F
            let isBidiOverride = (0x200E...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value)
            let isSpace = scalar == " "
            let isAllowed = !isControl
                && !isBidiOverride
                && !isSpace
                && (allowed.contains(scalar)
                    || CharacterSet.letters.contains(scalar)
                    || CharacterSet.decimalDigits.contains(scalar))
            if isAllowed {
                filtered.unicodeScalars.append(scalar)
            } else {
                filtered.append("_")
            }
        }

        // Step 2: collapse `..` runs so no path-traversal segment survives.
        while filtered.contains("..") {
            filtered = filtered.replacingOccurrences(of: "..", with: "_")
        }

        // Step 3: trim Windows-hostile leading / trailing characters.
        let trimSet = CharacterSet(charactersIn: ". _")
        var result = filtered.trimmingCharacters(in: trimSet)

        // Step 4: empty fallback before any subsequent prefix mutation.
        if result.isEmpty {
            result = "untitled"
        }

        // Step 5: Windows reserves CON, PRN, AUX, NUL, COM1…9, LPT1…9
        // case-insensitively, with or without extension. Prefix `_` when
        // the stem matches; the extension can stay untouched.
        let baseName = result.split(separator: ".").first.map(String.init) ?? result
        let reserved: Set<String> = [
            "CON", "PRN", "AUX", "NUL",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        ]
        if reserved.contains(baseName.uppercased()) {
            result = "_" + result
        }

        // Step 6: final length cap (applied last so the contract
        // result.count <= maxLength always holds, even after step 5).
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }

        return result
    }

    private func jsonData(for bundle: BillingRunBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // Foundation's JSONEncoder pipes `Decimal`
        // through `Double`, which would corrupt the audit snapshot. The
        // payload only encodes integer (`Int`) money fields and the
        // string-wrapped `Decimal` (`AuditDecimal`) for the VAT rate, so
        // no Double round-trip can occur. Any future Decimal field added
        // to `BillingRunExportPayload` MUST use `AuditDecimal` (or string)
        // to preserve the invariant.
        return try encoder.encode(BillingRunExportPayload(bundle: bundle))
    }

    private func csvData(for bundle: BillingRunBundle) -> Data {
        let rows = makeLineRows(bundle: bundle)
        let header = [
            ProWorkLocalizer.shared.string("export.column.todoTitle", defaultValue: "İş Tanımı"),
            ProWorkLocalizer.shared.string("vat.form.note", defaultValue: "Not"),
            ProWorkLocalizer.shared.string("workSessions.column.start", defaultValue: "Başlangıç"),
            ProWorkLocalizer.shared.string("workSessions.column.end", defaultValue: "Bitiş"),
            ProWorkLocalizer.shared.string("priceLists.rows.form.serviceType", defaultValue: "Hizmet"),
            ProWorkLocalizer.shared.string("priceLists.rows.form.timeType", defaultValue: "Zaman Tipi"),
            ProWorkLocalizer.shared.string("export.column.billableMinutes", defaultValue: "Ücretli Süre (dk)"),
            ProWorkLocalizer.shared.string("export.column.unitPrice", defaultValue: "Birim Fiyat"),
            ProWorkLocalizer.shared.string("export.column.fixedFee", defaultValue: "Sabit Fiyat"),
            ProWorkLocalizer.shared.string("reports.summary.subtotal", defaultValue: "Ara Toplam"),
            ProWorkLocalizer.shared.string("reports.summary.vat", defaultValue: "KDV"),
            ProWorkLocalizer.shared.string("reports.summary.grandTotal", defaultValue: "Toplam"),
            ProWorkLocalizer.shared.string("export.column.currency", defaultValue: "Para Birimi")
        ]
        // CRLF line separator for Excel/Windows compatibility.
        // The BOM is already written; \r\n termination is required for
        // full RFC 4180 + Excel expectations, otherwise it opens as "one line".
        let csv = ([header] + rows)
            .map { $0.map(Self.escapeCSVField).joined(separator: ",") }
            .joined(separator: "\r\n")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        return data
    }

    private func excelData(for bundle: BillingRunBundle) throws -> Data {
        let rows: [[String]] = [
            [ProWorkLocalizer.shared.string("export.row.document", defaultValue: "Belge"), bundle.run.title ?? bundle.run.invoiceNumber ?? bundle.run.id],
            [ProWorkLocalizer.shared.string("projects.form.customer", defaultValue: "Müşteri"), bundle.customer?.name ?? bundle.run.customerId],
            [ProWorkLocalizer.shared.string("reports.filter.period", defaultValue: "Dönem"), "\(bundle.run.periodStart) - \(bundle.run.periodEnd)"],
            [ProWorkLocalizer.shared.string("projects.form.status", defaultValue: "Durum"), bundle.run.status.title],
            [ProWorkLocalizer.shared.string("export.row.referenceNumber", defaultValue: "Referans No"), bundle.run.invoiceNumber ?? "—"],
            [ProWorkLocalizer.shared.string("export.column.currency", defaultValue: "Para Birimi"), bundle.run.currency],
            [ProWorkLocalizer.shared.string("reports.summary.subtotal", defaultValue: "Ara Toplam"), ProWorkFormatters.moneyAmount(bundle.run.subtotal)],
            [ProWorkLocalizer.shared.string("reports.summary.vat", defaultValue: "KDV"), ProWorkFormatters.moneyAmount(bundle.run.vat)],
            [ProWorkLocalizer.shared.string("reports.summary.grandTotal", defaultValue: "Genel Toplam"), ProWorkFormatters.moneyAmount(bundle.run.total)],
            [],
            [
                ProWorkLocalizer.shared.string("export.column.todoTitle", defaultValue: "İş Tanımı"),
                ProWorkLocalizer.shared.string("vat.form.note", defaultValue: "Not"),
                ProWorkLocalizer.shared.string("workSessions.column.start", defaultValue: "Başlangıç"),
                ProWorkLocalizer.shared.string("workSessions.column.end", defaultValue: "Bitiş"),
                ProWorkLocalizer.shared.string("priceLists.rows.form.serviceType", defaultValue: "Hizmet"),
                ProWorkLocalizer.shared.string("priceLists.rows.form.timeType", defaultValue: "Zaman Tipi"),
                ProWorkLocalizer.shared.string("export.column.billableMinutes", defaultValue: "Ücretli Süre (dk)"),
                ProWorkLocalizer.shared.string("export.column.unitPrice", defaultValue: "Birim Fiyat"),
                ProWorkLocalizer.shared.string("export.column.fixedFee", defaultValue: "Sabit Fiyat"),
                ProWorkLocalizer.shared.string("reports.summary.subtotal", defaultValue: "Ara Toplam"),
                ProWorkLocalizer.shared.string("reports.summary.vat", defaultValue: "KDV"),
                ProWorkLocalizer.shared.string("reports.summary.grandTotal", defaultValue: "Toplam"),
                ProWorkLocalizer.shared.string("export.column.currency", defaultValue: "Para Birimi")
            ]
        ] + makeLineRows(bundle: bundle)

        return try MinimalXLSXWriter.makeWorkbook(
            sheetName: ProWorkLocalizer.shared.string("export.sheet.billingReport", defaultValue: "HizmetDokumu"),
            rows: rows
        )
    }

    private func makeLineRows(bundle: BillingRunBundle) -> [[String]] {
        bundle.lines.map { line in
            let zeroMoney = Money(minorUnits: 0, currency: line.currency)
            let fixedFeeMoney = Money(
                minorUnits: line.fixedFeeMinor ?? 0,
                currency: line.currency
            )
            return [
                line.todoTitle,
                line.note ?? "—",
                line.isFixedFee ? "" : Self.displayDateTimeWithSeconds(line.startedAt),
                line.isFixedFee ? "" : Self.displayDateTimeWithSeconds(line.endedAt),
                line.isFixedFee ? ProWorkLocalizer.shared.string("export.fixedFee", defaultValue: "Sabit Ücret") : line.serviceType.title,
                line.isFixedFee ? "" : line.timeType.title,
                String(line.isFixedFee ? 0 : line.billableMinutes),
                ProWorkFormatters.moneyAmount(
                    line.isFixedFee
                        ? zeroMoney
                        : Money(minorUnits: line.unitPriceMinor, currency: line.currency)
                ),
                ProWorkFormatters.moneyAmount(line.isFixedFee ? fixedFeeMoney : zeroMoney),
                ProWorkFormatters.moneyAmount(Money(minorUnits: line.amountMinor, currency: line.currency)),
                ProWorkFormatters.moneyAmount(Money(minorUnits: line.vatMinor, currency: line.currency)),
                ProWorkFormatters.moneyAmount(Money(minorUnits: line.totalMinor, currency: line.currency)),
                line.currency
            ]
        }
    }

    /// Escapes a single CSV cell value.
    /// the order matters and the dependency between the
    /// two steps is intentional but was previously undocumented. Step 1
    /// is `SpreadsheetCellSanitizer.escape`, which neutralises formula-
    /// injection prefixes (`=`, `+`, `-`, `@`, `|`, TAB, CR) by prepending
    /// a leading `'`. Step 2 is CSV-quote escaping (`"` → `""` and wrap
    /// in `"…"` when the field contains comma / quote / newline). These
    /// MUST run in this order — running CSV escape first would leave the
    /// dangerous prefix character at position 0 of the cell that Excel
    /// imports, defeating the formula-injection guard.
    nonisolated private static func escapeCSVField(_ value: String) -> String {
        // Step 1: spreadsheet-safe sanitisation (formula injection guard).
        let sanitized = SpreadsheetCellSanitizer.escape(value)
        // Step 2: CSV quoting on top of the sanitised value.
        let needsQuotes = sanitized.contains(",") || sanitized.contains("\"") || sanitized.contains("\n")
        let escaped = sanitized.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    /// CSV / XLSX dates are emitted in ISO 8601 with a POSIX
    /// locale so Excel (and any other consumer) parses them deterministically
    /// regardless of system locale. Hardcoded `tr_TR` formatting previously
    /// produced `dd.MM.yyyy` text that downstream tools imported as strings
    /// instead of dates.
    nonisolated private static func displayDate(_ date: Date) -> String {
        Self.exportDateTimeFormatter.string(from: date)
    }

    nonisolated private static func displayDateTimeWithSeconds(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.exportDateTimeWithSecondsFormatter.string(from: date)
    }

    /// `nonisolated(unsafe)`: DateFormatter is thread-safe per Apple
    /// docs (iOS 7+ / macOS 10.9+) but not Sendable in Swift's type
    /// system. This formatter is used from nonisolated `displayDate(_:)`
    /// and `displayDateTimeWithSeconds(_:)` helpers — avoids the cost
    /// of pulling MainActor isolation inward.
    /// unsafe opt-out kabul edilebilir.
    nonisolated private static let exportDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    nonisolated private static let exportDateTimeWithSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private struct BillingRunExportPayload: Encodable {
    let run: RunPayload
    let customer: CustomerPayload?
    let companyProfile: CompanyProfilePayload?
    let lines: [LinePayload]
    let payments: [PaymentPayload]

    nonisolated init(bundle: BillingRunBundle) {
        self.run = RunPayload(run: bundle.run)
        self.customer = bundle.customer.map { CustomerPayload($0, currency: bundle.run.currency) }
        self.companyProfile = bundle.companyProfile.map(CompanyProfilePayload.init)
        self.lines = bundle.lines.map(LinePayload.init)
        self.payments = bundle.payments.map(PaymentPayload.init)
    }

    /// Shared ISO 8601 formatter for export payloads. Pinned to UTC and the
    /// `withInternetDateTime` option set so consumers see a single uniform
    /// shape across `finalizedAt`, line-level timestamps, etc.
    /// `nonisolated(unsafe)`: ISO8601DateFormatter is documented as
    /// thread-safe by Apple (macOS 10.12+) but lacks Sendable conformance
    /// in Swift's type system. The shared-formatter pattern here is
    /// intentional (avoids allocating a new instance per export call) —
    /// the unsafe opt-out is acceptable because there is no actual race.
    nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    nonisolated static func iso8601String(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    struct RunPayload: Encodable {
        let id: String
        let customerId: String
        let periodStart: String
        let periodEnd: String
        let status: String
        let title: String?
        let invoiceNumber: String?
        let currency: String
        let subtotalMinor: Int
        let vatMinor: Int
        let totalMinor: Int
        let paidMinor: Int
        let balanceMinor: Int
        let paymentStatus: String
        let dueDate: String?
        /// Previously a raw `Date`, which JSONEncoder encoded
        /// as a different string flavour from the day-only `periodStart` /
        /// `periodEnd` / `dueDate` siblings — consumers had to branch on type.
        /// Encode as ISO 8601 string so every date-shaped field in the run
        /// payload is the same JSON shape (`null` or `String`).
        let finalizedAt: String?

        nonisolated init(run: BillingReportRun) {
            id = run.id
            customerId = run.customerId
            periodStart = run.periodStart
            periodEnd = run.periodEnd
            status = run.status.rawValue
            title = run.title
            invoiceNumber = run.invoiceNumber
            currency = run.currency
            subtotalMinor = run.subtotalMinor
            vatMinor = run.vatMinor
            totalMinor = run.totalMinor
            paidMinor = run.paidMinor
            balanceMinor = run.balanceMinor
            paymentStatus = run.paymentStatus.rawValue
            dueDate = run.dueDate
            finalizedAt = run.finalizedAt.map(BillingRunExportPayload.iso8601String)
        }
    }

    struct CustomerPayload: Encodable {
        let id: String
        let name: String
        let currency: String

        nonisolated init(_ customer: Customer, currency: String) {
            id = customer.id
            name = customer.name
            self.currency = currency
        }
    }

    struct CompanyProfilePayload: Encodable {
        let legalName: String
        let taxNumber: String?
        let taxOffice: String?
        let address: String?
        let email: String?
        let phone: String?

        nonisolated init(_ profile: CompanyProfile) {
            legalName = profile.legalName
            taxNumber = profile.taxNumber
            taxOffice = profile.taxOffice
            address = profile.address
            email = profile.email
            phone = profile.phone
        }
    }

    struct LinePayload: Encodable {
        let workTitle: String
        let note: String?
        /// Encoded as ISO 8601 string so the on-disk shape
        /// matches the run-level period/dueDate/finalizedAt siblings.
        let startedAt: String?
        let endedAt: String?
        let serviceType: String
        let timeType: String
        let billableMinutes: Int
        let unitPriceMinor: Int
        let fixedFeeMinor: Int
        let amountMinor: Int
        /// Y10: We embed the VAT rate into the snapshot as a string; Decimal
        /// olarak encode etmek `Double` round-trip riski getirirdi.
        let vatRate: AuditDecimal
        let vatMinor: Int
        let totalMinor: Int
        let currency: String
        let isVatExempt: Bool

        nonisolated init(_ line: BillingReportLine) {
            workTitle = line.todoTitle
            note = line.note
            startedAt = line.startedAt.map(BillingRunExportPayload.iso8601String)
            endedAt = line.endedAt.map(BillingRunExportPayload.iso8601String)
            serviceType = line.serviceType.rawValue
            timeType = line.timeType.rawValue
            billableMinutes = line.billableMinutes
            unitPriceMinor = line.unitPriceMinor
            fixedFeeMinor = line.fixedFeeMinor ?? 0
            amountMinor = line.amountMinor
            vatRate = AuditDecimal(line.vatRate)
            vatMinor = line.vatMinor
            totalMinor = line.totalMinor
            currency = line.currency
            isVatExempt = line.isVatExempt
        }
    }

    /// Wrapper that always encodes `Decimal` as a canonical string.
    /// Foundation's JSONEncoder implementation serialises Decimal via
    /// Double; unacceptable for a financial snapshot.
    /// `nonisolated`: called from the enclosing `BillingRunExportPayload`'s
    /// nonisolated init, so it must stay outside the MainActor isolation default.
    nonisolated struct AuditDecimal: Encodable {
        let value: Decimal

        init(_ value: Decimal) {
            self.value = value
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(NSDecimalNumber(decimal: value).stringValue)
        }
    }

    struct PaymentPayload: Encodable {
        /// Encoded as ISO 8601 string for shape parity with
        /// other date-shaped fields in the export payload.
        let paidAt: String
        let amountMinor: Int
        let currency: String
        let method: String
        let reference: String?
        let note: String?

        nonisolated init(_ payment: Payment) {
            paidAt = BillingRunExportPayload.iso8601String(payment.paidAt)
            amountMinor = payment.amountMinor
            currency = payment.currency
            method = payment.method.rawValue
            reference = payment.reference
            note = payment.note
        }
    }
}

private enum MinimalXLSXWriter {
    static func makeWorkbook(sheetName: String, rows: [[String]]) throws -> Data {
        let worksheetXML = worksheetXML(rows: rows)
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="\(escapeXML(sheetName))" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
        let workbookRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
          <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
          <borders count="1"><border/></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """

        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(relsXML.utf8)),
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRelsXML.utf8)),
            ("xl/styles.xml", Data(stylesXML.utf8)),
            ("xl/worksheets/sheet1.xml", Data(worksheetXML.utf8))
        ]

        return try ZIPWriter.archive(entries: files)
    }

    private static func worksheetXML(rows: [[String]]) -> String {
        let sheetRows = rows.enumerated().map { rowIndex, columns in
            let cells = columns.enumerated().map { columnIndex, value in
                let cellRef = "\(columnName(columnIndex + 1))\(rowIndex + 1)"
                // Inline string cells must be sanitized for spreadsheet
                // formula injection. A field like
                // "=cmd|' /C calc'!A1" is interpreted as a formula even
                // through an inline string; prefixing with an apostrophe
                // forces text mode.
                let safe = SpreadsheetCellSanitizer.escape(value)
                return "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escapeXML(safe))</t></is></c>"
            }.joined()

            return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>\(sheetRows)</sheetData>
        </worksheet>
        """
    }

    private static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            index = (index - 1) / 26
        }
        return name
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum ZIPWriterError: LocalizedError {
    case tooManyEntries(Int)
    case entryTooLarge(path: String, bytes: Int)
    case entryNameTooLong(path: String)

    var errorDescription: String? {
        switch self {
        case .tooManyEntries(let n):
            return "ZIP archive entry count exceeds 65535 (got \(n)). ZIP64 not supported."
        case .entryTooLarge(let path, let bytes):
            return "ZIP archive entry '\(path)' is \(bytes) bytes which exceeds the 4 GiB ZIP-32 limit. ZIP64 not supported."
        case .entryNameTooLong(let path):
            return "ZIP archive entry name '\(path)' exceeds 65535 bytes."
        }
    }
}

private enum ZIPWriter {
    // PKZIP format signatures (PK\03\04, PK\01\02, PK\05\06)
    private static let localFileHeaderSignature: UInt32 = 0x04034b50
    private static let centralDirectoryHeaderSignature: UInt32 = 0x02014b50
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50

    // ZIP spec: "version needed to extract" / "version made by".
    // 20 = 2.0 (minimum for DEFLATE support).
    private static let versionNeededToExtract: UInt16 = 20
    private static let versionMadeBy: UInt16 = 20

    // General purpose bit flag.
    // Bit 11 (Language encoding flag, EFS) = 1 signals that file names
    // are stored as UTF-8 instead of the legacy CP437. Today every
    // archive we emit (XLSX inner paths, exported workbook entries)
    // uses ASCII-only names, so the practical impact is nil — but
    // setting the flag is the defensive future-proof choice the moment
    // anyone introduces a non-ASCII filename (Turkish customer names in
    // filenames are a realistic next step).
    private static let generalPurposeBitFlagLanguageEncodingUTF8: UInt16 = 1 << 11
    private static let generalPurposeBitFlag: UInt16 = generalPurposeBitFlagLanguageEncodingUTF8

    // Compression method codes (APPNOTE 4.4.5):
    //   0 = STORE (no compression), 8 = DEFLATE.
    private static let compressionMethodStore: UInt16 = 0
    private static let compressionMethodDeflate: UInt16 = 8

    static func archive(entries: [(String, Data)]) throws -> Data {
        // We don't support ZIP64, so size fields can't exceed UInt32 /
        // UInt16 limits. If a single file starts to exceed 4 GiB or
        // more than 65,535 entries are generated, the format silently
        // overflows (the lower 32 bits get truncated); catch this early.
        // tespit edip throw'la.
        guard entries.count <= Int(UInt16.max) else {
            throw ZIPWriterError.tooManyEntries(entries.count)
        }

        var fileData = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for (path, data) in entries {
            guard data.count <= Int(UInt32.max) else {
                throw ZIPWriterError.entryTooLarge(path: path, bytes: data.count)
            }
            let pathData = Data(path.utf8)
            guard pathData.count <= Int(UInt16.max) else {
                throw ZIPWriterError.entryNameTooLong(path: path)
            }
            let crc = CRC32.checksum(data: data)
            let uncompressedSize = UInt32(data.count)

            // Try DEFLATE; fall back to STORE on blobs that don't shrink.
            // For empty data or random / already-compressed bytes, STORE
            // comes out smaller (because of the header overhead).
            let payload: Data
            let compressionMethod: UInt16
            if let deflated = ZIPDeflater.deflate(data), deflated.count < data.count {
                payload = deflated
                compressionMethod = compressionMethodDeflate
            } else {
                payload = data
                compressionMethod = compressionMethodStore
            }
            guard payload.count <= Int(UInt32.max) else {
                throw ZIPWriterError.entryTooLarge(path: path, bytes: payload.count)
            }
            let compressedSize = UInt32(payload.count)

            // Local file header
            fileData.appendLE(localFileHeaderSignature)
            fileData.appendLE(versionNeededToExtract)
            fileData.appendLE(generalPurposeBitFlag)
            fileData.appendLE(compressionMethod)
            fileData.appendLE(UInt16(0)) // last mod file time (epoch)
            fileData.appendLE(UInt16(0)) // last mod file date (epoch)
            fileData.appendLE(crc)
            fileData.appendLE(compressedSize)
            fileData.appendLE(uncompressedSize)
            fileData.appendLE(UInt16(pathData.count))
            fileData.appendLE(UInt16(0)) // extra field length
            fileData.append(pathData)
            fileData.append(payload)

            // Central directory header
            centralDirectory.appendLE(centralDirectoryHeaderSignature)
            centralDirectory.appendLE(versionMadeBy)
            centralDirectory.appendLE(versionNeededToExtract)
            centralDirectory.appendLE(generalPurposeBitFlag)
            centralDirectory.appendLE(compressionMethod)
            centralDirectory.appendLE(UInt16(0)) // last mod file time
            centralDirectory.appendLE(UInt16(0)) // last mod file date
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(compressedSize)
            centralDirectory.appendLE(uncompressedSize)
            centralDirectory.appendLE(UInt16(pathData.count))
            centralDirectory.appendLE(UInt16(0)) // extra field length
            centralDirectory.appendLE(UInt16(0)) // file comment length
            centralDirectory.appendLE(UInt16(0)) // disk number start
            centralDirectory.appendLE(UInt16(0)) // internal file attributes
            centralDirectory.appendLE(UInt32(0)) // external file attributes
            centralDirectory.appendLE(offset)
            centralDirectory.append(pathData)

            offset = UInt32(fileData.count)
        }

        let startOfCentralDirectory = UInt32(fileData.count)
        fileData.append(centralDirectory)

        // End of central directory record
        fileData.appendLE(endOfCentralDirectorySignature)
        fileData.appendLE(UInt16(0)) // number of this disk
        fileData.appendLE(UInt16(0)) // disk where central directory starts
        fileData.appendLE(UInt16(entries.count)) // central directory records on this disk
        fileData.appendLE(UInt16(entries.count)) // total central directory records
        fileData.appendLE(UInt32(centralDirectory.count))
        fileData.appendLE(startOfCentralDirectory)
        fileData.appendLE(UInt16(0)) // comment length

        return fileData
    }
}

private enum ZIPDeflater {
    /// Raw DEFLATE encoding (without zlib header/trailer) — ZIP compression
    /// method 8 tam olarak bunu bekler.
    /// Apple's `COMPRESSION_ZLIB` algorithm is documented to produce raw
    /// DEFLATE ("encoded data has no header or trailer"). We still
    /// defensively check: if the output looks like an RFC 1950 zlib
    /// stream (2-byte header with 0x78 marker + 4-byte adler32 trailer)
    /// we strip the wrapping. If Apple ever changes the behaviour or
    /// there is an emulator/platform difference, this keeps the XLSX
    /// output parseable in strict parsers like LibreOffice.
    static func deflate(_ source: Data) -> Data? {
        guard !source.isEmpty else { return nil }

        // Sizing the destination buffer to "input + 64 bytes" is a safe
        // upper bound: for pathological inputs DEFLATE output can be
        // slightly larger than the source, so we allocate a generous buffer.
        let destinationCapacity = source.count + 64
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
        defer { destination.deallocate() }

        let compressedSize = source.withUnsafeBytes { rawBuffer -> Int in
            guard let sourcePointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compression_encode_buffer(
                destination,
                destinationCapacity,
                sourcePointer,
                source.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }
        let buffer = Data(bytes: destination, count: compressedSize)
        return stripZlibWrappingIfPresent(buffer)
    }

    /// RFC 1950 zlib stream tespit edilirse 2-byte header ve 4-byte adler32
    /// strips the trailer. Detection: the low 4 bits of the first byte
    /// method'u (CM = 8 = DEFLATE) ve `(byte0 << 8 | byte1) % 31 == 0` FCHECK
    /// must pass the compression check (RFC 1950 §2.2). Otherwise the
    /// output is already raw DEFLATE and is returned as-is.
    private static func stripZlibWrappingIfPresent(_ data: Data) -> Data {
        guard data.count >= 6 else { return data }
        let byte0 = data[data.startIndex]
        let byte1 = data[data.startIndex + 1]
        let cm = byte0 & 0x0F
        let cmf = UInt16(byte0) << 8 | UInt16(byte1)
        guard cm == 8, cmf % 31 == 0 else {
            return data
        }
        // Header (2) + raw DEFLATE + adler32 (4)
        let rawStart = data.startIndex + 2
        let rawEnd = data.endIndex - 4
        guard rawStart < rawEnd else { return data }
        return data.subdata(in: rawStart..<rawEnd)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 {
            if c & 1 == 1 {
                c = 0xedb88320 ^ (c >> 1)
            } else {
                c >>= 1
            }
        }
        return c
    }

    static func checksum(data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendLE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}
