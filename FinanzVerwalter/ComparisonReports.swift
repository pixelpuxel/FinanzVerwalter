import CoreGraphics
import CoreText
import Foundation

enum PeriodComparisonMetric: String, CaseIterable, Identifiable, Sendable {
    case income
    case expense
    case net

    var id: Self { self }

    var title: String {
        switch self {
        case .income: "Einnahmen"
        case .expense: "Ausgaben"
        case .net: "Saldo"
        }
    }
}

enum PeriodComparisonReferenceMode: String, CaseIterable, Identifiable, Sendable {
    case total
    case monthlyAverage

    var id: Self { self }

    var title: String {
        switch self {
        case .total: "Vergleichssumme"
        case .monthlyAverage: "Monatsdurchschnitt"
        }
    }
}

struct PeriodComparisonQuery: Equatable, Sendable {
    var currentFrom: Date
    var currentThrough: Date
    var referenceFrom: Date
    var referenceThrough: Date
    var grouping: ReportGrouping = .category
    var metric: PeriodComparisonMetric = .expense
    var referenceMode: PeriodComparisonReferenceMode = .total
    var baseQuery = TransactionReportQuery(dateFrom: nil, dateThrough: nil)
}

struct PeriodComparisonRow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let currency: String
    let currentMinor: Int64
    let referenceMinor: Int64
    let differenceMinor: Int64
    let percentBasisPoints: Int64?
    let currentFactIDs: Set<String>
    let referenceFactIDs: Set<String>
}

struct PeriodComparisonSnapshot: Equatable, Sendable {
    let currentFrom: Date
    let currentThrough: Date
    let referenceFrom: Date
    let referenceThrough: Date
    let metric: PeriodComparisonMetric
    let rows: [PeriodComparisonRow]
    let currentFacts: [TransactionReportFact]
    let referenceFacts: [TransactionReportFact]

    var totals: [PeriodComparisonCurrencyTotal] {
        Dictionary(grouping: rows, by: \.currency).map { currency, values in
            let current = values.reduce(Int64.zero) { $0 + $1.currentMinor }
            let reference = values.reduce(Int64.zero) { $0 + $1.referenceMinor }
            let difference = current - reference
            return PeriodComparisonCurrencyTotal(
                currency: currency, currentMinor: current,
                referenceMinor: reference, differenceMinor: difference,
                percentBasisPoints: reference == 0 ? nil
                    : NSDecimalNumber(decimal: Decimal(difference) * 10_000 / Decimal(reference))
                        .rounding(accordingToBehavior: NSDecimalNumberHandler(
                            roundingMode: .plain, scale: 0, raiseOnExactness: false,
                            raiseOnOverflow: true, raiseOnUnderflow: true,
                            raiseOnDivideByZero: true
                        )).int64Value
            )
        }.sorted { $0.currency < $1.currency }
    }
}

struct PeriodComparisonCurrencyTotal: Identifiable, Equatable, Sendable {
    var id: String { currency }
    let currency: String
    let currentMinor: Int64
    let referenceMinor: Int64
    let differenceMinor: Int64
    let percentBasisPoints: Int64?
}

