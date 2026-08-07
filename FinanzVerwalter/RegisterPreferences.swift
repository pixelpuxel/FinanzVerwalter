import Foundation

enum RegisterColumn: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case date
    case valueDate
    case reference
    case status
    case payee
    case purpose
    case category
    case tags
    case account
    case amount
    case debit
    case credit
    case balance

    var id: Self { self }

    var title: String {
        switch self {
        case .date: "Datum"
        case .valueDate: "Wertstellung"
        case .reference: "Belegnummer"
        case .status: "Status"
        case .payee: "Empfänger"
        case .purpose: "Verwendungszweck"
        case .category: "Kategorie"
        case .tags: "Klasse/Tags"
        case .account: "Konto"
        case .amount: "Betrag"
        case .debit: "Soll"
        case .credit: "Haben"
        case .balance: "Saldo"
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .date, .valueDate: 82
        case .reference: 90
        case .status: 44
        case .payee: 130
        case .purpose: 170
        case .category: 150
        case .tags: 110
        case .account: 100
        case .amount, .debit, .credit, .balance: 105
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .date, .valueDate: 92
        case .reference: 120
        case .status: 70
        case .payee: 180
        case .purpose: 260
        case .category: 220
        case .tags: 150
        case .account: 140
        case .amount: 120
        case .debit, .credit: 112
        case .balance: 125
        }
    }

    static let configurableCases = allCases.filter {
        $0 != .debit && $0 != .credit
    }
    static let defaultSet = Set(configurableCases)
}

enum RegisterAmountColumnMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case amount
    case debitCredit

    var id: Self { self }
    var title: String {
        switch self {
        case .amount: "Betrag"
        case .debitCredit: "Soll / Haben"
        }
    }
}

enum RegisterColumnLayout {
    static func columns(
        visible: Set<RegisterColumn>,
        amountMode: RegisterAmountColumnMode
    ) -> [RegisterColumn] {
        RegisterColumn.configurableCases.flatMap { column -> [RegisterColumn] in
            guard visible.contains(column) else { return [] }
            guard column == .amount, amountMode == .debitCredit else {
                return [column]
            }
            return [.debit, .credit]
        }
    }
}

enum RegisterAmountPresentation {
    static func minorUnits(
        for column: RegisterColumn,
        amountMinor: Int64
    ) -> Int64? {
        switch column {
        case .amount:
            amountMinor
        case .debit:
            amountMinor < 0
                ? (amountMinor == Int64.min ? Int64.max : -amountMinor)
                : nil
        case .credit:
            amountMinor > 0 ? amountMinor : nil
        default:
            nil
        }
    }
}

struct RegisterSearchQuery: Equatable, Sendable {
    let tokens: [String]

    init(_ text: String) {
        tokens = RegisterSearchDocument.normalizedTokens(text).sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0 < $1
        }
    }

    var isEmpty: Bool { tokens.isEmpty }
}

struct RegisterSearchDocument: Equatable, Sendable {
    let normalizedText: String

    init(fields: [String]) {
        normalizedText = Self.normalizedTokens(fields.joined(separator: " "))
            .joined(separator: " ")
    }

    func matches(_ query: RegisterSearchQuery) -> Bool {
        query.tokens.allSatisfy(normalizedText.contains)
    }

    static func normalizedTokens(_ text: String) -> [String] {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "de_DE")
        )
        .lowercased(with: Locale(identifier: "de_DE"))
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
    }
}

struct RegisterSearchIndex: Equatable, Sendable {
    let documents: [UUID: RegisterSearchDocument]
    private let transactionIDsByFragment: [String: Set<UUID>]

    static let empty = RegisterSearchIndex(documents: [:])

    init(documents: [UUID: RegisterSearchDocument]) {
        self.documents = documents
        var inverted: [String: Set<UUID>] = [:]
        for (transactionID, document) in documents {
            let tokens = Set(document.normalizedText.split(separator: " ").map(String.init))
            for token in tokens {
                for fragment in Self.searchFragments(token) {
                    inverted[fragment, default: []].insert(transactionID)
                }
            }
        }
        transactionIDsByFragment = inverted
    }

