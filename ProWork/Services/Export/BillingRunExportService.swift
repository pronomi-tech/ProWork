//
//  BillingRunExportService.swift
//  ProWork
//
//   Created by Pronomi.
//

import AppKit
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

    @MainActor
    func exportPDF(
        bundle: BillingRunBundle,
        settings: ServiceDocumentTemplateSettings = .defaultTemplate
    ) async throws -> Data {
        try await pdfRenderer.render(bundle: bundle, settings: settings)
    }

    func suggestedFilename(format: BillingExportFormat, bundle: BillingRunBundle) -> String {
        let customerName = (bundle.customer?.name ?? bundle.run.customerId)
            .replacingOccurrences(of: " ", with: "_")
        let title = bundle.run.invoiceNumber ?? bundle.run.title ?? ProWorkLocalizer.shared.string("export.filename.default", defaultValue: "hizmet_dokumu")
        let sanitizedTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        return "\(customerName)_\(sanitizedTitle).\(format.fileExtension)"
    }

    private func jsonData(for bundle: BillingRunBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
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
        let csv = ([header] + rows)
            .map { $0.map(Self.escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n")
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

    nonisolated private static func escapeCSVField(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    nonisolated private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    nonisolated private static func displayDateTimeWithSeconds(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter.string(from: date)
    }
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
        let finalizedAt: Date?

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
            finalizedAt = run.finalizedAt
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
        let startedAt: Date?
        let endedAt: Date?
        let serviceType: String
        let timeType: String
        let billableMinutes: Int
        let unitPriceMinor: Int
        let fixedFeeMinor: Int
        let amountMinor: Int
        let vatMinor: Int
        let totalMinor: Int
        let currency: String

        nonisolated init(_ line: BillingReportLine) {
            workTitle = line.todoTitle
            note = line.note
            startedAt = line.startedAt
            endedAt = line.endedAt
            serviceType = line.serviceType.rawValue
            timeType = line.timeType.rawValue
            billableMinutes = line.billableMinutes
            unitPriceMinor = line.unitPriceMinor
            fixedFeeMinor = line.fixedFeeMinor ?? 0
            amountMinor = line.amountMinor
            vatMinor = line.vatMinor
            totalMinor = line.totalMinor
            currency = line.currency
        }
    }

    struct PaymentPayload: Encodable {
        let paidAt: Date
        let amountMinor: Int
        let currency: String
        let method: String
        let reference: String?
        let note: String?

        nonisolated init(_ payment: Payment) {
            paidAt = payment.paidAt
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
                return "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escapeXML(value))</t></is></c>"
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

private enum ZIPWriter {
    static func archive(entries: [(String, Data)]) throws -> Data {
        var fileData = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for (path, data) in entries {
            let pathData = Data(path.utf8)
            let crc = CRC32.checksum(data: data)
            let compressedSize = UInt32(data.count)
            let uncompressedSize = UInt32(data.count)

            fileData.appendLE(UInt32(0x04034b50))
            fileData.appendLE(UInt16(20))
            fileData.appendLE(UInt16(0))
            fileData.appendLE(UInt16(0))
            fileData.appendLE(UInt16(0))
            fileData.appendLE(UInt16(0))
            fileData.appendLE(crc)
            fileData.appendLE(compressedSize)
            fileData.appendLE(uncompressedSize)
            fileData.appendLE(UInt16(pathData.count))
            fileData.appendLE(UInt16(0))
            fileData.append(pathData)
            fileData.append(data)

            centralDirectory.appendLE(UInt32(0x02014b50))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(compressedSize)
            centralDirectory.appendLE(uncompressedSize)
            centralDirectory.appendLE(UInt16(pathData.count))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt32(0))
            centralDirectory.appendLE(offset)
            centralDirectory.append(pathData)

            offset = UInt32(fileData.count)
        }

        let startOfCentralDirectory = UInt32(fileData.count)
        fileData.append(centralDirectory)

        fileData.appendLE(UInt32(0x06054b50))
        fileData.appendLE(UInt16(0))
        fileData.appendLE(UInt16(0))
        fileData.appendLE(UInt16(entries.count))
        fileData.appendLE(UInt16(entries.count))
        fileData.appendLE(UInt32(centralDirectory.count))
        fileData.appendLE(startOfCentralDirectory)
        fileData.appendLE(UInt16(0))

        return fileData
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
