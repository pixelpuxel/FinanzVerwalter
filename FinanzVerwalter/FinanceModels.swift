import Foundation

enum AccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case checking
    case savings
    case fixedDeposit
    case cash
    case creditCard
    case clearing
    case foreignCurrency
    case investment
    case loan
    case asset
    case liability
    case receivable
    case inventory
    case rewards

    var id: Self { self }

    var defaultGroupName: String {
        switch self {
        case .checking, .savings, .fixedDeposit, .clearing, .foreignCurrency:
            "Bankkonten"
        case .creditCard:
            "Kreditkarten"
        case .cash:
            "Bargeld"
        case .investment:
            "Depots"
        case .loan:
            "Kredite"
        case .asset, .inventory:
            "Vermögen"
        case .liability:
            "Verbindlichkeiten"
        case .receivable:
            "Forderungen"
        case .rewards:
            "Sonstige"
        }
    }

    var title: String {
        switch self {
        case .checking: "Girokonto"
        case .savings: "Spar-/Tagesgeld"
        case .fixedDeposit: "Festgeld"
        case .cash: "Bargeld/Kasse"
        case .creditCard: "Kreditkarte"
        case .clearing: "Verrechnungskonto"
        case .foreignCurrency: "Fremdwährungskonto"
        case .investment: "Depot"
        case .loan: "Darlehen"
        case .asset: "Vermögenswert"
        case .liability: "Verbindlichkeit"
        case .receivable: "Rechnung/Forderung"
        case .inventory: "Inventarkonto"
        case .rewards: "Punkte/Bonus/Sonstiges"
        }
    }
}

enum AccountSyncStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case offline
    case ready
    case syncing
    case warning
    case failed

    var id: Self { self }
    var title: String {
        switch self {
        case .offline: "Offline"
        case .ready: "Bereit"
        case .syncing: "Abruf läuft"
        case .warning: "Hinweis"
        case .failed: "Fehler"
        }
    }
}

struct AccountGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var isActive: Bool
}

struct FinanceFileInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var baseCurrency: String
    var locale: String
    var timeZone: String
}

struct ReferenceRegisterDatasetManifest: Equatable, Sendable {
    let accountCount: Int
    let usedAccountGroupCount: Int
    let transactionCount: Int
    let splitRowCount: Int
    let transferCount: Int
    let currencies: Set<String>
    let earliestBookingDate: Date
    let latestBookingDate: Date
    let expectedReportNetByCurrency: [String: Int64]
}

struct FinanceAccount: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var institution: String
    var type: AccountType
    var currency: String
    var openingBalanceMinor: Int64
    var isHidden: Bool
    var isClosed: Bool
    var sortOrder: Int
    var shortName: String = ""
    var description: String = ""
    var groupID: UUID? = nil
    var iban: String = ""
    var bic: String = ""
    var accountNumberMasked: String = ""
    var ownerName: String = ""
    var openingDate: Date? = nil
    var creditLimitMinor: Int64 = 0
    var isOnline: Bool = false
    var includeNetWorth: Bool = true
    var includeBudget: Bool = true
    var includeReports: Bool = true
    var includeForecast: Bool = true
    var lastSyncAt: Date? = nil
    var lastBankBalanceMinor: Int64? = nil
    var syncStatus: AccountSyncStatus = .offline
    var subtype: String = ""
    var bankCode: String = ""
    var openingBalanceDate: Date? = nil
    var closingDate: Date? = nil
    var linkedAccountID: UUID? = nil
}

struct AccountClosureImpact: Equatable, Sendable {
    let activeScheduledTransactions: Int
    let activeStandingOrders: Int
    let openPaymentOrders: Int

    var openItemCount: Int {
        activeScheduledTransactions + activeStandingOrders + openPaymentOrders
    }

    static func evaluate(
        accountID: UUID,
        scheduledTransactions: [ScheduledTransaction],
        standingOrders: [StandingOrder],
        paymentOrders: [PaymentOrder]
    ) -> Self {
        Self(
            activeScheduledTransactions: scheduledTransactions.filter {
                $0.accountID == accountID && $0.isActive
            }.count,
            activeStandingOrders: standingOrders.filter {
                $0.accountID == accountID && $0.status == .active
            }.count,
            openPaymentOrders: paymentOrders.filter {
                $0.accountID == accountID
                    && ![PaymentStatus.accepted, .rejected, .cancelled].contains($0.status)
            }.count
        )
    }
}

enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case income
    case expense
    case transfer

    var title: String {
        switch self {
        case .income: "Einnahme"
        case .expense: "Ausgabe"
        case .transfer: "Umbuchung"
        }
    }
}

struct FinanceCategory: Identifiable, Hashable, Sendable {
    let id: UUID
    var parentID: UUID?
    var name: String
    var kind: CategoryKind
    var color: String
    var isActive: Bool
    var description: String = ""
    var isBudgetable: Bool = true
    var defaultVATCodeID: UUID? = nil
    var germanTaxLine: String = ""
    var usTaxLine: String = ""
}

enum TransactionStatus: String, Codable, CaseIterable, Sendable {
    case expected
    case pending
    case booked
    case cleared
    case reconciled
    case cancelled

    var title: String {
        switch self {
        case .expected: "Erwartet"
        case .pending: "Vorgemerkt"
        case .booked: "Gebucht"
        case .cleared: "Bestätigt"
        case .reconciled: "Abgeglichen"
        case .cancelled: "Storniert"
        }
    }
}

struct FinanceSplit: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var categoryID: UUID?
    var amountMinor: Int64
    var memo: String
    var sortOrder: Int
    var tagIDs: [UUID] = []
    var vatCodeID: UUID? = nil
    var vatMode: VATMode = .none
    var netMinor: Int64 = 0
    var taxMinor: Int64 = 0

    func validateVAT() throws {
        switch vatMode {
        case .none:
            guard vatCodeID == nil, netMinor == 0, taxMinor == 0 else {
                throw FinanceError.invalidVAT(
                    "Eine Splitzeile ohne MwSt. darf keine Steuerwerte enthalten."
                )
            }
        case .automatic, .manual:
            guard vatCodeID != nil, netMinor + taxMinor == amountMinor else {
                throw FinanceError.invalidVAT(
                    "Die MwSt.-Werte der Splitzeile sind unvollständig."
                )
            }
        }
    }
}

struct FinanceTransaction: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var accountID: UUID
    var bookingDate: Date
    var valueDate: Date?
    var payee: String
    var purpose: String
    var categoryID: UUID?
    var amountMinor: Int64
    var currency: String
    var status: TransactionStatus
    var memo: String
    var reference: String
    var transferID: UUID?
    var importFingerprint: String?
    var splits: [FinanceSplit]
    var payeeID: UUID? = nil
    var tagIDs: [UUID] = []
    var vatCodeID: UUID? = nil
    var vatMode: VATMode = .none
    var netMinor: Int64 = 0
    var taxMinor: Int64 = 0
    var origin: TransactionOrigin = .manual
    var externalProvider: String = ""
    var externalTransactionID: String = ""
    var counterpartyIBAN: String = ""
    var endToEndID: String = ""
    var mandateReference: String = ""
    var duplicateFingerprint: String = ""
    var bankBalanceAfterMinor: Int64? = nil
    var counterpartyBIC: String = ""
    var creditorID: String = ""
    var bookingText: String = ""
    var originalAmountMinor: Int64? = nil
    var originalCurrency: String = ""
    var exchangeRateScaled: Int64? = nil
    var flag: TransactionFlag? = nil

    func validate() throws {
        try validateForeignCurrency()
        if splits.isEmpty {
            switch vatMode {
            case .none:
                guard vatCodeID == nil, netMinor == 0, taxMinor == 0 else {
                    throw FinanceError.invalidVAT(
                        "Eine Buchung ohne MwSt. darf keine Steuerwerte enthalten."
                    )
                }
            case .automatic, .manual:
                guard vatCodeID != nil, netMinor + taxMinor == amountMinor else {
                    throw FinanceError.invalidVAT(
                        "Netto und Steuer müssen den Bruttobetrag ergeben."
                    )
                }
            }
            return
        }
        let sum = splits.reduce(Int64.zero) { $0 + $1.amountMinor }
        guard sum == amountMinor else {
            throw FinanceError.splitMismatch(expected: amountMinor, actual: sum)
        }
        try splits.forEach { try $0.validateVAT() }
        if splits.allSatisfy({ $0.vatMode == .none }) {
            guard vatCodeID == nil, vatMode == .none, netMinor == 0, taxMinor == 0 else {
                throw FinanceError.invalidVAT(
                    "Eine Splitbuchung ohne MwSt. darf keine Steuerwerte enthalten."
                )
            }
            return
        }
        let receipt = try VATCalculator.receipt(
            splits.map {
                VATBreakdown(
                    grossMinor: $0.amountMinor,
                    netMinor: $0.vatMode == .none ? $0.amountMinor : $0.netMinor,
                    taxMinor: $0.taxMinor
                )
            }
        )
        guard vatCodeID == nil,
              vatMode == .none,
              netMinor == receipt.netMinor,
              taxMinor == receipt.taxMinor
        else {
            throw FinanceError.invalidVAT(
                "Die MwSt.-Summen der Splitbuchung stimmen nicht mit den Zeilen überein."
            )
        }
    }

    private func validateForeignCurrency() throws {
        guard let originalAmountMinor, let exchangeRateScaled else {
            guard self.originalAmountMinor == nil,
                  self.exchangeRateScaled == nil,
                  originalCurrency.isEmpty else {
                throw FinanceError.invalidExchangeRate(
                    "Originalbetrag, Originalwährung und Wechselkurs müssen gemeinsam gesetzt sein."
                )
            }
            return
        }
        let sourceCurrency = originalCurrency.uppercased()
        let targetCurrency = currency.uppercased()
        guard sourceCurrency.count == 3, targetCurrency.count == 3,
              sourceCurrency != targetCurrency else {
            throw FinanceError.invalidExchangeRate(
                "Original- und Kontowährung müssen unterschiedliche ISO-Währungen sein."
            )
        }
        guard originalAmountMinor != 0, amountMinor != 0,
              (originalAmountMinor < 0) == (amountMinor < 0) else {
            throw FinanceError.invalidExchangeRate(
                "Original- und Kontobetrag müssen ungleich null sein und dasselbe Vorzeichen besitzen."
            )
        }
        let rate = try ExchangeRate(scaledValue: exchangeRateScaled)
        let converted = try rate.convertedMinor(
            originalMinor: originalAmountMinor,
            originalCurrency: sourceCurrency,
            bookedCurrency: targetCurrency
        )
        let difference = Decimal(converted) - Decimal(amountMinor)
        guard difference >= -1, difference <= 1 else {
            throw FinanceError.invalidExchangeRate(
                "Originalbetrag und Wechselkurs ergeben nicht den Kontobetrag."
            )
        }
    }
}

enum TransactionFlag: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple

    var id: Self { self }
    var title: String {
        switch self {
        case .red: "Rot"
        case .orange: "Orange"
        case .yellow: "Gelb"
        case .green: "Grün"
        case .blue: "Blau"
        case .purple: "Violett"
        }
    }
}

struct TransactionUndoSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let transactionCount: Int
    let createdAt: Date
}

enum AttachmentEntityType: String, Codable, CaseIterable, Sendable {
    case account
    case transaction
    case contract
    case security
    case inventory
}

struct FinanceAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let entityType: AttachmentEntityType
    let entityID: UUID
    let fileName: String
    let mimeType: String
    let byteCount: Int64
    let sha256: String
    let source: String
    let addedAt: Date
    let ocrText: String
}

enum SecureNoteLinkKind: String, Hashable, Sendable {
    case https
    case localFile
}

struct SecureNoteLink: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: SecureNoteLinkKind

    var id: String { url.absoluteString }

    var displayName: String {
        switch kind {
        case .https:
            guard let host = url.host else { return url.absoluteString }
            let path = url.path == "/" ? "" : url.path
            return host + path
        case .localFile:
            return url.lastPathComponent
        }
    }
}

