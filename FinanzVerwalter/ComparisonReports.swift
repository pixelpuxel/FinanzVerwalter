import CoreGraphics
import CoreText
import Foundation

struct VATReportQuery: Codable, Equatable, Sendable {
    var dateFrom: Date
    var dateThrough: Date
    var accountIDs = Set<UUID>()
    var accountGroupIDs = Set<UUID>()
    var currencies = Set<String>()
    var statuses = Set(TransactionStatus.allCases.filter { $0 != .cancelled })
    var includeHiddenAccounts = false
    var includeAccountsExcludedFromReports = false
    var includeTransfers = false
}

struct VATReportFact: Identifiable, Equatable, Sendable {
    let id: String
    let transactionID: UUID
    let splitID: UUID?
    let bookingDate: Date
    let accountName: String
    let payee: String
    let categoryPath: String
    let categoryKind: CategoryKind?
    let vatCodeID: UUID
    let vatCodeName: String
    let rateBasisPoints: Int
    let grossMinor: Int64
    let netMinor: Int64
    let taxMinor: Int64
    let currency: String
}

struct VATReportRow: Identifiable, Equatable, Sendable {
    let id: String
    let vatCodeID: UUID
    let vatCodeName: String
    let rateBasisPoints: Int
    let currency: String
    let grossSalesMinor: Int64
    let netSalesMinor: Int64
    let outputTaxMinor: Int64
    let grossPurchasesMinor: Int64
    let netPurchasesMinor: Int64
    let inputTaxMinor: Int64
    let payableMinor: Int64
    let factIDs: Set<String>

    var bookingCount: Int { factIDs.count }
}

struct VATReportCurrencyTotal: Identifiable, Equatable, Sendable {
    var id: String { currency }
    let currency: String
    let grossSalesMinor: Int64
    let netSalesMinor: Int64
    let outputTaxMinor: Int64
    let grossPurchasesMinor: Int64
    let netPurchasesMinor: Int64
    let inputTaxMinor: Int64
    let payableMinor: Int64
}

struct VATReportSnapshot: Equatable, Sendable {
    let dateFrom: Date
    let dateThrough: Date
    let facts: [VATReportFact]
    let rows: [VATReportRow]
    let totals: [VATReportCurrencyTotal]

    func facts(inRowID id: String?) -> [VATReportFact] {
        guard let id, let row = rows.first(where: { $0.id == id }) else { return [] }
        return facts.filter { row.factIDs.contains($0.id) }
    }
}

enum VATReportEngine {
    static func snapshot(
        query: VATReportQuery,
        transactions: [FinanceTransaction],
        accounts: [FinanceAccount],
        categories: [FinanceCategory],
        vatCodes: [VATCode]
    ) -> VATReportSnapshot {
        let start = min(query.dateFrom, query.dateThrough)
        let end = max(query.dateFrom, query.dateThrough)
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let codesByID = Dictionary(uniqueKeysWithValues: vatCodes.map { ($0.id, $0) })
        let currencies = Set(query.currencies.map { $0.uppercased() })
        var facts: [VATReportFact] = []

        for transaction in transactions {
            guard let account = accountsByID[transaction.accountID] else { continue }
            guard transaction.bookingDate >= start, transaction.bookingDate <= end else { continue }
            guard query.statuses.contains(transaction.status) else { continue }
            guard query.includeTransfers || transaction.transferID == nil else { continue }
            guard (query.accountIDs.isEmpty && query.accountGroupIDs.isEmpty)
                || query.accountIDs.contains(account.id)
                || account.groupID.map(query.accountGroupIDs.contains) == true
            else { continue }
            guard query.includeHiddenAccounts || (!account.isHidden && !account.isClosed) else {
                continue
            }
            guard query.includeAccountsExcludedFromReports || account.includeReports else {
                continue
            }
            let currency = transaction.currency.uppercased()
            guard currencies.isEmpty || currencies.contains(currency) else { continue }

            if transaction.splits.isEmpty {
                if let fact = fact(
                    transaction: transaction, split: nil, account: account,
                    categoriesByID: categoriesByID, codesByID: codesByID
                ) {
                    facts.append(fact)
                }
            } else {
                facts.append(contentsOf: transaction.splits
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .compactMap { split in
                        fact(
                            transaction: transaction, split: split, account: account,
                            categoriesByID: categoriesByID, codesByID: codesByID
                        )
                    })
            }
        }

        facts.sort {
            $0.bookingDate == $1.bookingDate ? $0.id < $1.id : $0.bookingDate < $1.bookingDate
        }
        let rows = Dictionary(grouping: facts) {
            "\($0.vatCodeID.uuidString)\u{1F}\($0.currency)"
        }.map { key, values in
            let sales = values.filter(isSales)
            let purchases = values.filter { !isSales($0) }
            let first = values[0]
            let outputTax = sales.reduce(Int64.zero) { $0 + $1.taxMinor }
            let inputTax = purchases.reduce(Int64.zero) { $0 - $1.taxMinor }
            return VATReportRow(
                id: key, vatCodeID: first.vatCodeID,
                vatCodeName: first.vatCodeName, rateBasisPoints: first.rateBasisPoints,
                currency: first.currency,
                grossSalesMinor: sales.reduce(0) { $0 + $1.grossMinor },
                netSalesMinor: sales.reduce(0) { $0 + $1.netMinor },
                outputTaxMinor: outputTax,
                grossPurchasesMinor: purchases.reduce(0) { $0 - $1.grossMinor },
                netPurchasesMinor: purchases.reduce(0) { $0 - $1.netMinor },
                inputTaxMinor: inputTax,
                payableMinor: outputTax - inputTax,
                factIDs: Set(values.map(\.id))
            )
        }.sorted {
            if $0.rateBasisPoints != $1.rateBasisPoints {
                return $0.rateBasisPoints < $1.rateBasisPoints
            }
            let nameOrder = $0.vatCodeName.localizedCaseInsensitiveCompare($1.vatCodeName)
            return nameOrder == .orderedSame
                ? $0.currency < $1.currency : nameOrder == .orderedAscending
        }
        let totals = Dictionary(grouping: rows, by: \.currency).map { currency, values in
            VATReportCurrencyTotal(
                currency: currency,
                grossSalesMinor: values.reduce(0) { $0 + $1.grossSalesMinor },
                netSalesMinor: values.reduce(0) { $0 + $1.netSalesMinor },
                outputTaxMinor: values.reduce(0) { $0 + $1.outputTaxMinor },
                grossPurchasesMinor: values.reduce(0) { $0 + $1.grossPurchasesMinor },
                netPurchasesMinor: values.reduce(0) { $0 + $1.netPurchasesMinor },
                inputTaxMinor: values.reduce(0) { $0 + $1.inputTaxMinor },
                payableMinor: values.reduce(0) { $0 + $1.payableMinor }
            )
        }.sorted { $0.currency < $1.currency }
        return VATReportSnapshot(
            dateFrom: start, dateThrough: end, facts: facts, rows: rows, totals: totals
        )
    }

