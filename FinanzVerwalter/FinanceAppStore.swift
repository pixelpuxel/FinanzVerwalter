import CryptoKit
import Foundation

struct AutomaticBackupPolicy: Equatable, Sendable {
    var isEnabled: Bool = true
    var minimumIntervalHours: Int = 24
    var maximumBackupCount: Int = 14
    var maximumAgeDays: Int = 90

    var normalized: Self {
        Self(
            isEnabled: isEnabled,
            minimumIntervalHours: max(1, minimumIntervalHours),
            maximumBackupCount: max(1, maximumBackupCount),
            maximumAgeDays: max(1, maximumAgeDays)
        )
    }
}

enum AutomaticBackupOutcome: Equatable, Sendable {
    case disabled
    case notDue
    case unchanged
    case created(url: URL, removedCount: Int)

    var statusText: String {
        switch self {
        case .disabled: "Autosicherung ist ausgeschaltet"
        case .notDue: "Autosicherung ist noch nicht fällig"
        case .unchanged: "Keine Autosicherung nötig – Finanzdatei unverändert"
        case let .created(url, removedCount):
            removedCount == 0
                ? "Autosicherung erstellt: \(url.lastPathComponent)"
                : "Autosicherung erstellt, \(removedCount) alte Sicherungen entfernt"
        }
    }
}

enum AutomaticBackupPreferences {
    static let enabledKey = "automaticBackupEnabled"
    static let intervalHoursKey = "automaticBackupIntervalHours"
    static let maximumCountKey = "automaticBackupMaximumCount"
    static let maximumAgeDaysKey = "automaticBackupMaximumAgeDays"

    static func load(from defaults: UserDefaults = .standard) -> AutomaticBackupPolicy {
        let standard = AutomaticBackupPolicy()
        return AutomaticBackupPolicy(
            isEnabled: defaults.object(forKey: enabledKey) == nil
                ? standard.isEnabled : defaults.bool(forKey: enabledKey),
            minimumIntervalHours: defaults.object(forKey: intervalHoursKey) == nil
                ? standard.minimumIntervalHours : defaults.integer(forKey: intervalHoursKey),
            maximumBackupCount: defaults.object(forKey: maximumCountKey) == nil
                ? standard.maximumBackupCount : defaults.integer(forKey: maximumCountKey),
            maximumAgeDays: defaults.object(forKey: maximumAgeDaysKey) == nil
                ? standard.maximumAgeDays : defaults.integer(forKey: maximumAgeDaysKey)
        ).normalized
    }
}

enum FinanceFilePreferences {
    static let lastFilePathKey = "lastFinanceFilePath"
    static let recentFilePathsKey = "recentFinanceFilePaths"

    static func lastFileURL(from defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: lastFilePathKey), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func recentFileURLs(
        from defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> [URL] {
        let paths = defaults.stringArray(forKey: recentFilePathsKey) ?? []
        var seen = Set<String>()
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(url.path).inserted,
                  isRegularDirectFile(url, fileManager: fileManager)
            else { return nil }
            return url
        }
    }

    static func record(
        _ url: URL,
        in defaults: UserDefaults = .standard
    ) -> [URL] {
        let normalized = url.standardizedFileURL
        let existing = recentFileURLs(from: defaults).filter {
            $0.path != normalized.path
        }
        let recent = Array(([normalized] + existing).prefix(10))
        defaults.set(normalized.path, forKey: lastFilePathKey)
        defaults.set(recent.map(\.path), forKey: recentFilePathsKey)
        return recent
    }

    static func validatedName(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 120,
              name.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else { return nil }
        return name
    }

    static func isRegularDirectFile(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }
}

enum OpenDataExportPreferences {
    static let safeKeys: [String] = [
        "appearanceMode",
        AutomaticBackupPreferences.enabledKey,
        AutomaticBackupPreferences.intervalHoursKey,
        AutomaticBackupPreferences.maximumCountKey,
        AutomaticBackupPreferences.maximumAgeDaysKey,
        AppShortcutConfiguration.storageKey,
        "registerMiniReportVisibleV1",
        "registerMiniReportDimensionV1",
        "registerSplitViewVisibleV1",
        "registerSecondaryAccountIDV1",
        "registerRowMode",
        "registerVisibleColumnsV1",
        "registerAmountColumnModeV1",
        "registerVisibleColumnsIncludesBalanceV4",
        "savedRegisterViewsV1",
        "registerOpenAccountTabsV1",
        "registerF3FieldV1",
        "registerSortColumnV1",
        "registerSortAscendingV1",
        "registerQuickEntryVisibleV1",
        "combinedRegisterSecondaryAccountIDsV1",
        "combinedRegisterSecondaryForecastV1",
        "combinedRegisterAccountIDsV1",
        "savedCombinedRegisterViewsV1",
        "combinedRegisterSplitVisibleV1",
        "importMatchDateWindowDaysV1",
        "csvImportProfilesV1",
        "bankingMatchDateWindowDaysV1"
    ]

    static func values(from defaults: UserDefaults = .standard) -> [String: String] {
        var result: [String: String] = [:]
        for key in safeKeys {
            guard let value = defaults.object(forKey: key) else { continue }
            switch value {
            case let string as String:
                result[key] = string
            case let number as NSNumber:
                result[key] = number.stringValue
            case let data as Data:
                result[key] = String(data: data, encoding: .utf8)
                    ?? "base64:" + data.base64EncodedString()
            case let array as [Any]:
                if JSONSerialization.isValidJSONObject(array),
                   let data = try? JSONSerialization.data(
                       withJSONObject: array, options: [.sortedKeys]
                   ) {
                    result[key] = String(decoding: data, as: UTF8.self)
                }
            default:
                continue
            }
        }
        return result
    }
}

struct FinanceFileSnapshot: Equatable, Sendable {
    let url: URL
    let byteCount: Int64
    let sha256: String
}

enum FinanceFileSnapshotKind: Sendable {
    case copy
    case archive
    case repair

    var requiredExtension: String {
        switch self {
        case .copy, .repair: "qdata"
        case .archive: "qarchive"
        }
    }

    var permissions: Int {
        switch self {
        case .copy, .repair: 0o600
        case .archive: 0o400
        }
    }
}

enum FinanceFileSnapshotManager {
    static func create(
        repository: SQLiteFinanceStore,
        at rawTarget: URL,
        kind: FinanceFileSnapshotKind,
        fileManager: FileManager = .default
    ) throws -> FinanceFileSnapshot {
        let target = rawTarget.standardizedFileURL
        guard target.pathExtension.lowercased() == kind.requiredExtension else {
            throw FinanceError.database(
                "Das Ziel muss die Endung .\(kind.requiredExtension) besitzen."
            )
        }
        guard target.path != repository.fileURL.standardizedFileURL.path else {
            throw FinanceError.database(
                "Die aktive Finanzdatei darf nicht als eigenes Ziel verwendet werden."
            )
        }
        guard !fileManager.fileExists(atPath: target.path) else {
            throw FinanceError.database("Am gewählten Ziel existiert bereits eine Datei.")
        }
        let parent = target.deletingLastPathComponent()
        let parentValues = try parent.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard parentValues.isDirectory == true,
              parentValues.isSymbolicLink != true else {
            throw FinanceError.database(
                "Der Zielordner ist kein regulärer, direkter Ordner."
            )
        }
        let staged = parent.appendingPathComponent(
            ".finanzverwalter-\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: staged) }
        switch kind {
        case .copy, .archive:
            try repository.backup(to: staged)
        case .repair:
            try repository.repairCopy(to: staged)
        }
        try SQLiteFinanceStore.validateBackup(at: staged)
        try fileManager.setAttributes(
            [.posixPermissions: kind.permissions], ofItemAtPath: staged.path
        )
        let stagedSnapshot = try snapshot(for: staged, fileManager: fileManager)
        try fileManager.moveItem(at: staged, to: target)
        let finalSnapshot = try snapshot(for: target, fileManager: fileManager)
        guard stagedSnapshot.byteCount == finalSnapshot.byteCount,
              stagedSnapshot.sha256 == finalSnapshot.sha256 else {
            try? fileManager.removeItem(at: target)
            throw FinanceError.database(
                "Die fertige Datei stimmt nicht mit der geprüften Zwischenkopie überein."
            )
        }
        return finalSnapshot
    }

    static func snapshot(
        for url: URL,
        fileManager: FileManager = .default
    ) throws -> FinanceFileSnapshot {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw FinanceError.database("Die erzeugte Datei ist keine reguläre Datei.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
            byteCount += Int64(data.count)
        }
        guard byteCount == Int64(values.fileSize ?? -1) else {
            throw FinanceError.database("Die Dateigröße änderte sich während der Prüfung.")
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return FinanceFileSnapshot(url: url, byteCount: byteCount, sha256: digest)
    }
}

enum AutomaticBackupManager {
    static let filePrefix = "FinanzVerwalter-Autosicherung-"

    static func defaultDirectory(for financeFileURL: URL) -> URL {
        financeFileURL.deletingLastPathComponent()
            .appendingPathComponent("Sicherungen", isDirectory: true)
    }

    static func backups(
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> [(url: URL, modifiedAt: Date)] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            guard url.lastPathComponent.hasPrefix(filePrefix),
                  url.pathExtension.lowercased() == "qbackup"
            else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, let date = values.contentModificationDate else {
                return nil
            }
            return (url, date)
        }.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }
    }

    static func sourceModificationDate(
        for financeFileURL: URL,
        fileManager: FileManager = .default
    ) -> Date? {
        [financeFileURL.path, financeFileURL.path + "-wal", financeFileURL.path + "-shm"]
            .compactMap { path -> Date? in
                guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
                    return nil
                }
                return attributes[.modificationDate] as? Date
            }
            .max()
    }

    static func perform(
        repository: SQLiteFinanceStore,
        directory: URL? = nil,
        policy rawPolicy: AutomaticBackupPolicy,
        now: Date = Date(),
        force: Bool = false,
        sourceModifiedAt explicitSourceDate: Date? = nil,
        fileManager: FileManager = .default
    ) throws -> AutomaticBackupOutcome {
        let policy = rawPolicy.normalized
        guard policy.isEnabled || force else { return .disabled }
        let directory = directory ?? defaultDirectory(for: repository.fileURL)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let existing = try backups(in: directory, fileManager: fileManager)
        if !force, let newest = existing.first {
            let interval = TimeInterval(policy.minimumIntervalHours * 3_600)
            guard now.timeIntervalSince(newest.modifiedAt) >= interval else {
                return .notDue
            }
            let sourceDate = explicitSourceDate
                ?? sourceModificationDate(for: repository.fileURL, fileManager: fileManager)
            guard sourceDate == nil || sourceDate! > newest.modifiedAt else {
                return .unchanged
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let name = "\(filePrefix)\(formatter.string(from: now))-\(UUID().uuidString.prefix(8)).qbackup"
        let finalURL = directory.appendingPathComponent(name)
        let stagedURL = directory.appendingPathComponent(".\(UUID().uuidString).qbackup.tmp")
        defer { try? fileManager.removeItem(at: stagedURL) }
        try repository.backup(to: stagedURL)
        try SQLiteFinanceStore.validateBackup(at: stagedURL)
        try fileManager.moveItem(at: stagedURL, to: finalURL)
        try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: finalURL.path)

        let all = try backups(in: directory, fileManager: fileManager)
        let ageLimit = now.addingTimeInterval(-TimeInterval(policy.maximumAgeDays * 86_400))
        var removedCount = 0
        for (index, backup) in all.enumerated() where
            index >= policy.maximumBackupCount || backup.modifiedAt < ageLimit {
            try fileManager.removeItem(at: backup.url)
            removedCount += 1
        }
        return .created(url: finalURL, removedCount: removedCount)
    }
}

struct PayeeSmartFillSuggestion: Identifiable, Equatable, Sendable {
    let payee: FinancePayee
    let matchedAlias: String?
    let usageCount: Int
    let hasPrefixMatch: Bool

    var id: UUID { payee.id }
}