enum SecureNoteLinkPolicy {
    private static let blockedLocalExtensions: Set<String> = [
        "app", "application", "appref-ms", "bat", "bin", "bash", "cmd",
        "command", "com", "csh", "exe", "fish", "gadget", "hta", "inf",
        "ins", "isp", "jar", "js", "jse", "ksh", "lnk", "msc", "msi",
        "msp", "mst", "pif", "pl", "ps1", "py", "rb", "reg", "run",
        "scr", "sh", "shortcut", "terminal", "url", "vb", "vbe", "vbs",
        "workflow", "ws", "wsc", "wsf", "wsh", "zsh"
    ]

    static func links(in text: String) -> [SecureNoteLink] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        return detector.matches(in: text, options: [], range: range).compactMap { match in
            guard let rawURL = match.url,
                  let link = permittedLink(rawURL),
                  seen.insert(link.id).inserted
            else { return nil }
            return link
        }
    }

    static func validatedURLForOpening(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let link = permittedLink(url) else {
            throw FinanceError.database(
                "Notizlinks dürfen nur HTTPS-Webseiten oder lokale Dateien verwenden."
            )
        }
        switch link.kind {
        case .https:
            return link.url
        case .localFile:
            let target = link.url.standardizedFileURL
            let values = try target.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isPackageKey,
                .isSymbolicLinkKey, .isExecutableKey
            ])
            let suffix = target.pathExtension.lowercased()
            guard values.isRegularFile == true,
                  values.isDirectory != true,
                  values.isPackage != true,
                  values.isSymbolicLink != true,
                  values.isExecutable != true,
                  !fileManager.isExecutableFile(atPath: target.path),
                  !blockedLocalExtensions.contains(suffix)
            else {
                throw FinanceError.database(
                    "Der lokale Notizlink ist keine sichere reguläre Datei."
                )
            }
            return target
        }
    }

    private static func permittedLink(_ url: URL) -> SecureNoteLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "https":
            guard url.host?.isEmpty == false,
                  url.user == nil, url.password == nil else { return nil }
            return SecureNoteLink(url: url, kind: .https)
        case "file":
            guard url.isFileURL,
                  url.user == nil, url.password == nil,
                  url.host == nil || url.host?.isEmpty == true || url.host == "localhost"
            else { return nil }
            return SecureNoteLink(url: url.standardizedFileURL, kind: .localFile)
        default:
            return nil
        }
    }
}

struct TransactionTemplateSplit: Codable, Hashable, Sendable {
    var categoryID: UUID?
    var amountMinor: Int64
    var memo: String
    var sortOrder: Int
    var tagIDs: [UUID]
    var vatCodeID: UUID?
    var vatMode: VATMode?
    var netMinor: Int64?
    var taxMinor: Int64?
}

enum TransactionTemplateField: String, Codable, CaseIterable, Identifiable, Sendable {
    case account
    case payee
    case purpose
    case category
    case amount
    case status
    case memo
    case tags
    case splits
    case vat
    case foreignCurrency
    case flag

    var id: Self { self }

    var title: String {
        switch self {
        case .account: "Konto"
        case .payee: "Empfänger"
        case .purpose: "Verwendungszweck"
        case .category: "Kategorie"
        case .amount: "Betrag"
        case .status: "Status"
        case .memo: "Notiz"
        case .tags: "Klassen/Tags"
        case .splits: "Splitzeilen"
        case .vat: "MwSt.-Angaben"
        case .foreignCurrency: "Fremdwährung"
        case .flag: "Kennzeichen"
        }
    }
}

struct TransactionTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var accountID: UUID
    var payee: String
    var purpose: String
    var categoryID: UUID?
    var amountMinor: Int64
    var currency: String
    var status: TransactionStatus
    var memo: String
    var payeeID: UUID?
    var tagIDs: [UUID]
    var splits: [TransactionTemplateSplit]
    var vatCodeID: UUID?
    var vatMode: VATMode?
    var netMinor: Int64?
    var taxMinor: Int64?
    var originalAmountMinor: Int64?
    var originalCurrency: String?
    var exchangeRateScaled: Int64?
    var flag: TransactionFlag?
    var includedFields: Set<TransactionTemplateField>?
    var isActive: Bool?
    var usageCount: Int?
    var lastUsedAt: Date?

    var effectiveFields: Set<TransactionTemplateField> {
        includedFields ?? Set(TransactionTemplateField.allCases)
    }

    var effectiveIsActive: Bool { isActive ?? true }
    var effectiveUsageCount: Int { usageCount ?? 0 }
    var isPartial: Bool {
        effectiveFields != Set(TransactionTemplateField.allCases)
    }

    init(
        id: UUID = UUID(),
        name: String,
        transaction: FinanceTransaction,
        includedFields: Set<TransactionTemplateField> = Set(
            TransactionTemplateField.allCases
        ),
        isActive: Bool = true,
        usageCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        accountID = transaction.accountID
        payee = transaction.payee
        purpose = transaction.purpose
        categoryID = transaction.categoryID
        amountMinor = transaction.amountMinor
        currency = transaction.currency
        switch transaction.status {
        case .reconciled, .cancelled:
            status = .booked
        default:
            status = transaction.status
        }
        memo = transaction.memo
        payeeID = transaction.payeeID
        tagIDs = transaction.tagIDs
        vatCodeID = transaction.vatCodeID
        vatMode = transaction.vatMode
        netMinor = transaction.netMinor
        taxMinor = transaction.taxMinor
        originalAmountMinor = transaction.originalAmountMinor
        originalCurrency = transaction.originalCurrency.isEmpty
            ? nil : transaction.originalCurrency
        exchangeRateScaled = transaction.exchangeRateScaled
        flag = transaction.flag
        self.includedFields = includedFields
        self.isActive = isActive
        self.usageCount = max(0, usageCount)
        self.lastUsedAt = lastUsedAt
        splits = transaction.splits.map {
            TransactionTemplateSplit(
                categoryID: $0.categoryID,
                amountMinor: $0.amountMinor,
                memo: $0.memo,
                sortOrder: $0.sortOrder,
                tagIDs: $0.tagIDs,
                vatCodeID: $0.vatCodeID,
                vatMode: $0.vatMode,
                netMinor: $0.netMinor,
                taxMinor: $0.taxMinor
            )
        }
    }

    func transaction(on date: Date = .now) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(),
            accountID: accountID,
            bookingDate: date,
            valueDate: date,
            payee: payee,
            purpose: purpose,
            categoryID: categoryID,
            amountMinor: amountMinor,
            currency: currency,
            status: status,
            memo: memo,
            reference: "",
            transferID: nil,
            importFingerprint: nil,
            splits: splits.map {
                FinanceSplit(
                    id: UUID(),
                    categoryID: $0.categoryID,
                    amountMinor: $0.amountMinor,
                    memo: $0.memo,
                    sortOrder: $0.sortOrder,
                    tagIDs: $0.tagIDs,
                    vatCodeID: $0.vatCodeID,
                    vatMode: $0.vatMode ?? .none,
                    netMinor: $0.netMinor ?? 0,
                    taxMinor: $0.taxMinor ?? 0
                )
            },
            payeeID: payeeID,
            tagIDs: tagIDs,
            vatCodeID: vatCodeID,
            vatMode: vatMode ?? .none,
            netMinor: netMinor ?? 0,
            taxMinor: taxMinor ?? 0,
            originalAmountMinor: originalAmountMinor,
            originalCurrency: originalCurrency ?? "",
            exchangeRateScaled: exchangeRateScaled,
            flag: flag
        )
    }

    func appliedTransaction(
        on date: Date = .now,
        compatibleAccountID: UUID? = nil
    ) -> FinanceTransaction {
        let fields = effectiveFields
        var value = transaction(on: date)
        if !fields.contains(.account), let compatibleAccountID {
            value.accountID = compatibleAccountID
        }
        if !fields.contains(.payee) {
            value.payee = ""
            value.payeeID = nil
            value.creditorID = ""
            value.mandateReference = ""
        }
        if !fields.contains(.purpose) { value.purpose = "" }
        if !fields.contains(.category) { value.categoryID = nil }
        if !fields.contains(.status) { value.status = .booked }
        if !fields.contains(.memo) { value.memo = "" }
        if !fields.contains(.flag) { value.flag = nil }
        if !fields.contains(.tags) {
            value.tagIDs = []
            for index in value.splits.indices {
                value.splits[index].tagIDs = []
            }
        }
        if !fields.contains(.vat) {
            value.vatCodeID = nil
            value.vatMode = .none
            value.netMinor = 0
            value.taxMinor = 0
            for index in value.splits.indices {
                value.splits[index].vatCodeID = nil
                value.splits[index].vatMode = .none
                value.splits[index].netMinor = 0
                value.splits[index].taxMinor = 0
            }
        }
        if !fields.contains(.foreignCurrency) {
            value.originalAmountMinor = nil
            value.originalCurrency = ""
            value.exchangeRateScaled = nil
        }
        if !fields.contains(.splits) { value.splits = [] }
        if !fields.contains(.amount) {
            value.amountMinor = 0
            value.splits = []
            value.originalAmountMinor = nil
            value.originalCurrency = ""
            value.exchangeRateScaled = nil
            value.vatCodeID = nil
            value.vatMode = .none
            value.netMinor = 0
            value.taxMinor = 0
        }
        return value
    }
}

enum TransactionTemplateLibrary {
    static func orderedForUse(
        _ templates: [TransactionTemplate],
        selectedAccountID: UUID?
    ) -> [TransactionTemplate] {
        templates.filter(\.effectiveIsActive).sorted { lhs, rhs in
            let lhsAccount = lhs.accountID == selectedAccountID
            let rhsAccount = rhs.accountID == selectedAccountID
            if lhsAccount != rhsAccount { return lhsAccount }
            if lhs.effectiveUsageCount != rhs.effectiveUsageCount {
                return lhs.effectiveUsageCount > rhs.effectiveUsageCount
            }
            if lhs.lastUsedAt != rhs.lastUsedAt {
                return (lhs.lastUsedAt ?? .distantPast)
                    > (rhs.lastUsedAt ?? .distantPast)
            }
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return comparison == .orderedSame
                ? lhs.id.uuidString < rhs.id.uuidString
                : comparison == .orderedAscending
        }
    }
}

struct ReconciliationSnapshot: Equatable, Sendable {
    let accountID: UUID
    let statementDate: Date
    let startingBalanceMinor: Int64
    let candidates: [FinanceTransaction]
    let latestActiveReconciliationID: UUID?

    func selectedSumMinor(_ ids: Set<UUID>) -> Int64 {
        candidates
            .filter { ids.contains($0.id) }
            .reduce(Int64.zero) { $0 + $1.amountMinor }
    }

    func differenceMinor(
        endingBalanceMinor: Int64,
        selectedIDs: Set<UUID>
    ) -> Int64 {
        endingBalanceMinor
            - startingBalanceMinor
            - selectedSumMinor(selectedIDs)
    }
}

struct ReconciliationRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let statementDate: Date
    let startingBalanceMinor: Int64
    let endingBalanceMinor: Int64
    let selectedSumMinor: Int64
    let adjustmentTransactionID: UUID?
    let completedAt: Date
    let revertedAt: Date?
    let canRevert: Bool
}

struct BulkCategoryUpdateResult: Equatable, Sendable {
    let updatedCount: Int
    let totalsByCurrency: [String: Int64]
}

struct FinanceTag: Identifiable, Hashable, Sendable {
    let id: UUID
    var parentID: UUID?
    var name: String
    var color: String
    var description: String
    var isActive: Bool
}

struct FinancePayee: Identifiable, Hashable, Sendable {
    let id: UUID
    var canonicalName: String
    var aliases: [String]
    var address: String
    var email: String
    var phone: String
    var iban: String
    var bic: String
    var creditorID: String = ""
    var defaultCategoryID: UUID?
    var defaultTagIDs: [UUID] = []
    var preferredAccountID: UUID?
    var note: String
    var isActive: Bool
}