enum PeriodComparisonEngine {
    static func snapshot(
        query: PeriodComparisonQuery,
        transactions: [FinanceTransaction],
        accounts: [FinanceAccount],
        categories: [FinanceCategory],
        tags: [FinanceTag],
        calendar: Calendar = .current
    ) -> PeriodComparisonSnapshot {
        var currentQuery = query.baseQuery
        currentQuery.dateFrom = min(query.currentFrom, query.currentThrough)
        currentQuery.dateThrough = max(query.currentFrom, query.currentThrough)
        currentQuery.grouping = query.grouping
        currentQuery.secondaryGrouping = nil
        currentQuery.sort = .labelAscending
        var referenceQuery = currentQuery
        referenceQuery.dateFrom = min(query.referenceFrom, query.referenceThrough)
        referenceQuery.dateThrough = max(query.referenceFrom, query.referenceThrough)

        let current = TransactionReportEngine.snapshot(
            query: currentQuery, transactions: transactions, accounts: accounts,
            categories: categories, tags: tags
        )
        let reference = TransactionReportEngine.snapshot(
            query: referenceQuery, transactions: transactions, accounts: accounts,
            categories: categories, tags: tags
        )
        let currentValues = values(snapshot: current, grouping: query.grouping, metric: query.metric)
        let referenceValues = values(
            snapshot: reference, grouping: query.grouping, metric: query.metric
        )
        let referenceDivisor = query.referenceMode == .monthlyAverage
            ? monthCount(
                from: referenceQuery.dateFrom!, through: referenceQuery.dateThrough!,
                calendar: calendar
            )
            : 1
        let keys = Set(currentValues.keys).union(referenceValues.keys)
        let rows = keys.map { key in
            let currentValue = currentValues[key]
            let referenceValue = referenceValues[key]
            let currentMinor = currentValue?.amountMinor ?? 0
            let referenceMinor = divided(
                referenceValue?.amountMinor ?? 0, by: referenceDivisor
            )
            let difference = currentMinor - referenceMinor
            return PeriodComparisonRow(
                id: key,
                label: currentValue?.label ?? referenceValue?.label ?? "Ohne Zuordnung",
                currency: currentValue?.currency ?? referenceValue?.currency ?? "EUR",
                currentMinor: currentMinor,
                referenceMinor: referenceMinor,
                differenceMinor: difference,
                percentBasisPoints: percentBasisPoints(
                    difference: difference, reference: referenceMinor
                ),
                currentFactIDs: currentValue?.factIDs ?? [],
                referenceFactIDs: referenceValue?.factIDs ?? []
            )
        }
        .sorted {
            let comparison = $0.label.localizedCaseInsensitiveCompare($1.label)
            return comparison == .orderedSame ? $0.currency < $1.currency : comparison == .orderedAscending
        }
        return PeriodComparisonSnapshot(
            currentFrom: currentQuery.dateFrom!, currentThrough: currentQuery.dateThrough!,
            referenceFrom: referenceQuery.dateFrom!, referenceThrough: referenceQuery.dateThrough!,
            metric: query.metric, rows: rows,
            currentFacts: current.facts, referenceFacts: reference.facts
        )
    }

    private struct Value {
        let label: String
        let currency: String
        let amountMinor: Int64
        let factIDs: Set<String>
    }

    private static func values(
        snapshot: TransactionReportSnapshot,
        grouping: ReportGrouping,
        metric: PeriodComparisonMetric
    ) -> [String: Value] {
        if grouping == .none {
            return Dictionary(uniqueKeysWithValues: snapshot.totals.map { total in
                let key = "Gesamt\u{1F}\(total.currency)"
                return (key, Value(
                    label: "Gesamt", currency: total.currency,
                    amountMinor: amount(total, metric: metric),
                    factIDs: Set(snapshot.facts.filter { $0.currency == total.currency }.map(\.id))
                ))
            })
        }
        return Dictionary(uniqueKeysWithValues: snapshot.groups.map { group in
            (group.id, Value(
                label: group.label, currency: group.currency,
                amountMinor: amount(group, metric: metric), factIDs: group.factIDs
            ))
        })
    }

    private static func amount(
        _ group: TransactionReportGroup, metric: PeriodComparisonMetric
    ) -> Int64 {
        switch metric {
        case .income: group.incomeMinor
        case .expense: group.expenseMinor
        case .net: group.netMinor
        }
    }

    private static func amount(
        _ total: TransactionReportCurrencyTotal, metric: PeriodComparisonMetric
    ) -> Int64 {
        switch metric {
        case .income: total.incomeMinor
        case .expense: total.expenseMinor
        case .net: total.netMinor
        }
    }

    private static func percentBasisPoints(
        difference: Int64, reference: Int64
    ) -> Int64? {
        guard reference != 0 else { return nil }
        let result = Decimal(difference) * 10_000 / Decimal(reference)
        return NSDecimalNumber(decimal: result).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain, scale: 0, raiseOnExactness: false,
                raiseOnOverflow: true, raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            )
        ).int64Value
    }

    private static func monthCount(
        from: Date, through: Date, calendar: Calendar
    ) -> Int64 {
        let start = calendar.dateInterval(of: .month, for: from)?.start ?? from
        let end = calendar.dateInterval(of: .month, for: through)?.start ?? through
        return Int64((calendar.dateComponents([.month], from: start, to: end).month ?? 0) + 1)
    }

    private static func divided(_ value: Int64, by divisor: Int64) -> Int64 {
        guard divisor > 1 else { return value }
        return NSDecimalNumber(decimal: Decimal(value) / Decimal(divisor)).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain, scale: 0, raiseOnExactness: false,
                raiseOnOverflow: true, raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            )
        ).int64Value
    }
}