    func matches(transactionID: UUID, query: RegisterSearchQuery) -> Bool {
        query.isEmpty || documents[transactionID]?.matches(query) == true
    }

    func matchingTransactionIDs(_ query: RegisterSearchQuery) -> Set<UUID> {
        guard !query.isEmpty else { return Set(documents.keys) }
        var matches: Set<UUID>?
        for queryToken in query.tokens {
            var tokenMatches: Set<UUID>?
            for fragment in Self.queryFragments(queryToken) {
                let fragmentMatches = transactionIDsByFragment[fragment] ?? []
                if let existing = tokenMatches {
                    tokenMatches = existing.intersection(fragmentMatches)
                } else {
                    tokenMatches = fragmentMatches
                }
                if tokenMatches?.isEmpty == true { break }
            }
            if let existing = matches {
                matches = existing.intersection(tokenMatches ?? [])
            } else {
                matches = tokenMatches ?? []
            }
            if matches?.isEmpty == true { break }
        }
        return Set((matches ?? []).filter { documents[$0]?.matches(query) == true })
    }

    static func build(
        transactions: [FinanceTransaction],
        accounts: [FinanceAccount],
        accountGroups: [AccountGroup] = [],
        categories: [FinanceCategory],
        tags: [FinanceTag],
        runningBalances: [UUID: Int64]
    ) -> RegisterSearchIndex {
        let groupNames = Dictionary(
            uniqueKeysWithValues: accountGroups.map { ($0.id, $0.name) }
        )
        let accountSearchTexts = Dictionary(
            uniqueKeysWithValues: accounts.map { account in
                (
                    account.id,
                    accountSearchText(
                        account,
                        groupName: account.groupID.flatMap { groupNames[$0] }
                    )
                )
            }
        )
        let categoryPaths = categoryPathMap(categories)
        let tagPaths = tagPathMap(tags)
        return RegisterSearchIndex(documents: Dictionary(
            uniqueKeysWithValues: transactions.map { transaction in
                let categoryPath: String
                if transaction.transferID != nil {
                    categoryPath = "Umbuchung"
                } else if transaction.splits.isEmpty {
                    categoryPath = transaction.categoryID.flatMap {
                        categoryPaths[$0]
                    } ?? "Nicht kategorisiert"
                } else {
                    let paths = transaction.splits.compactMap {
                        $0.categoryID.flatMap { categoryPaths[$0] }
                    }.uniqued()
                    categoryPath = "Split " + paths.joined(separator: " ")
                }
                let allTagIDs = transaction.tagIDs
                    + transaction.splits.flatMap(\.tagIDs)
                let fullTagPaths = allTagIDs.compactMap { tagPaths[$0] }
                    .uniqued()
                return (
                    transaction.id,
                    document(
                        transaction: transaction,
                        accountName: accountSearchTexts[transaction.accountID] ?? "",
                        categoryPath: categoryPath,
                        tagPaths: fullTagPaths,
                        runningBalanceMinor: runningBalances[transaction.id]
                    )
                )
            }
        ))
    }

    static func accountSearchText(
        _ account: FinanceAccount,
        groupName: String? = nil
    ) -> String {
        var fields = [
            account.name, account.shortName, account.institution,
            account.description, account.type.title, account.type.rawValue,
            account.currency, groupName ?? "", account.iban, account.bic,
            account.accountNumberMasked, account.ownerName,
            account.syncStatus.title, account.syncStatus.rawValue,
            account.isClosed ? "geschlossen" : "offen",
            account.isHidden ? "ausgeblendet" : "sichtbar",
            account.isOnline ? "online" : "offline"
        ]
        fields.append(contentsOf: moneyFields(
            account.openingBalanceMinor,
            currency: account.currency
        ))
        fields.append(contentsOf: moneyFields(
            account.creditLimitMinor,
            currency: account.currency
        ))
        if let lastBankBalanceMinor = account.lastBankBalanceMinor {
            fields.append(contentsOf: moneyFields(
                lastBankBalanceMinor,
                currency: account.currency
            ))
        }
        if let openingDate = account.openingDate {
            fields.append(contentsOf: dateFields(openingDate))
        }
        if let lastSyncAt = account.lastSyncAt {
            fields.append(contentsOf: dateFields(lastSyncAt))
        }
        return fields.joined(separator: " ")
    }