struct FinancePayeeBankAccount: Identifiable, Hashable, Sendable {
    let id: UUID
    var payeeID: UUID
    var label: String
    var accountHolder: String
    var iban: String
    var bic: String
    var bankName: String
    var isDefault: Bool
    var isActive: Bool
}

enum SEPAMandateSequenceType: String, CaseIterable, Codable, Sendable {
    case oneOff
    case first
    case recurring
    case final

    var title: String {
        switch self {
        case .oneOff: "Einmalig (OOFF)"
        case .first: "Erstmalig (FRST)"
        case .recurring: "Wiederkehrend (RCUR)"
        case .final: "Letztmalig (FNAL)"
        }
    }
}

struct FinanceSEPAMandate: Identifiable, Hashable, Sendable {
    let id: UUID
    var payeeID: UUID
    var reference: String
    var signedOn: Date?
    var sequenceType: SEPAMandateSequenceType
    var note: String
    var isActive: Bool
}

struct CategoryReportRow: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let incomeMinor: Int64
    let expenseMinor: Int64
}

enum CSVImportEncoding: String, Codable, CaseIterable, Sendable {
    case utf8
    case windows1252
    case isoLatin1

    var title: String {
        switch self {
        case .utf8: "UTF-8"
        case .windows1252: "Windows-1252"
        case .isoLatin1: "ISO-8859-1"
        }
    }
}

enum CSVImportSeparator: String, Codable, CaseIterable, Sendable {
    case semicolon
    case comma
    case tab

    var title: String {
        switch self {
        case .semicolon: "Semikolon"
        case .comma: "Komma"
        case .tab: "Tabulator"
        }
    }

    var character: Character {
        switch self {
        case .semicolon: ";"
        case .comma: ","
        case .tab: "\t"
        }
    }
}

enum CSVImportDateFormat: String, Codable, CaseIterable, Sendable {
    case germanLong
    case germanShort
    case iso
    case us

    var title: String {
        switch self {
        case .germanLong: "TT.MM.JJJJ"
        case .germanShort: "TT.MM.JJ"
        case .iso: "JJJJ-MM-TT"
        case .us: "MM/TT/JJJJ"
        }
    }

    var pattern: String {
        switch self {
        case .germanLong: "dd.MM.yyyy"
        case .germanShort: "dd.MM.yy"
        case .iso: "yyyy-MM-dd"
        case .us: "MM/dd/yyyy"
        }
    }
}

enum CSVImportAmountMode: String, Codable, CaseIterable, Sendable {
    case signed
    case debitCredit

    var title: String {
        switch self {
        case .signed: "Betrag mit Vorzeichen"
        case .debitCredit: "Getrennte Soll-/Haben-Spalten"
        }
    }
}

enum CSVImportField: String, CaseIterable, Identifiable, Sendable {
    case bookingDate
    case valueDate
    case payee
    case purpose
    case amount
    case debit
    case credit
    case category
    case memo
    case reference
    case externalTransactionID
    case provider
    case counterpartyIBAN
    case counterpartyBIC
    case endToEndID
    case mandateReference
    case creditorID
    case bookingText
    case bankBalanceAfter

    var id: Self { self }

    var title: String {
        switch self {
        case .bookingDate: "Buchungsdatum"
        case .valueDate: "Wertstellung"
        case .payee: "Empfänger/Auftraggeber"
        case .purpose: "Verwendungszweck"
        case .amount: "Betrag"
        case .debit: "Soll/Belastung"
        case .credit: "Haben/Gutschrift"
        case .category: "Kategoriepfad"
        case .memo: "Notiz"
        case .reference: "Referenz"
        case .externalTransactionID: "Externe Transaktions-ID"
        case .provider: "Provider/Bank"
        case .counterpartyIBAN: "Gegenkonto-IBAN"
        case .counterpartyBIC: "Gegenkonto-BIC"
        case .endToEndID: "End-to-End-ID"
        case .mandateReference: "Mandatsreferenz"
        case .creditorID: "Gläubiger-ID"
        case .bookingText: "Buchungstext"
        case .bankBalanceAfter: "Saldo danach"
        }
    }
}

struct CSVImportProfile: Identifiable, Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var id: UUID
    var name: String
    var schema: Int
    var revision: Int
    var encoding: CSVImportEncoding
    var separator: CSVImportSeparator
    var hasHeader: Bool
    var dateFormat: CSVImportDateFormat
    var decimalSeparator: String
    var thousandsSeparator: String
    var amountMode: CSVImportAmountMode
    var mappings: [String: Int]

    init(
        id: UUID = UUID(),
        name: String = "Neues CSV-Profil",
        schema: Int = Self.schemaVersion,
        revision: Int = 1,
        encoding: CSVImportEncoding = .utf8,
        separator: CSVImportSeparator = .semicolon,
        hasHeader: Bool = true,
        dateFormat: CSVImportDateFormat = .germanLong,
        decimalSeparator: String = ",",
        thousandsSeparator: String = ".",
        amountMode: CSVImportAmountMode = .signed,
        mappings: [String: Int] = [:]
    ) {
        self.id = id
        self.name = name
        self.schema = schema
        self.revision = revision
        self.encoding = encoding
        self.separator = separator
        self.hasHeader = hasHeader
        self.dateFormat = dateFormat
        self.decimalSeparator = decimalSeparator
        self.thousandsSeparator = thousandsSeparator
        self.amountMode = amountMode
        self.mappings = mappings
    }

    func column(for field: CSVImportField) -> Int? {
        mappings[field.rawValue]
    }

    mutating func setColumn(_ column: Int?, for field: CSVImportField) {
        mappings[field.rawValue] = column
    }
}

struct CSVImportInspection: Equatable, Sendable {
    let columns: [String]
    let sampleRows: [[String]]
    let rowCount: Int
}

struct CSVImportProfileExchangeEnvelope: Codable, Equatable, Sendable {
    static let formatIdentifier =
        "de.pixelpuxel.finanzverwalter.csv-import-profile"
    static let formatVersion = 1

    let format: String
    let formatVersion: Int
    let profile: CSVImportProfile

    init(profile: CSVImportProfile) {
        self.format = Self.formatIdentifier
        self.formatVersion = Self.formatVersion
        self.profile = profile
    }
}

enum CSVImportProfileExchangeConflict: Equatable, Sendable {
    case none
    case identical
    case identifier(CSVImportProfile)
    case name(CSVImportProfile)
}

enum CSVImportProfileMergeStrategy: Equatable, Sendable {
    case automatic
    case replace
    case copy
}

enum CSVImportProfileLibrary {
    static let maximumExchangeBytes = 256 * 1_024

    static func upserting(
        _ profile: CSVImportProfile,
        into profiles: [CSVImportProfile]
    ) -> [CSVImportProfile] {
        var saved = profile
        saved.schema = CSVImportProfile.schemaVersion
        if let existing = profiles.first(where: { $0.id == profile.id }) {
            saved.revision = existing.revision + 1
        } else {
            saved.revision = max(1, profile.revision)
        }
        return (profiles.filter { $0.id != saved.id } + [saved]).sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : comparison == .orderedAscending
        }
    }

    static func encode(_ profiles: [CSVImportProfile]) throws -> Data {
        try JSONEncoder().encode(profiles)
    }

    static func decode(_ data: Data) throws -> [CSVImportProfile] {
        let decoded = try JSONDecoder().decode([CSVImportProfile].self, from: data)
        guard decoded.allSatisfy({ $0.schema == CSVImportProfile.schemaVersion }) else {
            throw FinanceError.invalidCSVImport(
                "Das gespeicherte Profil verwendet eine nicht unterstützte Version."
            )
        }
        return decoded
    }

    static func encodeExchange(_ profile: CSVImportProfile) throws -> Data {
        try validateExchangeProfile(profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(CSVImportProfileExchangeEnvelope(profile: profile))
    }

    static func decodeExchange(_ data: Data) throws -> CSVImportProfile {
        guard data.count <= maximumExchangeBytes else {
            throw FinanceError.invalidCSVImport(
                "Die Profildatei ist größer als 256 KiB."
            )
        }
        try validateExchangeJSONStructure(data)
        let envelope: CSVImportProfileExchangeEnvelope
        do {
            envelope = try JSONDecoder().decode(
                CSVImportProfileExchangeEnvelope.self,
                from: data
            )
        } catch {
            throw FinanceError.invalidCSVImport(
                "Die Profildatei ist kein gültiges FinanzVerwalter-Profil."
            )
        }
        guard envelope.format == CSVImportProfileExchangeEnvelope.formatIdentifier else {
            throw FinanceError.invalidCSVImport(
                "Die Formatkennung der Profildatei ist unbekannt."
            )
        }
        guard envelope.formatVersion == CSVImportProfileExchangeEnvelope.formatVersion else {
            throw FinanceError.invalidCSVImport(
                "Diese Version der Profildatei wird nicht unterstützt."
            )
        }
        try validateExchangeProfile(envelope.profile)
        return envelope.profile
    }

    static func conflict(
        for profile: CSVImportProfile,
        in profiles: [CSVImportProfile]
    ) -> CSVImportProfileExchangeConflict {
        if let existing = profiles.first(where: { $0.id == profile.id }) {
            return existing == profile ? .identical : .identifier(existing)
        }
        let normalizedName = normalizedProfileName(profile.name)
        if let existing = profiles.first(where: {
            normalizedProfileName($0.name) == normalizedName
        }) {
            return .name(existing)
        }
        return .none
    }

    static func merging(
        _ profile: CSVImportProfile,
        into profiles: [CSVImportProfile],
        strategy: CSVImportProfileMergeStrategy = .automatic
    ) throws -> [CSVImportProfile] {
        try validateExchangeProfile(profile)
        let conflict = conflict(for: profile, in: profiles)
        switch (conflict, strategy) {
        case (.identical, _):
            return profiles
        case (.none, _):
            return sorted(profiles + [profile])
        case (_, .automatic):
            throw FinanceError.invalidCSVImport(
                "Ein Profil mit derselben Kennung oder demselben Namen ist bereits vorhanden."
            )
        case (.identifier(let existing), .replace):
            let retained = profiles.filter { $0.id != existing.id }
            guard !retained.contains(where: {
                normalizedProfileName($0.name)
                    == normalizedProfileName(profile.name)
            }) else {
                throw FinanceError.invalidCSVImport(
                    "Kennung und Name kollidieren mit zwei verschiedenen Profilen. Importieren Sie das Profil als Kopie."
                )
            }
            return sorted(retained + [profile])
        case (.name(let existing), .replace):
            return sorted(profiles.filter { $0.id != existing.id } + [profile])
        case (_, .copy):
            var copy = profile
            copy.id = UUID()
            copy.revision = 1
            copy.name = availableCopyName(for: profile.name, in: profiles)
            return sorted(profiles + [copy])
        }
    }

    private static func validateExchangeProfile(
        _ profile: CSVImportProfile
    ) throws {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw FinanceError.invalidCSVImport(
                "Der Profilname muss 1 bis 100 druckbare Zeichen enthalten."
            )
        }
        guard profile.name == name else {
            throw FinanceError.invalidCSVImport(
                "Der Profilname darf nicht mit Leerzeichen beginnen oder enden."
            )
        }
        guard profile.schema == CSVImportProfile.schemaVersion else {
            throw FinanceError.invalidCSVImport(
                "Das Profil verwendet eine nicht unterstützte Version."
            )
        }
        guard (1...1_000_000).contains(profile.revision) else {
            throw FinanceError.invalidCSVImport(
                "Die Profilrevision liegt außerhalb des gültigen Bereichs."
            )
        }
        guard [",", "."].contains(profile.decimalSeparator),
              ["", ",", "."].contains(profile.thousandsSeparator),
              profile.decimalSeparator != profile.thousandsSeparator
        else {
            throw FinanceError.invalidCSVImport(
                "Dezimal- und Tausenderzeichen sind ungültig."
            )
        }
        let supportedFields = Set(CSVImportField.allCases.map(\.rawValue))
        guard profile.mappings.count <= supportedFields.count,
              profile.mappings.keys.allSatisfy(supportedFields.contains),
              profile.mappings.values.allSatisfy({ (0...4_095).contains($0) })
        else {
            throw FinanceError.invalidCSVImport(
                "Die Feldzuordnung enthält unbekannte Felder oder ungültige Spalten."
            )
        }
    }

    private static func validateExchangeJSONStructure(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any],
              Set(object.keys) == Set(["format", "formatVersion", "profile"]),
              let profile = object["profile"] as? [String: Any],
              Set(profile.keys) == Set([
                  "id", "name", "schema", "revision", "encoding", "separator",
                  "hasHeader", "dateFormat", "decimalSeparator",
                  "thousandsSeparator", "amountMode", "mappings"
              ]),
              profile["mappings"] is [String: Any]
        else {
            throw FinanceError.invalidCSVImport(
                "Die Profildatei enthält eine unerwartete Struktur."
            )
        }
    }

    private static func normalizedProfileName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func availableCopyName(
        for name: String,
        in profiles: [CSVImportProfile]
    ) -> String {
        let base = String(name.prefix(90))
        let names = Set(profiles.map { normalizedProfileName($0.name) })
        for number in 1...9_999 {
            let suffix = number == 1 ? " (Import)" : " (Import \(number))"
            let candidate = String(base.prefix(100 - suffix.count)) + suffix
            if !names.contains(normalizedProfileName(candidate)) {
                return candidate
            }
        }
        return "Importiertes Profil \(UUID().uuidString.prefix(8))"
    }

    private static func sorted(_ profiles: [CSVImportProfile]) -> [CSVImportProfile] {
        profiles.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : comparison == .orderedAscending
        }
    }
}