    private static func fact(
        transaction: FinanceTransaction,
        split: FinanceSplit?,
        account: FinanceAccount,
        categoriesByID: [UUID: FinanceCategory],
        codesByID: [UUID: VATCode]
    ) -> VATReportFact? {
        let mode = split?.vatMode ?? transaction.vatMode
        guard mode != .none,
              let codeID = split?.vatCodeID ?? transaction.vatCodeID
        else { return nil }
        let code = codesByID[codeID]
        let categoryID = split?.categoryID ?? transaction.categoryID
        return VATReportFact(
            id: split.map { "\(transaction.id.uuidString):\($0.id.uuidString)" }
                ?? transaction.id.uuidString,
            transactionID: transaction.id, splitID: split?.id,
            bookingDate: transaction.bookingDate, accountName: account.name,
            payee: transaction.payee,
            categoryPath: hierarchyPath(categoryID, categoriesByID: categoriesByID),
            categoryKind: categoryID.flatMap { categoriesByID[$0]?.kind },
            vatCodeID: codeID,
            vatCodeName: code?.name ?? "Unbekannter MwSt.-Schlüssel",
            rateBasisPoints: code?.rateBasisPoints ?? 0,
            grossMinor: split?.amountMinor ?? transaction.amountMinor,
            netMinor: split?.netMinor ?? transaction.netMinor,
            taxMinor: split?.taxMinor ?? transaction.taxMinor,
            currency: transaction.currency.uppercased()
        )
    }

    private static func hierarchyPath(
        _ id: UUID?, categoriesByID: [UUID: FinanceCategory]
    ) -> String {
        guard var current = id else { return "Ohne Kategorie" }
        var names: [String] = []
        var visited = Set<UUID>()
        while let value = categoriesByID[current], visited.insert(current).inserted {
            names.append(value.name)
            guard let parentID = value.parentID else { break }
            current = parentID
        }
        return names.isEmpty ? "Ohne Kategorie" : names.reversed().joined(separator: " › ")
    }

    private static func isSales(_ fact: VATReportFact) -> Bool {
        switch fact.categoryKind {
        case .income: true
        case .expense: false
        case .transfer, .none: fact.grossMinor >= 0
        }
    }
}

struct LoanReportQuery: Codable, Equatable, Sendable {
    var dateFrom: Date? = nil
    var dateThrough: Date? = nil
    var loanIDs = Set<UUID>()
    var currencies = Set<String>()
    var includeInactiveLoans = false
}

struct LoanReportRow: Identifiable, Equatable, Sendable {
    let id: String
    let loanID: UUID
    let loanName: String
    let lender: String
    let currency: String
    let sequence: Int
    let dueDate: Date
    let openingBalanceMinor: Int64
    let installmentMinor: Int64
    let principalMinor: Int64
    let interestMinor: Int64
    let feeMinor: Int64
    let extraPaymentMinor: Int64
    let closingBalanceMinor: Int64
    let annualBasisPoints: Int
    var actualPaymentMinor: Int64? = nil
    var paymentVarianceMinor: Int64? = nil
    var matchSource: LoanPaymentMatchSource? = nil
    var matchTransactionID: UUID? = nil
}

struct LoanReportSummary: Identifiable, Equatable, Sendable {
    var id: UUID { loanID }
    let loanID: UUID
    let loanName: String
    let lender: String
    let currency: String
    let originalPrincipalMinor: Int64
    let openingBalanceMinor: Int64
    let installmentMinor: Int64
    let principalMinor: Int64
    let interestMinor: Int64
    let feeMinor: Int64
    let extraPaymentMinor: Int64
    let closingBalanceMinor: Int64
    let payoffDate: Date?
    let fixedRateUntil: Date?
    let rowIDs: Set<String>
    var actualPaymentMinor: Int64 = 0
    var paymentVarianceMinor: Int64 = 0
    var matchedPaymentCount: Int = 0

    var paymentMinor: Int64 { installmentMinor + extraPaymentMinor }
    var borrowingCostMinor: Int64 { interestMinor + feeMinor }
    var paymentCount: Int { rowIDs.count }
}

struct LoanReportCurrencyTotal: Identifiable, Equatable, Sendable {
    var id: String { currency }
    let currency: String
    let openingBalanceMinor: Int64
    let paymentMinor: Int64
    let principalMinor: Int64
    let interestMinor: Int64
    let feeMinor: Int64
    let extraPaymentMinor: Int64
    let closingBalanceMinor: Int64
    var actualPaymentMinor: Int64 = 0
    var paymentVarianceMinor: Int64 = 0
    var matchedPaymentCount: Int = 0
}

struct LoanReportSnapshot: Equatable, Sendable {
    let dateFrom: Date?
    let dateThrough: Date?
    let summaries: [LoanReportSummary]
    let rows: [LoanReportRow]
    let totals: [LoanReportCurrencyTotal]

    func rows(forLoanID id: UUID?) -> [LoanReportRow] {
        guard let id else { return [] }
        return rows.filter { $0.loanID == id }
    }
}

