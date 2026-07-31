import XCTest
import SQLite3
import PDFKit
@testable import FinanzVerwalter

final class FinanzVerwalterTests: XCTestCase {
    func testGermanMoneyParsingUsesMinorUnitsWithoutBinaryFloat() throws {
        XCTAssertEqual(try Money(parsing: "1.234,56 €").minorUnits, 123_456)
        XCTAssertEqual(try Money(parsing: "-0,015").minorUnits, -2)
        XCTAssertEqual(try Money(parsing: "0,005").minorUnits, 0)
    }

    func testVATCalculatorRoundsPerLineAndValidatesManualTax() throws {
        XCTAssertEqual(
            try VATCalculator.automatic(
                grossMinor: 11_900,
                rateBasisPoints: 1_900
            ),
            VATBreakdown(
                grossMinor: 11_900,
                netMinor: 10_000,
                taxMinor: 1_900
            )
        )
        XCTAssertEqual(
            try VATCalculator.automatic(
                grossMinor: -11_900,
                rateBasisPoints: 1_900
            ),
            VATBreakdown(
                grossMinor: -11_900,
                netMinor: -10_000,
                taxMinor: -1_900
            )
        )
        XCTAssertEqual(
            try VATCalculator.automatic(grossMinor: 999, rateBasisPoints: 0),
            VATBreakdown(grossMinor: 999, netMinor: 999, taxMinor: 0)
        )
        XCTAssertEqual(try VATCalculator.basisPoints(parsing: "19,00 %"), 1_900)
        XCTAssertEqual(try VATCalculator.basisPoints(parsing: "0"), 0)
        XCTAssertThrowsError(
            try VATCalculator.manual(grossMinor: -1_000, taxMinor: 190)
        )
        let mixedReceipt = try VATCalculator.receipt([
            VATCalculator.automatic(grossMinor: -11_900, rateBasisPoints: 1_900),
            VATCalculator.automatic(grossMinor: -10_700, rateBasisPoints: 700)
        ])
        XCTAssertEqual(
            mixedReceipt,
            VATBreakdown(
                grossMinor: -22_600,
                netMinor: -20_000,
                taxMinor: -2_600
            )
        )
    }