struct BudgetReportQuery: Equatable, Sendable {
    var monthKeys: Set<String> = []
    var includeZeroRows = false
}

struct BudgetReportRow: Identifiable, Equatable, Sendable {
    var id: UUID { categoryID }
    let categoryID: UUID
    let categoryPath: String
    let kind: CategoryKind
    let currency: String
    let plannedMinor: Int64
    let actualMinor: Int64
    let varianceMinor: Int64
    let completionBasisPoints: Int64?
    let factIDs: Set<String>
}

struct BudgetReportSnapshot: Equatable, Sendable {
    let budget: FinanceBudget
    let includedMonths: [Date]
    let rows: [BudgetReportRow]
    let facts: [TransactionReportFact]

    var plannedIncomeMinor: Int64 {
        rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.plannedMinor }
    }

    var actualIncomeMinor: Int64 {
        rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.actualMinor }
    }

    var plannedExpenseMinor: Int64 {
        rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.plannedMinor }
    }

    var actualExpenseMinor: Int64 {
        rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.actualMinor }
    }
}

enum BudgetReportEngine {
    static func snapshot(
        budget: FinanceBudget,
        query: BudgetReportQuery,
        lines: [BudgetLine],
        transactions: [FinanceTransaction],
        accounts: [FinanceAccount],
        categories: [FinanceCategory],
        tags: [FinanceTag],
        calendar: Calendar = .current
    ) -> BudgetReportSnapshot {
        let allMonths = budget.months(calendar: calendar)
        let includedMonths = query.monthKeys.isEmpty
            ? allMonths
            : allMonths.filter { query.monthKeys.contains(monthKey($0, calendar: calendar)) }
        guard let first = includedMonths.first, let last = includedMonths.last else {
            return BudgetReportSnapshot(budget: budget, includedMonths: [], rows: [], facts: [])
        }
        let from = calendar.startOfDay(for: first)
        let through = calendar.date(
            byAdding: .month, value: 1,
            to: calendar.dateInterval(of: .month, for: last)?.start ?? last
        )?.addingTimeInterval(-0.001) ?? last
        let monthKeys = Set(includedMonths.map { monthKey($0, calendar: calendar) })
        let accountIDs = Set(accounts.filter {
            $0.includeBudget && !$0.isClosed
                && $0.currency.caseInsensitiveCompare(budget.currency) == .orderedSame
        }.map(\.id))
        let report = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(
                dateFrom: from, dateThrough: through, accountIDs: accountIDs,
                statuses: Set(TransactionStatus.allCases.filter { $0 != .cancelled }),
                currencies: [budget.currency.uppercased()], includeTransfers: false,
                expandSplits: true, grouping: .category, sort: .labelAscending
            ),
            transactions: transactions.filter { accountIDs.contains($0.accountID) },
            accounts: accounts,
            categories: categories, tags: tags
        )
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let factsByCategory = Dictionary(grouping: report.facts.compactMap { fact in
            fact.categoryID.map { ($0, fact) }
        }, by: { $0.0 }).mapValues { $0.map(\.1) }
        let plannedByCategory = Dictionary(grouping: lines.filter {
            $0.budgetID == budget.id
                && monthKeys.contains(String(format: "%04d-%02d", $0.year, $0.month))
        }, by: \.categoryID).mapValues { values in
            values.reduce(Int64.zero) { $0 + $1.plannedMinor }
        }
        let rows = categories.compactMap { category -> BudgetReportRow? in
            guard category.isActive, category.isBudgetable, category.kind != .transfer else {
                return nil
            }
            let facts = factsByCategory[category.id, default: []]
            let signedActual = facts.reduce(Int64.zero) { $0 + $1.amountMinor }
            let actual = category.kind == .expense ? abs(signedActual) : signedActual
            let planned = plannedByCategory[category.id] ?? 0
            guard query.includeZeroRows || planned != 0 || actual != 0 else { return nil }
            let variance = actual - planned
            return BudgetReportRow(
                categoryID: category.id,
                categoryPath: hierarchyPath(category.id, categoriesByID: categoryByID),
                kind: category.kind, currency: budget.currency.uppercased(),
                plannedMinor: planned, actualMinor: actual,
                varianceMinor: variance,
                completionBasisPoints: planned == 0
                    ? nil : roundedBasisPoints(numerator: actual, denominator: planned),
                factIDs: Set(facts.map(\.id))
            )
        }
        .sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.categoryPath.localizedCaseInsensitiveCompare($1.categoryPath)
                == .orderedAscending
        }
        return BudgetReportSnapshot(
            budget: budget, includedMonths: includedMonths, rows: rows, facts: report.facts
        )
    }

    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func roundedBasisPoints(numerator: Int64, denominator: Int64) -> Int64 {
        let result = Decimal(numerator) * 10_000 / Decimal(denominator)
        return NSDecimalNumber(decimal: result).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain, scale: 0, raiseOnExactness: false,
                raiseOnOverflow: true, raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            )
        ).int64Value
    }

    private static func hierarchyPath(
        _ id: UUID, categoriesByID: [UUID: FinanceCategory]
    ) -> String {
        guard let category = categoriesByID[id] else { return "Nicht zugeordnet" }
        var names = [category.name]
        var current = category.parentID
        var visited = Set([id])
        while let currentID = current,
              visited.insert(currentID).inserted,
              let parent = categoriesByID[currentID] {
            names.insert(parent.name, at: 0)
            current = parent.parentID
        }
        return names.joined(separator: " › ")
    }
}