struct ImportPreview: Sendable {
    let rows: [FinanceTransaction]
    let rejectedRows: [String]
    let fingerprint: String
    let matches: [UUID: ImportMatchAssessment]
    let matchDateWindowDays: Int

    init(
        rows: [FinanceTransaction],
        rejectedRows: [String],
        fingerprint: String,
        matches: [UUID: ImportMatchAssessment] = [:],
        matchDateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) {
        self.rows = rows
        self.rejectedRows = rejectedRows
        self.fingerprint = fingerprint
        self.matches = matches
        self.matchDateWindowDays = max(0, matchDateWindowDays)
    }

    func matched(
        against existing: [FinanceTransaction],
        dateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) -> Self {
        Self(
            rows: rows,
            rejectedRows: rejectedRows,
            fingerprint: fingerprint,
            matches: ImportMatcher.assess(
                rows: rows,
                against: existing,
                dateWindowDays: dateWindowDays
            ),
            matchDateWindowDays: dateWindowDays
        )
    }
}

struct ImportCommitResult: Equatable, Sendable {
    let importedCount: Int
    let matchedCount: Int
    let skippedCount: Int

    var statusText: String {
        "\(importedCount) neu importiert · "
            + "\(matchedCount) abgeglichen · "
            + "\(skippedCount) übersprungen"
    }
}

struct QIFPackageSummary: Sendable {
    let accountDefinitions: Int
    let categoryRecords: Int
    let transactionRecords: Int
    let supportedTransactionRecords: Int
    let sectionCounts: [String: Int]
    let unsupportedSectionCounts: [String: Int]
}

struct QIFPackagePreview: Sendable {
    let accountsToCreate: [FinanceAccount]
    let categoriesToCreate: [FinanceCategory]
    let importPreview: ImportPreview
    let summary: QIFPackageSummary
    let warnings: [String]
}

struct CategorizationRule: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var priority: Int
    var isActive: Bool
    var stopAfterMatch: Bool
    var payeeContains: String
    var purposeContains: String
    var minimumAmountMinor: Int64?
    var maximumAmountMinor: Int64?
    var categoryID: UUID
    var expression: RuleExpression? = nil
    var actions: [RuleAction] = []

    func matches(_ transaction: FinanceTransaction) -> Bool {
        guard isActive,
              transaction.status != .reconciled,
              transaction.status != .cancelled,
              transaction.transferID == nil
        else {
            return false
        }
        if expression != nil {
            return RuleEngine.matches(
                effectiveExpression,
                transaction: transaction
            )
        }
        if !payeeContains.isEmpty,
           !transaction.payee.localizedCaseInsensitiveContains(payeeContains) {
            return false
        }
        if !purposeContains.isEmpty,
           !transaction.purpose.localizedCaseInsensitiveContains(purposeContains) {
            return false
        }
        if let minimumAmountMinor, transaction.amountMinor < minimumAmountMinor {
            return false
        }
        if let maximumAmountMinor, transaction.amountMinor > maximumAmountMinor {
            return false
        }
        return true
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case biweekly
    case monthly
    case bimonthly
    case quarterly
    case semiannual
    case yearly

    var id: Self { self }
    var title: String {
        switch self {
        case .daily: "Täglich"
        case .weekly: "Wöchentlich"
        case .biweekly: "Zweiwöchentlich"
        case .monthly: "Monatlich"
        case .bimonthly: "Zweimonatlich"
        case .quarterly: "Quartalsweise"
        case .semiannual: "Halbjährlich"
        case .yearly: "Jährlich"
        }
    }

    func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly:
            return monthDate(after: date, months: 1, calendar: calendar)
        case .bimonthly:
            return monthDate(after: date, months: 2, calendar: calendar)
        case .quarterly:
            return monthDate(after: date, months: 3, calendar: calendar)
        case .semiannual:
            return monthDate(after: date, months: 6, calendar: calendar)
        case .yearly:
            return monthDate(after: date, months: 12, calendar: calendar)
        }
    }

    private func monthDate(after date: Date, months: Int, calendar: Calendar) -> Date {
        let sourceDay = calendar.component(.day, from: date)
        guard
            let sourceRange = calendar.range(of: .day, in: .month, for: date),
            let sourceMonthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date)
            ),
            let targetMonthStart = calendar.date(
                byAdding: .month, value: months, to: sourceMonthStart
            ),
            let targetRange = calendar.range(of: .day, in: .month, for: targetMonthStart)
        else { return date }
        let sourceIsMonthEnd = sourceDay == sourceRange.count
        let targetDay = sourceIsMonthEnd ? targetRange.count : min(sourceDay, targetRange.count)
        var components = calendar.dateComponents([.year, .month], from: targetMonthStart)
        components.day = targetDay
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components) ?? targetMonthStart
    }
}

enum ScheduledAction: String, Codable, CaseIterable, Sendable {
    case remind
    case automatic
    case preparePayment

    var title: String {
        switch self {
        case .remind: "Nur erinnern"
        case .automatic: "Automatisch eintragen"
        case .preparePayment: "Zur Zahlung vorbereiten"
        }
    }
}

enum FinanceCalendarViewMode: String, Codable, CaseIterable, Sendable {
    case month
    case week
    case list

    var title: String {
        switch self {
        case .month: "Monat"
        case .week: "Woche"
        case .list: "Liste"
        }
    }
}

enum FinanceCalendarEntryKind: String, Codable, CaseIterable, Sendable {
    case recurring
    case expected
    case pending
    case booked
    case cancelled

    var title: String {
        switch self {
        case .recurring: "Regelmäßig"
        case .expected: "Erwartet"
        case .pending: "Vorgemerkt"
        case .booked: "Gebucht"
        case .cancelled: "Storniert"
        }
    }

    static func classify(
        status: TransactionStatus,
        isRecurring: Bool
    ) -> FinanceCalendarEntryKind {
        if isRecurring { return .recurring }
        switch status {
        case .expected: return .expected
        case .pending: return .pending
        case .booked, .cleared, .reconciled: return .booked
        case .cancelled: return .cancelled
        }
    }
}

struct FinanceCalendarDay: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let isInFocusedPeriod: Bool
}

enum FinanceCalendarLayout {
    static func days(
        containing focusedDate: Date,
        mode: FinanceCalendarViewMode,
        calendar sourceCalendar: Calendar = .current
    ) -> [FinanceCalendarDay] {
        guard mode != .list else { return [] }
        var calendar = sourceCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let focusedDay = calendar.startOfDay(for: focusedDate)
        let component: Calendar.Component = mode == .month ? .month : .weekOfYear
        guard let focusedInterval = calendar.dateInterval(of: component, for: focusedDay)
        else { return [] }
        let gridStart: Date
        let gridEnd: Date
        if mode == .month {
            guard let firstWeek = calendar.dateInterval(
                of: .weekOfYear, for: focusedInterval.start
            ), let lastDay = calendar.date(byAdding: .day, value: -1, to: focusedInterval.end),
                  let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)
            else { return [] }
            gridStart = firstWeek.start
            gridEnd = lastWeek.end
        } else {
            gridStart = focusedInterval.start
            gridEnd = focusedInterval.end
        }
        var result: [FinanceCalendarDay] = []
        var date = gridStart
        while date < gridEnd, result.count < 42 {
            result.append(
                FinanceCalendarDay(
                    date: date,
                    isInFocusedPeriod: date >= focusedInterval.start
                        && date < focusedInterval.end
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: date)
            else { break }
            date = next
        }
        return result
    }

    static func shiftedFocus(
        from date: Date,
        mode: FinanceCalendarViewMode,
        offset: Int,
        calendar: Calendar = .current
    ) -> Date {
        let component: Calendar.Component = mode == .month ? .month : .weekOfYear
        return calendar.date(byAdding: component, value: offset, to: date) ?? date
    }
}

enum FinanceCalendarMoveError: LocalizedError, Equatable {
    case unsupportedStatus
    case linkedTransfer
    case pastDestination
    case sameDay
    case invalidRecurringReference

    var errorDescription: String? {
        switch self {
        case .unsupportedStatus:
            "Nur erwartete oder regelmäßige Prognosetermine lassen sich verschieben."
        case .linkedTransfer:
            "Eine verknüpfte Umbuchung kann nicht im Finanzkalender verschoben werden."
        case .pastDestination:
            "Ein Prognosetermin kann nicht in die Vergangenheit verschoben werden."
        case .sameDay:
            "Quell- und Zieldatum sind identisch."
        case .invalidRecurringReference:
            "Der regelmäßige Vorgang besitzt keine gültige Herkunftskennung."
        }
    }
}