    static func document(
        transaction: FinanceTransaction,
        accountName: String,
        categoryPath: String,
        tagPaths: [String],
        runningBalanceMinor: Int64?
    ) -> RegisterSearchDocument {
        var fields = [
            accountName, transaction.payee, transaction.purpose,
            transaction.memo, transaction.reference, categoryPath,
            tagPaths.joined(separator: " "), transaction.status.title,
            transaction.status.rawValue, transaction.currency,
            transaction.externalProvider, transaction.externalTransactionID,
            transaction.counterpartyIBAN, transaction.counterpartyBIC,
            transaction.endToEndID, transaction.mandateReference,
            transaction.creditorID, transaction.bookingText,
            transaction.origin.rawValue, transaction.duplicateFingerprint
        ]
        fields.append(contentsOf: dateFields(transaction.bookingDate))
        if let valueDate = transaction.valueDate {
            fields.append(contentsOf: dateFields(valueDate))
        }
        fields.append(contentsOf: moneyFields(
            transaction.amountMinor,
            currency: transaction.currency
        ))
        fields.append(contentsOf: moneyFields(
            transaction.netMinor,
            currency: transaction.currency
        ))
        fields.append(contentsOf: moneyFields(
            transaction.taxMinor,
            currency: transaction.currency
        ))
        if let runningBalanceMinor {
            fields.append(contentsOf: moneyFields(
                runningBalanceMinor,
                currency: transaction.currency
            ))
        }
        if let bankBalanceAfterMinor = transaction.bankBalanceAfterMinor {
            fields.append(contentsOf: moneyFields(
                bankBalanceAfterMinor,
                currency: transaction.currency
            ))
        }
        if let originalAmountMinor = transaction.originalAmountMinor,
           !transaction.originalCurrency.isEmpty {
            fields.append(contentsOf: moneyFields(
                originalAmountMinor,
                currency: transaction.originalCurrency
            ))
        }
        if let exchangeRateScaled = transaction.exchangeRateScaled {
            fields.append(String(exchangeRateScaled))
        }
        for split in transaction.splits {
            fields.append(split.memo)
            fields.append(contentsOf: moneyFields(
                split.amountMinor,
                currency: transaction.currency
            ))
            fields.append(contentsOf: moneyFields(
                split.netMinor,
                currency: transaction.currency
            ))
            fields.append(contentsOf: moneyFields(
                split.taxMinor,
                currency: transaction.currency
            ))
        }
        return RegisterSearchDocument(fields: fields)
    }

    private static func moneyFields(
        _ minorUnits: Int64,
        currency: String
    ) -> [String] {
        let money = Money(minorUnits: minorUnits, currency: currency)
        return [String(minorUnits), money.editingString, money.formatted]
    }

    private static func dateFields(_ date: Date) -> [String] {
        let values = Calendar.current.dateComponents(
            [.day, .month, .year],
            from: date
        )
        guard let day = values.day,
              let month = values.month,
              let year = values.year
        else { return [] }
        return [
            String(format: "%02d.%02d.%04d", day, month, year),
            String(format: "%04d-%02d-%02d", year, month, day)
        ]
    }

