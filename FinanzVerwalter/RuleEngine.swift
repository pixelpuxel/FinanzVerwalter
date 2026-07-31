import CryptoKit
import Foundation

enum RuleGroupLogic: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle Bedingungen (UND)"
        case .any: "Mindestens eine Bedingung (ODER)"
        }
    }
}

enum RuleField: String, Codable, CaseIterable, Identifiable, Sendable {
    case payee
    case purpose
    case counterpartyIBAN
    case counterpartyBIC
    case amount
    case sign
    case account
    case bookingText
    case reference
    case mandateReference
    case creditorID
    case endToEndID
    case bookingDate
    case memo
    case status
    case origin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payee: "Empfänger/Auftraggeber"
        case .purpose: "Verwendungszweck"
        case .counterpartyIBAN: "IBAN"
        case .counterpartyBIC: "BIC"
        case .amount: "Betrag"
        case .sign: "Vorzeichen"
        case .account: "Konto"
        case .bookingText: "Buchungstext"
        case .reference: "Referenz"
        case .mandateReference: "Mandatsreferenz"
        case .creditorID: "Gläubiger-ID"
        case .endToEndID: "End-to-End-ID"
        case .bookingDate: "Zeitraum"
        case .memo: "Notiz"
        case .status: "Status"
        case .origin: "Herkunft"
        }
    }
}

enum RuleOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    case equals
    case contains
    case beginsWith
    case endsWith
    case regex
    case between
    case isEmpty
    case isNotEmpty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equals: "ist gleich"
        case .contains: "enthält"
        case .beginsWith: "beginnt mit"
        case .endsWith: "endet mit"
        case .regex: "entspricht Regex"
        case .between: "liegt zwischen"
        case .isEmpty: "ist leer"
        case .isNotEmpty: "ist nicht leer"
        }
    }

    var needsValue: Bool {
        self != .isEmpty && self != .isNotEmpty
    }

    var needsSecondValue: Bool { self == .between }
}

struct RuleCondition: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var field: RuleField
    var operation: RuleOperator
    var value: String
    var secondValue: String

    init(
        id: UUID = UUID(),
        field: RuleField,
        operation: RuleOperator,
        value: String = "",
        secondValue: String = ""
    ) {
        self.id = id
        self.field = field
        self.operation = operation
        self.value = value
        self.secondValue = secondValue
    }
}

indirect enum RuleExpression: Codable, Hashable, Sendable {
    case condition(RuleCondition)
    case group(RuleGroupLogic, [RuleExpression])
}

enum RuleAction: Codable, Hashable, Sendable {
    case setCategory(UUID)
    case normalizePayee(String)
    case setMemo(String)
    case addTags([UUID])
    case replacePurpose(search: String, replacement: String, useRegex: Bool)
    case copyPurposeToMemo
    case createSingleSplit(categoryID: UUID, memo: String)

    var fieldKey: String {
        switch self {
        case .setCategory, .createSingleSplit: "category"
        case .normalizePayee: "payee"
        case .setMemo, .copyPurposeToMemo: "memo"
        case .addTags: "tags"
        case .replacePurpose: "purpose"
        }
    }

    var title: String {
        switch self {
        case .setCategory: "Kategorie setzen"
        case .normalizePayee: "Empfänger normalisieren"
        case .setMemo: "Notiz setzen"
        case .addTags: "Klassen/Tags ergänzen"
        case .replacePurpose: "Verwendungszweck ersetzen"
        case .copyPurposeToMemo: "Zweck in Notiz kopieren"
        case .createSingleSplit: "Split erzeugen"
        }
    }
}

struct RuleDefinition: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var expression: RuleExpression
    var actions: [RuleAction]
}

struct RuleFieldChange: Identifiable, Hashable, Sendable {
    let id: String
    let field: String
    let before: String
    let after: String
}

struct RuleTransactionPreview: Identifiable, Hashable, Sendable {
    let id: UUID
    let before: FinanceTransaction
    let after: FinanceTransaction
    let changes: [RuleFieldChange]
}

struct RuleConflict: Identifiable, Hashable, Sendable {
    let transactionID: UUID
    let field: String
    let ruleNames: [String]

    var id: String {
        transactionID.uuidString + ":" + field
    }
}

struct RuleApplicationResult: Equatable, Sendable {
    let runID: UUID
    let changedCount: Int
}

struct RuleUndoSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let ruleName: String
    let appliedAt: Date
    let transactionCount: Int
}