enum FinanceCalendarMovePolicy {
    static func movedExpectedTransaction(
        _ transaction: FinanceTransaction,
        to destination: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> FinanceTransaction {
        guard transaction.status == .expected else {
            throw FinanceCalendarMoveError.unsupportedStatus
        }
        guard transaction.transferID == nil else {
            throw FinanceCalendarMoveError.linkedTransfer
        }
        let target = try validatedDestination(
            destination, source: transaction.bookingDate, now: now, calendar: calendar
        )
        var result = transaction
        let valueDateFollowedBooking = transaction.valueDate.map {
            calendar.isDate($0, inSameDayAs: transaction.bookingDate)
        } ?? true
        result.bookingDate = target
        if valueDateFollowedBooking { result.valueDate = target }
        return result
    }

    static func movedRecurringException(
        for transaction: FinanceTransaction,
        existing: ScheduledTransactionException?,
        to destination: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> ScheduledTransactionException {
        guard let identity = ScheduledTransaction.occurrenceIdentity(
            from: transaction.reference
        ) else {
            throw FinanceCalendarMoveError.invalidRecurringReference
        }
        let target = try validatedDestination(
            destination, source: transaction.bookingDate, now: now, calendar: calendar
        )
        return ScheduledTransactionException(
            id: existing?.id ?? UUID(),
            scheduledTransactionID: identity.scheduledTransactionID,
            originalDueDate: identity.originalDueDate,
            effectiveDate: target,
            payee: transaction.payee,
            purpose: transaction.purpose,
            categoryID: transaction.categoryID,
            amountMinor: transaction.amountMinor,
            disposition: .modified,
            note: existing?.note ?? "Im Finanzkalender verschoben",
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    private static func validatedDestination(
        _ destination: Date,
        source: Date,
        now: Date,
        calendar: Calendar
    ) throws -> Date {
        let target = calendar.startOfDay(for: destination)
        guard target >= calendar.startOfDay(for: now) else {
            throw FinanceCalendarMoveError.pastDestination
        }
        guard !calendar.isDate(target, inSameDayAs: source) else {
            throw FinanceCalendarMoveError.sameDay
        }
        return target
    }
}

enum ForecastInterval: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly

    var title: String {
        switch self {
        case .daily: "Täglich"
        case .weekly: "Wöchentlich"
        case .monthly: "Monatlich"
        }
    }
}

struct ForecastScenario: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var note: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct ForecastScenarioEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var scenarioID: UUID
    var accountID: UUID
    var date: Date
    var name: String
    var amountMinor: Int64
    var isEnabled: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date
}

enum ForecastPositionOrigin: String, Codable, CaseIterable, Sendable {
    case booked
    case pending
    case expected
    case paymentOrder
    case standingOrder
    case recurring
    case scenario

    var title: String {
        switch self {
        case .booked: "Gebucht"
        case .pending: "Vorgemerkt"
        case .expected: "Erwartet"
        case .paymentOrder: "Zahlungsauftrag"
        case .standingOrder: "Dauerauftrag"
        case .recurring: "Regelmäßig"
        case .scenario: "Szenario"
        }
    }
}

struct ForecastPosition: Identifiable, Hashable, Sendable {
    let id: String
    let accountID: UUID
    let date: Date
    let amountMinor: Int64
    let title: String
    let origin: ForecastPositionOrigin
}

struct ForecastBucket: Identifiable, Hashable, Sendable {
    var id: Date { startDate }
    let startDate: Date
    let endDate: Date
    let openingBalanceMinor: Int64
    let changeMinor: Int64
    let closingBalanceMinor: Int64
    let minimumBalanceMinor: Int64
    let maximumBalanceMinor: Int64
    let positions: [ForecastPosition]
}

enum LiquidityForecastEngine {
    static func buckets(
        accounts: [FinanceAccount],
        transactions: [FinanceTransaction],
        paymentOrders: [PaymentOrder] = [],
        standingOrders: [StandingOrder] = [],
        recurring: [FinanceTransaction],
        scenarioEntries: [ForecastScenarioEntry],
        accountIDs: Set<UUID>,
        from startDate: Date,
        through endDate: Date,
        interval: ForecastInterval,
        calendar sourceCalendar: Calendar = .current
    ) -> [ForecastBucket] {
        var calendar = sourceCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let includedAccounts = accounts.filter { accountIDs.contains($0.id) }
        guard start <= end, !accountIDs.isEmpty,
              Set(includedAccounts.map { $0.currency.uppercased() }).count == 1
        else { return [] }
        let baseline = includedAccounts.reduce(Int64.zero) {
            $0 + $1.openingBalanceMinor
        } + transactions.filter {
            accountIDs.contains($0.accountID) && $0.status != .cancelled
                && $0.status != .expected && $0.bookingDate < start
        }.reduce(Int64.zero) { $0 + $1.amountMinor }
        let realPositions = transactions.compactMap { value -> ForecastPosition? in
            guard accountIDs.contains(value.accountID), value.status != .cancelled,
                  value.bookingDate >= start, value.bookingDate < dayAfter(end, calendar: calendar)
            else { return nil }
            let origin: ForecastPositionOrigin
            switch value.status {
            case .expected: origin = .expected
            case .pending: origin = .pending
            case .booked, .cleared, .reconciled: origin = .booked
            case .cancelled: return nil
            }
            return ForecastPosition(
                id: "transaction:\(value.id.uuidString)", accountID: value.accountID,
                date: value.bookingDate, amountMinor: value.amountMinor,
                title: value.payee.isEmpty ? value.purpose : value.payee, origin: origin
            )
        }
        let paymentOrderPositions = paymentOrders.compactMap { value -> ForecastPosition? in
            guard accountIDs.contains(value.accountID),
                  value.status != .rejected, value.status != .cancelled,
                  value.executionDate >= start,
                  value.executionDate < dayAfter(end, calendar: calendar)
            else { return nil }
            return ForecastPosition(
                id: "payment-order:\(value.id.uuidString)", accountID: value.accountID,
                date: value.executionDate, amountMinor: -abs(value.amountMinor),
                title: value.recipientName, origin: .paymentOrder
            )
        }
        var standingOrderPositions: [ForecastPosition] = []
        for value in standingOrders where value.status == .active
            && accountIDs.contains(value.accountID) {
            var dueDate = value.nextExecutionDate
            var occurrence = 0
            while dueDate <= end, occurrence < 10_000 {
                let executionDate = value.businessDayAdjustment.adjusted(
                    dueDate, bankingCalendar: value.bankingCalendar, calendar: calendar
                )
                if executionDate >= start,
                   executionDate < dayAfter(end, calendar: calendar),
                   value.endDate.map({ dueDate <= $0 }) ?? true {
                    standingOrderPositions.append(ForecastPosition(
                        id: "standing-order:\(value.id.uuidString):\(Int(dueDate.timeIntervalSince1970))",
                        accountID: value.accountID, date: executionDate,
                        amountMinor: -abs(value.amountMinor), title: value.recipientName,
                        origin: .standingOrder
                    ))
                }
                let next = value.frequency.next(after: dueDate, calendar: calendar)
                guard next > dueDate else { break }
                dueDate = next
                occurrence += 1
            }
        }
        let recurringPositions = recurring.compactMap { value -> ForecastPosition? in
            guard accountIDs.contains(value.accountID), value.bookingDate >= start,
                  value.bookingDate < dayAfter(end, calendar: calendar) else { return nil }
            return ForecastPosition(
                id: value.reference, accountID: value.accountID, date: value.bookingDate,
                amountMinor: value.amountMinor,
                title: value.payee.isEmpty ? value.purpose : value.payee, origin: .recurring
            )
        }
        let scenarioPositions = scenarioEntries.compactMap { value -> ForecastPosition? in
            guard value.isEnabled, accountIDs.contains(value.accountID), value.date >= start,
                  value.date < dayAfter(end, calendar: calendar) else { return nil }
            return ForecastPosition(
                id: "scenario:\(value.id.uuidString)", accountID: value.accountID,
                date: value.date, amountMinor: value.amountMinor,
                title: value.name, origin: .scenario
            )
        }
        let plannedPositions = deduplicated(
            realPositions + paymentOrderPositions + standingOrderPositions + recurringPositions,
            calendar: calendar
        )
        let positions = (plannedPositions + scenarioPositions).sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
        var result: [ForecastBucket] = []
        var cursor = start
        var running = baseline
        while cursor <= end {
            let boundary = nextBoundary(after: cursor, interval: interval, calendar: calendar)
            let bucketEnd = min(end, calendar.date(byAdding: .day, value: -1, to: boundary) ?? end)
            let values = positions.filter { $0.date >= cursor && $0.date < boundary }
            let opening = running
            var minimum = running
            var maximum = running
            for value in values {
                running += value.amountMinor
                minimum = min(minimum, running)
                maximum = max(maximum, running)
            }
            result.append(ForecastBucket(
                startDate: cursor, endDate: bucketEnd, openingBalanceMinor: opening,
                changeMinor: running - opening, closingBalanceMinor: running,
                minimumBalanceMinor: minimum, maximumBalanceMinor: maximum,
                positions: values
            ))
            cursor = boundary
        }
        return result
    }

    private static func dayAfter(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Reale Buchungen haben Vorrang vor Zahlungsaufträgen, diese vor
    /// Daueraufträgen und allgemeinen Serienterminen. Nur exakt gleiche,
    /// starke Schlüssel werden zusammengeführt; Szenariopositionen werden
    /// absichtlich nie dedupliziert, weil sie additive Annahmen darstellen.
    private static func deduplicated(
        _ positions: [ForecastPosition], calendar: Calendar
    ) -> [ForecastPosition] {
        var seen: Set<String> = []
        return positions.filter { value in
            let day = Int64(calendar.startOfDay(for: value.date).timeIntervalSinceReferenceDate)
            let title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "de_DE")
                )
            let key = "\(value.accountID.uuidString)|\(day)|\(value.amountMinor)|\(title)"
            return seen.insert(key).inserted
        }
    }

    private static func nextBoundary(
        after date: Date, interval: ForecastInterval, calendar: Calendar
    ) -> Date {
        switch interval {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.end
                ?? calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)?.end
                ?? calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}

enum ScheduledOccurrenceDisposition: String, Codable, CaseIterable, Sendable {
    case modified
    case skipped

    var title: String {
        switch self {
        case .modified: "Geändert"
        case .skipped: "Übersprungen"
        }
    }
}

struct ScheduledTransactionException: Identifiable, Hashable, Sendable {
    let id: UUID
    var scheduledTransactionID: UUID
    var originalDueDate: Date
    var effectiveDate: Date
    var payee: String
    var purpose: String
    var categoryID: UUID?
    var amountMinor: Int64
    var disposition: ScheduledOccurrenceDisposition
    var note: String
    var createdAt: Date
    var updatedAt: Date
}

struct ScheduledTransactionRevision: Identifiable, Hashable, Sendable {
    let id: UUID
    var scheduledTransactionID: UUID
    var originalDueDate: Date
    var effectiveDate: Date
    var payee: String
    var purpose: String
    var categoryID: UUID?
    var amountMinor: Int64
    var note: String
    var createdAt: Date
    var updatedAt: Date
}

struct ScheduledTransaction: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var accountID: UUID
    var payee: String
    var purpose: String
    var categoryID: UUID?
    var amountMinor: Int64
    var currency: String
    var nextDueDate: Date
    var endDate: Date?
    var frequency: RecurrenceFrequency
    var action: ScheduledAction
    var reminderDays: Int
    var isActive: Bool
    var transactionTemplate: TransactionTemplate? = nil

    static func draft(
        from transaction: FinanceTransaction,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> ScheduledTransaction {
        guard transaction.transferID == nil else {
            throw FinanceError.database(
                "Eine einzelne Umbuchungsseite kann nicht als regelmäßiger Vorgang gespeichert werden."
            )
        }
        let suggested = transaction.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = transaction.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = suggested.isEmpty
            ? (fallback.isEmpty ? "Neuer regelmäßiger Vorgang" : fallback)
            : suggested
        let frequency = RecurrenceFrequency.monthly
        let today = calendar.startOfDay(for: now)
        var nextDueDate = calendar.startOfDay(for: transaction.bookingDate)
        var guardCount = 0
        while nextDueDate < today, guardCount < 1_200 {
            nextDueDate = frequency.next(after: nextDueDate, calendar: calendar)
            guardCount += 1
        }
        if nextDueDate < today { nextDueDate = today }
        return ScheduledTransaction(
            id: UUID(), name: name, accountID: transaction.accountID,
            payee: transaction.payee, purpose: transaction.purpose,
            categoryID: transaction.categoryID,
            amountMinor: transaction.amountMinor, currency: transaction.currency,
            nextDueDate: nextDueDate, endDate: nil, frequency: frequency,
            action: .remind, reminderDays: 3, isActive: true,
            transactionTemplate: TransactionTemplate(
                name: name, transaction: transaction
            )
        )
    }

    func occurrences(
        until end: Date,
        excludingReferences: Set<String> = [],
        exceptions: [ScheduledTransactionException] = [],
        revisions: [ScheduledTransactionRevision] = [],
        calendar: Calendar = .current
    ) -> [FinanceTransaction] {
        guard isActive else { return [] }
        let relevantExceptions = exceptions
            .filter { $0.scheduledTransactionID == id }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        var exceptionByDay: [Int: ScheduledTransactionException] = [:]
        for exception in relevantExceptions where exceptionByDay[Self.dayKey(exception.originalDueDate, calendar: calendar)] == nil {
            exceptionByDay[Self.dayKey(exception.originalDueDate, calendar: calendar)] = exception
        }
        let relevantRevisions = revisions
            .filter { $0.scheduledTransactionID == id }
            .sorted {
                if $0.originalDueDate != $1.originalDueDate {
                    return $0.originalDueDate < $1.originalDueDate
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        var revisionByDay: [Int: ScheduledTransactionRevision] = [:]
        for revision in relevantRevisions where revisionByDay[Self.dayKey(revision.originalDueDate, calendar: calendar)] == nil {
            revisionByDay[Self.dayKey(revision.originalDueDate, calendar: calendar)] = revision
        }
        let originalDates = relevantExceptions.map(\.originalDueDate)
            + relevantRevisions.map(\.originalDueDate)
        let latestOriginalDate = originalDates.max() ?? end
        let backwardShiftDays = (relevantExceptions.map {
            calendar.dateComponents([.day], from: $0.effectiveDate, to: $0.originalDueDate).day ?? 0
        } + relevantRevisions.map {
            calendar.dateComponents([.day], from: $0.effectiveDate, to: $0.originalDueDate).day ?? 0
        }).max() ?? 0
        let shiftedGenerationEnd = calendar.date(
            byAdding: .day, value: max(0, backwardShiftDays), to: end
        ) ?? end
        let generationEnd = max(latestOriginalDate, shiftedGenerationEnd)
        var due = nextDueDate
        var activeRevision: ScheduledTransactionRevision?
        var revisedDueDate: Date?
        var values: [FinanceTransaction] = []
        var guardCount = 0
        while due <= generationEnd, due <= (endDate ?? generationEnd), guardCount < 1_000 {
            if let revision = revisionByDay[Self.dayKey(due, calendar: calendar)] {
                activeRevision = revision
                revisedDueDate = revision.effectiveDate
            } else if let previousRevisedDueDate = revisedDueDate {
                revisedDueDate = frequency.next(after: previousRevisedDueDate, calendar: calendar)
            }
            let exception = exceptionByDay[Self.dayKey(due, calendar: calendar)]
            let effectiveDate = exception?.effectiveDate ?? revisedDueDate ?? due
            let reference = occurrenceReference(for: due)
            guardCount += 1
            defer { due = frequency.next(after: due, calendar: calendar) }
            guard exception?.disposition != .skipped,
                  effectiveDate <= end,
                  !excludingReferences.contains(reference)
            else { continue }
            let effectivePayee = exception?.payee ?? activeRevision?.payee ?? payee
            let effectivePurpose = exception?.purpose ?? activeRevision?.purpose ?? purpose
            let effectiveCategory = exception.map(\.categoryID)
                ?? activeRevision.map(\.categoryID) ?? categoryID
            let effectiveAmount = exception?.amountMinor
                ?? activeRevision?.amountMinor ?? amountMinor
            var value = transactionTemplate?.transaction(on: effectiveDate)
                ?? FinanceTransaction(
                    id: UUID(), accountID: accountID,
                    bookingDate: effectiveDate, valueDate: effectiveDate,
                    payee: effectivePayee, purpose: effectivePurpose,
                    categoryID: effectiveCategory, amountMinor: effectiveAmount,
                    currency: currency, status: .expected,
                    memo: "", reference: "", transferID: nil,
                    importFingerprint: nil, splits: []
                )
            value.accountID = accountID
            value.bookingDate = effectiveDate
            value.valueDate = effectiveDate
            value.payee = effectivePayee
            value.purpose = effectivePurpose
            value.categoryID = effectiveCategory
            value.amountMinor = effectiveAmount
            value.currency = currency
            value.status = .expected
            value.memo = value.memo.isEmpty
                ? "Regelmäßig: \(name)"
                : value.memo + "\nRegelmäßig: \(name)"
            value.reference = reference
            value.transferID = nil
            value.importFingerprint = nil
            value.origin = .manual
            value.externalProvider = ""
            value.externalTransactionID = ""
            value.duplicateFingerprint = ""
            value.bankBalanceAfterMinor = nil
            if effectiveAmount != amountMinor || effectiveCategory != categoryID {
                value.splits = []
                value.vatCodeID = nil
                value.vatMode = .none
                value.netMinor = 0
                value.taxMinor = 0
                value.originalAmountMinor = nil
                value.originalCurrency = ""
                value.exchangeRateScaled = nil
            }
            values.append(value)
        }
        return values.sorted {
            $0.bookingDate == $1.bookingDate
                ? $0.reference < $1.reference : $0.bookingDate < $1.bookingDate
        }
    }

    func occurrenceReference(for originalDueDate: Date) -> String {
        "schedule:\(id.uuidString):\(Int(originalDueDate.timeIntervalSince1970))"
    }

    static func occurrenceIdentity(
        from reference: String
    ) -> (scheduledTransactionID: UUID, originalDueDate: Date)? {
        let parts = reference.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "schedule",
              let id = UUID(uuidString: parts[1]),
              let timestamp = TimeInterval(parts[2])
        else { return nil }
        return (id, Date(timeIntervalSince1970: timestamp))
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000
            + (components.month ?? 0) * 100
            + (components.day ?? 0)
    }
}

struct FinanceBudget: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var startYear: Int
    var startMonth: Int
    var currency: String
    var isActive: Bool

    func months(calendar: Calendar = .current) -> [Date] {
        guard let start = calendar.date(
            from: DateComponents(year: startYear, month: startMonth, day: 1)
        ) else { return [] }
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }
}

struct BudgetLine: Identifiable, Hashable, Sendable {
    let id: UUID
    var budgetID: UUID
    var categoryID: UUID
    var year: Int
    var month: Int
    var plannedMinor: Int64
    var rolloverPositive: Bool
    var rolloverNegative: Bool
}

struct BudgetStatusRow: Identifiable, Hashable, Sendable {
    let category: FinanceCategory
    let line: BudgetLine?
    let plannedMinor: Int64
    let actualMinor: Int64
    var rolloverMinor: Int64 = 0
    var rolloverOutMinor: Int64 = 0
    var rolloverMode: BudgetRolloverMode = .none

    var id: UUID { category.id }
    var basePlannedMinor: Int64 { line?.plannedMinor ?? plannedMinor }
    var varianceMinor: Int64 {
        category.kind == .income
            ? actualMinor - plannedMinor
            : plannedMinor - abs(actualMinor)
    }
    var completionPercent: Int? {
        guard plannedMinor != 0 else { return nil }
        let actual = NSDecimalNumber(value: abs(actualMinor))
        let planned = NSDecimalNumber(value: abs(plannedMinor))
        return actual
            .dividing(by: planned)
            .multiplying(by: NSDecimalNumber(value: 100))
            .rounding(
                accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .plain, scale: 0,
                    raiseOnExactness: false, raiseOnOverflow: true,
                    raiseOnUnderflow: true, raiseOnDivideByZero: true
                )
            )
            .intValue
    }
}

enum BudgetRolloverMode: String, CaseIterable, Identifiable, Sendable {
    case none
    case positiveOnly
    case positiveAndNegative

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "Kein Übertrag"
        case .positiveOnly: "Nur positive Reste"
        case .positiveAndNegative: "Positive und negative Reste"
        }
    }

