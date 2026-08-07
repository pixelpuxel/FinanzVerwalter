import Foundation

enum ReportGrouping: String, CaseIterable, Codable, Identifiable, Sendable {
    case category
    case payee
    case account
    case tag
    case none

    var id: Self { self }

    var title: String {
        switch self {
        case .category: "Kategorie"
        case .payee: "Empfänger"
        case .account: "Konto"
        case .tag: "Klasse/Tag"
        case .none: "Keine Gruppierung"
        }
    }
}

enum ReportSort: String, CaseIterable, Codable, Identifiable, Sendable {
    case labelAscending
    case amountDescending
    case amountAscending
    case dateDescending
    case dateAscending

    var id: Self { self }

    var title: String {
        switch self {
        case .labelAscending: "Bezeichnung A–Z"
        case .amountDescending: "Betrag absteigend"
        case .amountAscending: "Betrag aufsteigend"
        case .dateDescending: "Datum neu nach alt"
        case .dateAscending: "Datum alt nach neu"
        }
    }
}

enum TransactionReportStandardPreset: String, CaseIterable, Identifiable, Sendable {
    case categoryIncomeExpense
    case payeeIncomeExpense
    case bookingJournal
    case cashFlow
    case accountActivity
    case categoryAndTag

    var id: Self { self }

    var title: String {
        switch self {
        case .categoryIncomeExpense: "Einnahmen/Ausgaben nach Kategorie"
        case .payeeIncomeExpense: "Einnahmen/Ausgaben nach Empfänger"
        case .bookingJournal: "Buchungsbericht"
        case .cashFlow: "Cashflow nach Konto und Kategorie"
        case .accountActivity: "Kontobewegungen nach Konto und Empfänger"
        case .categoryAndTag: "Kategorie- und Klassenbericht"
        }
    }

    var systemImage: String {
        switch self {
        case .categoryIncomeExpense: "square.grid.2x2"
        case .payeeIncomeExpense: "person.2"
        case .bookingJournal: "list.bullet.rectangle"
        case .cashFlow: "arrow.left.arrow.right"
        case .accountActivity: "building.columns"
        case .categoryAndTag: "tag"
        }
    }

    var summary: String {
        switch self {
        case .categoryIncomeExpense:
            "Aktuelles Jahr, Kategorien nach Betrag"
        case .payeeIncomeExpense:
            "Aktuelles Jahr, Empfänger mit Kategorie-Drill-down"
        case .bookingJournal:
            "Aktuelles Jahr, alle Positionen chronologisch"
        case .cashFlow:
            "Aktuelles Jahr, Konten mit Kategorie-Drill-down"
        case .accountActivity:
            "Aktuelles Jahr, Konten mit Empfänger-Drill-down"
        case .categoryAndTag:
            "Aktuelles Jahr, Kategorien mit Klassen-/Tag-Drill-down"
        }
    }

