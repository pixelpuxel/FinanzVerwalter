import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit

enum ReportPDFOrientation: String, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape

    var id: Self { self }

    var title: String {
        switch self {
        case .portrait: "Hochformat"
        case .landscape: "Querformat"
        }
    }
}

struct RegisterPrintSnapshot: Equatable, Sendable {
    var title: String
    var filterSummary: String
    var generatedAt: Date
    var columns: [RegisterColumn]
    var rows: [[String]]
}

enum RegisterCSVFormat: String, CaseIterable, Identifiable, Sendable {
    case semicolonUTF8
    case commaUTF8
    case semicolonWindows1252

    var id: Self { self }

    var title: String {
        switch self {
        case .semicolonUTF8: "Semikolon · UTF-8"
        case .commaUTF8: "Komma · UTF-8"
        case .semicolonWindows1252: "Semikolon · Windows-1252"
        }
    }

    fileprivate var separator: Character {
        switch self {
        case .semicolonUTF8, .semicolonWindows1252: ";"
        case .commaUTF8: ","
        }
    }

    fileprivate var encoding: String.Encoding {
        switch self {
        case .semicolonUTF8, .commaUTF8: .utf8
        case .semicolonWindows1252: .windowsCP1252
        }
    }
}

enum RegisterCSVExporter {
    static func data(
        snapshot: RegisterPrintSnapshot,
        format: RegisterCSVFormat = .semicolonUTF8
    ) throws -> Data {
        guard !snapshot.columns.isEmpty else {
            throw FinanceError.database("Für die Ausgabe ist keine Spalte sichtbar.")
        }
        let separator = format.separator
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        var lines = [
            line(["Bericht", snapshot.title], separator: separator),
            line(["Filter", snapshot.filterSummary], separator: separator),
            line(["Erstellt", formatter.string(from: snapshot.generatedAt)], separator: separator),
            "",
            line(snapshot.columns.map(\.title), separator: separator)
        ]
        lines.append(contentsOf: snapshot.rows.map { row in
            line(
                snapshot.columns.indices.map { index in
                    index < row.count ? row[index] : ""
                },
                separator: separator
            )
        })
        let text = lines.joined(separator: "\r\n") + "\r\n"
        guard let data = text.data(
            using: format.encoding,
            allowLossyConversion: false
        ) else {
            throw FinanceError.database(
                "Das Kontoblatt enthält Zeichen, die im gewählten CSV-Encoding nicht darstellbar sind."
            )
        }
        return data
    }

    private static func line(
        _ values: [String], separator: Character
    ) -> String {
        values.map { escape($0, separator: separator) }
            .joined(separator: String(separator))
    }