    init(line: BudgetLine?) {
        if line?.rolloverNegative == true {
            self = .positiveAndNegative
        } else if line?.rolloverPositive == true {
            self = .positiveOnly
        } else {
            self = .none
        }
    }

    var rolloverPositive: Bool { self != .none }
    var rolloverNegative: Bool { self == .positiveAndNegative }
}

enum PaymentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case sepaCreditTransfer
    case instantCreditTransfer
    case scheduledCreditTransfer

    var id: Self { self }
    var title: String {
        switch self {
        case .sepaCreditTransfer: "SEPA-Überweisung"
        case .instantCreditTransfer: "Echtzeitüberweisung"
        case .scheduledCreditTransfer: "Terminüberweisung"
        }
    }
}

enum PaymentStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case initiated
    case challengeReceived
    case awaitingUser
    case submitted
    case accepted
    case rejected
    case unknown
    case cancelled

    var title: String {
        switch self {
        case .draft: "Entwurf"
        case .initiated: "Initialisiert"
        case .challengeReceived: "Freigabe angefordert"
        case .awaitingUser: "Wartet auf Freigabe"
        case .submitted: "Übermittelt"
        case .accepted: "Angenommen"
        case .rejected: "Abgelehnt"
        case .unknown: "Status unbekannt"
        case .cancelled: "Abgebrochen"
        }
    }

    func canTransition(to target: PaymentStatus) -> Bool {
        switch (self, target) {
        case (.draft, .initiated),
             (.draft, .cancelled),
             (.initiated, .challengeReceived),
             (.initiated, .rejected),
             (.challengeReceived, .awaitingUser),
             (.challengeReceived, .rejected),
             (.awaitingUser, .submitted),
             (.awaitingUser, .cancelled),
             (.submitted, .accepted),
             (.submitted, .rejected),
             (.submitted, .unknown),
             (.unknown, .accepted),
             (.unknown, .rejected):
            true
        default:
            false
        }
    }
}

enum SimulatorOutcome: String, CaseIterable, Identifiable, Sendable {
    case accepted
    case rejected
    case unknown

    var id: Self { self }
    var title: String {
        switch self {
        case .accepted: "Annahme simulieren"
        case .rejected: "Ablehnung simulieren"
        case .unknown: "Unbekannten Status simulieren"
        }
    }

    var paymentStatus: PaymentStatus {
        switch self {
        case .accepted: .accepted
        case .rejected: .rejected
        case .unknown: .unknown
        }
    }
}

struct PaymentOrder: Identifiable, Hashable, Sendable {
    let id: UUID
    var accountID: UUID
    var type: PaymentType
    var recipientName: String
    var iban: String
    var bic: String
    var amountMinor: Int64
    var currency: String
    var executionDate: Date
    var purpose: String
    var endToEndID: String
    var status: PaymentStatus
    var idempotencyKey: String
    var bankReference: String
    var createdAt: Date
    var updatedAt: Date
    var payeeID: UUID? = nil
    var payeeBankAccountID: UUID? = nil
    var purposeCode: String = ""

    func validate() throws {
        let normalizedRecipient = recipientName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedPurpose = purpose.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedEndToEndID = endToEndID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedRecipient.isEmpty,
              normalizedRecipient.count <= 70,
              !normalizedPurpose.isEmpty,
              normalizedPurpose.count <= 140,
              !normalizedEndToEndID.isEmpty,
              normalizedEndToEndID.count <= 35,
              amountMinor > 0 else {
            throw FinanceError.database(
                "Empfänger (maximal 70 Zeichen), Verwendungszweck (maximal 140 Zeichen), End-to-End-ID (maximal 35 Zeichen) und positiver Betrag sind erforderlich."
            )
        }
        guard currency.uppercased() == "EUR" else {
            throw FinanceError.database("SEPA-Überweisungen erfordern EUR.")
        }
        guard IBANValidator.isValid(iban) else { throw FinanceError.invalidIBAN }
        let normalizedBIC = bic.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !normalizedBIC.isEmpty,
           normalizedBIC.range(
               of: "^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$",
               options: .regularExpression
           ) == nil {
            throw FinanceError.database(
                "Die BIC muss 8 oder 11 gültige Zeichen enthalten."
            )
        }
        guard purposeCode.isEmpty || purposeCode.range(
            of: "^[A-Z0-9]{1,4}$", options: .regularExpression
        ) != nil else {
            throw FinanceError.database("Der SEPA-Zweckcode ist ungültig.")
        }
    }
}

