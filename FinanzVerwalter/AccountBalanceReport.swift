import CoreGraphics
import CoreText
import Foundation

struct AccountBalanceReportQuery: Codable, Equatable, Sendable {
    var asOf: Date
    var accountIDs: Set<UUID> = []
    var accountGroupIDs: Set<UUID> = []
    var currencies: Set<String> = []
    var includeHiddenAccounts = false
    var includeClosedAccounts = false
    var includeAccountsExcludedFromNetWorth = false
}

struct AccountBalanceReportRow: Identifiable, Equatable, Sendable {
    var id: UUID { accountID }
    let accountID: UUID
    let groupName: String
    let accountName: String
    let accountType: AccountType
    let currency: String
    let openingBalanceMinor: Int64
    let movementMinor: Int64
    let balanceMinor: Int64
    let isHidden: Bool
    let isClosed: Bool
    let includeNetWorth: Bool
}

struct AccountBalanceReportCurrencyTotal: Identifiable, Equatable, Sendable {
    var id: String { currency }
    let currency: String
    let assetsMinor: Int64
    let liabilitiesMinor: Int64
    let netWorthMinor: Int64
}

struct AccountBalanceReportSnapshot: Equatable, Sendable {
    let asOf: Date
    let rows: [AccountBalanceReportRow]
    let totals: [AccountBalanceReportCurrencyTotal]
}

enum AccountBalanceReportEngine {
    static func snapshot(
        query: AccountBalanceReportQuery,
        accounts: [FinanceAccount],
        accountGroups: [AccountGroup],
        transactions: [FinanceTransaction],
        calendar: Calendar = .current
    ) -> AccountBalanceReportSnapshot {
        let endOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: query.asOf)
        )?.addingTimeInterval(-0.001) ?? query.asOf
        let normalizedCurrencies = Set(query.currencies.map { $0.uppercased() })
        let groupsByID = Dictionary(uniqueKeysWithValues: accountGroups.map { ($0.id, $0) })
        let transactionsByAccount = Dictionary(grouping: transactions, by: \.accountID)

        let rows = accounts.compactMap { account -> AccountBalanceReportRow? in
            guard query.includeHiddenAccounts || !account.isHidden else { return nil }
            guard query.includeClosedAccounts || !account.isClosed else { return nil }
            guard query.includeAccountsExcludedFromNetWorth || account.includeNetWorth else {
                return nil
            }
            guard account.openingDate.map({ $0 <= endOfDay }) ?? true else { return nil }
            guard normalizedCurrencies.isEmpty
                || normalizedCurrencies.contains(account.currency.uppercased())
            else { return nil }
            if !query.accountIDs.isEmpty || !query.accountGroupIDs.isEmpty {
                guard query.accountIDs.contains(account.id)
                    || account.groupID.map(query.accountGroupIDs.contains) == true
                else { return nil }
            }
            let movement = transactionsByAccount[account.id, default: []]
                .filter { transaction in
                    transaction.status != .cancelled
                        && transaction.bookingDate <= endOfDay
                        && (account.openingDate.map {
                            transaction.bookingDate >= $0
                        } ?? true)
                        && transaction.currency.caseInsensitiveCompare(account.currency)
                            == .orderedSame
                }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
            return AccountBalanceReportRow(
                accountID: account.id,
                groupName: account.groupID.flatMap { groupsByID[$0]?.name }
                    ?? account.type.defaultGroupName,
                accountName: account.name,
                accountType: account.type,
                currency: account.currency.uppercased(),
                openingBalanceMinor: account.openingBalanceMinor,
                movementMinor: movement,
                balanceMinor: account.openingBalanceMinor + movement,
                isHidden: account.isHidden,
                isClosed: account.isClosed,
                includeNetWorth: account.includeNetWorth
            )
        }
        .sorted {
            if $0.groupName.localizedStandardCompare($1.groupName) != .orderedSame {
                return $0.groupName.localizedStandardCompare($1.groupName) == .orderedAscending
            }
            return $0.accountName.localizedStandardCompare($1.accountName) == .orderedAscending
        }

        let totals = Dictionary(grouping: rows, by: \.currency).map { currency, values in
            let assets = values.filter { $0.balanceMinor > 0 }
                .reduce(Int64.zero) { $0 + $1.balanceMinor }
            let signedLiabilities = values.filter { $0.balanceMinor < 0 }
                .reduce(Int64.zero) { $0 + $1.balanceMinor }
            return AccountBalanceReportCurrencyTotal(
                currency: currency,
                assetsMinor: assets,
                liabilitiesMinor: -signedLiabilities,
                netWorthMinor: assets + signedLiabilities
            )
        }
        .sorted { $0.currency < $1.currency }
        return AccountBalanceReportSnapshot(asOf: endOfDay, rows: rows, totals: totals)
    }
}

