import CryptoKit
import Foundation

enum BankingProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case simulator
    case finTS
    case openBanking
    case webConnector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simulator: "Lokaler Simulator"
        case .finTS: "FinTS/HBCI"
        case .openBanking: "PSD2/Open Banking"
        case .webConnector: "Web-Connector"
        }
    }

    var isProductionEnabled: Bool { false }
}

enum BankingConnectionStatus: String, Codable, CaseIterable, Sendable {
    case inactive
    case ready
    case syncing
    case consentRequired
    case warning
    case failed

    var title: String {
        switch self {
        case .inactive: "Inaktiv"
        case .ready: "Bereit"
        case .syncing: "Abruf läuft"
        case .consentRequired: "Zustimmung erforderlich"
        case .warning: "Hinweis"
        case .failed: "Fehler"
        }
    }
}

enum BankingOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case accounts
    case balances
    case transactions
    case pendingTransactions
    case standingOrders
    case scheduledPayments
    case holdings
    case prices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: "Kontenliste"
        case .balances: "Salden"
        case .transactions: "Gebuchte Umsätze"
        case .pendingTransactions: "Vormerkposten"
        case .standingOrders: "Dauerauftragsbestand"
        case .scheduledPayments: "Terminüberweisungen"
        case .holdings: "Depotbestand"
        case .prices: "Kurse"
        }
    }
}

struct BankingConnection: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var providerKind: BankingProviderKind
    var adapterIdentifier: String
    var institutionName: String
    var status: BankingConnectionStatus
    var consentValidUntil: Date?
    var lastSyncAt: Date?
    var lastUserMessage: String
    var isEnabled: Bool
}

struct BankingAccountMapping: Identifiable, Hashable, Sendable {
    let id: UUID
    let connectionID: UUID
    let externalAccountID: String
    var remoteName: String
    var remoteIBAN: String
    var currency: String
    var localAccountID: UUID?
    var isEnabled: Bool
}

enum BankingLaunchScope: Hashable, Sendable {
    case account(UUID)
    case group(id: UUID, name: String, accountIDs: Set<UUID>)

    var localAccountIDs: Set<UUID> {
        switch self {
        case let .account(id): [id]
        case let .group(_, _, accountIDs): accountIDs
        }
    }

    var title: String {
        switch self {
        case .account: "Kontoabruf"
        case let .group(_, name, _): "Gruppenabruf: \(name)"
        }
    }
}

struct BankingLaunchSelection: Equatable, Sendable {
    let connectionID: UUID
    let externalAccountIDs: Set<String>
    let requestedLocalAccountIDs: Set<UUID>
    let matchedLocalAccountIDs: Set<UUID>

    var unmatchedLocalAccountIDs: Set<UUID> {
        requestedLocalAccountIDs.subtracting(matchedLocalAccountIDs)
    }
}

enum BankingLaunchSelectionResolver {
    static func resolve(
        scope: BankingLaunchScope,
        connections: [BankingConnection],
        mappings: [BankingAccountMapping]
    ) -> BankingLaunchSelection? {
        let requested = scope.localAccountIDs
        guard !requested.isEmpty else { return nil }
        let enabledConnectionIDs = Set(
            connections.filter(\.isEnabled).map(\.id)
        )
        let candidates = mappings.filter {
            $0.isEnabled
                && enabledConnectionIDs.contains($0.connectionID)
                && $0.localAccountID.map(requested.contains) == true
        }
        let grouped = Dictionary(grouping: candidates, by: \.connectionID)
        guard let best = grouped.max(by: { lhs, rhs in
            let leftCount = Set(lhs.value.compactMap(\.localAccountID)).count
            let rightCount = Set(rhs.value.compactMap(\.localAccountID)).count
            if leftCount != rightCount { return leftCount < rightCount }
            return lhs.key.uuidString > rhs.key.uuidString
        }) else { return nil }
        return BankingLaunchSelection(
            connectionID: best.key,
            externalAccountIDs: Set(best.value.map(\.externalAccountID)),
            requestedLocalAccountIDs: requested,
            matchedLocalAccountIDs: Set(best.value.compactMap(\.localAccountID))
        )
    }
}

struct BankingRemoteAccount: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let iban: String
    let bic: String
    let currency: String
    let accountType: String
    let ownerName: String
}

struct BankingBalance: Hashable, Codable, Sendable {
    let externalAccountID: String
    let bookedMinor: Int64
    let availableMinor: Int64?
    let currency: String
    let asOf: Date
}

