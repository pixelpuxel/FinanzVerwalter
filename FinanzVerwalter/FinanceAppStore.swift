import CryptoKit
import Foundation

@MainActor
final class FinanceAppStore: ObservableObject {
    @Published private(set) var fileInfo: FinanceFileInfo?
    @Published private(set) var accounts: [FinanceAccount] = []
    @Published private(set) var accountGroups: [AccountGroup] = []
    @Published private(set) var categories: [FinanceCategory] = []
    @Published private(set) var transactions: [FinanceTransaction] = []
    @Published private(set) var balances: [UUID: Int64] = [:]
    @Published private(set) var reportRows: [CategoryReportRow] = []
    @Published private(set) var reportTemplates: [SavedReportTemplate] = []
    @Published private(set) var categorizationRules: [CategorizationRule] = []
    @Published private(set) var scheduledTransactions: [ScheduledTransaction] = []
    @Published private(set) var budgets: [FinanceBudget] = []
    @Published private(set) var paymentOrders: [PaymentOrder] = []
    @Published private(set) var standingOrders: [StandingOrder] = []
    @Published private(set) var payees: [FinancePayee] = []
    @Published private(set) var tags: [FinanceTag] = []
    @Published private(set) var securities: [Security] = []
    @Published private(set) var assetClasses: [AssetClass] = []
    @Published private(set) var portfolioPositions: [PortfolioPosition] = []
    @Published private(set) var securityTrades: [SecurityTrade] = []
    @Published private(set) var loans: [FinanceLoan] = []
    @Published private(set) var propertyAssetPositions: [PropertyAssetPosition] = []
    @Published private(set) var contracts: [FinanceContract] = []
    @Published private(set) var inventoryItems: [InventoryItem] = []
    @Published var selectedAccountID: UUID?
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var statusText = "Bereit"
    @Published var isBusy = false

    private var repository: SQLiteFinanceStore?