enum LoanReportEngine {
    static func snapshot(
        query: LoanReportQuery,
        loans: [FinanceLoan],
        schedulesByLoanID: [UUID: [LoanScheduleEntry]],
        matches: [LoanPaymentMatch] = [],
        calendar: Calendar = .current
    ) -> LoanReportSnapshot {
        let start = query.dateFrom.map { date in
            query.dateThrough.map { min(date, $0) } ?? date
        }
        let end = query.dateThrough.map { date in
            query.dateFrom.map { max(date, $0) } ?? date
        }
        let currencies = Set(query.currencies.map { $0.uppercased() })
        let selectedLoans = loans.filter { loan in
            (query.includeInactiveLoans || loan.isActive)
                && (query.loanIDs.isEmpty || query.loanIDs.contains(loan.id))
                && (currencies.isEmpty || currencies.contains(loan.currency.uppercased()))
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }

        var rows: [LoanReportRow] = []
        var summaries: [LoanReportSummary] = []
        for loan in selectedLoans {
            let fullSchedule = schedulesByLoanID[loan.id, default: []].sorted {
                $0.sequence == $1.sequence
                    ? $0.id < $1.id : $0.sequence < $1.sequence
            }
            let selected = fullSchedule.filter { entry in
                (start.map { entry.dueDate >= $0 } ?? true)
                    && (end.map { entry.dueDate <= $0 } ?? true)
            }
            guard let first = selected.first, let last = selected.last else { continue }
            let loanMatches = matches.filter { $0.loanID == loan.id }
            let loanRows = selected.map { entry in
                let match = loanMatches.first {
                    calendar.isDate($0.scheduledDate, inSameDayAs: entry.dueDate)
                }
                let planPayment = entry.installmentMinor + entry.extraPaymentMinor
                return LoanReportRow(
                    id: entry.id, loanID: loan.id, loanName: loan.name,
                    lender: loan.lender, currency: loan.currency.uppercased(),
                    sequence: entry.sequence, dueDate: entry.dueDate,
                    openingBalanceMinor: entry.openingBalanceMinor,
                    installmentMinor: entry.installmentMinor,
                    principalMinor: entry.principalMinor,
                    interestMinor: entry.interestMinor,
                    feeMinor: entry.feeMinor,
                    extraPaymentMinor: entry.extraPaymentMinor,
                    closingBalanceMinor: entry.closingBalanceMinor,
                    annualBasisPoints: entry.annualBasisPoints,
                    actualPaymentMinor: match?.actualPaymentMinor,
                    paymentVarianceMinor: match.map { $0.actualPaymentMinor - planPayment },
                    matchSource: match?.source,
                    matchTransactionID: match?.transactionID
                )
            }
            let matchedRows = loanRows.filter { $0.actualPaymentMinor != nil }
            rows.append(contentsOf: loanRows)
            summaries.append(
                LoanReportSummary(
                    loanID: loan.id, loanName: loan.name, lender: loan.lender,
                    currency: loan.currency.uppercased(),
                    originalPrincipalMinor: loan.principalMinor,
                    openingBalanceMinor: first.openingBalanceMinor,
                    installmentMinor: selected.reduce(0) { $0 + $1.installmentMinor },
                    principalMinor: selected.reduce(0) { $0 + $1.principalMinor },
                    interestMinor: selected.reduce(0) { $0 + $1.interestMinor },
                    feeMinor: selected.reduce(0) { $0 + $1.feeMinor },
                    extraPaymentMinor: selected.reduce(0) { $0 + $1.extraPaymentMinor },
                    closingBalanceMinor: last.closingBalanceMinor,
                    payoffDate: fullSchedule.last.flatMap {
                        $0.closingBalanceMinor == 0 ? $0.dueDate : nil
                    },
                    fixedRateUntil: loan.fixedRateUntil,
                    rowIDs: Set(loanRows.map(\.id)),
                    actualPaymentMinor: matchedRows.compactMap(\.actualPaymentMinor).reduce(0, +),
                    paymentVarianceMinor: matchedRows.compactMap(\.paymentVarianceMinor).reduce(0, +),
                    matchedPaymentCount: matchedRows.count
                )
            )
        }
        let totals = Dictionary(grouping: summaries, by: \.currency).map {
            currency, values in
            LoanReportCurrencyTotal(
                currency: currency,
                openingBalanceMinor: values.reduce(0) { $0 + $1.openingBalanceMinor },
                paymentMinor: values.reduce(0) { $0 + $1.paymentMinor },
                principalMinor: values.reduce(0) { $0 + $1.principalMinor },
                interestMinor: values.reduce(0) { $0 + $1.interestMinor },
                feeMinor: values.reduce(0) { $0 + $1.feeMinor },
                extraPaymentMinor: values.reduce(0) { $0 + $1.extraPaymentMinor },
                closingBalanceMinor: values.reduce(0) { $0 + $1.closingBalanceMinor },
                actualPaymentMinor: values.reduce(0) { $0 + $1.actualPaymentMinor },
                paymentVarianceMinor: values.reduce(0) { $0 + $1.paymentVarianceMinor },
                matchedPaymentCount: values.reduce(0) { $0 + $1.matchedPaymentCount }
            )
        }.sorted { $0.currency < $1.currency }
        return LoanReportSnapshot(
            dateFrom: start, dateThrough: end,
            summaries: summaries, rows: rows, totals: totals
        )
    }
}

enum PeriodComparisonMetric: String, CaseIterable, Codable, Identifiable, Sendable {
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

enum PeriodComparisonReferenceMode: String, CaseIterable, Codable, Identifiable, Sendable {
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

struct PeriodComparisonQuery: Codable, Equatable, Sendable {
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

struct BudgetPlanningMonthRow: Identifiable, Equatable, Sendable {
    var id: String { "\(categoryID.uuidString)|\(monthKey)" }
    let categoryID: UUID
    let categoryPath: String
    let kind: CategoryKind
    let month: Date
    let monthKey: String
    let line: BudgetLine?
    let rolloverMode: BudgetRolloverMode
    let basePlannedMinor: Int64
    let rolloverInMinor: Int64
    let effectivePlannedMinor: Int64
    let actualMinor: Int64
    let balanceMinor: Int64
    let rolloverOutMinor: Int64
    let factIDs: Set<String>
}

struct BudgetPlanningSnapshot: Equatable, Sendable {
    let budget: FinanceBudget
    let months: [Date]
    let rows: [BudgetPlanningMonthRow]
    let facts: [TransactionReportFact]

    func rows(monthKey: String) -> [BudgetPlanningMonthRow] {
        rows.filter { $0.monthKey == monthKey }
    }

    func rolloverReserve(after monthKey: String) -> Int64 {
        rows(monthKey: monthKey).reduce(Int64.zero) { $0 + $1.rolloverOutMinor }
    }
}

enum BudgetPlanningEngine {
    static func snapshot(
        budget: FinanceBudget,
        lines: [BudgetLine],
        transactions: [FinanceTransaction],
        accounts: [FinanceAccount],
        categories: [FinanceCategory],
        tags: [FinanceTag],
        calendar: Calendar = .current
    ) -> BudgetPlanningSnapshot {
        let months = budget.months(calendar: calendar)
        guard let first = months.first, let last = months.last else {
            return BudgetPlanningSnapshot(budget: budget, months: [], rows: [], facts: [])
        }
        let accountIDs = Set(accounts.filter {
            $0.includeBudget && !$0.isClosed
                && $0.currency.caseInsensitiveCompare(budget.currency) == .orderedSame
        }.map(\.id))
        let from = calendar.startOfDay(for: first)
        let through = calendar.date(
            byAdding: .month, value: 1,
            to: calendar.dateInterval(of: .month, for: last)?.start ?? last
        )?.addingTimeInterval(-0.001) ?? last
        let report = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(
                dateFrom: from, dateThrough: through, accountIDs: accountIDs,
                statuses: Set(TransactionStatus.allCases.filter { $0 != .cancelled }),
                currencies: [budget.currency.uppercased()], includeTransfers: false,
                expandSplits: true, grouping: .category, sort: .labelAscending
            ),
            transactions: transactions.filter { accountIDs.contains($0.accountID) },
            accounts: accounts, categories: categories, tags: tags
        )
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var lineByKey: [String: BudgetLine] = [:]
        for line in lines.filter({ $0.budgetID == budget.id }).sorted(by: {
            $0.id.uuidString < $1.id.uuidString
        }) {
            lineByKey[key(categoryID: line.categoryID, year: line.year, month: line.month)] = line
        }
        let factsByKey = Dictionary(grouping: report.facts.compactMap { fact -> (String, TransactionReportFact)? in
            guard let categoryID = fact.categoryID else { return nil }
            let components = calendar.dateComponents([.year, .month], from: fact.bookingDate)
            guard let year = components.year, let month = components.month else { return nil }
            return (key(categoryID: categoryID, year: year, month: month), fact)
        }, by: { $0.0 }).mapValues { $0.map(\.1) }