    private static func escape(
        _ value: String, separator: Character
    ) -> String {
        guard value.contains(separator)
                || value.contains("\"")
                || value.contains("\n")
                || value.contains("\r")
        else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

enum RegisterPDFExporter {
    static func data(
        snapshot: RegisterPrintSnapshot,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        guard !snapshot.columns.isEmpty else {
            throw FinanceError.database("Für die Ausgabe ist keine Spalte sichtbar.")
        }
        let portrait = CGSize(width: 595.28, height: 841.89)
        let size = orientation == .portrait
            ? portrait
            : CGSize(width: portrait.height, height: portrait.width)
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else {
            throw FinanceError.database("Der PDF-Datenstrom konnte nicht angelegt werden.")
        }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FinanceError.database("Der PDF-Kontext konnte nicht angelegt werden.")
        }
        RegisterPDFRenderer(
            context: context,
            pageSize: size,
            snapshot: snapshot
        ).render()
        context.closePDF()
        return mutableData as Data
    }
}

@MainActor
enum RegisterPrintService {
    static func printPDF(_ data: Data) throws {
        guard let document = PDFDocument(data: data) else {
            throw FinanceError.database("Das Kontoblatt-PDF ist ungültig.")
        }
        guard let operation = document.printOperation(
            for: NSPrintInfo.shared,
            scalingMode: .pageScaleDownToFit,
            autoRotate: true
        ) else {
            throw FinanceError.database("Der Druckdialog konnte nicht geöffnet werden.")
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}

private struct RegisterPDFRenderer {
    let context: CGContext
    let pageSize: CGSize
    let snapshot: RegisterPrintSnapshot

    private let margin: CGFloat = 30
    private let headerHeight: CGFloat = 86
    private let footerHeight: CGFloat = 28
    private let rowHeight: CGFloat = 21
    private let tableHeaderHeight: CGFloat = 23
    private let green = CGColor(red: 0.08, green: 0.38, blue: 0.20, alpha: 1)
    private let dark = CGColor(gray: 0.12, alpha: 1)
    private let secondary = CGColor(gray: 0.38, alpha: 1)
    private let stripe = CGColor(gray: 0.96, alpha: 1)

    func render() {
        let availableHeight = pageSize.height - headerHeight - footerHeight
            - tableHeaderHeight
        let rowsPerPage = max(1, Int(floor(availableHeight / rowHeight)))
        let pageCount = max(
            1,
            Int(ceil(Double(snapshot.rows.count) / Double(rowsPerPage)))
        )
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            drawPageHeader(pageNumber: pageIndex + 1, pageCount: pageCount)
            var y = headerHeight
            drawTableHeader(y: y)
            y += tableHeaderHeight
            let start = pageIndex * rowsPerPage
            let end = min(start + rowsPerPage, snapshot.rows.count)
            if start < end {
                for rowIndex in start..<end {
                    drawRow(
                        snapshot.rows[rowIndex],
                        y: y,
                        striped: rowIndex.isMultiple(of: 2)
                    )
                    y += rowHeight
                }
            }
            drawFooter(pageNumber: pageIndex + 1, pageCount: pageCount)
            context.endPDFPage()
        }
    }

    private var columnFrames: [CGRect] {
        let contentWidth = pageSize.width - 2 * margin
        let requested = snapshot.columns.map { max($0.minimumWidth, $0.idealWidth) }
        let scale = contentWidth / max(1, requested.reduce(0, +))
        var x = margin
        return requested.map { requestedWidth in
            let width = requestedWidth * scale
            defer { x += width }
            return CGRect(x: x, y: 0, width: width, height: 0)
        }
    }

    private func drawPageHeader(pageNumber: Int, pageCount: Int) {
        drawLine(
            snapshot.title,
            x: margin,
            top: 27,
            width: pageSize.width - 2 * margin - 160,
            fontSize: 18,
            bold: true,
            color: green
        )
        drawRightLine(
            "Seite \(pageNumber) von \(pageCount)",
            right: pageSize.width - margin,
            top: 31,
            width: 150,
            fontSize: 8.5,
            color: secondary
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        drawLine(
            "Filter: \(snapshot.filterSummary)",
            x: margin,
            top: 55,
            width: pageSize.width - 2 * margin - 180,
            fontSize: 8.2,
            color: secondary
        )
        drawRightLine(
            "Erstellt: \(formatter.string(from: snapshot.generatedAt))",
            right: pageSize.width - margin,
            top: 55,
            width: 175,
            fontSize: 8.2,
            color: secondary
        )
        context.setStrokeColor(green)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: margin, y: pageSize.height - 72))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: pageSize.height - 72))
        context.strokePath()
    }

    private func drawTableHeader(y: CGFloat) {
        context.setFillColor(green)
        context.fill(
            CGRect(
                x: margin,
                y: pageSize.height - y - tableHeaderHeight,
                width: pageSize.width - 2 * margin,
                height: tableHeaderHeight
            )
        )
        for (index, column) in snapshot.columns.enumerated() {
            let frame = columnFrames[index]
            drawCell(
                column.title,
                frame: frame,
                top: y + 7,
                fontSize: 7.5,
                bold: true,
                color: CGColor(gray: 1, alpha: 1),
                rightAligned: [.amount, .debit, .credit, .balance].contains(column)
            )
        }
    }

    private func drawRow(_ row: [String], y: CGFloat, striped: Bool) {
        if striped {
            context.setFillColor(stripe)
            context.fill(
                CGRect(
                    x: margin,
                    y: pageSize.height - y - rowHeight,
                    width: pageSize.width - 2 * margin,
                    height: rowHeight
                )
            )
        }
        for (index, column) in snapshot.columns.enumerated() {
            drawCell(
                index < row.count ? row[index] : "",
                frame: columnFrames[index],
                top: y + 6,
                fontSize: 7.2,
                bold: false,
                color: dark,
                rightAligned: [.amount, .debit, .credit, .balance].contains(column)
            )
        }
    }

    private func drawFooter(pageNumber: Int, pageCount: Int) {
        let top = pageSize.height - footerHeight + 5
        context.setStrokeColor(CGColor(gray: 0.78, alpha: 1))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: footerHeight + 5))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: footerHeight + 5))
        context.strokePath()
        drawLine(
            "FinanzVerwalter – Kontoblatt",
            x: margin,
            top: top,
            width: 250,
            fontSize: 7.2,
            color: secondary
        )
        drawRightLine(
            "Seite \(pageNumber) von \(pageCount)",
            right: pageSize.width - margin,
            top: top,
            width: 100,
            fontSize: 7.2,
            color: secondary
        )
    }

    private func drawCell(
        _ text: String,
        frame: CGRect,
        top: CGFloat,
        fontSize: CGFloat,
        bold: Bool,
        color: CGColor,
        rightAligned: Bool
    ) {
        if rightAligned {
            drawRightLine(
                text,
                right: frame.maxX - 4,
                top: top,
                width: frame.width - 8,
                fontSize: fontSize,
                bold: bold,
                color: color
            )
        } else {
            drawLine(
                text,
                x: frame.minX + 4,
                top: top,
                width: frame.width - 8,
                fontSize: fontSize,
                bold: bold,
                color: color
            )
        }
    }

    private func drawLine(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        fontSize: CGFloat,
        bold: Bool = false,
        color: CGColor
    ) {
        let line = truncatedLine(
            text,
            width: width,
            fontSize: fontSize,
            bold: bold,
            color: color
        )
        context.textPosition = CGPoint(x: x, y: pageSize.height - top - fontSize)
        CTLineDraw(line, context)
    }

    private func drawRightLine(
        _ text: String,
        right: CGFloat,
        top: CGFloat,
        width: CGFloat,
        fontSize: CGFloat,
        bold: Bool = false,
        color: CGColor
    ) {
        let line = truncatedLine(
            text,
            width: width,
            fontSize: fontSize,
            bold: bold,
            color: color
        )
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(
            x: max(right - width, right - lineWidth),
            y: pageSize.height - top - fontSize
        )
        CTLineDraw(line, context)
    }

    private func truncatedLine(
        _ text: String,
        width: CGFloat,
        fontSize: CGFloat,
        bold: Bool,
        color: CGColor
    ) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName(
                (bold ? "Helvetica-Bold" : "Helvetica") as CFString,
                fontSize,
                nil
            ),
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let original = CTLineCreateWithAttributedString(attributed)
        let ellipsis = CTLineCreateWithAttributedString(
            NSAttributedString(string: "…", attributes: attributes)
        )
        return CTLineCreateTruncatedLine(
            original,
            max(1, width),
            .end,
            ellipsis
        ) ?? original
    }
}