enum RuleEngine {
    static func validate(_ rule: CategorizationRule) throws {
        guard !rule.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw FinanceError.database("Der Regelname fehlt.")
        }
        try validate(rule.effectiveExpression)
        guard !rule.effectiveActions.isEmpty else {
            throw FinanceError.database(
                "Die Regel benötigt mindestens eine Aktion."
            )
        }
        let actionFields = rule.effectiveActions.map(\.fieldKey)
        guard Set(actionFields).count == actionFields.count else {
            throw FinanceError.database(
                "Eine Regel darf dasselbe Zielfeld nicht widersprüchlich mehrfach ändern."
            )
        }
        for action in rule.effectiveActions {
            if case .replacePurpose(let search, _, let useRegex) = action {
                guard !search.isEmpty else {
                    throw FinanceError.database(
                        "Der zu ersetzende Text darf nicht leer sein."
                    )
                }
                if useRegex {
                    _ = try validatedRegex(search)
                }
            }
            if case .normalizePayee(let value) = action,
               value.trimmingCharacters(
                    in: .whitespacesAndNewlines
               ).isEmpty {
                throw FinanceError.database(
                    "Ein normalisierter Empfänger darf nicht leer sein."
                )
            }
        }
    }

    static func matches(
        _ expression: RuleExpression,
        transaction: FinanceTransaction
    ) -> Bool {
        switch expression {
        case .condition(let condition):
            return matches(condition, transaction: transaction)
        case .group(let logic, let children):
            guard !children.isEmpty else { return true }
            switch logic {
            case .all:
                return children.allSatisfy {
                    matches($0, transaction: transaction)
                }
            case .any:
                return children.contains {
                    matches($0, transaction: transaction)
                }
            }
        }
    }

    static func preview(
        rule: CategorizationRule,
        transactions: [FinanceTransaction]
    ) -> [RuleTransactionPreview] {
        transactions
            .filter(rule.matches)
            .compactMap { transaction in
                guard let after = try? transformed(transaction, by: rule) else {
                    return nil
                }
                let changes = changes(from: transaction, to: after)
                guard !changes.isEmpty else { return nil }
                return RuleTransactionPreview(
                    id: transaction.id,
                    before: transaction,
                    after: after,
                    changes: changes
                )
            }
            .sorted {
                if $0.before.bookingDate != $1.before.bookingDate {
                    return $0.before.bookingDate < $1.before.bookingDate
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    static func transformed(
        _ transaction: FinanceTransaction,
        by rule: CategorizationRule
    ) throws -> FinanceTransaction {
        var value = transaction
        for action in rule.effectiveActions {
            switch action {
            case .setCategory(let categoryID):
                guard value.splits.isEmpty else {
                    throw FinanceError.database(
                        "Eine Splitbuchung kann nicht pauschal kategorisiert werden."
                    )
                }
                value.categoryID = categoryID
            case .normalizePayee(let payee):
                value.payee = payee.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            case .setMemo(let memo):
                value.memo = memo
            case .addTags(let tagIDs):
                value.tagIDs = Array(Set(value.tagIDs).union(tagIDs))
                    .sorted { $0.uuidString < $1.uuidString }
            case .replacePurpose(let search, let replacement, let useRegex):
                if useRegex {
                    let regex = try NSRegularExpression(
                        pattern: search,
                        options: [.caseInsensitive]
                    )
                    let range = NSRange(
                        value.purpose.startIndex..<value.purpose.endIndex,
                        in: value.purpose
                    )
                    value.purpose = regex.stringByReplacingMatches(
                        in: value.purpose,
                        range: range,
                        withTemplate: replacement
                    )
                } else {
                    value.purpose = value.purpose.replacingOccurrences(
                        of: search,
                        with: replacement,
                        options: [.caseInsensitive]
                    )
                }
            case .copyPurposeToMemo:
                value.memo = value.purpose
            case .createSingleSplit(let categoryID, let memo):
                guard value.splits.isEmpty,
                      value.vatMode == .none
                else {
                    throw FinanceError.database(
                        "Ein Split kann nur aus einer ungeteilten Buchung ohne MwSt. erzeugt werden."
                    )
                }
                value.categoryID = nil
                value.splits = [
                    FinanceSplit(
                        id: UUID(),
                        categoryID: categoryID,
                        amountMinor: value.amountMinor,
                        memo: memo,
                        sortOrder: 0
                    )
                ]
            }
        }
        value.origin = .rule
        if value.duplicateFingerprint.isEmpty {
            value.duplicateFingerprint = ImportMatcher.strongFingerprint(value)
        }
        try value.validate()
        return value
    }

    static func conflicts(
        rules: [CategorizationRule],
        transactions: [FinanceTransaction]
    ) -> [RuleConflict] {
        var result: [RuleConflict] = []
        let active = rules.filter(\.isActive).sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.id.uuidString < $1.id.uuidString
        }
        for transaction in transactions where transaction.status != .reconciled
            && transaction.status != .cancelled {
            let matching = active.filter { $0.matches(transaction) }
            let byField = Dictionary(
                grouping: matching.flatMap { rule in
                    rule.effectiveActions.map {
                        ($0.fieldKey, $0, rule.name)
                    }
                },
                by: \.0
            )
            for (field, values) in byField
            where Set(values.map(\.1)).count > 1 {
                result.append(
                    RuleConflict(
                        transactionID: transaction.id,
                        field: field,
                        ruleNames: values.map(\.2)
                    )
                )
            }
        }
        return result.sorted {
            if $0.transactionID != $1.transactionID {
                return $0.transactionID.uuidString
                    < $1.transactionID.uuidString
            }
            return $0.field < $1.field
        }
    }

    static func definitionData(
        for rule: CategorizationRule
    ) throws -> Data {
        try encoder.encode(
            RuleDefinition(
                expression: rule.effectiveExpression,
                actions: rule.effectiveActions
            )
        )
    }

    static func definition(from data: Data) -> RuleDefinition? {
        guard let value = try? decoder.decode(
            RuleDefinition.self,
            from: data
        ), value.version == RuleDefinition.currentVersion
        else { return nil }
        return value
    }

    static func snapshotData(
        _ transaction: FinanceTransaction
    ) throws -> Data {
        try encoder.encode(transaction)
    }

    static func snapshot(
        from data: Data
    ) throws -> FinanceTransaction {
        try decoder.decode(FinanceTransaction.self, from: data)
    }

    static func snapshotFingerprint(
        _ transaction: FinanceTransaction
    ) throws -> String {
        let data = try snapshotData(transaction)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func stableUUID(_ material: String) -> UUID {
        let bytes = Array(
            SHA256.hash(data: Data(material.utf8)).prefix(16)
        )
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    private static func matches(
        _ condition: RuleCondition,
        transaction: FinanceTransaction
    ) -> Bool {
        let raw = fieldValue(condition.field, transaction: transaction)
        switch condition.operation {
        case .isEmpty:
            return normalized(raw).isEmpty
        case .isNotEmpty:
            return !normalized(raw).isEmpty
        case .equals:
            return normalized(raw) == normalized(condition.value)
        case .contains:
            return normalized(raw).contains(normalized(condition.value))
        case .beginsWith:
            return normalized(raw).hasPrefix(normalized(condition.value))
        case .endsWith:
            return normalized(raw).hasSuffix(normalized(condition.value))
        case .regex:
            guard let regex = try? validatedRegex(condition.value)
            else { return false }
            return regex.firstMatch(
                in: raw,
                range: NSRange(raw.startIndex..<raw.endIndex, in: raw)
            ) != nil
        case .between:
            return isBetween(
                raw,
                lower: condition.value,
                upper: condition.secondValue,
                field: condition.field
            )
        }
    }

    private static func fieldValue(
        _ field: RuleField,
        transaction: FinanceTransaction
    ) -> String {
        switch field {
        case .payee: transaction.payee
        case .purpose: transaction.purpose
        case .counterpartyIBAN: transaction.counterpartyIBAN
        case .counterpartyBIC: transaction.counterpartyBIC
        case .amount: String(transaction.amountMinor)
        case .sign:
            transaction.amountMinor < 0
                ? "Ausgabe" : transaction.amountMinor > 0 ? "Einnahme" : "Null"
        case .account: transaction.accountID.uuidString
        case .bookingText: transaction.bookingText
        case .reference: transaction.reference
        case .mandateReference: transaction.mandateReference
        case .creditorID: transaction.creditorID
        case .endToEndID: transaction.endToEndID
        case .bookingDate:
            transaction.bookingDate.formatted(
                .iso8601.year().month().day().dateSeparator(.dash)
            )
        case .memo: transaction.memo
        case .status: transaction.status.rawValue
        case .origin: transaction.origin.rawValue
        }
    }

    private static func validate(
        _ expression: RuleExpression
    ) throws {
        switch expression {
        case .condition(let condition):
            if condition.operation.needsValue
                && condition.value.isEmpty {
                throw FinanceError.database(
                    "Mindestens eine Regelbedingung hat keinen Wert."
                )
            }
            if condition.operation.needsSecondValue
                && condition.secondValue.isEmpty {
                throw FinanceError.database(
                    "Eine Bereichsbedingung benötigt zwei Grenzwerte."
                )
            }
            if condition.operation == .regex {
                _ = try validatedRegex(condition.value)
            }
            if condition.field == .amount
                && condition.operation == .between
                && (
                    Int64(condition.value) == nil
                        || Int64(condition.secondValue) == nil
                ) {
                throw FinanceError.database(
                    "Betragsbereiche werden centgenau als ganze Zahlen gespeichert."
                )
            }
        case .group(_, let children):
            for child in children { try validate(child) }
        }
    }

    private static func validatedRegex(
        _ pattern: String
    ) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        } catch {
            throw FinanceError.database(
                "Der reguläre Ausdruck ist ungültig: \(error.localizedDescription)"
            )
        }
    }

    private static func isBetween(
        _ raw: String,
        lower: String,
        upper: String,
        field: RuleField
    ) -> Bool {
        if field == .amount,
           let value = Int64(raw),
           let minimum = Int64(lower),
           let maximum = Int64(upper) {
            return value >= min(minimum, maximum)
                && value <= max(minimum, maximum)
        }
        let value = normalized(raw)
        let minimum = normalized(lower)
        let maximum = normalized(upper)
        return value >= min(minimum, maximum)
            && value <= max(minimum, maximum)
    }

    private static func changes(
        from before: FinanceTransaction,
        to after: FinanceTransaction
    ) -> [RuleFieldChange] {
        var values: [RuleFieldChange] = []
        func append(
            _ id: String,
            _ field: String,
            _ oldValue: String,
            _ newValue: String
        ) {
            guard oldValue != newValue else { return }
            values.append(
                RuleFieldChange(
                    id: id,
                    field: field,
                    before: oldValue,
                    after: newValue
                )
            )
        }
        append(
            "category",
            "Kategorie",
            before.categoryID?.uuidString ?? "Ohne Kategorie",
            after.categoryID?.uuidString
                ?? (after.splits.isEmpty ? "Ohne Kategorie" : "Split")
        )
        append("payee", "Empfänger", before.payee, after.payee)
        append("purpose", "Verwendungszweck", before.purpose, after.purpose)
        append("memo", "Notiz", before.memo, after.memo)
        append(
            "tags",
            "Klassen/Tags",
            before.tagIDs.map(\.uuidString).sorted().joined(separator: ","),
            after.tagIDs.map(\.uuidString).sorted().joined(separator: ",")
        )
        append(
            "splits",
            "Splits",
            String(before.splits.count),
            String(after.splits.count)
        )
        return values
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "de_DE")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()
}

extension CategorizationRule {
    var effectiveExpression: RuleExpression {
        if let expression { return expression }
        var conditions: [RuleExpression] = []
        if !payeeContains.isEmpty {
            conditions.append(
                .condition(
                    RuleCondition(
                        id: RuleEngine.stableUUID(
                            id.uuidString + ":legacy-payee"
                        ),
                        field: .payee,
                        operation: .contains,
                        value: payeeContains
                    )
                )
            )
        }
        if !purposeContains.isEmpty {
            conditions.append(
                .condition(
                    RuleCondition(
                        id: RuleEngine.stableUUID(
                            id.uuidString + ":legacy-purpose"
                        ),
                        field: .purpose,
                        operation: .contains,
                        value: purposeContains
                    )
                )
            )
        }
        if let minimumAmountMinor {
            conditions.append(
                .condition(
                    RuleCondition(
                        id: RuleEngine.stableUUID(
                            id.uuidString + ":legacy-minimum"
                        ),
                        field: .amount,
                        operation: .between,
                        value: String(minimumAmountMinor),
                        secondValue: String(maximumAmountMinor ?? Int64.max)
                    )
                )
            )
        } else if let maximumAmountMinor {
            conditions.append(
                .condition(
                    RuleCondition(
                        id: RuleEngine.stableUUID(
                            id.uuidString + ":legacy-maximum"
                        ),
                        field: .amount,
                        operation: .between,
                        value: String(Int64.min),
                        secondValue: String(maximumAmountMinor)
                    )
                )
            )
        }
        return .group(.all, conditions)
    }

    var effectiveActions: [RuleAction] {
        actions.isEmpty ? [.setCategory(categoryID)] : actions
    }
}