        var result: [BudgetPlanningMonthRow] = []
        for category in categories.filter({
            $0.isActive && $0.isBudgetable && $0.kind != .transfer
        }) {
            var rollover = Int64.zero
            var rolloverMode = BudgetRolloverMode.none
            for month in months {
                let components = calendar.dateComponents([.year, .month], from: month)
                guard let year = components.year, let monthValue = components.month else { continue }
                let line = lineByKey[key(
                    categoryID: category.id, year: year, month: monthValue
                )]
                if line != nil {
                    rolloverMode = BudgetRolloverMode(line: line)
                }
                let facts = factsByKey[key(
                    categoryID: category.id, year: year, month: monthValue
                ), default: []]
                let signedActual = facts.reduce(Int64.zero) { $0 + $1.amountMinor }
                let actual = category.kind == .expense ? -signedActual : signedActual
                let base = line?.plannedMinor ?? 0
                let effective = category.kind == .expense ? base + rollover : base - rollover
                let balance = category.kind == .expense
                    ? effective - actual
                    : actual - effective
                let rolloverOut: Int64
                if balance > 0, rolloverMode.rolloverPositive {
                    rolloverOut = balance
                } else if balance < 0, rolloverMode.rolloverNegative {
                    rolloverOut = balance
                } else {
                    rolloverOut = 0
                }
                result.append(BudgetPlanningMonthRow(
                    categoryID: category.id,
                    categoryPath: hierarchyPath(category.id, categoriesByID: categoryByID),
                    kind: category.kind, month: month,
                    monthKey: monthKey(month, calendar: calendar), line: line,
                    rolloverMode: rolloverMode,
                    basePlannedMinor: base, rolloverInMinor: rollover,
                    effectivePlannedMinor: effective, actualMinor: actual,
                    balanceMinor: balance, rolloverOutMinor: rolloverOut,
                    factIDs: Set(facts.map(\.id))
                ))
                rollover = rolloverOut
            }
        }
        return BudgetPlanningSnapshot(
            budget: budget, months: months,
            rows: result.sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                let path = $0.categoryPath.localizedCaseInsensitiveCompare($1.categoryPath)
                return path == .orderedSame ? $0.month < $1.month : path == .orderedAscending
            },
            facts: report.facts
        )
    }

    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func key(categoryID: UUID, year: Int, month: Int) -> String {
        "\(categoryID.uuidString)|\(String(format: "%04d-%02d", year, month))"
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

struct BudgetReportQuery: Codable, Equatable, Sendable {
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
    let rolloverMinor: Int64
    let effectivePlannedMinor: Int64
    let actualMinor: Int64
    let varianceMinor: Int64
    let rolloverOutMinor: Int64
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

    var rolloverIncomeMinor: Int64 {
        rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.rolloverMinor }
    }

    var rolloverExpenseMinor: Int64 {
        rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.rolloverMinor }
    }

    var effectiveIncomeMinor: Int64 {
        rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.effectivePlannedMinor }
    }

    var effectiveExpenseMinor: Int64 {
        rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.effectivePlannedMinor }
    }

    var rolloverReserveMinor: Int64 {
        rows.reduce(0) { $0 + $1.rolloverOutMinor }
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
        guard !includedMonths.isEmpty else {
            return BudgetReportSnapshot(budget: budget, includedMonths: [], rows: [], facts: [])
        }
        let monthKeys = Set(includedMonths.map { monthKey($0, calendar: calendar) })
        let planning = BudgetPlanningEngine.snapshot(
            budget: budget, lines: lines, transactions: transactions,
            accounts: accounts, categories: categories, tags: tags, calendar: calendar
        )
        let rowsByCategory = Dictionary(grouping: planning.rows.filter {
            monthKeys.contains($0.monthKey)
        }, by: \.categoryID)
        let rows = rowsByCategory.values.compactMap { monthRows -> BudgetReportRow? in
            let values = monthRows.sorted { $0.month < $1.month }
            guard let first = values.first, let last = values.last else { return nil }
            let planned = values.reduce(Int64.zero) { $0 + $1.basePlannedMinor }
            let actual = values.reduce(Int64.zero) { $0 + $1.actualMinor }
            let rollover = first.rolloverInMinor
            let effective = first.kind == .expense ? planned + rollover : planned - rollover
            guard query.includeZeroRows || planned != 0 || actual != 0
                    || rollover != 0 || last.rolloverOutMinor != 0 else { return nil }
            let variance = actual - effective
            return BudgetReportRow(
                categoryID: first.categoryID, categoryPath: first.categoryPath,
                kind: first.kind, currency: budget.currency.uppercased(),
                plannedMinor: planned, rolloverMinor: rollover,
                effectivePlannedMinor: effective, actualMinor: actual,
                varianceMinor: variance, rolloverOutMinor: last.rolloverOutMinor,
                completionBasisPoints: effective == 0
                    ? nil : roundedBasisPoints(numerator: actual, denominator: effective),
                factIDs: values.reduce(into: Set<String>()) { $0.formUnion($1.factIDs) }
            )
        }
        .sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.categoryPath.localizedCaseInsensitiveCompare($1.categoryPath)
                == .orderedAscending
        }
        return BudgetReportSnapshot(
            budget: budget, includedMonths: includedMonths, rows: rows, facts: planning.facts
        )
    }

    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        BudgetPlanningEngine.monthKey(date, calendar: calendar)
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

}

struct ComparisonReportExportMetadata: Equatable, Sendable {
    let title: String
    let currentLabel: String
    let referenceLabel: String
    let generatedAt: Date
}

struct VATReportExportMetadata: Equatable, Sendable {
    let title: String
    let dateLabel: String
    let filterSummary: String
    let generatedAt: Date
}

struct LoanReportExportMetadata: Equatable, Sendable {
    let title: String
    let dateLabel: String
    let filterSummary: String
    let generatedAt: Date
}

enum AssetRegisterReportHorizon: Int, CaseIterable, Codable, Identifiable, Sendable {
    case all = 0
    case next30Days = 30
    case next90Days = 90
    case next365Days = 365

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Alle Fristen"
        case .next30Days: "Nächste 30 Tage"
        case .next90Days: "Nächste 90 Tage"
        case .next365Days: "Nächste 365 Tage"
        }
    }
}

struct AssetRegisterReportQuery: Codable, Equatable, Sendable {
    var referenceDate: Date
    var horizon: AssetRegisterReportHorizon = .all
    var includeInactive = false
    var contractTypes = Set<ContractType>()
    var inventoryCategories = Set<InventoryCategory>()
    var text = ""
}

