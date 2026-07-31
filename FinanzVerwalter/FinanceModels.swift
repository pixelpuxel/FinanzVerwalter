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

    func validate() throws {
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
}

struct TransactionTemplateSplit: Codable, Equatable, Sendable {
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

struct TransactionTemplate: Identifiable, Codable, Equatable, Sendable {
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

    init(id: UUID = UUID(), name: String, transaction: FinanceTransaction) {
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
            taxMinor: taxMinor ?? 0
        )
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

    func occurrences(
        until end: Date,
        excludingReferences: Set<String> = [],
        calendar: Calendar = .current
    ) -> [FinanceTransaction] {
        guard isActive else { return [] }
        var due = nextDueDate
        var values: [FinanceTransaction] = []
        var guardCount = 0
        while due <= end, due <= (endDate ?? end), guardCount < 1_000 {
            let value = FinanceTransaction(
                    id: UUID(), accountID: accountID, bookingDate: due, valueDate: due,
                    payee: payee, purpose: purpose, categoryID: categoryID,
                    amountMinor: amountMinor, currency: currency, status: .expected,
                    memo: "Regelmäßig: \(name)",
                    reference: "schedule:\(id.uuidString):\(Int(due.timeIntervalSince1970))",
                    transferID: nil, importFingerprint: nil, splits: []
                )
            if !excludingReferences.contains(value.reference) {
                values.append(value)
            }
            due = frequency.next(after: due, calendar: calendar)
            guardCount += 1
        }
        return values
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

    var id: UUID { category.id }
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
             (.submitted, .unknown):
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

    func validate() throws {
        guard !recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              amountMinor > 0 else {
            throw FinanceError.database("Empfänger, Verwendungszweck und positiver Betrag sind erforderlich.")
        }
        guard IBANValidator.isValid(iban) else { throw FinanceError.invalidIBAN }
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
        case .nextWeekday: "Nächster Werktag"
        case .previousWeekday: "Vorheriger Werktag"
        }
    }

    func adjusted(_ date: Date, calendar: Calendar = .current) -> Date {
        guard self != .none else { return date }
        var result = date
        let step = self == .nextWeekday ? 1 : -1
        while calendar.isDateInWeekend(result) {
            result = calendar.date(byAdding: .day, value: step, to: result) ?? result
        }
        return result
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
    let id: UUID
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
                    id: UUID(), sequence: offset + 1, dueDate: dueDate,
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