    init(repository: SQLiteFinanceStore? = nil) {
        do {
            if let repository {
                self.repository = repository
            } else if ProcessInfo.processInfo.arguments.contains("-demo") {
                let demoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("finanzverwalter-ui-demo-\(ProcessInfo.processInfo.processIdentifier).qdata")
                self.repository = try SQLiteFinanceStore(fileURL: demoURL)
            } else if ProcessInfo.processInfo.environment[
                "XCTestConfigurationFilePath"
            ] != nil {
                let testHostURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "finanzverwalter-test-host-\(ProcessInfo.processInfo.processIdentifier).qdata"
                    )
                self.repository = try SQLiteFinanceStore(fileURL: testHostURL)
            } else {
                self.repository = try SQLiteFinanceStore()
            }
            try load()
            if ProcessInfo.processInfo.arguments.contains("-demo"), accounts.isEmpty {
                try seedDemo()
                try load()
            }
        } catch {
            self.repository = nil
            errorMessage = error.localizedDescription
            statusText = "Finanzdatei konnte nicht geöffnet werden"
        }
    }

    var selectedAccount: FinanceAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    var filteredTransactions: [FinanceTransaction] {
        transactions.filter { transaction in
            (selectedAccountID == nil || transaction.accountID == selectedAccountID)
                && (
                    searchText.isEmpty
                    || transaction.payee.localizedCaseInsensitiveContains(searchText)
                    || transaction.purpose.localizedCaseInsensitiveContains(searchText)
                    || transaction.memo.localizedCaseInsensitiveContains(searchText)
                    || categoryName(transaction.categoryID).localizedCaseInsensitiveContains(searchText)
                    || transaction.tagIDs.contains {
                        tagName($0).localizedCaseInsensitiveContains(searchText)
                    }
                )
        }
    }

    var totalBalanceMinor: Int64 {
        let baseCurrency = fileInfo?.baseCurrency ?? "EUR"
        return accounts.filter {
            !$0.isHidden && $0.includeNetWorth && $0.currency == baseCurrency
        }
            .reduce(Int64.zero) { $0 + (balances[$1.id] ?? 0) }
    }

    func runningBalances(accountID: UUID? = nil) -> [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for account in accounts where accountID == nil || account.id == accountID {
            var balance = account.openingBalanceMinor
            let accountTransactions = transactions
                .filter { $0.accountID == account.id }
                .sorted {
                    if $0.bookingDate != $1.bookingDate {
                        return $0.bookingDate < $1.bookingDate
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
            for transaction in accountTransactions {
                if transaction.status != .cancelled {
                    balance += transaction.amountMinor
                }
                result[transaction.id] = balance
            }
        }
        return result
    }

    func transactionReport(
        _ query: TransactionReportQuery
    ) -> TransactionReportSnapshot {
        TransactionReportEngine.snapshot(
            query: query,
            transactions: transactions,
            accounts: accounts,
            categories: categories,
            tags: tags
        )
    }

    func saveReportTemplate(_ template: SavedReportTemplate) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveReportTemplate(template)
            reportTemplates = try repository.reportTemplates()
            statusText = "Berichtsvorlage gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteReportTemplate(_ template: SavedReportTemplate) {
        guard let repository else { return }
        do {
            try repository.deleteReportTemplate(id: template.id)
            reportTemplates = try repository.reportTemplates()
            statusText = "Berichtsvorlage gelöscht"
        } catch {
            present(error)
        }
    }

    func reload() {
        do {
            try load()
            statusText = "Finanzdatei aktualisiert"
        } catch {
            present(error)
        }
    }

    func categoryName(_ id: UUID?) -> String {
        guard let id else { return "Nicht kategorisiert" }
        return categories.first { $0.id == id }?.name ?? "Unbekannte Kategorie"
    }

    func categoryPath(_ id: UUID?) -> String {
        guard let id, let category = categories.first(where: { $0.id == id }) else {
            return "Nicht kategorisiert"
        }
        var names = [category.name]
        var parentID = category.parentID
        var visited = Set([category.id])
        while let currentID = parentID,
              visited.insert(currentID).inserted,
              let parent = categories.first(where: { $0.id == currentID }) {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }
        return names.joined(separator: " › ")
    }

    func transactionCategoryPath(_ transaction: FinanceTransaction) -> String {
        if transaction.transferID != nil {
            return "Umbuchung"
        }
        guard !transaction.splits.isEmpty else {
            return categoryPath(transaction.categoryID)
        }
        let paths = transaction.splits
            .map { categoryPath($0.categoryID) }
            .reduce(into: [String]()) { result, path in
                if !result.contains(path) {
                    result.append(path)
                }
            }
        return "Split: " + paths.joined(separator: " · ")
    }

    var categoriesByPath: [FinanceCategory] {
        categories.sorted {
            categoryPath($0.id).localizedCaseInsensitiveCompare(categoryPath($1.id))
                == .orderedAscending
        }
    }

    func accountName(_ id: UUID) -> String {
        accounts.first { $0.id == id }?.name ?? "Unbekanntes Konto"
    }

    func accountGroupName(_ id: UUID?) -> String {
        guard let id else { return "Ohne Gruppe" }
        return accountGroups.first { $0.id == id }?.name ?? "Unbekannte Gruppe"
    }

    func tagName(_ id: UUID) -> String {
        tags.first { $0.id == id }?.name ?? "Unbekannter Tag"
    }

    func payeeSuggestions(for query: String) -> [FinancePayee] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return payees
            .filter { payee in
                payee.isActive && (
                    trimmed.isEmpty
                    || payee.canonicalName.localizedCaseInsensitiveContains(trimmed)
                    || payee.aliases.contains {
                        $0.localizedCaseInsensitiveContains(trimmed)
                    }
                )
            }
            .sorted { left, right in
                let query = trimmed.lowercased()
                let leftPrefix = left.canonicalName.lowercased().hasPrefix(query)
                let rightPrefix = right.canonicalName.lowercased().hasPrefix(query)
                if leftPrefix != rightPrefix { return leftPrefix }
                let leftCount = transactions.filter { $0.payeeID == left.id }.count
                let rightCount = transactions.filter { $0.payeeID == right.id }.count
                if leftCount != rightCount { return leftCount > rightCount }
                return left.canonicalName.localizedCaseInsensitiveCompare(right.canonicalName) == .orderedAscending
            }
    }

    func saveAccount(
        id: UUID? = nil,
        name: String,
        institution: String,
        type: AccountType,
        openingBalance: String
    ) -> Bool {
        guard let repository else { return false }
        do {
            let amount = try Money(parsing: openingBalance)
            let account = FinanceAccount(
                id: id ?? UUID(),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                institution: institution.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                currency: "EUR",
                openingBalanceMinor: amount.minorUnits,
                isHidden: false,
                isClosed: false,
                sortOrder: accounts.count
            )
            try repository.saveAccount(account)
            selectedAccountID = account.id
            try load()
            statusText = "Konto „\(account.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveAccount(_ value: FinanceAccount) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveAccount(value)
            selectedAccountID = value.id
            try load()
            statusText = "Konto „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveAccountGroup(_ value: AccountGroup) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveAccountGroup(value)
            try load()
            statusText = "Kontengruppe „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveCategory(name: String, kind: CategoryKind) -> Bool {
        guard let repository else { return false }
        do {
            let category = FinanceCategory(
                id: UUID(), parentID: nil,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind, color: kind == .income ? "green" : "blue", isActive: true
            )
            try repository.saveCategory(category)
            try load()
            statusText = "Kategorie „\(category.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveCategory(_ value: FinanceCategory) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveCategory(value)
            try load()
            statusText = "Kategorie „\(categoryPath(value.id))“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveTag(_ value: FinanceTag) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveTag(value)
            try load()
            statusText = "Tag „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func savePayee(_ value: FinancePayee) -> Bool {
        guard let repository else { return false }
        do {
            try repository.savePayee(value)
            try load()
            statusText = "Empfänger „\(value.canonicalName)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveTransaction(
        id: UUID? = nil,
        accountID: UUID,
        date: Date,
        payee: String,
        purpose: String,
        categoryID: UUID?,
        amount: String,
        status: TransactionStatus,
        memo: String = "",
        reference: String = "",
        payeeID: UUID? = nil,
        tagIDs: [UUID] = []
    ) -> Bool {
        guard let repository else { return false }
        do {
            let money = try Money(parsing: amount)
            let value = FinanceTransaction(
                id: id ?? UUID(), accountID: accountID, bookingDate: date, valueDate: date,
                payee: payee.trimmingCharacters(in: .whitespacesAndNewlines),
                purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryID: categoryID, amountMinor: money.minorUnits, currency: money.currency,
                status: status, memo: memo, reference: reference,
                transferID: nil, importFingerprint: nil, splits: [],
                payeeID: payeeID, tagIDs: tagIDs
            )
            try repository.saveTransaction(value)
            try load()
            statusText = "Buchung gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveSplitTransaction(_ value: FinanceTransaction) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveTransaction(value)
            try load()
            statusText = "Splitbuchung gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func bulkAssignCategory(transactionIDs: Set<UUID>, categoryID: UUID?) -> Bool {
        guard let repository else { return false }
        do {
            let result = try repository.bulkUpdateTransactionCategory(
                ids: transactionIDs,
                categoryID: categoryID
            )
            try load()
            statusText = "\(result.updatedCount) Buchungen kategorisiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteTransaction(_ value: FinanceTransaction) {
        guard let repository else { return }
        do {
            try repository.deleteTransaction(id: value.id)
            try load()
            statusText = "Buchung gelöscht"
        } catch {
            present(error)
        }
    }

    func createTransfer(
        from sourceID: UUID,
        to destinationID: UUID,
        amount: String,
        date: Date,
        purpose: String
    ) -> Bool {
        guard
            let repository,
            let source = accounts.first(where: { $0.id == sourceID }),
            let destination = accounts.first(where: { $0.id == destinationID })
        else { return false }
        do {
            let money = try Money(parsing: amount)
            try repository.createTransfer(
                from: source, to: destination,
                amountMinor: abs(money.minorUnits), date: date, purpose: purpose
            )
            try load()
            statusText = "Umbuchung atomar gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func importCSV(data: Data, accountID: UUID) -> ImportPreview? {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            present(FinanceError.missingAccount)
            return nil
        }
        do {
            return try CSVFinanceImporter.preview(data: data, account: account)
        } catch {
            present(error)
            return nil
        }
    }

    func importQIF(data: Data, accountID: UUID) -> ImportPreview? {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            present(FinanceError.missingAccount)
            return nil
        }
        do {
            return try QIFFinanceImporter.preview(
                data: data, account: account, categories: categories
            )
        } catch {
            present(error)
            return nil
        }
    }

    func previewQIFPackage(data: Data) -> QIFPackagePreview? {
        do {
            return try QIFPackageImporter.preview(
                data: data,
                existingAccounts: accounts,
                existingCategories: categories,
                currency: fileInfo?.baseCurrency ?? "EUR"
            )
        } catch {
            present(error)
            return nil
        }
    }

    func commitImport(_ preview: ImportPreview) -> Bool {
        guard let repository else { return false }
        do {
            try repository.commitImport(preview)
            try load()
            statusText = "\(preview.rows.count) Buchungen importiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func commitQIFPackage(_ package: QIFPackagePreview) -> Bool {
        guard let repository else { return false }
        do {
            try repository.commitQIFPackage(package)
            try load()
            statusText = "\(package.importPreview.rows.count) Buchungen aus dem QIF-Paket importiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func createBackup(at url: URL) -> Bool {
        guard let repository else { return false }
        do {
            try repository.backup(to: url)
            statusText = "Sicherung geprüft und erstellt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func backupData() -> Data? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finanzverwalter-\(UUID().uuidString).qbackup")
        guard createBackup(at: url) else { return nil }
        return try? Data(contentsOf: url)
    }

    func restoreBackup(from source: URL) -> Bool {
        guard let current = repository else { return false }
        let target = current.fileURL
        let safety = target.deletingLastPathComponent().appendingPathComponent(
            "Autosicherung-vor-Wiederherstellung-\(Int(Date().timeIntervalSince1970)).qbackup"
        )
        do {
            try SQLiteFinanceStore.validateBackup(at: source)
            try current.backup(to: safety)
            current.close()
            repository = nil
            let manager = FileManager.default
            let staged = target.deletingLastPathComponent()
                .appendingPathComponent("restore-\(UUID().uuidString).qdata")
            try manager.copyItem(at: source, to: staged)
            if manager.fileExists(atPath: target.path) {
                _ = try manager.replaceItemAt(target, withItemAt: staged)
            } else {
                try manager.moveItem(at: staged, to: target)
            }
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: target.path + suffix)
                if manager.fileExists(atPath: sidecar.path) {
                    try manager.removeItem(at: sidecar)
                }
            }
            repository = try SQLiteFinanceStore(fileURL: target)
            try load()
            statusText = "Sicherung validiert und wiederhergestellt"
            return true
        } catch {
            if repository == nil {
                repository = try? SQLiteFinanceStore(fileURL: target)
                try? load()
            }
            present(error)
            return false
        }
    }

    func checkIntegrity() {
        guard let repository else { return }
        do {
            statusText = try repository.integrityCheck()
                ? "Datenbank-Integritätsprüfung: OK"
                : "Datenbank-Integritätsprüfung fehlgeschlagen"
        } catch {
            present(error)
        }
    }

    func reconcile(accountID: UUID, endingBalance: String, date: Date) -> Bool {
        guard
            let repository,
            let account = accounts.first(where: { $0.id == accountID })
        else { return false }
        do {
            let amount = try Money(parsing: endingBalance, currency: account.currency)
            try repository.reconcile(
                account: account, endingBalanceMinor: amount.minorUnits, date: date
            )
            try load()
            statusText = "Konto „\(account.name)“ erfolgreich abgeglichen"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func rulePreviewCount(_ rule: CategorizationRule) -> Int {
        transactions.filter(rule.matches).count
    }

    func saveRule(_ rule: CategorizationRule) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveCategorizationRule(rule)
            try load()
            statusText = "Regel „\(rule.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func applyRule(_ rule: CategorizationRule) -> Int? {
        guard let repository else { return nil }
        do {
            let count = try repository.applyCategorizationRule(rule)
            try load()
            statusText = "Regel auf \(count) Buchungen angewendet"
            return count
        } catch {
            present(error)
            return nil
        }
    }

    func forecastOccurrences(days: Int = 90) -> [FinanceTransaction] {
        let end = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let existingReferences = Set(transactions.map(\.reference).filter { !$0.isEmpty })
        let includedAccounts = Set(
            accounts.filter { $0.includeForecast && !$0.isClosed }.map(\.id)
        )
        return scheduledTransactions
            .filter { includedAccounts.contains($0.accountID) }
            .flatMap { $0.occurrences(until: end, excludingReferences: existingReferences) }
            .sorted {
                if $0.bookingDate != $1.bookingDate { return $0.bookingDate < $1.bookingDate }
                return $0.reference < $1.reference
            }
    }

    func projectedBalanceMinor(accountID: UUID, through date: Date) -> Int64 {
        guard let account = accounts.first(where: {
            $0.id == accountID && $0.includeForecast && !$0.isClosed
        }) else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let posted = transactions
            .filter {
                $0.accountID == accountID
                    && $0.status != .cancelled
                    && $0.status != .expected
                    && $0.bookingDate < calendar.date(byAdding: .day, value: 1, to: today)!
            }
            .reduce(account.openingBalanceMinor) { $0 + $1.amountMinor }
        let pendingExpected = transactions
            .filter {
                $0.accountID == accountID
                    && $0.status == .expected
                    && $0.bookingDate <= date
            }
            .reduce(Int64.zero) { $0 + $1.amountMinor }
        let scheduled = forecastOccurrences(days: max(0, calendar.dateComponents([.day], from: today, to: date).day ?? 0))
            .filter { $0.accountID == accountID && $0.bookingDate <= date }
            .reduce(Int64.zero) { $0 + $1.amountMinor }
        return posted + pendingExpected + scheduled
    }

    func saveScheduledTransaction(_ value: ScheduledTransaction) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveScheduledTransaction(value)
            try load()
            statusText = "Regelmäßiger Vorgang „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveBudget(_ value: FinanceBudget) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveBudget(value)
            try load()
            statusText = "Budget „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func budgetStatusRows(budgetID: UUID, month: Date) -> [BudgetStatusRow] {
        guard let repository else { return [] }
        let components = Calendar.current.dateComponents([.year, .month], from: month)
        guard let year = components.year, let monthValue = components.month else { return [] }
        do {
            let lines = try repository.budgetLines(
                budgetID: budgetID, year: year, month: monthValue
            )
            let linesByCategory = Dictionary(uniqueKeysWithValues: lines.map { ($0.categoryID, $0) })
            let interval = Calendar.current.dateInterval(of: .month, for: month)
            let includedAccounts = Set(
                accounts.filter { $0.includeBudget && !$0.isClosed }.map(\.id)
            )
            return categories
                .filter { $0.isActive && $0.kind != .transfer }
                .map { category in
                    let actual = transactions
                        .filter {
                            $0.categoryID == category.id
                                && includedAccounts.contains($0.accountID)
                                && $0.status != .cancelled
                                && interval?.contains($0.bookingDate) == true
                                && $0.transferID == nil
                        }
                        .reduce(Int64.zero) { $0 + $1.amountMinor }
                    let line = linesByCategory[category.id]
                    return BudgetStatusRow(
                        category: category, line: line,
                        plannedMinor: line?.plannedMinor ?? 0, actualMinor: actual
                    )
                }
                .sorted {
                    if $0.category.kind != $1.category.kind {
                        return $0.category.kind.rawValue < $1.category.kind.rawValue
                    }
                    return $0.category.name.localizedCaseInsensitiveCompare($1.category.name) == .orderedAscending
                }
        } catch {
            present(error)
            return []
        }
    }

    func saveBudgetAmount(
        budgetID: UUID,
        categoryID: UUID,
        month: Date,
        amount: String,
        rolloverPositive: Bool,
        rolloverNegative: Bool
    ) -> Bool {
        guard let repository else { return false }
        let components = Calendar.current.dateComponents([.year, .month], from: month)
        guard let year = components.year, let monthValue = components.month else { return false }
        do {
            let money = try Money(parsing: amount)
            let existing = try repository.budgetLines(
                budgetID: budgetID, year: year, month: monthValue
            ).first { $0.categoryID == categoryID }
            try repository.saveBudgetLine(
                BudgetLine(
                    id: existing?.id ?? UUID(), budgetID: budgetID, categoryID: categoryID,
                    year: year, month: monthValue, plannedMinor: abs(money.minorUnits),
                    rolloverPositive: rolloverPositive, rolloverNegative: rolloverNegative
                )
            )
            statusText = "Budgetwert gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func budgetTransactions(categoryID: UUID, month: Date) -> [FinanceTransaction] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return transactions.filter {
            $0.categoryID == categoryID
                && $0.status != .cancelled
                && $0.transferID == nil
                && interval.contains($0.bookingDate)
        }
    }

    func createPaymentOrder(
        accountID: UUID,
        type: PaymentType,
        recipientName: String,
        iban: String,
        bic: String,
        amount: String,
        executionDate: Date,
        purpose: String,
        endToEndID: String
    ) -> Bool {
        guard let repository, let account = accounts.first(where: { $0.id == accountID }) else {
            return false
        }
        do {
            let money = try Money(parsing: amount, currency: account.currency)
            let normalizedIBAN = IBANValidator.normalized(iban)
            let day = executionDate.formatted(
                .iso8601.year().month().day().dateSeparator(.dash)
            )
            let canonical = [
                accountID.uuidString, type.rawValue, normalizedIBAN,
                String(abs(money.minorUnits)), day,
                purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                endToEndID.trimmingCharacters(in: .whitespacesAndNewlines)
            ].joined(separator: "|")
            let idempotencyKey = SHA256.hash(data: Data(canonical.utf8))
                .map { String(format: "%02x", $0) }.joined()
            let now = Date()
            try repository.createPaymentOrder(
                PaymentOrder(
                    id: UUID(), accountID: accountID, type: type,
                    recipientName: recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
                    iban: normalizedIBAN, bic: bic.trimmingCharacters(in: .whitespacesAndNewlines),
                    amountMinor: abs(money.minorUnits), currency: account.currency,
                    executionDate: executionDate,
                    purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                    endToEndID: endToEndID.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: .draft, idempotencyKey: idempotencyKey,
                    bankReference: "", createdAt: now, updatedAt: now
                )
            )
            try load()
            statusText = "Zahlungsentwurf angelegt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func transitionPayment(_ order: PaymentOrder, to target: PaymentStatus) -> Bool {
        guard let repository else { return false }
        do {
            try repository.transitionPaymentOrder(id: order.id, to: target)
            try load()
            statusText = "Zahlungsstatus: \(target.title)"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func submitPayment(_ order: PaymentOrder, authorizationCode: String) -> Bool {
        guard !authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Für die Simulation ist ein Freigabecode erforderlich. Er wird nicht gespeichert."
            return false
        }
        return transitionPayment(order, to: .submitted)
    }

    func simulatePaymentDecision(_ order: PaymentOrder, outcome: SimulatorOutcome) -> Bool {
        transitionPayment(order, to: outcome.paymentStatus)
    }

    func saveStandingOrder(_ value: StandingOrder) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveStandingOrder(value)
            try load()
            statusText = "Dauerauftrag „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func setStandingOrderStatus(_ value: StandingOrder, to target: StandingOrderStatus) -> Bool {
        guard let repository else { return false }
        do {
            try repository.setStandingOrderStatus(id: value.id, to: target)
            try load()
            statusText = "Dauerauftrag: \(target.title)"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func materializeStandingOrder(_ value: StandingOrder) -> Bool {
        guard let repository else { return false }
        do {
            let payment = try repository.materializeStandingOrder(
                id: value.id, dueDate: value.nextExecutionDate
            )
            try load()
            statusText = "Termin als Zahlungsentwurf vorbereitet: \(payment.recipientName)"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func skipStandingOrder(_ value: StandingOrder) -> Bool {
        guard let repository else { return false }
        do {
            try repository.skipStandingOrder(id: value.id, dueDate: value.nextExecutionDate)
            try load()
            statusText = "Dauerauftragsfälligkeit übersprungen"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func standingOrderRuns(_ value: StandingOrder) -> [StandingOrderRun] {
        guard let repository else { return [] }
        do {
            return try repository.standingOrderRuns(standingOrderID: value.id)
        } catch {
            present(error)
            return []
        }
    }

    func saveSecurity(_ value: Security) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveSecurity(value)
            try load()
            statusText = "Wertpapier „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func recordSecurityTrade(
        accountID: UUID,
        securityID: UUID,
        type: SecurityTradeType,
        date: Date,
        quantity: String,
        price: String,
        fees: String,
        taxes: String,
        note: String
    ) -> Bool {
        guard let repository else { return false }
        do {
            let quantityValue = try SecurityQuantity(parsing: quantity)
            let priceValue = try Money(parsing: price)
            let feeValue = try Money(parsing: fees.isEmpty ? "0" : fees)
            let taxValue = try Money(parsing: taxes.isEmpty ? "0" : taxes)
            switch type {
            case .buy:
                try repository.recordPurchase(
                    accountID: accountID, securityID: securityID, date: date,
                    quantityMicro: quantityValue.microUnits,
                    priceMinor: priceValue.minorUnits,
                    feesMinor: feeValue.minorUnits, taxesMinor: taxValue.minorUnits,
                    note: note
                )
            case .sell:
                try repository.recordSale(
                    accountID: accountID, securityID: securityID, date: date,
                    quantityMicro: quantityValue.microUnits,
                    priceMinor: priceValue.minorUnits,
                    feesMinor: feeValue.minorUnits, taxesMinor: taxValue.minorUnits,
                    note: note
                )
            case .dividend, .fee:
                throw FinanceError.database("Diese Transaktionsart folgt im Ertragsdialog.")
            }
            try load()
            statusText = "\(type.title) gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveSecurityPrice(
        securityID: UUID,
        date: Date,
        price: String,
        source: String = "Manuell"
    ) -> Bool {
        guard let repository,
              let security = securities.first(where: { $0.id == securityID })
        else { return false }
        do {
            let money = try Money(parsing: price, currency: security.currency)
            try repository.saveSecurityPrice(
                securityID: securityID, date: date,
                priceMinor: money.minorUnits, currency: security.currency, source: source
            )
            try load()
            statusText = "Kurs gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveAllocations(
        securityID: UUID,
        values: [(assetClassID: UUID, basisPoints: Int)]
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.replaceAllocations(securityID: securityID, values: values)
            try load()
            statusText = "Vermögensklassen gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func allocations(securityID: UUID) -> [SecurityAllocation] {
        guard let repository else { return [] }
        return (try? repository.allocations(securityID: securityID)) ?? []
    }

    func saveLoan(_ loan: FinanceLoan, initialRate: String) -> Bool {
        guard let repository else { return false }
        do {
            let rate = try Money(parsing: initialRate).minorUnits
            guard (0...100_000).contains(rate) else {
                throw FinanceError.invalidLoanTerms("Der Zinssatz ist ungültig.")
            }
            try repository.saveLoan(loan)
            let existing = try repository.loanInterestRates(loanID: loan.id)
                .first { Calendar.current.isDate($0.effectiveFrom, inSameDayAs: loan.disbursementDate) }
            try repository.saveLoanInterestRate(
                LoanInterestRate(
                    id: existing?.id ?? UUID(), loanID: loan.id,
                    annualBasisPoints: Int(rate), effectiveFrom: loan.disbursementDate,
                    note: "Ausgangszinssatz"
                )
            )
            _ = try repository.loanSchedule(loanID: loan.id)
            try load()
            statusText = "Darlehen „\(loan.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveLoanInterestRate(
        loanID: UUID,
        effectiveFrom: Date,
        annualRate: String,
        note: String
    ) -> Bool {
        guard let repository else { return false }
        do {
            let rate = try Money(parsing: annualRate).minorUnits
            guard (0...100_000).contains(rate) else {
                throw FinanceError.invalidLoanTerms("Der Zinssatz ist ungültig.")
            }
            try repository.saveLoanInterestRate(
                LoanInterestRate(
                    id: UUID(), loanID: loanID, annualBasisPoints: Int(rate),
                    effectiveFrom: effectiveFrom, note: note
                )
            )
            _ = try repository.loanSchedule(loanID: loanID)
            try load()
            statusText = "Zinsänderung gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveLoanExtraPayment(
        loanID: UUID,
        date: Date,
        amount: String,
        note: String
    ) -> Bool {
        guard let repository else { return false }
        do {
            let money = try Money(parsing: amount)
            try repository.saveLoanExtraPayment(
                LoanExtraPayment(
                    id: UUID(), loanID: loanID, paymentDate: date,
                    amountMinor: abs(money.minorUnits), note: note
                )
            )
            try load()
            statusText = "Sondertilgung gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func loanInterestRates(loanID: UUID) -> [LoanInterestRate] {
        guard let repository else { return [] }
        return (try? repository.loanInterestRates(loanID: loanID)) ?? []
    }

    func loanExtraPayments(loanID: UUID) -> [LoanExtraPayment] {
        guard let repository else { return [] }
        return (try? repository.loanExtraPayments(loanID: loanID)) ?? []
    }

    func loanSchedule(loanID: UUID) -> [LoanScheduleEntry] {
        guard let repository else { return [] }
        return (try? repository.loanSchedule(loanID: loanID)) ?? []
    }

    func savePropertyAsset(_ value: PropertyAsset) -> Bool {
        guard let repository else { return false }
        do {
            try repository.savePropertyAsset(value)
            try load()
            statusText = "Vermögenswert „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveAssetValuation(
        assetID: UUID,
        date: Date,
        value: String,
        source: String,
        note: String
    ) -> Bool {
        guard let repository else { return false }
        do {
            let money = try Money(parsing: value)
            try repository.saveAssetValuation(
                AssetValuation(
                    id: UUID(), assetID: assetID, valuationDate: date,
                    valueMinor: abs(money.minorUnits), source: source, note: note
                )
            )
            try load()
            statusText = "Bewertung gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func assetValuations(assetID: UUID) -> [AssetValuation] {
        guard let repository else { return [] }
        return (try? repository.assetValuations(assetID: assetID)) ?? []
    }

    func saveContract(_ value: FinanceContract) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveContract(value)
            try load()
            statusText = "Vertrag „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveInventoryItem(_ value: InventoryItem) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveInventoryItem(value)
            try load()
            statusText = "Inventargegenstand „\(value.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func load() throws {
        guard let repository else { return }
        fileInfo = try repository.financeFileInfo()
        accounts = try repository.accounts()
        accountGroups = try repository.accountGroups()
        categories = try repository.categories()
        transactions = try repository.transactions()
        reportRows = try repository.categoryReport()
        reportTemplates = try repository.reportTemplates()
        categorizationRules = try repository.categorizationRules()
        scheduledTransactions = try repository.scheduledTransactions()
        budgets = try repository.budgets()
        paymentOrders = try repository.paymentOrders()
        standingOrders = try repository.standingOrders()
        payees = try repository.payees()
        tags = try repository.tags()
        securities = try repository.securities()
        assetClasses = try repository.assetClasses()
        portfolioPositions = try repository.portfolioPositions()
        securityTrades = try repository.securityTrades()
        loans = try repository.loans()
        propertyAssetPositions = try repository.propertyAssetPositions()
        contracts = try repository.contracts()
        inventoryItems = try repository.inventoryItems()
        balances = Dictionary(
            uniqueKeysWithValues: try accounts.map { ($0.id, try repository.accountBalanceMinor(account: $0)) }
        )
        if selectedAccountID == nil || !accounts.contains(where: { $0.id == selectedAccountID }) {
            selectedAccountID = accounts.first?.id
        }
    }

    private func seedDemo() throws {
        guard let repository else { return }
        let groups = try repository.accountGroups()
        let bankGroupID = groups.first { $0.name == "Bankkonten" }?.id
        let cashGroupID = groups.first { $0.name == "Bargeld" }?.id
        let assetGroupID = groups.first { $0.name == "Vermögen" }?.id
        let checking = FinanceAccount(
            id: UUID(), name: "Girokonto", institution: "Hausbank", type: .checking,
            currency: "EUR", openingBalanceMinor: 245_000, isHidden: false,
            isClosed: false, sortOrder: 0, shortName: "Giro",
            groupID: bankGroupID, accountNumberMasked: "•••• 4711",
            ownerName: "Privathaushalt", creditLimitMinor: 100_000,
            isOnline: true, syncStatus: .ready
        )
        let savings = FinanceAccount(
            id: UUID(), name: "Tagesgeld", institution: "Hausbank", type: .savings,
            currency: "EUR", openingBalanceMinor: 1_250_000, isHidden: false,
            isClosed: false, sortOrder: 1, groupID: bankGroupID,
            accountNumberMasked: "•••• 0815", ownerName: "Privathaushalt",
            isOnline: true, syncStatus: .ready
        )
        let cash = FinanceAccount(
            id: UUID(), name: "Bargeld", institution: "", type: .cash,
            currency: "EUR", openingBalanceMinor: 12_000, isHidden: false,
            isClosed: false, sortOrder: 2, groupID: cashGroupID
        )
        let depot = FinanceAccount(
            id: UUID(), name: "Wertpapierdepot", institution: "Hausbank",
            type: .investment, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 3,
            groupID: assetGroupID, isOnline: true, includeBudget: false,
            includeForecast: false, syncStatus: .ready
        )
        try repository.saveAccount(checking)
        try repository.saveAccount(savings)
        try repository.saveAccount(cash)
        try repository.saveAccount(depot)
        let values: [(Int, String, String, Int64, String)] = [
            (-1, "Stadtwerke", "Abschlag Strom", -9_850, "Wohnen"),
            (-3, "EDEKA", "Wocheneinkauf", -7_426, "Lebensmittel"),
            (-5, "Arbeitgeber GmbH", "Gehalt Juli", 324_580, "Gehalt"),
            (-7, "Versicherung AG", "Haftpflicht", -4_990, "Versicherungen"),
            (-10, "Deutsche Bahn", "Fahrkarte", -6_490, "Mobilität"),
            (-13, "Buchhandlung", "Fachliteratur", -3_299, "Freizeit")
        ]
        for value in values {
            let date = Calendar.current.date(byAdding: .day, value: value.0, to: Date()) ?? Date()
            let category = try repository.categories().first { $0.name == value.4 }
            try repository.saveTransaction(
                FinanceTransaction(
                    id: UUID(), accountID: checking.id, bookingDate: date, valueDate: date,
                    payee: value.1, purpose: value.2, categoryID: category?.id,
                    amountMinor: value.3, currency: "EUR", status: .booked,
                    memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
                )
            )
        }
        let baseCategories = try repository.categories()
        let foodRoot = baseCategories.first { $0.name == "Lebensmittel" }
        let housingRoot = baseCategories.first { $0.name == "Wohnen" }
        let mobilityRoot = baseCategories.first { $0.name == "Mobilität" }
        if let foodRoot {
            try repository.saveCategory(
                FinanceCategory(
                    id: UUID(), parentID: foodRoot.id, name: "Supermarkt",
                    kind: .expense, color: "green", isActive: true
                )
            )
        }
        if let housingRoot {
            try repository.saveCategory(
                FinanceCategory(
                    id: UUID(), parentID: housingRoot.id, name: "Energie",
                    kind: .expense, color: "orange", isActive: true
                )
            )
        }
        if let mobilityRoot {
            try repository.saveCategory(
                FinanceCategory(
                    id: UUID(), parentID: mobilityRoot.id, name: "ÖPNV & Bahn",
                    kind: .expense, color: "blue", isActive: true
                )
            )
        }
        let categories = try repository.categories()
        let food = categories.first { $0.name == "Supermarkt" }
        if let food {
            try repository.saveCategorizationRule(
                CategorizationRule(
                    id: UUID(), name: "EDEKA → Lebensmittel", priority: 10,
                    isActive: true, stopAfterMatch: true, payeeContains: "EDEKA",
                    purposeContains: "", minimumAmountMinor: nil, maximumAmountMinor: -1,
                    categoryID: food.id
                )
            )
        }
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let rent = categories.first { $0.name == "Wohnen" }
        let salary = categories.first { $0.name == "Gehalt" }
        try repository.saveScheduledTransaction(
            ScheduledTransaction(
                id: UUID(), name: "Monatsmiete", accountID: checking.id,
                payee: "Hausverwaltung", purpose: "Miete", categoryID: rent?.id,
                amountMinor: -98_000, currency: "EUR", nextDueDate: nextMonth,
                endDate: nil, frequency: .monthly, action: .preparePayment,
                reminderDays: 5, isActive: true
            )
        )
        try repository.saveScheduledTransaction(
            ScheduledTransaction(
                id: UUID(), name: "Gehalt", accountID: checking.id,
                payee: "Arbeitgeber GmbH", purpose: "Monatsgehalt", categoryID: salary?.id,
                amountMinor: 324_580, currency: "EUR", nextDueDate: nextMonth,
                endDate: nil, frequency: .monthly, action: .remind,
                reminderDays: 0, isActive: true
            )
        )
        try repository.saveScheduledTransaction(
            ScheduledTransaction(
                id: UUID(), name: "Wochenbudget", accountID: cash.id,
                payee: "Bargeldplanung", purpose: "Wöchentlicher Bedarf", categoryID: food?.id,
                amountMinor: -8_000, currency: "EUR", nextDueDate: nextWeek,
                endDate: calendar.date(byAdding: .month, value: 3, to: Date()),
                frequency: .weekly, action: .remind, reminderDays: 1, isActive: true
            )
        )
        let currentComponents = calendar.dateComponents([.year, .month], from: Date())
        let budget = FinanceBudget(
            id: UUID(), name: "Haushaltsbudget \(currentComponents.year ?? 2026)",
            startYear: currentComponents.year ?? 2026, startMonth: 1,
            currency: "EUR", isActive: true
        )
        try repository.saveBudget(budget)
        let planned: [(String, Int64)] = [
            ("Gehalt", 324_580), ("Wohnen", 120_000), ("Lebensmittel", 45_000),
            ("Mobilität", 18_000), ("Freizeit", 15_000), ("Versicherungen", 12_000)
        ]
        for item in planned {
            guard let category = categories.first(where: { $0.name == item.0 }) else { continue }
            try repository.saveBudgetLine(
                BudgetLine(
                    id: UUID(), budgetID: budget.id, categoryID: category.id,
                    year: currentComponents.year ?? 2026,
                    month: currentComponents.month ?? 1,
                    plannedMinor: item.1, rolloverPositive: item.0 != "Gehalt",
                    rolloverNegative: false
                )
            )
        }
        try seedDemoPayments(repository: repository, account: checking)
        let privateTag = FinanceTag(
            id: UUID(), parentID: nil, name: "Privat", color: "blue",
            description: "Private Lebensführung", isActive: true
        )
        let projectTag = FinanceTag(
            id: UUID(), parentID: nil, name: "Projekt FinanzVerwalter", color: "purple",
            description: "Projektbezogene Ausgaben", isActive: true
        )
        try repository.saveTag(privateTag)
        try repository.saveTag(projectTag)
        let edekaPayee = FinancePayee(
            id: UUID(), canonicalName: "EDEKA Markt", aliases: ["EDEKA", "EDEKA Center"],
            address: "Musterstraße 1, 10115 Berlin", email: "", phone: "",
            iban: "", bic: "", defaultCategoryID: food?.id,
            preferredAccountID: checking.id, note: "Lebensmitteleinkäufe", isActive: true
        )
        try repository.savePayee(edekaPayee)
        for var transaction in try repository.transactions() {
            if transaction.payee == "EDEKA" {
                transaction.payee = edekaPayee.canonicalName
                transaction.payeeID = edekaPayee.id
                transaction.tagIDs = [privateTag.id]
                try repository.saveTransaction(transaction)
            } else if transaction.payee == "Buchhandlung" {
                transaction.tagIDs = [privateTag.id, projectTag.id]
                try repository.saveTransaction(transaction)
            }
        }
        try seedDemoPortfolio(repository: repository, account: depot)
        try seedDemoLoansAndAssets(repository: repository, linkedAccount: checking)
        try seedDemoContractsAndInventory(
            repository: repository, linkedAccount: checking
        )
    }

    private func seedDemoPortfolio(
        repository: SQLiteFinanceStore,
        account: FinanceAccount
    ) throws {
        let etf = Security(
            id: UUID(), name: "MSCI World ETF", shortName: "World ETF",
            isin: "IE00B4L5Y983", wkn: "A0RPWH", ticker: "EUNL",
            type: .etf, currency: "EUR", exchange: "Xetra",
            priceDecimals: 2, allowsShort: false, isActive: true,
            note: "Breit gestreuter Welt-Aktien-ETF"
        )
        let stock = Security(
            id: UUID(), name: "Muster AG", shortName: "Muster",
            isin: "DE0000000001", wkn: "000001", ticker: "MSTR",
            type: .stock, currency: "EUR", exchange: "Xetra",
            priceDecimals: 2, allowsShort: false, isActive: true,
            note: "Demowert"
        )
        try repository.saveSecurity(etf)
        try repository.saveSecurity(stock)
        let classes = try repository.assetClasses()
        if let equity = classes.first(where: { $0.name == "Aktien" }) {
            try repository.replaceAllocations(
                securityID: etf.id, values: [(equity.id, 10_000)]
            )
            try repository.replaceAllocations(
                securityID: stock.id, values: [(equity.id, 10_000)]
            )
        }
        let calendar = Calendar.current
        try repository.recordPurchase(
            accountID: account.id, securityID: etf.id,
            date: calendar.date(byAdding: .month, value: -8, to: Date()) ?? Date(),
            quantityMicro: 12_500_000, priceMinor: 8_450,
            feesMinor: 990, note: "ETF-Sparplan"
        )
        try repository.recordPurchase(
            accountID: account.id, securityID: stock.id,
            date: calendar.date(byAdding: .month, value: -4, to: Date()) ?? Date(),
            quantityMicro: 20_000_000, priceMinor: 4_000,
            feesMinor: 990, note: "Einmalkauf"
        )
        try repository.recordSale(
            accountID: account.id, securityID: stock.id,
            date: calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
            quantityMicro: 5_000_000, priceMinor: 4_800,
            feesMinor: 990, note: "FIFO-Teilverkauf"
        )
        try repository.saveSecurityPrice(
            securityID: etf.id, date: Date(), priceMinor: 9_620,
            currency: "EUR", source: "Demo"
        )
        try repository.saveSecurityPrice(
            securityID: stock.id, date: Date(), priceMinor: 4_550,
            currency: "EUR", source: "Demo"
        )
    }

    private func seedDemoLoansAndAssets(
        repository: SQLiteFinanceStore,
        linkedAccount: FinanceAccount
    ) throws {
        let calendar = Calendar.current
        let disbursement = calendar.date(byAdding: .year, value: -3, to: Date()) ?? Date()
        let firstPayment = calendar.date(byAdding: .month, value: 1, to: disbursement) ?? disbursement
        let loan = FinanceLoan(
            id: UUID(), name: "Immobiliendarlehen", lender: "Hausbank",
            principalMinor: 30_000_000, disbursementDate: disbursement,
            firstPaymentDate: firstPayment,
            fixedRateUntil: calendar.date(byAdding: .year, value: 7, to: Date()),
            termMonths: 300, installmentMinor: 145_000, regularFeeMinor: 0,
            dueDay: calendar.component(.day, from: firstPayment),
            linkedAccountID: linkedAccount.id, currency: "EUR",
            note: "Zinsbindung zehn Jahre", isActive: true
        )
        try repository.saveLoan(loan)
        try repository.saveLoanInterestRate(
            LoanInterestRate(
                id: UUID(), loanID: loan.id, annualBasisPoints: 310,
                effectiveFrom: disbursement, note: "Sollzins"
            )
        )
        let extraDate = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        try repository.saveLoanExtraPayment(
            LoanExtraPayment(
                id: UUID(), loanID: loan.id, paymentDate: extraDate,
                amountMinor: 500_000, note: "Jährliche Sondertilgung"
            )
        )
        let home = PropertyAsset(
            id: UUID(), name: "Eigentumswohnung", type: .realEstate,
            purchaseDate: disbursement, purchaseValueMinor: 42_000_000,
            linkedLoanID: loan.id, location: "Berlin",
            note: "Selbst genutzt", isActive: true
        )
        try repository.savePropertyAsset(home)
        try repository.saveAssetValuation(
            AssetValuation(
                id: UUID(), assetID: home.id, valuationDate: Date(),
                valueMinor: 45_500_000, source: "Eigene Schätzung",
                note: "Verwaltungshilfe, kein Gutachten"
            )
        )
    }

    private func seedDemoContractsAndInventory(
        repository: SQLiteFinanceStore,
        linkedAccount: FinanceAccount
    ) throws {
        let calendar = Calendar.current
        let categories = try repository.categories()
        let insuranceCategory = categories.first { $0.name == "Versicherungen" }
        let housingCategory = categories.first { $0.name == "Wohnen" }
        let insurance = FinanceContract(
            id: UUID(), provider: "Muster Versicherung AG",
            contractNumber: "HV-2026-4711", name: "Hausratversicherung",
            type: .insurance,
            startDate: calendar.date(byAdding: .year, value: -2, to: Date()) ?? Date(),
            initialTermMonths: 12, renewalMonths: 12,
            cancellationNoticeDays: 90, amountMinor: 9_850,
            frequency: .yearly, accountID: linkedAccount.id,
            categoryID: insuranceCategory?.id, reminderDays: 30,
            note: "Jährliche Hauptfälligkeit", isActive: true
        )
        let internet = FinanceContract(
            id: UUID(), provider: "Muster Telekom",
            contractNumber: "DSL-815", name: "Internetanschluss",
            type: .telecommunications,
            startDate: calendar.date(byAdding: .month, value: -14, to: Date()) ?? Date(),
            initialTermMonths: 24, renewalMonths: 1,
            cancellationNoticeDays: 30, amountMinor: 3_499,
            frequency: .monthly, accountID: linkedAccount.id,
            categoryID: housingCategory?.id, reminderDays: 14,
            note: "Monatlich kündbar nach Mindestlaufzeit", isActive: true
        )
        try repository.saveContract(insurance)
        try repository.saveContract(internet)
        try repository.saveInventoryItem(
            InventoryItem(
                id: UUID(), name: "MacBook Pro", category: .electronics,
                room: "Arbeitszimmer",
                purchaseDate: calendar.date(byAdding: .year, value: -1, to: Date()),
                purchasePriceMinor: 249_900, currentValueMinor: 175_000,
                insuranceValueMinor: 249_900, retailer: "Apple",
                serialNumber: "DEMO-MBP-2025",
                warrantyEnd: calendar.date(byAdding: .year, value: 1, to: Date()),
                note: "Demodatensatz", isActive: true
            )
        )
        try repository.saveInventoryItem(
            InventoryItem(
                id: UUID(), name: "Fahrrad", category: .sports,
                room: "Keller",
                purchaseDate: calendar.date(byAdding: .year, value: -3, to: Date()),
                purchasePriceMinor: 120_000, currentValueMinor: 75_000,
                insuranceValueMinor: 120_000, retailer: "Fahrradladen",
                serialNumber: "DEMO-BIKE-4711", warrantyEnd: nil,
                note: "Rahmennummer dokumentiert", isActive: true
            )
        )
    }

    private func seedDemoPayments(
        repository: SQLiteFinanceStore,
        account: FinanceAccount
    ) throws {
        let samples: [(String, String, Int64, PaymentStatus)] = [
            ("Stadtwerke Musterstadt", "Abschlag August", 9_850, .accepted),
            ("Muster Telekom", "Mobilfunkrechnung", 3_499, .unknown)
        ]
        for sample in samples {
            let now = Date()
            let order = PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: sample.0, iban: "DE89370400440532013000",
                bic: "COBADEFFXXX", amountMinor: sample.2, currency: "EUR",
                executionDate: Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now,
                purpose: sample.1, endToEndID: "NOTPROVIDED",
                status: .draft,
                idempotencyKey: UUID().uuidString.lowercased(),
                bankReference: "", createdAt: now, updatedAt: now
            )
            try repository.createPaymentOrder(order)
            try repository.transitionPaymentOrder(id: order.id, to: .initiated)
            try repository.transitionPaymentOrder(id: order.id, to: .challengeReceived)
            try repository.transitionPaymentOrder(id: order.id, to: .awaitingUser)
            try repository.transitionPaymentOrder(id: order.id, to: .submitted)
            try repository.transitionPaymentOrder(id: order.id, to: sample.3)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        statusText = "Fehler"
    }
}