struct ContractReportRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let provider: String
    let type: ContractType
    let contractNumber: String
    let isActive: Bool
    let annualCostMinor: Int64
    let nextRenewal: Date?
    let cancellationDeadline: Date?
    let accountName: String
    let categoryPath: String
}

struct InventoryReportRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let category: InventoryCategory
    let room: String
    let isActive: Bool
    let purchasePriceMinor: Int64
    let currentValueMinor: Int64
    let insuranceValueMinor: Int64
    let warrantyEnd: Date?
    let retailer: String
    let serialNumber: String
}

struct AssetRegisterReportSnapshot: Equatable, Sendable {
    let referenceDate: Date
    let horizon: AssetRegisterReportHorizon
    let contracts: [ContractReportRow]
    let inventory: [InventoryReportRow]

    var annualContractCostMinor: Int64 {
        contracts.reduce(Int64.zero) { $0 + $1.annualCostMinor }
    }

    var purchasePriceMinor: Int64 {
        inventory.reduce(Int64.zero) { $0 + $1.purchasePriceMinor }
    }

    var currentValueMinor: Int64 {
        inventory.reduce(Int64.zero) { $0 + $1.currentValueMinor }
    }

    var insuranceValueMinor: Int64 {
        inventory.reduce(Int64.zero) { $0 + $1.insuranceValueMinor }
    }
}

enum AssetRegisterReportEngine {
    static func snapshot(
        query: AssetRegisterReportQuery,
        contracts: [FinanceContract],
        inventory: [InventoryItem],
        accounts: [FinanceAccount],
        categories: [FinanceCategory],
        calendar: Calendar = .current
    ) -> AssetRegisterReportSnapshot {
        let referenceDay = calendar.startOfDay(for: query.referenceDate)
        let through = query.horizon == .all ? nil : calendar.date(
            byAdding: .day, value: query.horizon.rawValue, to: referenceDay
        )
        let normalizedText = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let categoryPaths = categoryPathMap(categories)

        let contractRows = contracts.compactMap { contract -> ContractReportRow? in
            guard query.includeInactive || contract.isActive else { return nil }
            guard query.contractTypes.isEmpty || query.contractTypes.contains(contract.type)
            else { return nil }
            let renewal = contract.nextRenewal(after: referenceDay, calendar: calendar)
            let deadline = contract.cancellationDeadline(after: referenceDay, calendar: calendar)
            if let through {
                guard let deadline, deadline <= through else { return nil }
            }
            let accountName = contract.accountID.flatMap { accountsByID[$0] } ?? "–"
            let categoryPath = contract.categoryID.flatMap { categoryPaths[$0] } ?? "–"
            guard matches(
                normalizedText,
                values: [contract.name, contract.provider, contract.contractNumber,
                         contract.type.title, accountName, categoryPath]
            ) else { return nil }
            return ContractReportRow(
                id: contract.id, name: contract.name, provider: contract.provider,
                type: contract.type, contractNumber: contract.contractNumber,
                isActive: contract.isActive, annualCostMinor: contract.annualCostMinor,
                nextRenewal: renewal, cancellationDeadline: deadline,
                accountName: accountName, categoryPath: categoryPath
            )
        }.sorted {
            compareDatesThenNames(
                $0.cancellationDeadline, $1.cancellationDeadline,
                $0.name, $1.name
            )
        }

        let inventoryRows = inventory.compactMap { item -> InventoryReportRow? in
            guard query.includeInactive || item.isActive else { return nil }
            guard query.inventoryCategories.isEmpty
                    || query.inventoryCategories.contains(item.category) else { return nil }
            if let through {
                guard let warrantyEnd = item.warrantyEnd, warrantyEnd <= through else {
                    return nil
                }
            }
            guard matches(
                normalizedText,
                values: [item.name, item.category.title, item.room, item.retailer,
                         item.serialNumber]
            ) else { return nil }
            return InventoryReportRow(
                id: item.id, name: item.name, category: item.category, room: item.room,
                isActive: item.isActive, purchasePriceMinor: item.purchasePriceMinor,
                currentValueMinor: item.currentValueMinor,
                insuranceValueMinor: item.insuranceValueMinor,
                warrantyEnd: item.warrantyEnd, retailer: item.retailer,
                serialNumber: item.serialNumber
            )
        }.sorted {
            compareDatesThenNames($0.warrantyEnd, $1.warrantyEnd, $0.name, $1.name)
        }

        return AssetRegisterReportSnapshot(
            referenceDate: referenceDay, horizon: query.horizon,
            contracts: contractRows, inventory: inventoryRows
        )
    }

    private static func matches(_ needle: String, values: [String]) -> Bool {
        guard !needle.isEmpty else { return true }
        return values.contains {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(needle)
        }
    }