    func query(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TransactionReportQuery {
        let interval = calendar.dateInterval(of: .year, for: now)
        let dateFrom = interval?.start
        let dateThrough = interval?.end.addingTimeInterval(-0.001)
        switch self {
        case .categoryIncomeExpense:
            return TransactionReportQuery(
                dateFrom: dateFrom, dateThrough: dateThrough,
                grouping: .category, sort: .amountDescending
            )
        case .payeeIncomeExpense:
            return TransactionReportQuery(
                dateFrom: dateFrom, dateThrough: dateThrough,
                grouping: .payee, secondaryGrouping: .category,
                sort: .amountDescending
            )
        case .bookingJournal:
            return TransactionReportQuery(
                dateFrom: dateFrom, dateThrough: dateThrough,
                grouping: .none, sort: .dateAscending
            )
        case .cashFlow:
            return TransactionReportQuery(
                dateFrom: dateFrom, dateThrough: dateThrough,
                grouping: .account, secondaryGrouping: .category,
                sort: .amountDescending
            )
        case .accountActivity:
            return TransactionReportQuery(
                dateFrom: dateFrom, dateThrough: dateThrough,
                grouping: .account, secondaryGrouping: .payee,
                sort: .amountDescending
            )
        case .categoryAndTag:
            return TransactionReportQuery(
                dateFrom: dateFrom, dateThrough: dateThrough,
                grouping: .category, secondaryGrouping: .tag,
                sort: .amountDescending
            )
        }
    }
}

struct TransactionReportQuery: Codable, Equatable, Sendable {
    var dateFrom: Date?
    var dateThrough: Date?
    var accountIDs: Set<UUID> = []
    var accountGroupIDs: Set<UUID> = []
    var categoryIDs: Set<UUID> = []
    var includeCategoryDescendants = true
    var tagIDs: Set<UUID> = []
    var payeeIDs: Set<UUID> = []
    var statuses: Set<TransactionStatus> = Set(
        TransactionStatus.allCases.filter { $0 != .cancelled }
    )
    var minimumAmountMinor: Int64?
    var maximumAmountMinor: Int64?
    var text = ""
    var currencies: Set<String> = []
    var includeHiddenAccounts = false
    var includeAccountsExcludedFromReports = false
    var includeTransfers = false
    var expandSplits = true
    var grouping: ReportGrouping = .category
    var secondaryGrouping: ReportGrouping? = nil
    var sort: ReportSort = .amountDescending
    var transactionIDs: Set<UUID>? = nil
    var exactPayee: String? = nil
    var includeForecast: Bool? = nil
    var includeDetailRows: Bool? = nil
    var includeSubtotals: Bool? = nil
    var includeGrandTotals: Bool? = nil

    var showsDetailRows: Bool { includeDetailRows ?? true }
    var showsSubtotals: Bool { includeSubtotals ?? true }
    var showsGrandTotals: Bool { includeGrandTotals ?? true }
}

struct SavedReportTemplate: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var definitionVersion: Int
    var query: TransactionReportQuery
}

struct TransactionReportFact: Identifiable, Hashable, Sendable {
    let id: String
    let transactionID: UUID
    let splitID: UUID?
    let bookingDate: Date
    let accountID: UUID
    let accountName: String
    let payee: String
    let payeeID: UUID?
    let purpose: String
    let detail: String
    let categoryID: UUID?
    let categoryPath: String
    let tagIDs: [UUID]
    let tagPaths: [String]
    let status: TransactionStatus
    let amountMinor: Int64
    let currency: String
    let isTransfer: Bool
}

struct TransactionReportGroup: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let currency: String
    let incomeMinor: Int64
    let expenseMinor: Int64
    let netMinor: Int64
    let factIDs: Set<String>
    var primaryLabel: String = ""
    var secondaryLabel: String = ""
    var level: ReportSummaryLevel = .detail

    var bookingCount: Int { factIDs.count }
}

enum ReportSummaryLevel: Hashable, Sendable {
    case detail
    case subtotal
}

struct TransactionReportPresentation: Equatable, Sendable {
    var includeDetailRows = true
    var includeSubtotals = true
    var includeGrandTotals = true

    static let all = TransactionReportPresentation()
}

struct TransactionReportCurrencyTotal: Identifiable, Hashable, Sendable {
    var id: String { currency }
    let currency: String
    let incomeMinor: Int64
    let expenseMinor: Int64
    let netMinor: Int64
}

struct TransactionReportSnapshot: Equatable, Sendable {
    let facts: [TransactionReportFact]
    let groups: [TransactionReportGroup]
    let totals: [TransactionReportCurrencyTotal]
    var presentation: TransactionReportPresentation = .all

    func facts(inGroupID id: String?) -> [TransactionReportFact] {
        guard let id, let group = groups.first(where: { $0.id == id }) else {
            return []
        }
        return facts.filter { group.factIDs.contains($0.id) }
    }
}