struct BankingTransaction: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let externalAccountID: String
    let bookingDate: Date
    let valueDate: Date?
    let amountMinor: Int64
    let currency: String
    let payee: String
    let purpose: String
    let reference: String
    let counterpartyIBAN: String
    let counterpartyBIC: String
    let endToEndID: String
    let mandateReference: String
    let creditorID: String
    let bookingText: String
    let isPending: Bool
    let balanceAfterMinor: Int64?
}

struct BankingRemoteStandingOrder: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let externalAccountID: String
    let recipientName: String
    let recipientIBAN: String
    let amountMinor: Int64
    let currency: String
    let purpose: String
    let nextExecutionDate: Date
    let frequency: String
    let isScheduledPayment: Bool
}

struct BankingDiagnostic: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let accountID: String?
    let operation: BankingOperation
    let isSuccess: Bool
    let userMessage: String
    let technicalCode: String
}

struct BankingFetchRequest: Hashable, Sendable {
    let externalAccountIDs: Set<String>
    let operations: Set<BankingOperation>
    let dateFrom: Date?
}

struct BankingFetchPackage: Hashable, Codable, Sendable {
    let adapterIdentifier: String
    let providerIdentifier: String
    let fetchedAt: Date
    let rawPayloadHash: String
    let accounts: [BankingRemoteAccount]
    let balances: [BankingBalance]
    let transactions: [BankingTransaction]
    let standingOrders: [BankingRemoteStandingOrder]
    let diagnostics: [BankingDiagnostic]
}

struct BankingDownloadPreview: Identifiable, Sendable {
    let connection: BankingConnection
    let package: BankingFetchPackage
    let importPreview: ImportPreview
    let balancesByLocalAccountID: [UUID: BankingBalance]
    let selectedExternalAccountIDs: Set<String>
    let requestedOperations: Set<BankingOperation>
    let ruleWarnings: [String]
    let appliedRuleNamesByTransactionID: [UUID: [String]]

    var id: String { package.rawPayloadHash }
}

struct BankingSyncRun: Identifiable, Hashable, Sendable {
    let id: UUID
    let connectionID: UUID
    let startedAt: Date
    let completedAt: Date?
    let status: BankingConnectionStatus
    let requestedOperations: Set<BankingOperation>
    let importedCount: Int
    let matchedCount: Int
    let skippedCount: Int
    let userMessage: String
    let technicalCode: String
    let rawPayloadHash: String
}

protocol ReadOnlyBankingAdapter: Sendable {
    var identifier: String { get }
    var providerKind: BankingProviderKind { get }
    var supportedOperations: Set<BankingOperation> { get }

    func fetch(_ request: BankingFetchRequest) async throws
        -> BankingFetchPackage
}

struct SimulatorBankingAdapter: ReadOnlyBankingAdapter {
    let identifier = "de.pixelpuxel.finanzverwalter.banking-simulator.v1"
    let providerKind = BankingProviderKind.simulator
    let supportedOperations: Set<BankingOperation> = [
        .accounts, .balances, .transactions, .pendingTransactions,
        .standingOrders, .scheduledPayments
    ]

    let accounts: [BankingRemoteAccount]
    let anchorDate: Date

    func fetch(
        _ request: BankingFetchRequest
    ) async throws -> BankingFetchPackage {
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(250))
        try Task.checkCancellation()

        let selected = accounts.filter {
            request.externalAccountIDs.contains($0.id)
        }
        let calendar = Calendar(identifier: .gregorian)
        var balances: [BankingBalance] = []
        var transactions: [BankingTransaction] = []
        var standingOrders: [BankingRemoteStandingOrder] = []
        var diagnostics: [BankingDiagnostic] = []