struct AccountBalanceReportExportMetadata: Equatable, Sendable {
    let title: String
    let filterSummary: String
    let generatedAt: Date
}

enum AccountBalanceReportCSVExporter {
    static func data(
        snapshot: AccountBalanceReportSnapshot,
        metadata: AccountBalanceReportExportMetadata
    ) -> Data {
        var lines = [
            csv(["Bericht", metadata.title]),
            csv(["Stichtag", date(snapshot.asOf)]),
            csv(["Filter", metadata.filterSummary]),
            csv(["Erstellt", timestamp(metadata.generatedAt)]),
            "",
            csv(["Gruppe", "Konto", "Kontotyp", "Eröffnung", "Bewegungen", "Saldo", "Währung"])
        ]
        lines.append(contentsOf: snapshot.rows.map { row in
            csv([
                row.groupName, row.accountName, row.accountType.title,
                decimal(row.openingBalanceMinor), decimal(row.movementMinor),
                decimal(row.balanceMinor), row.currency
            ])
        })
        lines.append("")
        lines.append(csv(["Währung", "Aktiva", "Passiva", "Nettovermögen"]))
        lines.append(contentsOf: snapshot.totals.map { total in
            csv([
                total.currency, decimal(total.assetsMinor),
                decimal(total.liabilitiesMinor), decimal(total.netWorthMinor)
            ])
        })
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func csv(_ values: [String]) -> String {
        values.map { value in
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return escaped.contains(";") || escaped.contains("\"")
                || escaped.contains("\n") || escaped.contains("\r")
                ? "\"\(escaped)\""
                : escaped
        }.joined(separator: ";")
    }

    private static func decimal(_ minor: Int64) -> String {
        let sign = minor < 0 ? "-" : ""
        let magnitude = minor.magnitude
        return "\(sign)\(magnitude / 100),\(String(format: "%02llu", magnitude % 100))"
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: value)
    }

    private static func timestamp(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: value)
    }
}

enum AccountBalanceReportPDFExporter {
    static func data(
        snapshot: AccountBalanceReportSnapshot,
        metadata: AccountBalanceReportExportMetadata,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        let portrait = CGSize(width: 595.28, height: 841.89)
        let pageSize = orientation == .portrait
            ? portrait
            : CGSize(width: portrait.height, height: portrait.width)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw FinanceError.database("Der PDF-Datenstrom konnte nicht angelegt werden.")
        }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw FinanceError.database("Der PDF-Kontext konnte nicht angelegt werden.")
        }
        AccountBalanceReportPDFRenderer(
            context: context,
            pageSize: pageSize,
            snapshot: snapshot,
            metadata: metadata
        ).render()
        context.closePDF()
        return data as Data
    }
}

private struct AccountBalanceReportPDFRenderer {
    let context: CGContext
    let pageSize: CGSize
    let snapshot: AccountBalanceReportSnapshot
    let metadata: AccountBalanceReportExportMetadata