struct ComparisonReportExportMetadata: Equatable, Sendable {
    let title: String
    let currentLabel: String
    let referenceLabel: String
    let generatedAt: Date
}

enum ComparisonReportCSVExporter {
    static func periodData(
        snapshot: PeriodComparisonSnapshot,
        metadata: ComparisonReportExportMetadata
    ) -> Data {
        var lines = metadataLines(metadata)
        lines.append("")
        lines.append(csv(["Gruppe", metadata.currentLabel, metadata.referenceLabel,
                          "Abweichung", "Abweichung %", "Währung"]))
        lines.append(contentsOf: snapshot.rows.map { row in
            csv([row.label, decimal(row.currentMinor), decimal(row.referenceMinor),
                 decimal(row.differenceMinor), percent(row.percentBasisPoints), row.currency])
        })
        lines.append("")
        lines.append(csv(["Gesamtsumme", metadata.currentLabel, metadata.referenceLabel,
                          "Abweichung", "Abweichung %", "Währung"]))
        lines.append(contentsOf: snapshot.totals.map { total in
            csv(["Gesamt", decimal(total.currentMinor), decimal(total.referenceMinor),
                 decimal(total.differenceMinor), percent(total.percentBasisPoints),
                 total.currency])
        })
        return data(lines)
    }

    static func budgetData(
        snapshot: BudgetReportSnapshot,
        metadata: ComparisonReportExportMetadata
    ) -> Data {
        var lines = metadataLines(metadata)
        lines.append("")
        lines.append(csv(["Kategorie", "Art", "Plan", "Ist", "Abweichung",
                          "Zielerreichung %", "Währung"]))
        lines.append(contentsOf: snapshot.rows.map { row in
            csv([row.categoryPath, row.kind == .income ? "Einnahme" : "Ausgabe",
                 decimal(row.plannedMinor), decimal(row.actualMinor),
                 decimal(row.varianceMinor), percent(row.completionBasisPoints), row.currency])
        })
        lines.append("")
        lines.append(csv(["Gesamtsumme", "Art", "Plan", "Ist", "Abweichung",
                          "Zielerreichung %", "Währung"]))
        lines.append(csv([
            "Gesamt", "Einnahmen", decimal(snapshot.plannedIncomeMinor),
            decimal(snapshot.actualIncomeMinor),
            decimal(snapshot.actualIncomeMinor - snapshot.plannedIncomeMinor), "",
            snapshot.budget.currency.uppercased()
        ]))
        lines.append(csv([
            "Gesamt", "Ausgaben", decimal(snapshot.plannedExpenseMinor),
            decimal(snapshot.actualExpenseMinor),
            decimal(snapshot.actualExpenseMinor - snapshot.plannedExpenseMinor), "",
            snapshot.budget.currency.uppercased()
        ]))
        return data(lines)
    }

    private static func metadataLines(_ metadata: ComparisonReportExportMetadata) -> [String] {
        [csv(["Bericht", metadata.title]), csv(["Aktueller Zeitraum", metadata.currentLabel]),
         csv(["Vergleich", metadata.referenceLabel]),
         csv(["Erstellt", ISO8601DateFormatter().string(from: metadata.generatedAt)])]
    }