        for (index, account) in selected.enumerated() {
            try Task.checkCancellation()
            let baseBalance = Int64(245_000 + index * 81_300)
            if request.operations.contains(.balances) {
                balances.append(
                    BankingBalance(
                        externalAccountID: account.id,
                        bookedMinor: baseBalance,
                        availableMinor: baseBalance - 25_000,
                        currency: account.currency,
                        asOf: anchorDate
                    )
                )
            }
            if request.operations.contains(.transactions) {
                transactions.append(
                    transaction(
                        account: account,
                        suffix: "booked-1",
                        dayOffset: -2,
                        amountMinor: -5_432,
                        payee: "Stadtwerke Musterstadt",
                        purpose: "Abschlag Energie",
                        pending: false,
                        balanceAfterMinor: baseBalance
                    )
                )
                transactions.append(
                    transaction(
                        account: account,
                        suffix: "booked-2",
                        dayOffset: -5,
                        amountMinor: 185_000,
                        payee: "Muster Arbeitgeber GmbH",
                        purpose: "Gehalt",
                        pending: false,
                        balanceAfterMinor: baseBalance + 5_432
                    )
                )
            }
            if request.operations.contains(.pendingTransactions) {
                transactions.append(
                    transaction(
                        account: account,
                        suffix: "pending-1",
                        dayOffset: 0,
                        amountMinor: -2_599,
                        payee: "Muster Markt",
                        purpose: "Kartenzahlung vorgemerkt",
                        pending: true,
                        balanceAfterMinor: nil
                    )
                )
            }
            if request.operations.contains(.standingOrders) {
                standingOrders.append(
                    BankingRemoteStandingOrder(
                        id: account.id + ":standing-rent",
                        externalAccountID: account.id,
                        recipientName: "Muster Vermietung",
                        recipientIBAN: "DE89370400440532013000",
                        amountMinor: 89_000,
                        currency: account.currency,
                        purpose: "Miete",
                        nextExecutionDate: calendar.date(
                            byAdding: .day,
                            value: 5,
                            to: anchorDate
                        ) ?? anchorDate,
                        frequency: "monthly",
                        isScheduledPayment: false
                    )
                )
            }
            if request.operations.contains(.scheduledPayments) {
                standingOrders.append(
                    BankingRemoteStandingOrder(
                        id: account.id + ":scheduled-tax",
                        externalAccountID: account.id,
                        recipientName: "Finanzkasse Musterstadt",
                        recipientIBAN: "DE89370400440532013000",
                        amountMinor: 12_500,
                        currency: account.currency,
                        purpose: "Terminüberweisung",
                        nextExecutionDate: calendar.date(
                            byAdding: .day,
                            value: 10,
                            to: anchorDate
                        ) ?? anchorDate,
                        frequency: "once",
                        isScheduledPayment: true
                    )
                )
            }
            for operation in request.operations.sorted(by: {
                $0.rawValue < $1.rawValue
            }) {
                diagnostics.append(
                    BankingDiagnostic(
                        id: RuleEngine.stableUUID(
                            account.id + ":" + operation.rawValue
                        ),
                        accountID: account.id,
                        operation: operation,
                        isSuccess: true,
                        userMessage: "(operation.title) erfolgreich simuliert",
                        technicalCode: "SIM-OK"
                    )
                )
            }
        }

        let material = try Self.encoder.encode(
            RawMaterial(
                adapterIdentifier: identifier,
                anchorDate: anchorDate,
                accounts: selected,
                balances: balances,
                transactions: transactions,
                standingOrders: standingOrders
            )
        )
        let rawHash = SHA256.hash(data: material)
            .map { String(format: "%02x", $0) }
            .joined()
        return BankingFetchPackage(
            adapterIdentifier: identifier,
            providerIdentifier: "SIMULATOR",
            fetchedAt: anchorDate,
            rawPayloadHash: rawHash,
            accounts: selected,
            balances: balances,
            transactions: transactions,
            standingOrders: standingOrders,
            diagnostics: diagnostics
        )
    }

    private func transaction(
        account: BankingRemoteAccount,
        suffix: String,
        dayOffset: Int,
        amountMinor: Int64,
        payee: String,
        purpose: String,
        pending: Bool,
        balanceAfterMinor: Int64?
    ) -> BankingTransaction {
        let date = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: dayOffset,
            to: anchorDate
        ) ?? anchorDate
        let externalID = account.id + ":" + suffix
        return BankingTransaction(
            id: externalID,
            externalAccountID: account.id,
            bookingDate: date,
            valueDate: pending ? nil : date,
            amountMinor: amountMinor,
            currency: account.currency,
            payee: payee,
            purpose: purpose,
            reference: "SIM-" + suffix.uppercased(),
            counterpartyIBAN: "DE89370400440532013000",
            counterpartyBIC: "COBADEFFXXX",
            endToEndID: "E2E-" + externalID,
            mandateReference: amountMinor < 0 ? "MANDAT-SIM" : "",
            creditorID: amountMinor < 0 ? "DE98ZZZ09999999999" : "",
            bookingText: pending ? "Vormerkposten" : "Umsatz",
            isPending: pending,
            balanceAfterMinor: balanceAfterMinor
        )
    }

    private struct RawMaterial: Codable {
        let adapterIdentifier: String
        let anchorDate: Date
        let accounts: [BankingRemoteAccount]
        let balances: [BankingBalance]
        let transactions: [BankingTransaction]
        let standingOrders: [BankingRemoteStandingOrder]
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()
}

