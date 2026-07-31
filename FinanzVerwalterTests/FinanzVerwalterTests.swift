import XCTest
import SQLite3
@testable import FinanzVerwalter

final class FinanzVerwalterTests: XCTestCase {
    func testGermanMoneyParsingUsesMinorUnitsWithoutBinaryFloat() throws {
        XCTAssertEqual(try Money(parsing: "1.234,56 €").minorUnits, 123_456)
        XCTAssertEqual(try Money(parsing: "-0,015").minorUnits, -2)
        XCTAssertEqual(try Money(parsing: "0,005").minorUnits, 0)
    }

    func testSplitInvariantRejectsDifferenceOfOneCent() throws {
        let accountID = UUID()
        let value = FinanceTransaction(
            id: UUID(), accountID: accountID, bookingDate: Date(), valueDate: nil,
            payee: "Muster", purpose: "Test", categoryID: nil,
            amountMinor: -1_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [
                FinanceSplit(id: UUID(), categoryID: nil, amountMinor: -600, memo: "", sortOrder: 0),
                FinanceSplit(id: UUID(), categoryID: nil, amountMinor: -399, memo: "", sortOrder: 1)
            ]
        )
        XCTAssertThrowsError(try value.validate()) { error in
            XCTAssertEqual(error as? FinanceError, .splitMismatch(expected: -1_000, actual: -999))
        }
    }

    func testSQLiteMigrationAccountBalanceAndPersistence() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Girokonto", institution: "Testbank", type: .checking,
            currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        try context.store.saveTransaction(
            FinanceTransaction(
                id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
                payee: "Händler", purpose: "Einkauf", categoryID: nil,
                amountMinor: -2_345, currency: "EUR", status: .booked,
                memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
            )
        )