struct ReportPDFOptions: Equatable, Sendable {
    var orientation: ReportPDFOrientation = .landscape
}

enum TransactionReportPDFExporter {
    static func data(
        snapshot: TransactionReportSnapshot,
        metadata: ReportExportMetadata,
        options: ReportPDFOptions
    ) throws -> Data {
        let portrait = CGSize(width: 595.28, height: 841.89)
        let size = options.orientation == .portrait
            ? portrait
            : CGSize(width: portrait.height, height: portrait.width)
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else {
            throw FinanceError.database("Der PDF-Datenstrom konnte nicht angelegt werden.")
        }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FinanceError.database("Der PDF-Kontext konnte nicht angelegt werden.")
        }
        var renderer = ReportPDFRenderer(
            context: context,
            pageSize: size,
            snapshot: snapshot,
            metadata: metadata
        )
        renderer.render()
        context.closePDF()
        return mutableData as Data
    }
}

private struct ReportPDFRenderer {
    private enum TableKind {
        case groups
        case facts
        case totals
    }

    let context: CGContext
    let pageSize: CGSize
    let snapshot: TransactionReportSnapshot
    let metadata: ReportExportMetadata

    private let margin: CGFloat = 36
    private let footerHeight: CGFloat = 28
    private let green = CGColor(
        red: 0.08,
        green: 0.38,
        blue: 0.20,
        alpha: 1
    )
    private let lightGreen = CGColor(
        red: 0.92,
        green: 0.97,
        blue: 0.94,
        alpha: 1
    )
    private let stripe = CGColor(
        red: 0.96,
        green: 0.96,
        blue: 0.96,
        alpha: 1
    )
    private let dark = CGColor(gray: 0.12, alpha: 1)
    private let secondary = CGColor(gray: 0.38, alpha: 1)