    private static func categoryPathMap(
        _ categories: [FinanceCategory]
    ) -> [UUID: String] {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: categories.map { category in
            (category.id, hierarchyPath(
                id: category.id,
                name: { byID[$0]?.name },
                parent: { byID[$0]?.parentID }
            ))
        })
    }

    private static func tagPathMap(_ tags: [FinanceTag]) -> [UUID: String] {
        let byID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: tags.map { tag in
            (tag.id, hierarchyPath(
                id: tag.id,
                name: { byID[$0]?.name },
                parent: { byID[$0]?.parentID }
            ))
        })
    }

    private static func hierarchyPath(
        id: UUID,
        name: (UUID) -> String?,
        parent: (UUID) -> UUID?
    ) -> String {
        var names: [String] = []
        var currentID: UUID? = id
        var visited = Set<UUID>()
        while let value = currentID,
              visited.insert(value).inserted {
            if let valueName = name(value) {
                names.insert(valueName, at: 0)
            }
            currentID = parent(value)
        }
        return names.joined(separator: " › ")
    }

    private static func searchFragments(_ token: String) -> Set<String> {
        let characters = Array(token)
        var result = Set<String>()
        for length in 1...min(3, characters.count) {
            for start in 0...(characters.count - length) {
                result.insert(String(characters[start..<(start + length)]))
            }
        }
        return result
    }

    private static func queryFragments(_ token: String) -> Set<String> {
        let characters = Array(token)
        guard characters.count > 3 else { return [token] }
        return Set((0...(characters.count - 3)).map {
            String(characters[$0..<($0 + 3)])
        })
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

enum CombinedRegisterChartMode: String, Equatable, Sendable {
    case balance
    case filteredMovement

    var title: String {
        switch self {
        case .balance: "Saldoverlauf"
        case .filteredMovement: "Gefilterte Bewegungssumme"
        }
    }
}

struct CombinedRegisterChartPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let valueMinor: Int64
    let lastTransactionID: UUID

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)-\(lastTransactionID.uuidString)"
    }
}

struct CombinedRegisterChartSeries: Identifiable, Equatable, Sendable {
    let currency: String
    let points: [CombinedRegisterChartPoint]

    var id: String { currency }
}

struct CombinedRegisterChartSnapshot: Equatable, Sendable {
    let mode: CombinedRegisterChartMode
    let series: [CombinedRegisterChartSeries]

    var pointCount: Int {
        series.reduce(0) { $0 + $1.points.count }
    }
}

