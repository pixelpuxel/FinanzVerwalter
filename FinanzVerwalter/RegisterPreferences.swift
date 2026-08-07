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