    func testVATCodesCategoryTaxAssignmentAndMixedSplitRoundTrip() throws {
        let context = try TestDatabase()
        let seededCodes = try context.store.vatCodes()
        XCTAssertEqual(Set(seededCodes.map(\.rateBasisPoints)), [0, 700, 1_900])
        let ownZero = VATCode(
            id: UUID(),
            name: "Eigener steuerfreier Umsatz",
            rateBasisPoints: 0,
            description: "Nicht auf den Standardschlüssel umleiten",
            isActive: true
        )
        try context.store.saveVATCode(ownZero)
        XCTAssertEqual(
            try context.store.vatCodes().filter { $0.rateBasisPoints == 0 }.count,
            2
        )
        let category = FinanceCategory(
            id: UUID(),
            parentID: nil,
            name: "Betriebliche Leistung",
            kind: .income,
            color: "green",
            isActive: true,
            description: "Testkategorie",
            isBudgetable: false,
            defaultVATCodeID: ownZero.id,
            germanTaxLine: "EÜR · Betriebseinnahmen",
            usTaxLine: "Schedule C"
        )
        try context.store.saveCategory(category)
        let restoredCategory = try XCTUnwrap(
            context.store.categories().first { $0.id == category.id }
        )
        XCTAssertEqual(restoredCategory.defaultVATCodeID, ownZero.id)
        XCTAssertEqual(restoredCategory.germanTaxLine, "EÜR · Betriebseinnahmen")
        XCTAssertFalse(restoredCategory.isBudgetable)

        let account = FinanceAccount(
            id: UUID(), name: "Geschäft", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let code19 = try XCTUnwrap(
            seededCodes.first { $0.rateBasisPoints == 1_900 }
        )
        let code7 = try XCTUnwrap(
            seededCodes.first { $0.rateBasisPoints == 700 }
        )
        let line19 = try VATCalculator.automatic(
            grossMinor: -11_900,
            rateBasisPoints: code19.rateBasisPoints
        )
        let line7 = try VATCalculator.automatic(
            grossMinor: -10_700,
            rateBasisPoints: code7.rateBasisPoints
        )
        let receipt = try VATCalculator.receipt([line19, line7])
        let value = FinanceTransaction(
            id: UUID(),
            accountID: account.id,
            bookingDate: .now,
            valueDate: .now,
            payee: "Lieferant",
            purpose: "Gemischter Beleg",
            categoryID: nil,
            amountMinor: receipt.grossMinor,
            currency: "EUR",
            status: .booked,
            memo: "",
            reference: "",
            transferID: nil,
            importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: nil,
                    amountMinor: line19.grossMinor, memo: "19 %",
                    sortOrder: 0, vatCodeID: code19.id,
                    vatMode: .automatic, netMinor: line19.netMinor,
                    taxMinor: line19.taxMinor
                ),
                FinanceSplit(
                    id: UUID(), categoryID: nil,
                    amountMinor: line7.grossMinor, memo: "7 %",
                    sortOrder: 1, vatCodeID: code7.id,
                    vatMode: .manual, netMinor: line7.netMinor,
                    taxMinor: line7.taxMinor
                )
            ],
            vatCodeID: nil,
            vatMode: .none,
            netMinor: receipt.netMinor,
            taxMinor: receipt.taxMinor
        )
        try context.store.saveTransaction(value)
        let restored = try XCTUnwrap(
            context.store.transactions().first { $0.id == value.id }
        )
        XCTAssertEqual(restored.netMinor, -20_000)
        XCTAssertEqual(restored.taxMinor, -2_600)
        XCTAssertEqual(restored.splits.map(\.vatCodeID), [code19.id, code7.id])
        XCTAssertEqual(restored.splits.map(\.vatMode), [.automatic, .manual])
        let zeroBreakdown = try VATCalculator.automatic(
            grossMinor: 12_345,
            rateBasisPoints: ownZero.rateBasisPoints
        )
        let zeroTransaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: .now, payee: "Steuerfrei", purpose: "Eigener Nullsatz",
            categoryID: category.id, amountMinor: zeroBreakdown.grossMinor,
            currency: "EUR", status: .booked, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: [],
            vatCodeID: ownZero.id, vatMode: .automatic,
            netMinor: zeroBreakdown.netMinor, taxMinor: zeroBreakdown.taxMinor
        )
        try context.store.saveTransaction(zeroTransaction)
        let restoredZero = try XCTUnwrap(
            context.store.transactions().first { $0.id == zeroTransaction.id }
        )
        XCTAssertEqual(restoredZero.vatCodeID, ownZero.id)
        XCTAssertEqual(restoredZero.netMinor, 12_345)
        XCTAssertEqual(restoredZero.taxMinor, 0)
        XCTAssertTrue(try context.store.integrityCheck())
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
        _ = try context.store.commitImport(preview)
        XCTAssertThrowsError(try context.store.commitImport(preview)) { error in
            XCTAssertEqual(error as? FinanceError, .duplicateImport)
        }
        XCTAssertEqual(try context.store.transactions().count, 2)
    }

    func testImportMatcherUsesTieredEvidenceAndAvoidsAmbiguousAutoMatch() throws {
        let accountID = UUID()
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 30)
            )
        )
        let later = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 1, to: date)
        )
        let existing = FinanceTransaction(
            id: UUID(), accountID: accountID, bookingDate: date,
            valueDate: date, payee: "Stadtwerke München",
            purpose: "Abschlag Strom Juli", categoryID: nil,
            amountMinor: -12_345, currency: "EUR", status: .expected,
            memo: "", reference: "RE-4711", transferID: nil,
            importFingerprint: nil, splits: [],
            counterpartyIBAN: "DE89370400440532013000",
            endToEndID: "E2E-2026-4711"
        )
        let imported = FinanceTransaction(
            id: UUID(), accountID: accountID, bookingDate: later,
            valueDate: date, payee: "STADTWERKE MUENCHEN",
            purpose: "Strom Abschlag 07 2026", categoryID: nil,
            amountMinor: -12_345, currency: "EUR", status: .booked,
            memo: "", reference: "RE-4711", transferID: nil,
            importFingerprint: "paket-a", splits: [],
            origin: .fileImport,
            externalProvider: "DemoBank",
            externalTransactionID: "TX-1",
            counterpartyIBAN: "DE89 3704 0044 0532 0130 00",
            endToEndID: "E2E-2026-4711"
        )
        let assessment = try XCTUnwrap(
            ImportMatcher.assess(
                rows: [imported],
                against: [existing]
            )[imported.id]
        )
        let candidate = try XCTUnwrap(assessment.bestCandidate)
        XCTAssertGreaterThanOrEqual(
            candidate.score,
            ImportMatcher.automaticThreshold
        )
        XCTAssertEqual(candidate.tier, .strongFingerprint)
        XCTAssertEqual(
            assessment.suggestedResolution,
            .match(existing.id)
        )

        var equallyStrong = existing
        equallyStrong = FinanceTransaction(
            id: UUID(), accountID: equallyStrong.accountID,
            bookingDate: equallyStrong.bookingDate,
            valueDate: equallyStrong.valueDate,
            payee: equallyStrong.payee, purpose: equallyStrong.purpose,
            categoryID: nil, amountMinor: equallyStrong.amountMinor,
            currency: equallyStrong.currency, status: .expected,
            memo: "", reference: equallyStrong.reference,
            transferID: nil, importFingerprint: nil, splits: [],
            counterpartyIBAN: equallyStrong.counterpartyIBAN,
            endToEndID: equallyStrong.endToEndID
        )
        let ambiguous = try XCTUnwrap(
            ImportMatcher.assess(
                rows: [imported],
                against: [existing, equallyStrong]
            )[imported.id]
        )
        XCTAssertEqual(ambiguous.candidates.count, 2)
        XCTAssertEqual(ambiguous.suggestedResolution, .importNew)

        var outsideDefaultWindow = imported
        outsideDefaultWindow.bookingDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 6, to: date)
        )
        outsideDefaultWindow.valueDate = outsideDefaultWindow.bookingDate
        XCTAssertTrue(
            try XCTUnwrap(
                ImportMatcher.assess(
                    rows: [outsideDefaultWindow],
                    against: [existing]
                )[outsideDefaultWindow.id]
            ).candidates.isEmpty
        )
        let configuredPreview = ImportPreview(
            rows: [outsideDefaultWindow],
            rejectedRows: [],
            fingerprint: "konfiguriertes-fenster"
        ).matched(
            against: [existing],
            dateWindowDays: 7
        )
        XCTAssertEqual(configuredPreview.matchDateWindowDays, 7)
        XCTAssertFalse(
            try XCTUnwrap(
                configuredPreview.matches[outsideDefaultWindow.id]
            ).candidates.isEmpty
        )

        var exactDuplicate = existing
        exactDuplicate.externalProvider = "DemoBank"
        exactDuplicate.externalTransactionID = "TX-1"
        let incompatible = FinanceTransaction(
            id: UUID(), accountID: accountID, bookingDate: later,
            valueDate: later, payee: "Abweichend", purpose: "",
            categoryID: nil, amountMinor: -99, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: "paket-b", splits: [],
            origin: .fileImport, externalProvider: "DemoBank",
            externalTransactionID: "TX-1"
        )
        let exactAssessment = try XCTUnwrap(
            ImportMatcher.assess(
                rows: [incompatible],
                against: [exactDuplicate]
            )[incompatible.id]
        )
        XCTAssertEqual(exactAssessment.bestCandidate?.score, 100)
        XCTAssertEqual(
            exactAssessment.bestCandidate?.tier,
            .exactExternalID
        )
        XCTAssertFalse(
            try XCTUnwrap(exactAssessment.bestCandidate)
                .isFinanciallyCompatible
        )
        XCTAssertEqual(exactAssessment.suggestedResolution, .skip)
    }

    func testCSVMatchingMergesBankIdentityWithoutLosingLocalEnrichment() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = try XCTUnwrap(
            try context.store.categories().first
        )
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 7, day: 30)
            )
        )
        let existing = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: date,
            valueDate: date, payee: "Stadtwerke",
            purpose: "Erwarteter Abschlag", categoryID: category.id,
            amountMinor: -12_345, currency: "EUR", status: .expected,
            memo: "Lokale Notiz bleibt", reference: "RE-4711",
            transferID: nil, importFingerprint: nil, splits: [],
            counterpartyIBAN: "DE89370400440532013000",
            endToEndID: "E2E-4711"
        )
        try context.store.saveTransaction(existing)

        let firstData = Data(
            """
            Datum;Wertstellung;Empfänger;Verwendungszweck;Betrag;Referenz;Provider;Transaktions-ID;IBAN;End-to-End-ID;Saldo danach
            31.07.2026;31.07.2026;Stadtwerke München;Abschlag Strom Juli;-123,45;RE-4711;Testbank;TX-4711;DE89370400440532013000;E2E-4711;987,65
            """.utf8
        )
        let rawPreview = try CSVFinanceImporter.preview(
            data: firstData,
            account: account
        )
        let preview = rawPreview.matched(
            against: try context.store.transactions()
        )
        XCTAssertEqual(
            preview.matches[rawPreview.rows[0].id]?.suggestedResolution,
            .match(existing.id)
        )
        let result = try context.store.commitImport(preview)
        XCTAssertEqual(
            result,
            ImportCommitResult(
                importedCount: 0,
                matchedCount: 1,
                skippedCount: 0
            )
        )
        var restored = try XCTUnwrap(
            try context.store.transactions().first
        )
        XCTAssertEqual(try context.store.transactions().count, 1)
        XCTAssertEqual(restored.id, existing.id)
        XCTAssertEqual(restored.categoryID, category.id)
        XCTAssertEqual(restored.memo, "Lokale Notiz bleibt")
        XCTAssertEqual(restored.status, .booked)
        XCTAssertEqual(restored.origin, .bankDownload)
        XCTAssertEqual(restored.externalProvider, "Testbank")
        XCTAssertEqual(restored.externalTransactionID, "TX-4711")
        XCTAssertEqual(restored.endToEndID, "E2E-4711")
        XCTAssertEqual(restored.bankBalanceAfterMinor, 98_765)

        let changedPackage = Data(
            """
            Datum;Empfänger;Verwendungszweck;Betrag;Provider;Transaktions-ID
            31.07.2026;Stadtwerke München;Gleicher Umsatz, andere Datei;-123,45;Testbank;TX-4711
            """.utf8
        )
        let duplicateRaw = try CSVFinanceImporter.preview(
            data: changedPackage,
            account: account
        )
        let duplicate = duplicateRaw.matched(
            against: try context.store.transactions()
        )
        XCTAssertEqual(
            duplicate.matches[duplicateRaw.rows[0].id]?.suggestedResolution,
            .skip
        )
        let skipped = try context.store.commitImport(duplicate)
        XCTAssertEqual(skipped.skippedCount, 1)
        XCTAssertEqual(try context.store.transactions().count, 1)

        let forcedRaw = try CSVFinanceImporter.preview(
            data: changedPackage + Data("\n".utf8),
            account: account
        )
        let forced = forcedRaw.matched(
            against: try context.store.transactions()
        )
        XCTAssertThrowsError(
            try context.store.commitImport(
                forced,
                resolutions: [forced.rows[0].id: .importNew]
            )
        ) { error in
            guard
                let financeError = error as? FinanceError,
                case .invalidImportResolution = financeError
            else {
                return XCTFail("Unerwarteter Fehler: \(error)")
            }
        }
        restored = try XCTUnwrap(try context.store.transactions().first)
        XCTAssertEqual(restored.externalTransactionID, "TX-4711")
        XCTAssertTrue(try context.store.integrityCheck())
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

        _ = try context.store.commitQIFPackage(package)
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
        _ = try context.store.commitQIFPackage(package)
        XCTAssertEqual(
            try context.store.transactions().count,
            package.importPreview.rows.count
        )
        XCTAssertGreaterThanOrEqual(
            try context.store.accounts().count,
            package.accountsToCreate.count
        )
        let importedTransactions = try context.store.transactions()
        let report = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(),
            transactions: importedTransactions,
            accounts: try context.store.accounts(),
            categories: try context.store.categories(),
            tags: try context.store.tags()
        )
        let reportAmountsByTransaction = Dictionary(
            grouping: report.facts,
            by: \.transactionID
        ).mapValues { $0.reduce(Int64.zero) { $0 + $1.amountMinor } }
        for transaction in importedTransactions
            where transaction.status != .cancelled && transaction.transferID == nil {
            XCTAssertEqual(
                reportAmountsByTransaction[transaction.id],
                transaction.amountMinor,
                "Der Bericht muss jede reale QIF-Buchung genau einmal auswerten."
            )
        }
        XCTAssertFalse(report.groups.isEmpty)
        XCTAssertFalse(report.totals.isEmpty)
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

    func testReconciliationSelectsStatementItemsAdjustsAndRevertsLatestOnly() throws {
        let context = try TestDatabase()
        let calendar = Calendar(identifier: .gregorian)
        let statementDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 31))
        )
        let futureDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 2, day: 1))
        )
        let account = FinanceAccount(
            id: UUID(),
            name: "Auswahlkonto",
            institution: "",
            type: .checking,
            currency: "EUR",
            openingBalanceMinor: 10_000,
            isHidden: false,
            isClosed: false,
            sortOrder: 0
        )
        let booked = FinanceTransaction(
            id: UUID(),
            accountID: account.id,
            bookingDate: statementDate,
            valueDate: nil,
            payee: "Miete",
            purpose: "Januar",
            categoryID: nil,
            amountMinor: -2_000,
            currency: "EUR",
            status: .booked,
            memo: "",
            reference: "",
            transferID: nil,
            importFingerprint: nil,
            splits: []
        )
        let cleared = FinanceTransaction(
            id: UUID(),
            accountID: account.id,
            bookingDate: statementDate,
            valueDate: nil,
            payee: "Erstattung",
            purpose: "Januar",
            categoryID: nil,
            amountMinor: 500,
            currency: "EUR",
            status: .cleared,
            memo: "",
            reference: "",
            transferID: nil,
            importFingerprint: nil,
            splits: []
        )
        let future = FinanceTransaction(
            id: UUID(),
            accountID: account.id,
            bookingDate: futureDate,
            valueDate: nil,
            payee: "Später",
            purpose: "Februar",
            categoryID: nil,
            amountMinor: 100,
            currency: "EUR",
            status: .booked,
            memo: "",
            reference: "",
            transferID: nil,
            importFingerprint: nil,
            splits: []
        )
        try context.store.saveAccount(account)
        try context.store.saveTransaction(booked)
        try context.store.saveTransaction(cleared)
        try context.store.saveTransaction(future)

        let firstSnapshot = try context.store.reconciliationSnapshot(
            account: account,
            statementDate: statementDate
        )
        XCTAssertEqual(firstSnapshot.startingBalanceMinor, 10_000)
        XCTAssertEqual(
            Set(firstSnapshot.candidates.map(\.id)),
            [booked.id, cleared.id]
        )
        XCTAssertEqual(
            firstSnapshot.differenceMinor(
                endingBalanceMinor: 8_000,
                selectedIDs: [booked.id]
            ),
            0
        )
        let first = try context.store.reconcile(
            account: account,
            endingBalanceMinor: 8_000,
            date: statementDate,
            selectedTransactionIDs: [booked.id],
            createAdjustment: false
        )
        var transactions = try context.store.transactions(accountID: account.id)
        XCTAssertEqual(
            transactions.first(where: { $0.id == booked.id })?.status,
            .reconciled
        )
        XCTAssertEqual(
            transactions.first(where: { $0.id == cleared.id })?.status,
            .cleared
        )
        XCTAssertEqual(
            transactions.first(where: { $0.id == future.id })?.status,
            .booked
        )

        let secondSnapshot = try context.store.reconciliationSnapshot(
            account: account,
            statementDate: statementDate
        )
        XCTAssertEqual(secondSnapshot.startingBalanceMinor, 8_000)
        XCTAssertEqual(secondSnapshot.candidates.map(\.id), [cleared.id])
        XCTAssertThrowsError(
            try context.store.reconcile(
                account: account,
                endingBalanceMinor: 8_600,
                date: statementDate,
                selectedTransactionIDs: [cleared.id],
                createAdjustment: false
            )
        ) { error in
            XCTAssertEqual(
                error as? FinanceError,
                .reconciliationDifference(100)
            )
        }
        let second = try context.store.reconcile(
            account: account,
            endingBalanceMinor: 8_600,
            date: statementDate,
            selectedTransactionIDs: [cleared.id],
            createAdjustment: true
        )
        let adjustmentID = try XCTUnwrap(second.adjustmentTransactionID)
        transactions = try context.store.transactions(accountID: account.id)
        XCTAssertEqual(
            transactions.first(where: { $0.id == cleared.id })?.status,
            .reconciled
        )
        let adjustment = try XCTUnwrap(
            transactions.first(where: { $0.id == adjustmentID })
        )
        XCTAssertEqual(adjustment.amountMinor, 100)
        XCTAssertEqual(adjustment.reference, "ABGLEICH")
        XCTAssertEqual(adjustment.status, .reconciled)

        var history = try context.store.reconciliations(accountID: account.id)
        XCTAssertEqual(history.count, 2)
        XCTAssertTrue(history.first(where: { $0.id == second.id })?.canRevert == true)
        XCTAssertTrue(history.first(where: { $0.id == first.id })?.canRevert == false)
        XCTAssertThrowsError(
            try context.store.revertReconciliation(
                id: first.id,
                accountID: account.id
            )
        )

        try context.store.revertReconciliation(
            id: second.id,
            accountID: account.id
        )
        transactions = try context.store.transactions(accountID: account.id)
        XCTAssertEqual(
            transactions.first(where: { $0.id == cleared.id })?.status,
            .cleared
        )
        XCTAssertEqual(
            transactions.first(where: { $0.id == adjustmentID })?.status,
            .cancelled
        )
        history = try context.store.reconciliations(accountID: account.id)
        XCTAssertNotNil(
            history.first(where: { $0.id == second.id })?.revertedAt
        )
        XCTAssertTrue(history.first(where: { $0.id == first.id })?.canRevert == true)
        XCTAssertThrowsError(
            try context.store.reconciliationSnapshot(
                account: account,
                statementDate: calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: statementDate
                ) ?? statementDate
            )
        )
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

        let storedRule = try XCTUnwrap(
            try context.store.categorizationRules().first
        )
        XCTAssertEqual(storedRule.id, rule.id)
        XCTAssertEqual(
            storedRule.effectiveExpression,
            rule.effectiveExpression
        )
        XCTAssertEqual(storedRule.effectiveActions, rule.effectiveActions)
        XCTAssertTrue(rule.matches(matching))
        XCTAssertFalse(rule.matches(protected))
        XCTAssertEqual(try context.store.applyCategorizationRule(rule), 1)
        let values = try context.store.transactions()
        XCTAssertEqual(values.first { $0.id == matching.id }?.categoryID, category.id)
        XCTAssertNil(values.first { $0.id == protected.id }?.categoryID)
    }

    func testNestedRulePreviewConflictSelectedApplyAndSafeUndo() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "",
            type: .checking, currency: "EUR",
            openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let categories = try context.store.categories()
        let food = try XCTUnwrap(
            categories.first { $0.name == "Lebensmittel" }
        )
        let housing = try XCTUnwrap(
            categories.first { $0.name == "Wohnen" }
        )
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 7, day: 31)
            )
        )
        let first = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: date,
            valueDate: date, payee: "Edeka Markt 12",
            purpose: "Kartenzahlung 4711", categoryID: nil,
            amountMinor: -5_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: [],
            counterpartyIBAN: "DE89370400440532013000",
            counterpartyBIC: "COBADEFFXXX",
            bookingText: "Kartenzahlung"
        )
        var second = first
        second = FinanceTransaction(
            id: UUID(), accountID: second.accountID,
            bookingDate: second.bookingDate, valueDate: second.valueDate,
            payee: "EDEKA City", purpose: "Kartenzahlung 4711",
            categoryID: nil, amountMinor: -2_500,
            currency: second.currency, status: .booked,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: [],
            counterpartyIBAN: second.counterpartyIBAN,
            counterpartyBIC: second.counterpartyBIC,
            bookingText: second.bookingText
        )
        try context.store.saveTransaction(first)
        try context.store.saveTransaction(second)
        let persistedFirst = try XCTUnwrap(
            try context.store.transactions().first { $0.id == first.id }
        )
        XCTAssertEqual(persistedFirst.counterpartyBIC, "COBADEFFXXX")
        XCTAssertEqual(persistedFirst.bookingText, "Kartenzahlung")

        let expression = RuleExpression.group(
            .all,
            [
                .condition(
                    RuleCondition(
                        field: .payee,
                        operation: .regex,
                        value: "^edeka"
                    )
                ),
                .group(
                    .any,
                    [
                        .condition(
                            RuleCondition(
                                field: .purpose,
                                operation: .contains,
                                value: "4711"
                            )
                        ),
                        .condition(
                            RuleCondition(
                                field: .counterpartyIBAN,
                                operation: .equals,
                                value: "DE89370400440532013000"
                            )
                        )
                    ]
                )
            ]
        )
        let rule = CategorizationRule(
            id: UUID(), name: "EDEKA vollständig", priority: 10,
            isActive: true, stopAfterMatch: true,
            payeeContains: "", purposeContains: "",
            minimumAmountMinor: nil, maximumAmountMinor: nil,
            categoryID: food.id,
            expression: expression,
            actions: [
                .setCategory(food.id),
                .normalizePayee("EDEKA"),
                .setMemo("Automatisch kategorisiert"),
                .replacePurpose(
                    search: "4711",
                    replacement: "****",
                    useRegex: false
                )
            ]
        )
        try context.store.saveCategorizationRule(rule)
        let stored = try XCTUnwrap(
            try context.store.categorizationRules().first {
                $0.id == rule.id
            }
        )
        XCTAssertEqual(stored.expression, expression)
        XCTAssertEqual(stored.actions, rule.actions)

        let invalidRegexRule = CategorizationRule(
            id: UUID(), name: "Ungültige Regex", priority: 11,
            isActive: true, stopAfterMatch: true,
            payeeContains: "", purposeContains: "",
            minimumAmountMinor: nil, maximumAmountMinor: nil,
            categoryID: food.id,
            expression: .condition(
                RuleCondition(
                    field: .purpose,
                    operation: .regex,
                    value: "["
                )
            ),
            actions: [.setCategory(food.id)]
        )
        XCTAssertThrowsError(
            try context.store.saveCategorizationRule(invalidRegexRule)
        )

        let splitRule = CategorizationRule(
            id: UUID(), name: "Regelsplit", priority: 12,
            isActive: true, stopAfterMatch: true,
            payeeContains: "", purposeContains: "",
            minimumAmountMinor: nil, maximumAmountMinor: nil,
            categoryID: food.id,
            expression: expression,
            actions: [
                .createSingleSplit(
                    categoryID: food.id,
                    memo: "Regelsplit"
                )
            ]
        )
        let splitValue = try RuleEngine.transformed(first, by: splitRule)
        XCTAssertNil(splitValue.categoryID)
        XCTAssertEqual(splitValue.splits.count, 1)
        XCTAssertEqual(splitValue.splits[0].amountMinor, first.amountMinor)
        XCTAssertEqual(splitValue.splits[0].categoryID, food.id)

        let preview = RuleEngine.preview(
            rule: stored,
            transactions: try context.store.transactions()
        )
        XCTAssertEqual(preview.count, 2)
        XCTAssertTrue(
            preview.allSatisfy {
                $0.after.categoryID == food.id
                    && $0.after.payee == "EDEKA"
                    && $0.after.memo == "Automatisch kategorisiert"
                    && $0.after.purpose == "Kartenzahlung ****"
            }
        )

        let conflicting = CategorizationRule(
            id: UUID(), name: "Andere Kategorie", priority: 20,
            isActive: true, stopAfterMatch: false,
            payeeContains: "edeka", purposeContains: "",
            minimumAmountMinor: nil, maximumAmountMinor: nil,
            categoryID: housing.id
        )
        XCTAssertEqual(
            RuleEngine.conflicts(
                rules: [stored, conflicting],
                transactions: try context.store.transactions()
            ).filter { $0.field == "category" }.count,
            2
        )

        let result = try context.store.applyCategorizationRule(
            stored,
            transactionIDs: [first.id]
        )
        XCTAssertEqual(result.changedCount, 1)
        var values = try context.store.transactions()
        let changed = try XCTUnwrap(values.first { $0.id == first.id })
        XCTAssertEqual(changed.categoryID, food.id)
        XCTAssertEqual(changed.payee, "EDEKA")
        XCTAssertEqual(changed.origin, .rule)
        XCTAssertNil(values.first { $0.id == second.id }?.categoryID)
        let undo = try XCTUnwrap(try context.store.latestRuleUndo())
        XCTAssertEqual(undo.id, result.runID)
        XCTAssertEqual(
            try context.store.undoRuleApplication(id: undo.id),
            1
        )
        values = try context.store.transactions()
        let restored = try XCTUnwrap(values.first { $0.id == first.id })
        XCTAssertEqual(restored.categoryID, first.categoryID)
        XCTAssertEqual(restored.payee, first.payee)
        XCTAssertEqual(restored.purpose, first.purpose)
        XCTAssertEqual(restored.memo, first.memo)
        XCTAssertEqual(restored.origin, first.origin)

        let secondRun = try context.store.applyCategorizationRule(
            stored,
            transactionIDs: [first.id]
        )
        var intervening = try XCTUnwrap(
            try context.store.transactions().first { $0.id == first.id }
        )
        intervening.memo = "Manuell nachbearbeitet"
        try context.store.saveTransaction(intervening)
        XCTAssertThrowsError(
            try context.store.undoRuleApplication(id: secondRun.runID)
        )
        XCTAssertEqual(
            try context.store.transactions().first {
                $0.id == first.id
            }?.memo,
            "Manuell nachbearbeitet"
        )
        XCTAssertTrue(try context.store.integrityCheck())
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

    func testStandingOrderMaterializationIsIdempotentAuditedAndWeekendSafe() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let saturday = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)
            )
        )
        let septemberFirst = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)
            )
        )
        let context = try TestDatabase()
        var account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 100_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.iban = "DE89370400440532013000"
        account.ownerName = "Testperson"
        try context.store.saveAccount(account)
        let now = Date()
        let standingOrder = StandingOrder(
            id: UUID(), accountID: account.id, name: "Monatlicher Abschlag",
            recipientName: "Stadtwerke", iban: "DE12500105170648489890",
            bic: "", amountMinor: 9_850, currency: "EUR",
            purpose: "Energieabschlag", nextExecutionDate: saturday,
            endDate: septemberFirst, frequency: .monthly,
            businessDayAdjustment: .nextWeekday, status: .active,
            createdAt: now, updatedAt: now
        )
        try context.store.saveStandingOrder(standingOrder)

        let persisted = try XCTUnwrap(context.store.standingOrders().first)
        XCTAssertEqual(persisted.id, standingOrder.id)
        XCTAssertEqual(persisted.status, .active)

        let first = try context.store.materializeStandingOrder(
            id: standingOrder.id, dueDate: saturday
        )
        XCTAssertEqual(first.type, .scheduledCreditTransfer)
        XCTAssertEqual(first.status, .draft)
        XCTAssertEqual(first.idempotencyKey, "standing:\(standingOrder.id.uuidString):2026-08-01")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: first.executionDate),
            DateComponents(year: 2026, month: 8, day: 3)
        )
        let retry = try context.store.materializeStandingOrder(
            id: standingOrder.id, dueDate: saturday
        )
        XCTAssertEqual(retry.id, first.id)
        XCTAssertEqual(try context.store.paymentOrders().count, 1)

        var advanced = try XCTUnwrap(context.store.standingOrders().first)
        XCTAssertEqual(
            calendar.dateComponents(
                [.year, .month, .day], from: advanced.nextExecutionDate
            ),
            DateComponents(year: 2026, month: 9, day: 1)
        )
        advanced.amountMinor = 10_500
        advanced.purpose = "Neuer Abschlag"
        try context.store.saveStandingOrder(advanced)
        let unchangedFirst = try XCTUnwrap(
            context.store.paymentOrders().first { $0.id == first.id }
        )
        XCTAssertEqual(unchangedFirst.amountMinor, 9_850)
        XCTAssertEqual(unchangedFirst.purpose, "Energieabschlag")

        var rewound = advanced
        rewound.nextExecutionDate = saturday
        XCTAssertThrowsError(try context.store.saveStandingOrder(rewound)) {
            XCTAssertEqual(
                $0 as? FinanceError,
                .invalidStandingOrder(
                    "Die nächste Fälligkeit muss nach allen bereits verarbeiteten Terminen liegen."
                )
            )
        }
        try context.store.skipStandingOrder(
            id: standingOrder.id, dueDate: advanced.nextExecutionDate
        )
        let completed = try XCTUnwrap(context.store.standingOrders().first)
        XCTAssertEqual(completed.status, .cancelled)
        let runs = try context.store.standingOrderRuns(
            standingOrderID: standingOrder.id
        )
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.map(\.status), [.skipped, .materialized])
        XCTAssertEqual(try context.store.paymentOrders().count, 1)
        XCTAssertThrowsError(
            try context.store.materializeStandingOrder(
                id: standingOrder.id, dueDate: septemberFirst
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .standingOrderRunFinalized)
        }
        XCTAssertThrowsError(
            try context.store.setStandingOrderStatus(
                id: standingOrder.id, to: .active
            )
        )
    }

    func testPain001ExportIsDeterministicEscapedAndUsesEPC2025Rules() throws {
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let orderID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        var account = FinanceAccount(
            id: accountID, name: "Geschäftskonto", institution: "Musterbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.iban = "DE89370400440532013000"
        account.ownerName = "Müller & Söhne"
        let executionDate = Pain001Exporter.gregorianDate(
            year: 2026, month: 8, day: 3
        )
        let creationDate = Pain001Exporter.gregorianDate(
            year: 2026, month: 7, day: 31
        )
        let order = PaymentOrder(
            id: orderID, accountID: accountID, type: .instantCreditTransfer,
            recipientName: "Stadtwerke <Nord>", iban: "DE12500105170648489890",
            bic: "INGDDEFFXXX", amountMinor: 123_456, currency: "EUR",
            executionDate: executionDate, purpose: "Abschlag & Vertrag 42",
            endToEndID: "E2E-42", status: .draft,
            idempotencyKey: "pain-test", bankReference: "",
            createdAt: creationDate, updatedAt: creationDate
        )

        let first = try Pain001Exporter.export(
            order: order, account: account, createdAt: creationDate,
            messageID: "MSG-2026-0001"
        )
        let second = try Pain001Exporter.export(
            order: order, account: account, createdAt: creationDate,
            messageID: "MSG-2026-0001"
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rulePackage, .epc2025)
        XCTAssertEqual(
            first.fileName,
            "pain.001-2026-08-03-BBBBBBBB.xml"
        )

        let document = try XMLDocument(data: first.data)
        XCTAssertEqual(
            document.rootElement()?.namespace(forPrefix: "")?.stringValue,
            Pain001RulePackage.epc2025.namespace
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='CtrlSum']"
            ).compactMap(\.stringValue),
            ["1234.56", "1234.56"]
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='LclInstrm']/*[local-name()='Cd']"
            ).first?.stringValue,
            "INST"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='DbtrAgt']//*[local-name()='Id']"
            ).first?.stringValue,
            "NOTPROVIDED"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='Cdtr']/*[local-name()='Nm']"
            ).first?.stringValue,
            "Stadtwerke <Nord>"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='Ustrd']"
            ).first?.stringValue,
            "Abschlag & Vertrag 42"
        )
        let rawXML = try XCTUnwrap(String(data: first.data, encoding: .utf8))
        XCTAssertTrue(rawXML.contains("Müller &amp; Söhne"))
        XCTAssertTrue(rawXML.contains("Stadtwerke &lt;Nord&gt;"))
        XCTAssertTrue(rawXML.contains("<ChrgBr>SLEV</ChrgBr>"))
        XCTAssertTrue(rawXML.contains("<ReqdExctnDt><Dt>2026-08-03</Dt>"))
        if let outputPath = ProcessInfo.processInfo.environment[
            "FINANZVERWALTER_PAIN001_OUTPUT"
        ] {
            try first.data.write(to: URL(fileURLWithPath: outputPath))
        }
    }

    func testPain001ExportRejectsUnsafeOrIncompleteSourceData() throws {
        let accountID = UUID()
        var account = FinanceAccount(
            id: accountID, name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.iban = "DE89370400440532013001"
        account.ownerName = "Testperson"
        let date = Pain001Exporter.gregorianDate(
            year: 2026, month: 8, day: 1
        )
        let order = PaymentOrder(
            id: UUID(), accountID: accountID, type: .sepaCreditTransfer,
            recipientName: "Empfänger", iban: "DE12500105170648489890",
            bic: "", amountMinor: 100, currency: "EUR",
            executionDate: date, purpose: "Test", endToEndID: "NOTPROVIDED",
            status: .draft, idempotencyKey: "invalid-source",
            bankReference: "", createdAt: date, updatedAt: date
        )
        XCTAssertThrowsError(
            try Pain001Exporter.export(
                order: order, account: account, createdAt: date
            )
        ) { error in
            XCTAssertEqual(
                error as? Pain001ExportError,
                .invalidDebtorIBAN
            )
        }

        account.iban = "DE89370400440532013000"
        var unsafe = order
        unsafe.endToEndID = "/nicht-erlaubt"
        XCTAssertThrowsError(
            try Pain001Exporter.export(
                order: unsafe, account: account, createdAt: date
            )
        ) { error in
            XCTAssertEqual(
                error as? Pain001ExportError,
                .invalidIdentifier("End-to-End-ID")
            )
        }

        unsafe.endToEndID = "NOTPROVIDED"
        unsafe.status = .unknown
        XCTAssertThrowsError(
            try Pain001Exporter.export(
                order: unsafe, account: account, createdAt: date
            )
        ) { error in
            XCTAssertEqual(
                error as? Pain001ExportError,
                .nonDraftOrder
            )
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
        CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            finance_file_id TEXT NOT NULL REFERENCES finance_files(id),
            parent_id TEXT,name TEXT NOT NULL,kind TEXT NOT NULL,
            color TEXT NOT NULL DEFAULT 'blue',
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
            version INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL DEFAULT '',
            booking_date TEXT NOT NULL
        );
        CREATE TABLE transaction_splits (id TEXT PRIMARY KEY);
        CREATE TABLE reconciliations (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL REFERENCES accounts(id),
            statement_date TEXT NOT NULL,
            ending_balance_minor INTEGER NOT NULL,
            completed_at TEXT NOT NULL,
            reverted_at TEXT
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

    func testMigration14To21PreservesLegacyReconciliationHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-migration-14-16-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.qdata")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let accountID = UUID()
        let reconciliationID = UUID()
        let legacySQL = """
        CREATE TABLE finance_files (id TEXT PRIMARY KEY);
        CREATE TABLE accounts (id TEXT PRIMARY KEY);
        CREATE TABLE categories (id TEXT PRIMARY KEY);
        CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL DEFAULT '',
            booking_date TEXT NOT NULL DEFAULT '2025-01-01'
        );
        CREATE TABLE transaction_splits (id TEXT PRIMARY KEY);
        CREATE TABLE reconciliations (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL REFERENCES accounts(id),
            statement_date TEXT NOT NULL,
            ending_balance_minor INTEGER NOT NULL,
            completed_at TEXT NOT NULL,
            reverted_at TEXT
        );
        INSERT INTO finance_files(id) VALUES('\(UUID().uuidString)');
        INSERT INTO accounts(id) VALUES('\(accountID.uuidString)');
        INSERT INTO reconciliations(
            id,account_id,statement_date,ending_balance_minor,completed_at
        ) VALUES(
            '\(reconciliationID.uuidString)',
            '\(accountID.uuidString)',
            '2025-12-31',
            123456,
            '2025-12-31T12:00:00Z'
        );
        PRAGMA user_version=14;
        """
        var message: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(
            sqlite3_exec(database, legacySQL, nil, nil, &message),
            SQLITE_OK
        )
        if let message { sqlite3_free(message) }
        sqlite3_close(database)

        var migratedStore: SQLiteFinanceStore? = try SQLiteFinanceStore(
            fileURL: url
        )
        migratedStore?.close()
        migratedStore = nil

        XCTAssertEqual(
            sqlite3_open_v2(
                url.path,
                &database,
                SQLITE_OPEN_READONLY,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT workflow_version,sequence,starting_balance_minor,
                       selected_sum_minor,adjustment_transaction_id
                FROM reconciliations WHERE id=?
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        sqlite3_bind_text(
            statement,
            1,
            reconciliationID.uuidString,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
        XCTAssertGreaterThan(sqlite3_column_int64(statement, 1), 0)
        XCTAssertEqual(sqlite3_column_int64(statement, 2), 0)
        XCTAssertEqual(sqlite3_column_int64(statement, 3), 0)
        XCTAssertEqual(sqlite3_column_type(statement, 4), SQLITE_NULL)
        sqlite3_finalize(statement)
        statement = nil
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                "PRAGMA user_version",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 21)
        sqlite3_finalize(statement)
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

    func testTransactionReportExpandsSplitsWithoutDoubleCountingAndDrillsDown() throws {
        let account = FinanceAccount(
            id: UUID(), name: "Haushaltskonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let expense = FinanceCategory(
            id: UUID(), parentID: nil, name: "Ausgaben",
            kind: .expense, color: "#AA0000", isActive: true
        )
        let groceries = FinanceCategory(
            id: UUID(), parentID: expense.id, name: "Lebensmittel",
            kind: .expense, color: "#AA0000", isActive: true
        )
        let utilities = FinanceCategory(
            id: UUID(), parentID: expense.id, name: "Nebenkosten",
            kind: .expense, color: "#AA0000", isActive: true
        )
        let income = FinanceCategory(
            id: UUID(), parentID: nil, name: "Gehalt",
            kind: .income, color: "#00AA00", isActive: true
        )
        let property = FinanceTag(
            id: UUID(), parentID: nil, name: "Immobilien",
            color: "#336699", description: "", isActive: true
        )
        let home = FinanceTag(
            id: UUID(), parentID: property.id, name: "Wohnung A",
            color: "#336699", description: "", isActive: true
        )
        let splitTransaction = FinanceTransaction(
            id: UUID(), accountID: account.id,
            bookingDate: Date(timeIntervalSince1970: 1_735_689_600),
            valueDate: nil, payee: "Supermarkt", purpose: "Einkauf und Strom",
            categoryID: nil, amountMinor: -1_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: groceries.id, amountMinor: -600,
                    memo: "Wocheneinkauf", sortOrder: 0, tagIDs: [home.id]
                ),
                FinanceSplit(
                    id: UUID(), categoryID: utilities.id, amountMinor: -400,
                    memo: "Abschlag", sortOrder: 1
                )
            ],
            tagIDs: [property.id]
        )
        let salary = FinanceTransaction(
            id: UUID(), accountID: account.id,
            bookingDate: Date(timeIntervalSince1970: 1_735_776_000),
            valueDate: nil, payee: "Arbeitgeber", purpose: "Gehalt",
            categoryID: income.id, amountMinor: 2_000, currency: "EUR", status: .cleared,
            memo: "", reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        let cancelled = FinanceTransaction(
            id: UUID(), accountID: account.id,
            bookingDate: Date(timeIntervalSince1970: 1_735_776_000),
            valueDate: nil, payee: "Storno", purpose: "",
            categoryID: utilities.id, amountMinor: -300, currency: "EUR",
            status: .cancelled, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )

        let snapshot = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(),
            transactions: [splitTransaction, salary, cancelled],
            accounts: [account],
            categories: [expense, groceries, utilities, income],
            tags: [property, home]
        )

        XCTAssertEqual(snapshot.facts.count, 3)
        XCTAssertFalse(snapshot.facts.contains { $0.id == splitTransaction.id.uuidString })
        XCTAssertEqual(
            snapshot.facts.filter { $0.transactionID == splitTransaction.id }
                .reduce(Int64.zero) { $0 + $1.amountMinor },
            -1_000
        )
        let total = try XCTUnwrap(snapshot.totals.first)
        XCTAssertEqual(total.currency, "EUR")
        XCTAssertEqual(total.incomeMinor, 2_000)
        XCTAssertEqual(total.expenseMinor, 1_000)
        XCTAssertEqual(total.netMinor, 1_000)
        XCTAssertEqual(snapshot.groups.count, 3)
        let groceriesGroup = try XCTUnwrap(
            snapshot.groups.first { $0.label == "Ausgaben › Lebensmittel" }
        )
        XCTAssertEqual(groceriesGroup.expenseMinor, 600)
        let drillDown = snapshot.facts(inGroupID: groceriesGroup.id)
        XCTAssertEqual(drillDown.count, 1)
        XCTAssertNotNil(drillDown.first?.splitID)
        XCTAssertEqual(
            drillDown.first?.tagPaths,
            ["Immobilien", "Immobilien › Wohnung A"]
        )
    }

    func testTransactionReportCombinesAllCoreFiltersAndExplicitInclusions() throws {
        let groupID = UUID()
        let visible = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0, groupID: groupID
        )
        let hidden = FinanceAccount(
            id: UUID(), name: "Archiv", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: true, isClosed: false, sortOrder: 1,
            groupID: groupID, includeReports: false
        )
        let housing = FinanceCategory(
            id: UUID(), parentID: nil, name: "Immobilie A",
            kind: .expense, color: "", isActive: true
        )
        let tax = FinanceCategory(
            id: UUID(), parentID: housing.id, name: "Grundsteuer",
            kind: .expense, color: "", isActive: true
        )
        let propertyTag = FinanceTag(
            id: UUID(), parentID: nil, name: "Objekte",
            color: "", description: "", isActive: true
        )
        let propertyATag = FinanceTag(
            id: UUID(), parentID: propertyTag.id, name: "Objekt A",
            color: "", description: "", isActive: true
        )
        let payeeID = UUID()
        let date = Date(timeIntervalSince1970: 1_735_689_600)

        func transaction(
            accountID: UUID,
            status: TransactionStatus = .booked,
            transferID: UUID? = nil
        ) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: accountID, bookingDate: date, valueDate: nil,
                payee: "Gemeinde", purpose: "Nebenkosten Grundsteuer",
                categoryID: tax.id, amountMinor: -600, currency: "EUR", status: status,
                memo: "Bescheid", reference: "", transferID: transferID,
                importFingerprint: nil, splits: [], payeeID: payeeID,
                tagIDs: [propertyATag.id]
            )
        }
        let normal = transaction(accountID: visible.id)
        let hiddenValue = transaction(accountID: hidden.id)
        let transfer = transaction(accountID: visible.id, transferID: UUID())
        let cancelled = transaction(accountID: visible.id, status: .cancelled)

        var query = TransactionReportQuery(
            dateFrom: date.addingTimeInterval(-10),
            dateThrough: date.addingTimeInterval(10),
            accountGroupIDs: [groupID],
            categoryIDs: [housing.id],
            tagIDs: [propertyTag.id],
            payeeIDs: [payeeID],
            statuses: [.booked],
            minimumAmountMinor: 500,
            maximumAmountMinor: 700,
            text: "Bescheid",
            currencies: ["EUR"],
            grouping: .account,
            sort: .dateAscending
        )
        let allTransactions = [normal, hiddenValue, transfer, cancelled]
        let base = TransactionReportEngine.snapshot(
            query: query,
            transactions: allTransactions,
            accounts: [visible, hidden],
            categories: [housing, tax],
            tags: [propertyTag, propertyATag]
        )
        XCTAssertEqual(base.facts.map(\.transactionID), [normal.id])
        XCTAssertEqual(base.groups.map(\.label), ["Giro"])

        query.includeHiddenAccounts = true
        let stillReportEligibleOnly = TransactionReportEngine.snapshot(
            query: query,
            transactions: allTransactions,
            accounts: [visible, hidden],
            categories: [housing, tax],
            tags: [propertyTag, propertyATag]
        )
        XCTAssertEqual(stillReportEligibleOnly.facts.count, 1)

        query.includeAccountsExcludedFromReports = true
        query.includeTransfers = true
        query.statuses.insert(.cancelled)
        let explicitlyIncluded = TransactionReportEngine.snapshot(
            query: query,
            transactions: allTransactions,
            accounts: [visible, hidden],
            categories: [housing, tax],
            tags: [propertyTag, propertyATag]
        )
        XCTAssertEqual(explicitlyIncluded.facts.count, 4)
        XCTAssertEqual(Set(explicitlyIncluded.groups.map(\.label)), ["Giro", "Archiv"])
    }

    func testSavedReportTemplateRoundTripsVersionedQueryAndCanBeDeleted() throws {
        let context = try TestDatabase()
        var query = TransactionReportQuery(
            dateFrom: Date(timeIntervalSince1970: 1_700_000_000),
            dateThrough: Date(timeIntervalSince1970: 1_710_000_000),
            accountIDs: [UUID()],
            accountGroupIDs: [UUID()],
            categoryIDs: [UUID()],
            includeCategoryDescendants: false,
            tagIDs: [UUID()],
            payeeIDs: [UUID()],
            statuses: [.booked, .reconciled],
            minimumAmountMinor: 1_000,
            maximumAmountMinor: 50_000,
            text: "Grundsteuer",
            currencies: ["EUR"],
            includeHiddenAccounts: true,
            includeAccountsExcludedFromReports: true,
            includeTransfers: true,
            expandSplits: false,
            grouping: .account,
            sort: .dateAscending
        )
        let id = UUID()
        try context.store.saveReportTemplate(
            SavedReportTemplate(
                id: id,
                name: "Immobiliensteuer",
                definitionVersion: 1,
                query: query
            )
        )
        let restored = try XCTUnwrap(context.store.reportTemplates().first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.name, "Immobiliensteuer")
        XCTAssertEqual(restored.definitionVersion, 1)
        XCTAssertEqual(restored.query, query)

        query.text = "aktualisiert"
        try context.store.saveReportTemplate(
            SavedReportTemplate(
                id: id,
                name: "Immobiliensteuer aktualisiert",
                definitionVersion: 1,
                query: query
            )
        )
        XCTAssertEqual(try context.store.reportTemplates().count, 1)
        XCTAssertEqual(try context.store.reportTemplates().first?.query.text, "aktualisiert")
        try context.store.deleteReportTemplate(id: id)
        XCTAssertTrue(try context.store.reportTemplates().isEmpty)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testReportCSVExportIsDeterministicEscapedAndUsesGermanMinorUnits() throws {
        let fact = TransactionReportFact(
            id: "fact-1",
            transactionID: UUID(),
            splitID: UUID(),
            bookingDate: Date(timeIntervalSince1970: 0),
            accountID: UUID(),
            accountName: "Giro;Privat",
            payee: "Händler \"Nord\"",
            payeeID: nil,
            purpose: "Zeile 1\nZeile 2",
            detail: "",
            categoryID: nil,
            categoryPath: "Haushalt › Lebensmittel",
            tagIDs: [],
            tagPaths: [],
            status: .booked,
            amountMinor: -123_456,
            currency: "EUR",
            isTransfer: false
        )
        let snapshot = TransactionReportSnapshot(
            facts: [fact],
            groups: [],
            totals: [
                TransactionReportCurrencyTotal(
                    currency: "EUR",
                    incomeMinor: 0,
                    expenseMinor: 123_456,
                    netMinor: -123_456
                )
            ]
        )
        let data = try TransactionReportCSVExporter.data(
            snapshot: snapshot,
            metadata: ReportExportMetadata(
                title: "Buchungsbericht",
                dateLabel: "Gesamter Zeitraum",
                filterSummary: "ohne Umbuchungen",
                baseCurrency: "EUR",
                generatedAt: Date(timeIntervalSince1970: 0)
            ),
            options: ReportCSVOptions(separator: .semicolon, encoding: .utf8)
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let expected = [
            "Bericht;Buchungsbericht",
            "Zeitraum;Gesamter Zeitraum",
            "Filter;ohne Umbuchungen",
            "Erstellt;1970-01-01T00:00:00Z",
            "Basiswährung;EUR",
            "",
            "Datum;Konto;Empfänger;Verwendungszweck;Kategorie;Status;Betrag;Währung;Split",
            "1970-01-01;\"Giro;Privat\";\"Händler \"\"Nord\"\"\";"
                + "\"Zeile 1\nZeile 2\";Haushalt › Lebensmittel;Gebucht;-1234,56;EUR;Ja"
        ].joined(separator: "\r\n") + "\r\n"
        XCTAssertEqual(text, expected)
    }

    func testReportPDFExportCreatesReadableMultipagePrintLayout() throws {
        let accountID = UUID()
        let facts = (0..<80).map { index in
            TransactionReportFact(
                id: "fact-\(index)",
                transactionID: UUID(),
                splitID: index.isMultiple(of: 3) ? UUID() : nil,
                bookingDate: Date(timeIntervalSince1970: TimeInterval(index * 86_400)),
                accountID: accountID,
                accountName: "Girokonto Privat",
                payee: "Empfänger \(index)",
                payeeID: nil,
                purpose: "Verwendungszweck und Belegnummer \(index)",
                detail: "",
                categoryID: nil,
                categoryPath: "Immobilien › Wohnung A › Grundsteuer",
                tagIDs: [],
                tagPaths: [],
                status: .booked,
                amountMinor: index.isMultiple(of: 4) ? 123_456 : -9_876,
                currency: "EUR",
                isTransfer: false
            )
        }
        let groups = (0..<8).map { index in
            let ids = Set(facts[index * 10..<(index + 1) * 10].map(\.id))
            return TransactionReportGroup(
                id: "group-\(index)",
                label: "Immobilien › Wohnung \(index) › Grundsteuer",
                currency: "EUR",
                incomeMinor: 123_456,
                expenseMinor: 98_760,
                netMinor: 24_696,
                factIDs: ids
            )
        }
        let snapshot = TransactionReportSnapshot(
            facts: facts,
            groups: groups,
            totals: [
                TransactionReportCurrencyTotal(
                    currency: "EUR",
                    incomeMinor: 2_469_120,
                    expenseMinor: 592_560,
                    netMinor: 1_876_560
                )
            ]
        )
        let data = try TransactionReportPDFExporter.data(
            snapshot: snapshot,
            metadata: ReportExportMetadata(
                title: "Immobiliensteuer 2025",
                dateLabel: "01.01.2025 – 31.12.2025",
                filterSummary: "alle Konten · Grundsteuer · ohne Umbuchungen",
                baseCurrency: "EUR",
                generatedAt: Date(timeIntervalSince1970: 0)
            ),
            options: ReportPDFOptions(orientation: .landscape)
        )
        if let outputPath = ProcessInfo.processInfo.environment[
            "FINANZVERWALTER_PDF_QA_OUTPUT"
        ] {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 2)
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("Immobiliensteuer 2025"))
        XCTAssertTrue(text.contains("Gruppierte Übersicht"))
        XCTAssertTrue(text.contains("Buchungen und Splitpositionen"))
        XCTAssertTrue(text.contains("Immobilien › Wohnung 0 › Grundsteuer"))
        XCTAssertTrue(text.contains("1.234,56 EUR"))
        XCTAssertTrue(text.contains("Seite 1"))
        XCTAssertTrue(text.contains("Seite \(document.pageCount)"))
    }

    func testRegisterPreferencesRoundTripColumnsAndNamedViewDeterministically() throws {
        let columns: Set<RegisterColumn> = [
            .date, .payee, .category, .amount, .balance
        ]
        let encodedColumns = RegisterPreferencesCodec.encodeColumns(columns)
        XCTAssertEqual(
            encodedColumns,
            "amount,balance,category,date,payee"
        )
        XCTAssertEqual(
            RegisterPreferencesCodec.decodeColumns(encodedColumns),
            columns
        )
        XCTAssertEqual(
            RegisterPreferencesCodec.decodeColumns(""),
            RegisterColumn.defaultSet
        )
        XCTAssertEqual(
            RegisterPreferencesCodec.addingBalanceColumn(
                to: "amount,category,date,payee"
            ),
            "amount,balance,category,date,payee"
        )
        let viewWithoutBalance = SavedRegisterView(
            id: UUID(),
            name: "Alte Ansicht",
            accountID: nil,
            statusRawValue: nil,
            categorySelection: .all,
            periodRawValue: "all",
            customStart: Date(timeIntervalSince1970: 0),
            customEnd: Date(timeIntervalSince1970: 1),
            rowModeRawValue: "single",
            visibleColumns: [.date, .payee, .amount]
        )
        let oldViews = try RegisterPreferencesCodec.encodeViews([
            viewWithoutBalance
        ])
        let migratedViews = RegisterPreferencesCodec.decodeViews(
            RegisterPreferencesCodec.addingBalanceColumnToViews(oldViews)
        )
        XCTAssertEqual(
            migratedViews.first?.visibleColumns,
            [.date, .payee, .amount, .balance]
        )
        let firstAccountID = UUID()
        let secondAccountID = UUID()
        let missingAccountID = UUID()
        let encodedTabs = RegisterPreferencesCodec.encodeTabAccountIDs([
            firstAccountID, secondAccountID, firstAccountID
        ])
        XCTAssertEqual(
            encodedTabs,
            "\(firstAccountID.uuidString),\(secondAccountID.uuidString)"
        )
        XCTAssertEqual(
            RegisterPreferencesCodec.decodeTabAccountIDs(
                encodedTabs + ",\(missingAccountID.uuidString),ungültig",
                availableAccountIDs: [firstAccountID, secondAccountID]
            ),
            [firstAccountID, secondAccountID]
        )

        let view = SavedRegisterView(
            id: UUID(),
            name: "  Grundsteuer kompakt  ",
            accountID: UUID(),
            statusRawValue: TransactionStatus.booked.rawValue,
            categorySelection: .category(UUID()),
            periodRawValue: "currentYear",
            customStart: Date(timeIntervalSince1970: 1_704_067_200),
            customEnd: Date(timeIntervalSince1970: 1_735_603_199),
            rowModeRawValue: "twoLines",
            visibleColumns: columns
        )
        let encodedViews = try RegisterPreferencesCodec.encodeViews([view])
        let restored = try XCTUnwrap(
            RegisterPreferencesCodec.decodeViews(encodedViews).first
        )
        XCTAssertEqual(restored.id, view.id)
        XCTAssertEqual(restored.name, "Grundsteuer kompakt")
        XCTAssertEqual(restored.accountID, view.accountID)
        XCTAssertEqual(restored.statusRawValue, view.statusRawValue)
        XCTAssertEqual(restored.categorySelection, view.categorySelection)
        XCTAssertEqual(restored.periodRawValue, view.periodRawValue)
        XCTAssertEqual(restored.rowModeRawValue, view.rowModeRawValue)
        XCTAssertEqual(restored.visibleColumns, columns)
        XCTAssertTrue(
            RegisterPreferencesCodec.decodeViews("{nicht-json").isEmpty
        )
    }

    func testRegisterF3SelectionUsesConfiguredTransactionField() throws {
        let accountID = UUID()
        let categoryID = UUID()
        let transaction = FinanceTransaction(
            id: UUID(),
            accountID: accountID,
            bookingDate: Date(timeIntervalSince1970: 0),
            valueDate: nil,
            payee: "  Stadtwerke Nord  ",
            purpose: "Abschlag Juli",
            categoryID: categoryID,
            amountMinor: -12_345,
            currency: "EUR",
            status: .cleared,
            memo: "",
            reference: "",
            transferID: nil,
            importFingerprint: nil,
            splits: []
        )
        XCTAssertEqual(
            RegisterF3Field.payee.selection(for: transaction),
            .search("Stadtwerke Nord")
        )
        XCTAssertEqual(
            RegisterF3Field.purpose.selection(for: transaction),
            .search("Abschlag Juli")
        )
        XCTAssertEqual(
            RegisterF3Field.category.selection(for: transaction),
            .category(.category(categoryID))
        )
        XCTAssertEqual(
            RegisterF3Field.account.selection(for: transaction),
            .account(accountID)
        )
        XCTAssertEqual(
            RegisterF3Field.status.selection(for: transaction),
            .status(.cleared)
        )
    }

    func testRegisterPDFContainsExactlyVisibleColumnsAndRepeatsHeaders() throws {
        let rows = (0..<90).map { index in
            [
                "01.07.2025",
                "Empfänger \(index)",
                index.isMultiple(of: 2) ? "-12,34 EUR" : "45,67 EUR",
                "\(1_000 + index),00 EUR"
            ]
        }
        let data = try RegisterPDFExporter.data(
            snapshot: RegisterPrintSnapshot(
                title: "Kontoblatt – Girokonto",
                filterSummary: "Kategorie: Immobilie › Haus › Grundsteuer",
                generatedAt: Date(timeIntervalSince1970: 0),
                columns: [.date, .payee, .amount, .balance],
                rows: rows
            )
        )
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 2)
        let pageTexts = (0..<document.pageCount).compactMap {
            document.page(at: $0)?.string
        }
        XCTAssertTrue(pageTexts.allSatisfy { $0.contains("Saldo") })
        XCTAssertTrue(pageTexts.allSatisfy { $0.contains("Betrag") })
        let text = pageTexts.joined(separator: "\n")
        XCTAssertTrue(text.contains("Empfänger 89"))
        XCTAssertFalse(text.contains("Verwendungszweck"))
        XCTAssertFalse(text.contains("Kategorie\n"))
        XCTAssertTrue(text.contains("Seite 1 von \(document.pageCount)"))
    }

    func testShortcutConfigurationRoundTripsAllActionsAndRejectsConflicts() throws {
        let defaults = AppShortcutConfiguration.defaults
        XCTAssertEqual(defaults.assignments.count, AppShortcutAction.allCases.count)
        XCTAssertTrue(defaults.conflicts.isEmpty)
        XCTAssertEqual(defaults.binding(for: .filterSelection).displayText, "F3")
        XCTAssertEqual(defaults.binding(for: .deleteSelection).key, .delete)

        var customized = defaults
        customized.set(
            AppShortcutBinding(key: .g, modifiers: [.control, .shift]),
            for: .search
        )
        let encoded = AppShortcutCodec.encode(customized)
        XCTAssertFalse(encoded.isEmpty)
        let decoded = AppShortcutCodec.decode(encoded)
        XCTAssertEqual(
            decoded.binding(for: .search),
            AppShortcutBinding(key: .g, modifiers: [.control, .shift])
        )
        XCTAssertEqual(AppShortcutCodec.decode("{kaputt"), .defaults)

        var conflicting = customized
        conflicting.set(customized.binding(for: .search), for: .reconcile)
        XCTAssertFalse(conflicting.conflicts.isEmpty)
        XCTAssertTrue(AppShortcutCodec.encode(conflicting).isEmpty)
        let conflictingData = try JSONEncoder().encode(conflicting)
        let conflictingRaw = try XCTUnwrap(
            String(data: conflictingData, encoding: .utf8)
        )
        XCTAssertEqual(AppShortcutCodec.decode(conflictingRaw), .defaults)

        var unsafe = defaults
        unsafe.set(
            AppShortcutBinding(key: .x, modifiers: []),
            for: .search
        )
        XCTAssertEqual(unsafe.barePrintableActions, [.search])
        XCTAssertFalse(unsafe.isValid)
        XCTAssertTrue(AppShortcutCodec.encode(unsafe).isEmpty)
    }

    func testTransactionTemplatePersistsSplitsAndCreatesFreshDraft() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(),
            name: "Vorlagenkonto",
            institution: "",
            type: .checking,
            currency: "EUR",
            openingBalanceMinor: 0,
            isHidden: false,
            isClosed: false,
            sortOrder: 0
        )
        try context.store.saveAccount(account)
        let source = FinanceTransaction(
            id: UUID(),
            accountID: account.id,
            bookingDate: Date(timeIntervalSince1970: 100),
            valueDate: Date(timeIntervalSince1970: 100),
            payee: "Vermieter",
            purpose: "Monatsmiete",
            categoryID: nil,
            amountMinor: -100_000,
            currency: "EUR",
            status: .reconciled,
            memo: "Vorlage ohne Altbeleg",
            reference: "ALT-4711",
            transferID: nil,
            importFingerprint: "privater-import",
            splits: [
                FinanceSplit(
                    id: UUID(),
                    categoryID: nil,
                    amountMinor: -80_000,
                    memo: "Miete",
                    sortOrder: 0
                ),
                FinanceSplit(
                    id: UUID(),
                    categoryID: nil,
                    amountMinor: -20_000,
                    memo: "Nebenkosten",
                    sortOrder: 1
                )
            ]
        )
        let template = TransactionTemplate(
            name: "  Monatsmiete  ",
            transaction: source
        )
        try context.store.saveTransactionTemplate(template)
        let restored = try XCTUnwrap(context.store.transactionTemplates().first)
        XCTAssertEqual(restored.id, template.id)
        XCTAssertEqual(restored.name, "Monatsmiete")
        XCTAssertEqual(restored.status, .booked)
        XCTAssertEqual(restored.splits.map(\.amountMinor), [-80_000, -20_000])
        var cancelledSource = source
        cancelledSource.status = .cancelled
        XCTAssertEqual(
            TransactionTemplate(
                name: "Stornierte Quelle",
                transaction: cancelledSource
            ).status,
            .booked
        )

        let date = Date(timeIntervalSince1970: 500)
        let draft = restored.transaction(on: date)
        XCTAssertNotEqual(draft.id, source.id)
        XCTAssertEqual(draft.bookingDate, date)
        XCTAssertEqual(draft.valueDate, date)
        XCTAssertEqual(draft.reference, "")
        XCTAssertNil(draft.importFingerprint)
        XCTAssertEqual(draft.amountMinor, source.amountMinor)
        try draft.validate()

        try context.store.deleteTransactionTemplate(id: restored.id)
        XCTAssertTrue(try context.store.transactionTemplates().isEmpty)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    @MainActor
    func testTransactionTemplateRejectsSingleTransferSide() throws {
        let context = try TestDatabase()
        let source = FinanceAccount(
            id: UUID(), name: "Quelle", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let target = FinanceAccount(
            id: UUID(), name: "Ziel", institution: "", type: .savings,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(source)
        try context.store.saveAccount(target)
        try context.store.createTransfer(
            from: source,
            to: target,
            amountMinor: 1_000,
            date: .now,
            purpose: "Rücklage"
        )
        let side = try XCTUnwrap(context.store.transactions().first)
        let appStore = FinanceAppStore(repository: context.store)
        XCTAssertFalse(
            appStore.saveTransactionTemplate(name: "Falsche Einzelvorlage", from: side)
        )
        XCTAssertTrue(appStore.transactionTemplates.isEmpty)
        XCTAssertNotNil(appStore.errorMessage)
        XCTAssertTrue(try context.store.transactionTemplates().isEmpty)
    }

    func testReadOnlyBankingSimulatorIsDeterministicAndCancellable() async throws {
        let anchor = Date(timeIntervalSince1970: 1_767_225_600)
        let remote = BankingRemoteAccount(
            id: "sim:giro",
            name: "Giro",
            iban: "DE89370400440532013000",
            bic: "COBADEFFXXX",
            currency: "EUR",
            accountType: AccountType.checking.rawValue,
            ownerName: "Testperson"
        )
        let adapter = SimulatorBankingAdapter(
            accounts: [remote],
            anchorDate: anchor
        )
        XCTAssertFalse(adapter.supportedOperations.contains(.holdings))
        let request = BankingFetchRequest(
            externalAccountIDs: [remote.id],
            operations: [
                .accounts, .balances, .transactions,
                .pendingTransactions, .standingOrders,
                .scheduledPayments
            ],
            dateFrom: nil
        )
        let first = try await adapter.fetch(request)
        let second = try await adapter.fetch(request)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.transactions.count, 3)
        XCTAssertEqual(first.balances.count, 1)
        XCTAssertEqual(first.standingOrders.count, 2)
        XCTAssertEqual(first.rawPayloadHash.count, 64)
        XCTAssertTrue(first.diagnostics.allSatisfy(\.isSuccess))

        let task = Task { try await adapter.fetch(request) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Ein abgebrochener Abruf darf kein Paket liefern.")
        } catch is CancellationError {
            // Erwartetes Verhalten: kein partielles Paket.
        }
    }

    func testRegisterMiniReportUsesSplitContributionsAndKeepsCurrenciesSeparate() {
        let accountID = UUID()
        let categoryID = UUID()
        let otherCategoryID = UUID()
        let tagID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let selected = FinanceTransaction(
            id: UUID(), accountID: accountID,
            bookingDate: Date(timeIntervalSince1970: 300), valueDate: nil,
            payee: "Müller GmbH", purpose: "Gemischter Beleg",
            categoryID: nil, amountMinor: -10_000, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: categoryID,
                    amountMinor: -6_000, memo: "Ziel", sortOrder: 0,
                    tagIDs: [tagID]
                ),
                FinanceSplit(
                    id: UUID(), categoryID: otherCategoryID,
                    amountMinor: -4_000, memo: "Andere", sortOrder: 1
                )
            ]
        )
        let sameCategory = FinanceTransaction(
            id: UUID(), accountID: accountID,
            bookingDate: Date(timeIntervalSince1970: 200), valueDate: nil,
            payee: "Andere Firma", purpose: "Direkt",
            categoryID: categoryID, amountMinor: -5_000, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let samePayeeUSD = FinanceTransaction(
            id: UUID(), accountID: accountID,
            bookingDate: Date(timeIntervalSince1970: 100), valueDate: nil,
            payee: "muller gmbh", purpose: "Erstattung",
            categoryID: nil, amountMinor: 20_000, currency: "USD",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        var cancelled = sameCategory
        cancelled = FinanceTransaction(
            id: UUID(), accountID: cancelled.accountID,
            bookingDate: cancelled.bookingDate, valueDate: nil,
            payee: cancelled.payee, purpose: cancelled.purpose,
            categoryID: categoryID, amountMinor: -99_999, currency: "EUR",
            status: .cancelled, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let values = [selected, sameCategory, samePayeeUSD, cancelled]

        let category = RegisterMiniReportSnapshot.make(
            selected: selected,
            dimension: .category,
            transactions: values
        )
        XCTAssertEqual(category.entries.map(\.contributionMinor), [-6_000, -5_000])
        XCTAssertEqual(
            category.totals,
            [
                RegisterMiniReportCurrencyTotal(
                    currency: "EUR", incomeMinor: 0,
                    expenseMinor: -11_000, netMinor: -11_000,
                    transactionCount: 2
                )
            ]
        )

        let tag = RegisterMiniReportSnapshot.make(
            selected: selected,
            dimension: .tag,
            transactions: values
        )
        XCTAssertEqual(tag.entries.map(\.contributionMinor), [-6_000])

        let payee = RegisterMiniReportSnapshot.make(
            selected: selected,
            dimension: .payee,
            transactions: values
        )
        XCTAssertEqual(payee.entries.count, 2)
        XCTAssertEqual(payee.totals.map(\.currency), ["EUR", "USD"])
        XCTAssertEqual(payee.totals.map(\.netMinor), [-10_000, 20_000])
    }

    func testSecondaryRegisterQueryKeepsAccountAndFiltersIndependent() {
        let firstAccountID = UUID()
        let secondAccountID = UUID()
        let categoryID = UUID()
        let first = FinanceTransaction(
            id: UUID(), accountID: firstAccountID,
            bookingDate: Date(timeIntervalSince1970: 100), valueDate: nil,
            payee: "Versorger", purpose: "Abschlag",
            categoryID: categoryID, amountMinor: -5_000, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let expected = FinanceTransaction(
            id: UUID(), accountID: firstAccountID,
            bookingDate: Date(timeIntervalSince1970: 200), valueDate: nil,
            payee: "Planung", purpose: "Später",
            categoryID: nil, amountMinor: -1_000, currency: "EUR",
            status: .expected, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let second = FinanceTransaction(
            id: UUID(), accountID: secondAccountID,
            bookingDate: Date(timeIntervalSince1970: 300), valueDate: nil,
            payee: "Anderes Konto", purpose: "Unabhängig",
            categoryID: categoryID, amountMinor: 7_000, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let values = [first, expected, second]
        let secondRows = RegisterSecondaryQuery.visible(
            transactions: values,
            accountID: secondAccountID,
            status: nil,
            category: .all,
            period: .all,
            customStart: .distantPast,
            customEnd: .distantFuture,
            searchText: ""
        ) { _ in "Immobilie › Energie" }
        XCTAssertEqual(secondRows.map(\.id), [second.id])

        let filteredFirstRows = RegisterSecondaryQuery.visible(
            transactions: values,
            accountID: firstAccountID,
            status: .booked,
            category: .category(categoryID),
            period: .all,
            customStart: .distantPast,
            customEnd: .distantFuture,
            searchText: "Immobilie"
        ) { _ in "Immobilie › Energie" }
        XCTAssertEqual(filteredFirstRows.map(\.id), [first.id])
        XCTAssertTrue(
            RegisterSecondaryQuery.visible(
                transactions: values,
                accountID: nil,
                status: nil,
                category: .all,
                period: .all,
                customStart: .distantPast,
                customEnd: .distantFuture,
                searchText: ""
            ) { _ in "" }.isEmpty
        )
    }

    func testBankingDownloadCommitsAtomicallyAndIsIdempotent() async throws {
        let context = try TestDatabase()
        var account = FinanceAccount(
            id: UUID(), name: "Online-Giro", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        try context.store.saveAccount(account)
        let connection = BankingConnection(
            id: UUID(), name: "Simulator", providerKind: .simulator,
            adapterIdentifier:
                "de.pixelpuxel.finanzverwalter.banking-simulator.v1",
            institutionName: "Testbank", status: .ready,
            consentValidUntil: nil, lastSyncAt: nil,
            lastUserMessage: "Keine Zugangsdaten", isEnabled: true
        )
        try context.store.saveBankingConnection(connection)
        XCTAssertThrowsError(
            try context.store.saveBankingConnection(
                BankingConnection(
                    id: UUID(), name: "Live", providerKind: .finTS,
                    adapterIdentifier: "live.disabled",
                    institutionName: "Bank", status: .inactive,
                    consentValidUntil: nil, lastSyncAt: nil,
                    lastUserMessage: "", isEnabled: false
                )
            )
        )
        let mapping = BankingAccountMapping(
            id: UUID(), connectionID: connection.id,
            externalAccountID: "sim:giro", remoteName: "Online-Giro",
            remoteIBAN: account.iban, currency: "EUR",
            localAccountID: account.id, isEnabled: true
        )
        try context.store.saveBankingAccountMapping(mapping)
        let remote = BankingRemoteAccount(
            id: mapping.externalAccountID, name: mapping.remoteName,
            iban: mapping.remoteIBAN, bic: account.bic, currency: "EUR",
            accountType: account.type.rawValue, ownerName: "Testperson"
        )
        let operations: Set<BankingOperation> = [
            .balances, .transactions, .pendingTransactions,
            .standingOrders, .scheduledPayments
        ]
        let adapter = SimulatorBankingAdapter(
            accounts: [remote],
            anchorDate: Date(timeIntervalSince1970: 1_767_225_600)
        )
        let package = try await adapter.fetch(
            BankingFetchRequest(
                externalAccountIDs: [remote.id],
                operations: operations,
                dateFrom: nil
            )
        )
        let preview = try BankingImportNormalizer.preview(
            connection: connection,
            package: package,
            mappings: [mapping],
            existingTransactions: [],
            rules: [],
            selectedExternalAccountIDs: [remote.id],
            requestedOperations: operations,
            dateWindowDays: 4
        )
        let result = try context.store.commitBankingDownload(preview)
        XCTAssertEqual(
            result,
            ImportCommitResult(
                importedCount: 3,
                matchedCount: 0,
                skippedCount: 0
            )
        )
        let imported = try context.store.transactions(accountID: account.id)
        XCTAssertEqual(imported.count, 3)
        XCTAssertTrue(imported.allSatisfy { $0.origin == .bankDownload })
        XCTAssertTrue(imported.allSatisfy { !$0.externalTransactionID.isEmpty })
        XCTAssertEqual(
            try XCTUnwrap(
                context.store.accounts().first { $0.id == account.id }
            ).lastBankBalanceMinor,
            package.balances.first?.bookedMinor
        )
        XCTAssertEqual(
            try context.store.bankingRemoteOrders(connectionID: connection.id),
            package.standingOrders
        )
        XCTAssertEqual(
            try context.store.bankingSyncRuns(connectionID: connection.id).count,
            1
        )

        let repeated = try BankingImportNormalizer.preview(
            connection: connection,
            package: package,
            mappings: [mapping],
            existingTransactions: imported,
            rules: [],
            selectedExternalAccountIDs: [remote.id],
            requestedOperations: operations,
            dateWindowDays: 4
        )
        let repeatResult = try context.store.commitBankingDownload(repeated)
        XCTAssertEqual(repeatResult.importedCount, 0)
        XCTAssertEqual(repeatResult.skippedCount, 3)
        XCTAssertEqual(try context.store.transactions().count, 3)
        XCTAssertEqual(
            try context.store.bankingSyncRuns(connectionID: connection.id).count,
            2
        )

        let failedPackage = BankingFetchPackage(
            adapterIdentifier: package.adapterIdentifier,
            providerIdentifier: package.providerIdentifier,
            fetchedAt: package.fetchedAt,
            rawPayloadHash: String(repeating: "f", count: 64),
            accounts: package.accounts,
            balances: package.balances,
            transactions: package.transactions,
            standingOrders: package.standingOrders,
            diagnostics: [
                BankingDiagnostic(
                    id: UUID(), accountID: remote.id,
                    operation: .transactions, isSuccess: false,
                    userMessage: "Abruf fehlgeschlagen",
                    technicalCode: "SIM-FAIL"
                )
            ]
        )
        let failedPreview = try BankingImportNormalizer.preview(
            connection: connection,
            package: failedPackage,
            mappings: [mapping],
            existingTransactions: imported,
            rules: [],
            selectedExternalAccountIDs: [remote.id],
            requestedOperations: operations,
            dateWindowDays: 4
        )
        XCTAssertThrowsError(
            try context.store.commitBankingDownload(failedPreview)
        )
        XCTAssertEqual(try context.store.transactions().count, 3)
        XCTAssertEqual(
            try context.store.bankingSyncRuns(connectionID: connection.id).count,
            2
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testConfirmedBulkDeleteIsAtomicAndProtectsReconciledTransactions() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(),
            name: "Löschschutz",
            institution: "",
            type: .checking,
            currency: "EUR",
            openingBalanceMinor: 0,
            isHidden: false,
            isClosed: false,
            sortOrder: 0
        )
        try context.store.saveAccount(account)
        let booked = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now, valueDate: nil,
            payee: "Frei", purpose: "", categoryID: nil, amountMinor: -100,
            currency: "EUR", status: .booked, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: []
        )
        let protected = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now, valueDate: nil,
            payee: "Abgeglichen", purpose: "", categoryID: nil, amountMinor: -200,
            currency: "EUR", status: .reconciled, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(booked)
        try context.store.saveTransaction(protected)
        XCTAssertThrowsError(
            try context.store.deleteTransactions(ids: [booked.id, protected.id])
        ) { error in
            XCTAssertEqual(error as? FinanceError, .protectedTransaction)
        }
        XCTAssertEqual(Set(try context.store.transactions().map(\.id)), [booked.id, protected.id])
        XCTAssertTrue(try context.store.integrityCheck())
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