    private var pageNumber = 0
    private var y: CGFloat = 0
    private var activeTable: TableKind = .facts

    init(
        context: CGContext,
        pageSize: CGSize,
        snapshot: TransactionReportSnapshot,
        metadata: ReportExportMetadata
    ) {
        self.context = context
        self.pageSize = pageSize
        self.snapshot = snapshot
        self.metadata = metadata
    }

    mutating func render() {
        let hasVisibleSection = !snapshot.groups.isEmpty
            || snapshot.presentation.includeDetailRows
            || snapshot.presentation.includeGrandTotals

        if !hasVisibleSection {
            beginPage(
                section: "Keine sichtbaren Berichtsbereiche",
                table: .facts,
                detailedHeader: true
            )
            endPage()
            return
        }

        if !snapshot.groups.isEmpty {
            beginPage(section: "Gruppierte Übersicht", table: .groups, detailedHeader: true)
            for (index, group) in snapshot.groups.enumerated() {
                ensureSpace(30, section: "Gruppierte Übersicht", table: .groups)
                drawGroup(group, striped: index.isMultiple(of: 2))
            }
            endPage()
        }

        if snapshot.presentation.includeDetailRows {
            beginPage(
                section: "Buchungen und Splitpositionen",
                table: .facts,
                detailedHeader: snapshot.groups.isEmpty
            )
            for (index, fact) in snapshot.facts.enumerated() {
                ensureSpace(22, section: "Buchungen und Splitpositionen", table: .facts)
                drawFact(fact, striped: index.isMultiple(of: 2))
            }
            endPage()
        }

        if snapshot.presentation.includeGrandTotals {
            beginPage(
                section: "Gesamtsummen",
                table: .totals,
                detailedHeader: snapshot.groups.isEmpty
                    && !snapshot.presentation.includeDetailRows
            )
            for (index, total) in snapshot.totals.enumerated() {
                ensureSpace(26, section: "Gesamtsummen", table: .totals)
                drawTotal(total, striped: index.isMultiple(of: 2))
            }
            endPage()
        }
    }