    private let margin: CGFloat = 30
    private let headerHeight: CGFloat = 94
    private let tableHeaderHeight: CGFloat = 23
    private let rowHeight: CGFloat = 21
    private let footerHeight: CGFloat = 28
    private let green = CGColor(red: 0.08, green: 0.38, blue: 0.20, alpha: 1)
    private let dark = CGColor(gray: 0.12, alpha: 1)
    private let secondary = CGColor(gray: 0.38, alpha: 1)
    private let stripe = CGColor(gray: 0.96, alpha: 1)

    private var columns: [(String, CGFloat, Bool)] {
        [
            ("Gruppe", 1.15, false), ("Konto", 1.65, false),
            ("Kontotyp", 1.15, false), ("Eröffnung", 1.0, true),
            ("Bewegungen", 1.0, true), ("Saldo", 1.0, true),
            ("Währung", 0.62, false)
        ]
    }

    private var tableRows: [[String]] {
        var values = snapshot.rows.map { row in
            [
                row.groupName, row.accountName, row.accountType.title,
                money(row.openingBalanceMinor, currency: row.currency),
                money(row.movementMinor, currency: row.currency),
                money(row.balanceMinor, currency: row.currency), row.currency
            ]
        }
        for total in snapshot.totals {
            values.append([
                "", "Nettovermögen \(total.currency)", "Aktiva",
                "", "", money(total.assetsMinor, currency: total.currency), total.currency
            ])
            values.append([
                "", "", "Passiva", "", "",
                money(total.liabilitiesMinor, currency: total.currency), total.currency
            ])
            values.append([
                "", "", "Netto", "", "",
                money(total.netWorthMinor, currency: total.currency), total.currency
            ])
        }
        return values
    }