enum TransactionReportEngine {
    static func snapshot(
        query: TransactionReportQuery,
        transactions: [FinanceTransaction],
        accounts: [FinanceAccount],
        categories: [FinanceCategory],
        tags: [FinanceTag]
    ) -> TransactionReportSnapshot {
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let normalizedCurrencies = Set(query.currencies.map { $0.uppercased() })
        let allowedCategories = descendantIDs(
            selected: query.categoryIDs,
            parents: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.parentID) }),
            includeDescendants: query.includeCategoryDescendants
        )
        let allowedTags = descendantIDs(
            selected: query.tagIDs,
            parents: Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.parentID) }),
            includeDescendants: true
        )
        let normalizedText = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExactPayee = query.exactPayee.map(normalized)

        var facts: [TransactionReportFact] = []
        for transaction in transactions {
            guard query.transactionIDs?.contains(transaction.id) ?? true else {
                continue
            }
            guard let account = accountsByID[transaction.accountID] else { continue }
            guard accountMatches(account, query: query) else { continue }
            guard query.statuses.contains(transaction.status) else { continue }
            guard query.includeTransfers || transaction.transferID == nil else { continue }
            guard query.dateFrom.map({ transaction.bookingDate >= $0 }) ?? true else { continue }
            guard query.dateThrough.map({ transaction.bookingDate <= $0 }) ?? true else { continue }
            guard normalizedCurrencies.isEmpty
                || normalizedCurrencies.contains(transaction.currency.uppercased())
            else { continue }
            guard query.payeeIDs.isEmpty
                || transaction.payeeID.map(query.payeeIDs.contains) == true
            else { continue }
            guard normalizedExactPayee.map({
                normalized(transaction.payee) == $0
            }) ?? true else { continue }

            let candidates = expandedFacts(
                transaction: transaction,
                account: account,
                categoriesByID: categoriesByID,
                tagsByID: tagsByID,
                expandSplits: query.expandSplits
            )
            facts.append(
                contentsOf: candidates.filter { fact in
                    let absoluteAmount = fact.amountMinor == Int64.min
                        ? Int64.max
                        : abs(fact.amountMinor)
                    let amountMatches =
                        (query.minimumAmountMinor.map { absoluteAmount >= $0 } ?? true)
                        && (query.maximumAmountMinor.map { absoluteAmount <= $0 } ?? true)
                    let categoryMatches = allowedCategories.isEmpty
                        || fact.categoryID.map(allowedCategories.contains) == true
                    let tagMatches = allowedTags.isEmpty
                        || !allowedTags.isDisjoint(with: fact.tagIDs)
                    let textMatches = normalizedText.isEmpty
                        || searchableText(for: fact).localizedCaseInsensitiveContains(normalizedText)
                    return amountMatches && categoryMatches && tagMatches && textMatches
                }
            )
        }

        facts = sortFacts(facts, by: query.sort)
        let groups = makeGroups(
            facts: facts,
            grouping: query.grouping,
            secondaryGrouping: query.secondaryGrouping,
            sort: query.sort,
            includeSubtotals: query.showsSubtotals
        )
        let totals = makeTotals(facts)
        return TransactionReportSnapshot(
            facts: facts,
            groups: groups,
            totals: totals,
            presentation: TransactionReportPresentation(
                includeDetailRows: query.showsDetailRows,
                includeSubtotals: query.showsSubtotals,
                includeGrandTotals: query.showsGrandTotals
            )
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "de_DE")
            )
    }

    private static func accountMatches(
        _ account: FinanceAccount,
        query: TransactionReportQuery
    ) -> Bool {
        guard query.includeHiddenAccounts || (!account.isHidden && !account.isClosed) else {
            return false
        }
        guard query.includeAccountsExcludedFromReports || account.includeReports else {
            return false
        }
        if query.accountIDs.isEmpty && query.accountGroupIDs.isEmpty {
            return true
        }
        return query.accountIDs.contains(account.id)
            || account.groupID.map(query.accountGroupIDs.contains) == true
    }

    private static func expandedFacts(
        transaction: FinanceTransaction,
        account: FinanceAccount,
        categoriesByID: [UUID: FinanceCategory],
        tagsByID: [UUID: FinanceTag],
        expandSplits: Bool
    ) -> [TransactionReportFact] {
        if expandSplits, !transaction.splits.isEmpty {
            return transaction.splits.sorted { $0.sortOrder < $1.sortOrder }.map { split in
                let combinedTagIDs = unique(transaction.tagIDs + split.tagIDs)
                return TransactionReportFact(
                    id: "\(transaction.id.uuidString):\(split.id.uuidString)",
                    transactionID: transaction.id,
                    splitID: split.id,
                    bookingDate: transaction.bookingDate,
                    accountID: transaction.accountID,
                    accountName: account.name,
                    payee: transaction.payee,
                    payeeID: transaction.payeeID,
                    purpose: transaction.purpose,
                    detail: [transaction.memo, transaction.reference, split.memo]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "),
                    categoryID: split.categoryID,
                    categoryPath: hierarchyPath(split.categoryID, values: categoriesByID),
                    tagIDs: combinedTagIDs,
                    tagPaths: combinedTagIDs.map { hierarchyPath($0, values: tagsByID) },
                    status: transaction.status,
                    amountMinor: split.amountMinor,
                    currency: transaction.currency,
                    isTransfer: transaction.transferID != nil
                )
            }
        }
        let tagIDs = unique(transaction.tagIDs)
        return [
            TransactionReportFact(
                id: transaction.id.uuidString,
                transactionID: transaction.id,
                splitID: nil,
                bookingDate: transaction.bookingDate,
                accountID: transaction.accountID,
                accountName: account.name,
                payee: transaction.payee,
                payeeID: transaction.payeeID,
                purpose: transaction.purpose,
                detail: [transaction.memo, transaction.reference]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "),
                categoryID: transaction.categoryID,
                categoryPath: hierarchyPath(transaction.categoryID, values: categoriesByID),
                tagIDs: tagIDs,
                tagPaths: tagIDs.map { hierarchyPath($0, values: tagsByID) },
                status: transaction.status,
                amountMinor: transaction.amountMinor,
                currency: transaction.currency,
                isTransfer: transaction.transferID != nil
            )
        ]
    }

    private static func makeGroups(
        facts: [TransactionReportFact],
        grouping: ReportGrouping,
        secondaryGrouping: ReportGrouping?,
        sort: ReportSort,
        includeSubtotals: Bool
    ) -> [TransactionReportGroup] {
        guard grouping != .none else { return [] }
        let secondary: ReportGrouping = secondaryGrouping == grouping
            ? .none
            : secondaryGrouping ?? .none
        let grouped = Dictionary(grouping: facts) { fact in
            let primaryLabel = groupLabel(for: fact, grouping: grouping)
            let secondaryLabel = secondary == .none
                ? ""
                : groupLabel(for: fact, grouping: secondary)
            return "\(primaryLabel)\u{1E}\(secondaryLabel)\u{1F}\(fact.currency)"
        }
        let detailGroups = grouped.map { key, values in
            let parts = key.components(separatedBy: "\u{1F}")
            let labels = (parts.first ?? "").components(separatedBy: "\u{1E}")
            let primaryLabel = labels.first ?? "Ohne Zuordnung"
            let secondaryLabel = labels.count > 1 ? labels[1] : ""
            let income = values.filter { $0.amountMinor > 0 }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
            let expense = values.filter { $0.amountMinor < 0 }
                .reduce(Int64.zero) { $0 - $1.amountMinor }
            return TransactionReportGroup(
                id: key,
                label: secondaryLabel.isEmpty
                    ? primaryLabel
                    : "\(primaryLabel) › \(secondaryLabel)",
                currency: parts.count > 1 ? parts[1] : "EUR",
                incomeMinor: income,
                expenseMinor: expense,
                netMinor: income - expense,
                factIDs: Set(values.map(\.id)),
                primaryLabel: primaryLabel,
                secondaryLabel: secondaryLabel,
                level: .detail
            )
        }
        let sortedDetails = sortGroups(detailGroups, by: sort)
        guard includeSubtotals, secondary != .none else {
            return sortedDetails
        }

        let primaryGroups = Dictionary(grouping: facts) { fact in
            "\(groupLabel(for: fact, grouping: grouping))\u{1F}\(fact.currency)"
        }.map { key, values in
            let parts = key.components(separatedBy: "\u{1F}")
            let primaryLabel = parts.first ?? "Ohne Zuordnung"
            let income = values.filter { $0.amountMinor > 0 }
                .reduce(Int64.zero) { $0 + $1.amountMinor }
            let expense = values.filter { $0.amountMinor < 0 }
                .reduce(Int64.zero) { $0 - $1.amountMinor }
            return TransactionReportGroup(
                id: "subtotal\u{1D}\(key)",
                label: "Summe \(primaryLabel)",
                currency: parts.count > 1 ? parts[1] : "EUR",
                incomeMinor: income,
                expenseMinor: expense,
                netMinor: income - expense,
                factIDs: Set(values.map(\.id)),
                primaryLabel: primaryLabel,
                secondaryLabel: "",
                level: .subtotal
            )
        }

        var result: [TransactionReportGroup] = []
        for subtotal in sortGroups(primaryGroups, by: sort) {
            result.append(
                contentsOf: sortGroups(
                    detailGroups.filter {
                        $0.primaryLabel == subtotal.primaryLabel
                            && $0.currency == subtotal.currency
                    },
                    by: sort
                )
            )
            result.append(subtotal)
        }
        return result
    }

    private static func sortGroups(
        _ groups: [TransactionReportGroup],
        by sort: ReportSort
    ) -> [TransactionReportGroup] {
        groups.sorted { lhs, rhs in
            switch sort {
            case .amountDescending:
                return absoluteNet(lhs) == absoluteNet(rhs)
                    ? lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    : absoluteNet(lhs) > absoluteNet(rhs)
            case .amountAscending:
                return absoluteNet(lhs) == absoluteNet(rhs)
                    ? lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    : absoluteNet(lhs) < absoluteNet(rhs)
            default:
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
        }
    }

    private static func makeTotals(
        _ facts: [TransactionReportFact]
    ) -> [TransactionReportCurrencyTotal] {
        Dictionary(grouping: facts, by: \.currency)
            .map { currency, values in
                let income = values.filter { $0.amountMinor > 0 }
                    .reduce(Int64.zero) { $0 + $1.amountMinor }
                let expense = values.filter { $0.amountMinor < 0 }
                    .reduce(Int64.zero) { $0 - $1.amountMinor }
                return TransactionReportCurrencyTotal(
                    currency: currency,
                    incomeMinor: income,
                    expenseMinor: expense,
                    netMinor: income - expense
                )
            }
            .sorted { $0.currency < $1.currency }
    }

    private static func sortFacts(
        _ facts: [TransactionReportFact],
        by sort: ReportSort
    ) -> [TransactionReportFact] {
        facts.sorted { lhs, rhs in
            switch sort {
            case .dateAscending:
                return dateOrder(lhs, rhs, ascending: true)
            case .dateDescending:
                return dateOrder(lhs, rhs, ascending: false)
            case .amountAscending:
                return lhs.amountMinor == rhs.amountMinor
                    ? dateOrder(lhs, rhs, ascending: false)
                    : lhs.amountMinor < rhs.amountMinor
            case .amountDescending:
                return lhs.amountMinor == rhs.amountMinor
                    ? dateOrder(lhs, rhs, ascending: false)
                    : lhs.amountMinor > rhs.amountMinor
            case .labelAscending:
                let lhsLabel = lhs.payee.isEmpty ? lhs.purpose : lhs.payee
                let rhsLabel = rhs.payee.isEmpty ? rhs.purpose : rhs.payee
                let comparison = lhsLabel.localizedCaseInsensitiveCompare(rhsLabel)
                return comparison == .orderedSame
                    ? dateOrder(lhs, rhs, ascending: false)
                    : comparison == .orderedAscending
            }
        }
    }

    private static func dateOrder(
        _ lhs: TransactionReportFact,
        _ rhs: TransactionReportFact,
        ascending: Bool
    ) -> Bool {
        if lhs.bookingDate == rhs.bookingDate {
            return ascending ? lhs.id < rhs.id : lhs.id > rhs.id
        }
        return ascending
            ? lhs.bookingDate < rhs.bookingDate
            : lhs.bookingDate > rhs.bookingDate
    }

    private static func groupLabel(
        for fact: TransactionReportFact,
        grouping: ReportGrouping
    ) -> String {
        switch grouping {
        case .category:
            fact.categoryPath
        case .payee:
            fact.payee.isEmpty ? "Ohne Empfänger" : fact.payee
        case .account:
            fact.accountName
        case .tag:
            fact.tagPaths.isEmpty ? "Ohne Klasse/Tag" : fact.tagPaths.joined(separator: " + ")
        case .none:
            "Alle Buchungen"
        }
    }

    private static func searchableText(for fact: TransactionReportFact) -> String {
        [
            fact.payee, fact.purpose, fact.detail, fact.categoryPath,
            fact.accountName, fact.status.title, fact.tagPaths.joined(separator: " ")
        ].joined(separator: "\n")
    }

    private static func descendantIDs(
        selected: Set<UUID>,
        parents: [UUID: UUID?],
        includeDescendants: Bool
    ) -> Set<UUID> {
        guard includeDescendants, !selected.isEmpty else { return selected }
        var result = selected
        for candidate in parents.keys {
            var current = parents[candidate] ?? nil
            var visited = Set<UUID>()
            while let id = current, visited.insert(id).inserted {
                if selected.contains(id) {
                    result.insert(candidate)
                    break
                }
                current = parents[id] ?? nil
            }
        }
        return result
    }

    private static func hierarchyPath<Value>(
        _ id: UUID?,
        values: [UUID: Value]
    ) -> String where Value: HierarchyNamedValue {
        guard let id, let value = values[id] else { return "Nicht zugeordnet" }
        var names = [value.hierarchyName]
        var current = value.hierarchyParentID
        var visited = Set([id])
        while let parentID = current,
              visited.insert(parentID).inserted,
              let parent = values[parentID] {
            names.insert(parent.hierarchyName, at: 0)
            current = parent.hierarchyParentID
        }
        return names.joined(separator: " › ")
    }

    private static func unique(_ values: [UUID]) -> [UUID] {
        values.reduce(into: [UUID]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private static func absoluteNet(_ group: TransactionReportGroup) -> Int64 {
        group.netMinor == Int64.min ? Int64.max : abs(group.netMinor)
    }
}

enum ReportCSVSeparator: String, CaseIterable, Identifiable, Sendable {
    case semicolon = ";"
    case comma = ","
    case tab = "\t"

    var id: Self { self }

    var title: String {
        switch self {
        case .semicolon: "Semikolon"
        case .comma: "Komma"
        case .tab: "Tabulator"
        }
    }
}

enum ReportCSVEncoding: String, CaseIterable, Identifiable, Sendable {
    case utf8
    case isoLatin1

    var id: Self { self }

    var title: String {
        switch self {
        case .utf8: "UTF-8"
        case .isoLatin1: "ISO-8859-1"
        }
    }
}

struct ReportCSVOptions: Equatable, Sendable {
    var separator: ReportCSVSeparator = .semicolon
    var encoding: ReportCSVEncoding = .utf8
}

struct ReportExportMetadata: Equatable, Sendable {
    var title: String
    var dateLabel: String
    var filterSummary: String
    var baseCurrency: String
    var generatedAt: Date
}

enum TransactionReportCSVExporter {
    static func data(
        snapshot: TransactionReportSnapshot,
        metadata: ReportExportMetadata,
        options: ReportCSVOptions
    ) throws -> Data {
        let delimiter = options.separator.rawValue
        var rows = [
            ["Bericht", metadata.title],
            ["Zeitraum", metadata.dateLabel],
            ["Filter", metadata.filterSummary],
            ["Erstellt", isoDateTime(metadata.generatedAt)],
            ["Basiswährung", metadata.baseCurrency]
        ]

        if !snapshot.groups.isEmpty {
            rows.append([])
            rows.append(["Gruppenübersicht"])
            rows.append([
                "Typ", "Gruppe", "Anzahl", "Einnahmen", "Ausgaben",
                "Saldo", "Währung"
            ])
            rows.append(contentsOf: snapshot.groups.map { group in
                [
                    group.level == .subtotal ? "Zwischensumme" : "Gruppe",
                    group.label,
                    String(group.bookingCount),
                    germanAmount(group.incomeMinor, currency: group.currency),
                    germanAmount(group.expenseMinor, currency: group.currency),
                    germanAmount(group.netMinor, currency: group.currency),
                    group.currency
                ]
            })
        }

        if snapshot.presentation.includeDetailRows {
            rows.append([])
            rows.append(["Buchungen und Splitpositionen"])
            rows.append([
                "Datum", "Konto", "Empfänger", "Verwendungszweck", "Kategorie",
                "Status", "Betrag", "Währung", "Split"
            ])
            rows.append(
                contentsOf: snapshot.facts.map { fact in
                    [
                        isoDate(fact.bookingDate),
                        fact.accountName,
                        fact.payee,
                        fact.purpose,
                        fact.categoryPath,
                        fact.status.title,
                        germanAmount(fact.amountMinor, currency: fact.currency),
                        fact.currency,
                        fact.splitID == nil ? "Nein" : "Ja"
                    ]
                }
            )
        }

        if snapshot.presentation.includeGrandTotals {
            rows.append([])
            rows.append(["Gesamtsummen"])
            rows.append(["Währung", "Einnahmen", "Ausgaben", "Saldo"])
            rows.append(contentsOf: snapshot.totals.map { total in
                [
                    total.currency,
                    germanAmount(total.incomeMinor, currency: total.currency),
                    germanAmount(total.expenseMinor, currency: total.currency),
                    germanAmount(total.netMinor, currency: total.currency)
                ]
            })
        }
        let text = rows.map { row in
            row.map { escape($0, delimiter: delimiter) }.joined(separator: delimiter)
        }.joined(separator: "\r\n") + "\r\n"
        switch options.encoding {
        case .utf8:
            return Data(text.utf8)
        case .isoLatin1:
            guard let data = text.data(using: .isoLatin1, allowLossyConversion: false) else {
                throw FinanceError.database(
                    "Der Bericht enthält Zeichen, die ISO-8859-1 nicht darstellen kann."
                )
            }
            return data
        }
    }

    private static func escape(_ value: String, delimiter: String) -> String {
        guard value.contains(delimiter)
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    fileprivate static func germanAmount(
        _ minorUnits: Int64,
        currency: String
    ) -> String {
        let digits = Money.fractionDigits(for: currency)
        let factor = UInt64(Money.minorUnitFactor(for: currency))
        let magnitude = minorUnits.magnitude
        let units = magnitude / factor
        guard digits > 0 else {
            return "\(minorUnits < 0 ? "-" : "")\(units)"
        }
        let fraction = String(magnitude % factor)
            .leftPadded(to: digits, with: "0")
        return "\(minorUnits < 0 ? "-" : "")\(units),\(fraction)"
    }

    private static func isoDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func isoDateTime(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum TransactionReportHTMLExporter {
    static func data(
        snapshot: TransactionReportSnapshot,
        metadata: ReportExportMetadata
    ) -> Data {
        Data(html(snapshot: snapshot, metadata: metadata).utf8)
    }

    static func html(
        snapshot: TransactionReportSnapshot,
        metadata: ReportExportMetadata
    ) -> String {
        var sections: [String] = []
        if !snapshot.groups.isEmpty {
            let rows = snapshot.groups.map { group in
                let cssClass = group.level == .subtotal ? " class=\"subtotal\"" : ""
                return "<tr\(cssClass)><td>\(escape(group.label))</td>"
                    + "<td class=\"number\">\(group.bookingCount)</td>"
                    + amountCells(
                        [group.incomeMinor, group.expenseMinor, group.netMinor],
                        currency: group.currency
                    )
                    + "<td>\(escape(group.currency))</td></tr>"
            }.joined(separator: "\n")
            sections.append(
                """
                <section>
                <h2>Gruppenübersicht</h2>
                <table><thead><tr><th>Gruppe</th><th class="number">Anzahl</th><th class="number">Einnahmen</th><th class="number">Ausgaben</th><th class="number">Saldo</th><th>Währung</th></tr></thead>
                <tbody>
                \(rows)
                </tbody></table>
                </section>
                """
            )
        }

        if snapshot.presentation.includeDetailRows {
            let rows = snapshot.facts.map { fact in
                "<tr><td><time datetime=\"\(isoDate(fact.bookingDate))\">\(isoDate(fact.bookingDate))</time></td>"
                    + "<td>\(escape(fact.accountName))</td>"
                    + "<td>\(escape(fact.payee))</td>"
                    + "<td>\(escape(fact.purpose))</td>"
                    + "<td>\(escape(fact.categoryPath))</td>"
                    + "<td>\(escape(fact.status.title + (fact.splitID == nil ? "" : " · Split")))</td>"
                    + amountCells([fact.amountMinor], currency: fact.currency)
                    + "<td>\(escape(fact.currency))</td></tr>"
            }.joined(separator: "\n")
            sections.append(
                """
                <section>
                <h2>Buchungen und Splitpositionen</h2>
                <table><thead><tr><th>Datum</th><th>Konto</th><th>Empfänger</th><th>Verwendungszweck</th><th>Kategorie</th><th>Status</th><th class="number">Betrag</th><th>Währung</th></tr></thead>
                <tbody>
                \(rows)
                </tbody></table>
                </section>
                """
            )
        }

        if snapshot.presentation.includeGrandTotals {
            let rows = snapshot.totals.map { total in
                "<tr class=\"grand-total\"><td>\(escape(total.currency))</td>"
                    + amountCells(
                        [total.incomeMinor, total.expenseMinor, total.netMinor],
                        currency: total.currency
                    )
                    + "</tr>"
            }.joined(separator: "\n")
            sections.append(
                """
                <section>
                <h2>Gesamtsummen</h2>
                <table class="totals"><thead><tr><th>Währung</th><th class="number">Einnahmen</th><th class="number">Ausgaben</th><th class="number">Saldo</th></tr></thead>
                <tbody>
                \(rows)
                </tbody></table>
                </section>
                """
            )
        }

        return """
        <!doctype html>
        <html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(metadata.title))</title>
        <style>
        :root{color-scheme:light dark;--accent:#146136;--line:#cfd8d2;--stripe:#f4f7f5;--subtotal:#e6f2eb}*{box-sizing:border-box}body{font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:32px;color:#17211b;background:#fff}h1{color:var(--accent);margin:0 0 6px}h2{font-size:17px;margin:28px 0 8px}.meta{display:grid;grid-template-columns:max-content 1fr;gap:4px 14px;margin:12px 0 24px}.meta dt{font-weight:600}.meta dd{margin:0}table{border-collapse:collapse;width:100%;font-size:12px}th,td{border:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}th{background:var(--accent);color:#fff}.number{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}tbody tr:nth-child(even){background:var(--stripe)}tr.subtotal td{background:var(--subtotal);font-weight:700;border-top:2px solid var(--accent)}tr.grand-total td{font-weight:700}footer{margin-top:28px;color:#536158;font-size:11px}@media print{body{margin:12mm;color:#000}section{break-inside:auto}thead{display:table-header-group}tr{break-inside:avoid}:root{color-scheme:light}}
        </style></head><body>
        <header><h1>\(escape(metadata.title))</h1><div>\(escape(metadata.dateLabel))</div></header>
        <dl class="meta"><dt>Filter</dt><dd>\(escape(metadata.filterSummary))</dd><dt>Erstellt</dt><dd><time datetime="\(isoDateTime(metadata.generatedAt))">\(isoDateTime(metadata.generatedAt))</time></dd><dt>Basiswährung</dt><dd>\(escape(metadata.baseCurrency))</dd></dl>
        \(sections.joined(separator: "\n"))
        <footer>Erstellt mit FinanzVerwalter</footer>
        </body></html>
        """ + "\n"
    }

    private static func amountCells(
        _ values: [Int64],
        currency: String
    ) -> String {
        values.map {
            "<td class=\"number\">"
                + TransactionReportCSVExporter.germanAmount($0, currency: currency)
                + "</td>"
        }.joined()
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func isoDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func isoDateTime(_ date: Date) -> String {
        isoDateTimeFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoDateTimeFormatter = ISO8601DateFormatter()
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(character), count: length - count) + self
    }
}

private protocol HierarchyNamedValue {
    var hierarchyName: String { get }
    var hierarchyParentID: UUID? { get }
}

extension FinanceCategory: HierarchyNamedValue {
    fileprivate var hierarchyName: String { name }
    fileprivate var hierarchyParentID: UUID? { parentID }
}

extension FinanceTag: HierarchyNamedValue {
    fileprivate var hierarchyName: String { name }
    fileprivate var hierarchyParentID: UUID? { parentID }
}
