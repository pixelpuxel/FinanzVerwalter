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

    var bookingCount: Int { factIDs.count }
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
            sort: query.sort
        )
        let totals = makeTotals(facts)
        return TransactionReportSnapshot(facts: facts, groups: groups, totals: totals)
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
        sort: ReportSort
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
        let result = grouped.map { key, values in
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
                factIDs: Set(values.map(\.id))
            )
        }
        return result.sorted { lhs, rhs in
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
            ["Basiswährung", metadata.baseCurrency],
            [],
            [
                "Datum", "Konto", "Empfänger", "Verwendungszweck", "Kategorie",
                "Status", "Betrag", "Währung", "Split"
            ]
        ]
        rows.append(
            contentsOf: snapshot.facts.map { fact in
                [
                    isoDate(fact.bookingDate),
                    fact.accountName,
                    fact.payee,
                    fact.purpose,
                    fact.categoryPath,
                    fact.status.title,
                    germanAmount(fact.amountMinor),
                    fact.currency,
                    fact.splitID == nil ? "Nein" : "Ja"
                ]
            }
        )
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

    private static func germanAmount(_ minorUnits: Int64) -> String {
        let magnitude = minorUnits.magnitude
        let units = magnitude / 100
        let cents = magnitude % 100
        return "\(minorUnits < 0 ? "-" : "")\(units),\(cents < 10 ? "0" : "")\(cents)"
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