        XCTAssertEqual(try context.store.accountBalanceMinor(account: account), 7_655)
        XCTAssertEqual(try context.store.accounts().map(\.name), ["Girokonto"])
        XCTAssertEqual(try context.store.transactions(accountID: account.id).count, 1)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testTransferCreatesExactlyTwoBalancedSides() throws {
        let context = try TestDatabase()
        let source = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking, currency: "EUR",
            openingBalanceMinor: 100_000, isHidden: false, isClosed: false, sortOrder: 0
        )
        let destination = FinanceAccount(
            id: UUID(), name: "Tagesgeld", institution: "", type: .savings, currency: "EUR",
            openingBalanceMinor: 0, isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(source)
        try context.store.saveAccount(destination)
        try context.store.createTransfer(
            from: source, to: destination, amountMinor: 25_000, date: Date(), purpose: "Rücklage"
        )

        let values = try context.store.transactions()
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(Set(values.compactMap(\.transferID)).count, 1)
        XCTAssertEqual(values.reduce(Int64.zero) { $0 + $1.amountMinor }, 0)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: source), 75_000)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: destination), 25_000)
    }

    func testCSVImportIsIdempotentByPackageFingerprint() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Kasse", institution: "", type: .cash, currency: "EUR",
            openingBalanceMinor: 0, isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let data = Data(
            """
            Datum;Empfänger;Verwendungszweck;Betrag
            30.07.2026;Bäckerei;Frühstück;-8,90
            31.07.2026;Kunde;Erstattung;12,34
            """.utf8
        )
        let preview = try CSVFinanceImporter.preview(data: data, account: account)
        XCTAssertEqual(preview.rows.count, 2)
        XCTAssertTrue(preview.rejectedRows.isEmpty)
        try context.store.commitImport(preview)
        XCTAssertThrowsError(try context.store.commitImport(preview)) { error in
            XCTAssertEqual(error as? FinanceError, .duplicateImport)
        }
        XCTAssertEqual(try context.store.transactions().count, 2)
    }

    func testBackupIsIndependentAndPassesIntegrityCheck() throws {
        let context = try TestDatabase()
        let backupURL = context.directory.appendingPathComponent("backup.qbackup")
        try context.store.backup(to: backupURL)
        let backup = try SQLiteFinanceStore(fileURL: backupURL)
        XCTAssertTrue(try backup.integrityCheck())
        XCTAssertEqual(try backup.financeFileInfo().name, "Meine Finanzen")
    }

    func testQIFImportPreservesCategoriesAndExactSplits() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking, currency: "EUR",
            openingBalanceMinor: 0, isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let categories = try context.store.categories()
        let data = Data(
            """
            !Type:Bank
            D7/31/2026
            T-100,00
            PMusterhandel
            MEinkauf
            SWohnen
            EAnteil Wohnen
            $-60,00
            SLebensmittel
            EAnteil Lebensmittel
            $-40,00
            ^
            """.utf8
        )
        let preview = try QIFFinanceImporter.preview(
            data: data, account: account, categories: categories
        )
        XCTAssertEqual(preview.rows.count, 1)
        XCTAssertTrue(preview.rejectedRows.isEmpty)
        XCTAssertEqual(preview.rows[0].splits.count, 2)
        XCTAssertEqual(preview.rows[0].splits.reduce(0) { $0 + $1.amountMinor }, -10_000)
        XCTAssertNoThrow(try preview.rows[0].validate())
    }

    func testQIFPackageCreatesAccountsHierarchyAndTransactionsAtomically() throws {
        let context = try TestDatabase()
        let data = Data(
            """
            !Type:Cat
            NHaushalt:Strom
            E
            ^
            NEinkommen:Honorar
            I
            ^
            !Account
            NAlltagskonto
            TBank
            DTestinstitut
            ^
            !Type:Bank
            D7/30/2026
            T-82.45
            PEnergieversorger
            MAbschlag
            LHaushalt:Strom
            ^
            !Account
            NKasse
            TCash
            ^
            !Type:Cash
            D7/31/2026
            T125.00
            PKundschaft
            MProjekt
            LEinkommen:Honorar
            ^
            !Account
            NDepot
            TInvst
            ^
            !Type:Invst
            D7/31/2026
            NBuy
            T100.00
            ^
            """.utf8
        )

        XCTAssertTrue(QIFPackageImporter.isPackage(data: data))
        XCTAssertThrowsError(
            try QIFFinanceImporter.preview(
                data: data,
                account: FinanceAccount(
                    id: UUID(), name: "Falsch", institution: "", type: .checking,
                    currency: "EUR", openingBalanceMinor: 0,
                    isHidden: false, isClosed: false, sortOrder: 0
                ),
                categories: []
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .qifPackageRequiresPackageImport)
        }

        let package = try QIFPackageImporter.preview(
            data: data,
            existingAccounts: try context.store.accounts(),
            existingCategories: try context.store.categories()
        )
        XCTAssertEqual(package.summary.accountDefinitions, 3)
        XCTAssertEqual(package.accountsToCreate.count, 3)
        XCTAssertEqual(package.importPreview.rows.count, 2)
        XCTAssertEqual(package.summary.unsupportedSectionCounts["Invst"], 1)
        XCTAssertTrue(package.importPreview.rejectedRows.isEmpty)
        XCTAssertTrue(
            package.categoriesToCreate.contains {
                $0.name == "Strom" && $0.parentID != nil
            }
        )

        try context.store.commitQIFPackage(package)
        let importedAccounts = try context.store.accounts()
        XCTAssertEqual(importedAccounts.count, 3)
        XCTAssertEqual(try context.store.transactions().count, 2)
        let groupsByID = Dictionary(
            uniqueKeysWithValues: try context.store.accountGroups().map { ($0.id, $0.name) }
        )
        XCTAssertEqual(
            groupsByID[importedAccounts.first { $0.name == "Alltagskonto" }?.groupID ?? UUID()],
            "Bankkonten"
        )
        XCTAssertEqual(
            groupsByID[importedAccounts.first { $0.name == "Kasse" }?.groupID ?? UUID()],
            "Bargeld"
        )
        XCTAssertEqual(
            groupsByID[importedAccounts.first { $0.name == "Depot" }?.groupID ?? UUID()],
            "Depots"
        )
        let categories = try context.store.categories()
        let electricity = try XCTUnwrap(categories.first { $0.name == "Strom" })
        XCTAssertEqual(
            categories.first { $0.id == electricity.parentID }?.name,
            "Haushalt"
        )
        XCTAssertThrowsError(try context.store.commitQIFPackage(package)) { error in
            XCTAssertEqual(error as? FinanceError, .duplicateImport)
        }
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testExternalQIFPackageWhenConfigured() throws {
        let configuredPath = ProcessInfo.processInfo.environment["FINANZVERWALTER_REAL_QIF"]
        let localAcceptanceLink = "/tmp/finanzverwalter-real-qif-acceptance.qif"
        let path = configuredPath.flatMap { $0.isEmpty ? nil : $0 }
            ?? (FileManager.default.fileExists(atPath: localAcceptanceLink)
                ? localAcceptanceLink
                : nil)
        guard let path else {
            throw XCTSkip("Nur für die lokale Abnahme mit einer externen QIF-Datei.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let context = try TestDatabase()
        let package = try QIFPackageImporter.preview(
            data: data,
            existingAccounts: try context.store.accounts(),
            existingCategories: try context.store.categories()
        )
        NSLog(
            "REAL_QIF_SAFE_SUMMARY accounts=%d categories=%d rows=%d rejected=%d unsupported=%d",
            package.summary.accountDefinitions,
            package.summary.categoryRecords,
            package.importPreview.rows.count,
            package.importPreview.rejectedRows.count,
            package.summary.unsupportedSectionCounts.values.reduce(0, +)
        )
        XCTContext.runActivity(
            named: "QIF-Strukturabnahme: \(package.summary.accountDefinitions) Konten, "
                + "\(package.summary.categoryRecords) Kategorien, "
                + "\(package.importPreview.rows.count) Buchungen, "
                + "\(package.importPreview.rejectedRows.count) abgelehnt, "
                + "\(package.summary.unsupportedSectionCounts.values.reduce(0, +)) nicht unterstützt"
        ) { _ in }
        XCTAssertGreaterThan(package.summary.accountDefinitions, 1)
        XCTAssertGreaterThan(package.importPreview.rows.count, 0)
        XCTAssertEqual(
            package.importPreview.rejectedRows.count, 0,
            "Der reale QIF-Import hat Buchungen abgelehnt."
        )
        try context.store.commitQIFPackage(package)
        XCTAssertEqual(
            try context.store.transactions().count,
            package.importPreview.rows.count
        )
        XCTAssertGreaterThanOrEqual(
            try context.store.accounts().count,
            package.accountsToCreate.count
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testReconciliationRequiresExactBalanceAndProtectsTransactions() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking, currency: "EUR",
            openingBalanceMinor: 10_000, isHidden: false, isClosed: false, sortOrder: 0
        )
        let transaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "Händler", purpose: "Kauf", categoryID: nil,
            amountMinor: -2_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveAccount(account)
        try context.store.saveTransaction(transaction)
        XCTAssertThrowsError(
            try context.store.reconcile(
                account: account, endingBalanceMinor: 8_001, date: Date()
            )
        )
        try context.store.reconcile(account: account, endingBalanceMinor: 8_000, date: Date())
        XCTAssertEqual(try context.store.transactions().first?.status, .reconciled)
        XCTAssertThrowsError(try context.store.saveTransaction(transaction)) { error in
            XCTAssertEqual(error as? FinanceError, .protectedTransaction)
        }
    }

    func testBulkCategorizationIsAtomicAndProtectsReconciledAndStructuredTransactions() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking, currency: "EUR",
            openingBalanceMinor: 0, isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = try XCTUnwrap(try context.store.categories().first(where: \.isActive))
        let editable = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "Markt", purpose: "Einkauf", categoryID: nil,
            amountMinor: -2_500, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        let reconciled = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "Versorger", purpose: "Abgeglichen", categoryID: nil,
            amountMinor: -4_000, currency: "EUR", status: .reconciled,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        let split = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "Kaufhaus", purpose: "Aufgeteilt", categoryID: nil,
            amountMinor: -1_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: category.id, amountMinor: -1_000,
                    memo: "", sortOrder: 0
                )
            ]
        )
        try context.store.saveTransaction(editable)
        try context.store.saveTransaction(reconciled)
        try context.store.saveTransaction(split)

        XCTAssertThrowsError(
            try context.store.bulkUpdateTransactionCategory(
                ids: [editable.id, reconciled.id],
                categoryID: category.id
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .protectedBulkEdit)
        }
        XCTAssertNil(
            try context.store.transactions().first(where: { $0.id == editable.id })?.categoryID
        )
        XCTAssertThrowsError(
            try context.store.bulkUpdateTransactionCategory(
                ids: [editable.id, split.id],
                categoryID: category.id
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .protectedBulkEdit)
        }

        let result = try context.store.bulkUpdateTransactionCategory(
            ids: [editable.id],
            categoryID: category.id
        )
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.totalsByCurrency, ["EUR": -2_500])
        XCTAssertEqual(
            try context.store.transactions().first(where: { $0.id == editable.id })?.categoryID,
            category.id
        )

        XCTAssertThrowsError(
            try context.store.bulkUpdateTransactionCategory(
                ids: [editable.id],
                categoryID: UUID()
            )
        )
        XCTAssertEqual(
            try context.store.transactions().first(where: { $0.id == editable.id })?.categoryID,
            category.id
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testInvalidBackupIsRejectedBeforeRestore() throws {
        let context = try TestDatabase()
        let invalid = context.directory.appendingPathComponent("invalid.qbackup")
        try Data("kein sqlite".utf8).write(to: invalid)
        XCTAssertThrowsError(try SQLiteFinanceStore.validateBackup(at: invalid)) { error in
            XCTAssertEqual(error as? FinanceError, .invalidBackup)
        }
    }

    func testCategorizationRulePreviewAndApplyAreDeterministic() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking, currency: "EUR",
            openingBalanceMinor: 0, isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = try XCTUnwrap(
            context.store.categories().first { $0.name == "Lebensmittel" }
        )
        let matching = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "EDEKA Markt", purpose: "Wocheneinkauf", categoryID: nil,
            amountMinor: -5_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        let protected = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "EDEKA Markt", purpose: "Alter Einkauf", categoryID: nil,
            amountMinor: -4_000, currency: "EUR", status: .reconciled,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(matching)
        try context.store.saveTransaction(protected)
        let rule = CategorizationRule(
            id: UUID(), name: "EDEKA → Lebensmittel", priority: 10,
            isActive: true, stopAfterMatch: true, payeeContains: "edeka",
            purposeContains: "", minimumAmountMinor: nil, maximumAmountMinor: nil,
            categoryID: category.id
        )
        try context.store.saveCategorizationRule(rule)

        XCTAssertEqual(try context.store.categorizationRules(), [rule])
        XCTAssertTrue(rule.matches(matching))
        XCTAssertFalse(rule.matches(protected))
        XCTAssertEqual(try context.store.applyCategorizationRule(rule), 1)
        let values = try context.store.transactions()
        XCTAssertEqual(values.first { $0.id == matching.id }?.categoryID, category.id)
        XCTAssertNil(values.first { $0.id == protected.id }?.categoryID)
    }

    func testMonthlySchedulePreservesMonthEndAndPersists() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let januaryEnd = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 31, hour: 12))
        )
        let februaryEnd = RecurrenceFrequency.monthly.next(after: januaryEnd, calendar: calendar)
        let marchEnd = RecurrenceFrequency.monthly.next(after: februaryEnd, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: februaryEnd), DateComponents(year: 2024, month: 2, day: 29))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: marchEnd), DateComponents(year: 2024, month: 3, day: 31))

        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking, currency: "EUR",
            openingBalanceMinor: 0, isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let schedule = ScheduledTransaction(
            id: UUID(), name: "Monatsende", accountID: account.id,
            payee: "Vermieter", purpose: "Miete", categoryID: nil,
            amountMinor: -100_000, currency: "EUR", nextDueDate: januaryEnd,
            endDate: marchEnd, frequency: .monthly, action: .remind,
            reminderDays: 5, isActive: true
        )
        try context.store.saveScheduledTransaction(schedule)

        let persisted = try XCTUnwrap(context.store.scheduledTransactions().first)
        XCTAssertEqual(persisted.id, schedule.id)
        XCTAssertEqual(persisted.name, schedule.name)
        XCTAssertEqual(persisted.amountMinor, schedule.amountMinor)
        XCTAssertEqual(persisted.frequency, schedule.frequency)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: persisted.nextDueDate),
            DateComponents(year: 2024, month: 1, day: 31)
        )
        let occurrences = schedule.occurrences(until: marchEnd, calendar: calendar)
        XCTAssertEqual(occurrences.count, 3)
        XCTAssertEqual(Set(occurrences.map(\.reference)).count, 3)
        XCTAssertTrue(occurrences.allSatisfy { $0.status == .expected })
        let materializedReference = try XCTUnwrap(occurrences.first?.reference)
        let remaining = schedule.occurrences(
            until: marchEnd,
            excludingReferences: [materializedReference],
            calendar: calendar
        )
        XCTAssertEqual(remaining.count, 2)
        XCTAssertFalse(remaining.contains { $0.reference == materializedReference })
    }

    func testFiscalBudgetPersistsPlanAndCalculatesVarianceInMinorUnits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let budget = FinanceBudget(
            id: UUID(), name: "Geschäftsjahr", startYear: 2026,
            startMonth: 4, currency: "EUR", isActive: true
        )
        let months = budget.months(calendar: calendar)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month], from: months.last!),
            DateComponents(year: 2027, month: 3)
        )

        let context = try TestDatabase()
        let expense = try XCTUnwrap(context.store.categories().first { $0.name == "Lebensmittel" })
        let income = try XCTUnwrap(context.store.categories().first { $0.name == "Gehalt" })
        try context.store.saveBudget(budget)
        let line = BudgetLine(
            id: UUID(), budgetID: budget.id, categoryID: expense.id,
            year: 2026, month: 7, plannedMinor: 50_000,
            rolloverPositive: true, rolloverNegative: false
        )
        try context.store.saveBudgetLine(line)

        XCTAssertEqual(try context.store.budgets(), [budget])
        XCTAssertEqual(try context.store.budgetLines(budgetID: budget.id, year: 2026, month: 7), [line])
        let expenseStatus = BudgetStatusRow(
            category: expense, line: line, plannedMinor: 50_000, actualMinor: -45_500
        )
        XCTAssertEqual(expenseStatus.varianceMinor, 4_500)
        XCTAssertEqual(expenseStatus.completionPercent, 91)
        XCTAssertEqual(
            BudgetStatusRow(
                category: expense, line: nil,
                plannedMinor: 15_000, actualMinor: -3_299
            ).completionPercent,
            22
        )
        let incomeStatus = BudgetStatusRow(
            category: income, line: nil, plannedMinor: 300_000, actualMinor: 320_000
        )
        XCTAssertEqual(incomeStatus.varianceMinor, 20_000)
    }

    func testIBANChecksumAndPaymentSimulatorStateMachineAreSafeAndIdempotent() throws {
        XCTAssertTrue(IBANValidator.isValid("DE89 3704 0044 0532 0130 00"))
        XCTAssertFalse(IBANValidator.isValid("DE89 3704 0044 0532 0130 01"))

        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 100_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let now = Date()
        let order = PaymentOrder(
            id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
            recipientName: "Stadtwerke", iban: "DE89370400440532013000",
            bic: "", amountMinor: 9_850, currency: "EUR",
            executionDate: now, purpose: "Abschlag", endToEndID: "NOTPROVIDED",
            status: .draft, idempotencyKey: "same-logical-order",
            bankReference: "", createdAt: now, updatedAt: now
        )
        try context.store.createPaymentOrder(order)
        XCTAssertThrowsError(try context.store.createPaymentOrder(order)) { error in
            XCTAssertEqual(error as? FinanceError, .duplicatePaymentOrder)
        }
        for status in [
            PaymentStatus.initiated, .challengeReceived, .awaitingUser,
            .submitted, .accepted
        ] {
            try context.store.transitionPaymentOrder(id: order.id, to: status)
        }
        let accepted = try XCTUnwrap(context.store.paymentOrders().first)
        XCTAssertEqual(accepted.status, .accepted)
        XCTAssertTrue(accepted.bankReference.hasPrefix("SIM-"))
        XCTAssertEqual(
            try context.store.transactions().filter {
                $0.reference == "payment:\(order.id.uuidString)"
            }.count,
            1
        )
        XCTAssertThrowsError(
            try context.store.transitionPaymentOrder(id: order.id, to: .submitted)
        ) { error in
            XCTAssertEqual(error as? FinanceError, .invalidPaymentTransition)
        }

        var unknownOrder = order
        unknownOrder = PaymentOrder(
            id: UUID(), accountID: unknownOrder.accountID, type: unknownOrder.type,
            recipientName: unknownOrder.recipientName, iban: unknownOrder.iban,
            bic: unknownOrder.bic, amountMinor: 1_000, currency: unknownOrder.currency,
            executionDate: unknownOrder.executionDate, purpose: "Unklarer Auftrag",
            endToEndID: unknownOrder.endToEndID, status: .draft,
            idempotencyKey: "unknown-logical-order", bankReference: "",
            createdAt: now, updatedAt: now
        )
        try context.store.createPaymentOrder(unknownOrder)
        for status in [
            PaymentStatus.initiated, .challengeReceived, .awaitingUser,
            .submitted, .unknown
        ] {
            try context.store.transitionPaymentOrder(id: unknownOrder.id, to: status)
        }
        XCTAssertThrowsError(
            try context.store.transitionPaymentOrder(id: unknownOrder.id, to: .initiated)
        ) { error in
            XCTAssertEqual(error as? FinanceError, .invalidPaymentTransition)
        }
    }

    func testPayeeAliasesAndTransactionAndSplitTagsRoundTrip() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = try XCTUnwrap(context.store.categories().first { $0.name == "Lebensmittel" })
        let privateTag = FinanceTag(
            id: UUID(), parentID: nil, name: "Privat", color: "blue",
            description: "Private Ausgaben", isActive: true
        )
        let childTag = FinanceTag(
            id: UUID(), parentID: privateTag.id, name: "Haushalt", color: "green",
            description: "", isActive: true
        )
        try context.store.saveTag(privateTag)
        try context.store.saveTag(childTag)
        let payee = FinancePayee(
            id: UUID(), canonicalName: "EDEKA Markt",
            aliases: ["EDEKA", "EDEKA Center"], address: "Musterstraße 1",
            email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: category.id, preferredAccountID: account.id,
            note: "Lebensmittel", isActive: true
        )
        try context.store.savePayee(payee)
        let value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: payee.canonicalName, purpose: "Einkauf", categoryID: nil,
            amountMinor: -10_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: category.id, amountMinor: -6_000,
                    memo: "Lebensmittel", sortOrder: 0, tagIDs: [privateTag.id]
                ),
                FinanceSplit(
                    id: UUID(), categoryID: category.id, amountMinor: -4_000,
                    memo: "Haushalt", sortOrder: 1, tagIDs: [childTag.id]
                )
            ],
            payeeID: payee.id,
            tagIDs: [privateTag.id, childTag.id]
        )
        try context.store.saveTransaction(value)

        XCTAssertEqual(try context.store.tags(), [childTag, privateTag])
        XCTAssertEqual(try context.store.payees(), [payee])
        let restored = try XCTUnwrap(context.store.transactions().first)
        XCTAssertEqual(restored.payeeID, payee.id)
        XCTAssertEqual(Set(restored.tagIDs), Set([privateTag.id, childTag.id]))
        XCTAssertEqual(Set(restored.splits[0].tagIDs), [privateTag.id])
        XCTAssertEqual(Set(restored.splits[1].tagIDs), [childTag.id])
        XCTAssertNoThrow(try restored.validate())
    }

    func testPortfolioFIFOUsesFixedPointLotsAndRejectsNegativeHoldings() throws {
        XCTAssertEqual(try SecurityQuantity(parsing: "12,500001").microUnits, 12_500_001)
        let context = try TestDatabase()
        let depot = FinanceAccount(
            id: UUID(), name: "Depot", institution: "", type: .investment,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(depot)
        let security = Security(
            id: UUID(), name: "Test ETF", shortName: "ETF",
            isin: "IE00TEST00001", wkn: "TEST01", ticker: "TEST",
            type: .etf, currency: "EUR", exchange: "Xetra",
            priceDecimals: 2, allowsShort: false, isActive: true, note: ""
        )
        try context.store.saveSecurity(security)
        let classes = try context.store.assetClasses()
        XCTAssertGreaterThanOrEqual(classes.count, 2)
        XCTAssertThrowsError(
            try context.store.replaceAllocations(
                securityID: security.id,
                values: [(classes[0].id, 6_000), (classes[1].id, 3_999)]
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .allocationMismatch(9_999))
        }
        try context.store.replaceAllocations(
            securityID: security.id,
            values: [(classes[0].id, 6_000), (classes[1].id, 4_000)]
        )
        XCTAssertEqual(
            try context.store.allocations(securityID: security.id)
                .reduce(0) { $0 + $1.basisPoints },
            10_000
        )

        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_710_000_000)
        try context.store.recordPurchase(
            accountID: depot.id, securityID: security.id, date: firstDate,
            quantityMicro: 10_000_000, priceMinor: 10_000, feesMinor: 1_000
        )
        try context.store.recordPurchase(
            accountID: depot.id, securityID: security.id, date: secondDate,
            quantityMicro: 5_000_000, priceMinor: 12_000, feesMinor: 500
        )
        try context.store.recordSale(
            accountID: depot.id, securityID: security.id, date: Date(),
            quantityMicro: 12_000_000, priceMinor: 15_000, feesMinor: 1_000
        )
        let lots = try context.store.portfolioLots(
            accountID: depot.id, securityID: security.id
        )
        XCTAssertEqual(lots[0].remainingQuantityMicro, 0)
        XCTAssertEqual(lots[0].remainingCostMinor, 0)
        XCTAssertEqual(lots[1].remainingQuantityMicro, 3_000_000)
        XCTAssertEqual(lots[1].remainingCostMinor, 36_300)
        let sale = try XCTUnwrap(
            context.store.securityTrades().first { $0.type == .sell }
        )
        XCTAssertEqual(sale.realizedGainMinor, 53_800)
        try context.store.saveSecurityPrice(
            securityID: security.id, date: Date(), priceMinor: 14_000,
            currency: "EUR", source: "Test"
        )
        let position = try XCTUnwrap(context.store.portfolioPositions().first)
        XCTAssertEqual(position.quantityMicro, 3_000_000)
        XCTAssertEqual(position.costBasisMinor, 36_300)
        XCTAssertEqual(position.marketValueMinor, 42_000)
        XCTAssertEqual(position.unrealizedGainMinor, 5_700)

        XCTAssertThrowsError(
            try context.store.recordSale(
                accountID: depot.id, securityID: security.id, date: Date(),
                quantityMicro: 4_000_000, priceMinor: 15_000, feesMinor: 0
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .insufficientQuantity)
        }
        XCTAssertEqual(
            try context.store.portfolioLots(
                accountID: depot.id, securityID: security.id
            ).reduce(0) { $0 + $1.remainingQuantityMicro },
            3_000_000
        )
    }

    func testLoanScheduleUsesVersionedRatesExtraPaymentsAndAssetEquity() throws {
        let context = try TestDatabase()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let disbursement = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))
        )
        let firstPayment = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 12))
        )
        let secondPayment = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))
        )
        let thirdPayment = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 12))
        )
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let loan = FinanceLoan(
            id: UUID(), name: "Testdarlehen", lender: "Testbank",
            principalMinor: 1_200_000, disbursementDate: disbursement,
            firstPaymentDate: firstPayment, fixedRateUntil: nil,
            termMonths: 12, installmentMinor: 100_000,
            regularFeeMinor: 100, dueDay: 1,
            linkedAccountID: account.id, currency: "EUR",
            note: "", isActive: true
        )
        try context.store.saveLoan(loan)
        try context.store.saveLoanInterestRate(
            LoanInterestRate(
                id: UUID(), loanID: loan.id, annualBasisPoints: 600,
                effectiveFrom: disbursement, note: "Ausgangszins"
            )
        )
        try context.store.saveLoanInterestRate(
            LoanInterestRate(
                id: UUID(), loanID: loan.id, annualBasisPoints: 300,
                effectiveFrom: thirdPayment, note: "Zinsänderung"
            )
        )
        try context.store.saveLoanExtraPayment(
            LoanExtraPayment(
                id: UUID(), loanID: loan.id, paymentDate: secondPayment,
                amountMinor: 50_000, note: "Sondertilgung"
            )
        )

        let schedule = try context.store.loanSchedule(loanID: loan.id)
        XCTAssertEqual(schedule.count, 12)
        XCTAssertEqual(schedule[0].openingBalanceMinor, 1_200_000)
        XCTAssertEqual(schedule[0].interestMinor, 6_000)
        XCTAssertEqual(schedule[0].feeMinor, 100)
        XCTAssertEqual(schedule[0].principalMinor, 93_900)
        XCTAssertEqual(schedule[0].closingBalanceMinor, 1_106_100)
        XCTAssertEqual(schedule[1].extraPaymentMinor, 50_000)
        XCTAssertEqual(schedule[2].annualBasisPoints, 300)
        XCTAssertEqual(
            schedule.reduce(Int64.zero) { $0 + $1.principalMinor + $1.extraPaymentMinor }
                + (schedule.last?.closingBalanceMinor ?? 0),
            loan.principalMinor
        )

        let asset = PropertyAsset(
            id: UUID(), name: "Wohnung", type: .realEstate,
            purchaseDate: disbursement, purchaseValueMinor: 2_000_000,
            linkedLoanID: loan.id, location: "Berlin", note: "", isActive: true
        )
        try context.store.savePropertyAsset(asset)
        try context.store.saveAssetValuation(
            AssetValuation(
                id: UUID(), assetID: asset.id, valuationDate: secondPayment,
                valueMinor: 2_200_000, source: "Test", note: ""
            )
        )
        let position = try XCTUnwrap(
            context.store.propertyAssetPositions(asOf: secondPayment).first
        )
        XCTAssertEqual(position.currentValueMinor, 2_200_000)
        XCTAssertEqual(position.linkedLoanBalanceMinor, schedule[1].closingBalanceMinor)
        XCTAssertEqual(
            position.netEquityMinor,
            position.currentValueMinor - position.linkedLoanBalanceMinor
        )
        XCTAssertTrue(try context.store.integrityCheck())

        let invalidLoan = FinanceLoan(
            id: UUID(), name: "Nicht tragfähig", lender: loan.lender,
            principalMinor: loan.principalMinor,
            disbursementDate: loan.disbursementDate,
            firstPaymentDate: loan.firstPaymentDate,
            fixedRateUntil: nil, termMonths: loan.termMonths,
            installmentMinor: 100, regularFeeMinor: loan.regularFeeMinor,
            dueDay: loan.dueDay, linkedAccountID: loan.linkedAccountID,
            currency: loan.currency, note: "", isActive: true
        )
        XCTAssertThrowsError(
            try LoanAmortizationEngine.schedule(
                loan: invalidLoan,
                rates: [
                    LoanInterestRate(
                        id: UUID(), loanID: invalidLoan.id,
                        annualBasisPoints: 600, effectiveFrom: disbursement, note: ""
                    )
                ],
                extraPayments: [],
                calendar: calendar
            )
        )
    }

    func testContractsCalculateDeadlinesAndInventoryPersistsInsuranceValues() throws {
        let context = try TestDatabase()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))
        )
        let reference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))
        )
        let expectedRenewal = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))
        )
        let expectedDeadline = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -90, to: expectedRenewal)
        )
        let contract = FinanceContract(
            id: UUID(), provider: "Muster Telekom", contractNumber: "4711",
            name: "Internet", type: .telecommunications, startDate: start,
            initialTermMonths: 12, renewalMonths: 12,
            cancellationNoticeDays: 90, amountMinor: 3_499,
            frequency: .monthly, accountID: nil, categoryID: nil,
            reminderDays: 30, note: "", isActive: true
        )
        XCTAssertEqual(contract.annualCostMinor, 41_988)
        XCTAssertEqual(
            contract.nextRenewal(after: reference, calendar: calendar),
            expectedRenewal
        )
        XCTAssertEqual(
            contract.cancellationDeadline(after: reference, calendar: calendar),
            expectedDeadline
        )
        try context.store.saveContract(contract)
        XCTAssertEqual(try context.store.contracts(), [contract])

        let item = InventoryItem(
            id: UUID(), name: "Laptop", category: .electronics,
            room: "Arbeitszimmer", purchaseDate: start,
            purchasePriceMinor: 249_900, currentValueMinor: 175_000,
            insuranceValueMinor: 249_900, retailer: "Fachhandel",
            serialNumber: "TEST-123", warrantyEnd: expectedRenewal,
            note: "Test", isActive: true
        )
        try context.store.saveInventoryItem(item)
        XCTAssertEqual(try context.store.inventoryItems(), [item])
        XCTAssertEqual(
            try context.store.inventoryItems().reduce(Int64.zero) {
                $0 + $1.insuranceValueMinor
            },
            249_900
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testCategoryHierarchyRejectsCyclesAndPersistsSubcategories() throws {
        let context = try TestDatabase()
        let root = try XCTUnwrap(
            context.store.categories().first { $0.name == "Lebensmittel" }
        )
        let child = FinanceCategory(
            id: UUID(), parentID: root.id, name: "Supermarkt",
            kind: root.kind, color: "green", isActive: true
        )
        let grandchild = FinanceCategory(
            id: UUID(), parentID: child.id, name: "Bio",
            kind: root.kind, color: "teal", isActive: true
        )
        try context.store.saveCategory(child)
        try context.store.saveCategory(grandchild)
        let restored = try context.store.categories()
        XCTAssertEqual(restored.first { $0.id == child.id }?.parentID, root.id)
        XCTAssertEqual(restored.first { $0.id == grandchild.id }?.parentID, child.id)

        var cyclicRoot = root
        cyclicRoot.parentID = grandchild.id
        XCTAssertThrowsError(try context.store.saveCategory(cyclicRoot))

        let incomeRoot = try XCTUnwrap(
            restored.first { $0.kind == .income && $0.parentID == nil }
        )
        var wrongKind = child
        wrongKind.parentID = incomeRoot.id
        XCTAssertThrowsError(try context.store.saveCategory(wrongKind))

        XCTAssertEqual(
            try context.store.categories().first { $0.id == root.id }?.parentID,
            nil
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    @MainActor
    func testRegisterCategoryDisplayUsesCompletePathAndAllSplitPaths() throws {
        let context = try TestDatabase()
        let root = try XCTUnwrap(
            context.store.categories().first { $0.name == "Lebensmittel" }
        )
        let child = FinanceCategory(
            id: UUID(), parentID: root.id, name: "Supermarkt",
            kind: root.kind, color: "green", isActive: true
        )
        let leaf = FinanceCategory(
            id: UUID(), parentID: child.id, name: "Bio",
            kind: root.kind, color: "teal", isActive: true
        )
        try context.store.saveCategory(child)
        try context.store.saveCategory(leaf)
        let appStore = FinanceAppStore(repository: context.store)
        let plain = FinanceTransaction(
            id: UUID(), accountID: UUID(), bookingDate: .now, valueDate: nil,
            payee: "", purpose: "", categoryID: leaf.id,
            amountMinor: -1_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        XCTAssertEqual(
            appStore.transactionCategoryPath(plain),
            "Lebensmittel › Supermarkt › Bio"
        )

        var split = plain
        split.categoryID = nil
        split.splits = [
            FinanceSplit(
                id: UUID(), categoryID: leaf.id, amountMinor: -700,
                memo: "", sortOrder: 0
            ),
            FinanceSplit(
                id: UUID(), categoryID: root.id, amountMinor: -300,
                memo: "", sortOrder: 1
            )
        ]
        XCTAssertEqual(
            appStore.transactionCategoryPath(split),
            "Split: Lebensmittel › Supermarkt › Bio · Lebensmittel"
        )
    }

    func testRichAccountMetadataGroupsAndValidationRoundTrip() throws {
        let context = try TestDatabase()
        XCTAssertEqual(try context.store.accountGroups().count, 9)
        let group = AccountGroup(
            id: UUID(), name: "Tägliche Finanzen", sortOrder: 1, isActive: true
        )
        try context.store.saveAccountGroup(group)
        var accountCalendar = Calendar(identifier: .gregorian)
        accountCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let openingDate = try XCTUnwrap(
            accountCalendar.date(
                from: DateComponents(year: 2020, month: 1, day: 15)
            )
        )
        let lastSync = Date(timeIntervalSince1970: 1_700_000_000)
        let account = FinanceAccount(
            id: UUID(), name: "Haushaltskonto", institution: "Musterbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 12_345,
            isHidden: false, isClosed: false, sortOrder: 2,
            shortName: "Haushalt", description: "Gemeinsame Ausgaben",
            groupID: group.id, iban: "DE89 3704 0044 0532 0130 00",
            bic: "COBADEFFXXX", accountNumberMasked: "•••• 1300",
            ownerName: "Testhaushalt", openingDate: openingDate,
            creditLimitMinor: 200_000, isOnline: true,
            includeNetWorth: true, includeBudget: true,
            includeReports: false, includeForecast: true,
            lastSyncAt: lastSync, lastBankBalanceMinor: 54_321,
            syncStatus: .ready
        )
        try context.store.saveAccount(account)
        let restored = try XCTUnwrap(
            context.store.accounts().first { $0.id == account.id }
        )
        XCTAssertEqual(restored.name, "Haushaltskonto")
        XCTAssertEqual(restored.groupID, group.id)
        XCTAssertEqual(restored.iban, "DE89370400440532013000")
        XCTAssertEqual(restored.creditLimitMinor, 200_000)
        XCTAssertEqual(restored.lastBankBalanceMinor, 54_321)
        XCTAssertEqual(restored.syncStatus, .ready)
        XCTAssertFalse(restored.includeReports)
        let restoredDate = try XCTUnwrap(restored.openingDate)
        let restoredComponents = Calendar.current.dateComponents(
            [.year, .month, .day], from: restoredDate
        )
        XCTAssertEqual(restoredComponents.year, 2020)
        XCTAssertEqual(restoredComponents.month, 1)
        XCTAssertEqual(restoredComponents.day, 15)
        let category = try XCTUnwrap(context.store.categories().first)
        try context.store.saveTransaction(
            FinanceTransaction(
                id: UUID(), accountID: account.id, bookingDate: openingDate,
                valueDate: nil, payee: "Test", purpose: "Auswertung",
                categoryID: category.id, amountMinor: -1_000, currency: "EUR",
                status: .booked, memo: "", reference: "", transferID: nil,
                importFingerprint: nil, splits: []
            )
        )
        XCTAssertTrue(try context.store.categoryReport().isEmpty)
        var included = restored
        included.includeReports = true
        try context.store.saveAccount(included)
        XCTAssertEqual(try context.store.categoryReport().count, 1)

        var invalid = account
        invalid.iban = "DE001234"
        XCTAssertThrowsError(try context.store.saveAccount(invalid)) { error in
            XCTAssertEqual(error as? FinanceError, .invalidIBAN)
        }
        XCTAssertEqual(try context.store.accounts().count, 1)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testMigration10To11PreservesExistingAccountAndAddsDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-migration-10-11-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.qdata")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let fileID = UUID()
        let accountID = UUID()
        let legacySQL = """
        CREATE TABLE finance_files (
            id TEXT PRIMARY KEY,name TEXT NOT NULL,base_currency TEXT NOT NULL,
            locale TEXT NOT NULL,time_zone TEXT NOT NULL,created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE accounts (
            id TEXT PRIMARY KEY,
            finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
            name TEXT NOT NULL,institution TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL,currency TEXT NOT NULL,
            opening_balance_minor INTEGER NOT NULL,
            is_hidden INTEGER NOT NULL DEFAULT 0,
            is_closed INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
            version INTEGER NOT NULL DEFAULT 1
        );
        INSERT INTO finance_files VALUES(
            '\(fileID.uuidString)','Altbestand','EUR','de-DE','Europe/Berlin',
            '2025-01-01T00:00:00Z','2025-01-01T00:00:00Z',1
        );
        INSERT INTO accounts VALUES(
            '\(accountID.uuidString)','\(fileID.uuidString)','Bestandskonto',
            'Altbank','checking','EUR',12345,0,0,4,
            '2025-01-01T00:00:00Z','2025-01-01T00:00:00Z',1
        );
        PRAGMA user_version=10;
        """
        var message: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(sqlite3_exec(database, legacySQL, nil, nil, &message), SQLITE_OK)
        if let message { sqlite3_free(message) }
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        let account = try XCTUnwrap(migrated.accounts().first)
        XCTAssertEqual(account.id, accountID)
        XCTAssertEqual(account.name, "Bestandskonto")
        XCTAssertEqual(account.openingBalanceMinor, 12_345)
        XCTAssertEqual(account.creditLimitMinor, 0)
        XCTAssertTrue(account.includeNetWorth)
        XCTAssertTrue(account.includeBudget)
        XCTAssertTrue(account.includeReports)
        XCTAssertTrue(account.includeForecast)
        XCTAssertEqual(account.syncStatus, .offline)
        let groups = try migrated.accountGroups()
        XCTAssertEqual(groups.count, 9)
        XCTAssertEqual(
            groups.first { $0.id == account.groupID }?.name,
            "Bankkonten"
        )
        XCTAssertTrue(try migrated.integrityCheck())
    }

    @MainActor
    func testNetWorthNeverAddsDifferentCurrenciesWithoutFXRate() throws {
        let context = try TestDatabase()
        let euro = FinanceAccount(
            id: UUID(), name: "Eurokonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let dollar = FinanceAccount(
            id: UUID(), name: "Dollarkonto", institution: "",
            type: .foreignCurrency, currency: "USD", openingBalanceMinor: 99_999,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(euro)
        try context.store.saveAccount(dollar)
        let appStore = FinanceAppStore(repository: context.store)
        XCTAssertEqual(appStore.fileInfo?.baseCurrency, "EUR")
        XCTAssertEqual(appStore.totalBalanceMinor, 10_000)
    }

    @MainActor
    func testRunningBalancesStayPerAccountAndIgnoreCancelledTransactions() throws {
        let context = try TestDatabase()
        let euro = FinanceAccount(
            id: UUID(), name: "Eurokonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let dollar = FinanceAccount(
            id: UUID(), name: "Dollarkonto", institution: "",
            type: .foreignCurrency, currency: "USD", openingBalanceMinor: 20_000,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(euro)
        try context.store.saveAccount(dollar)
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_086_400)
        let euroFirst = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: firstDate, valueDate: nil,
            payee: "", purpose: "", categoryID: nil,
            amountMinor: -1_500, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        let euroCancelled = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: secondDate, valueDate: nil,
            payee: "", purpose: "", categoryID: nil,
            amountMinor: -9_999, currency: "EUR", status: .cancelled,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        let dollarValue = FinanceTransaction(
            id: UUID(), accountID: dollar.id, bookingDate: firstDate, valueDate: nil,
            payee: "", purpose: "", categoryID: nil,
            amountMinor: 2_500, currency: "USD", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(euroFirst)
        try context.store.saveTransaction(euroCancelled)
        try context.store.saveTransaction(dollarValue)
        let appStore = FinanceAppStore(repository: context.store)
        let balances = appStore.runningBalances()
        XCTAssertEqual(balances[euroFirst.id], 8_500)
        XCTAssertEqual(balances[euroCancelled.id], 8_500)
        XCTAssertEqual(balances[dollarValue.id], 22_500)
    }
}

private final class TestDatabase {
    let directory: URL
    let store: SQLiteFinanceStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("finanzverwalter-tests-\(UUID().uuidString)", isDirectory: true)
        store = try SQLiteFinanceStore(fileURL: directory.appendingPathComponent("test.qdata"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