    func render() {
        let rows = tableRows
        let available = pageSize.height - headerHeight - tableHeaderHeight - footerHeight
        let rowsPerPage = max(1, Int(floor(available / rowHeight)))
        let pageCount = max(1, Int(ceil(Double(rows.count) / Double(rowsPerPage))))
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            drawHeader(page: page + 1, pageCount: pageCount)
            drawTableHeader(top: headerHeight)
            let start = page * rowsPerPage
            let end = min(start + rowsPerPage, rows.count)
            var top = headerHeight + tableHeaderHeight
            if start < end {
                for index in start..<end {
                    drawRow(rows[index], top: top, striped: index.isMultiple(of: 2))
                    top += rowHeight
                }
            }
            drawFooter(page: page + 1, pageCount: pageCount)
            context.endPDFPage()
        }
    }

    private var columnFrames: [CGRect] {
        let available = pageSize.width - 2 * margin
        let totalWeight = columns.reduce(CGFloat.zero) { $0 + $1.1 }
        var x = margin
        return columns.map { column in
            let width = available * column.1 / totalWeight
            defer { x += width }
            return CGRect(x: x, y: 0, width: width, height: 0)
        }
    }

    private func drawHeader(page: Int, pageCount: Int) {
        draw(metadata.title, x: margin, top: 25, width: pageSize.width - 220,
             size: 18, bold: true, color: green)
        drawRight("Seite \(page) von \(pageCount)", right: pageSize.width - margin,
                  top: 30, width: 140, size: 8.5, color: secondary)
        let day = DateFormatter()
        day.locale = Locale(identifier: "de_DE")
        day.dateStyle = .medium
        day.timeStyle = .none
        draw("Stichtag: \(day.string(from: snapshot.asOf)) · \(metadata.filterSummary)",
             x: margin, top: 54, width: pageSize.width - 220,
             size: 8.2, color: secondary)
        let timestamp = DateFormatter()
        timestamp.locale = Locale(identifier: "de_DE")
        timestamp.dateStyle = .medium
        timestamp.timeStyle = .short
        drawRight("Erstellt: \(timestamp.string(from: metadata.generatedAt))",
                  right: pageSize.width - margin, top: 54,
                  width: 185, size: 8.2, color: secondary)
        draw("Fremdwährungen werden ohne FX-Kurs getrennt ausgewiesen.",
             x: margin, top: 72, width: pageSize.width - 2 * margin,
             size: 7.8, color: secondary)
    }

    private func drawTableHeader(top: CGFloat) {
        context.setFillColor(green)
        context.fill(CGRect(x: margin, y: pageSize.height - top - tableHeaderHeight,
                            width: pageSize.width - 2 * margin, height: tableHeaderHeight))
        for index in columns.indices {
            drawCell(columns[index].0, frame: columnFrames[index], top: top + 7,
                     size: 7.4, bold: true, color: CGColor(gray: 1, alpha: 1),
                     rightAligned: columns[index].2)
        }
    }

    private func drawRow(_ values: [String], top: CGFloat, striped: Bool) {
        if striped {
            context.setFillColor(stripe)
            context.fill(CGRect(x: margin, y: pageSize.height - top - rowHeight,
                                width: pageSize.width - 2 * margin, height: rowHeight))
        }
        for index in columns.indices {
            drawCell(index < values.count ? values[index] : "", frame: columnFrames[index],
                     top: top + 6, size: 7.1, bold: false, color: dark,
                     rightAligned: columns[index].2)
        }
    }

    private func drawFooter(page: Int, pageCount: Int) {
        let top = pageSize.height - footerHeight + 5
        context.setStrokeColor(CGColor(gray: 0.78, alpha: 1))
        context.move(to: CGPoint(x: margin, y: footerHeight + 5))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: footerHeight + 5))
        context.strokePath()
        draw("FinanzVerwalter – Kontosalden und Nettovermögen", x: margin,
             top: top, width: 320, size: 7.2, color: secondary)
        drawRight("Seite \(page) von \(pageCount)", right: pageSize.width - margin,
                  top: top, width: 110, size: 7.2, color: secondary)
    }

    private func drawCell(
        _ value: String, frame: CGRect, top: CGFloat, size: CGFloat,
        bold: Bool, color: CGColor, rightAligned: Bool
    ) {
        if rightAligned {
            drawRight(value, right: frame.maxX - 4, top: top,
                      width: frame.width - 8, size: size, bold: bold, color: color)
        } else {
            draw(value, x: frame.minX + 4, top: top,
                 width: frame.width - 8, size: size, bold: bold, color: color)
        }
    }

    private func draw(
        _ value: String, x: CGFloat, top: CGFloat, width: CGFloat,
        size: CGFloat, bold: Bool = false, color: CGColor
    ) {
        let line = line(value, width: width, size: size, bold: bold, color: color)
        context.textPosition = CGPoint(x: x, y: pageSize.height - top - size)
        CTLineDraw(line, context)
    }

    private func drawRight(
        _ value: String, right: CGFloat, top: CGFloat, width: CGFloat,
        size: CGFloat, bold: Bool = false, color: CGColor
    ) {
        let line = line(value, width: width, size: size, bold: bold, color: color)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: max(right - width, right - lineWidth),
                                       y: pageSize.height - top - size)
        CTLineDraw(line, context)
    }

    private func line(
        _ value: String, width: CGFloat, size: CGFloat,
        bold: Bool, color: CGColor
    ) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName(
                (bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil
            ),
            .foregroundColor: color
        ]
        let original = CTLineCreateWithAttributedString(
            NSAttributedString(string: value, attributes: attributes)
        )
        let ellipsis = CTLineCreateWithAttributedString(
            NSAttributedString(string: "…", attributes: attributes)
        )
        return CTLineCreateTruncatedLine(original, max(1, width), .end, ellipsis) ?? original
    }

    private func money(_ minor: Int64, currency: String) -> String {
        Money(minorUnits: minor, currency: currency).formatted
    }
}