    private static func compareDatesThenNames(
        _ lhsDate: Date?, _ rhsDate: Date?, _ lhsName: String, _ rhsName: String
    ) -> Bool {
        switch (lhsDate, rhsDate) {
        case let (lhs?, rhs?) where lhs != rhs: return lhs < rhs
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private static func categoryPathMap(_ categories: [FinanceCategory]) -> [UUID: String] {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: categories.map { category in
            var names = [String]()
            var current: FinanceCategory? = category
            var visited = Set<UUID>()
            while let value = current, visited.insert(value.id).inserted {
                names.append(value.name)
                current = value.parentID.flatMap { byID[$0] }
            }
            return (category.id, names.reversed().joined(separator: " > "))
        })
    }
}

struct AssetRegisterReportExportMetadata: Equatable, Sendable {
    let title: String
    let filterSummary: String
    let generatedAt: Date
}

enum AssetRegisterReportCSVExporter {
    static func data(
        snapshot: AssetRegisterReportSnapshot,
        metadata: AssetRegisterReportExportMetadata
    ) -> Data {
        var lines = [
            csv(["Bericht", metadata.title]),
            csv(["Filter", metadata.filterSummary]),
            csv(["Stichtag", date(snapshot.referenceDate)]),
            csv(["Erstellt", ISO8601DateFormatter().string(from: metadata.generatedAt)]),
            "",
            csv(["Verträge"]),
            csv(["Bezeichnung", "Anbieter", "Typ", "Vertragsnummer", "Status",
                 "Jahreskosten", "Kündigungsfrist", "Verlängerung", "Konto",
                 "Kategorie", "Währung"])
        ]
        lines.append(contentsOf: snapshot.contracts.map { row in
            csv([row.name, row.provider, row.type.title, row.contractNumber,
                 row.isActive ? "Aktiv" : "Inaktiv", decimal(row.annualCostMinor),
                 optionalDate(row.cancellationDeadline), optionalDate(row.nextRenewal),
                 row.accountName, row.categoryPath, "EUR"])
        })
        lines.append(csv(["Gesamt", "", "", "", "", decimal(snapshot.annualContractCostMinor),
                          "", "", "", "", "EUR"]))
        lines.append("")
        lines.append(csv(["Inventar"]))
        lines.append(csv(["Gegenstand", "Kategorie", "Raum", "Status", "Kaufpreis",
                          "Aktueller Wert", "Versicherungswert", "Garantieende", "Händler",
                          "Seriennummer", "Währung"]))
        lines.append(contentsOf: snapshot.inventory.map { row in
            csv([row.name, row.category.title, row.room, row.isActive ? "Aktiv" : "Inaktiv",
                 decimal(row.purchasePriceMinor), decimal(row.currentValueMinor),
                 decimal(row.insuranceValueMinor), optionalDate(row.warrantyEnd),
                 row.retailer, row.serialNumber, "EUR"])
        })
        lines.append(csv(["Gesamt", "", "", "", decimal(snapshot.purchasePriceMinor),
                          decimal(snapshot.currentValueMinor), decimal(snapshot.insuranceValueMinor),
                          "", "", "", "EUR"]))
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
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

    private static func optionalDate(_ value: Date?) -> String {
        value.map(date) ?? ""
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: value)
    }
}

enum LoanReportCSVExporter {
    static func data(
        snapshot: LoanReportSnapshot,
        metadata: LoanReportExportMetadata
    ) -> Data {
        var rows = [
            ["Bericht", metadata.title],
            ["Zeitraum", metadata.dateLabel],
            ["Filter", metadata.filterSummary],
            ["Erstellt", ISO8601DateFormatter().string(from: metadata.generatedAt)],
            ["Datenart", "Planwerte mit Ist-Zahlungsabgleich"],
            [],
            ["Darlehen", "Kreditgeber", "Ursprung", "Anfangssaldo", "Zahlungen",
             "Ist-Zahlungen", "Abweichung", "Tilgung", "Zins", "Gebühren",
             "Sondertilgung", "Restschuld", "Schuldenfrei", "Währung",
             "Abgeglichen", "Raten"]
        ]
        rows.append(contentsOf: snapshot.summaries.map { summary in
            [summary.loanName, summary.lender,
             amount(summary.originalPrincipalMinor, summary.currency),
             amount(summary.openingBalanceMinor, summary.currency),
             amount(summary.paymentMinor, summary.currency),
             amount(summary.actualPaymentMinor, summary.currency),
             amount(summary.paymentVarianceMinor, summary.currency),
             amount(summary.principalMinor, summary.currency),
             amount(summary.interestMinor, summary.currency),
             amount(summary.feeMinor, summary.currency),
             amount(summary.extraPaymentMinor, summary.currency),
             amount(summary.closingBalanceMinor, summary.currency),
             summary.payoffDate.map(date) ?? "Ballonrest",
             summary.currency, String(summary.matchedPaymentCount),
             String(summary.paymentCount)]
        })
        rows.append([])
        rows.append(["Währungssummen", "", "", "Anfangssaldo", "Zahlungen",
                     "Ist-Zahlungen", "Abweichung", "Tilgung", "Zins", "Gebühren",
                     "Sondertilgung", "Restschuld", "", "Währung", "Abgeglichen", ""])
        rows.append(contentsOf: snapshot.totals.map { total in
            ["Gesamt", "", "", amount(total.openingBalanceMinor, total.currency),
             amount(total.paymentMinor, total.currency),
             amount(total.actualPaymentMinor, total.currency),
             amount(total.paymentVarianceMinor, total.currency),
             amount(total.principalMinor, total.currency),
             amount(total.interestMinor, total.currency),
             amount(total.feeMinor, total.currency),
             amount(total.extraPaymentMinor, total.currency),
             amount(total.closingBalanceMinor, total.currency), "", total.currency,
             String(total.matchedPaymentCount), ""]
        })
        rows.append([])
        rows.append(["Tilgungsplan"])
        rows.append(["Darlehen", "Nr.", "Fälligkeit", "Sollzins", "Anfangssaldo",
                     "Rate", "Ist", "Abweichung", "Zuordnung", "Tilgung", "Zins",
                     "Gebühr", "Sondertilgung", "Restschuld", "Währung"])
        rows.append(contentsOf: snapshot.rows.map { row in
            [row.loanName, String(row.sequence), date(row.dueDate),
             rate(row.annualBasisPoints), amount(row.openingBalanceMinor, row.currency),
             amount(row.installmentMinor, row.currency),
             row.actualPaymentMinor.map { amount($0, row.currency) } ?? "",
             row.paymentVarianceMinor.map { amount($0, row.currency) } ?? "",
             row.matchSource?.title ?? "Offen",
             amount(row.principalMinor, row.currency),
             amount(row.interestMinor, row.currency), amount(row.feeMinor, row.currency),
             amount(row.extraPaymentMinor, row.currency),
             amount(row.closingBalanceMinor, row.currency), row.currency]
        })
        let text = rows.map { $0.map(csv).joined(separator: ";") }
            .joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    private static func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(";") || escaped.contains("\"")
            || escaped.contains("\n") || escaped.contains("\r")
            ? "\"\(escaped)\"" : escaped
    }

    private static func amount(_ minor: Int64, _ currency: String) -> String {
        let factor = UInt64(Money.minorUnitFactor(for: currency))
        let magnitude = minor.magnitude
        let sign = minor < 0 ? "-" : ""
        guard factor > 1 else { return "\(sign)\(magnitude)" }
        var digits = 0
        var divisor = factor
        while divisor > 1 { digits += 1; divisor /= 10 }
        return "\(sign)\(magnitude / factor),"
            + String(format: "%0*llu", digits, magnitude % factor)
    }

    private static func rate(_ basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let remainder = abs(basisPoints % 100)
        return remainder == 0
            ? "\(whole) %"
            : "\(whole),\(String(format: "%02d", remainder)) %"
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: value)
    }
}