struct DirectDebitOrder: Identifiable, Hashable, Sendable {
    let id: UUID
    var creditorAccountID: UUID
    var debtorPayeeID: UUID
    var debtorBankAccountID: UUID
    var mandateID: UUID
    var creditorName: String
    var creditorID: String
    var creditorIBAN: String
    var creditorBIC: String
    var debtorName: String
    var debtorIBAN: String
    var debtorBIC: String
    var amountMinor: Int64
    var currency: String
    var collectionDate: Date
    var purpose: String
    var endToEndID: String
    var mandateReference: String
    var mandateSignedOn: Date
    var sequenceType: SEPAMandateSequenceType
    var status: PaymentStatus
    var idempotencyKey: String
    var bankReference: String
    var createdAt: Date
    var updatedAt: Date

    func validate() throws {
        guard !creditorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !debtorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !mandateReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              amountMinor > 0 else {
            throw FinanceError.invalidDirectDebit(
                "Gläubiger, Zahler, Mandat, Verwendungszweck und positiver Betrag sind erforderlich."
            )
        }
        guard currency.uppercased() == "EUR" else {
            throw FinanceError.invalidDirectDebit(
                "SEPA-Basislastschriften erfordern EUR."
            )
        }
        guard IBANValidator.isValid(debtorIBAN) else {
            throw FinanceError.invalidIBAN
        }
        guard IBANValidator.isValid(creditorIBAN) else {
            throw FinanceError.invalidDirectDebit(
                "Die IBAN des Gläubigerkontos ist ungültig."
            )
        }
        guard SEPACreditorIDValidator.isValid(creditorID) else {
            throw FinanceError.invalidDirectDebit(
                "Die SEPA-Gläubiger-ID ist ungültig."
            )
        }
        guard mandateSignedOn <= collectionDate else {
            throw FinanceError.invalidDirectDebit(
                "Das Mandat darf nicht nach dem Fälligkeitsdatum unterzeichnet sein."
            )
        }
    }
}

enum PaymentBatchKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case creditTransfer
    case directDebit

    var id: Self { self }
    var title: String {
        switch self {
        case .creditTransfer: "Sammelüberweisung"
        case .directDebit: "Sammellastschrift"
        }
    }
}

struct PaymentBatch: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var kind: PaymentBatchKind
    var accountID: UUID
    var requestedDate: Date
    var status: PaymentStatus
    var idempotencyKey: String
    var bankReference: String
    var memberOrderIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    func validate() throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= 140 else {
            throw FinanceError.invalidPaymentBatch(
                "Die Bezeichnung muss 1 bis 140 Zeichen lang sein."
            )
        }
        guard memberOrderIDs.count >= 2,
              Set(memberOrderIDs).count == memberOrderIDs.count else {
            throw FinanceError.invalidPaymentBatch(
                "Ein Sammler benötigt mindestens zwei unterschiedliche Aufträge."
            )
        }
        guard status == .draft else {
            throw FinanceError.invalidPaymentBatch(
                "Ein neuer Sammler muss als Entwurf beginnen."
            )
        }
    }
}

enum StandingOrderStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case paused
    case cancelled

    var id: Self { self }
    var title: String {
        switch self {
        case .active: "Aktiv"
        case .paused: "Pausiert"
        case .cancelled: "Beendet"
        }
    }
}

enum BusinessDayAdjustment: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case nextWeekday
    case previousWeekday

    var id: Self { self }
    var title: String {
        switch self {
        case .none: "Nicht verschieben"
        case .nextWeekday: "Nächster Bankarbeitstag"
        case .previousWeekday: "Vorheriger Bankarbeitstag"
        }
    }

    func adjusted(
        _ date: Date,
        bankingCalendar: BankingCalendarProfile = .targetEuroV1,
        calendar: Calendar = .current
    ) -> Date {
        bankingCalendar.adjusted(date, direction: self, calendar: calendar)
    }
}

enum StandingOrderRunStatus: String, Codable, Sendable {
    case materialized
    case skipped

    var title: String {
        switch self {
        case .materialized: "Entwurf erzeugt"
        case .skipped: "Übersprungen"
        }
    }
}

struct StandingOrder: Identifiable, Hashable, Sendable {
    let id: UUID
    var accountID: UUID
    var name: String
    var recipientName: String
    var iban: String
    var bic: String
    var amountMinor: Int64
    var currency: String
    var purpose: String
    var nextExecutionDate: Date
    var endDate: Date?
    var frequency: RecurrenceFrequency
    var businessDayAdjustment: BusinessDayAdjustment
    var bankingCalendar: BankingCalendarProfile = .targetEuroV1
    var status: StandingOrderStatus
    var createdAt: Date
    var updatedAt: Date

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              amountMinor > 0 else {
            throw FinanceError.invalidStandingOrder(
                "Name, Empfänger, Verwendungszweck und positiver Betrag sind erforderlich."
            )
        }
        guard currency == "EUR" else {
            throw FinanceError.invalidStandingOrder("SEPA-Daueraufträge erfordern EUR.")
        }
        guard IBANValidator.isValid(iban) else { throw FinanceError.invalidIBAN }
        let normalizedBIC = bic.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !normalizedBIC.isEmpty {
            let pattern = #"^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$"#
            guard normalizedBIC.range(of: pattern, options: .regularExpression) != nil else {
                throw FinanceError.invalidStandingOrder("Die BIC muss 8 oder 11 gültige Zeichen enthalten.")
            }
        }
        if let endDate,
           Calendar.current.startOfDay(for: endDate)
            < Calendar.current.startOfDay(for: nextExecutionDate) {
            throw FinanceError.invalidStandingOrder(
                "Das Enddatum liegt vor der nächsten Ausführung."
            )
        }
    }
}

struct StandingOrderRun: Identifiable, Hashable, Sendable {
    let id: UUID
    var standingOrderID: UUID
    var dueDate: Date
    var executionDate: Date
    var status: StandingOrderRunStatus
    var paymentOrderID: UUID?
    var createdAt: Date
    var bankingCalendarID: String = BankingCalendarProfile.targetEuroV1.rawValue
    var bankingCalendarVersion: Int = BankingCalendarProfile.targetEuroV1.version
}

enum IBANValidator {
    static func normalized(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isValid(_ value: String) -> Bool {
        let iban = normalized(value)
        guard (15...34).contains(iban.count),
              iban.prefix(2).allSatisfy(\.isLetter),
              iban.dropFirst(2).prefix(2).allSatisfy(\.isNumber)
        else { return false }
        let rotated = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rotated {
            let digits: String
            if let number = character.wholeNumberValue {
                digits = String(number)
            } else if let ascii = character.asciiValue {
                digits = String(Int(ascii) - 55)
            } else {
                return false
            }
            for digit in digits {
                guard let number = digit.wholeNumberValue else { return false }
                remainder = (remainder * 10 + number) % 97
            }
        }
        return remainder == 1
    }
}

enum SEPACreditorIDValidator {
    static func normalized(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isValid(_ value: String) -> Bool {
        let identifier = normalized(value)
        guard (8...35).contains(identifier.count),
              identifier.prefix(2).allSatisfy(\.isLetter),
              identifier.dropFirst(2).prefix(2).allSatisfy(\.isNumber),
              identifier.dropFirst(4).prefix(3).allSatisfy({
                  $0.isLetter || $0.isNumber
              })
        else { return false }

        // Der dreistellige Geschäftsbereichscode ist nach EPC-Regelwerk
        // nicht Bestandteil der ISO-13616-Prüfsummenberechnung.
        let checksumSource = identifier.prefix(4) + identifier.dropFirst(7)
        let rotated = checksumSource.dropFirst(4) + checksumSource.prefix(4)
        var remainder = 0
        for character in rotated {
            let digits: String
            if let number = character.wholeNumberValue {
                digits = String(number)
            } else if let ascii = character.asciiValue {
                digits = String(Int(ascii) - 55)
            } else {
                return false
            }
            for digit in digits {
                guard let number = digit.wholeNumberValue else { return false }
                remainder = (remainder * 10 + number) % 97
            }
        }
        return remainder == 1
    }
}

enum SecurityType: String, Codable, CaseIterable, Identifiable, Sendable {
    case stock
    case fund
    case etf
    case bond
    case certificate
    case option
    case employeeOption
    case savingsBond
    case index
    case other

    var id: Self { self }
    var title: String {
        switch self {
        case .stock: "Aktie"
        case .fund: "Fonds"
        case .etf: "ETF"
        case .bond: "Anleihe"
        case .certificate: "Zertifikat"
        case .option: "Option"
        case .employeeOption: "Mitarbeiteroption"
        case .savingsBond: "Sparbrief"
        case .index: "Index"
        case .other: "Sonstiges"
        }
    }
}

struct Security: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var shortName: String
    var isin: String
    var wkn: String
    var ticker: String
    var type: SecurityType
    var currency: String
    var exchange: String
    var priceDecimals: Int
    var allowsShort: Bool
    var isActive: Bool
    var note: String
}

struct AssetClass: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var color: String
    var isActive: Bool
}

struct SecurityAllocation: Identifiable, Hashable, Sendable {
    let id: UUID
    var securityID: UUID
    var assetClassID: UUID
    var basisPoints: Int
}

enum SecurityTradeType: String, Codable, CaseIterable, Sendable {
    case buy
    case sell
    case dividend
    case fee

    var title: String {
        switch self {
        case .buy: "Kauf"
        case .sell: "Verkauf"
        case .dividend: "Dividende/Zins"
        case .fee: "Gebühr"
        }
    }
}

struct SecurityTrade: Identifiable, Hashable, Sendable {
    let id: UUID
    var accountID: UUID
    var securityID: UUID
    var type: SecurityTradeType
    var tradeDate: Date
    var quantityMicro: Int64
    var priceMinor: Int64
    var feesMinor: Int64
    var taxesMinor: Int64
    var grossMinor: Int64
    var realizedGainMinor: Int64
    var currency: String
    var note: String
}

struct SecurityPrice: Identifiable, Hashable, Sendable {
    var id: String {
        "\(securityID.uuidString):\(priceDate.timeIntervalSince1970):\(source)"
    }
    var securityID: UUID
    var priceDate: Date
    var priceMinor: Int64
    var currency: String
    var source: String
}

struct PortfolioLot: Identifiable, Hashable, Sendable {
    let id: UUID
    var accountID: UUID
    var securityID: UUID
    var acquisitionTradeID: UUID
    var acquisitionDate: Date
    var quantityMicro: Int64
    var remainingQuantityMicro: Int64
    var totalCostMinor: Int64
    var remainingCostMinor: Int64
    var currency: String
}

struct PortfolioPosition: Identifiable, Hashable, Sendable {
    let security: Security
    let accountID: UUID
    let quantityMicro: Int64
    let costBasisMinor: Int64
    let latestPriceMinor: Int64?

    var id: String { "\(accountID.uuidString):\(security.id.uuidString)" }
    var marketValueMinor: Int64? {
        latestPriceMinor.map {
            NSDecimalNumber(
                decimal: Decimal(quantityMicro) * Decimal($0)
                    / Decimal(SecurityQuantity.scale)
            ).rounding(
                accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .bankers, scale: 0,
                    raiseOnExactness: false, raiseOnOverflow: true,
                    raiseOnUnderflow: true, raiseOnDivideByZero: true
                )
            ).int64Value
        }
    }
    var unrealizedGainMinor: Int64? { marketValueMinor.map { $0 - costBasisMinor } }
}

struct FinanceLoan: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var lender: String
    var principalMinor: Int64
    var disbursementDate: Date
    var firstPaymentDate: Date
    var fixedRateUntil: Date?
    var termMonths: Int
    var installmentMinor: Int64
    var regularFeeMinor: Int64
    var dueDay: Int
    var linkedAccountID: UUID?
    var currency: String
    var note: String
    var isActive: Bool

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              principalMinor > 0,
              termMonths > 0,
              installmentMinor > 0,
              regularFeeMinor >= 0,
              installmentMinor > regularFeeMinor,
              (1...31).contains(dueDay),
              firstPaymentDate >= disbursementDate
        else {
            throw FinanceError.invalidLoanTerms(
                "Name, positive Beträge, Laufzeit und ein gültiger erster Fälligkeitstermin sind erforderlich."
            )
        }
    }
}