enum PayeeSmartFill {
    static func suggestions(
        payees: [FinancePayee],
        transactions: [FinanceTransaction],
        query: String
    ) -> [PayeeSmartFillSuggestion] {
        let needle = normalized(query)
        let usageCounts = Dictionary(
            grouping: transactions.compactMap(\.payeeID),
            by: { $0 }
        ).mapValues(\.count)

        return payees.compactMap { payee in
            guard payee.isActive else { return nil }
            let canonical = normalized(payee.canonicalName)
            let aliases = payee.aliases.sorted {
                normalized($0) < normalized($1)
            }
            let matchingAliases = aliases.filter {
                needle.isEmpty || normalized($0).contains(needle)
            }
            let canonicalMatches = needle.isEmpty || canonical.contains(needle)
            guard canonicalMatches || !matchingAliases.isEmpty else { return nil }
            let prefixAliases = matchingAliases.filter {
                normalized($0).hasPrefix(needle)
            }
            return PayeeSmartFillSuggestion(
                payee: payee,
                matchedAlias: canonicalMatches
                    ? nil : (prefixAliases.first ?? matchingAliases.first),
                usageCount: usageCounts[payee.id, default: 0],
                hasPrefixMatch: needle.isEmpty
                    || canonical.hasPrefix(needle)
                    || !prefixAliases.isEmpty
            )
        }.sorted { left, right in
            if left.hasPrefixMatch != right.hasPrefixMatch {
                return left.hasPrefixMatch
            }
            if left.usageCount != right.usageCount {
                return left.usageCount > right.usageCount
            }
            let leftName = normalized(left.payee.canonicalName)
            let rightName = normalized(right.payee.canonicalName)
            if leftName != rightName { return leftName < rightName }
            return left.payee.id.uuidString < right.payee.id.uuidString
        }
    }

    private static func normalized(_ value: String) -> String {
        let locale = Locale(identifier: "de_DE")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }
}

@MainActor
final class FinanceAppStore: ObservableObject {
    @Published private(set) var fileInfo: FinanceFileInfo?
    @Published private(set) var accounts: [FinanceAccount] = []
    @Published private(set) var accountGroups: [AccountGroup] = []
    @Published private(set) var categories: [FinanceCategory] = []
    @Published private(set) var vatCodes: [VATCode] = []
    @Published private(set) var transactions: [FinanceTransaction] = []
    @Published private(set) var balances: [UUID: Int64] = [:]
    @Published private(set) var reportRows: [CategoryReportRow] = []
    @Published private(set) var reportTemplates: [SavedReportTemplate] = []
    @Published private(set) var transactionTemplates: [TransactionTemplate] = []
    @Published private(set) var categorizationRules: [CategorizationRule] = []
    @Published private(set) var latestRuleUndo: RuleUndoSummary?
    @Published private(set) var latestTransactionUndo: TransactionUndoSummary?
    @Published private(set) var bankingConnections: [BankingConnection] = []
    @Published private(set) var bankingMappings: [BankingAccountMapping] = []
    @Published private(set) var bankingSyncRuns: [BankingSyncRun] = []
    @Published private(set) var bankingRemoteOrders: [BankingRemoteStandingOrder] = []
    @Published private(set) var bankingProgressText = ""
    @Published private(set) var scheduledTransactions: [ScheduledTransaction] = []
    @Published private(set) var scheduledTransactionExceptions: [ScheduledTransactionException] = []
    @Published private(set) var scheduledTransactionRevisions: [ScheduledTransactionRevision] = []
    @Published private(set) var forecastScenarios: [ForecastScenario] = []
    @Published private(set) var forecastScenarioEntries: [ForecastScenarioEntry] = []
    @Published private(set) var budgets: [FinanceBudget] = []
    @Published private(set) var paymentOrders: [PaymentOrder] = []
    @Published private(set) var directDebitOrders: [DirectDebitOrder] = []
    @Published private(set) var paymentBatches: [PaymentBatch] = []
    @Published private(set) var paymentStatusReports: [PaymentStatusReportSummary] = []
    @Published private(set) var paymentInstructionImports: [PaymentInstructionImportSummary] = []
    @Published private(set) var standingOrders: [StandingOrder] = []
    @Published private(set) var payees: [FinancePayee] = []
    @Published private(set) var payeeBankAccounts: [FinancePayeeBankAccount] = []
    @Published private(set) var sepaMandates: [FinanceSEPAMandate] = []
    @Published private(set) var tags: [FinanceTag] = []
    @Published private(set) var securities: [Security] = []
    @Published private(set) var assetClasses: [AssetClass] = []
    @Published private(set) var securityAllocations: [SecurityAllocation] = []
    @Published private(set) var securityPrices: [SecurityPrice] = []
    @Published private(set) var portfolioPositions: [PortfolioPosition] = []
    @Published private(set) var securityTrades: [SecurityTrade] = []
    @Published private(set) var loans: [FinanceLoan] = []
    @Published private(set) var loanPaymentMatches: [LoanPaymentMatch] = []
    @Published private(set) var propertyAssetPositions: [PropertyAssetPosition] = []
    @Published private(set) var contracts: [FinanceContract] = []
    @Published private(set) var inventoryItems: [InventoryItem] = []
    @Published private(set) var taxPeople: [TaxPerson] = []
    @Published private(set) var taxAllowanceRules: [TaxAllowanceRule] = []
    @Published private(set) var taxAllowanceOrders: [TaxAllowanceOrder] = []
    @Published private(set) var taxAllowanceUsages: [TaxAllowanceUsage] = []
    @Published var selectedAccountID: UUID?
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var statusText = "Bereit"
    @Published var isBusy = false
    @Published private(set) var automaticBackupStatusText = "Autosicherung noch nicht geprüft"
    @Published private(set) var registerSearchIndex = RegisterSearchIndex.empty
    @Published private(set) var recentFinanceFileURLs: [URL] = []

    private var repository: SQLiteFinanceStore?
    private var registerSearchIndexTask: Task<Void, Never>?
    private var registerSearchIndexGeneration = UUID()
    private let preferences: UserDefaults