    private mutating func beginPage(
        section: String,
        table: TableKind,
        detailedHeader: Bool = false
    ) {
        pageNumber += 1
        activeTable = table
        context.beginPDFPage(nil)
        context.textMatrix = .identity

        drawLine(
            metadata.title,
            x: margin,
            top: 28,
            width: pageSize.width - 2 * margin - 180,
            fontSize: 18,
            bold: true,
            color: green
        )
        drawRightLine(
            metadata.dateLabel,
            right: pageSize.width - margin,
            top: 31,
            width: 175,
            fontSize: 9,
            color: secondary
        )

        if detailedHeader {
            drawLine(
                "Basiswährung: \(metadata.baseCurrency)   Erstellt: \(isoDateTime(metadata.generatedAt))",
                x: margin,
                top: 55,
                width: pageSize.width - 2 * margin,
                fontSize: 8.5,
                color: secondary
            )
            drawWrapped(
                "Filter: \(metadata.filterSummary)",
                x: margin,
                top: 70,
                width: pageSize.width - 2 * margin,
                height: 28,
                fontSize: 8.5,
                color: secondary
            )
            y = 105
        } else {
            y = 64
        }

        drawHorizontalLine(top: y - 5, color: green, width: 1)
        drawLine(
            section,
            x: margin,
            top: y + 5,
            width: pageSize.width - 2 * margin,
            fontSize: 12,
            bold: true,
            color: dark
        )
        y += 27
        drawTableHeader(table)
    }

    private mutating func endPage() {
        drawHorizontalLine(
            top: pageSize.height - footerHeight - 4,
            color: CGColor(gray: 0.78, alpha: 1),
            width: 0.5
        )
        drawLine(
            "FinanzVerwalter - \(metadata.title)",
            x: margin,
            top: pageSize.height - footerHeight + 4,
            width: pageSize.width - 2 * margin - 80,
            fontSize: 7.5,
            color: secondary
        )
        drawRightLine(
            "Seite \(pageNumber)",
            right: pageSize.width - margin,
            top: pageSize.height - footerHeight + 4,
            width: 70,
            fontSize: 7.5,
            color: secondary
        )
        context.endPDFPage()
    }

    private mutating func ensureSpace(
        _ height: CGFloat,
        section: String,
        table: TableKind
    ) {
        if y + height > pageSize.height - footerHeight - 8 {
            endPage()
            beginPage(section: section, table: table)
        }
    }

    private mutating func drawTableHeader(_ table: TableKind) {
        fillRect(
            CGRect(
                x: margin,
                y: y,
                width: pageSize.width - 2 * margin,
                height: 22
            ),
            color: green
        )
        switch table {
        case .groups:
            let columns = groupColumns
            drawHeaderCell("Gruppe", column: columns[0])
            drawHeaderCell("Anzahl", column: columns[1], rightAligned: true)
            drawHeaderCell("Einnahmen", column: columns[2], rightAligned: true)
            drawHeaderCell("Ausgaben", column: columns[3], rightAligned: true)
            drawHeaderCell("Saldo", column: columns[4], rightAligned: true)
            drawHeaderCell("Währung", column: columns[5])
        case .facts:
            let columns = factColumns
            for (index, detailColumn) in snapshot.presentation.detailColumns.enumerated() {
                drawHeaderCell(
                    detailColumn.title,
                    column: columns[index],
                    rightAligned: detailColumn.isNumeric
                )
            }
        case .totals:
            let columns = totalColumns
            for (index, title) in [
                "Währung", "Einnahmen", "Ausgaben", "Saldo"
            ].enumerated() {
                drawHeaderCell(
                    title,
                    column: columns[index],
                    rightAligned: index > 0
                )
            }
        }
        y += 22
    }