enum VATReportCSVExporter {
    static func data(
        snapshot: VATReportSnapshot,
        metadata: VATReportExportMetadata
    ) -> Data {
        var rows = [
            ["Bericht", metadata.title],
            ["Zeitraum", metadata.dateLabel],
            ["Filter", metadata.filterSummary],
            ["Erstellt", ISO8601DateFormatter().string(from: metadata.generatedAt)],
            [],
            ["MwSt.-Schlüssel", "Satz", "Bruttoumsatz", "Nettoumsatz",
             "Umsatzsteuer", "Bruttoeinkauf", "Nettoeinkauf", "Vorsteuer",
             "Zahllast", "Währung", "Positionen"]
        ]
        rows.append(contentsOf: snapshot.rows.map { row in
            [row.vatCodeName, rate(row.rateBasisPoints),
             amount(row.grossSalesMinor, row.currency),
             amount(row.netSalesMinor, row.currency),
             amount(row.outputTaxMinor, row.currency),
             amount(row.grossPurchasesMinor, row.currency),
             amount(row.netPurchasesMinor, row.currency),
             amount(row.inputTaxMinor, row.currency),
             amount(row.payableMinor, row.currency), row.currency,
             String(row.bookingCount)]
        })
        rows.append([])
        rows.append(["Gesamtsummen", "", "Bruttoumsatz", "Nettoumsatz",
                     "Umsatzsteuer", "Bruttoeinkauf", "Nettoeinkauf", "Vorsteuer",
                     "Zahllast", "Währung", ""])
        rows.append(contentsOf: snapshot.totals.map { total in
            ["Gesamt", "", amount(total.grossSalesMinor, total.currency),
             amount(total.netSalesMinor, total.currency),
             amount(total.outputTaxMinor, total.currency),
             amount(total.grossPurchasesMinor, total.currency),
             amount(total.netPurchasesMinor, total.currency),
             amount(total.inputTaxMinor, total.currency),
             amount(total.payableMinor, total.currency), total.currency, ""]
        })
        rows.append([])
        rows.append(["Buchungen und Splitpositionen"])
        rows.append(["Datum", "Konto", "Empfänger", "Kategorie", "MwSt.-Schlüssel",
                     "Satz", "Brutto", "Netto", "Steuer", "Währung", "Split"])
        rows.append(contentsOf: snapshot.facts.map { fact in
            [date(fact.bookingDate), fact.accountName, fact.payee, fact.categoryPath,
             fact.vatCodeName, rate(fact.rateBasisPoints),
             amount(fact.grossMinor, fact.currency), amount(fact.netMinor, fact.currency),
             amount(fact.taxMinor, fact.currency), fact.currency,
             fact.splitID == nil ? "Nein" : "Ja"]
        })
        let text = rows.map { $0.map(csv).joined(separator: ";") }
            .joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    private static func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(";") || escaped.contains("\"")
            || escaped.contains("\n") || escaped.contains("\r")
            ? "\"\(escaped)\"" : escaped
    }

    private static func amount(_ minor: Int64, _ currency: String) -> String {
        let factor = UInt64(Money.minorUnitFactor(for: currency))
        let magnitude = minor.magnitude
        let sign = minor < 0 ? "-" : ""
        guard factor > 1 else { return "\(sign)\(magnitude)" }
        var digits = 0
        var divisor = factor
        while divisor > 1 { digits += 1; divisor /= 10 }
        return "\(sign)\(magnitude / factor),"
            + String(format: "%0*llu", digits, magnitude % factor)
    }