enum CombinedRegisterChartEngine {
    static func make(
        accounts: [FinanceAccount],
        rows: [FinanceTransaction],
        isFiltered: Bool,
        calendar: Calendar = .current
    ) -> CombinedRegisterChartSnapshot {
        let mode: CombinedRegisterChartMode = isFiltered
            ? .filteredMovement : .balance
        var valuesByCurrency: [String: Int64] = [:]
        if !isFiltered {
            for account in accounts {
                valuesByCurrency[account.currency, default: 0] +=
                    account.openingBalanceMinor
            }
        }

        var dailyPoints: [String: [Date: CombinedRegisterChartPoint]] = [:]
        for transaction in rows.sorted(by: chronologicalTransactionOrder) {
            if transaction.status == .cancelled
                || isFiltered && transaction.transferID != nil {
                continue
            }
            valuesByCurrency[transaction.currency, default: 0] +=
                transaction.amountMinor
            let day = calendar.startOfDay(for: transaction.bookingDate)
            dailyPoints[transaction.currency, default: [:]][day] =
                CombinedRegisterChartPoint(
                    date: day,
                    valueMinor: valuesByCurrency[transaction.currency] ?? 0,
                    lastTransactionID: transaction.id
                )
        }

        let series: [CombinedRegisterChartSeries] = dailyPoints.compactMap {
            entry -> CombinedRegisterChartSeries? in
            let (currency, values) = entry
            let points = values.values.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.lastTransactionID.uuidString
                    < $1.lastTransactionID.uuidString
            }
            guard !points.isEmpty else { return nil }
            return CombinedRegisterChartSeries(
                currency: currency,
                points: points
            )
        }.sorted { $0.currency < $1.currency }
        return CombinedRegisterChartSnapshot(mode: mode, series: series)
    }

    private static func chronologicalTransactionOrder(
        _ lhs: FinanceTransaction,
        _ rhs: FinanceTransaction
    ) -> Bool {
        if lhs.bookingDate != rhs.bookingDate {
            return lhs.bookingDate < rhs.bookingDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum RegisterAccessibility {
    static func cellLabel(column: RegisterColumn, value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(column.title): \(normalized.isEmpty ? "Leer" : normalized)"
    }

    static func tableValue(visibleCount: Int, selectedCount: Int) -> String {
        let visible = "\(visibleCount) Buchung\(visibleCount == 1 ? "" : "en")"
        guard selectedCount > 0 else { return visible }
        return "\(visible), \(selectedCount) ausgewählt"
    }
}

struct RegisterSortLabels: Equatable, Sendable {
    var account: String
    var category: String
    var tags: String
}

struct RegisterSortState: Equatable, Sendable {
    var column: RegisterColumn
    var ascending: Bool
}

enum RegisterSortInteraction {
    static func state(
        from sortOrder: [RegisterTableComparator],
        fallback: RegisterSortState
    ) -> RegisterSortState {
        guard let comparator = sortOrder.first else { return fallback }
        return RegisterSortState(
            column: comparator.column,
            ascending: comparator.order == .forward
        )
    }
}

struct RegisterTableComparator: SortComparator {
    var column: RegisterColumn
    var order: SortOrder = .forward
    var runningBalances: [UUID: Int64] = [:]
    var labels: [UUID: RegisterSortLabels] = [:]

    static func == (
        left: RegisterTableComparator,
        right: RegisterTableComparator
    ) -> Bool {
        left.column == right.column && left.order == right.order
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(column)
        hasher.combine(order)
    }

    func compare(
        _ left: FinanceTransaction,
        _ right: FinanceTransaction
    ) -> ComparisonResult {
        let primary = RegisterSorter.comparison(
            left,
            right,
            column: column,
            runningBalances: runningBalances,
            labels: labels
        )
        if primary != .orderedSame {
            guard order == .reverse else { return primary }
            return primary == .orderedAscending
                ? .orderedDescending : .orderedAscending
        }
        if left.bookingDate != right.bookingDate {
            return left.bookingDate < right.bookingDate
                ? .orderedAscending : .orderedDescending
        }
        if left.id == right.id { return .orderedSame }
        return left.id.uuidString < right.id.uuidString
            ? .orderedAscending : .orderedDescending
    }
}

enum RegisterSorter {
    static func sorted(
        _ transactions: [FinanceTransaction],
        by column: RegisterColumn,
        ascending: Bool,
        runningBalances: [UUID: Int64],
        labels: [UUID: RegisterSortLabels]
    ) -> [FinanceTransaction] {
        transactions.sorted { left, right in
            let comparison = comparison(
                left,
                right,
                column: column,
                runningBalances: runningBalances,
                labels: labels
            )
            if comparison != .orderedSame {
                return ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            if left.bookingDate != right.bookingDate {
                return left.bookingDate < right.bookingDate
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    static func comparison(
        _ left: FinanceTransaction,
        _ right: FinanceTransaction,
        column: RegisterColumn,
        runningBalances: [UUID: Int64],
        labels: [UUID: RegisterSortLabels]
    ) -> ComparisonResult {
        switch column {
        case .date:
            compare(left.bookingDate, right.bookingDate)
        case .valueDate:
            compare(
                left.valueDate ?? left.bookingDate,
                right.valueDate ?? right.bookingDate
            )
        case .reference:
            compare(left.reference, right.reference)
        case .status:
            compare(statusRank(left.status), statusRank(right.status))
        case .payee:
            compare(left.payee, right.payee)
        case .purpose:
            compare(left.purpose, right.purpose)
        case .category:
            compare(labels[left.id]?.category ?? "", labels[right.id]?.category ?? "")
        case .tags:
            compare(labels[left.id]?.tags ?? "", labels[right.id]?.tags ?? "")
        case .account:
            compare(labels[left.id]?.account ?? "", labels[right.id]?.account ?? "")
        case .amount:
            compare(left.amountMinor, right.amountMinor)
        case .debit:
            compare(
                RegisterAmountPresentation.minorUnits(
                    for: .debit, amountMinor: left.amountMinor
                ) ?? 0,
                RegisterAmountPresentation.minorUnits(
                    for: .debit, amountMinor: right.amountMinor
                ) ?? 0
            )
        case .credit:
            compare(
                RegisterAmountPresentation.minorUnits(
                    for: .credit, amountMinor: left.amountMinor
                ) ?? 0,
                RegisterAmountPresentation.minorUnits(
                    for: .credit, amountMinor: right.amountMinor
                ) ?? 0
            )
        case .balance:
            compare(
                runningBalances[left.id] ?? 0,
                runningBalances[right.id] ?? 0
            )
        }
    }

    private static func compare<T: Comparable>(
        _ left: T, _ right: T
    ) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }

    private static func compare(
        _ left: String, _ right: String
    ) -> ComparisonResult {
        left.compare(
            right,
            options: [.caseInsensitive, .diacriticInsensitive, .numeric],
            range: nil,
            locale: Locale(identifier: "de_DE")
        )
    }

    private static func statusRank(_ status: TransactionStatus) -> Int {
        TransactionStatus.allCases.firstIndex(of: status) ?? Int.max
    }
}

enum RegisterClipboard {
    static func tsv(
        transaction: FinanceTransaction,
        categoryPath: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy"
        return [
            formatter.string(from: transaction.bookingDate),
            transaction.payee,
            transaction.purpose,
            categoryPath,
            Money(
                minorUnits: transaction.amountMinor,
                currency: transaction.currency
            ).editingString,
            transaction.currency
        ]
        .map { $0.replacingOccurrences(of: "\t", with: " ") }
        .joined(separator: "\t")
    }
}

struct RegisterQuickEntryDraft: Equatable, Sendable {
    var accountID: UUID?
    var bookingDate: Date
    var payee: String
    var purpose: String
    var categoryID: UUID?
    var amountText: String
    var status: TransactionStatus = .booked

    func resolved(accounts: [FinanceAccount]) throws -> RegisterQuickEntryResolved {
        guard let accountID,
              let account = accounts.first(where: { $0.id == accountID })
        else { throw FinanceError.missingAccount }
        guard !account.isClosed else {
            throw FinanceError.database(
                "Auf einem geschlossenen Konto kann keine Buchung erfasst werden."
            )
        }
        guard !amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.database("Bitte gib einen Betrag ein.")
        }
        return RegisterQuickEntryResolved(
            accountID: account.id,
            bookingDate: Calendar.current.startOfDay(for: bookingDate),
            payee: payee.trimmingCharacters(in: .whitespacesAndNewlines),
            purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: categoryID,
            money: try Money(evaluating: amountText, currency: account.currency),
            status: status
        )
    }
}

struct RegisterQuickEntryResolved: Equatable, Sendable {
    let accountID: UUID
    let bookingDate: Date
    let payee: String
    let purpose: String
    let categoryID: UUID?
    let money: Money
    let status: TransactionStatus

    func transaction(id: UUID = UUID()) -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            accountID: accountID,
            bookingDate: bookingDate,
            valueDate: bookingDate,
            payee: payee,
            purpose: purpose,
            categoryID: categoryID,
            amountMinor: money.minorUnits,
            currency: money.currency,
            status: status,
            memo: "",
            reference: "",
            transferID: nil,
            importFingerprint: nil,
            splits: []
        )
    }
}

enum RegisterCategorySelection: Codable, Equatable, Sendable {
    case all
    case uncategorized
    case category(UUID)
}

enum RegisterF3Field: String, CaseIterable, Identifiable, Sendable {
    case payee
    case purpose
    case category
    case account
    case status

    var id: Self { self }

    var title: String {
        switch self {
        case .payee: "Empfänger"
        case .purpose: "Verwendungszweck"
        case .category: "Kategorie"
        case .account: "Konto"
        case .status: "Status"
        }
    }
}

enum RegisterF3Selection: Equatable, Sendable {
    case search(String)
    case category(RegisterCategorySelection)
    case account(UUID)
    case status(TransactionStatus)
}

extension RegisterF3Field {
    func selection(for transaction: FinanceTransaction) -> RegisterF3Selection? {
        switch self {
        case .payee:
            return searchSelection(transaction.payee)
        case .purpose:
            return searchSelection(transaction.purpose)
        case .category:
            if let categoryID = transaction.categoryID {
                return .category(.category(categoryID))
            }
            return .category(.uncategorized)
        case .account:
            return .account(transaction.accountID)
        case .status:
            return .status(transaction.status)
        }
    }

    private func searchSelection(_ value: String) -> RegisterF3Selection? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : .search(normalized)
    }
}

struct SavedRegisterView: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var accountID: UUID?
    var statusRawValue: String?
    var categorySelection: RegisterCategorySelection
    var tagID: UUID? = nil
    var periodRawValue: String
    var customStart: Date
    var customEnd: Date
    var rowModeRawValue: String
    var visibleColumns: Set<RegisterColumn>
    var sortColumnRawValue: String? = nil
    var sortAscending: Bool? = nil
    var amountColumnModeRawValue: String? = nil
}