    private static func data(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func csv(_ values: [String]) -> String {
        values.map { value in
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return escaped.contains(";") || escaped.contains("\"")
                || escaped.contains("\n") || escaped.contains("\r")
                ? "\"\(escaped)\"" : escaped
        }.joined(separator: ";")
    }

    private static func decimal(_ minor: Int64) -> String {
        let sign = minor < 0 ? "-" : ""
        let magnitude = minor.magnitude
        return "\(sign)\(magnitude / 100),\(String(format: "%02llu", magnitude % 100))"
    }

    private static func percent(_ basisPoints: Int64?) -> String {
        guard let basisPoints else { return "" }
        return decimal(basisPoints)
    }
}

enum ComparisonReportPDFExporter {
    static func periodData(
        snapshot: PeriodComparisonSnapshot,
        metadata: ComparisonReportExportMetadata,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        try data(
            rows: snapshot.rows.map { row in
                [row.label, money(row.currentMinor, row.currency),
                 money(row.referenceMinor, row.currency), money(row.differenceMinor, row.currency),
                 percent(row.percentBasisPoints), row.currency]
            } + snapshot.totals.map { total in
                ["Gesamt", money(total.currentMinor, total.currency),
                 money(total.referenceMinor, total.currency),
                 money(total.differenceMinor, total.currency),
                 percent(total.percentBasisPoints), total.currency]
            },
            headers: ["Gruppe", metadata.currentLabel, metadata.referenceLabel,
                      "Abweichung", "%", "Währung"], metadata: metadata,
            orientation: orientation
        )
    }

    static func budgetData(
        snapshot: BudgetReportSnapshot,
        metadata: ComparisonReportExportMetadata,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        try data(
            rows: snapshot.rows.map { row in
                [row.categoryPath, row.kind == .income ? "Einnahme" : "Ausgabe",
                 money(row.plannedMinor, row.currency), money(row.actualMinor, row.currency),
                 money(row.varianceMinor, row.currency), percent(row.completionBasisPoints),
                 row.currency]
            } + [
                ["Gesamt", "Einnahmen", money(snapshot.plannedIncomeMinor, snapshot.budget.currency),
                 money(snapshot.actualIncomeMinor, snapshot.budget.currency),
                 money(snapshot.actualIncomeMinor - snapshot.plannedIncomeMinor,
                       snapshot.budget.currency), "", snapshot.budget.currency.uppercased()],
                ["Gesamt", "Ausgaben", money(snapshot.plannedExpenseMinor, snapshot.budget.currency),
                 money(snapshot.actualExpenseMinor, snapshot.budget.currency),
                 money(snapshot.actualExpenseMinor - snapshot.plannedExpenseMinor,
                       snapshot.budget.currency), "", snapshot.budget.currency.uppercased()]
            ],
            headers: ["Kategorie", "Art", "Plan", "Ist", "Abweichung", "%", "Währung"],
            metadata: metadata, orientation: orientation
        )
    }

    private static func data(
        rows: [[String]], headers: [String],
        metadata: ComparisonReportExportMetadata,
        orientation: ReportPDFOrientation
    ) throws -> Data {
        let portrait = CGSize(width: 595.28, height: 841.89)
        let pageSize = orientation == .portrait
            ? portrait : CGSize(width: portrait.height, height: portrait.width)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw FinanceError.database("Der PDF-Datenstrom konnte nicht angelegt werden.")
        }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw FinanceError.database("Der PDF-Kontext konnte nicht angelegt werden.")
        }
        ComparisonReportPDFRenderer(
            context: context, pageSize: pageSize, headers: headers,
            rows: rows, metadata: metadata
        ).render()
        context.closePDF()
        return output as Data
    }

    private static func money(_ minor: Int64, _ currency: String) -> String {
        Money(minorUnits: minor, currency: currency).formatted
    }

    private static func percent(_ basisPoints: Int64?) -> String {
        guard let basisPoints else { return "–" }
        let sign = basisPoints < 0 ? "-" : ""
        let magnitude = basisPoints.magnitude
        return "\(sign)\(magnitude / 100),\(String(format: "%02llu", magnitude % 100)) %"
    }
}

private struct ComparisonReportPDFRenderer {
    let context: CGContext
    let pageSize: CGSize
    let headers: [String]
    let rows: [[String]]
    let metadata: ComparisonReportExportMetadata

    private let margin: CGFloat = 30
    private let headerHeight: CGFloat = 94
    private let tableHeaderHeight: CGFloat = 23
    private let rowHeight: CGFloat = 21
    private let footerHeight: CGFloat = 28