    private static func rate(_ basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let remainder = abs(basisPoints % 100)
        return remainder == 0 ? "\(whole) %" : "\(whole),\(String(format: "%02d", remainder)) %"
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: value)
    }
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
        lines.append(csv(["Kategorie", "Art", "Plan", "Übertrag", "Verfügbar", "Ist",
                          "Abweichung", "Zielerreichung %", "Währung"]))
        lines.append(contentsOf: snapshot.rows.map { row in
            csv([row.categoryPath, row.kind == .income ? "Einnahme" : "Ausgabe",
                 decimal(row.plannedMinor), decimal(row.rolloverMinor),
                 decimal(row.effectivePlannedMinor), decimal(row.actualMinor),
                 decimal(row.varianceMinor), percent(row.completionBasisPoints), row.currency])
        })
        lines.append("")
        lines.append(csv(["Gesamtsumme", "Art", "Plan", "Übertrag", "Verfügbar", "Ist",
                          "Abweichung", "Zielerreichung %", "Währung"]))
        lines.append(csv([
            "Gesamt", "Einnahmen", decimal(snapshot.plannedIncomeMinor),
            decimal(snapshot.rolloverIncomeMinor), decimal(snapshot.effectiveIncomeMinor),
            decimal(snapshot.actualIncomeMinor),
            decimal(snapshot.actualIncomeMinor - snapshot.effectiveIncomeMinor), "",
            snapshot.budget.currency.uppercased()
        ]))
        lines.append(csv([
            "Gesamt", "Ausgaben", decimal(snapshot.plannedExpenseMinor),
            decimal(snapshot.rolloverExpenseMinor), decimal(snapshot.effectiveExpenseMinor),
            decimal(snapshot.actualExpenseMinor),
            decimal(snapshot.actualExpenseMinor - snapshot.effectiveExpenseMinor), "",
            snapshot.budget.currency.uppercased()
        ]))
        lines.append(csv([
            "Roll-over-Reserve", "", "", "", decimal(snapshot.rolloverReserveMinor),
            "", "", "", snapshot.budget.currency.uppercased()
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
    static func taxAllowanceData(
        snapshot: TaxAllowanceReportSnapshot,
        generatedAt: Date,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        let rows = snapshot.rows.map { row in
            [row.institution, row.holderNames, row.assessmentType.title,
             money(row.allowanceMinor, "EUR"), money(row.usedMinor, "EUR"),
             money(row.remainingMinor, "EUR"), money(row.legalLimitMinor, "EUR"),
             row.validity, row.taxIDComplete ? "Ja" : "Nein", row.accountNames]
        } + snapshot.subjectTotals.map { total in
            ["Gesamt", total.holderNames, "", money(total.allocatedMinor, "EUR"),
             money(total.usedMinor, "EUR"), money(total.unusedOrderMinor, "EUR"),
             money(total.legalLimitMinor, "EUR"), "", "", ""]
        }
        return try data(
            rows: rows,
            headers: ["Institut", "Person/en", "Art", "Auftrag", "Genutzt", "Rest",
                      "Maximum", "Gültigkeit", "Steuer-ID", "Kontenabdeckung"],
            metadata: ComparisonReportExportMetadata(
                title: "Freistellungsaufträge",
                currentLabel: "Steuerjahr \(snapshot.taxYear)",
                referenceLabel: "§ 20 Absatz 9 EStG",
                generatedAt: generatedAt
            ),
            orientation: orientation,
            subtitle: "Steuerjahr \(snapshot.taxYear) · Verwaltungshilfe, keine Steuerberatung"
        )
    }

    static func assetRegisterData(
        snapshot: AssetRegisterReportSnapshot,
        metadata: AssetRegisterReportExportMetadata,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        let contractRows = snapshot.contracts.map { row in
            ["Vertrag", row.name, row.provider, row.type.title,
             money(row.annualCostMinor, "EUR"),
             dateOrDash(row.cancellationDeadline), row.accountName, row.categoryPath]
        }
        let inventoryRows = snapshot.inventory.map { row in
            ["Inventar", row.name, row.room, row.category.title,
             money(row.currentValueMinor, "EUR"), dateOrDash(row.warrantyEnd),
             row.retailer, row.serialNumber]
        }
        let totalRows = [
            ["Summe", "Vertragskosten/Jahr", "", "",
             money(snapshot.annualContractCostMinor, "EUR"), "", "", ""],
            ["Summe", "Inventar aktuell", "", "",
             money(snapshot.currentValueMinor, "EUR"), "", "Versicherungswert",
             money(snapshot.insuranceValueMinor, "EUR")]
        ]
        return try data(
            rows: contractRows + inventoryRows + totalRows,
            headers: ["Bereich", "Bezeichnung", "Anbieter/Raum", "Typ/Kategorie",
                      "Jahreskosten/Wert", "Frist/Garantie", "Konto/Händler",
                      "Kategorie/Seriennr."],
            metadata: ComparisonReportExportMetadata(
                title: metadata.title,
                currentLabel: "Stichtag \(date(snapshot.referenceDate))",
                referenceLabel: metadata.filterSummary,
                generatedAt: metadata.generatedAt
            ),
            orientation: orientation,
            subtitle: metadata.filterSummary
        )
    }

    static func loanData(
        snapshot: LoanReportSnapshot,
        metadata: LoanReportExportMetadata,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        let rows = snapshot.rows.map { row in
            [row.loanName, date(row.dueDate), rate(row.annualBasisPoints),
             money(row.openingBalanceMinor, row.currency),
             money(row.installmentMinor, row.currency),
             row.actualPaymentMinor.map { money($0, row.currency) } ?? "Offen",
             row.paymentVarianceMinor.map { money($0, row.currency) } ?? "—",
             money(row.principalMinor, row.currency),
             money(row.interestMinor + row.feeMinor, row.currency),
             money(row.extraPaymentMinor, row.currency),
             money(row.closingBalanceMinor, row.currency), row.currency]
        } + snapshot.totals.map { total in
            ["Gesamt", "", "", money(total.openingBalanceMinor, total.currency),
             money(total.paymentMinor - total.extraPaymentMinor, total.currency),
             money(total.actualPaymentMinor, total.currency),
             money(total.paymentVarianceMinor, total.currency),
             money(total.principalMinor, total.currency),
             money(total.interestMinor + total.feeMinor, total.currency),
             money(total.extraPaymentMinor, total.currency),
             money(total.closingBalanceMinor, total.currency), total.currency]
        }
        return try data(
            rows: rows,
            headers: ["Darlehen", "Fälligkeit", "Sollzins", "Anfang", "Rate",
                      "Ist", "Abw.", "Tilgung", "Zins+Geb.", "Sondertilg.",
                      "Restschuld", "Währ."],
            metadata: ComparisonReportExportMetadata(
                title: metadata.title, currentLabel: metadata.dateLabel,
                referenceLabel: metadata.filterSummary, generatedAt: metadata.generatedAt
            ),
            orientation: orientation,
            subtitle: "Plan und Ist · \(metadata.dateLabel) · \(metadata.filterSummary)"
        )
    }

    static func vatData(
        snapshot: VATReportSnapshot,
        metadata: VATReportExportMetadata,
        orientation: ReportPDFOrientation = .landscape
    ) throws -> Data {
        let rows = snapshot.rows.map { row in
            [row.vatCodeName, rate(row.rateBasisPoints),
             money(row.grossSalesMinor, row.currency),
             money(row.netSalesMinor, row.currency),
             money(row.outputTaxMinor, row.currency),
             money(row.grossPurchasesMinor, row.currency),
             money(row.netPurchasesMinor, row.currency),
             money(row.inputTaxMinor, row.currency),
             money(row.payableMinor, row.currency), row.currency]
        } + snapshot.totals.map { total in
            ["Gesamt", "", money(total.grossSalesMinor, total.currency),
             money(total.netSalesMinor, total.currency),
             money(total.outputTaxMinor, total.currency),
             money(total.grossPurchasesMinor, total.currency),
             money(total.netPurchasesMinor, total.currency),
             money(total.inputTaxMinor, total.currency),
             money(total.payableMinor, total.currency), total.currency]
        }
        return try data(
            rows: rows,
            headers: ["MwSt.-Schlüssel", "Satz", "Brutto U.", "Netto U.", "USt.",
                      "Brutto E.", "Netto E.", "Vorsteuer", "Zahllast", "Währ."],
            metadata: ComparisonReportExportMetadata(
                title: metadata.title, currentLabel: metadata.dateLabel,
                referenceLabel: metadata.filterSummary, generatedAt: metadata.generatedAt
            ),
            orientation: orientation,
            subtitle: "\(metadata.dateLabel) · \(metadata.filterSummary)"
        )
    }

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
                 money(row.plannedMinor, row.currency), money(row.rolloverMinor, row.currency),
                 money(row.effectivePlannedMinor, row.currency),
                 money(row.actualMinor, row.currency), money(row.varianceMinor, row.currency),
                 percent(row.completionBasisPoints), row.currency]
            } + [
                ["Gesamt", "Einnahmen", money(snapshot.plannedIncomeMinor, snapshot.budget.currency),
                 money(snapshot.rolloverIncomeMinor, snapshot.budget.currency),
                 money(snapshot.effectiveIncomeMinor, snapshot.budget.currency),
                 money(snapshot.actualIncomeMinor, snapshot.budget.currency),
                 money(snapshot.actualIncomeMinor - snapshot.effectiveIncomeMinor,
                       snapshot.budget.currency), "", snapshot.budget.currency.uppercased()],
                ["Gesamt", "Ausgaben", money(snapshot.plannedExpenseMinor, snapshot.budget.currency),
                 money(snapshot.rolloverExpenseMinor, snapshot.budget.currency),
                 money(snapshot.effectiveExpenseMinor, snapshot.budget.currency),
                 money(snapshot.actualExpenseMinor, snapshot.budget.currency),
                 money(snapshot.actualExpenseMinor - snapshot.effectiveExpenseMinor,
                       snapshot.budget.currency), "", snapshot.budget.currency.uppercased()],
                ["Roll-over-Reserve", "", "", "",
                 money(snapshot.rolloverReserveMinor, snapshot.budget.currency),
                 "", "", "", snapshot.budget.currency.uppercased()]
            ],
            headers: ["Kategorie", "Art", "Plan", "Übertrag", "Verfügbar", "Ist",
                      "Abweichung", "%", "Währung"],
            metadata: metadata, orientation: orientation
        )
    }

    private static func data(
        rows: [[String]], headers: [String],
        metadata: ComparisonReportExportMetadata,
        orientation: ReportPDFOrientation,
        subtitle: String? = nil
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
            rows: rows, metadata: metadata,
            subtitle: subtitle
                ?? "\(metadata.currentLabel) · Vergleich: \(metadata.referenceLabel)"
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

    private static func rate(_ basisPoints: Int) -> String {
        let whole = basisPoints / 100
        let remainder = abs(basisPoints % 100)
        return remainder == 0
            ? "\(whole) %"
            : "\(whole),\(String(format: "%02d", remainder)) %"
    }

    private static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .short
        return formatter.string(from: value)
    }

    private static func dateOrDash(_ value: Date?) -> String {
        value.map(date) ?? "–"
    }
}

private struct ComparisonReportPDFRenderer {
    let context: CGContext
    let pageSize: CGSize
    let headers: [String]
    let rows: [[String]]
    let metadata: ComparisonReportExportMetadata
    let subtitle: String

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
            draw(subtitle,
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