struct SavedCombinedRegisterView: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var includedAccountIDs: Set<UUID>
    var statusRawValue: String?
    var categorySelection: RegisterCategorySelection
    var tagID: UUID? = nil
    var periodRawValue: String
    var customStart: Date
    var customEnd: Date
    var includeForecast: Bool
    var rowModeRawValue: String
    var visibleColumns: Set<RegisterColumn>
    var amountColumnModeRawValue: String? = nil
}

enum RegisterPreferencesCodec {
    static func encodeTabAccountIDs(_ ids: [UUID]) -> String {
        var seen = Set<UUID>()
        return ids
            .filter { seen.insert($0).inserted }
            .map(\.uuidString)
            .joined(separator: ",")
    }

    static func decodeTabAccountIDs(
        _ value: String,
        availableAccountIDs: Set<UUID>
    ) -> [UUID] {
        var seen = Set<UUID>()
        return value
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
            .filter {
                availableAccountIDs.contains($0) && seen.insert($0).inserted
            }
    }

    static func encodeColumns(_ columns: Set<RegisterColumn>) -> String {
        normalized(columns).map(\.rawValue).sorted().joined(separator: ",")
    }

    static func decodeColumns(_ value: String) -> Set<RegisterColumn> {
        let decoded = Set(
            value.split(separator: ",").compactMap {
                RegisterColumn(rawValue: String($0))
            }
        )
        return normalized(decoded)
    }