    private mutating func drawGroup(
        _ group: TransactionReportGroup,
        striped: Bool
    ) {
        if striped || group.level == .subtotal {
            fillRect(
                CGRect(
                    x: margin,
                    y: y,
                    width: pageSize.width - 2 * margin,
                    height: 30
                ),
                color: lightGreen
            )
        }
        let columns = groupColumns
        drawCell(
            group.label,
            column: columns[0],
            height: 30,
            fontSize: 8.5,
            bold: group.level == .subtotal
        )
        drawCell(
            "\(group.bookingCount)",
            column: columns[1],
            height: 30,
            fontSize: 8.5,
            rightAligned: true
        )
        drawCell(
            germanAmount(group.incomeMinor, currency: group.currency),
            column: columns[2],
            height: 30,
            fontSize: 8.5,
            rightAligned: true
        )
        drawCell(
            germanAmount(group.expenseMinor, currency: group.currency),
            column: columns[3],
            height: 30,
            fontSize: 8.5,
            rightAligned: true
        )
        drawCell(
            germanAmount(group.netMinor, currency: group.currency),
            column: columns[4],
            height: 30,
            fontSize: 8.5,
            rightAligned: true
        )
        drawCell(group.currency, column: columns[5], height: 30, fontSize: 8.5)
        y += 30
    }

    private mutating func drawFact(
        _ fact: TransactionReportFact,
        striped: Bool
    ) {
        if striped {
            fillRect(
                CGRect(
                    x: margin,
                    y: y,
                    width: pageSize.width - 2 * margin,
                    height: 22
                ),
                color: stripe
            )
        }
        let columns = factColumns
        let detailColumns = snapshot.presentation.detailColumns
        let fontSize: CGFloat = detailColumns.count > 9 ? 6.2
            : detailColumns.count > 7 ? 7.0 : 7.8
        for (index, detailColumn) in detailColumns.enumerated() {
            drawCell(
                detailColumn.exportText(for: fact),
                column: columns[index],
                height: 22,
                fontSize: fontSize,
                rightAligned: detailColumn.isNumeric
            )
        }
        y += 22
    }

    private mutating func drawTotal(
        _ total: TransactionReportCurrencyTotal,
        striped: Bool
    ) {
        if striped {
            fillRect(
                CGRect(
                    x: margin,
                    y: y,
                    width: pageSize.width - 2 * margin,
                    height: 26
                ),
                color: stripe
            )
        }
        let columns = totalColumns
        drawCell(
            total.currency,
            column: columns[0],
            height: 26,
            fontSize: 9,
            bold: true
        )
        for (index, amount) in [
            total.incomeMinor, total.expenseMinor, total.netMinor
        ].enumerated() {
            drawCell(
                germanAmount(amount, currency: total.currency),
                column: columns[index + 1],
                height: 26,
                fontSize: 9,
                rightAligned: true,
                bold: true
            )
        }
        y += 26
    }

    private var groupColumns: [CGRect] {
        let content = pageSize.width - 2 * margin
        let currency: CGFloat = 48
        let count: CGFloat = 52
        let money: CGFloat = 88
        let label = content - currency - count - 3 * money
        return horizontalColumns(
            widths: [label, count, money, money, money, currency]
        )
    }

    private var factColumns: [CGRect] {
        let content = pageSize.width - 2 * margin
        let detailColumns = snapshot.presentation.detailColumns
        let totalWeight = detailColumns.reduce(CGFloat.zero) {
            $0 + $1.widthWeight
        }
        return horizontalColumns(widths: detailColumns.map {
            content * $0.widthWeight / max(totalWeight, 1)
        })
    }

    private var totalColumns: [CGRect] {
        let content = pageSize.width - 2 * margin
        let currency: CGFloat = 90
        let money = (content - currency) / 3
        return horizontalColumns(widths: [currency, money, money, money])
    }

    private func horizontalColumns(widths: [CGFloat]) -> [CGRect] {
        var x = margin
        return widths.map { width in
            defer { x += width }
            return CGRect(x: x, y: 0, width: width, height: 0)
        }
    }