struct LoanInterestRate: Identifiable, Hashable, Sendable {
    let id: UUID
    var loanID: UUID
    var annualBasisPoints: Int
    var effectiveFrom: Date
    var note: String

    var formattedPercent: String {
        (Decimal(annualBasisPoints) / 100).formatted(
            .number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(2))
        ) + " %"
    }
}

struct LoanExtraPayment: Identifiable, Hashable, Sendable {
    let id: UUID
    var loanID: UUID
    var paymentDate: Date
    var amountMinor: Int64
    var note: String
}

struct LoanScheduleEntry: Identifiable, Hashable, Sendable {
    let id: String
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
}

enum LoanPaymentMatchSource: String, Codable, CaseIterable, Sendable {
    case generated
    case linkedExisting
    case legacy

    var title: String {
        switch self {
        case .generated: "Automatisch gebucht"
        case .linkedExisting: "Reale Buchung zugeordnet"
        case .legacy: "Ältere Zuordnung"
        }
    }
}

struct LoanPaymentMatch: Identifiable, Hashable, Sendable {
    let id: UUID
    let loanID: UUID
    let transactionID: UUID
    let scheduledDate: Date
    let principalMinor: Int64
    let interestMinor: Int64
    let feeMinor: Int64
    let extraPaymentMinor: Int64
    let matchedAt: Date
    let source: LoanPaymentMatchSource

    var actualPaymentMinor: Int64 {
        principalMinor + interestMinor + feeMinor + extraPaymentMinor
    }
}

struct LoanPaymentCandidate: Identifiable, Hashable, Sendable {
    var id: UUID { transaction.id }
    let transaction: FinanceTransaction
    let dayDistance: Int
    let amountDifferenceMinor: Int64
}

enum LoanPaymentMatchingEngine {
    static func candidates(
        for entry: LoanScheduleEntry,
        loan: FinanceLoan,
        transactions: [FinanceTransaction],
        alreadyMatchedTransactionIDs: Set<UUID>,
        calendar suppliedCalendar: Calendar? = nil,
        dayWindow: Int = 45
    ) -> [LoanPaymentCandidate] {
        guard let accountID = loan.linkedAccountID else { return [] }
        var calendar = suppliedCalendar ?? Calendar(identifier: .gregorian)
        if suppliedCalendar == nil { calendar.timeZone = TimeZone(secondsFromGMT: 0)! }
        let expected = entry.installmentMinor + entry.extraPaymentMinor
        return transactions.compactMap { transaction in
            guard transaction.accountID == accountID,
                  transaction.currency.uppercased() == loan.currency.uppercased(),
                  transaction.amountMinor < 0,
                  transaction.transferID == nil,
                  transaction.splits.isEmpty,
                  transaction.vatMode == .none,
                  transaction.status == .booked || transaction.status == .cleared,
                  !alreadyMatchedTransactionIDs.contains(transaction.id)
            else { return nil }
            let start = calendar.startOfDay(for: entry.dueDate)
            let end = calendar.startOfDay(for: transaction.valueDate ?? transaction.bookingDate)
            let distance = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            guard abs(distance) <= dayWindow else { return nil }
            return LoanPaymentCandidate(
                transaction: transaction,
                dayDistance: distance,
                amountDifferenceMinor: abs(transaction.amountMinor) - expected
            )
        }.sorted {
            let left = (abs($0.amountDifferenceMinor), abs($0.dayDistance), $0.transaction.bookingDate, $0.id.uuidString)
            let right = (abs($1.amountDifferenceMinor), abs($1.dayDistance), $1.transaction.bookingDate, $1.id.uuidString)
            return left < right
        }
    }
}

enum LoanAmortizationEngine {
    static func schedule(
        loan: FinanceLoan,
        rates: [LoanInterestRate],
        extraPayments: [LoanExtraPayment],
        calendar suppliedCalendar: Calendar? = nil
    ) throws -> [LoanScheduleEntry] {
        var calendar = suppliedCalendar ?? Calendar(identifier: .gregorian)
        if suppliedCalendar == nil {
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        }
        try loan.validate()
        let sortedRates = rates.sorted {
            if $0.effectiveFrom != $1.effectiveFrom {
                return $0.effectiveFrom < $1.effectiveFrom
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let firstRate = sortedRates.first,
              firstRate.effectiveFrom <= loan.disbursementDate,
              sortedRates.allSatisfy({ (0...100_000).contains($0.annualBasisPoints) })
        else {
            throw FinanceError.invalidLoanTerms(
                "Mindestens ein gültiger Zinssatz muss ab Auszahlung gelten."
            )
        }
        let extrasByMonth = Dictionary(grouping: extraPayments) {
            calendar.dateComponents([.year, .month], from: $0.paymentDate)
        }
        var balance = loan.principalMinor
        var result: [LoanScheduleEntry] = []
        for offset in 0..<loan.termMonths where balance > 0 {
            guard let dueDate = calendar.date(
                byAdding: .month, value: offset, to: loan.firstPaymentDate
            ) else { continue }
            let rate = sortedRates.last(where: { $0.effectiveFrom <= dueDate }) ?? firstRate
            let interest = roundedMinor(
                Decimal(balance) * Decimal(rate.annualBasisPoints)
                    / Decimal(10_000) / Decimal(12)
            )
            guard loan.installmentMinor > interest + loan.regularFeeMinor else {
                throw FinanceError.invalidLoanTerms(
                    "Die Rate deckt Zins und Gebühr am \(dueDate.formatted(date: .numeric, time: .omitted)) nicht."
                )
            }
            let regularPrincipal = min(
                balance,
                loan.installmentMinor - interest - loan.regularFeeMinor
            )
            let components = calendar.dateComponents([.year, .month], from: dueDate)
            let requestedExtra = extrasByMonth[components, default: []]
                .reduce(Int64.zero) { $0 + max(0, $1.amountMinor) }
            let extra = min(balance - regularPrincipal, requestedExtra)
            let closing = balance - regularPrincipal - extra
            result.append(
                LoanScheduleEntry(
                    id: "\(loan.id.uuidString):\(offset + 1)",
                    sequence: offset + 1, dueDate: dueDate,
                    openingBalanceMinor: balance,
                    installmentMinor: regularPrincipal + interest + loan.regularFeeMinor,
                    principalMinor: regularPrincipal, interestMinor: interest,
                    feeMinor: loan.regularFeeMinor, extraPaymentMinor: extra,
                    closingBalanceMinor: closing,
                    annualBasisPoints: rate.annualBasisPoints
                )
            )
            balance = closing
        }
        return result
    }

    private static func roundedMinor(_ value: Decimal) -> Int64 {
        NSDecimalNumber(decimal: value).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .bankers, scale: 0,
                raiseOnExactness: false, raiseOnOverflow: true,
                raiseOnUnderflow: true, raiseOnDivideByZero: true
            )
        ).int64Value
    }
}

enum PropertyAssetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case realEstate
    case vehicle
    case collectible
    case other

    var id: Self { self }
    var title: String {
        switch self {
        case .realEstate: "Immobilie"
        case .vehicle: "Fahrzeug"
        case .collectible: "Sammlerstück"
        case .other: "Sonstiger Vermögenswert"
        }
    }
}

struct PropertyAsset: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var type: PropertyAssetType
    var purchaseDate: Date
    var purchaseValueMinor: Int64
    var linkedLoanID: UUID?
    var location: String
    var note: String
    var isActive: Bool
}

struct AssetValuation: Identifiable, Hashable, Sendable {
    let id: UUID
    var assetID: UUID
    var valuationDate: Date
    var valueMinor: Int64
    var source: String
    var note: String
}

struct PropertyAssetPosition: Identifiable, Hashable, Sendable {
    let asset: PropertyAsset
    let latestValuation: AssetValuation?
    let linkedLoanBalanceMinor: Int64

    var id: UUID { asset.id }
    var currentValueMinor: Int64 {
        latestValuation?.valueMinor ?? asset.purchaseValueMinor
    }
    var netEquityMinor: Int64 {
        currentValueMinor - linkedLoanBalanceMinor
    }
}

enum ContractType: String, Codable, CaseIterable, Identifiable, Sendable {
    case insurance
    case energy
    case telecommunications
    case subscription
    case lease
    case membership
    case other

    var id: Self { self }
    var title: String {
        switch self {
        case .insurance: "Versicherung"
        case .energy: "Energie"
        case .telecommunications: "Telekommunikation"
        case .subscription: "Abonnement"
        case .lease: "Miete/Leasing"
        case .membership: "Mitgliedschaft"
        case .other: "Sonstiger Vertrag"
        }
    }
}

enum ContractPaymentFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case monthly
    case quarterly
    case semiannual
    case yearly
    case oneTime

    var id: Self { self }
    var title: String {
        switch self {
        case .weekly: "Wöchentlich"
        case .monthly: "Monatlich"
        case .quarterly: "Quartalsweise"
        case .semiannual: "Halbjährlich"
        case .yearly: "Jährlich"
        case .oneTime: "Einmalig"
        }
    }

    func annualized(_ amountMinor: Int64) -> Int64 {
        switch self {
        case .weekly: amountMinor * 52
        case .monthly: amountMinor * 12
        case .quarterly: amountMinor * 4
        case .semiannual: amountMinor * 2
        case .yearly, .oneTime: amountMinor
        }
    }
}

struct FinanceContract: Identifiable, Hashable, Sendable {
    let id: UUID
    var provider: String
    var contractNumber: String
    var name: String
    var type: ContractType
    var startDate: Date
    var initialTermMonths: Int
    var renewalMonths: Int
    var cancellationNoticeDays: Int
    var amountMinor: Int64
    var frequency: ContractPaymentFrequency
    var accountID: UUID?
    var categoryID: UUID?
    var reminderDays: Int
    var note: String
    var isActive: Bool

    var annualCostMinor: Int64 {
        frequency.annualized(amountMinor)
    }

    func nextRenewal(
        after referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard initialTermMonths > 0,
              var renewal = calendar.date(
                  byAdding: .month, value: initialTermMonths, to: startDate
              )
        else { return nil }
        guard renewalMonths > 0 else {
            return renewal >= referenceDate ? renewal : nil
        }
        while renewal < referenceDate {
            guard let next = calendar.date(
                byAdding: .month, value: renewalMonths, to: renewal
            ) else { return nil }
            renewal = next
        }
        return renewal
    }

    func cancellationDeadline(
        after referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let renewal = nextRenewal(after: referenceDate, calendar: calendar) else {
            return nil
        }
        return calendar.date(
            byAdding: .day, value: -cancellationNoticeDays, to: renewal
        )
    }
}

struct ContractDocument: Identifiable, Hashable, Sendable {
    let id: UUID
    var contractID: UUID
    var name: String
    var fileName: String
    var bookmarkData: Data?
    var addedAt: Date
}

enum InventoryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case electronics
    case furniture
    case jewelry
    case art
    case sports
    case household
    case other

    var id: Self { self }
    var title: String {
        switch self {
        case .electronics: "Elektronik"
        case .furniture: "Möbel"
        case .jewelry: "Schmuck"
        case .art: "Kunst"
        case .sports: "Sport"
        case .household: "Haushalt"
        case .other: "Sonstiges"
        }
    }
}

struct InventoryItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var category: InventoryCategory
    var room: String
    var purchaseDate: Date?
    var purchasePriceMinor: Int64
    var currentValueMinor: Int64
    var insuranceValueMinor: Int64
    var retailer: String
    var serialNumber: String
    var warrantyEnd: Date?
    var note: String
    var isActive: Bool
}

struct InventoryAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    var itemID: UUID
    var kind: String
    var fileName: String
    var bookmarkData: Data?
    var addedAt: Date
}