    static func addingBalanceColumn(to value: String) -> String {
        var columns = decodeColumns(value)
        columns.insert(.balance)
        return encodeColumns(columns)
    }

    static func addingBalanceColumnToViews(_ value: String) -> String {
        let migrated = decodeViews(value).map { view in
            var migratedView = view
            migratedView.visibleColumns.insert(.balance)
            return migratedView
        }
        return (try? encodeViews(migrated)) ?? value
    }

    static func encodeViews(_ views: [SavedRegisterView]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(views), as: UTF8.self)
    }

    static func decodeViews(_ value: String) -> [SavedRegisterView] {
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([SavedRegisterView].self, from: data) else {
            return []
        }
        var seen = Set<UUID>()
        return decoded
            .filter { seen.insert($0.id).inserted }
            .map { view in
                var normalizedView = view
                normalizedView.name = view.name.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                normalizedView.visibleColumns = normalized(view.visibleColumns)
                return normalizedView
            }
            .filter { !$0.name.isEmpty }
    }

    static func encodeCombinedViews(
        _ views: [SavedCombinedRegisterView]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(views), as: UTF8.self)
    }

    static func decodeCombinedViews(
        _ value: String
    ) -> [SavedCombinedRegisterView] {
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(
            [SavedCombinedRegisterView].self,
            from: data
        ) else { return [] }
        var seen = Set<UUID>()
        return decoded.compactMap { view in
            guard seen.insert(view.id).inserted else { return nil }
            var normalizedView = view
            normalizedView.name = view.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            normalizedView.visibleColumns = normalized(view.visibleColumns)
            return normalizedView.name.isEmpty ? nil : normalizedView
        }
    }

    private static func normalized(
        _ columns: Set<RegisterColumn>
    ) -> Set<RegisterColumn> {
        let supported = columns.intersection(Set(RegisterColumn.configurableCases))
        return supported.isEmpty ? RegisterColumn.defaultSet : supported
    }
}