enum BankingImportNormalizer {
    static func preview(
        connection: BankingConnection,
        package: BankingFetchPackage,
        mappings: [BankingAccountMapping],
        existingTransactions: [FinanceTransaction],
        rules: [CategorizationRule],
        selectedExternalAccountIDs: Set<String>,
        requestedOperations: Set<BankingOperation>,
        dateWindowDays: Int
    ) throws -> BankingDownloadPreview {
        let pairs: [(String, UUID)] = mappings.compactMap { mapping in
            mapping.localAccountID.map { (mapping.externalAccountID, $0) }
        }
        guard pairs.count == mappings.count,
              Set(pairs.map(\.0)).count == pairs.count,
              Set(pairs.map(\.1)).count == pairs.count
        else {
            throw FinanceError.database(
                "Jedes ausgewählte Bankkonto muss genau einem lokalen Konto zugeordnet sein."
            )
        }
        let localByExternal = Dictionary(uniqueKeysWithValues: pairs)
        let packageFingerprint =
            "banking:\(connection.id.uuidString):\(package.rawPayloadHash)"
        var warnings = Set<String>()
        var appliedRuleNames: [UUID: [String]] = [:]
        let rows: [FinanceTransaction] = try package.transactions.map { remote in
            guard let localAccountID = localByExternal[remote.externalAccountID]
            else {
                throw FinanceError.database(
                    "Ein abgerufener Umsatz gehört zu keinem zugeordneten Bankkonto."
                )
            }
            var value = FinanceTransaction(
                id: RuleEngine.stableUUID(
                    connection.id.uuidString + ":" + remote.id
                ),
                accountID: localAccountID,
                bookingDate: remote.bookingDate,
                valueDate: remote.valueDate,
                payee: remote.payee,
                purpose: remote.purpose,
                categoryID: nil,
                amountMinor: remote.amountMinor,
                currency: remote.currency,
                status: remote.isPending ? .pending : .booked,
                memo: "",
                reference: remote.reference,
                transferID: nil,
                importFingerprint: packageFingerprint,
                splits: [],
                origin: .bankDownload,
                externalProvider: connection.adapterIdentifier,
                externalTransactionID: remote.id,
                counterpartyIBAN: remote.counterpartyIBAN,
                endToEndID: remote.endToEndID,
                mandateReference: remote.mandateReference,
                bankBalanceAfterMinor: remote.balanceAfterMinor,
                counterpartyBIC: remote.counterpartyBIC,
                creditorID: remote.creditorID,
                bookingText: remote.bookingText
            )
            let matchingRules = rules.filter { $0.matches(value) }
            if !RuleEngine.conflicts(
                rules: matchingRules,
                transactions: [value]
            ).isEmpty {
                warnings.insert(
                    "\(remote.payee): widersprüchliche Regeln wurden nicht automatisch angewandt"
                )
            } else {
                var names: [String] = []
                for rule in matchingRules.sorted(by: ruleOrder) {
                    value = try RuleEngine.transformed(value, by: rule)
                    value.origin = .bankDownload
                    names.append(rule.name)
                    if rule.stopAfterMatch { break }
                }
                if !names.isEmpty { appliedRuleNames[value.id] = names }
            }
            try value.validate()
            return value
        }
        let importPreview = ImportPreview(
            rows: rows,
            rejectedRows: [],
            fingerprint: packageFingerprint
        ).matched(
            against: existingTransactions,
            dateWindowDays: dateWindowDays
        )
        let balances = Dictionary(
            uniqueKeysWithValues: package.balances.compactMap { balance in
                localByExternal[balance.externalAccountID].map { ($0, balance) }
            }
        )
        return BankingDownloadPreview(
            connection: connection,
            package: package,
            importPreview: importPreview,
            balancesByLocalAccountID: balances,
            selectedExternalAccountIDs: selectedExternalAccountIDs,
            requestedOperations: requestedOperations,
            ruleWarnings: warnings.sorted(),
            appliedRuleNamesByTransactionID: appliedRuleNames
        )
    }

    private static func ruleOrder(
        _ left: CategorizationRule,
        _ right: CategorizationRule
    ) -> Bool {
        if left.priority != right.priority { return left.priority < right.priority }
        return left.id.uuidString < right.id.uuidString
    }
}