    init(
        repository: SQLiteFinanceStore? = nil,
        preferences: UserDefaults = .standard
    ) {
        self.preferences = preferences
        recentFinanceFileURLs = FinanceFilePreferences.recentFileURLs(
            from: preferences
        )
        let arguments = ProcessInfo.processInfo.arguments
        let isReferenceDemo = arguments.contains("-reference-demo")
        let isDemo = arguments.contains("-demo") || isReferenceDemo
        let shouldRunAutomaticBackup = repository == nil
            && !isDemo
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        do {
            if let repository {
                self.repository = repository
            } else if isDemo {
                let demoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        (isReferenceDemo
                            ? "finanzverwalter-reference-demo-"
                            : "finanzverwalter-ui-demo-")
                            + "\(ProcessInfo.processInfo.processIdentifier).qdata"
                    )
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
                let remembered = FinanceFilePreferences.lastFileURL(
                    from: preferences
                )
                let target = remembered.flatMap { url in
                    FinanceFilePreferences.isRegularDirectFile(url) ? url : nil
                } ?? SQLiteFinanceStore.defaultFileURL()
                self.repository = try SQLiteFinanceStore(fileURL: target)
            }
            try load()
            if isDemo, accounts.isEmpty {
                if isReferenceDemo {
                    _ = try seedReferenceRegisterDataset()
                } else {
                    try seedDemo()
                }
                try load()
            }
            if shouldRunAutomaticBackup {
                _ = createAutomaticBackup()
            }
            if repository == nil, !isDemo,
               ProcessInfo.processInfo.environment[
                   "XCTestConfigurationFilePath"
               ] == nil,
               let fileURL = self.repository?.fileURL {
                recentFinanceFileURLs = FinanceFilePreferences.record(
                    fileURL, in: preferences
                )
            }
        } catch {
            self.repository = nil
            errorMessage = error.localizedDescription
            statusText = "Finanzdatei konnte nicht geöffnet werden"
        }
    }

    var currentFinanceFileURL: URL? { repository?.fileURL }

    @discardableResult
    func openFinanceFile(at rawURL: URL) -> Bool {
        let url = rawURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "qdata" else {
            errorMessage = "Finanzdateien müssen die Endung .qdata besitzen."
            return false
        }
        do {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw FinanceError.database(
                    "Die gewählte Finanzdatei ist keine reguläre, direkte Datei."
                )
            }
            if repository?.fileURL.standardizedFileURL.path == url.path {
                try load()
                errorMessage = nil
                statusText = "Finanzdatei aktualisiert: \(url.lastPathComponent)"
                return true
            }
            let candidate = try SQLiteFinanceStore(fileURL: url)
            return switchFinanceFile(
                to: candidate,
                successText: "Finanzdatei geöffnet: \(url.lastPathComponent)"
            )
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func createFinanceFile(at rawURL: URL, name rawName: String) -> Bool {
        let url = rawURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "qdata" else {
            errorMessage = "Neue Finanzdateien müssen die Endung .qdata besitzen."
            return false
        }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Am gewählten Ort existiert bereits eine Datei."
            return false
        }
        guard let name = FinanceFilePreferences.validatedName(rawName) else {
            errorMessage = "Der Name der Finanzdatei fehlt, enthält Steuerzeichen oder ist länger als 120 Zeichen."
            return false
        }
        do {
            let parentValues = try url.deletingLastPathComponent().resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard parentValues.isDirectory == true,
                  parentValues.isSymbolicLink != true else {
                throw FinanceError.database(
                    "Der Zielordner ist kein regulärer, direkter Ordner."
                )
            }
            let candidate = try SQLiteFinanceStore(fileURL: url)
            do {
                try candidate.renameFinanceFile(name)
                return switchFinanceFile(
                    to: candidate,
                    successText: "Neue Finanzdatei angelegt: \(url.lastPathComponent)"
                )
            } catch {
                candidate.close()
                throw error
            }
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func createFinanceFileCopy(at url: URL) -> FinanceFileSnapshot? {
        guard let repository else { return nil }
        do {
            let snapshot = try FinanceFileSnapshotManager.create(
                repository: repository, at: url, kind: .copy
            )
            errorMessage = nil
            statusText = "Geprüfte Kopie erstellt: \(snapshot.url.lastPathComponent) · SHA-256 \(snapshot.sha256.prefix(12))…"
            return snapshot
        } catch {
            present(error)
            return nil
        }
    }

    @discardableResult
    func archiveFinanceFile(at url: URL) -> FinanceFileSnapshot? {
        guard let repository else { return nil }
        do {
            let snapshot = try FinanceFileSnapshotManager.create(
                repository: repository, at: url, kind: .archive
            )
            errorMessage = nil
            statusText = "Schreibgeschütztes Archiv erstellt: \(snapshot.url.lastPathComponent) · SHA-256 \(snapshot.sha256.prefix(12))…"
            return snapshot
        } catch {
            present(error)
            return nil
        }
    }

    @discardableResult
    func createRepairCopy(at url: URL) -> FinanceFileSnapshot? {
        guard let repository else { return nil }
        do {
            let snapshot = try FinanceFileSnapshotManager.create(
                repository: repository, at: url, kind: .repair
            )
            errorMessage = nil
            statusText = "Geprüfte Reparaturkopie erstellt: \(snapshot.url.lastPathComponent) · SHA-256 \(snapshot.sha256.prefix(12))…"
            return snapshot
        } catch {
            present(error)
            return nil
        }
    }

    @discardableResult
    func exportOpenDataArchive(at url: URL) -> OpenDataArchiveSummary? {
        guard let repository else { return nil }
        do {
            let summary = try repository.exportOpenDataArchive(
                to: url,
                settings: OpenDataExportPreferences.values(from: preferences)
            )
            errorMessage = nil
            statusText = "Offenes Datenarchiv exportiert: \(summary.tableCount) Tabellen · \(summary.rowCount) Zeilen · \(summary.attachmentCount) Anhänge"
            return summary
        } catch {
            present(error)
            return nil
        }
    }

    /// Baut aus dem dokumentierten Gesamtdatenarchiv eine unabhängige
    /// Finanzdatei auf. Die enthaltenen Oberflächeneinstellungen werden aus
    /// Sicherheitsgründen nur gemeldet und niemals ungefragt übernommen.
    @discardableResult
    func importOpenDataArchive(
        from archiveURL: URL,
        to financeFileURL: URL,
        openAfterImport: Bool = true
    ) -> OpenDataArchiveImportSummary? {
        guard let repository else { return nil }
        do {
            let summary = try repository.importOpenDataArchive(
                from: archiveURL,
                to: financeFileURL
            )
            errorMessage = nil
            if openAfterImport {
                guard openFinanceFile(at: summary.financeFileURL) else {
                    return summary
                }
                statusText = "Datenarchiv vollständig importiert und geöffnet: \(summary.tableCount) Tabellen · \(summary.rowCount) Zeilen · \(summary.attachmentCount) Anhänge"
            } else {
                statusText = "Datenarchiv vollständig importiert: \(summary.financeFileURL.lastPathComponent) · \(summary.rowCount) Zeilen"
            }
            return summary
        } catch {
            present(error)
            return nil
        }
    }

    @discardableResult
    func closeFinanceFile() -> Bool {
        guard let repository else { return true }
        guard createAutomaticBackup(force: true) != nil else { return false }
        repository.close()
        self.repository = nil
        clearLoadedState()
        errorMessage = nil
        statusText = "Keine Finanzdatei geöffnet"
        NotificationCenter.default.post(name: .financeFileDidChange, object: nil)
        return true
    }

    private func switchFinanceFile(
        to candidate: SQLiteFinanceStore,
        successText: String
    ) -> Bool {
        let previous = repository
        if previous != nil, createAutomaticBackup(force: true) == nil {
            candidate.close()
            return false
        }
        repository = candidate
        selectedAccountID = nil
        searchText = ""
        do {
            try load()
            previous?.close()
            recentFinanceFileURLs = FinanceFilePreferences.record(
                candidate.fileURL, in: preferences
            )
            errorMessage = nil
            statusText = successText
            NotificationCenter.default.post(name: .financeFileDidChange, object: nil)
            return true
        } catch {
            repository = previous
            candidate.close()
            if previous != nil {
                try? load()
            } else {
                clearLoadedState()
            }
            present(error)
            return false
        }
    }

    private func clearLoadedState() {
        registerSearchIndexTask?.cancel()
        registerSearchIndexGeneration = UUID()
        fileInfo = nil
        accounts = []
        accountGroups = []
        categories = []
        vatCodes = []
        transactions = []
        balances = [:]
        reportRows = []
        reportTemplates = []
        transactionTemplates = []
        categorizationRules = []
        latestRuleUndo = nil
        latestTransactionUndo = nil
        bankingConnections = []
        bankingMappings = []
        bankingSyncRuns = []
        bankingRemoteOrders = []
        bankingProgressText = ""
        scheduledTransactions = []
        scheduledTransactionExceptions = []
        scheduledTransactionRevisions = []
        forecastScenarios = []
        forecastScenarioEntries = []
        budgets = []
        paymentOrders = []
        directDebitOrders = []
        paymentBatches = []
        paymentStatusReports = []
        paymentInstructionImports = []
        standingOrders = []
        payees = []
        payeeBankAccounts = []
        sepaMandates = []
        tags = []
        securities = []
        assetClasses = []
        securityAllocations = []
        securityPrices = []
        portfolioPositions = []
        securityTrades = []
        loans = []
        loanPaymentMatches = []
        propertyAssetPositions = []
        contracts = []
        inventoryItems = []
        taxPeople = []
        taxAllowanceRules = []
        taxAllowanceOrders = []
        taxAllowanceUsages = []
        selectedAccountID = nil
        searchText = ""
        registerSearchIndex = .empty
    }

    var selectedAccount: FinanceAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    var filteredTransactions: [FinanceTransaction] {
        let query = RegisterSearchQuery(searchText)
        if registerSearchIndex.documents.count != transactions.count {
            return transactions.filter { transaction in
                (selectedAccountID == nil || transaction.accountID == selectedAccountID)
                    && matchesRegisterSearch(
                        transaction,
                        query: query,
                        runningBalanceMinor: nil
                    )
            }
        }
        let matchingIDs = registerSearchIndex.matchingTransactionIDs(query)
        return transactions.filter { transaction in
            (selectedAccountID == nil || transaction.accountID == selectedAccountID)
                && matchingIDs.contains(transaction.id)
        }
    }

    func matchesRegisterSearch(
        _ transaction: FinanceTransaction,
        query: RegisterSearchQuery,
        runningBalanceMinor: Int64?,
        indexedMatches: Set<UUID>? = nil
    ) -> Bool {
        guard !query.isEmpty else { return true }
        if registerSearchIndex.documents[transaction.id] != nil {
            return indexedMatches?.contains(transaction.id)
                ?? registerSearchIndex.matches(
                    transactionID: transaction.id,
                    query: query
                )
        }
        let allTagIDs = transaction.tagIDs
            + transaction.splits.flatMap(\.tagIDs)
        let tagPaths = allTagIDs.map { tagPath($0) }
        let account = accounts.first { $0.id == transaction.accountID }
        let groupName = account?.groupID.flatMap { groupID in
            accountGroups.first { $0.id == groupID }?.name
        }
        return RegisterSearchIndex.document(
            transaction: transaction,
            accountName: account.map {
                RegisterSearchIndex.accountSearchText(
                    $0,
                    groupName: groupName
                )
            } ?? accountName(transaction.accountID),
            categoryPath: transactionCategoryPath(transaction),
            tagPaths: tagPaths,
            runningBalanceMinor: runningBalanceMinor
        ).matches(query)
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
        let reportTransactions = query.includeForecast == true
            ? transactions + forecastOccurrences(days: 365)
            : transactions
        return TransactionReportEngine.snapshot(
            query: query,
            transactions: reportTransactions,
            accounts: accounts,
            categories: categories,
            tags: tags
        )
    }

    func accountBalanceReport(
        _ query: AccountBalanceReportQuery,
        calendar: Calendar = .current
    ) -> AccountBalanceReportSnapshot {
        AccountBalanceReportEngine.snapshot(
            query: query,
            accounts: accounts,
            accountGroups: accountGroups,
            transactions: transactions,
            calendar: calendar
        )
    }

    func vatReport(_ query: VATReportQuery) -> VATReportSnapshot {
        VATReportEngine.snapshot(
            query: query, transactions: transactions, accounts: accounts,
            categories: categories, vatCodes: vatCodes
        )
    }

    func loanReport(_ query: LoanReportQuery) -> LoanReportSnapshot {
        LoanReportEngine.snapshot(
            query: query, loans: loans,
            schedulesByLoanID: Dictionary(uniqueKeysWithValues: loans.map {
                ($0.id, loanSchedule(loanID: $0.id))
            }),
            matches: loanPaymentMatches
        )
    }

    func periodComparisonReport(
        _ query: PeriodComparisonQuery
    ) -> PeriodComparisonSnapshot {
        PeriodComparisonEngine.snapshot(
            query: query, transactions: transactions, accounts: accounts,
            categories: categories, tags: tags
        )
    }

    func budgetReport(
        budgetID: UUID,
        query: BudgetReportQuery,
        calendar: Calendar = .current
    ) -> BudgetReportSnapshot? {
        guard let repository,
              let budget = budgets.first(where: { $0.id == budgetID })
        else { return nil }
        do {
            let lines = try repository.budgetLines(budgetID: budgetID)
            return BudgetReportEngine.snapshot(
                budget: budget, query: query, lines: lines,
                transactions: transactions, accounts: accounts,
                categories: categories, tags: tags, calendar: calendar
            )
        } catch {
            present(error)
            return nil
        }
    }

    func portfolioReport(_ query: PortfolioReportQuery) -> PortfolioReportSnapshot {
        let allocations = Dictionary(grouping: securityAllocations, by: \.securityID)
        return PortfolioReportEngine.snapshot(
            query: query, positions: portfolioPositions,
            trades: securityTrades, accounts: accounts,
            securities: securities, allocationsBySecurityID: allocations,
            assetClasses: assetClasses, prices: securityPrices
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

    func saveTransactionTemplate(name: String, from transaction: FinanceTransaction) -> Bool {
        guard let repository else { return false }
        guard transaction.transferID == nil else {
            errorMessage = "Umbuchungen können nur als zusammengehöriges Buchungspaar wiederverwendet werden und sind deshalb keine Einzelvorlage."
            return false
        }
        do {
            let template = TransactionTemplate(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                transaction: transaction
            )
            try repository.saveTransactionTemplate(template)
            transactionTemplates = try repository.transactionTemplates()
            statusText = "Buchungsvorlage „\(template.name)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteTransactionTemplate(_ template: TransactionTemplate) {
        guard let repository else { return }
        do {
            try repository.deleteTransactionTemplate(id: template.id)
            transactionTemplates = try repository.transactionTemplates()
            statusText = "Buchungsvorlage gelöscht"
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

    func tagPath(_ id: UUID?) -> String {
        guard let id, let tag = tags.first(where: { $0.id == id }) else {
            return "Ohne Klasse/Tag"
        }
        var names = [tag.name]
        var parentID = tag.parentID
        var visited = Set([tag.id])
        while let currentID = parentID,
              visited.insert(currentID).inserted,
              let parent = tags.first(where: { $0.id == currentID }) {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }
        return names.joined(separator: " › ")
    }

    var tagsByPath: [FinanceTag] {
        tags.sorted {
            tagPath($0.id).localizedCaseInsensitiveCompare(tagPath($1.id))
                == .orderedAscending
        }
    }

    func payeeSuggestions(for query: String) -> [FinancePayee] {
        payeeSmartFillSuggestions(for: query).map(\.payee)
    }

    func payeeSmartFillSuggestions(
        for query: String
    ) -> [PayeeSmartFillSuggestion] {
        PayeeSmartFill.suggestions(
            payees: payees,
            transactions: transactions,
            query: query
        )
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

    func saveVATCode(_ value: VATCode) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveVATCode(value)
            try load()
            statusText = "MwSt.-Schlüssel „\(value.name)“ gespeichert"
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

    func savePayeeBankAccount(_ value: FinancePayeeBankAccount) -> Bool {
        guard let repository else { return false }
        do {
            try repository.savePayeeBankAccount(value)
            try load()
            statusText = "Bankverbindung „\(value.label)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveSEPAMandate(_ value: FinanceSEPAMandate) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveSEPAMandate(value)
            try load()
            statusText = "Mandat „\(value.reference)“ gespeichert"
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
        flag: TransactionFlag? = nil,
        reference: String = "",
        payeeID: UUID? = nil,
        tagIDs: [UUID] = [],
        creditorID: String = "",
        mandateReference: String = "",
        vatCodeID: UUID? = nil,
        vatMode: VATMode = .none,
        netMinor: Int64 = 0,
        taxMinor: Int64 = 0,
        originalAmount: String = "",
        originalCurrency: String = ""
    ) -> Bool {
        guard let repository else { return false }
        do {
            guard let account = accounts.first(where: { $0.id == accountID }) else {
                throw FinanceError.missingAccount
            }
            let normalizedCreditorID = SEPACreditorIDValidator.normalized(
                creditorID
            )
            if !normalizedCreditorID.isEmpty,
               !SEPACreditorIDValidator.isValid(normalizedCreditorID) {
                throw FinanceError.database(
                    "Die SEPA-Gläubiger-ID ist ungültig."
                )
            }
            let normalizedMandate = mandateReference.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if normalizedMandate.count > 35 {
                throw FinanceError.database(
                    "Die Mandatsreferenz darf höchstens 35 Zeichen lang sein."
                )
            }
            let money = try Money(evaluating: amount, currency: account.currency)
            let normalizedOriginalCurrency = originalCurrency
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let originalMoney: Money?
            let exchangeRate: ExchangeRate?
            if originalAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               normalizedOriginalCurrency.isEmpty {
                originalMoney = nil
                exchangeRate = nil
            } else {
                guard normalizedOriginalCurrency.count == 3,
                      normalizedOriginalCurrency != account.currency.uppercased() else {
                    throw FinanceError.invalidExchangeRate(
                        "Bitte gib eine von der Kontowährung abweichende dreistellige ISO-Währung an."
                    )
                }
                let parsedInput = try Money(
                    evaluating: originalAmount,
                    currency: normalizedOriginalCurrency
                )
                let parsed = Money(
                    minorUnits: money.minorUnits < 0
                        ? -abs(parsedInput.minorUnits) : abs(parsedInput.minorUnits),
                    currency: parsedInput.currency
                )
                originalMoney = parsed
                exchangeRate = try ExchangeRate.derived(
                    originalMinor: parsed.minorUnits,
                    originalCurrency: parsed.currency,
                    bookedMinor: money.minorUnits,
                    bookedCurrency: money.currency
                )
            }
            let existing = id.flatMap { transactionID in
                transactions.first { $0.id == transactionID }
            }
            let value = FinanceTransaction(
                id: id ?? UUID(), accountID: accountID, bookingDate: date, valueDate: date,
                payee: payee.trimmingCharacters(in: .whitespacesAndNewlines),
                purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryID: categoryID, amountMinor: money.minorUnits, currency: money.currency,
                status: status, memo: memo, reference: reference,
                transferID: nil, importFingerprint: nil, splits: [],
                payeeID: payeeID, tagIDs: tagIDs,
                vatCodeID: vatCodeID, vatMode: vatMode,
                netMinor: netMinor, taxMinor: taxMinor,
                origin: existing?.origin ?? .manual,
                externalProvider: existing?.externalProvider ?? "",
                externalTransactionID: existing?.externalTransactionID ?? "",
                counterpartyIBAN: existing?.counterpartyIBAN ?? "",
                endToEndID: existing?.endToEndID ?? "",
                mandateReference: normalizedMandate,
                duplicateFingerprint: existing?.duplicateFingerprint ?? "",
                bankBalanceAfterMinor: existing?.bankBalanceAfterMinor,
                counterpartyBIC: existing?.counterpartyBIC ?? "",
                creditorID: normalizedCreditorID,
                bookingText: existing?.bookingText ?? "",
                originalAmountMinor: originalMoney?.minorUnits,
                originalCurrency: originalMoney?.currency ?? "",
                exchangeRateScaled: exchangeRate?.scaledValue,
                flag: flag
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

    func saveQuickEntry(_ value: RegisterQuickEntryResolved) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveTransaction(value.transaction())
            try load()
            statusText = "Schnellbuchung gespeichert"
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

    func bulkAssignOrganization(
        transactionIDs: Set<UUID>,
        updateCategory: Bool,
        categoryID: UUID?,
        replacementTagIDs: Set<UUID>?,
        updateFlag: Bool = false,
        flag: TransactionFlag? = nil
    ) -> Bool {
        guard let repository else { return false }
        do {
            let result = try repository.bulkUpdateTransactionOrganization(
                ids: transactionIDs,
                updateCategory: updateCategory,
                categoryID: categoryID,
                replacementTagIDs: replacementTagIDs,
                updateFlag: updateFlag,
                flag: flag
            )
            try load()
            statusText = "\(result.updatedCount) Buchungen organisiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteTransaction(_ value: FinanceTransaction) {
        _ = deleteTransactions([value])
    }

    @discardableResult
    func moveTransaction(
        _ value: FinanceTransaction,
        toAccountID destinationID: UUID
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.moveTransaction(
                id: value.id,
                toAccountID: destinationID
            )
            try load()
            statusText = "Buchung nach „\(accountName(destinationID))“ verschoben"
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func deleteTransactions(_ values: [FinanceTransaction]) -> Bool {
        guard let repository else { return false }
        do {
            try repository.deleteTransactions(ids: Set(values.map(\.id)))
            try load()
            statusText = values.count == 1
                ? "Buchung gelöscht"
                : "\(values.count) Buchungen gelöscht"
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func undoLatestTransactionMutation() -> Bool {
        guard let repository, let latestTransactionUndo else { return false }
        do {
            let count = try repository.undoTransactionMutation(
                id: latestTransactionUndo.id
            )
            try load()
            statusText = count == 1
                ? "Letzte Buchungsänderung rückgängig gemacht"
                : "Letzte Änderung an \(count) Buchungen rückgängig gemacht"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func attachments(
        entityType: AttachmentEntityType,
        entityID: UUID
    ) -> [FinanceAttachment] {
        guard let repository else { return [] }
        do {
            return try repository.attachments(
                entityType: entityType, entityID: entityID
            )
        } catch {
            present(error)
            return []
        }
    }

    @discardableResult
    func addAttachment(
        from url: URL,
        to entityType: AttachmentEntityType,
        entityID: UUID
    ) -> Bool {
        guard let repository else { return false }
        do {
            let attachment = try repository.addAttachment(
                from: url, to: entityType, entityID: entityID
            )
            statusText = "Anhang „\(attachment.fileName)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func removeAttachment(_ attachment: FinanceAttachment) -> Bool {
        guard let repository else { return false }
        do {
            try repository.removeAttachment(id: attachment.id)
            statusText = "Anhang „\(attachment.fileName)“ entfernt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func attachmentPreviewURL(_ attachment: FinanceAttachment) -> URL? {
        guard let repository else { return nil }
        do {
            return try repository.attachmentPreviewURL(id: attachment.id)
        } catch {
            present(error)
            return nil
        }
    }

    @discardableResult
    func exportAttachment(
        _ attachment: FinanceAttachment,
        to destinationURL: URL,
        replaceExisting: Bool
    ) -> Bool {
        guard let repository else { return false }
        do {
            let exported = try repository.exportAttachment(
                id: attachment.id,
                to: destinationURL,
                replaceExisting: replaceExisting
            )
            statusText = "Anhang „\(attachment.fileName)“ nach „\(exported.lastPathComponent)“ exportiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func createTransfer(
        from sourceID: UUID,
        to destinationID: UUID,
        amount: String,
        date: Date,
        purpose: String
    ) -> Bool {
        createTransfer(
            from: sourceID,
            to: destinationID,
            sourceAmount: amount,
            destinationAmount: amount,
            date: date,
            purpose: purpose
        )
    }

    func updateTransfer(
        id transferID: UUID,
        sourceAmount: String,
        destinationAmount: String,
        date: Date,
        purpose: String
    ) -> Bool {
        guard let repository else { return false }
        let members = transactions.filter { $0.transferID == transferID }
        guard let sourceValue = members.first(where: { $0.amountMinor < 0 }),
              let destinationValue = members.first(where: { $0.amountMinor > 0 }),
              let source = accounts.first(where: {
                  $0.id == sourceValue.accountID
              }),
              let destination = accounts.first(where: {
                  $0.id == destinationValue.accountID
              }) else {
            errorMessage = "Die Umbuchung ist nicht vollständig."
            return false
        }
        do {
            let sourceMoney = try Money(
                parsing: sourceAmount, currency: source.currency
            )
            let destinationMoney = try Money(
                parsing: destinationAmount, currency: destination.currency
            )
            try repository.updateTransfer(
                id: transferID,
                sourceAmountMinor: abs(sourceMoney.minorUnits),
                destinationAmountMinor: abs(destinationMoney.minorUnits),
                date: date,
                purpose: purpose
            )
            try load()
            statusText = "Umbuchung atomar aktualisiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func createTransfer(
        from sourceID: UUID,
        to destinationID: UUID,
        sourceAmount: String,
        destinationAmount: String,
        date: Date,
        purpose: String
    ) -> Bool {
        guard
            let repository,
            let source = accounts.first(where: { $0.id == sourceID }),
            let destination = accounts.first(where: { $0.id == destinationID })
        else { return false }
        do {
            let sourceMoney = try Money(
                parsing: sourceAmount,
                currency: source.currency
            )
            let destinationMoney = try Money(
                parsing: destinationAmount,
                currency: destination.currency
            )
            try repository.createTransfer(
                from: source, to: destination,
                sourceAmountMinor: abs(sourceMoney.minorUnits),
                destinationAmountMinor: abs(destinationMoney.minorUnits),
                date: date,
                purpose: purpose
            )
            try load()
            statusText = "Umbuchung atomar gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func importCSV(
        data: Data,
        accountID: UUID,
        dateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) -> ImportPreview? {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            present(FinanceError.missingAccount)
            return nil
        }
        do {
            return try CSVFinanceImporter.preview(
                data: data,
                account: account
            ).matched(
                against: transactions,
                dateWindowDays: dateWindowDays
            )
        } catch {
            present(error)
            return nil
        }
    }

    func importCSV(
        data: Data,
        accountID: UUID,
        profile: CSVImportProfile,
        dateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) -> ImportPreview? {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            present(FinanceError.missingAccount)
            return nil
        }
        do {
            return try CSVFinanceImporter.preview(
                data: data,
                account: account,
                profile: profile,
                categories: categories
            ).matched(
                against: transactions,
                dateWindowDays: dateWindowDays
            )
        } catch {
            present(error)
            return nil
        }
    }

    func importQIF(
        data: Data,
        accountID: UUID,
        dateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) -> ImportPreview? {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            present(FinanceError.missingAccount)
            return nil
        }
        do {
            return try QIFFinanceImporter.preview(
                data: data, account: account, categories: categories
            ).matched(
                against: transactions,
                dateWindowDays: dateWindowDays
            )
        } catch {
            present(error)
            return nil
        }
    }

    func parseBankStatement(
        data: Data,
        format: BankStatementFormat
    ) -> BankStatementPackage? {
        do {
            return try BankStatementImporter.parse(data: data, format: format)
        } catch {
            present(error)
            return nil
        }
    }

    func previewBankStatement(
        _ package: BankStatementPackage,
        mappings: [String: UUID],
        dateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) -> ImportPreview? {
        do {
            return try package.preview(
                mappings: mappings,
                localAccounts: accounts
            ).matched(
                against: transactions,
                dateWindowDays: dateWindowDays
            )
        } catch {
            present(error)
            return nil
        }
    }

    func previewQIFPackage(
        data: Data,
        dateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) -> QIFPackagePreview? {
        do {
            let package = try QIFPackageImporter.preview(
                data: data,
                existingAccounts: accounts,
                existingCategories: categories,
                currency: fileInfo?.baseCurrency ?? "EUR"
            )
            return QIFPackagePreview(
                accountsToCreate: package.accountsToCreate,
                categoriesToCreate: package.categoriesToCreate,
                importPreview: package.importPreview.matched(
                    against: transactions,
                    dateWindowDays: dateWindowDays
                ),
                summary: package.summary,
                warnings: package.warnings
            )
        } catch {
            present(error)
            return nil
        }
    }

    func commitImport(
        _ preview: ImportPreview,
        resolutions: [UUID: ImportResolution] = [:]
    ) -> Bool {
        guard let repository else { return false }
        do {
            let result = try repository.commitImport(
                preview,
                resolutions: resolutions
            )
            try load()
            statusText = result.statusText
            return true
        } catch {
            present(error)
            return false
        }
    }

    func commitQIFPackage(
        _ package: QIFPackagePreview,
        resolutions: [UUID: ImportResolution] = [:]
    ) -> Bool {
        guard let repository else { return false }
        do {
            let result = try repository.commitQIFPackage(
                package,
                resolutions: resolutions
            )
            try load()
            statusText = result.statusText
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
        defer { try? FileManager.default.removeItem(at: url) }
        guard createBackup(at: url) else { return nil }
        return try? Data(contentsOf: url)
    }

    var automaticBackupDirectory: URL? {
        repository.map { AutomaticBackupManager.defaultDirectory(for: $0.fileURL) }
    }

    @discardableResult
    func createAutomaticBackup(
        force: Bool = false,
        policy: AutomaticBackupPolicy? = nil
    ) -> AutomaticBackupOutcome? {
        guard let repository else { return nil }
        do {
            let outcome = try AutomaticBackupManager.perform(
                repository: repository,
                policy: policy ?? AutomaticBackupPreferences.load(),
                force: force
            )
            automaticBackupStatusText = outcome.statusText
            if case .created = outcome { statusText = outcome.statusText }
            return outcome
        } catch {
            present(error)
            automaticBackupStatusText = "Autosicherung fehlgeschlagen: \(error.localizedDescription)"
            return nil
        }
    }

    func restoreBackup(from source: URL) -> Bool {
        guard let current = repository else { return false }
        let target = current.fileURL
        let safety = target.deletingLastPathComponent().appendingPathComponent(
            "Autosicherung-vor-Wiederherstellung-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).qbackup"
        )
        do {
            _ = try SQLiteFinanceStore.backupPreview(at: source)
            try current.backup(to: safety)
            _ = try SQLiteFinanceStore.backupPreview(at: safety)
            current.close()
            repository = nil
            let manager = FileManager.default
            func removeSidecars() throws {
                for suffix in ["-wal", "-shm"] {
                    let sidecar = URL(fileURLWithPath: target.path + suffix)
                    if manager.fileExists(atPath: sidecar.path) {
                        try manager.removeItem(at: sidecar)
                    }
                }
            }
            func replaceTarget(with source: URL, stagedName: String) throws {
                let staged = target.deletingLastPathComponent()
                    .appendingPathComponent(stagedName)
                defer { try? manager.removeItem(at: staged) }
                try manager.copyItem(at: source, to: staged)
                _ = try SQLiteFinanceStore.backupPreview(at: staged)
                try removeSidecars()
                if manager.fileExists(atPath: target.path) {
                    _ = try manager.replaceItemAt(target, withItemAt: staged)
                } else {
                    try manager.moveItem(at: staged, to: target)
                }
                try removeSidecars()
            }
            try replaceTarget(
                with: source,
                stagedName: "restore-\(UUID().uuidString).qdata"
            )
            do {
                repository = try SQLiteFinanceStore(fileURL: target)
                try load()
            } catch {
                let restoreError = error
                repository?.close()
                repository = nil
                try replaceTarget(
                    with: safety,
                    stagedName: "restore-rollback-\(UUID().uuidString).qdata"
                )
                repository = try SQLiteFinanceStore(fileURL: target)
                try load()
                throw restoreError
            }
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

    func reconciliationSnapshot(
        accountID: UUID,
        date: Date
    ) -> ReconciliationSnapshot? {
        guard
            let repository,
            let account = accounts.first(where: { $0.id == accountID })
        else { return nil }
        do {
            return try repository.reconciliationSnapshot(
                account: account,
                statementDate: date
            )
        } catch {
            present(error)
            return nil
        }
    }

    func reconciliationHistory(accountID: UUID) -> [ReconciliationRecord] {
        guard let repository else { return [] }
        do {
            return try repository.reconciliations(accountID: accountID)
        } catch {
            present(error)
            return []
        }
    }

    func reconcile(
        accountID: UUID,
        endingBalance: String,
        date: Date,
        selectedTransactionIDs: Set<UUID>,
        createAdjustment: Bool
    ) -> Bool {
        guard
            let repository,
            let account = accounts.first(where: { $0.id == accountID })
        else { return false }
        do {
            let amount = try Money(parsing: endingBalance, currency: account.currency)
            try repository.reconcile(
                account: account,
                endingBalanceMinor: amount.minorUnits,
                date: date,
                selectedTransactionIDs: selectedTransactionIDs,
                createAdjustment: createAdjustment
            )
            try load()
            statusText = "Konto „\(account.name)“ erfolgreich abgeglichen"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func revertReconciliation(_ value: ReconciliationRecord) -> Bool {
        guard let repository else { return false }
        do {
            try repository.revertReconciliation(
                id: value.id,
                accountID: value.accountID
            )
            try load()
            statusText = "Kontoabgleich wurde mit Auditspur zurückgenommen"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func rulePreviewCount(_ rule: CategorizationRule) -> Int {
        rulePreview(rule).count
    }

    func rulePreview(
        _ rule: CategorizationRule
    ) -> [RuleTransactionPreview] {
        RuleEngine.preview(rule: rule, transactions: transactions)
    }

    var ruleConflicts: [RuleConflict] {
        RuleEngine.conflicts(
            rules: categorizationRules,
            transactions: transactions
        )
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

    func createRule(from transaction: FinanceTransaction) -> Bool {
        guard let categoryID = transaction.categoryID,
              transaction.splits.isEmpty
        else {
            present(
                FinanceError.database(
                    "Eine Regel kann hier nur aus einer einfach kategorisierten Buchung erzeugt werden."
                )
            )
            return false
        }
        var conditions: [RuleExpression] = [
            .condition(
                RuleCondition(
                    field: .account,
                    operation: .equals,
                    value: transaction.accountID.uuidString
                )
            )
        ]
        if !transaction.payee.isEmpty {
            conditions.append(
                .condition(
                    RuleCondition(
                        field: .payee,
                        operation: .equals,
                        value: transaction.payee
                    )
                )
            )
        } else if !transaction.purpose.isEmpty {
            conditions.append(
                .condition(
                    RuleCondition(
                        field: .purpose,
                        operation: .contains,
                        value: transaction.purpose
                    )
                )
            )
        }
        let nameSource = transaction.payee.isEmpty
            ? transaction.purpose : transaction.payee
        let rule = CategorizationRule(
            id: UUID(),
            name: "\(nameSource) → \(categoryName(categoryID))",
            priority: (categorizationRules.map(\.priority).max() ?? 0) + 10,
            isActive: true,
            stopAfterMatch: true,
            payeeContains: "",
            purposeContains: "",
            minimumAmountMinor: nil,
            maximumAmountMinor: nil,
            categoryID: categoryID,
            expression: .group(.all, conditions),
            actions: [.setCategory(categoryID)]
        )
        guard saveRule(rule) else { return false }
        statusText = "Regel „\(rule.name)“ aus Buchung erstellt · noch nicht angewendet"
        return true
    }

    func applyRule(_ rule: CategorizationRule) -> Int? {
        applyRule(
            rule,
            transactionIDs: Set(rulePreview(rule).map(\.id))
        )
    }

    func applyRule(
        _ rule: CategorizationRule,
        transactionIDs: Set<UUID>
    ) -> Int? {
        guard let repository else { return nil }
        do {
            let result = try repository.applyCategorizationRule(
                rule,
                transactionIDs: transactionIDs
            )
            try load()
            statusText = "Regel auf \(result.changedCount) Buchungen angewendet · Undo verfügbar"
            return result.changedCount
        } catch {
            present(error)
            return nil
        }
    }

    func undoLatestRuleApplication() -> Bool {
        guard let repository, let latestRuleUndo else { return false }
        do {
            let count = try repository.undoRuleApplication(
                id: latestRuleUndo.id
            )
            try load()
            statusText = "\(count) Regeländerungen vollständig zurückgenommen"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func createSimulatorBankingConnection() -> BankingConnection? {
        guard let repository else { return nil }
        if let existing = bankingConnections.first(where: {
            $0.providerKind == .simulator
        }) {
            statusText = "Vorhandener Banking-Simulator ausgewählt"
            return existing
        }
        let eligible = accounts.filter {
            !$0.isClosed
                && [.checking, .savings, .creditCard]
                    .contains($0.type)
        }.prefix(5)
        guard !eligible.isEmpty else {
            present(
                FinanceError.database(
                    "Für den Simulator wird mindestens ein offenes Bank- oder Kreditkartenkonto benötigt."
                )
            )
            return nil
        }
        let connection = BankingConnection(
            id: UUID(),
            name: "Lokaler Banking-Simulator",
            providerKind: .simulator,
            adapterIdentifier:
                "de.pixelpuxel.finanzverwalter.banking-simulator.v1",
            institutionName: "FinanzVerwalter Testbank",
            status: .ready,
            consentValidUntil: nil,
            lastSyncAt: nil,
            lastUserMessage:
                "Keine echte Bankverbindung und keine Zugangsdaten",
            isEnabled: true
        )
        do {
            try repository.saveBankingConnection(connection)
            for account in eligible {
                try repository.saveBankingAccountMapping(
                    BankingAccountMapping(
                        id: UUID(),
                        connectionID: connection.id,
                        externalAccountID:
                            "sim:" + account.id.uuidString.lowercased(),
                        remoteName: account.name,
                        remoteIBAN: account.iban,
                        currency: account.currency,
                        localAccountID: account.id,
                        isEnabled: true
                    )
                )
            }
            try load()
            statusText = "Simulator eingerichtet · keine echte Bankverbindung"
            return bankingConnections.first { $0.id == connection.id }
        } catch {
            present(error)
            return nil
        }
    }

    func saveBankingMapping(
        _ mapping: BankingAccountMapping
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveBankingAccountMapping(mapping)
            try load()
            statusText = "Bankkonto-Zuordnung gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func previewSimulatorBankingDownload(
        connectionID: UUID,
        externalAccountIDs: Set<String>,
        operations: Set<BankingOperation>,
        dateWindowDays: Int = ImportMatcher.defaultDateWindowDays
    ) async -> BankingDownloadPreview? {
        guard
            let connection = bankingConnections.first(where: {
                $0.id == connectionID
            }),
            connection.providerKind == .simulator,
            connection.isEnabled,
            !externalAccountIDs.isEmpty,
            !operations.isEmpty
        else {
            present(
                FinanceError.database(
                    "Verbindung, Konten und Abrufvorgänge müssen ausgewählt sein."
                )
            )
            return nil
        }
        let mappings = bankingMappings.filter {
            $0.connectionID == connectionID
                && $0.isEnabled
                && externalAccountIDs.contains($0.externalAccountID)
        }
        guard mappings.count == externalAccountIDs.count,
              mappings.allSatisfy({ $0.localAccountID != nil })
        else {
            present(
                FinanceError.database(
                    "Alle ausgewählten Bankkonten benötigen eine lokale Zuordnung."
                )
            )
            return nil
        }
        let localByID = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0) }
        )
        let remoteAccounts: [BankingRemoteAccount] = mappings.compactMap {
            (mapping: BankingAccountMapping) -> BankingRemoteAccount? in
            guard let localID = mapping.localAccountID,
                  let local = localByID[localID]
            else { return nil }
            return BankingRemoteAccount(
                id: mapping.externalAccountID,
                name: mapping.remoteName,
                iban: mapping.remoteIBAN,
                bic: local.bic,
                currency: mapping.currency,
                accountType: local.type.rawValue,
                ownerName: local.ownerName
            )
        }
        let adapter = SimulatorBankingAdapter(
            accounts: remoteAccounts,
            anchorDate: Calendar(identifier: .gregorian)
                .startOfDay(for: Date())
        )
        isBusy = true
        bankingProgressText = "Dialog initialisiert · Abruf läuft"
        statusText = bankingProgressText
        defer {
            isBusy = false
            bankingProgressText = ""
        }
        do {
            let package = try await adapter.fetch(
                BankingFetchRequest(
                    externalAccountIDs: externalAccountIDs,
                    operations: operations,
                    dateFrom: Calendar.current.date(
                        byAdding: .month,
                        value: -3,
                        to: Date()
                    )
                )
            )
            try Task.checkCancellation()
            let preview = try BankingImportNormalizer.preview(
                connection: connection,
                package: package,
                mappings: mappings,
                existingTransactions: transactions,
                rules: categorizationRules,
                selectedExternalAccountIDs: externalAccountIDs,
                requestedOperations: operations,
                dateWindowDays: dateWindowDays
            )
            statusText = "Abruf erfolgreich · Vorschau bereit"
            return preview
        } catch is CancellationError {
            statusText = "Banking-Abruf ohne Datenänderung abgebrochen"
            return nil
        } catch {
            do {
                try repository?.recordBankingFailure(
                    connectionID: connectionID,
                    operations: operations,
                    userMessage: "Der simulierte Abruf ist fehlgeschlagen.",
                    technicalCode: String(describing: error)
                )
                try load()
            } catch {
                present(error)
            }
            present(error)
            return nil
        }
    }

    func commitBankingDownload(
        _ preview: BankingDownloadPreview,
        resolutions: [UUID: ImportResolution]
    ) -> Bool {
        guard let repository else { return false }
        do {
            let result = try repository.commitBankingDownload(
                preview,
                resolutions: resolutions
            )
            try load()
            statusText = "Banking-Abruf: " + result.statusText
            return true
        } catch {
            present(error)
            return false
        }
    }

    func forecastOccurrences(days: Int = 90) -> [FinanceTransaction] {
        let end = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return forecastOccurrences(through: end)
    }

    private func forecastOccurrences(through end: Date) -> [FinanceTransaction] {
        let existingReferences = Set(transactions.map(\.reference).filter { !$0.isEmpty })
        let includedAccounts = Set(
            accounts.filter { $0.includeForecast && !$0.isClosed }.map(\.id)
        )
        return scheduledTransactions
            .filter { includedAccounts.contains($0.accountID) }
            .flatMap {
                $0.occurrences(
                    until: end,
                    excludingReferences: existingReferences,
                    exceptions: scheduledTransactionExceptions,
                    revisions: scheduledTransactionRevisions
                )
            }
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

    func liquidityForecast(
        accountIDs: Set<UUID>, scenarioID: UUID?, from start: Date,
        through end: Date, interval: ForecastInterval
    ) -> [ForecastBucket] {
        return LiquidityForecastEngine.buckets(
            accounts: accounts, transactions: transactions,
            paymentOrders: paymentOrders, standingOrders: standingOrders,
            recurring: forecastOccurrences(through: end),
            scenarioEntries: scenarioID.flatMap { id in
                forecastScenarios.first { $0.id == id && $0.isActive }.map { _ in
                    forecastScenarioEntries.filter { $0.scenarioID == id }
                }
            } ?? [],
            accountIDs: accountIDs, from: start, through: end, interval: interval
        )
    }

    func saveForecastScenario(_ value: ForecastScenario) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveForecastScenario(value)
            try load()
            statusText = "Szenario „\(value.name)“ gespeichert"
            return true
        } catch { present(error); return false }
    }

    func saveForecastScenarioEntry(_ value: ForecastScenarioEntry) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveForecastScenarioEntry(value)
            try load()
            statusText = "Szenarioposition „\(value.name)“ gespeichert"
            return true
        } catch { present(error); return false }
    }

    func deleteForecastScenario(id: UUID) -> Bool {
        guard let repository else { return false }
        do {
            try repository.deleteForecastScenario(id: id)
            try load()
            statusText = "Szenario gelöscht"
            return true
        } catch { present(error); return false }
    }

    func deleteForecastScenarioEntry(id: UUID) -> Bool {
        guard let repository else { return false }
        do {
            try repository.deleteForecastScenarioEntry(id: id)
            try load()
            statusText = "Szenarioposition gelöscht"
            return true
        } catch { present(error); return false }
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

    func scheduledTransactionException(
        forReference reference: String,
        calendar: Calendar = .current
    ) -> ScheduledTransactionException? {
        guard let identity = ScheduledTransaction.occurrenceIdentity(from: reference) else {
            return nil
        }
        return scheduledTransactionExceptions.first {
            $0.scheduledTransactionID == identity.scheduledTransactionID
                && calendar.isDate($0.originalDueDate, inSameDayAs: identity.originalDueDate)
        }
    }

    func saveScheduledTransactionException(
        _ value: ScheduledTransactionException
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveScheduledTransactionException(value)
            try load()
            statusText = value.disposition == .skipped
                ? "Serienfälligkeit übersprungen"
                : "Serienfälligkeit geändert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func scheduledTransactionRevision(
        forReference reference: String,
        startingExactly: Bool = false,
        calendar: Calendar = .current
    ) -> ScheduledTransactionRevision? {
        guard let identity = ScheduledTransaction.occurrenceIdentity(from: reference) else {
            return nil
        }
        let boundary = calendar.startOfDay(for: identity.originalDueDate)
        let matches = scheduledTransactionRevisions.filter {
            guard $0.scheduledTransactionID == identity.scheduledTransactionID else {
                return false
            }
            let revisionDay = calendar.startOfDay(for: $0.originalDueDate)
            return startingExactly ? revisionDay == boundary : revisionDay <= boundary
        }
        return matches.max {
            let left = calendar.startOfDay(for: $0.originalDueDate)
            let right = calendar.startOfDay(for: $1.originalDueDate)
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }

    func saveScheduledTransactionRevision(
        _ value: ScheduledTransactionRevision
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveScheduledTransactionRevision(value)
            try load()
            statusText = "Serie ab gewählter Fälligkeit geändert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func resetScheduledTransactionRevision(
        scheduledTransactionID: UUID,
        originalDueDate: Date
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.deleteScheduledTransactionRevision(
                scheduledTransactionID: scheduledTransactionID,
                originalDueDate: originalDueDate
            )
            try load()
            statusText = "Serienänderung ab gewählter Fälligkeit zurückgesetzt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func resetScheduledTransactionException(
        scheduledTransactionID: UUID,
        originalDueDate: Date
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.deleteScheduledTransactionException(
                scheduledTransactionID: scheduledTransactionID,
                originalDueDate: originalDueDate
            )
            try load()
            statusText = "Serienfälligkeit auf den Serienwert zurückgesetzt"
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
        guard let planning = budgetPlanningSnapshot(budgetID: budgetID) else { return [] }
        let monthKey = BudgetPlanningEngine.monthKey(month)
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return planning.rows(monthKey: monthKey).compactMap { row in
            categoriesByID[row.categoryID].map { category in
                BudgetStatusRow(
                    category: category, line: row.line,
                    plannedMinor: row.effectivePlannedMinor,
                    actualMinor: row.actualMinor,
                    rolloverMinor: row.rolloverInMinor,
                    rolloverOutMinor: row.rolloverOutMinor,
                    rolloverMode: row.rolloverMode
                )
            }
        }
    }

    func budgetPlanningSnapshot(
        budgetID: UUID,
        calendar: Calendar = .current
    ) -> BudgetPlanningSnapshot? {
        guard let repository,
              let budget = budgets.first(where: { $0.id == budgetID })
        else { return nil }
        do {
            return BudgetPlanningEngine.snapshot(
                budget: budget, lines: try repository.budgetLines(budgetID: budgetID),
                transactions: transactions, accounts: accounts,
                categories: categories, tags: tags, calendar: calendar
            )
        } catch {
            present(error)
            return nil
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
            try load()
            statusText = "Budgetwert gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveBudgetYear(
        budgetID: UUID,
        categoryID: UUID,
        amounts: [Date: Int64],
        rolloverMode: BudgetRolloverMode,
        calendar: Calendar = .current
    ) -> Bool {
        guard let repository,
              let budget = budgets.first(where: { $0.id == budgetID }),
              budget.months(calendar: calendar).allSatisfy({ amounts[$0] != nil })
        else { return false }
        do {
            let existing = Dictionary(uniqueKeysWithValues:
                try repository.budgetLines(budgetID: budgetID)
                    .filter { $0.categoryID == categoryID }
                    .map { (String(format: "%04d-%02d", $0.year, $0.month), $0) }
            )
            let lines = try budget.months(calendar: calendar).map { month -> BudgetLine in
                let components = calendar.dateComponents([.year, .month], from: month)
                guard let year = components.year, let monthValue = components.month,
                      let amount = amounts[month] else {
                    throw FinanceError.database("Ein Jahresbudgetwert ist unvollständig.")
                }
                let key = String(format: "%04d-%02d", year, monthValue)
                return BudgetLine(
                    id: existing[key]?.id ?? UUID(), budgetID: budgetID,
                    categoryID: categoryID, year: year, month: monthValue,
                    plannedMinor: abs(amount),
                    rolloverPositive: rolloverMode.rolloverPositive,
                    rolloverNegative: rolloverMode.rolloverNegative
                )
            }
            try repository.saveBudgetLines(lines)
            try load()
            statusText = "Jahreswerte gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func duplicateBudget(
        sourceID: UUID,
        name: String,
        startYear: Int,
        startMonth: Int,
        calendar: Calendar = .current
    ) -> UUID? {
        guard let repository,
              let source = budgets.first(where: { $0.id == sourceID })
        else { return nil }
        let target = FinanceBudget(
            id: UUID(), name: name, startYear: startYear, startMonth: startMonth,
            currency: source.currency, isActive: true
        )
        do {
            try repository.duplicateBudget(sourceID: sourceID, target: target, calendar: calendar)
            try load()
            statusText = "Budget „\(target.name)“ angelegt"
            return target.id
        } catch {
            present(error)
            return nil
        }
    }

    func deleteBudget(id: UUID) -> Bool {
        guard let repository else { return false }
        do {
            try repository.deleteBudget(id: id)
            try load()
            statusText = "Budget gelöscht"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func budgetTransactions(
        budgetID: UUID, categoryID: UUID, month: Date
    ) -> [FinanceTransaction] {
        guard let planning = budgetPlanningSnapshot(budgetID: budgetID) else { return [] }
        let monthKey = BudgetPlanningEngine.monthKey(month)
        let factIDs = planning.rows.first {
            $0.categoryID == categoryID && $0.monthKey == monthKey
        }?.factIDs ?? []
        let transactionIDs = Set(planning.facts.filter { factIDs.contains($0.id) }.map(\.transactionID))
        return transactions.filter { transactionIDs.contains($0.id) }
            .sorted { $0.bookingDate == $1.bookingDate ? $0.id.uuidString < $1.id.uuidString
                : $0.bookingDate < $1.bookingDate }
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
        endToEndID: String,
        payeeID: UUID? = nil,
        payeeBankAccountID: UUID? = nil,
        purposeCode: String = ""
    ) -> Bool {
        guard let repository, let account = accounts.first(where: { $0.id == accountID }) else {
            return false
        }
        do {
            let money = try Money(parsing: amount, currency: account.currency)
            let normalizedIBAN = IBANValidator.normalized(iban)
            let normalizedPurposeCode = purposeCode
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let day = executionDate.formatted(
                .iso8601.year().month().day().dateSeparator(.dash)
            )
            let canonical = [
                accountID.uuidString, type.rawValue, normalizedIBAN,
                String(abs(money.minorUnits)), day,
                purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                endToEndID.trimmingCharacters(in: .whitespacesAndNewlines),
                normalizedPurposeCode
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
                    bankReference: "", createdAt: now, updatedAt: now,
                    payeeID: payeeID,
                    payeeBankAccountID: payeeBankAccountID,
                    purposeCode: normalizedPurposeCode
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

    func updatePaymentOrderDraft(
        _ original: PaymentOrder,
        accountID: UUID,
        type: PaymentType,
        recipientName: String,
        iban: String,
        bic: String,
        amount: String,
        executionDate: Date,
        purpose: String,
        endToEndID: String,
        payeeID: UUID? = nil,
        payeeBankAccountID: UUID? = nil,
        purposeCode: String = ""
    ) -> Bool {
        guard let repository,
              original.status == .draft,
              let account = accounts.first(where: {
                  $0.id == accountID && !$0.isClosed
              }) else { return false }
        do {
            let money = try Money(parsing: amount, currency: account.currency)
            let normalizedIBAN = IBANValidator.normalized(iban)
            let normalizedPurposeCode = purposeCode
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let normalizedRecipient = recipientName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let normalizedPurpose = purpose.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let normalizedEndToEndID = endToEndID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let day = executionDate.formatted(
                .iso8601.year().month().day().dateSeparator(.dash)
            )
            let canonical = [
                accountID.uuidString, type.rawValue, normalizedIBAN,
                String(abs(money.minorUnits)), day, normalizedPurpose,
                normalizedEndToEndID, normalizedPurposeCode
            ].joined(separator: "|")
            let idempotencyKey = SHA256.hash(data: Data(canonical.utf8))
                .map { String(format: "%02x", $0) }.joined()
            try repository.updatePaymentOrderDraft(
                PaymentOrder(
                    id: original.id, accountID: accountID, type: type,
                    recipientName: normalizedRecipient,
                    iban: normalizedIBAN,
                    bic: bic.trimmingCharacters(in: .whitespacesAndNewlines),
                    amountMinor: abs(money.minorUnits),
                    currency: account.currency,
                    executionDate: executionDate,
                    purpose: normalizedPurpose,
                    endToEndID: normalizedEndToEndID,
                    status: .draft, idempotencyKey: idempotencyKey,
                    bankReference: original.bankReference,
                    createdAt: original.createdAt, updatedAt: Date(),
                    payeeID: payeeID,
                    payeeBankAccountID: payeeBankAccountID,
                    purposeCode: normalizedPurposeCode
                )
            )
            try load()
            statusText = "Zahlungsentwurf aktualisiert"
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

    func previewPaymentStatusReport(data: Data) -> Pain002Preview? {
        do {
            return Pain002Importer.preview(
                document: try Pain002Importer.parse(data: data),
                paymentOrders: paymentOrders,
                directDebitOrders: directDebitOrders,
                batches: paymentBatches
            )
        } catch {
            present(error)
            return nil
        }
    }

    func previewPaymentInstructionImport(
        data: Data
    ) -> PainInstructionPreview? {
        do {
            return PainInstructionImporter.preview(
                document: try PainInstructionImporter.parse(data: data),
                accounts: accounts, payees: payees,
                bankAccounts: payeeBankAccounts, mandates: sepaMandates
            )
        } catch {
            present(error)
            return nil
        }
    }

    func commitPaymentInstructionImport(
        _ preview: PainInstructionPreview,
        importing selectedMatchIDs: Set<UUID>
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.commitPaymentInstructionImport(
                preview, importing: selectedMatchIDs
            )
            try load()
            statusText = "\(preview.document.kind.title)en als Entwürfe importiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func paymentInstructionImportItems(
        importID: String
    ) -> [PaymentInstructionImportItem] {
        guard let repository else { return [] }
        return (try? repository.paymentInstructionImportItems(importID: importID)) ?? []
    }

    func commitPaymentStatusReport(
        _ preview: Pain002Preview,
        applying selectedMatchIDs: Set<UUID>
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.commitPaymentStatusReport(
                preview, applying: selectedMatchIDs
            )
            try load()
            statusText = "pain.002-Statusbericht importiert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func paymentStatusReportItems(
        reportID: String
    ) -> [PaymentStatusReportItem] {
        guard let repository else { return [] }
        return (try? repository.paymentStatusReportItems(reportID: reportID)) ?? []
    }

    func createPaymentBatch(
        name: String,
        kind: PaymentBatchKind,
        memberOrderIDs: Set<UUID>
    ) -> Bool {
        guard let repository else { return false }
        let sortedIDs = memberOrderIDs.sorted { $0.uuidString < $1.uuidString }
        let accountID: UUID
        let requestedDate: Date
        switch kind {
        case .creditTransfer:
            guard let firstID = sortedIDs.first,
                  let first = paymentOrders.first(where: { $0.id == firstID })
            else {
                errorMessage = "Bitte wähle mindestens zwei Überweisungsentwürfe."
                return false
            }
            accountID = first.accountID
            requestedDate = first.executionDate
        case .directDebit:
            guard let firstID = sortedIDs.first,
                  let first = directDebitOrders.first(where: { $0.id == firstID })
            else {
                errorMessage = "Bitte wähle mindestens zwei Lastschriftentwürfe."
                return false
            }
            accountID = first.creditorAccountID
            requestedDate = first.collectionDate
        }
        let requestedDay = requestedDate.formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
        let canonical = ([kind.rawValue, accountID.uuidString, requestedDay]
            + sortedIDs.map(\.uuidString)).joined(separator: "|")
        let idempotencyKey = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let now = Date()
        do {
            try repository.createPaymentBatch(
                PaymentBatch(
                    id: UUID(),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind, accountID: accountID,
                    requestedDate: requestedDate, status: .draft,
                    idempotencyKey: idempotencyKey, bankReference: "",
                    memberOrderIDs: sortedIDs, createdAt: now, updatedAt: now
                )
            )
            try load()
            statusText = "\(kind.title) angelegt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func transitionPaymentBatch(
        _ batch: PaymentBatch,
        to target: PaymentStatus
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.transitionPaymentBatch(id: batch.id, to: target)
            try load()
            statusText = "Sammlerstatus: \(target.title)"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func submitPaymentBatch(
        _ batch: PaymentBatch,
        authorizationCode: String
    ) -> Bool {
        guard !authorizationCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            errorMessage = "Für die Simulation ist ein Freigabecode erforderlich. Er wird nicht gespeichert."
            return false
        }
        return transitionPaymentBatch(batch, to: .submitted)
    }

    func simulatePaymentBatchDecision(
        _ batch: PaymentBatch,
        outcome: SimulatorOutcome
    ) -> Bool {
        transitionPaymentBatch(batch, to: outcome.paymentStatus)
    }

    func createDirectDebitOrder(
        creditorAccountID: UUID,
        debtorPayeeID: UUID,
        debtorBankAccountID: UUID,
        mandateID: UUID,
        creditorID: String,
        amount: String,
        collectionDate: Date,
        purpose: String,
        endToEndID: String
    ) -> Bool {
        guard let repository,
              let account = accounts.first(where: { $0.id == creditorAccountID }),
              let bankAccount = payeeBankAccounts.first(where: {
                  $0.id == debtorBankAccountID
                      && $0.payeeID == debtorPayeeID
              }),
              let mandate = sepaMandates.first(where: {
                  $0.id == mandateID && $0.payeeID == debtorPayeeID
              }),
              let mandateSignedOn = mandate.signedOn
        else {
            errorMessage = "Für die Lastschrift fehlen Konto, Zahler, Bankverbindung oder unterzeichnetes Mandat."
            return false
        }
        do {
            let money = try Money(parsing: amount, currency: account.currency)
            let collectionDay = collectionDate.formatted(
                .iso8601.year().month().day().dateSeparator(.dash)
            )
            let canonical = [
                creditorAccountID.uuidString,
                debtorPayeeID.uuidString,
                debtorBankAccountID.uuidString,
                mandateID.uuidString,
                SEPACreditorIDValidator.normalized(creditorID),
                String(abs(money.minorUnits)), collectionDay,
                purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                endToEndID.trimmingCharacters(in: .whitespacesAndNewlines)
            ].joined(separator: "|")
            let idempotencyKey = SHA256.hash(data: Data(canonical.utf8))
                .map { String(format: "%02x", $0) }.joined()
            let now = Date()
            try repository.createDirectDebitOrder(
                DirectDebitOrder(
                    id: UUID(), creditorAccountID: account.id,
                    debtorPayeeID: debtorPayeeID,
                    debtorBankAccountID: bankAccount.id,
                    mandateID: mandate.id,
                    creditorName: account.ownerName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    creditorID: SEPACreditorIDValidator.normalized(creditorID),
                    creditorIBAN: IBANValidator.normalized(account.iban),
                    creditorBIC: account.bic.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    debtorName: bankAccount.accountHolder,
                    debtorIBAN: IBANValidator.normalized(bankAccount.iban),
                    debtorBIC: bankAccount.bic,
                    amountMinor: abs(money.minorUnits), currency: account.currency,
                    collectionDate: collectionDate,
                    purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                    endToEndID: endToEndID.trimmingCharacters(in: .whitespacesAndNewlines),
                    mandateReference: mandate.reference,
                    mandateSignedOn: mandateSignedOn,
                    sequenceType: mandate.sequenceType,
                    status: .draft, idempotencyKey: idempotencyKey,
                    bankReference: "", createdAt: now, updatedAt: now
                )
            )
            try load()
            statusText = "Lastschriftentwurf angelegt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func transitionDirectDebit(
        _ order: DirectDebitOrder,
        to target: PaymentStatus
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.transitionDirectDebitOrder(id: order.id, to: target)
            try load()
            statusText = "Lastschriftstatus: \(target.title)"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func submitDirectDebit(
        _ order: DirectDebitOrder,
        authorizationCode: String
    ) -> Bool {
        guard !authorizationCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            errorMessage = "Für die Simulation ist ein Freigabecode erforderlich. Er wird nicht gespeichert."
            return false
        }
        return transitionDirectDebit(order, to: .submitted)
    }

    func simulateDirectDebitDecision(
        _ order: DirectDebitOrder,
        outcome: SimulatorOutcome
    ) -> Bool {
        transitionDirectDebit(order, to: outcome.paymentStatus)
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
        amount: String,
        fees: String,
        taxes: String,
        note: String
    ) -> Bool {
        guard let repository,
              let security = securities.first(where: { $0.id == securityID })
        else { return false }
        do {
            switch type {
            case .buy:
                let quantityValue = try SecurityQuantity(parsing: quantity)
                let priceValue = try Money(parsing: price, currency: security.currency)
                let feeValue = try Money(
                    parsing: fees.isEmpty ? "0" : fees, currency: security.currency
                )
                let taxValue = try Money(
                    parsing: taxes.isEmpty ? "0" : taxes, currency: security.currency
                )
                try repository.recordPurchase(
                    accountID: accountID, securityID: securityID, date: date,
                    quantityMicro: quantityValue.microUnits,
                    priceMinor: priceValue.minorUnits,
                    feesMinor: feeValue.minorUnits, taxesMinor: taxValue.minorUnits,
                    note: note
                )
            case .sell:
                let quantityValue = try SecurityQuantity(parsing: quantity)
                let priceValue = try Money(parsing: price, currency: security.currency)
                let feeValue = try Money(
                    parsing: fees.isEmpty ? "0" : fees, currency: security.currency
                )
                let taxValue = try Money(
                    parsing: taxes.isEmpty ? "0" : taxes, currency: security.currency
                )
                try repository.recordSale(
                    accountID: accountID, securityID: securityID, date: date,
                    quantityMicro: quantityValue.microUnits,
                    priceMinor: priceValue.minorUnits,
                    feesMinor: feeValue.minorUnits, taxesMinor: taxValue.minorUnits,
                    note: note
                )
            case .dividend:
                let grossValue = try Money(parsing: amount, currency: security.currency)
                let feeValue = try Money(
                    parsing: fees.isEmpty ? "0" : fees, currency: security.currency
                )
                let taxValue = try Money(
                    parsing: taxes.isEmpty ? "0" : taxes, currency: security.currency
                )
                try repository.recordSecurityIncome(
                    accountID: accountID, securityID: securityID, date: date,
                    grossMinor: grossValue.minorUnits,
                    feesMinor: feeValue.minorUnits,
                    taxesMinor: taxValue.minorUnits, note: note
                )
            case .fee:
                let feeValue = try Money(parsing: amount, currency: security.currency)
                try repository.recordSecurityFee(
                    accountID: accountID, securityID: securityID, date: date,
                    feeMinor: feeValue.minorUnits, note: note
                )
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

    func loanPaymentCandidates(
        loan: FinanceLoan,
        entry: LoanScheduleEntry
    ) -> [LoanPaymentCandidate] {
        LoanPaymentMatchingEngine.candidates(
            for: entry, loan: loan, transactions: transactions,
            alreadyMatchedTransactionIDs: Set(loanPaymentMatches.map(\.transactionID))
        )
    }

    func postLoanScheduleEntry(
        loanID: UUID,
        scheduleEntryID: String,
        bookingDate: Date? = nil
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.postLoanScheduleEntry(
                loanID: loanID, scheduleEntryID: scheduleEntryID,
                bookingDate: bookingDate
            )
            try load()
            statusText = "Kreditrate als Splitbuchung angelegt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func matchLoanPayment(
        loanID: UUID,
        scheduleEntryID: String,
        transactionID: UUID
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.matchLoanPayment(
                loanID: loanID, scheduleEntryID: scheduleEntryID,
                transactionID: transactionID
            )
            try load()
            statusText = "Reale Kreditrate zugeordnet und aufgeteilt"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func removeLoanPaymentMatch(id: UUID) -> Bool {
        guard let repository else { return false }
        do {
            try repository.removeLoanPaymentMatch(id: id)
            try load()
            statusText = "Kreditabgleich sicher gelöst"
            return true
        } catch {
            present(error)
            return false
        }
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

    func saveTaxPerson(_ value: TaxPerson) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveTaxPerson(value)
            try load()
            statusText = "Steuerperson „\(value.displayName)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveTaxAllowanceOrder(_ value: TaxAllowanceOrder) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveTaxAllowanceOrder(value)
            try load()
            statusText = "Freistellungsauftrag bei „\(value.institution)“ gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func saveTaxAllowanceUsage(_ value: TaxAllowanceUsage) -> Bool {
        guard let repository else { return false }
        do {
            try repository.saveTaxAllowanceUsage(value)
            try load()
            statusText = "Genutzter Freistellungsbetrag gespeichert"
            return true
        } catch {
            present(error)
            return false
        }
    }

    func taxAllowanceReport(_ query: TaxAllowanceReportQuery) -> TaxAllowanceReportSnapshot {
        TaxAllowanceRuleEngine.snapshot(
            query: query, orders: taxAllowanceOrders, usages: taxAllowanceUsages,
            people: taxPeople, accounts: accounts, rules: taxAllowanceRules
        )
    }

    private func load() throws {
        guard let repository else { return }
        fileInfo = try repository.financeFileInfo()
        accounts = try repository.accounts()
        accountGroups = try repository.accountGroups()
        categories = try repository.categories()
        vatCodes = try repository.vatCodes()
        transactions = try repository.transactions()
        reportRows = try repository.categoryReport()
        reportTemplates = try repository.reportTemplates()
        transactionTemplates = try repository.transactionTemplates()
        categorizationRules = try repository.categorizationRules()
        latestRuleUndo = try repository.latestRuleUndo()
        latestTransactionUndo = try repository.latestTransactionUndo()
        bankingConnections = try repository.bankingConnections()
        bankingMappings = try repository.bankingAccountMappings()
        bankingSyncRuns = try repository.bankingSyncRuns()
        bankingRemoteOrders = try bankingConnections.flatMap {
            try repository.bankingRemoteOrders(connectionID: $0.id)
        }
        scheduledTransactions = try repository.scheduledTransactions()
        scheduledTransactionExceptions = try repository.scheduledTransactionExceptions()
        scheduledTransactionRevisions = try repository.scheduledTransactionRevisions()
        forecastScenarios = try repository.forecastScenarios()
        forecastScenarioEntries = try repository.forecastScenarioEntries()
        budgets = try repository.budgets()
        paymentOrders = try repository.paymentOrders()
        directDebitOrders = try repository.directDebitOrders()
        paymentBatches = try repository.paymentBatches()
        paymentStatusReports = try repository.paymentStatusReports()
        paymentInstructionImports = try repository.paymentInstructionImports()
        standingOrders = try repository.standingOrders()
        payees = try repository.payees()
        payeeBankAccounts = try repository.payeeBankAccounts()
        sepaMandates = try repository.sepaMandates()
        tags = try repository.tags()
        securities = try repository.securities()
        assetClasses = try repository.assetClasses()
        securityAllocations = try repository.securityAllocations()
        securityPrices = try repository.securityPrices()
        portfolioPositions = try repository.portfolioPositions()
        securityTrades = try repository.securityTrades()
        loans = try repository.loans()
        loanPaymentMatches = try repository.loanPaymentMatches()
        propertyAssetPositions = try repository.propertyAssetPositions()
        contracts = try repository.contracts()
        inventoryItems = try repository.inventoryItems()
        taxPeople = try repository.taxPeople()
        taxAllowanceRules = try repository.taxAllowanceRules()
        taxAllowanceOrders = try repository.taxAllowanceOrders()
        taxAllowanceUsages = try repository.taxAllowanceUsages()
        balances = Dictionary(
            uniqueKeysWithValues: try accounts.map { ($0.id, try repository.accountBalanceMinor(account: $0)) }
        )
        rebuildRegisterSearchIndex()
        if selectedAccountID == nil || !accounts.contains(where: { $0.id == selectedAccountID }) {
            selectedAccountID = accounts.first?.id
        }
    }

    private func rebuildRegisterSearchIndex() {
        registerSearchIndexTask?.cancel()
        let generation = UUID()
        registerSearchIndexGeneration = generation
        guard transactions.count > 25_000 else {
            registerSearchIndex = RegisterSearchIndex.build(
                transactions: transactions,
                accounts: accounts,
                accountGroups: accountGroups,
                categories: categories,
                tags: tags,
                runningBalances: runningBalances()
            )
            return
        }

        registerSearchIndex = .empty
        let indexedTransactions = transactions
        let indexedAccounts = accounts
        let indexedGroups = accountGroups
        let indexedCategories = categories
        let indexedTags = tags
        registerSearchIndexTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            let runningBalances = CombinedRegisterQuery.runningBalances(
                accounts: indexedAccounts,
                transactions: indexedTransactions
            )
            let index = RegisterSearchIndex.build(
                transactions: indexedTransactions,
                accounts: indexedAccounts,
                accountGroups: indexedGroups,
                categories: indexedCategories,
                tags: indexedTags,
                runningBalances: runningBalances
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard self?.registerSearchIndexGeneration == generation else { return }
                self?.registerSearchIndex = index
                self?.registerSearchIndexTask = nil
            }
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

    func seedReferenceRegisterDataset() throws -> ReferenceRegisterDatasetManifest {
        guard let repository, try repository.accounts().isEmpty else {
            throw FinanceError.database(
                "Der Referenzdatensatz kann nur in eine leere Finanzdatei geschrieben werden."
            )
        }
        let groups = try repository.accountGroups()
        let groupNames = ["Bankkonten", "Bargeld", "Vermögen", "Verbindlichkeiten"]
        let usedGroups = try groupNames.map { name in
            guard let group = groups.first(where: { $0.name == name }) else {
                throw FinanceError.database(
                    "Die Referenzkontengruppe „\(name)“ fehlt."
                )
            }
            return group
        }
        let accountDefinitions: [(String, AccountType, String, Int)] = [
            ("Giro Haushalt", .checking, "EUR", 0),
            ("Giro Rücklagen", .checking, "EUR", 0),
            ("Tagesgeld", .savings, "EUR", 0),
            ("Bargeld", .cash, "EUR", 1),
            ("Kreditkarte", .creditCard, "EUR", 3),
            ("Immobilie", .asset, "EUR", 2),
            ("Darlehen", .loan, "EUR", 3),
            ("Depot Inland", .investment, "EUR", 2),
            ("Depot Ausland", .investment, "USD", 2),
            ("Dollar-Konto", .foreignCurrency, "USD", 0),
            ("Franken-Konto", .foreignCurrency, "CHF", 0),
            ("Verrechnung", .clearing, "EUR", 0)
        ]
        var referenceAccounts: [FinanceAccount] = []
        referenceAccounts.reserveCapacity(accountDefinitions.count)
        for (offset, definition) in accountDefinitions.enumerated() {
            let id = Self.referenceUUID(prefix: "A", number: offset + 1)
            let account = FinanceAccount(
                id: id, name: definition.0, institution: "Referenzbank",
                type: definition.1, currency: definition.2,
                openingBalanceMinor: Int64((offset + 1) * 100_000),
                isHidden: false, isClosed: false, sortOrder: offset,
                shortName: "R\(offset + 1)",
                description: "Synthetisches Referenzkonto",
                groupID: usedGroups[definition.3].id,
                accountNumberMasked: String(format: "•••• %04d", offset + 1),
                ownerName: "Referenzhaushalt",
                includeBudget: definition.2 == "EUR",
                includeForecast: definition.2 == "EUR"
            )
            try repository.saveAccount(account)
            referenceAccounts.append(account)
        }

        let categories = try repository.categories()
        let incomeCategories = categories.filter { $0.kind == .income }
        let expenseCategories = categories.filter { $0.kind == .expense }
        guard !incomeCategories.isEmpty, expenseCategories.count >= 2 else {
            throw FinanceError.database(
                "Für den Referenzdatensatz fehlen Standardkategorien."
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = calendar.date(
            from: DateComponents(year: 2026, month: 12, day: 31)
        )!
        var transactions: [FinanceTransaction] = []
        transactions.reserveCapacity(10_000)
        var expectedNetByCurrency: [String: Int64] = [:]
        for offset in 0..<9_700 {
            let account = referenceAccounts[offset % referenceAccounts.count]
            let isIncome = offset % 11 == 0
            let magnitude = Int64(500 + (offset * 97) % 45_000)
            let amount = isIncome ? magnitude : -magnitude
            let category = isIncome
                ? incomeCategories[offset % incomeCategories.count]
                : expenseCategories[offset % expenseCategories.count]
            let date = calendar.date(
                byAdding: .day, value: -((offset * 37) % 3_653), to: endDate
            )!
            let splitValues: [FinanceSplit]
            if offset < 100 {
                let first = amount / 2
                splitValues = [
                    FinanceSplit(
                        id: Self.referenceUUID(prefix: "C", number: offset * 2 + 1),
                        categoryID: expenseCategories[offset % expenseCategories.count].id,
                        amountMinor: first, memo: "Referenzsplit A", sortOrder: 0
                    ),
                    FinanceSplit(
                        id: Self.referenceUUID(prefix: "C", number: offset * 2 + 2),
                        categoryID: expenseCategories[(offset + 1) % expenseCategories.count].id,
                        amountMinor: amount - first, memo: "Referenzsplit B", sortOrder: 1
                    )
                ]
            } else {
                splitValues = []
            }
            transactions.append(
                FinanceTransaction(
                    id: Self.referenceUUID(prefix: "B", number: offset + 1),
                    accountID: account.id, bookingDate: date, valueDate: date,
                    payee: "Referenzpartner \(offset % 250)",
                    purpose: "Synthetische Buchung \(offset + 1)",
                    categoryID: splitValues.isEmpty ? category.id : nil,
                    amountMinor: amount, currency: account.currency,
                    status: offset % 17 == 0 ? .cleared : .booked,
                    memo: "Referenzdatensatz", reference: "REF-\(offset + 1)",
                    transferID: nil, importFingerprint: nil, splits: splitValues
                )
            )
            expectedNetByCurrency[account.currency, default: 0] += amount
        }
        for offset in 0..<150 {
            let source = referenceAccounts[offset % 4]
            let destination = referenceAccounts[(offset + 1) % 4]
            let date = calendar.date(
                byAdding: .day, value: -((offset * 23) % 3_653), to: endDate
            )!
            let amount = Int64(1_000 + offset * 10)
            let transferID = Self.referenceUUID(prefix: "D", number: offset + 1)
            let common = (
                purpose: "Referenzumbuchung \(offset + 1)",
                firstID: Self.referenceUUID(prefix: "B", number: 9_701 + offset * 2),
                secondID: Self.referenceUUID(prefix: "B", number: 9_702 + offset * 2)
            )
            transactions.append(
                FinanceTransaction(
                    id: common.firstID, accountID: source.id,
                    bookingDate: date, valueDate: date,
                    payee: destination.name, purpose: common.purpose,
                    categoryID: nil, amountMinor: -amount,
                    currency: source.currency, status: .booked,
                    memo: "", reference: "", transferID: transferID,
                    importFingerprint: nil, splits: [], origin: .transfer
                )
            )
            transactions.append(
                FinanceTransaction(
                    id: common.secondID, accountID: destination.id,
                    bookingDate: date, valueDate: date,
                    payee: source.name, purpose: common.purpose,
                    categoryID: nil, amountMinor: amount,
                    currency: destination.currency, status: .booked,
                    memo: "", reference: "", transferID: transferID,
                    importFingerprint: nil, splits: [], origin: .transfer
                )
            )
        }
        try repository.seedReferenceTransactions(transactions)
        return ReferenceRegisterDatasetManifest(
            accountCount: 12, usedAccountGroupCount: 4,
            transactionCount: 10_000, splitRowCount: 200,
            transferCount: 150, currencies: ["EUR", "USD", "CHF"],
            earliestBookingDate: calendar.date(
                byAdding: .day, value: -3_652, to: endDate
            )!,
            latestBookingDate: endDate,
            expectedReportNetByCurrency: expectedNetByCurrency
        )
    }

    private static func referenceUUID(prefix: Character, number: Int) -> UUID {
        let value = String(
            format: "%@0000000-0000-4000-8000-%012llX",
            String(prefix), Int64(number)
        )
        return UUID(uuidString: value)!
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