    private func drawHeaderCell(
        _ text: String,
        column: CGRect,
        rightAligned: Bool = false
    ) {
        if rightAligned {
            drawRightLine(
                text,
                right: column.maxX - 5,
                top: y + 6,
                width: column.width - 10,
                fontSize: 8,
                bold: true,
                color: CGColor(gray: 1, alpha: 1)
            )
        } else {
            drawLine(
                text,
                x: column.minX + 5,
                top: y + 6,
                width: column.width - 10,
                fontSize: 8,
                bold: true,
                color: CGColor(gray: 1, alpha: 1)
            )
        }
    }

    private func drawCell(
        _ text: String,
        column: CGRect,
        height: CGFloat,
        fontSize: CGFloat,
        rightAligned: Bool = false,
        bold: Bool = false
    ) {
        if rightAligned {
            drawRightLine(
                text,
                right: column.maxX - 5,
                top: y + (height - fontSize) / 2 - 1,
                width: column.width - 10,
                fontSize: fontSize,
                bold: bold,
                color: dark
            )
        } else {
            drawLine(
                text,
                x: column.minX + 5,
                top: y + (height - fontSize) / 2 - 1,
                width: column.width - 10,
                fontSize: fontSize,
                bold: bold,
                color: dark
            )
        }
    }

    private func drawLine(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        fontSize: CGFloat,
        bold: Bool = false,
        color: CGColor
    ) {
        let attributed = attributedString(
            text,
            fontSize: fontSize,
            bold: bold,
            color: color
        )
        let original = CTLineCreateWithAttributedString(attributed)
        let ellipsis = CTLineCreateWithAttributedString(
            attributedString("…", fontSize: fontSize, bold: bold, color: color)
        )
        let line = CTLineCreateTruncatedLine(original, max(1, width), .end, ellipsis)
            ?? original
        context.textPosition = CGPoint(x: x, y: pageSize.height - top - fontSize)
        CTLineDraw(line, context)
    }

    private func drawRightLine(
        _ text: String,
        right: CGFloat,
        top: CGFloat,
        width: CGFloat,
        fontSize: CGFloat,
        bold: Bool = false,
        color: CGColor
    ) {
        let attributed = attributedString(
            text,
            fontSize: fontSize,
            bold: bold,
            color: color
        )
        let original = CTLineCreateWithAttributedString(attributed)
        let ellipsis = CTLineCreateWithAttributedString(
            attributedString("…", fontSize: fontSize, bold: bold, color: color)
        )
        let line = CTLineCreateTruncatedLine(original, max(1, width), .end, ellipsis)
            ?? original
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(
            x: max(right - width, right - lineWidth),
            y: pageSize.height - top - fontSize
        )
        CTLineDraw(line, context)
    }

    private func drawWrapped(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        fontSize: CGFloat,
        color: CGColor
    ) {
        let attributed = attributedString(
            text,
            fontSize: fontSize,
            bold: false,
            color: color
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(
                x: x,
                y: pageSize.height - top - height,
                width: width,
                height: height
            ),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        CTFrameDraw(frame, context)
    }

    private func attributedString(
        _ text: String,
        fontSize: CGFloat,
        bold: Bool,
        color: CGColor
    ) -> CFAttributedString {
        let font = CTFontCreateWithName(
            (bold ? "Helvetica-Bold" : "Helvetica") as CFString,
            fontSize,
            nil
        )
        return NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
        ) as CFAttributedString
    }

    private func fillRect(_ topRect: CGRect, color: CGColor) {
        context.setFillColor(color)
        context.fill(
            CGRect(
                x: topRect.minX,
                y: pageSize.height - topRect.minY - topRect.height,
                width: topRect.width,
                height: topRect.height
            )
        )
    }

    private func drawHorizontalLine(top: CGFloat, color: CGColor, width: CGFloat) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        let pageY = pageSize.height - top
        context.move(to: CGPoint(x: margin, y: pageY))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: pageY))
        context.strokePath()
    }

    private func germanAmount(_ minorUnits: Int64, currency: String) -> String {
        Money(minorUnits: minorUnits, currency: currency).editingString
    }

    private func isoDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func isoDateTime(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()
}