    func render() {
        let available = pageSize.height - headerHeight - tableHeaderHeight - footerHeight
        let rowsPerPage = max(1, Int(available / rowHeight))
        let pageCount = max(1, Int(ceil(Double(rows.count) / Double(rowsPerPage))))
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            draw(metadata.title, x: margin, top: 25, width: pageSize.width - 210,
                 size: 18, bold: true, color: green)
            drawRight("Seite \(page + 1) von \(pageCount)", right: pageSize.width - margin,
                      top: 30, width: 140, size: 8.2, color: secondary)
            draw("\(metadata.currentLabel) · Vergleich: \(metadata.referenceLabel)",
                 x: margin, top: 55, width: pageSize.width - 2 * margin,
                 size: 8.2, color: secondary)
            drawTableHeader()
            let start = page * rowsPerPage
            let end = min(start + rowsPerPage, rows.count)
            var top = headerHeight + tableHeaderHeight
            if start < end {
                for index in start..<end {
                    drawRow(rows[index], top: top, striped: index.isMultiple(of: 2))
                    top += rowHeight
                }
            }
            draw("FinanzVerwalter – \(metadata.title)", x: margin,
                 top: pageSize.height - footerHeight + 5, width: 400,
                 size: 7.2, color: secondary)
            context.endPDFPage()
        }
    }

    private var frames: [CGRect] {
        let available = pageSize.width - 2 * margin
        let firstWeight: CGFloat = headers.count == 7 ? 2.2 : 2.5
        let weights = [firstWeight] + Array(repeating: CGFloat(1), count: max(0, headers.count - 1))
        let total = weights.reduce(0, +)
        var x = margin
        return weights.map { weight in
            let width = available * weight / total
            defer { x += width }
            return CGRect(x: x, y: 0, width: width, height: 0)
        }
    }

    private func drawTableHeader() {
        context.setFillColor(green)
        context.fill(CGRect(x: margin, y: pageSize.height - headerHeight - tableHeaderHeight,
                            width: pageSize.width - 2 * margin, height: tableHeaderHeight))
        for index in headers.indices {
            drawCell(headers[index], index: index, top: headerHeight + 7,
                     bold: true, color: CGColor(gray: 1, alpha: 1))
        }
    }

    private func drawRow(_ row: [String], top: CGFloat, striped: Bool) {
        if striped {
            context.setFillColor(CGColor(gray: 0.96, alpha: 1))
            context.fill(CGRect(x: margin, y: pageSize.height - top - rowHeight,
                                width: pageSize.width - 2 * margin, height: rowHeight))
        }
        for index in headers.indices {
            drawCell(index < row.count ? row[index] : "", index: index,
                     top: top + 6, bold: false, color: CGColor(gray: 0.12, alpha: 1))
        }
    }

    private func drawCell(
        _ value: String, index: Int, top: CGFloat, bold: Bool, color: CGColor
    ) {
        let frame = frames[index]
        let rightAligned = index > (headers.count == 7 ? 1 : 0) && index < headers.count - 1
        if rightAligned {
            drawRight(value, right: frame.maxX - 4, top: top, width: frame.width - 8,
                      size: 7.1, bold: bold, color: color)
        } else {
            draw(value, x: frame.minX + 4, top: top, width: frame.width - 8,
                 size: 7.1, bold: bold, color: color)
        }
    }

    private var green: CGColor {
        CGColor(red: 0.08, green: 0.38, blue: 0.20, alpha: 1)
    }

    private var secondary: CGColor { CGColor(gray: 0.38, alpha: 1) }

    private func draw(
        _ value: String, x: CGFloat, top: CGFloat, width: CGFloat,
        size: CGFloat, bold: Bool = false, color: CGColor
    ) {
        let font = CTFontCreateWithName(
            (bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil
        )
        let text = NSAttributedString(string: value, attributes: [
            .font: font, .foregroundColor: color
        ])
        let line = CTLineCreateWithAttributedString(text)
        context.saveGState()
        context.textPosition = CGPoint(x: x, y: pageSize.height - top - size)
        context.clip(to: CGRect(x: x, y: pageSize.height - top - 2,
                                width: width, height: size + 6))
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawRight(
        _ value: String, right: CGFloat, top: CGFloat, width: CGFloat,
        size: CGFloat, bold: Bool = false, color: CGColor
    ) {
        let font = CTFontCreateWithName(
            (bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil
        )
        let text = NSAttributedString(string: value, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        draw(value, x: max(right - min(bounds.width, width), right - width),
             top: top, width: width, size: size, bold: bold, color: color)
    }
}
