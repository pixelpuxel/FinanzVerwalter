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
        case .amount, .balance: 105
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
        case .balance: 125
        }
    }

    static let defaultSet = Set(allCases)
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
    var periodRawValue: String
    var customStart: Date
    var customEnd: Date
    var rowModeRawValue: String
    var visibleColumns: Set<RegisterColumn>
}

struct SavedCombinedRegisterView: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var includedAccountIDs: Set<UUID>
    var statusRawValue: String?
    var categorySelection: RegisterCategorySelection
    var periodRawValue: String
    var customStart: Date
    var customEnd: Date
    var includeForecast: Bool
    var rowModeRawValue: String
    var visibleColumns: Set<RegisterColumn>
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
        return decoded.isEmpty ? RegisterColumn.defaultSet : decoded
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
        columns.isEmpty ? RegisterColumn.defaultSet : columns
    }
}
