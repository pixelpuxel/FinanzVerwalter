import XCTest
import SQLite3
import PDFKit
import AppKit
import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import FinanzVerwalter

final class FinanzVerwalterTests: XCTestCase {
    @MainActor
    func testEPCQRParsesScansPersistsAndExportsPurposeCode() throws {
        let text = [
            "BCD", "002", "1", "SCT", "COBADEFFXXX",
            "Stadtwerke Nord", "DE12500105170648489890", "EUR12.30",
            "GDDS", "RF18539007547034", "", "Nur mit Rechnung abgleichen"
        ].joined(separator: "\n")
        let parsed = try EPCQRImporter.parse(text)
        XCTAssertEqual(parsed.version, "002")
        XCTAssertEqual(parsed.amountMinor, 1_230)
        XCTAssertEqual(parsed.purposeCode, "GDDS")
        XCTAssertEqual(parsed.paymentPurpose, "RF18539007547034")

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        let output = try XCTUnwrap(filter.outputImage).transformed(
            by: CGAffineTransform(scaleX: 8, y: 8)
        )
        let cgImage = try XCTUnwrap(
            CIContext().createCGImage(output, from: output.extent)
        )
        let representation = NSBitmapImageRep(cgImage: cgImage)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("epc-qr-\(UUID().uuidString).png")
        try png.write(to: imageURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        XCTAssertEqual(try EPCQRImporter.decodeImage(at: imageURL), parsed)

        let context = try TestDatabase()
        var account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "Bank", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        account.ownerName = "Max Mustermann"
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        try context.store.saveAccount(account)
        let now = Pain001Exporter.gregorianDate(year: 2026, month: 7, day: 31)
        let order = PaymentOrder(
            id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
            recipientName: parsed.recipientName, iban: parsed.iban,
            bic: parsed.bic, amountMinor: try XCTUnwrap(parsed.amountMinor),
            currency: "EUR", executionDate: now, purpose: parsed.paymentPurpose,
            endToEndID: "NOTPROVIDED", status: .draft,
            idempotencyKey: UUID().uuidString, bankReference: "",
            createdAt: now, updatedAt: now, purposeCode: parsed.purposeCode
        )
        try context.store.createPaymentOrder(order)
        XCTAssertEqual(try context.store.paymentOrders().first?.purposeCode, "GDDS")
        let xml = try Pain001Exporter.export(
            order: order, account: account, createdAt: now
        ).data
        XCTAssertTrue(String(decoding: xml, as: UTF8.self).contains("<Purp><Cd>GDDS</Cd></Purp>"))
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testEPCQRRejectsUnsafeOrContradictoryPayloads() throws {
        let valid = [
            "BCD", "002", "1", "SCT", "", "Empfänger",
            "DE12500105170648489890", "EUR0.01", "", "", "Rechnung"
        ].joined(separator: "\n")
        XCTAssertNoThrow(try EPCQRImporter.parse(valid))
        XCTAssertThrowsError(try EPCQRImporter.parse(valid + "\n"))
        XCTAssertThrowsError(try EPCQRImporter.parse(valid.replacingOccurrences(of: "EUR0.01", with: "USD0.01")))
        XCTAssertThrowsError(try EPCQRImporter.parse(valid.replacingOccurrences(of: "EUR0.01", with: "EUR1000000000.00")))
        XCTAssertThrowsError(try EPCQRImporter.parse(valid.replacingOccurrences(of: "\n\nRechnung", with: "\nRF00539007547034\nRechnung")))
        XCTAssertThrowsError(try EPCQRImporter.parse(valid.replacingOccurrences(of: "\n\nRechnung", with: "\nRF18539007547034\nRechnung")))
        XCTAssertThrowsError(try EPCQRImporter.parse(valid.replacingOccurrences(of: "\n1\nSCT", with: "\n2\nSCT").replacingOccurrences(of: "Empfänger", with: "Empfänger 😀")))
        let oversized = [
            "BCD", "002", "1", "SCT", "COBADEFFXXX",
            String(repeating: "N", count: 70), "DE12500105170648489890",
            "EUR999999999.99", "GDDS", "",
            String(repeating: "Z", count: 140), String(repeating: "I", count: 70)
        ].joined(separator: "\n")
        XCTAssertThrowsError(try EPCQRImporter.parse(oversized))
    }

    func testPainInstructionImporterRoundTripsCreditAndDebitExports() throws {
        var account = FinanceAccount(
            id: UUID(), name: "SEPA-Konto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.ownerName = "Müller & Partner"
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        let creation = Pain001Exporter.gregorianDate(year: 2026, month: 7, day: 31)
        let requested = Pain001Exporter.gregorianDate(year: 2026, month: 8, day: 3)
        let payment = PaymentOrder(
            id: UUID(), accountID: account.id, type: .instantCreditTransfer,
            recipientName: "Stadtwerke <Nord>", iban: "DE12500105170648489890",
            bic: "INGDDEFFXXX", amountMinor: 123_456, currency: "EUR",
            executionDate: requested, purpose: "Abschlag & Vertrag",
            endToEndID: "IMPORT-E2E-1", status: .draft,
            idempotencyKey: "instruction-payment", bankReference: "",
            createdAt: creation, updatedAt: creation
        )
        let creditData = try Pain001Exporter.export(
            order: payment, account: account, createdAt: creation,
            messageID: "IMPORT-MSG-1"
        ).data
        let credit = try PainInstructionImporter.parse(data: creditData)
        XCTAssertEqual(credit.kind, .creditTransfer)
        XCTAssertEqual(credit.messageID, "IMPORT-MSG-1")
        XCTAssertEqual(credit.records.count, 1)
        XCTAssertEqual(credit.records[0].localIBAN, account.iban)
        XCTAssertEqual(credit.records[0].counterpartyName, "Stadtwerke <Nord>")
        XCTAssertEqual(credit.records[0].amountMinor, 123_456)
        XCTAssertEqual(credit.records[0].purpose, "Abschlag & Vertrag")
        XCTAssertTrue(credit.records[0].isInstant)

        let debit = DirectDebitOrder(
            id: UUID(), creditorAccountID: account.id,
            debtorPayeeID: UUID(), debtorBankAccountID: UUID(),
            mandateID: UUID(), creditorName: account.ownerName,
            creditorID: "DE98ZZZ09999999999",
            creditorIBAN: account.iban, creditorBIC: account.bic,
            debtorName: "Zahler Süd", debtorIBAN: "DE12500105170648489890",
            debtorBIC: "INGDDEFFXXX", amountMinor: 9_876, currency: "EUR",
            collectionDate: requested, purpose: "Mitgliedsbeitrag",
            endToEndID: "IMPORT-DD-E2E", mandateReference: "MANDAT-IMPORT-1",
            mandateSignedOn: Pain008Exporter.gregorianDate(
                year: 2026, month: 1, day: 15
            ),
            sequenceType: .recurring, status: .draft,
            idempotencyKey: "instruction-debit", bankReference: "",
            createdAt: creation, updatedAt: creation
        )
        let debitData = try Pain008Exporter.export(
            order: debit, account: account, createdAt: creation,
            messageID: "IMPORT-DD-MSG-1"
        ).data
        let direct = try PainInstructionImporter.parse(data: debitData)
        XCTAssertEqual(direct.kind, .directDebit)
        XCTAssertEqual(direct.records.count, 1)
        XCTAssertEqual(direct.records[0].creditorID, "DE98ZZZ09999999999")
        XCTAssertEqual(direct.records[0].mandateReference, "MANDAT-IMPORT-1")
        XCTAssertEqual(direct.records[0].sequenceType, .recurring)
        XCTAssertEqual(direct.records[0].amountMinor, 9_876)
    }

    func testPainInstructionImporterRejectsUnsafeWrongAndManipulatedXML() throws {
        let unsafe = """
        <!DOCTYPE x [<!ENTITY leak SYSTEM "file:///etc/passwd">]>
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.09">&leak;</Document>
        """
        XCTAssertThrowsError(
            try PainInstructionImporter.parse(data: Data(unsafe.utf8))
        )
        let oldVersion = """
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">
          <CstmrCdtTrfInitn><GrpHdr><MsgId>OLD-1</MsgId></GrpHdr></CstmrCdtTrfInitn>
        </Document>
        """
        XCTAssertThrowsError(
            try PainInstructionImporter.parse(data: Data(oldVersion.utf8))
        )

        var account = FinanceAccount(
            id: UUID(), name: "Konto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.ownerName = "Firma"
        account.iban = "DE89370400440532013000"
        let date = Pain001Exporter.gregorianDate(year: 2026, month: 8, day: 3)
        let order = PaymentOrder(
            id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
            recipientName: "Empfänger", iban: "DE12500105170648489890",
            bic: "", amountMinor: 1_000, currency: "EUR",
            executionDate: date, purpose: "Zweck", endToEndID: "E2E-SAFE",
            status: .draft, idempotencyKey: "safe", bankReference: "",
            createdAt: date, updatedAt: date
        )
        let valid = try Pain001Exporter.export(
            order: order, account: account, createdAt: date,
            messageID: "SAFE-MSG"
        ).data
        let text = try XCTUnwrap(String(data: valid, encoding: .utf8))
        let badControl = text.replacingOccurrences(
            of: "<CtrlSum>10.00</CtrlSum>", with: "<CtrlSum>10.01</CtrlSum>"
        )
        XCTAssertThrowsError(
            try PainInstructionImporter.parse(data: Data(badControl.utf8))
        )
        let badCurrency = text.replacingOccurrences(of: "Ccy=\"EUR\"", with: "Ccy=\"USD\"")
        XCTAssertThrowsError(
            try PainInstructionImporter.parse(data: Data(badCurrency.utf8))
        )
    }

    func testPain001ImportCommitsDraftsBatchAndHistoryExactlyOnce() throws {
        let context = try TestDatabase()
        var account = FinanceAccount(
            id: UUID(), name: "Importkonto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 50_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.ownerName = "Import Firma"
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        try context.store.saveAccount(account)
        let created = Pain001Exporter.gregorianDate(year: 2026, month: 7, day: 31)
        let execution = Pain001Exporter.gregorianDate(year: 2026, month: 8, day: 3)
        let sourceOrders = [
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Empfänger Eins", iban: "DE12500105170648489890",
                bic: "INGDDEFFXXX", amountMinor: 1_100, currency: "EUR",
                executionDate: execution, purpose: "Eins", endToEndID: "IMP-B-1",
                status: .draft, idempotencyKey: "source-1", bankReference: "",
                createdAt: created, updatedAt: created
            ),
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Empfänger Zwei", iban: "DE75512108001245126199",
                bic: "", amountMinor: 2_200, currency: "EUR",
                executionDate: execution, purpose: "Zwei", endToEndID: "IMP-B-2",
                status: .draft, idempotencyKey: "source-2", bankReference: "",
                createdAt: created, updatedAt: created
            )
        ]
        let sourceBatch = PaymentBatch(
            id: UUID(), name: "Quelldatei", kind: .creditTransfer,
            accountID: account.id, requestedDate: execution, status: .draft,
            idempotencyKey: "source-batch", bankReference: "",
            memberOrderIDs: sourceOrders.map(\.id),
            createdAt: created, updatedAt: created
        )
        let data = try Pain001Exporter.export(
            batch: sourceBatch, orders: sourceOrders, account: account,
            createdAt: created, messageID: "IMPORT-BATCH-MSG"
        ).data
        let document = try PainInstructionImporter.parse(data: data)
        let preview = PainInstructionImporter.preview(
            document: document, accounts: try context.store.accounts(),
            payees: [], bankAccounts: [], mandates: []
        )
        XCTAssertEqual(preview.importableCount, 2)
        XCTAssertTrue(preview.matches.allSatisfy(\.canImport))
        let selected = Set(preview.matches.map(\.id))
        try context.store.commitPaymentInstructionImport(
            preview, importing: selected
        )
        XCTAssertEqual(try context.store.paymentOrders().count, 2)
        XCTAssertTrue(try context.store.paymentOrders().allSatisfy {
            $0.status == .draft
        })
        let batch = try XCTUnwrap(context.store.paymentBatches().first)
        XCTAssertEqual(batch.kind, .creditTransfer)
        XCTAssertEqual(batch.memberOrderIDs, preview.matches.map(\.id))
        XCTAssertTrue(try context.store.transactions().isEmpty)
        let history = try XCTUnwrap(context.store.paymentInstructionImports().first)
        XCTAssertEqual(history.recordCount, 2)
        XCTAssertEqual(history.importedCount, 2)
        XCTAssertEqual(
            try context.store.paymentInstructionImportItems(importID: history.id)
                .filter(\.imported).count,
            2
        )
        XCTAssertThrowsError(
            try context.store.commitPaymentInstructionImport(
                preview, importing: selected
            )
        ) { XCTAssertEqual($0 as? FinanceError, .duplicateImport) }
        XCTAssertEqual(try context.store.paymentOrders().count, 2)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testPain008ImportRequiresAndRechecksExactActiveMandate() throws {
        let context = try TestDatabase()
        var account = FinanceAccount(
            id: UUID(), name: "Gläubigerkonto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.ownerName = "Verein Nord"
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        try context.store.saveAccount(account)
        let payee = FinancePayee(
            id: UUID(), canonicalName: "Zahler Süd", aliases: [],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: true
        )
        try context.store.savePayee(payee)
        let bank = FinancePayeeBankAccount(
            id: UUID(), payeeID: payee.id, label: "Lastschrift",
            accountHolder: "Zahler Süd", iban: "DE12500105170648489890",
            bic: "INGDDEFFXXX", bankName: "", isDefault: true,
            isActive: true
        )
        try context.store.savePayeeBankAccount(bank)
        let signed = Pain008Exporter.gregorianDate(year: 2026, month: 1, day: 15)
        let mandate = FinanceSEPAMandate(
            id: UUID(), payeeID: payee.id, reference: "MANDAT-EXAKT",
            signedOn: signed, sequenceType: .recurring,
            note: "", isActive: true
        )
        try context.store.saveSEPAMandate(mandate)
        let due = Pain008Exporter.gregorianDate(year: 2026, month: 8, day: 15)
        let source = DirectDebitOrder(
            id: UUID(), creditorAccountID: account.id,
            debtorPayeeID: payee.id, debtorBankAccountID: bank.id,
            mandateID: mandate.id, creditorName: account.ownerName,
            creditorID: "DE98ZZZ09999999999",
            creditorIBAN: account.iban, creditorBIC: account.bic,
            debtorName: bank.accountHolder, debtorIBAN: bank.iban,
            debtorBIC: bank.bic, amountMinor: 7_700, currency: "EUR",
            collectionDate: due, purpose: "Beitrag", endToEndID: "DD-IMPORT-1",
            mandateReference: mandate.reference, mandateSignedOn: signed,
            sequenceType: .recurring, status: .draft,
            idempotencyKey: "source-dd", bankReference: "",
            createdAt: due, updatedAt: due
        )
        let data = try Pain008Exporter.export(
            order: source, account: account, createdAt: due,
            messageID: "DD-IMPORT-MSG"
        ).data
        let document = try PainInstructionImporter.parse(data: data)
        let preview = PainInstructionImporter.preview(
            document: document, accounts: try context.store.accounts(),
            payees: try context.store.payees(),
            bankAccounts: try context.store.payeeBankAccounts(),
            mandates: try context.store.sepaMandates()
        )
        XCTAssertEqual(preview.importableCount, 1)
        XCTAssertEqual(preview.matches[0].mandateID, mandate.id)
        var inactive = mandate
        inactive.isActive = false
        try context.store.saveSEPAMandate(inactive)
        XCTAssertThrowsError(
            try context.store.commitPaymentInstructionImport(
                preview, importing: [preview.matches[0].id]
            )
        )
        XCTAssertTrue(try context.store.directDebitOrders().isEmpty)
        XCTAssertTrue(try context.store.paymentInstructionImports().isEmpty)
        inactive.isActive = true
        try context.store.saveSEPAMandate(inactive)
        let fresh = PainInstructionImporter.preview(
            document: document, accounts: try context.store.accounts(),
            payees: try context.store.payees(),
            bankAccounts: try context.store.payeeBankAccounts(),
            mandates: try context.store.sepaMandates()
        )
        try context.store.commitPaymentInstructionImport(
            fresh, importing: [fresh.matches[0].id]
        )
        let imported = try XCTUnwrap(context.store.directDebitOrders().first)
        XCTAssertEqual(imported.status, .draft)
        XCTAssertEqual(imported.mandateID, mandate.id)
        XCTAssertTrue(try context.store.transactions().isEmpty)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testPain002ParsesSafelyAndMatchesOnlyFinalExactReference() throws {
        let id = UUID(uuidString: "11111111-2222-4333-A444-555555555555")!
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let order = PaymentOrder(
            id: id, accountID: UUID(), type: .sepaCreditTransfer,
            recipientName: "Müller & Söhne", iban: "DE89370400440532013000",
            bic: "COBADEFFXXX", amountMinor: 12_345, currency: "EUR",
            executionDate: now, purpose: "Rechnung", endToEndID: "E2E-EXAKT-1",
            status: .submitted, idempotencyKey: "pain002-source",
            bankReference: "", createdAt: now, updatedAt: now
        )
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.002.001.10">
          <CstmrPmtStsRpt>
            <GrpHdr><MsgId>STATUS-1</MsgId><CreDtTm>2026-08-01T10:00:00Z</CreDtTm></GrpHdr>
            <OrgnlGrpInfAndSts>
              <OrgnlMsgId>FV-1111111122224333A444555555555555</OrgnlMsgId>
              <OrgnlMsgNmId>pain.001.001.09</OrgnlMsgNmId>
            </OrgnlGrpInfAndSts>
            <OrgnlPmtInfAndSts>
              <OrgnlPmtInfId>PI-1111111122224333A444555555555555</OrgnlPmtInfId>
              <TxInfAndSts>
                <OrgnlEndToEndId>E2E-EXAKT-1</OrgnlEndToEndId>
                <TxSts>ACSC</TxSts>
                <StsRsnInf><Rsn><Cd>G000</Cd></Rsn><AddtlInf>Gebucht &amp; bestätigt</AddtlInf></StsRsnInf>
              </TxInfAndSts>
            </OrgnlPmtInfAndSts>
          </CstmrPmtStsRpt>
        </Document>
        """
        let document = try Pain002Importer.parse(data: Data(xml.utf8))
        XCTAssertEqual(document.messageID, "STATUS-1")
        XCTAssertEqual(document.records.count, 1)
        XCTAssertEqual(document.records[0].proposedStatus, .accepted)
        XCTAssertEqual(document.records[0].reasonText, "Gebucht & bestätigt")
        let preview = Pain002Importer.preview(
            document: document, paymentOrders: [order],
            directDebitOrders: [], batches: []
        )
        XCTAssertEqual(preview.applicableCount, 1)
        XCTAssertEqual(preview.matches[0].targetID, id)
        XCTAssertEqual(preview.matches[0].currentStatus, .submitted)
        XCTAssertEqual(preview.matches[0].proposedStatus, .accepted)

        let pendingXML = xml.replacingOccurrences(of: "ACSC", with: "PDNG")
            .replacingOccurrences(of: "E2E-EXAKT-1", with: "UNBEKANNT")
        let pending = try Pain002Importer.parse(data: Data(pendingXML.utf8))
        let pendingPreview = Pain002Importer.preview(
            document: pending, paymentOrders: [order],
            directDebitOrders: [], batches: []
        )
        XCTAssertEqual(pendingPreview.applicableCount, 0)
        XCTAssertEqual(pendingPreview.unresolvedCount, 1)
        XCTAssertNil(pending.records[0].proposedStatus)
    }

    func testPain002RejectsWrongNamespaceAndExternalEntities() throws {
        let wrongNamespace = """
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.002.001.09">
          <CstmrPmtStsRpt><GrpHdr><MsgId>X-1</MsgId></GrpHdr>
          <OrgnlGrpInfAndSts><OrgnlMsgId>Y-1</OrgnlMsgId><GrpSts>RJCT</GrpSts></OrgnlGrpInfAndSts>
          </CstmrPmtStsRpt>
        </Document>
        """
        XCTAssertThrowsError(
            try Pain002Importer.parse(data: Data(wrongNamespace.utf8))
        )
        let unsafe = """
        <!DOCTYPE x [<!ENTITY leak SYSTEM "file:///etc/passwd">]>
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.002.001.10">&leak;</Document>
        """
        XCTAssertThrowsError(try Pain002Importer.parse(data: Data(unsafe.utf8)))
    }

    func testPain002CommitIsAtomicIdempotentAndMaterializesOnlyACSC() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Statuskonto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 50_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let accepted = PaymentOrder(
            id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
            recipientName: "Akzeptiert GmbH", iban: "DE89370400440532013000",
            bic: "", amountMinor: 12_345, currency: "EUR",
            executionDate: now, purpose: "Akzeptanz", endToEndID: "E2E-ACSC-1",
            status: .draft, idempotencyKey: "pain002-accepted",
            bankReference: "", createdAt: now, updatedAt: now
        )
        let rejected = PaymentOrder(
            id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
            recipientName: "Abgelehnt GmbH", iban: "DE75512108001245126199",
            bic: "", amountMinor: 2_500, currency: "EUR",
            executionDate: now, purpose: "Ablehnung", endToEndID: "E2E-RJCT-1",
            status: .draft, idempotencyKey: "pain002-rejected",
            bankReference: "", createdAt: now, updatedAt: now
        )
        for order in [accepted, rejected] {
            try context.store.createPaymentOrder(order)
            for status in [
                PaymentStatus.initiated, .challengeReceived, .awaitingUser,
                .submitted
            ] {
                try context.store.transitionPaymentOrder(id: order.id, to: status)
            }
        }
        let xml = """
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.002.001.10">
          <CstmrPmtStsRpt>
            <GrpHdr><MsgId>BANK-STATUS-42</MsgId><CreDtTm>2026-08-01T12:00:00Z</CreDtTm></GrpHdr>
            <OrgnlGrpInfAndSts><OrgnlMsgId>EXTERNAL-GROUP</OrgnlMsgId><OrgnlMsgNmId>pain.001.001.09</OrgnlMsgNmId></OrgnlGrpInfAndSts>
            <OrgnlPmtInfAndSts><OrgnlPmtInfId>EXTERNAL-PAYMENT</OrgnlPmtInfId>
              <TxInfAndSts><OrgnlEndToEndId>E2E-ACSC-1</OrgnlEndToEndId><TxSts>ACSC</TxSts><StsRsnInf><Rsn><Cd>G000</Cd></Rsn><AddtlInf>Settlement abgeschlossen</AddtlInf></StsRsnInf></TxInfAndSts>
              <TxInfAndSts><OrgnlEndToEndId>E2E-RJCT-1</OrgnlEndToEndId><TxSts>RJCT</TxSts><StsRsnInf><Rsn><Cd>AC01</Cd></Rsn><AddtlInf>Kontonummer fehlerhaft</AddtlInf></StsRsnInf></TxInfAndSts>
            </OrgnlPmtInfAndSts>
          </CstmrPmtStsRpt>
        </Document>
        """
        let document = try Pain002Importer.parse(data: Data(xml.utf8))
        let preview = Pain002Importer.preview(
            document: document,
            paymentOrders: try context.store.paymentOrders(),
            directDebitOrders: try context.store.directDebitOrders(),
            batches: try context.store.paymentBatches()
        )
        XCTAssertEqual(preview.applicableCount, 2)
        let selected = Set(preview.matches.filter(\.canApply).map(\.id))
        try context.store.commitPaymentStatusReport(preview, applying: selected)

        let byID = Dictionary(uniqueKeysWithValues: try context.store.paymentOrders().map { ($0.id, $0) })
        XCTAssertEqual(byID[accepted.id]?.status, .accepted)
        XCTAssertEqual(byID[rejected.id]?.status, .rejected)
        XCTAssertEqual(byID[accepted.id]?.bankReference, "P002-BANK-STATUS-42")
        XCTAssertEqual(byID[rejected.id]?.bankReference, "P002-BANK-STATUS-42")
        XCTAssertEqual(
            try context.store.transactions().filter {
                $0.reference == "payment:\(accepted.id.uuidString)"
            }.count,
            1
        )
        XCTAssertFalse(try context.store.transactions().contains {
            $0.reference == "payment:\(rejected.id.uuidString)"
        })
        let report = try XCTUnwrap(context.store.paymentStatusReports().first)
        XCTAssertEqual(report.messageID, "BANK-STATUS-42")
        XCTAssertEqual(report.recordCount, 2)
        XCTAssertEqual(report.appliedCount, 2)
        let items = try context.store.paymentStatusReportItems(reportID: report.id)
        XCTAssertEqual(items.map(\.statusCode), ["ACSC", "RJCT"])
        XCTAssertEqual(items.map(\.appliedStatus), [.accepted, .rejected])
        XCTAssertEqual(items.map(\.reasonCode), ["G000", "AC01"])
        XCTAssertThrowsError(
            try context.store.commitPaymentStatusReport(preview, applying: selected)
        ) { XCTAssertEqual($0 as? FinanceError, .duplicateImport) }
        XCTAssertEqual(
            try context.store.transactions().filter {
                $0.reference == "payment:\(accepted.id.uuidString)"
            }.count,
            1
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testPain002ResolvesBatchAtomicallyWithoutApplyingMemberRows() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Sammlerkonto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 100_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let orders = [
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Position Eins", iban: "DE89370400440532013000",
                bic: "", amountMinor: 1_100, currency: "EUR",
                executionDate: now, purpose: "Eins", endToEndID: "BATCH-E2E-1",
                status: .draft, idempotencyKey: "pain002-batch-1",
                bankReference: "", createdAt: now, updatedAt: now
            ),
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Position Zwei", iban: "DE75512108001245126199",
                bic: "", amountMinor: 2_200, currency: "EUR",
                executionDate: now, purpose: "Zwei", endToEndID: "BATCH-E2E-2",
                status: .draft, idempotencyKey: "pain002-batch-2",
                bankReference: "", createdAt: now, updatedAt: now
            )
        ]
        for order in orders { try context.store.createPaymentOrder(order) }
        let batch = PaymentBatch(
            id: UUID(), name: "Statussammler", kind: .creditTransfer,
            accountID: account.id, requestedDate: now, status: .draft,
            idempotencyKey: "pain002-batch", bankReference: "",
            memberOrderIDs: orders.map(\.id), createdAt: now, updatedAt: now
        )
        try context.store.createPaymentBatch(batch)
        for status in [
            PaymentStatus.initiated, .challengeReceived, .awaitingUser,
            .submitted
        ] {
            try context.store.transitionPaymentBatch(id: batch.id, to: status)
        }
        let compact = batch.id.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        let xml = """
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.002.001.10">
          <CstmrPmtStsRpt>
            <GrpHdr><MsgId>BATCH-STATUS-1</MsgId></GrpHdr>
            <OrgnlGrpInfAndSts><OrgnlMsgId>BT-\(compact)</OrgnlMsgId><OrgnlMsgNmId>pain.001.001.09</OrgnlMsgNmId><GrpSts>ACSC</GrpSts></OrgnlGrpInfAndSts>
            <OrgnlPmtInfAndSts><OrgnlPmtInfId>BT-\(compact)</OrgnlPmtInfId>
              <TxInfAndSts><OrgnlEndToEndId>BATCH-E2E-1</OrgnlEndToEndId><TxSts>ACSC</TxSts></TxInfAndSts>
              <TxInfAndSts><OrgnlEndToEndId>BATCH-E2E-2</OrgnlEndToEndId><TxSts>ACSC</TxSts></TxInfAndSts>
            </OrgnlPmtInfAndSts>
          </CstmrPmtStsRpt>
        </Document>
        """
        let document = try Pain002Importer.parse(data: Data(xml.utf8))
        let preview = Pain002Importer.preview(
            document: document,
            paymentOrders: try context.store.paymentOrders(),
            directDebitOrders: [], batches: try context.store.paymentBatches()
        )
        XCTAssertEqual(preview.matches.count, 3)
        XCTAssertEqual(preview.matches.filter(\.canApply).map(\.targetID), [batch.id])
        XCTAssertTrue(preview.matches.dropFirst().allSatisfy {
            !$0.canApply && $0.targetID != nil
        })
        let selected = Set(preview.matches.filter(\.canApply).map(\.id))
        try context.store.commitPaymentStatusReport(preview, applying: selected)
        XCTAssertEqual(try context.store.paymentBatches().first?.status, .accepted)
        XCTAssertEqual(Set(try context.store.paymentOrders().map(\.status)), [.accepted])
        XCTAssertEqual(
            try context.store.transactions().filter {
                $0.reference.hasPrefix("payment:")
            }.count,
            2
        )
        let report = try XCTUnwrap(context.store.paymentStatusReports().first)
        XCTAssertEqual(report.recordCount, 3)
        XCTAssertEqual(report.appliedCount, 1)
        XCTAssertEqual(
            try context.store.paymentStatusReportItems(reportID: report.id)
                .filter { $0.appliedStatus != nil }.count,
            1
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testGermanMoneyParsingUsesMinorUnitsWithoutBinaryFloat() throws {
        XCTAssertEqual(try Money(parsing: "1.234,56 €").minorUnits, 123_456)
        XCTAssertEqual(try Money(parsing: "-0,015").minorUnits, -2)
        XCTAssertEqual(try Money(parsing: "0,005").minorUnits, 0)
    }

    func testGermanMoneyExpressionUsesDecimalPrecedenceAndUnicodeOperators() throws {
        XCTAssertEqual(
            try Money(evaluating: "= (1.234,56 + 5,44) / 2 €").minorUnits,
            62_000
        )
        XCTAssertEqual(try Money(evaluating: "100 + 20 * 3").minorUnits, 16_000)
        XCTAssertEqual(try Money(evaluating: "-(10,00 - 2,50) × 2").minorUnits, -1_500)
        XCTAssertEqual(try Money(evaluating: "5--2").minorUnits, 700)
        XCTAssertEqual(try Money(evaluating: "1 ÷ 3").minorUnits, 33)
    }

    func testGermanMoneyExpressionUsesCurrencyPrecisionAndSymbols() throws {
        XCTAssertEqual(
            try Money(evaluating: "1,234 + 0,001", currency: "KWD").minorUnits,
            1_235
        )
        XCTAssertEqual(try Money(evaluating: "EUR 1,00 + € 2,00").minorUnits, 300)
    }

    func testStrictMoneyParserRejectsExpressions() throws {
        XCTAssertThrowsError(try Money(parsing: "1 + 2"))
    }

    func testGermanMoneyExpressionRejectsMalformedInput() throws {
        for invalid in ["", "1 / 0", "(1 + 2", "1..2", "1 +", "()"] {
            XCTAssertThrowsError(try Money(evaluating: invalid), invalid)
        }
    }

    func testGermanMoneyExpressionRejectsOverflow() throws {
        XCTAssertThrowsError(
            try Money(evaluating: String(repeating: "9", count: 80) + " * 9")
        )
    }

    func testGermanMoneyExpressionRejectsExcessiveNesting() throws {
        XCTAssertThrowsError(
            try Money(evaluating: String(repeating: "(", count: 34) + "1"
                + String(repeating: ")", count: 34))
        )
    }

    @MainActor
    func testTransactionEntryEvaluatesAmountAndForeignCurrencyExpressions() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Rechnerkonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let appStore = FinanceAppStore(repository: context.store)
        XCTAssertTrue(
            appStore.saveTransaction(
                accountID: account.id, date: .now, payee: "Ausdruck",
                purpose: "Grundrechenarten", categoryID: nil,
                amount: "-(100,00 + 23,45) / 2", status: .booked,
                originalAmount: "50 + 11,725", originalCurrency: "USD"
            )
        )
        let stored = try XCTUnwrap(context.store.transactions().first)
        XCTAssertEqual(stored.amountMinor, -6_172)
        XCTAssertEqual(stored.originalAmountMinor, -6_172)
        XCTAssertEqual(stored.originalCurrency, "USD")
        XCTAssertNotNil(stored.exchangeRateScaled)
        XCTAssertFalse(
            appStore.saveTransaction(
                accountID: account.id, date: .now, payee: "Ungültig",
                purpose: "Nullteilung", categoryID: nil,
                amount: "10 / 0", status: .booked
            )
        )
        XCTAssertEqual(try context.store.transactions().count, 1)
    }

    func testMoneyUsesCurrencyMinorUnitsAndExchangeRatesDeterministically() throws {
        XCTAssertEqual(Money.fractionDigits(for: "JPY"), 0)
        XCTAssertEqual(Money.fractionDigits(for: "KWD"), 3)
        XCTAssertEqual(try Money(parsing: "123,5", currency: "JPY").minorUnits, 124)
        XCTAssertEqual(try Money(parsing: "1,234", currency: "KWD").minorUnits, 1_234)

        let rate = try ExchangeRate.derived(
            originalMinor: 10_000,
            originalCurrency: "EUR",
            bookedMinor: 10_950,
            bookedCurrency: "USD"
        )
        XCTAssertEqual(rate.scaledValue, 109_500_000)
        XCTAssertEqual(
            try rate.convertedMinor(
                originalMinor: -10_000,
                originalCurrency: "EUR",
                bookedCurrency: "USD"
            ),
            -10_950
        )
        XCTAssertEqual(try ExchangeRate(parsing: "1,09500000"), rate)
        XCTAssertThrowsError(try ExchangeRate(parsing: "0"))
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

    func testTransferUpdateChangesBothSidesAtomicallyAndSupportsUndo() throws {
        let context = try TestDatabase()
        let source = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 100_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let destination = FinanceAccount(
            id: UUID(), name: "Rücklage", institution: "", type: .savings,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(source)
        try context.store.saveAccount(destination)
        let originalDate = Date(timeIntervalSince1970: 1_735_689_600)
        let editedDate = Date(timeIntervalSince1970: 1_738_368_000)
        try context.store.createTransfer(
            from: source, to: destination, amountMinor: 25_000,
            date: originalDate, purpose: "Erste Rücklage"
        )
        let original = try context.store.transactions()
        let transferID = try XCTUnwrap(original.first?.transferID)
        let originalIDs = Set(original.map(\.id))

        XCTAssertThrowsError(
            try context.store.updateTransfer(
                id: transferID,
                sourceAmountMinor: .min,
                destinationAmountMinor: 40_000,
                date: editedDate,
                purpose: "Darf nicht teilweise schreiben"
            )
        )
        XCTAssertEqual(try context.store.transactions(), original)

        try context.store.updateTransfer(
            id: transferID,
            sourceAmountMinor: 40_000,
            destinationAmountMinor: 40_000,
            date: editedDate,
            purpose: "Erhöhte Rücklage"
        )

        let edited = try context.store.transactions()
        XCTAssertEqual(edited.count, 2)
        XCTAssertEqual(Set(edited.map(\.id)), originalIDs)
        XCTAssertEqual(Set(edited.compactMap(\.transferID)), Set([transferID]))
        XCTAssertEqual(edited.reduce(Int64.zero) { $0 + $1.amountMinor }, 0)
        XCTAssertTrue(edited.allSatisfy { $0.bookingDate == editedDate })
        XCTAssertTrue(edited.allSatisfy { $0.valueDate == editedDate })
        XCTAssertTrue(edited.allSatisfy { $0.purpose == "Erhöhte Rücklage" })
        XCTAssertEqual(edited.first { $0.amountMinor < 0 }?.payee, destination.name)
        XCTAssertEqual(edited.first { $0.amountMinor > 0 }?.payee, source.name)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: source), 60_000)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: destination), 40_000)

        var forbiddenSingleSide = try XCTUnwrap(
            edited.first { $0.amountMinor < 0 }
        )
        forbiddenSingleSide.purpose = "Nur eine Seite"
        XCTAssertThrowsError(
            try context.store.saveTransaction(forbiddenSingleSide)
        )
        XCTAssertTrue(
            try context.store.transactions().allSatisfy {
                $0.purpose == "Erhöhte Rücklage"
            }
        )

        let undo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(undo.title, "Umbuchung bearbeitet")
        XCTAssertEqual(undo.transactionCount, 2)
        XCTAssertEqual(try context.store.undoTransactionMutation(id: undo.id), 2)
        let restored = try context.store.transactions()
        XCTAssertEqual(Set(restored.map(\.id)), originalIDs)
        XCTAssertTrue(restored.allSatisfy { $0.bookingDate == originalDate })
        XCTAssertTrue(restored.allSatisfy { $0.purpose == "Erste Rücklage" })
        XCTAssertEqual(restored.reduce(Int64.zero) { $0 + $1.amountMinor }, 0)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testForeignCurrencyTransferPersistsBothAmountsRatesAndBalances() throws {
        let context = try TestDatabase()
        let euro = FinanceAccount(
            id: UUID(), name: "Eurokonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let dollar = FinanceAccount(
            id: UUID(), name: "Dollarkonto", institution: "",
            type: .foreignCurrency, currency: "USD", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(euro)
        try context.store.saveAccount(dollar)

        try context.store.createTransfer(
            from: euro,
            to: dollar,
            sourceAmountMinor: 10_000,
            destinationAmountMinor: 10_950,
            date: Date(timeIntervalSince1970: 1_735_689_600),
            purpose: "Währungstausch"
        )

        let values = try context.store.transactions()
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(Set(values.compactMap(\.transferID)).count, 1)
        let source = try XCTUnwrap(values.first { $0.accountID == euro.id })
        let destination = try XCTUnwrap(values.first { $0.accountID == dollar.id })
        XCTAssertEqual(source.amountMinor, -10_000)
        XCTAssertEqual(source.currency, "EUR")
        XCTAssertEqual(source.originalAmountMinor, -10_950)
        XCTAssertEqual(source.originalCurrency, "USD")
        XCTAssertNotNil(source.exchangeRateScaled)
        XCTAssertEqual(destination.amountMinor, 10_950)
        XCTAssertEqual(destination.currency, "USD")
        XCTAssertEqual(destination.originalAmountMinor, 10_000)
        XCTAssertEqual(destination.originalCurrency, "EUR")
        XCTAssertEqual(destination.exchangeRateScaled, 109_500_000)
        XCTAssertEqual(source.origin, .transfer)
        XCTAssertEqual(destination.origin, .transfer)
        XCTAssertNoThrow(try source.validate())
        XCTAssertNoThrow(try destination.validate())
        XCTAssertEqual(try context.store.accountBalanceMinor(account: euro), -10_000)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: dollar), 10_950)

        let transferID = try XCTUnwrap(source.transferID)
        let editedDate = Date(timeIntervalSince1970: 1_738_368_000)
        try context.store.updateTransfer(
            id: transferID,
            sourceAmountMinor: 12_000,
            destinationAmountMinor: 13_200,
            date: editedDate,
            purpose: "Währungstausch angepasst"
        )
        let edited = try context.store.transactions()
        let editedSource = try XCTUnwrap(edited.first { $0.accountID == euro.id })
        let editedDestination = try XCTUnwrap(
            edited.first { $0.accountID == dollar.id }
        )
        XCTAssertEqual(editedSource.amountMinor, -12_000)
        XCTAssertEqual(editedSource.originalAmountMinor, -13_200)
        XCTAssertEqual(editedSource.originalCurrency, "USD")
        XCTAssertEqual(editedDestination.amountMinor, 13_200)
        XCTAssertEqual(editedDestination.originalAmountMinor, 12_000)
        XCTAssertEqual(editedDestination.originalCurrency, "EUR")
        XCTAssertEqual(editedDestination.exchangeRateScaled, 110_000_000)
        XCTAssertTrue(edited.allSatisfy { $0.bookingDate == editedDate })
        XCTAssertTrue(edited.allSatisfy {
            $0.purpose == "Währungstausch angepasst"
        })
        XCTAssertEqual(try context.store.accountBalanceMinor(account: euro), -12_000)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: dollar), 13_200)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testForeignCurrencyInvariantsRejectMismatchWithoutPartialWrite() throws {
        let context = try TestDatabase()
        let euro = FinanceAccount(
            id: UUID(), name: "Euro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let secondEuro = FinanceAccount(
            id: UUID(), name: "Euro 2", institution: "", type: .savings,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        let dollar = FinanceAccount(
            id: UUID(), name: "Dollar", institution: "",
            type: .foreignCurrency, currency: "USD", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 2
        )
        try [euro, secondEuro, dollar].forEach(context.store.saveAccount)

        XCTAssertThrowsError(
            try context.store.createTransfer(
                from: euro, to: secondEuro,
                sourceAmountMinor: 1_000, destinationAmountMinor: 999,
                date: Date(), purpose: "Ungültig"
            )
        )
        XCTAssertTrue(try context.store.transactions().isEmpty)

        let mismatch = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: Date(), valueDate: nil,
            payee: "Test", purpose: "Falsche Kontowährung", categoryID: nil,
            amountMinor: -1_000, currency: "USD", status: .booked,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        XCTAssertThrowsError(try context.store.saveTransaction(mismatch))
        XCTAssertTrue(try context.store.transactions().isEmpty)

        let validRate = try ExchangeRate.derived(
            originalMinor: -1_100,
            originalCurrency: "USD",
            bookedMinor: -1_000,
            bookedCurrency: "EUR"
        )
        var foreign = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: Date(), valueDate: nil,
            payee: "Hotel", purpose: "Originalbeleg", categoryID: nil,
            amountMinor: -1_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: [],
            originalAmountMinor: -1_100, originalCurrency: "USD",
            exchangeRateScaled: validRate.scaledValue
        )
        try context.store.saveTransaction(foreign)
        let restored = try XCTUnwrap(context.store.transactions().first)
        XCTAssertEqual(restored.originalAmountMinor, -1_100)
        XCTAssertEqual(restored.originalCurrency, "USD")
        XCTAssertEqual(restored.exchangeRateScaled, validRate.scaledValue)

        foreign.exchangeRateScaled = ExchangeRate.scale
        XCTAssertThrowsError(try context.store.saveTransaction(foreign))
        XCTAssertEqual(try context.store.transactions().count, 1)
    }

    func testMovingTransactionIsAtomicAndProtectsAccountingInvariants() throws {
        let context = try TestDatabase()
        let source = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let destination = FinanceAccount(
            id: UUID(), name: "Haushalt", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        let foreignCurrency = FinanceAccount(
            id: UUID(), name: "Dollar", institution: "", type: .checking,
            currency: "USD", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 2
        )
        let closed = FinanceAccount(
            id: UUID(), name: "Alt", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: true, sortOrder: 3
        )
        try [source, destination, foreignCurrency, closed]
            .forEach(context.store.saveAccount)

        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let firstSplitID = UUID()
        let secondSplitID = UUID()
        let value = FinanceTransaction(
            id: UUID(), accountID: source.id, bookingDate: date,
            valueDate: date, payee: "Vermieter", purpose: "Nebenkosten",
            categoryID: nil, amountMinor: -3_000, currency: "EUR",
            status: .booked, memo: "Vollständig erhalten", reference: "R-42",
            transferID: nil, importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: firstSplitID, categoryID: nil, amountMinor: -2_000,
                    memo: "Heizung", sortOrder: 0
                ),
                FinanceSplit(
                    id: secondSplitID, categoryID: nil, amountMinor: -1_000,
                    memo: "Wasser", sortOrder: 1
                )
            ],
            origin: .manual, externalProvider: "Testbank",
            externalTransactionID: "external-42", counterpartyIBAN: "DE001234",
            endToEndID: "E2E-42", mandateReference: "M-42",
            duplicateFingerprint: "duplicate-42", bankBalanceAfterMinor: 7_000,
            counterpartyBIC: "TESTDEFF", creditorID: "DE98ZZZ09999999999",
            bookingText: "LASTSCHRIFT"
        )
        try context.store.saveTransaction(value)

        try context.store.moveTransaction(id: value.id, toAccountID: destination.id)
        let moved = try XCTUnwrap(
            context.store.transactions().first { $0.id == value.id }
        )
        XCTAssertEqual(moved.accountID, destination.id)
        XCTAssertEqual(moved.splits.map(\.id), [firstSplitID, secondSplitID])
        XCTAssertEqual(moved.splits.map(\.amountMinor), [-2_000, -1_000])
        XCTAssertEqual(moved.memo, value.memo)
        XCTAssertEqual(moved.reference, value.reference)
        XCTAssertEqual(moved.externalTransactionID, value.externalTransactionID)
        XCTAssertEqual(moved.bankBalanceAfterMinor, value.bankBalanceAfterMinor)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: source), 10_000)
        XCTAssertEqual(try context.store.accountBalanceMinor(account: destination), -3_000)

        for invalidDestination in [foreignCurrency.id, closed.id, destination.id] {
            XCTAssertThrowsError(
                try context.store.moveTransaction(
                    id: value.id,
                    toAccountID: invalidDestination
                )
            )
            XCTAssertEqual(
                try context.store.transactions().first { $0.id == value.id }?.accountID,
                destination.id
            )
        }

        let reconciled = FinanceTransaction(
            id: UUID(), accountID: source.id, bookingDate: date,
            valueDate: nil, payee: "Abgeglichen", purpose: "Abschluss",
            categoryID: nil, amountMinor: -100, currency: "EUR",
            status: .reconciled, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(reconciled)
        XCTAssertThrowsError(
            try context.store.moveTransaction(
                id: reconciled.id,
                toAccountID: destination.id
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .protectedTransaction)
        }
        XCTAssertEqual(
            try context.store.transactions().first { $0.id == reconciled.id }?.accountID,
            source.id
        )

        try context.store.createTransfer(
            from: source, to: destination, amountMinor: 500,
            date: date, purpose: "Rücklage"
        )
        let transferSide = try XCTUnwrap(
            context.store.transactions().first { $0.transferID != nil }
        )
        XCTAssertThrowsError(
            try context.store.moveTransaction(
                id: transferSide.id,
                toAccountID: foreignCurrency.id
            )
        )
        XCTAssertEqual(
            try context.store.transactions().first { $0.id == transferSide.id }?.accountID,
            transferSide.accountID
        )
        XCTAssertTrue(try context.store.integrityCheck())
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

    func testCSVImportProfileHandlesEncodingMappingDebitCreditAndFullCategoryPath() throws {
        let account = FinanceAccount(
            id: UUID(), name: "Geschäft", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let root = FinanceCategory(
            id: UUID(), parentID: nil, name: "Immobilien",
            kind: .expense, color: "blue", isActive: true
        )
        let apartment = FinanceCategory(
            id: UUID(), parentID: root.id, name: "Wohnung Köln",
            kind: .expense, color: "blue", isActive: true
        )
        let propertyTax = FinanceCategory(
            id: UUID(), parentID: apartment.id, name: "Grundsteuer",
            kind: .expense, color: "orange", isActive: true
        )
        let text = "Tag\tValuta\tName\tText\tSoll\tHaben\tKategorie\tBank-ID\n"
            + "07/31/2026\t08/01/2026\tStadt Köln\t\"Grundsteuer, Objekt\n"
            + "zweite Zeile\"\t1,234.56\t\tImmobilien:Wohnung Köln:Grundsteuer\tTX-42\n"
            + "08/02/2026\t\tMieter\tErstattung\t\t2,500.00\t\tTX-43\n"
        let data = try XCTUnwrap(text.data(using: .windowsCP1252))
        var profile = CSVImportProfile(
            name: "Bank TSV", encoding: .windows1252, separator: .tab,
            hasHeader: true, dateFormat: .us,
            decimalSeparator: ".", thousandsSeparator: ",",
            amountMode: .debitCredit
        )
        let mappings: [(CSVImportField, Int)] = [
            (.bookingDate, 0), (.valueDate, 1), (.payee, 2),
            (.purpose, 3), (.debit, 4), (.credit, 5),
            (.category, 6), (.externalTransactionID, 7)
        ]
        mappings.forEach { profile.setColumn($0.1, for: $0.0) }

        let inspection = try CSVFinanceImporter.inspect(
            data: data, profile: profile
        )
        XCTAssertEqual(inspection.columns.first, "Tag")
        XCTAssertEqual(inspection.rowCount, 2)
        XCTAssertTrue(inspection.sampleRows[0][3].contains("zweite Zeile"))

        let preview = try CSVFinanceImporter.preview(
            data: data, account: account, profile: profile,
            categories: [root, apartment, propertyTax]
        )
        XCTAssertTrue(preview.rejectedRows.isEmpty)
        XCTAssertEqual(preview.rows.count, 2)
        XCTAssertEqual(preview.rows.map(\.amountMinor), [-123_456, 250_000])
        XCTAssertEqual(preview.rows[0].categoryID, propertyTax.id)
        XCTAssertEqual(preview.rows[0].externalProvider, "CSV")
        XCTAssertEqual(preview.rows[0].externalTransactionID, "TX-42")
        XCTAssertEqual(preview.rows[0].purpose, "Grundsteuer, Objekt\nzweite Zeile")
        XCTAssertNotNil(preview.rows[0].valueDate)
        XCTAssertNil(preview.rows[1].valueDate)
    }

    func testCSVImportProfileReportsRowErrorsAndRejectsMalformedStructure() throws {
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        var profile = CSVImportProfile(amountMode: .debitCredit)
        profile.setColumn(0, for: .bookingDate)
        profile.setColumn(1, for: .debit)
        profile.setColumn(2, for: .credit)
        let data = Data(
            "Datum;Soll;Haben\n31.07.2026;10,00;20,00\n99.99.2026;1,00;".utf8
        )
        let preview = try CSVFinanceImporter.preview(
            data: data, account: account, profile: profile
        )
        XCTAssertTrue(preview.rows.isEmpty)
        XCTAssertEqual(preview.rejectedRows.count, 2)
        XCTAssertTrue(preview.rejectedRows[0].contains("gleichzeitig"))
        XCTAssertTrue(preview.rejectedRows[1].contains("Buchungsdatum"))

        let malformed = Data("Datum;Betrag\n\"31.07.2026;10,00".utf8)
        XCTAssertThrowsError(
            try CSVFinanceImporter.inspect(data: malformed, profile: profile)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("nicht geschlossen"))
        }
    }

    func testCSVImportProfileDetectionAndVersionedPersistenceAreDeterministic() throws {
        let data = Data(
            "Datum;Empfänger;Verwendungszweck;Betrag\n31.07.2026;Bäcker;Brötchen;-4,20".utf8
        )
        var profile = try CSVFinanceImporter.suggestedProfile(data: data)
        XCTAssertEqual(profile.encoding, .utf8)
        XCTAssertEqual(profile.separator, .semicolon)
        XCTAssertEqual(profile.dateFormat, .germanLong)
        XCTAssertEqual(profile.column(for: .bookingDate), 0)
        XCTAssertEqual(profile.column(for: .payee), 1)
        XCTAssertEqual(profile.column(for: .purpose), 2)
        XCTAssertEqual(profile.column(for: .amount), 3)

        profile.name = "Hausbank"
        let first = CSVImportProfileLibrary.upserting(profile, into: [])
        XCTAssertEqual(first.first?.revision, 1)
        profile = try XCTUnwrap(first.first)
        profile.separator = .tab
        let second = CSVImportProfileLibrary.upserting(profile, into: first)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.revision, 2)
        XCTAssertEqual(second.first?.separator, .tab)
        let encoded = try CSVImportProfileLibrary.encode(second)
        XCTAssertEqual(try CSVImportProfileLibrary.decode(encoded), second)

        var future = profile
        future.schema = CSVImportProfile.schemaVersion + 1
        let futureData = try JSONEncoder().encode([future])
        XCTAssertThrowsError(try CSVImportProfileLibrary.decode(futureData))
    }

    func testCSVImportProfileExchangeRoundTripsOnlyPortableRules() throws {
        var profile = CSVImportProfile(
            id: UUID(uuidString: "D407825C-9F69-45C7-95F4-68DC25C15A75")!,
            name: "Hausbank TSV",
            revision: 7,
            encoding: .windows1252,
            separator: .tab,
            hasHeader: true,
            dateFormat: .germanLong,
            decimalSeparator: ",",
            thousandsSeparator: ".",
            amountMode: .debitCredit
        )
        profile.setColumn(0, for: .bookingDate)
        profile.setColumn(4, for: .debit)
        profile.setColumn(5, for: .credit)
        profile.setColumn(6, for: .category)

        let data = try CSVImportProfileLibrary.encodeExchange(profile)
        XCTAssertLessThan(data.count, CSVImportProfileLibrary.maximumExchangeBytes)
        XCTAssertEqual(try CSVImportProfileLibrary.decodeExchange(data), profile)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains(CSVImportProfileExchangeEnvelope.formatIdentifier))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("account"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("transaction"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("bookingData"))
    }

    func testCSVImportProfileExchangeRejectsUnexpectedAndOversizedInput() throws {
        var profile = CSVImportProfile(name: "Strenges Profil")
        profile.setColumn(0, for: .bookingDate)
        profile.setColumn(1, for: .amount)
        let data = try CSVImportProfileLibrary.encodeExchange(profile)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["unexpected"] = true
        let unexpected = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try CSVImportProfileLibrary.decodeExchange(unexpected)
        )

        object.removeValue(forKey: "unexpected")
        object["formatVersion"] =
            CSVImportProfileExchangeEnvelope.formatVersion + 1
        let futureFormat = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try CSVImportProfileLibrary.decodeExchange(futureFormat)
        )

        var invalidProfile = profile
        invalidProfile.mappings["unknownField"] = 9
        let invalidEnvelope = CSVImportProfileExchangeEnvelope(
            profile: invalidProfile
        )
        let invalidData = try JSONEncoder().encode(invalidEnvelope)
        XCTAssertThrowsError(
            try CSVImportProfileLibrary.decodeExchange(invalidData)
        )

        let oversized = Data(
            repeating: 0x20,
            count: CSVImportProfileLibrary.maximumExchangeBytes + 1
        )
        XCTAssertThrowsError(
            try CSVImportProfileLibrary.decodeExchange(oversized)
        )
    }

    func testCSVImportProfileExchangeResolvesIdentifierAndNameConflicts() throws {
        let id = UUID()
        let existing = CSVImportProfile(id: id, name: "Hausbank", revision: 2)
        var changed = existing
        changed.revision = 3
        changed.separator = .tab

        XCTAssertEqual(
            CSVImportProfileLibrary.conflict(for: existing, in: [existing]),
            .identical
        )
        XCTAssertEqual(
            CSVImportProfileLibrary.conflict(for: changed, in: [existing]),
            .identifier(existing)
        )
        XCTAssertThrowsError(
            try CSVImportProfileLibrary.merging(changed, into: [existing])
        )
        let replaced = try CSVImportProfileLibrary.merging(
            changed,
            into: [existing],
            strategy: .replace
        )
        XCTAssertEqual(replaced, [changed])

        let sameName = CSVImportProfile(name: "hausbank")
        XCTAssertEqual(
            CSVImportProfileLibrary.conflict(for: sameName, in: [existing]),
            .name(existing)
        )
        let copied = try CSVImportProfileLibrary.merging(
            sameName,
            into: [existing],
            strategy: .copy
        )
        XCTAssertEqual(copied.count, 2)
        let importedCopy = try XCTUnwrap(copied.first { $0.id != existing.id })
        XCTAssertNotEqual(importedCopy.id, sameName.id)
        XCTAssertEqual(importedCopy.revision, 1)
        XCTAssertEqual(importedCopy.name, "hausbank (Import)")

        let other = CSVImportProfile(name: "Zweitbank")
        var doubleConflict = changed
        doubleConflict.name = other.name
        XCTAssertThrowsError(
            try CSVImportProfileLibrary.merging(
                doubleConflict,
                into: [existing, other],
                strategy: .replace
            )
        )
        let safeCopy = try CSVImportProfileLibrary.merging(
            doubleConflict,
            into: [existing, other],
            strategy: .copy
        )
        XCTAssertEqual(safeCopy.count, 3)
        XCTAssertTrue(safeCopy.contains(existing))
        XCTAssertTrue(safeCopy.contains(other))
    }

    func testCSVImportProfileSupportsHeaderlessFilesAndRejectsUnknownCategories() throws {
        let account = FinanceAccount(
            id: UUID(), name: "Kasse", institution: "", type: .cash,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        var profile = CSVImportProfile(
            separator: .semicolon, hasHeader: false,
            dateFormat: .germanShort, amountMode: .signed
        )
        profile.setColumn(0, for: .bookingDate)
        profile.setColumn(1, for: .payee)
        profile.setColumn(2, for: .amount)
        profile.setColumn(3, for: .category)
        let data = Data(
            "1.8.26;Bäckerei;-4,20;Lebensmittel\n2.8.26;Kiosk;-3,10;Unbekannt".utf8
        )
        let food = FinanceCategory(
            id: UUID(), parentID: nil, name: "Lebensmittel",
            kind: .expense, color: "green", isActive: true
        )

        let inspection = try CSVFinanceImporter.inspect(data: data, profile: profile)
        XCTAssertEqual(inspection.columns, ["Spalte 1", "Spalte 2", "Spalte 3", "Spalte 4"])
        XCTAssertEqual(inspection.rowCount, 2)
        let preview = try CSVFinanceImporter.preview(
            data: data, account: account, profile: profile, categories: [food]
        )
        XCTAssertEqual(preview.rows.count, 1)
        XCTAssertEqual(preview.rows.first?.amountMinor, -420)
        XCTAssertEqual(preview.rows.first?.categoryID, food.id)
        XCTAssertEqual(preview.rejectedRows.count, 1)
        XCTAssertTrue(preview.rejectedRows[0].contains("Unbekannt"))
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
        XCTAssertThrowsError(try context.store.backup(to: backupURL))
        XCTAssertThrowsError(try context.store.backup(to: context.store.fileURL))
    }

    func testAutomaticBackupHonorsChangesIntervalsValidationAndRotation() throws {
        let context = try TestDatabase()
        let directory = context.directory.appendingPathComponent("Autosicherungen")
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let policy = AutomaticBackupPolicy(
            isEnabled: true,
            minimumIntervalHours: 24,
            maximumBackupCount: 2,
            maximumAgeDays: 30
        )

        let first = try AutomaticBackupManager.perform(
            repository: context.store,
            directory: directory,
            policy: policy,
            now: start,
            sourceModifiedAt: start.addingTimeInterval(-60)
        )
        guard case let .created(firstURL, firstRemoved) = first else {
            return XCTFail("Erste Autosicherung wurde nicht erstellt: \(first)")
        }
        XCTAssertEqual(firstRemoved, 0)
        XCTAssertNoThrow(try SQLiteFinanceStore.validateBackup(at: firstURL))

        XCTAssertEqual(
            try AutomaticBackupManager.perform(
                repository: context.store,
                directory: directory,
                policy: policy,
                now: start.addingTimeInterval(3_600),
                sourceModifiedAt: start.addingTimeInterval(1_800)
            ),
            .notDue
        )
        XCTAssertEqual(
            try AutomaticBackupManager.perform(
                repository: context.store,
                directory: directory,
                policy: policy,
                now: start.addingTimeInterval(25 * 3_600),
                sourceModifiedAt: start.addingTimeInterval(-60)
            ),
            .unchanged
        )

        let secondTime = start.addingTimeInterval(26 * 3_600)
        let second = try AutomaticBackupManager.perform(
            repository: context.store,
            directory: directory,
            policy: policy,
            now: secondTime,
            sourceModifiedAt: secondTime
        )
        guard case let .created(secondURL, secondRemoved) = second else {
            return XCTFail("Geänderte Datei wurde nicht gesichert: \(second)")
        }
        XCTAssertEqual(secondRemoved, 0)
        XCTAssertNoThrow(try SQLiteFinanceStore.validateBackup(at: secondURL))

        let thirdTime = start.addingTimeInterval(27 * 3_600)
        let third = try AutomaticBackupManager.perform(
            repository: context.store,
            directory: directory,
            policy: policy,
            now: thirdTime,
            force: true,
            sourceModifiedAt: thirdTime
        )
        guard case let .created(thirdURL, thirdRemoved) = third else {
            return XCTFail("Erzwungene Sicherung wurde nicht erstellt: \(third)")
        }
        XCTAssertEqual(thirdRemoved, 1)
        let retained = try AutomaticBackupManager.backups(in: directory)
        XCTAssertEqual(retained.count, 2)
        XCTAssertEqual(
            retained.first?.url.standardizedFileURL,
            thirdURL.standardizedFileURL
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        for backup in retained {
            XCTAssertNoThrow(try SQLiteFinanceStore.validateBackup(at: backup.url))
        }

        let agedTime = start.addingTimeInterval(60 * 86_400)
        let aged = try AutomaticBackupManager.perform(
            repository: context.store,
            directory: directory,
            policy: AutomaticBackupPolicy(
                isEnabled: true,
                minimumIntervalHours: 24,
                maximumBackupCount: 10,
                maximumAgeDays: 30
            ),
            now: agedTime,
            force: true,
            sourceModifiedAt: agedTime
        )
        guard case let .created(agedURL, agedRemoved) = aged else {
            return XCTFail("Altersrotation wurde nicht ausgeführt: \(aged)")
        }
        XCTAssertEqual(agedRemoved, 2)
        let afterAgeRotation = try AutomaticBackupManager.backups(in: directory)
        XCTAssertEqual(afterAgeRotation.map { $0.url.standardizedFileURL }, [
            agedURL.standardizedFileURL
        ])
        XCTAssertNoThrow(try SQLiteFinanceStore.validateBackup(at: agedURL))

        XCTAssertEqual(
            try AutomaticBackupManager.perform(
                repository: context.store,
                directory: directory,
                policy: AutomaticBackupPolicy(isEnabled: false),
                now: agedTime.addingTimeInterval(3_600),
                sourceModifiedAt: agedTime.addingTimeInterval(3_600)
            ),
            .disabled
        )
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

    func testBulkOrganizationReplacesTagsAtomicallyAndKeepsCategories() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = try XCTUnwrap(try context.store.categories().first(where: \.isActive))
        let oldTag = FinanceTag(
            id: UUID(), parentID: nil, name: "Alt", color: "gray",
            description: "", isActive: true
        )
        let newTag = FinanceTag(
            id: UUID(), parentID: nil, name: "Neu", color: "blue",
            description: "", isActive: true
        )
        try context.store.saveTag(oldTag)
        try context.store.saveTag(newTag)
        let editable = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "Markt", purpose: "Einkauf", categoryID: category.id,
            amountMinor: -2_500, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [], tagIDs: [oldTag.id]
        )
        let split = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "Kaufhaus", purpose: "Aufgeteilt", categoryID: nil,
            amountMinor: -1_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: category.id, amountMinor: -1_000,
                    memo: "", sortOrder: 0, tagIDs: [oldTag.id]
                )
            ],
            tagIDs: [oldTag.id]
        )
        let reconciled = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(), valueDate: nil,
            payee: "Versorger", purpose: "Abgeglichen", categoryID: nil,
            amountMinor: -4_000, currency: "EUR", status: .reconciled,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [], tagIDs: [oldTag.id]
        )
        try context.store.saveTransaction(editable)
        try context.store.saveTransaction(split)
        try context.store.saveTransaction(reconciled)

        let result = try context.store.bulkUpdateTransactionOrganization(
            ids: [editable.id, split.id],
            updateCategory: false,
            categoryID: nil,
            replacementTagIDs: [newTag.id]
        )
        XCTAssertEqual(result.updatedCount, 2)
        XCTAssertEqual(result.totalsByCurrency, ["EUR": -3_500])
        var restored = try context.store.transactions()
        XCTAssertEqual(
            restored.first(where: { $0.id == editable.id })?.categoryID,
            category.id
        )
        XCTAssertEqual(
            Set(restored.first(where: { $0.id == editable.id })?.tagIDs ?? []),
            [newTag.id]
        )
        XCTAssertEqual(
            Set(restored.first(where: { $0.id == split.id })?.tagIDs ?? []),
            [newTag.id]
        )
        XCTAssertEqual(
            Set(restored.first(where: { $0.id == split.id })?.splits.first?.tagIDs ?? []),
            [oldTag.id]
        )

        XCTAssertThrowsError(
            try context.store.bulkUpdateTransactionOrganization(
                ids: [editable.id, reconciled.id],
                updateCategory: false,
                categoryID: nil,
                replacementTagIDs: [oldTag.id]
            )
        ) { error in
            XCTAssertEqual(error as? FinanceError, .protectedBulkEdit)
        }
        restored = try context.store.transactions()
        XCTAssertEqual(
            Set(restored.first(where: { $0.id == editable.id })?.tagIDs ?? []),
            [newTag.id]
        )
        XCTAssertEqual(
            Set(restored.first(where: { $0.id == reconciled.id })?.tagIDs ?? []),
            [oldTag.id]
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testTransactionFlagRoundTripsSearchesBulkUpdatesAndUndoes() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Kennzeichenkonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let transaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Prüffall", purpose: "Farbige Fahne",
            categoryID: nil, amountMinor: -1_234, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: [], flag: .purple
        )
        try context.store.saveTransaction(transaction)

        let restored = try XCTUnwrap(
            try context.store.transactions().first { $0.id == transaction.id }
        )
        XCTAssertEqual(restored.flag, .purple)
        let document = RegisterSearchIndex.document(
            transaction: restored, accountName: account.name,
            categoryPath: "Nicht kategorisiert", tagPaths: [],
            runningBalanceMinor: -1_234
        )
        XCTAssertTrue(document.matches(RegisterSearchQuery("violett fahne")))
        XCTAssertEqual(TransactionTemplate(name: "Mit Kennzeichen", transaction: restored).transaction().flag, .purple)

        let result = try context.store.bulkUpdateTransactionOrganization(
            ids: [transaction.id], updateCategory: false, categoryID: nil,
            replacementTagIDs: nil, updateFlag: true, flag: .green
        )
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(try context.store.transactions().first?.flag, .green)
        let undo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(try context.store.undoTransactionMutation(id: undo.id), 1)
        XCTAssertEqual(try context.store.transactions().first?.flag, .purple)
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

    func testTransactionCreatesCompleteScheduledDraftAndRoundTripsPayload() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(
                calendar.date(
                    from: DateComponents(
                        year: year, month: month, day: day, hour: 12
                    )
                )
            )
        }
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Serienkonto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let firstCategoryID = UUID()
        let secondCategoryID = UUID()
        let topTagID = UUID()
        let splitTagID = UUID()
        let rate = try ExchangeRate.derived(
            originalMinor: -13_500, originalCurrency: "USD",
            bookedMinor: -12_345, bookedCurrency: "EUR"
        )
        let source = FinanceTransaction(
            id: UUID(), accountID: account.id,
            bookingDate: try date(2026, 1, 31),
            valueDate: try date(2026, 2, 2),
            payee: "Hausverwaltung", purpose: "Miete und Nebenkosten",
            categoryID: nil, amountMinor: -12_345, currency: "EUR",
            status: .reconciled, memo: "Vertrag 42", reference: "BANK-ALT",
            transferID: nil, importFingerprint: "privat-alt",
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: firstCategoryID,
                    amountMinor: -10_000, memo: "Kaltmiete", sortOrder: 0,
                    tagIDs: [splitTagID]
                ),
                FinanceSplit(
                    id: UUID(), categoryID: secondCategoryID,
                    amountMinor: -2_345, memo: "Nebenkosten", sortOrder: 1
                )
            ],
            payeeID: UUID(), tagIDs: [topTagID], origin: .fileImport,
            externalProvider: "Bank", externalTransactionID: "EXT-ALT",
            duplicateFingerprint: "DUP-ALT", bankBalanceAfterMinor: 99_999,
            originalAmountMinor: -13_500, originalCurrency: "USD",
            exchangeRateScaled: rate.scaledValue
        )
        try source.validate()
        let now = try date(2026, 8, 7)
        let draft = try ScheduledTransaction.draft(
            from: source, now: now, calendar: calendar
        )
        XCTAssertEqual(draft.name, "Hausverwaltung")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: draft.nextDueDate),
            DateComponents(year: 2026, month: 8, day: 31)
        )
        XCTAssertEqual(draft.transactionTemplate?.splits.count, 2)
        XCTAssertEqual(draft.transactionTemplate?.tagIDs, [topTagID])
        XCTAssertEqual(draft.transactionTemplate?.originalCurrency, "USD")

        try context.store.saveScheduledTransaction(draft)
        let loaded = try XCTUnwrap(
            context.store.scheduledTransactions().first { $0.id == draft.id }
        )
        XCTAssertEqual(loaded.transactionTemplate, draft.transactionTemplate)
        let occurrence = try XCTUnwrap(
            loaded.occurrences(
                until: loaded.nextDueDate, calendar: calendar
            ).first
        )
        XCTAssertEqual(occurrence.splits.map(\.amountMinor), [-10_000, -2_345])
        XCTAssertEqual(occurrence.splits.first?.tagIDs, [splitTagID])
        XCTAssertEqual(occurrence.tagIDs, [topTagID])
        XCTAssertEqual(occurrence.originalAmountMinor, -13_500)
        XCTAssertEqual(occurrence.originalCurrency, "USD")
        XCTAssertEqual(occurrence.status, .expected)
        XCTAssertEqual(occurrence.origin, .manual)
        XCTAssertEqual(occurrence.externalProvider, "")
        XCTAssertEqual(occurrence.externalTransactionID, "")
        XCTAssertNil(occurrence.importFingerprint)
        XCTAssertTrue(occurrence.memo.contains("Vertrag 42"))
        XCTAssertTrue(occurrence.memo.contains("Regelmäßig: Hausverwaltung"))
        XCTAssertNoThrow(try occurrence.validate())

        let changed = try XCTUnwrap(
            loaded.occurrences(
                until: loaded.nextDueDate,
                exceptions: [
                    ScheduledTransactionException(
                        id: UUID(), scheduledTransactionID: loaded.id,
                        originalDueDate: loaded.nextDueDate,
                        effectiveDate: loaded.nextDueDate,
                        payee: "Hausverwaltung", purpose: "Einmal reduziert",
                        categoryID: nil, amountMinor: -11_000,
                        disposition: .modified, note: "",
                        createdAt: now, updatedAt: now
                    )
                ], calendar: calendar
            ).first
        )
        XCTAssertTrue(changed.splits.isEmpty)
        XCTAssertNil(changed.originalAmountMinor)
        XCTAssertEqual(changed.originalCurrency, "")
        XCTAssertNoThrow(try changed.validate())
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testMigration37To38AddsScheduledPayloadWithoutChangingLegacySchedule() throws {
        let context = try TestDatabase()
        let url = context.store.fileURL
        let account = FinanceAccount(
            id: UUID(), name: "Bestandskonto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 12_300,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let schedule = ScheduledTransaction(
            id: UUID(), name: "Bestandsserie", accountID: account.id,
            payee: "Vermieter", purpose: "Miete", categoryID: nil,
            amountMinor: -100_000, currency: "EUR", nextDueDate: .now,
            endDate: nil, frequency: .monthly, action: .remind,
            reminderDays: 5, isActive: true
        )
        try context.store.saveScheduledTransaction(schedule)
        context.store.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                """
                ALTER TABLE scheduled_transactions DROP COLUMN transaction_template_json;
                PRAGMA user_version=37;
                """,
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertEqual(
            try sqliteScalar(
                url,
                "SELECT COUNT(*) FROM pragma_table_info('scheduled_transactions') WHERE name='transaction_template_json'"
            ),
            1
        )
        let preserved = try XCTUnwrap(
            migrated.scheduledTransactions().first { $0.id == schedule.id }
        )
        XCTAssertEqual(preserved.name, schedule.name)
        XCTAssertEqual(preserved.amountMinor, schedule.amountMinor)
        XCTAssertNil(preserved.transactionTemplate)
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testMigration38To39AddsCompleteAccountMasterDataWithoutChangingLegacyAccount() throws {
        let context = try TestDatabase()
        let url = context.store.fileURL
        let legacy = FinanceAccount(
            id: UUID(), name: "Bestandskonto", institution: "Altbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 45_600,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(legacy)
        context.store.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                """
                DROP INDEX accounts_linked_account;
                ALTER TABLE accounts DROP COLUMN linked_account_id;
                ALTER TABLE accounts DROP COLUMN closing_date;
                ALTER TABLE accounts DROP COLUMN opening_balance_date;
                ALTER TABLE accounts DROP COLUMN bank_code;
                ALTER TABLE accounts DROP COLUMN subtype;
                PRAGMA user_version=38;
                """,
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        for column in [
            "subtype", "bank_code", "opening_balance_date",
            "closing_date", "linked_account_id"
        ] {
            XCTAssertEqual(
                try sqliteScalar(
                    url,
                    "SELECT COUNT(*) FROM pragma_table_info('accounts') WHERE name='\(column)'"
                ),
                1
            )
        }
        let preserved = try XCTUnwrap(
            migrated.accounts().first { $0.id == legacy.id }
        )
        XCTAssertEqual(preserved.name, legacy.name)
        XCTAssertEqual(preserved.openingBalanceMinor, legacy.openingBalanceMinor)
        XCTAssertEqual(preserved.subtype, "")
        XCTAssertEqual(preserved.bankCode, "")
        XCTAssertNil(preserved.openingBalanceDate)
        XCTAssertNil(preserved.closingDate)
        XCTAssertNil(preserved.linkedAccountID)
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testMigration39To40AddsTransactionFlagWithoutChangingLegacyBooking() throws {
        let context = try TestDatabase()
        let url = context.store.fileURL
        let account = FinanceAccount(
            id: UUID(), name: "Altbestand", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let legacy = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Alt", purpose: "Bleibt erhalten",
            categoryID: nil, amountMinor: -500, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(legacy)
        context.store.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "DROP INDEX transactions_flag; ALTER TABLE transactions DROP COLUMN flag_color; PRAGMA user_version=39;",
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        defer { migrated.close() }
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertEqual(
            try sqliteScalar(
                url,
                "SELECT COUNT(*) FROM pragma_table_info('transactions') WHERE name='flag_color'"
            ),
            1
        )
        let preserved = try XCTUnwrap(
            migrated.transactions().first { $0.id == legacy.id }
        )
        XCTAssertEqual(preserved.payee, legacy.payee)
        XCTAssertEqual(preserved.amountMinor, legacy.amountMinor)
        XCTAssertNil(preserved.flag)
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testCompleteAccountMasterDataRoundTripsSearchesAndRejectsInvalidRelations() throws {
        let context = try TestDatabase()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let opening = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2017, month: 4, day: 3)
        ))
        let balanceDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2017, month: 4, day: 5)
        ))
        let closing = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 7)
        ))
        let linked = FinanceAccount(
            id: UUID(), name: "Verrechnung Depot", institution: "Musterbank",
            type: .clearing, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(linked)
        let complete = FinanceAccount(
            id: UUID(), name: "Festgeld 2026", institution: "Musterbank",
            type: .savings, currency: "EUR", openingBalanceMinor: 250_000,
            isHidden: false, isClosed: true, sortOrder: 1,
            openingDate: opening, creditLimitMinor: 0,
            subtype: "Festgeld 24 Monate", bankCode: "1234 5678",
            openingBalanceDate: balanceDate, closingDate: closing,
            linkedAccountID: linked.id
        )
        try context.store.saveAccount(complete)

        let loaded = try XCTUnwrap(
            context.store.accounts().first { $0.id == complete.id }
        )
        XCTAssertEqual(loaded.subtype, "Festgeld 24 Monate")
        XCTAssertEqual(loaded.bankCode, "12345678")
        XCTAssertEqual(loaded.openingBalanceDate, balanceDate)
        XCTAssertEqual(loaded.closingDate, closing)
        XCTAssertEqual(loaded.linkedAccountID, linked.id)
        let searchText = RegisterSearchIndex.accountSearchText(loaded)
        XCTAssertTrue(searchText.contains("Festgeld 24 Monate"))
        XCTAssertTrue(searchText.contains("12345678"))
        XCTAssertTrue(searchText.contains("05.04.2017"))
        XCTAssertTrue(searchText.contains("07.08.2026"))

        var invalid = complete
        invalid.bankCode = "1234567X"
        XCTAssertThrowsError(try context.store.saveAccount(invalid))
        invalid = complete
        invalid.linkedAccountID = invalid.id
        XCTAssertThrowsError(try context.store.saveAccount(invalid))
        invalid = complete
        invalid.linkedAccountID = UUID()
        XCTAssertThrowsError(try context.store.saveAccount(invalid))
        invalid = complete
        invalid.isClosed = false
        XCTAssertThrowsError(try context.store.saveAccount(invalid))
        invalid = complete
        invalid.openingBalanceDate = calendar.date(
            byAdding: .day, value: -1, to: opening
        )
        XCTAssertThrowsError(try context.store.saveAccount(invalid))
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testScheduledOccurrenceExceptionsModifySkipPersistAndResetExactlyOnce() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(
                calendar.date(
                    from: DateComponents(
                        year: year, month: month, day: day, hour: 12
                    )
                )
            )
        }

        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Prognosekonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = try XCTUnwrap(
            context.store.categories().first { $0.kind == .expense }
        )
        let schedule = ScheduledTransaction(
            id: UUID(), name: "Monatliche Miete", accountID: account.id,
            payee: "Vermieter", purpose: "Miete", categoryID: category.id,
            amountMinor: -100_000, currency: "EUR",
            nextDueDate: try date(2024, 1, 31),
            endDate: try date(2024, 4, 30), frequency: .monthly,
            action: .remind, reminderDays: 5, isActive: true
        )
        try context.store.saveScheduledTransaction(schedule)
        let february = try date(2024, 2, 29)
        let march = try date(2024, 3, 31)
        let modifiedID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try context.store.saveScheduledTransactionException(
            ScheduledTransactionException(
                id: modifiedID, scheduledTransactionID: schedule.id,
                originalDueDate: february, effectiveDate: try date(2024, 3, 2),
                payee: "Hausverwaltung", purpose: "Miete angepasst",
                categoryID: nil, amountMinor: -120_000,
                disposition: .modified, note: "Einmalige Anpassung",
                createdAt: now, updatedAt: now
            )
        )
        try context.store.saveScheduledTransactionException(
            ScheduledTransactionException(
                id: UUID(), scheduledTransactionID: schedule.id,
                originalDueDate: march, effectiveDate: march,
                payee: schedule.payee, purpose: schedule.purpose,
                categoryID: schedule.categoryID, amountMinor: schedule.amountMinor,
                disposition: .skipped, note: "Ausgesetzt",
                createdAt: now, updatedAt: now
            )
        )

        var exceptions = try context.store.scheduledTransactionExceptions()
        XCTAssertEqual(exceptions.count, 2)
        XCTAssertEqual(exceptions.first { $0.originalDueDate < march }?.id, modifiedID)
        let loadedSchedule = try XCTUnwrap(
            context.store.scheduledTransactions().first { $0.id == schedule.id }
        )
        let occurrences = loadedSchedule.occurrences(
            until: try date(2024, 4, 30), exceptions: exceptions,
            calendar: calendar
        )
        XCTAssertEqual(occurrences.count, 3)
        XCTAssertEqual(
            occurrences.map { calendar.component(.day, from: $0.bookingDate) },
            [31, 2, 30]
        )
        let modified = try XCTUnwrap(
            occurrences.first { $0.payee == "Hausverwaltung" }
        )
        XCTAssertEqual(modified.amountMinor, -120_000)
        XCTAssertEqual(modified.purpose, "Miete angepasst")
        XCTAssertNil(modified.categoryID)
        let identity = try XCTUnwrap(
            ScheduledTransaction.occurrenceIdentity(from: modified.reference)
        )
        XCTAssertEqual(identity.scheduledTransactionID, schedule.id)
        XCTAssertTrue(calendar.isDate(identity.originalDueDate, inSameDayAs: february))
        XCTAssertTrue(
            loadedSchedule.occurrences(
                until: try date(2024, 4, 30),
                excludingReferences: [modified.reference],
                exceptions: exceptions, calendar: calendar
            ).allSatisfy { $0.reference != modified.reference }
        )

        try context.store.saveScheduledTransactionException(
            ScheduledTransactionException(
                id: UUID(), scheduledTransactionID: schedule.id,
                originalDueDate: february, effectiveDate: try date(2024, 3, 3),
                payee: "Hausverwaltung neu", purpose: "Korrigiert",
                categoryID: category.id, amountMinor: -121_000,
                disposition: .modified, note: "Ersetzt",
                createdAt: now, updatedAt: now
            )
        )
        exceptions = try context.store.scheduledTransactionExceptions()
        XCTAssertEqual(exceptions.count, 2)
        XCTAssertEqual(exceptions.first { $0.originalDueDate < march }?.id, modifiedID)
        XCTAssertEqual(exceptions.first { $0.originalDueDate < march }?.amountMinor, -121_000)

        XCTAssertThrowsError(
            try context.store.saveScheduledTransactionException(
                ScheduledTransactionException(
                    id: UUID(), scheduledTransactionID: schedule.id,
                    originalDueDate: try date(2024, 2, 15),
                    effectiveDate: try date(2024, 2, 15), payee: "Ungültig",
                    purpose: "Ungültig", categoryID: nil, amountMinor: 1,
                    disposition: .modified, note: "", createdAt: now,
                    updatedAt: now
                )
            )
        )
        XCTAssertEqual(try context.store.scheduledTransactionExceptions().count, 2)

        try context.store.deleteScheduledTransactionException(
            scheduledTransactionID: schedule.id, originalDueDate: february
        )
        exceptions = try context.store.scheduledTransactionExceptions()
        XCTAssertEqual(exceptions.count, 1)
        XCTAssertEqual(exceptions.first?.disposition, .skipped)
        let resetOccurrences = loadedSchedule.occurrences(
            until: try date(2024, 4, 30), exceptions: exceptions,
            calendar: calendar
        )
        XCTAssertTrue(resetOccurrences.contains {
            calendar.isDate($0.bookingDate, inSameDayAs: february)
                && $0.amountMinor == schedule.amountMinor
        })
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testScheduledFutureRevisionChangesCadencePersistsOverridesAndResets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(
                calendar.date(
                    from: DateComponents(year: year, month: month, day: day, hour: 12)
                )
            )
        }

        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Serienkonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = try XCTUnwrap(
            context.store.categories().first { $0.kind == .expense }
        )
        let schedule = ScheduledTransaction(
            id: UUID(), name: "Monatliche Miete", accountID: account.id,
            payee: "Altvermieter", purpose: "Altmiete",
            categoryID: category.id, amountMinor: -100_000, currency: "EUR",
            nextDueDate: try date(2024, 1, 31),
            endDate: try date(2024, 4, 30), frequency: .monthly,
            action: .remind, reminderDays: 5, isActive: true
        )
        try context.store.saveScheduledTransaction(schedule)
        let february = try date(2024, 2, 29)
        let march = try date(2024, 3, 31)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try context.store.saveScheduledTransactionException(
            ScheduledTransactionException(
                id: UUID(), scheduledTransactionID: schedule.id,
                originalDueDate: february, effectiveDate: try date(2024, 3, 1),
                payee: "Einmalig", purpose: "Wird ersetzt",
                categoryID: category.id, amountMinor: -101_000,
                disposition: .modified, note: "Einzelausnahme",
                createdAt: now, updatedAt: now
            )
        )
        let revisionID = UUID()
        try context.store.saveScheduledTransactionRevision(
            ScheduledTransactionRevision(
                id: revisionID, scheduledTransactionID: schedule.id,
                originalDueDate: february, effectiveDate: try date(2024, 3, 2),
                payee: "Neuvermieter", purpose: "Neue Miete",
                categoryID: nil, amountMinor: -120_000,
                note: "Ab Februar angepasst", createdAt: now, updatedAt: now
            )
        )

        XCTAssertEqual(try context.store.scheduledTransactionExceptions(), [])
        XCTAssertEqual(
            try sqliteScalar(
                context.store.fileURL,
                "SELECT COUNT(*) FROM audit_events WHERE entity_type='scheduled_transaction_exception' AND action='replaced_by_revision'"
            ),
            1
        )
        var revisions = try context.store.scheduledTransactionRevisions()
        XCTAssertEqual(revisions.map(\.id), [revisionID])
        let loaded = try XCTUnwrap(
            context.store.scheduledTransactions().first { $0.id == schedule.id }
        )
        var occurrences = loaded.occurrences(
            until: try date(2024, 5, 31), revisions: revisions,
            calendar: calendar
        )
        XCTAssertEqual(
            occurrences.map { calendar.dateComponents([.month, .day], from: $0.bookingDate) },
            [
                DateComponents(month: 1, day: 31),
                DateComponents(month: 3, day: 2),
                DateComponents(month: 4, day: 2),
                DateComponents(month: 5, day: 2)
            ]
        )
        XCTAssertEqual(occurrences.first?.payee, "Altvermieter")
        XCTAssertTrue(occurrences.dropFirst().allSatisfy {
            $0.payee == "Neuvermieter" && $0.purpose == "Neue Miete"
                && $0.categoryID == nil && $0.amountMinor == -120_000
        })
        let revisedFirst = try XCTUnwrap(
            occurrences.first { $0.bookingDate > (try? date(2024, 2, 1)) ?? .distantPast }
        )
        let identity = try XCTUnwrap(
            ScheduledTransaction.occurrenceIdentity(from: revisedFirst.reference)
        )
        XCTAssertTrue(calendar.isDate(identity.originalDueDate, inSameDayAs: february))

        let oneTimeReference = try XCTUnwrap(
            occurrences.first {
                guard let identity = ScheduledTransaction.occurrenceIdentity(
                    from: $0.reference
                ) else { return false }
                return calendar.isDate(identity.originalDueDate, inSameDayAs: march)
            }?.reference
        )
        try context.store.saveScheduledTransactionException(
            ScheduledTransactionException(
                id: UUID(), scheduledTransactionID: schedule.id,
                originalDueDate: march, effectiveDate: try date(2024, 4, 5),
                payee: "Einmaliger Vertreter", purpose: "Nur März",
                categoryID: category.id, amountMinor: -130_000,
                disposition: .modified, note: "Einmalig nach Serienänderung",
                createdAt: now, updatedAt: now
            )
        )
        let exceptions = try context.store.scheduledTransactionExceptions()
        occurrences = loaded.occurrences(
            until: try date(2024, 5, 31), exceptions: exceptions,
            revisions: revisions, calendar: calendar
        )
        XCTAssertEqual(occurrences.first { $0.reference == oneTimeReference }?.payee, "Einmaliger Vertreter")
        XCTAssertTrue(
            calendar.isDate(
                try XCTUnwrap(
                    occurrences.first { $0.reference == oneTimeReference }?.bookingDate
                ),
                inSameDayAs: try date(2024, 4, 5)
            )
        )
        XCTAssertEqual(occurrences.last?.payee, "Neuvermieter")
        XCTAssertFalse(
            loaded.occurrences(
                until: try date(2024, 5, 31),
                excludingReferences: [oneTimeReference],
                exceptions: exceptions, revisions: revisions,
                calendar: calendar
            ).contains { $0.reference == oneTimeReference }
        )

        try context.store.saveScheduledTransactionRevision(
            ScheduledTransactionRevision(
                id: UUID(), scheduledTransactionID: schedule.id,
                originalDueDate: february, effectiveDate: try date(2024, 3, 3),
                payee: "Neuvermieter korrigiert", purpose: "Korrigiert",
                categoryID: category.id, amountMinor: -121_000,
                note: "Ersetzt", createdAt: now, updatedAt: now
            )
        )
        revisions = try context.store.scheduledTransactionRevisions()
        XCTAssertEqual(revisions.count, 1)
        XCTAssertEqual(revisions.first?.id, revisionID)
        XCTAssertEqual(revisions.first?.payee, "Neuvermieter korrigiert")

        let secondRevisionID = UUID()
        try context.store.saveScheduledTransactionRevision(
            ScheduledTransactionRevision(
                id: secondRevisionID, scheduledTransactionID: schedule.id,
                originalDueDate: march, effectiveDate: try date(2024, 4, 10),
                payee: "Dritter Vermieter", purpose: "Nochmals geändert",
                categoryID: nil, amountMinor: -140_000,
                note: "Zweiter Änderungspunkt", createdAt: now, updatedAt: now
            )
        )
        XCTAssertEqual(try context.store.scheduledTransactionExceptions(), [])
        revisions = try context.store.scheduledTransactionRevisions()
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(Set(revisions.map(\.id)), [revisionID, secondRevisionID])
        occurrences = loaded.occurrences(
            until: try date(2024, 5, 31), revisions: revisions,
            calendar: calendar
        )
        XCTAssertEqual(
            occurrences.map { calendar.dateComponents([.month, .day], from: $0.bookingDate) },
            [
                DateComponents(month: 1, day: 31),
                DateComponents(month: 3, day: 3),
                DateComponents(month: 4, day: 10),
                DateComponents(month: 5, day: 10)
            ]
        )
        XCTAssertTrue(occurrences.suffix(2).allSatisfy {
            $0.payee == "Dritter Vermieter" && $0.amountMinor == -140_000
        })
        XCTAssertEqual(
            try sqliteScalar(
                context.store.fileURL,
                "SELECT COUNT(*) FROM audit_events WHERE entity_type='scheduled_transaction_exception' AND action='replaced_by_revision'"
            ),
            2
        )

        XCTAssertThrowsError(
            try context.store.saveScheduledTransactionRevision(
                ScheduledTransactionRevision(
                    id: UUID(), scheduledTransactionID: schedule.id,
                    originalDueDate: try date(2024, 2, 15),
                    effectiveDate: try date(2024, 2, 15), payee: "Ungültig",
                    purpose: "Ungültig", categoryID: nil, amountMinor: 1,
                    note: "", createdAt: now, updatedAt: now
                )
            )
        )
        XCTAssertEqual(try context.store.scheduledTransactionRevisions().count, 2)

        try context.store.deleteScheduledTransactionRevision(
            scheduledTransactionID: schedule.id, originalDueDate: march
        )
        XCTAssertEqual(try context.store.scheduledTransactionRevisions().map(\.id), [revisionID])

        try context.store.deleteScheduledTransactionRevision(
            scheduledTransactionID: schedule.id, originalDueDate: february
        )
        XCTAssertEqual(try context.store.scheduledTransactionRevisions(), [])
        let reset = loaded.occurrences(
            until: try date(2024, 4, 30),
            exceptions: try context.store.scheduledTransactionExceptions(),
            revisions: [], calendar: calendar
        )
        XCTAssertTrue(reset.contains {
            calendar.isDate($0.bookingDate, inSameDayAs: february)
                && $0.payee == schedule.payee
        })
        XCTAssertTrue(try context.store.integrityCheck())
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

    func testPaymentDraftCanBeAuditedEditedCancelledAndNeverChangedAfterInitiation() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "Musterbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 100_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = PaymentOrder(
            id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
            recipientName: "Stadtwerke", iban: "DE89370400440532013000",
            bic: "", amountMinor: 9_850, currency: "EUR",
            executionDate: createdAt, purpose: "Abschlag",
            endToEndID: "ALT", status: .draft,
            idempotencyKey: "draft-before-edit", bankReference: "",
            createdAt: createdAt, updatedAt: createdAt
        )
        var invalidSEPA = original
        invalidSEPA.currency = "USD"
        XCTAssertThrowsError(try invalidSEPA.validate())
        invalidSEPA = original
        invalidSEPA.bic = "FALSCH"
        XCTAssertThrowsError(try invalidSEPA.validate())
        invalidSEPA = original
        invalidSEPA.endToEndID = String(repeating: "X", count: 36)
        XCTAssertThrowsError(try invalidSEPA.validate())
        try context.store.createPaymentOrder(original)

        var edited = original
        edited.recipientName = "Stadtwerke Köln"
        edited.amountMinor = 10_250
        edited.purpose = "Abschlag August"
        edited.endToEndID = "NEU"
        edited.idempotencyKey = "draft-after-edit"
        edited.updatedAt = createdAt.addingTimeInterval(60)
        try context.store.updatePaymentOrderDraft(edited)

        let persisted = try XCTUnwrap(
            context.store.paymentOrders().first { $0.id == original.id }
        )
        XCTAssertEqual(persisted.recipientName, "Stadtwerke Köln")
        XCTAssertEqual(persisted.amountMinor, 10_250)
        XCTAssertEqual(persisted.purpose, "Abschlag August")
        XCTAssertEqual(persisted.endToEndID, "NEU")
        XCTAssertEqual(persisted.idempotencyKey, "draft-after-edit")
        XCTAssertEqual(persisted.createdAt, createdAt)
        XCTAssertEqual(persisted.status, .draft)
        XCTAssertEqual(
            try sqliteScalar(
                context.store.fileURL,
                "SELECT COUNT(*) FROM audit_events "
                    + "WHERE entity_type='payment_order' "
                    + "AND entity_id='\(original.id.uuidString)' "
                    + "AND action='update_draft'"
            ),
            1
        )

        var duplicate = original
        duplicate = PaymentOrder(
            id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
            recipientName: "Andere Zahlung", iban: "DE89370400440532013000",
            bic: "", amountMinor: 1_000, currency: "EUR",
            executionDate: createdAt, purpose: "Andere Zahlung",
            endToEndID: "ANDERE", status: .draft,
            idempotencyKey: "duplicate-after-edit", bankReference: "",
            createdAt: createdAt, updatedAt: createdAt
        )
        try context.store.createPaymentOrder(duplicate)
        edited.idempotencyKey = duplicate.idempotencyKey
        XCTAssertThrowsError(try context.store.updatePaymentOrderDraft(edited)) {
            XCTAssertEqual($0 as? FinanceError, .duplicatePaymentOrder)
        }

        try context.store.transitionPaymentOrder(id: original.id, to: .initiated)
        edited.idempotencyKey = "another-edit"
        XCTAssertThrowsError(try context.store.updatePaymentOrderDraft(edited)) {
            XCTAssertEqual($0 as? FinanceError, .invalidPaymentTransition)
        }

        try context.store.transitionPaymentOrder(id: duplicate.id, to: .cancelled)
        let cancelled = try XCTUnwrap(
            context.store.paymentOrders().first { $0.id == duplicate.id }
        )
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertThrowsError(try context.store.updatePaymentOrderDraft(cancelled)) {
            XCTAssertEqual($0 as? FinanceError, .invalidPaymentTransition)
        }
    }

    func testPayeeBankAccountsKeepOneDefaultAndLinkImmutablePaymentSnapshot() throws {
        let context = try TestDatabase()
        let source = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 50_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(source)
        let payee = FinancePayee(
            id: UUID(), canonicalName: "Muster GmbH", aliases: [],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: source.id,
            note: "", isActive: true
        )
        try context.store.savePayee(payee)
        var primary = FinancePayeeBankAccount(
            id: UUID(), payeeID: payee.id, label: "Rechnungen",
            accountHolder: "Muster GmbH",
            iban: "DE89 3704 0044 0532 0130 00", bic: "COBADEFFXXX",
            bankName: "Commerzbank", isDefault: true, isActive: true
        )
        var secondary = FinancePayeeBankAccount(
            id: UUID(), payeeID: payee.id, label: "Erstattungen",
            accountHolder: "Muster Erstattung GmbH",
            iban: "DE75 5121 0800 1245 1261 99", bic: "SOGEDEFFXXX",
            bankName: "Bank Zwei", isDefault: false, isActive: true
        )
        try context.store.savePayeeBankAccount(primary)
        try context.store.savePayeeBankAccount(secondary)
        var restored = try context.store.payeeBankAccounts(payeeID: payee.id)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.filter(\.isDefault).map(\.id), [primary.id])
        XCTAssertEqual(
            restored.first { $0.id == primary.id }?.iban,
            "DE89370400440532013000"
        )

        secondary.isDefault = true
        try context.store.savePayeeBankAccount(secondary)
        restored = try context.store.payeeBankAccounts(payeeID: payee.id)
        XCTAssertEqual(restored.filter(\.isDefault).map(\.id), [secondary.id])

        let otherPayee = FinancePayee(
            id: UUID(), canonicalName: "Andere GmbH", aliases: [],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: source.id,
            note: "", isActive: true
        )
        try context.store.savePayee(otherPayee)
        var reassigned = primary
        reassigned.payeeID = otherPayee.id
        XCTAssertThrowsError(try context.store.savePayeeBankAccount(reassigned))

        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let payment = PaymentOrder(
            id: UUID(), accountID: source.id, type: .sepaCreditTransfer,
            recipientName: secondary.accountHolder,
            iban: IBANValidator.normalized(secondary.iban), bic: secondary.bic,
            amountMinor: 12_345, currency: "EUR", executionDate: now,
            purpose: "Rechnung 42", endToEndID: "E2E-42", status: .draft,
            idempotencyKey: "payee-bank-link-42", bankReference: "",
            createdAt: now, updatedAt: now,
            payeeID: payee.id, payeeBankAccountID: secondary.id
        )
        try context.store.createPaymentOrder(payment)
        let restoredPayment = try XCTUnwrap(context.store.paymentOrders().first)
        XCTAssertEqual(restoredPayment.payeeID, payee.id)
        XCTAssertEqual(restoredPayment.payeeBankAccountID, secondary.id)
        XCTAssertEqual(restoredPayment.recipientName, "Muster Erstattung GmbH")
        XCTAssertEqual(restoredPayment.iban, "DE75512108001245126199")

        let tampered = PaymentOrder(
            id: UUID(), accountID: source.id, type: .sepaCreditTransfer,
            recipientName: secondary.accountHolder,
            iban: IBANValidator.normalized(secondary.iban), bic: "FALSCHBIC",
            amountMinor: 100, currency: "EUR", executionDate: now,
            purpose: "Manipuliert", endToEndID: "NOTPROVIDED", status: .draft,
            idempotencyKey: "tampered-payee-bank-link", bankReference: "",
            createdAt: now, updatedAt: now,
            payeeID: payee.id, payeeBankAccountID: secondary.id
        )
        XCTAssertThrowsError(try context.store.createPaymentOrder(tampered))
        let tamperedHolder = PaymentOrder(
            id: UUID(), accountID: payment.accountID, type: payment.type,
            recipientName: "Manipulierter Kontoinhaber", iban: payment.iban,
            bic: payment.bic, amountMinor: payment.amountMinor,
            currency: payment.currency, executionDate: payment.executionDate,
            purpose: payment.purpose, endToEndID: payment.endToEndID,
            status: .draft, idempotencyKey: "tampered-payee-account-holder",
            bankReference: "", createdAt: now, updatedAt: now,
            payeeID: payment.payeeID,
            payeeBankAccountID: payment.payeeBankAccountID
        )
        XCTAssertThrowsError(try context.store.createPaymentOrder(tamperedHolder))

        var inactivePayee = otherPayee
        inactivePayee.isActive = false
        try context.store.savePayee(inactivePayee)
        let inactivePayeePayment = PaymentOrder(
            id: UUID(), accountID: payment.accountID, type: payment.type,
            recipientName: payment.recipientName, iban: payment.iban,
            bic: payment.bic, amountMinor: payment.amountMinor,
            currency: payment.currency, executionDate: payment.executionDate,
            purpose: payment.purpose, endToEndID: payment.endToEndID,
            status: .draft, idempotencyKey: "inactive-payee-link",
            bankReference: "", createdAt: now, updatedAt: now,
            payeeID: inactivePayee.id, payeeBankAccountID: nil
        )
        XCTAssertThrowsError(
            try context.store.createPaymentOrder(inactivePayeePayment)
        )

        secondary.isDefault = false
        secondary.isActive = false
        try context.store.savePayeeBankAccount(secondary)
        restored = try context.store.payeeBankAccounts(payeeID: payee.id)
        XCTAssertEqual(restored.filter(\.isDefault).map(\.id), [primary.id])
        XCTAssertEqual(
            try context.store.paymentOrders().first?.iban,
            "DE75512108001245126199",
            "Der bestehende Zahlungsauftrag bleibt ein unveränderlicher Schnappschuss."
        )
        let inactivePayment = PaymentOrder(
            id: UUID(), accountID: source.id, type: .sepaCreditTransfer,
            recipientName: secondary.accountHolder,
            iban: IBANValidator.normalized(secondary.iban), bic: secondary.bic,
            amountMinor: 100, currency: "EUR", executionDate: now,
            purpose: "Inaktiv", endToEndID: "NOTPROVIDED", status: .draft,
            idempotencyKey: "inactive-payee-bank-link", bankReference: "",
            createdAt: now, updatedAt: now,
            payeeID: payee.id, payeeBankAccountID: secondary.id
        )
        XCTAssertThrowsError(try context.store.createPaymentOrder(inactivePayment))

        primary.isActive = false
        primary.isDefault = true
        XCTAssertThrowsError(try context.store.savePayeeBankAccount(primary))
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testDirectDebitOrderRequiresActiveSnapshotsAndMaterializesExactlyOnce() throws {
        let context = try TestDatabase()
        var creditorAccount = FinanceAccount(
            id: UUID(), name: "Vereinskonto", institution: "Musterbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        creditorAccount.ownerName = "Musterverein e.V."
        creditorAccount.iban = "DE89370400440532013000"
        creditorAccount.bic = "COBADEFFXXX"
        try context.store.saveAccount(creditorAccount)
        let debtor = FinancePayee(
            id: UUID(), canonicalName: "Mitglied Beispiel", aliases: [],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: true
        )
        try context.store.savePayee(debtor)
        var bankAccount = FinancePayeeBankAccount(
            id: UUID(), payeeID: debtor.id, label: "Beitragskonto",
            accountHolder: "Mitglied Beispiel",
            iban: "DE12500105170648489890", bic: "INGDDEFFXXX",
            bankName: "Zahlerbank", isDefault: true, isActive: true
        )
        try context.store.savePayeeBankAccount(bankAccount)
        let signedOn = Pain008Exporter.gregorianDate(
            year: 2026, month: 1, day: 15
        )
        var mandate = FinanceSEPAMandate(
            id: UUID(), payeeID: debtor.id, reference: "MITGLIED-2026-42",
            signedOn: signedOn, sequenceType: .recurring,
            note: "Mitgliedsbeitrag", isActive: true
        )
        try context.store.saveSEPAMandate(mandate)
        let collectionDate = Pain008Exporter.gregorianDate(
            year: 2026, month: 8, day: 15
        )
        let now = Pain008Exporter.gregorianDate(
            year: 2026, month: 7, day: 31
        )
        let order = DirectDebitOrder(
            id: UUID(), creditorAccountID: creditorAccount.id,
            debtorPayeeID: debtor.id,
            debtorBankAccountID: bankAccount.id,
            mandateID: mandate.id,
            creditorName: creditorAccount.ownerName,
            creditorID: "DE98ZZZ09999999999",
            creditorIBAN: creditorAccount.iban,
            creditorBIC: creditorAccount.bic,
            debtorName: bankAccount.accountHolder,
            debtorIBAN: bankAccount.iban,
            debtorBIC: bankAccount.bic,
            amountMinor: 4_250, currency: "EUR",
            collectionDate: collectionDate,
            purpose: "Mitgliedsbeitrag August",
            endToEndID: "BEITRAG-2026-08",
            mandateReference: mandate.reference,
            mandateSignedOn: signedOn,
            sequenceType: mandate.sequenceType,
            status: .draft,
            idempotencyKey: "direct-debit-member-42-2026-08",
            bankReference: "", createdAt: now, updatedAt: now
        )
        var invalid = order
        invalid.debtorBIC = "FALSCH"
        invalid.idempotencyKey = "invalid-direct-debit-bic"
        XCTAssertThrowsError(try context.store.createDirectDebitOrder(invalid))
        invalid = order
        invalid.endToEndID = "/UNZULAESSIG"
        invalid.idempotencyKey = "invalid-direct-debit-slash"
        XCTAssertThrowsError(try context.store.createDirectDebitOrder(invalid))
        invalid = order
        invalid.mandateReference = String(repeating: "M", count: 36)
        invalid.idempotencyKey = "invalid-direct-debit-mandate"
        XCTAssertThrowsError(try context.store.createDirectDebitOrder(invalid))
        try context.store.createDirectDebitOrder(order)
        XCTAssertThrowsError(try context.store.createDirectDebitOrder(order)) {
            XCTAssertEqual($0 as? FinanceError, .duplicateDirectDebitOrder)
        }
        let stored = try XCTUnwrap(context.store.directDebitOrders().first)
        XCTAssertEqual(stored, order)

        let cancelledOrder = DirectDebitOrder(
            id: UUID(), creditorAccountID: order.creditorAccountID,
            debtorPayeeID: order.debtorPayeeID,
            debtorBankAccountID: order.debtorBankAccountID,
            mandateID: order.mandateID,
            creditorName: order.creditorName, creditorID: order.creditorID,
            creditorIBAN: order.creditorIBAN, creditorBIC: order.creditorBIC,
            debtorName: order.debtorName, debtorIBAN: order.debtorIBAN,
            debtorBIC: order.debtorBIC, amountMinor: 4_251,
            currency: order.currency, collectionDate: order.collectionDate,
            purpose: "Bewusst abgebrochener Einzug",
            endToEndID: "ABBRUCH-2026-08",
            mandateReference: order.mandateReference,
            mandateSignedOn: order.mandateSignedOn,
            sequenceType: order.sequenceType, status: .draft,
            idempotencyKey: "cancelled-direct-debit", bankReference: "",
            createdAt: now, updatedAt: now
        )
        try context.store.createDirectDebitOrder(cancelledOrder)
        try context.store.transitionDirectDebitOrder(
            id: cancelledOrder.id, to: .cancelled
        )
        XCTAssertEqual(
            try context.store.directDebitOrders().first {
                $0.id == cancelledOrder.id
            }?.status,
            .cancelled
        )
        XCTAssertEqual(
            try context.store.transactions().filter {
                $0.reference == "direct-debit:\(cancelledOrder.id.uuidString)"
            }.count,
            0
        )
        XCTAssertThrowsError(
            try context.store.transitionDirectDebitOrder(
                id: cancelledOrder.id, to: .initiated
            )
        )

        var tampered = order
        tampered = DirectDebitOrder(
            id: UUID(), creditorAccountID: order.creditorAccountID,
            debtorPayeeID: order.debtorPayeeID,
            debtorBankAccountID: order.debtorBankAccountID,
            mandateID: order.mandateID,
            creditorName: order.creditorName, creditorID: order.creditorID,
            creditorIBAN: order.creditorIBAN, creditorBIC: order.creditorBIC,
            debtorName: "Manipulierter Zahler", debtorIBAN: order.debtorIBAN,
            debtorBIC: order.debtorBIC, amountMinor: order.amountMinor,
            currency: order.currency, collectionDate: order.collectionDate,
            purpose: order.purpose, endToEndID: order.endToEndID,
            mandateReference: order.mandateReference,
            mandateSignedOn: order.mandateSignedOn,
            sequenceType: order.sequenceType, status: .draft,
            idempotencyKey: "tampered-direct-debit", bankReference: "",
            createdAt: now, updatedAt: now
        )
        XCTAssertThrowsError(try context.store.createDirectDebitOrder(tampered))

        bankAccount.isActive = false
        bankAccount.isDefault = false
        try context.store.savePayeeBankAccount(bankAccount)
        var inactiveBankOrder = tampered
        inactiveBankOrder = DirectDebitOrder(
            id: UUID(), creditorAccountID: order.creditorAccountID,
            debtorPayeeID: order.debtorPayeeID,
            debtorBankAccountID: order.debtorBankAccountID,
            mandateID: order.mandateID,
            creditorName: order.creditorName, creditorID: order.creditorID,
            creditorIBAN: order.creditorIBAN, creditorBIC: order.creditorBIC,
            debtorName: order.debtorName, debtorIBAN: order.debtorIBAN,
            debtorBIC: order.debtorBIC, amountMinor: order.amountMinor,
            currency: order.currency, collectionDate: order.collectionDate,
            purpose: order.purpose, endToEndID: order.endToEndID,
            mandateReference: order.mandateReference,
            mandateSignedOn: order.mandateSignedOn,
            sequenceType: order.sequenceType, status: .draft,
            idempotencyKey: "inactive-bank-direct-debit", bankReference: "",
            createdAt: now, updatedAt: now
        )
        XCTAssertThrowsError(
            try context.store.createDirectDebitOrder(inactiveBankOrder)
        )

        mandate.sequenceType = .final
        try context.store.saveSEPAMandate(mandate)
        XCTAssertEqual(
            try context.store.directDebitOrders().first {
                $0.id == order.id
            }?.sequenceType,
            .recurring,
            "Ein bestehender Auftrag behält den Mandatsschnappschuss."
        )
        for status in [
            PaymentStatus.initiated, .challengeReceived, .awaitingUser,
            .submitted, .accepted
        ] {
            try context.store.transitionDirectDebitOrder(id: order.id, to: status)
        }
        let accepted = try XCTUnwrap(
            context.store.directDebitOrders().first { $0.id == order.id }
        )
        XCTAssertEqual(accepted.status, .accepted)
        XCTAssertTrue(accepted.bankReference.hasPrefix("SIM-DD-"))
        let materialized = try context.store.transactions().filter {
            $0.reference == "direct-debit:\(order.id.uuidString)"
        }
        XCTAssertEqual(materialized.count, 1)
        XCTAssertEqual(materialized.first?.amountMinor, 4_250)
        XCTAssertEqual(materialized.first?.payeeID, debtor.id)
        XCTAssertEqual(materialized.first?.mandateReference, mandate.reference)
        XCTAssertThrowsError(
            try context.store.transitionDirectDebitOrder(id: order.id, to: .submitted)
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testPain008ExportIsDeterministicEscapedAndUsesEPC2025Rules() throws {
        let accountID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let orderID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
        var account = FinanceAccount(
            id: accountID, name: "Vereinskonto", institution: "Musterbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.ownerName = "Müller & Partner e.V."
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        let signedOn = Pain008Exporter.gregorianDate(
            year: 2026, month: 1, day: 15
        )
        let collectionDate = Pain008Exporter.gregorianDate(
            year: 2026, month: 8, day: 15
        )
        let creationDate = Pain008Exporter.gregorianDate(
            year: 2026, month: 7, day: 31
        )
        var order = DirectDebitOrder(
            id: orderID, creditorAccountID: accountID,
            debtorPayeeID: UUID(), debtorBankAccountID: UUID(),
            mandateID: UUID(), creditorName: account.ownerName,
            creditorID: "DE98ZZZ09999999999",
            creditorIBAN: account.iban, creditorBIC: account.bic,
            debtorName: "Zahler <Nord>",
            debtorIBAN: "DE12500105170648489890",
            debtorBIC: "INGDDEFFXXX", amountMinor: 123_456,
            currency: "EUR", collectionDate: collectionDate,
            purpose: "Beitrag & Vertrag 42", endToEndID: "E2E-DD-42",
            mandateReference: "MANDAT-42", mandateSignedOn: signedOn,
            sequenceType: .recurring, status: .draft,
            idempotencyKey: "pain008-test", bankReference: "",
            createdAt: creationDate, updatedAt: creationDate
        )

        let first = try Pain008Exporter.export(
            order: order, account: account, createdAt: creationDate,
            messageID: "MSG-DD-2026-0001"
        )
        let second = try Pain008Exporter.export(
            order: order, account: account, createdAt: creationDate,
            messageID: "MSG-DD-2026-0001"
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rulePackage, .epc2025)
        XCTAssertEqual(first.fileName, "pain.008-2026-08-15-CCCCCCCC.xml")
        let document = try XMLDocument(data: first.data)
        XCTAssertEqual(
            document.rootElement()?.namespace(forPrefix: "")?.stringValue,
            Pain008RulePackage.epc2025.namespace
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='PmtMtd']"
            ).first?.stringValue,
            "DD"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='LclInstrm']/*[local-name()='Cd']"
            ).first?.stringValue,
            "CORE"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='SeqTp']"
            ).first?.stringValue,
            "RCUR"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='MndtId']"
            ).first?.stringValue,
            "MANDAT-42"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='DtOfSgntr']"
            ).first?.stringValue,
            "2026-01-15"
        )
        XCTAssertEqual(
            try document.nodes(
                forXPath: "//*[local-name()='CtrlSum']"
            ).compactMap(\.stringValue),
            ["1234.56", "1234.56"]
        )
        let rawXML = try XCTUnwrap(String(data: first.data, encoding: .utf8))
        XCTAssertTrue(rawXML.contains("Müller &amp; Partner e.V."))
        XCTAssertTrue(rawXML.contains("Zahler &lt;Nord&gt;"))
        XCTAssertTrue(rawXML.contains("<ReqdColltnDt>2026-08-15</ReqdColltnDt>"))
        XCTAssertTrue(rawXML.contains("<Prtry>SEPA</Prtry>"))

        order.mandateReference = "/nicht-erlaubt"
        XCTAssertThrowsError(
            try Pain008Exporter.export(
                order: order, account: account, createdAt: creationDate
            )
        ) {
            XCTAssertEqual(
                $0 as? Pain008ExportError,
                .invalidIdentifier("Mandatsreferenz")
            )
        }
        order.mandateReference = "MANDAT-42"
        order.status = .unknown
        XCTAssertThrowsError(
            try Pain008Exporter.export(
                order: order, account: account, createdAt: creationDate
            )
        ) {
            XCTAssertEqual($0 as? Pain008ExportError, .nonDraftOrder)
        }
    }

    func testCreditTransferBatchIsAtomicAndExportsDeterministicPain001() throws {
        let context = try TestDatabase()
        var account = FinanceAccount(
            id: UUID(), name: "Sammlerkonto", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 50_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.ownerName = "Müller & Co."
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        try context.store.saveAccount(account)
        let executionDate = Pain001Exporter.gregorianDate(
            year: 2026, month: 8, day: 17
        )
        let createdAt = Pain001Exporter.gregorianDate(
            year: 2026, month: 7, day: 31
        )
        let orders = [
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Empfänger <Eins>",
                iban: "DE12500105170648489890", bic: "INGDDEFFXXX",
                amountMinor: 1_000, currency: "EUR",
                executionDate: executionDate, purpose: "Rechnung & eins",
                endToEndID: "SAMMEL-1", status: .draft,
                idempotencyKey: "batch-payment-1", bankReference: "",
                createdAt: createdAt, updatedAt: createdAt
            ),
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Empfänger Zwei",
                iban: "DE75512108001245126199", bic: "",
                amountMinor: 2_000, currency: "EUR",
                executionDate: executionDate, purpose: "Rechnung zwei",
                endToEndID: "SAMMEL-2", status: .draft,
                idempotencyKey: "batch-payment-2", bankReference: "",
                createdAt: createdAt.addingTimeInterval(1),
                updatedAt: createdAt.addingTimeInterval(1)
            )
        ]
        for order in orders { try context.store.createPaymentOrder(order) }
        let memberIDs = orders.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let batch = PaymentBatch(
            id: UUID(), name: "Rechnungen August",
            kind: .creditTransfer, accountID: account.id,
            requestedDate: executionDate, status: .draft,
            idempotencyKey: "credit-batch-2026-08", bankReference: "",
            memberOrderIDs: memberIDs, createdAt: createdAt,
            updatedAt: createdAt
        )
        try context.store.createPaymentBatch(batch)
        XCTAssertEqual(try context.store.paymentBatches(), [batch])
        XCTAssertThrowsError(try context.store.createPaymentBatch(batch)) {
            XCTAssertEqual($0 as? FinanceError, .duplicatePaymentBatch)
        }
        XCTAssertThrowsError(
            try context.store.transitionPaymentOrder(
                id: memberIDs[0], to: .initiated
            )
        ) {
            guard case .invalidPaymentBatch = $0 as? FinanceError else {
                return XCTFail("Erwartet wurde der Sammlerschutz.")
            }
        }

        let orderedMembers = memberIDs.compactMap { id in
            orders.first { $0.id == id }
        }
        let first = try Pain001Exporter.export(
            batch: batch, orders: orderedMembers, account: account,
            createdAt: createdAt, messageID: "MSG-BATCH-001"
        )
        let second = try Pain001Exporter.export(
            batch: batch, orders: orderedMembers, account: account,
            createdAt: createdAt, messageID: "MSG-BATCH-001"
        )
        XCTAssertEqual(first, second)
        let document = try XMLDocument(data: first.data)
        XCTAssertEqual(
            try document.nodes(forXPath: "//*[local-name()='CdtTrfTxInf']").count,
            2
        )
        XCTAssertEqual(
            try document.nodes(forXPath: "//*[local-name()='NbOfTxs']")
                .compactMap(\.stringValue),
            ["2", "2"]
        )
        XCTAssertEqual(
            try document.nodes(forXPath: "//*[local-name()='CtrlSum']")
                .compactMap(\.stringValue),
            ["30.00", "30.00"]
        )
        XCTAssertEqual(
            try document.nodes(forXPath: "//*[local-name()='BtchBookg']")
                .first?.stringValue,
            "true"
        )
        let rawXML = try XCTUnwrap(String(data: first.data, encoding: .utf8))
        XCTAssertTrue(rawXML.contains("Müller &amp; Co."))
        XCTAssertTrue(rawXML.contains("Empfänger &lt;Eins&gt;"))

        for target in [
            PaymentStatus.initiated, .challengeReceived, .awaitingUser,
            .submitted, .accepted
        ] {
            try context.store.transitionPaymentBatch(id: batch.id, to: target)
        }
        let acceptedBatch = try XCTUnwrap(context.store.paymentBatches().first)
        XCTAssertEqual(acceptedBatch.status, .accepted)
        XCTAssertTrue(acceptedBatch.bankReference.hasPrefix("SIM-BT-"))
        let acceptedOrders = try context.store.paymentOrders().filter {
            memberIDs.contains($0.id)
        }
        XCTAssertEqual(Set(acceptedOrders.map(\.status)), [.accepted])
        let expectedReferences = Set(memberIDs.map { "payment:\($0.uuidString)" })
        let materialized = try context.store.transactions().filter {
            expectedReferences.contains($0.reference)
        }
        XCTAssertEqual(materialized.count, 2)
        XCTAssertEqual(materialized.reduce(Int64.zero) { $0 + $1.amountMinor }, -3_000)
        XCTAssertThrowsError(
            try context.store.transitionPaymentBatch(id: batch.id, to: .submitted)
        )

        let cancellationOrders = [
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Abbruch Eins", iban: "DE12500105170648489890",
                bic: "INGDDEFFXXX", amountMinor: 400, currency: "EUR",
                executionDate: executionDate, purpose: "Nicht senden eins",
                endToEndID: "CANCEL-BATCH-1", status: .draft,
                idempotencyKey: "cancel-batch-payment-1", bankReference: "",
                createdAt: createdAt.addingTimeInterval(10),
                updatedAt: createdAt.addingTimeInterval(10)
            ),
            PaymentOrder(
                id: UUID(), accountID: account.id, type: .sepaCreditTransfer,
                recipientName: "Abbruch Zwei", iban: "DE75512108001245126199",
                bic: "", amountMinor: 500, currency: "EUR",
                executionDate: executionDate, purpose: "Nicht senden zwei",
                endToEndID: "CANCEL-BATCH-2", status: .draft,
                idempotencyKey: "cancel-batch-payment-2", bankReference: "",
                createdAt: createdAt.addingTimeInterval(11),
                updatedAt: createdAt.addingTimeInterval(11)
            )
        ]
        for order in cancellationOrders {
            try context.store.createPaymentOrder(order)
        }
        let cancellationMemberIDs = cancellationOrders.map(\.id).sorted {
            $0.uuidString < $1.uuidString
        }
        let cancellationBatch = PaymentBatch(
            id: UUID(), name: "Bewusst abgebrochener Sammler",
            kind: .creditTransfer, accountID: account.id,
            requestedDate: executionDate, status: .draft,
            idempotencyKey: "cancelled-credit-batch", bankReference: "",
            memberOrderIDs: cancellationMemberIDs, createdAt: createdAt,
            updatedAt: createdAt
        )
        try context.store.createPaymentBatch(cancellationBatch)
        try context.store.transitionPaymentBatch(
            id: cancellationBatch.id, to: .cancelled
        )
        XCTAssertEqual(
            try context.store.paymentBatches().first {
                $0.id == cancellationBatch.id
            }?.status,
            .cancelled
        )
        XCTAssertEqual(
            Set(try context.store.paymentOrders().filter {
                cancellationMemberIDs.contains($0.id)
            }.map(\.status)),
            [.cancelled]
        )
        XCTAssertEqual(
            try context.store.transactions().filter {
                cancellationMemberIDs.map {
                    "payment:\($0.uuidString)"
                }.contains($0.reference)
            }.count,
            0
        )
        XCTAssertThrowsError(
            try context.store.transitionPaymentBatch(
                id: cancellationBatch.id, to: .initiated
            )
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testDirectDebitBatchIsAtomicAndExportsDeterministicPain008() throws {
        let context = try TestDatabase()
        var account = FinanceAccount(
            id: UUID(), name: "Vereinskonto", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        account.ownerName = "Verein Beispiel"
        account.iban = "DE89370400440532013000"
        account.bic = "COBADEFFXXX"
        try context.store.saveAccount(account)
        let signedOn = Pain008Exporter.gregorianDate(
            year: 2026, month: 1, day: 15
        )
        let collectionDate = Pain008Exporter.gregorianDate(
            year: 2026, month: 8, day: 20
        )
        let createdAt = Pain008Exporter.gregorianDate(
            year: 2026, month: 7, day: 31
        )
        var orders: [DirectDebitOrder] = []
        for index in 1...2 {
            let payee = FinancePayee(
                id: UUID(), canonicalName: "Mitglied \(index)", aliases: [],
                address: "", email: "", phone: "", iban: "", bic: "",
                defaultCategoryID: nil, preferredAccountID: nil,
                note: "", isActive: true
            )
            try context.store.savePayee(payee)
            let bank = FinancePayeeBankAccount(
                id: UUID(), payeeID: payee.id, label: "Beitragskonto",
                accountHolder: index == 1 ? "Mitglied & Eins" : "Mitglied Zwei",
                iban: index == 1
                    ? "DE12500105170648489890" : "DE75512108001245126199",
                bic: index == 1 ? "INGDDEFFXXX" : "",
                bankName: "", isDefault: true, isActive: true
            )
            try context.store.savePayeeBankAccount(bank)
            let mandate = FinanceSEPAMandate(
                id: UUID(), payeeID: payee.id, reference: "MANDAT-\(index)",
                signedOn: signedOn, sequenceType: .recurring,
                note: "", isActive: true
            )
            try context.store.saveSEPAMandate(mandate)
            let order = DirectDebitOrder(
                id: UUID(), creditorAccountID: account.id,
                debtorPayeeID: payee.id, debtorBankAccountID: bank.id,
                mandateID: mandate.id, creditorName: account.ownerName,
                creditorID: "DE98ZZZ09999999999",
                creditorIBAN: account.iban, creditorBIC: account.bic,
                debtorName: bank.accountHolder, debtorIBAN: bank.iban,
                debtorBIC: bank.bic, amountMinor: Int64(index * 1_500),
                currency: "EUR", collectionDate: collectionDate,
                purpose: "Beitrag \(index)", endToEndID: "DD-BATCH-\(index)",
                mandateReference: mandate.reference,
                mandateSignedOn: signedOn, sequenceType: .recurring,
                status: .draft, idempotencyKey: "dd-batch-order-\(index)",
                bankReference: "", createdAt: createdAt.addingTimeInterval(
                    TimeInterval(index)
                ), updatedAt: createdAt
            )
            try context.store.createDirectDebitOrder(order)
            orders.append(order)
        }
        let memberIDs = orders.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let batch = PaymentBatch(
            id: UUID(), name: "Beiträge August", kind: .directDebit,
            accountID: account.id, requestedDate: collectionDate,
            status: .draft, idempotencyKey: "dd-batch-2026-08",
            bankReference: "", memberOrderIDs: memberIDs,
            createdAt: createdAt, updatedAt: createdAt
        )
        try context.store.createPaymentBatch(batch)
        XCTAssertThrowsError(
            try context.store.transitionDirectDebitOrder(
                id: memberIDs[0], to: .initiated
            )
        ) {
            guard case .invalidPaymentBatch = $0 as? FinanceError else {
                return XCTFail("Erwartet wurde der Sammlerschutz.")
            }
        }
        let orderedMembers = memberIDs.compactMap { id in
            orders.first { $0.id == id }
        }
        let result = try Pain008Exporter.export(
            batch: batch, orders: orderedMembers, account: account,
            createdAt: createdAt, messageID: "MSG-BATCH-008"
        )
        XCTAssertEqual(
            result,
            try Pain008Exporter.export(
                batch: batch, orders: orderedMembers, account: account,
                createdAt: createdAt, messageID: "MSG-BATCH-008"
            )
        )
        let document = try XMLDocument(data: result.data)
        XCTAssertEqual(
            try document.nodes(forXPath: "//*[local-name()='DrctDbtTxInf']").count,
            2
        )
        XCTAssertEqual(
            try document.nodes(forXPath: "//*[local-name()='CtrlSum']")
                .compactMap(\.stringValue),
            ["45.00", "45.00"]
        )
        XCTAssertEqual(
            try document.nodes(forXPath: "//*[local-name()='SeqTp']")
                .first?.stringValue,
            "RCUR"
        )
        XCTAssertTrue(
            try XCTUnwrap(String(data: result.data, encoding: .utf8))
                .contains("Mitglied &amp; Eins")
        )
        for target in [
            PaymentStatus.initiated, .challengeReceived, .awaitingUser,
            .submitted, .accepted
        ] {
            try context.store.transitionPaymentBatch(id: batch.id, to: target)
        }
        XCTAssertEqual(
            Set(try context.store.directDebitOrders().filter {
                memberIDs.contains($0.id)
            }.map(\.status)),
            [.accepted]
        )
        let transactions = try context.store.transactions().filter {
            $0.reference.hasPrefix("direct-debit:")
        }
        XCTAssertEqual(transactions.count, 2)
        XCTAssertEqual(transactions.reduce(Int64.zero) { $0 + $1.amountMinor }, 4_500)
        XCTAssertTrue(try context.store.integrityCheck())
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
        XCTAssertEqual(
            runs.map(\.bankingCalendarID),
            [BankingCalendarProfile.targetEuroV1.rawValue,
             BankingCalendarProfile.targetEuroV1.rawValue]
        )
        XCTAssertEqual(runs.map(\.bankingCalendarVersion), [1, 1])
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

    func testVersionedTARGETCalendarHandlesMovableHolidaysAndBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: year, month: month, day: day, hour: 12
            )))
        }
        func components(_ value: Date) -> DateComponents {
            calendar.dateComponents([.year, .month, .day], from: value)
        }

        let profile = BankingCalendarProfile.targetEuroV1
        XCTAssertEqual(profile.version, 1)
        XCTAssertEqual(profile.closureName(on: try date(2026, 4, 3), calendar: calendar), "Karfreitag")
        XCTAssertEqual(profile.closureName(on: try date(2026, 4, 6), calendar: calendar), "Ostermontag")
        XCTAssertEqual(profile.closureName(on: try date(2027, 3, 26), calendar: calendar), "Karfreitag")
        XCTAssertEqual(profile.closureName(on: try date(2026, 5, 1), calendar: calendar), "Tag der Arbeit")
        XCTAssertEqual(profile.closureName(on: try date(2026, 12, 25), calendar: calendar), "1. Weihnachtstag")
        XCTAssertNil(profile.closureName(on: try date(2026, 4, 7), calendar: calendar))

        XCTAssertEqual(
            components(BusinessDayAdjustment.nextWeekday.adjusted(
                try date(2026, 4, 3), bankingCalendar: profile, calendar: calendar
            )),
            DateComponents(year: 2026, month: 4, day: 7)
        )
        XCTAssertEqual(
            components(BusinessDayAdjustment.previousWeekday.adjusted(
                try date(2026, 4, 6), bankingCalendar: profile, calendar: calendar
            )),
            DateComponents(year: 2026, month: 4, day: 2)
        )
        XCTAssertEqual(
            components(BusinessDayAdjustment.nextWeekday.adjusted(
                try date(2026, 12, 25), bankingCalendar: profile, calendar: calendar
            )),
            DateComponents(year: 2026, month: 12, day: 28)
        )
        XCTAssertEqual(
            components(BusinessDayAdjustment.nextWeekday.adjusted(
                try date(2026, 4, 3), bankingCalendar: .weekdaysV1,
                calendar: calendar
            )),
            DateComponents(year: 2026, month: 4, day: 3)
        )
        XCTAssertEqual(
            components(BusinessDayAdjustment.none.adjusted(
                try date(2026, 12, 25), bankingCalendar: profile,
                calendar: calendar
            )),
            DateComponents(year: 2026, month: 12, day: 25)
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

    func testPayeeSmartFillRanksPrefixesUsageAndAliasesDeterministically() {
        let aliasPrefix = FinancePayee(
            id: UUID(), canonicalName: "EDEKA", aliases: ["Markt Center"],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: true
        )
        let canonicalPrefix = FinancePayee(
            id: UUID(), canonicalName: "Markthalle", aliases: [],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: true
        )
        let frequentContains = FinancePayee(
            id: UUID(), canonicalName: "Supermarkt Nord", aliases: [],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: true
        )
        let diacriticAlias = FinancePayee(
            id: UUID(), canonicalName: "Bäckerei", aliases: ["Café Central"],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: true
        )
        let inactive = FinancePayee(
            id: UUID(), canonicalName: "Markt Ruhe", aliases: [],
            address: "", email: "", phone: "", iban: "", bic: "",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: false
        )
        let accountID = UUID()
        func transaction(payeeID: UUID) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: accountID, bookingDate: Date(), valueDate: nil,
                payee: "", purpose: "", categoryID: nil,
                amountMinor: -100, currency: "EUR", status: .booked,
                memo: "", reference: "", transferID: nil,
                importFingerprint: nil, splits: [], payeeID: payeeID
            )
        }
        let transactions = [
            transaction(payeeID: aliasPrefix.id),
            transaction(payeeID: canonicalPrefix.id),
            transaction(payeeID: canonicalPrefix.id),
            transaction(payeeID: frequentContains.id),
            transaction(payeeID: frequentContains.id),
            transaction(payeeID: frequentContains.id)
        ]
        let payees = [
            frequentContains, inactive, aliasPrefix, diacriticAlias,
            canonicalPrefix
        ]

        let results = PayeeSmartFill.suggestions(
            payees: payees,
            transactions: transactions,
            query: "markt"
        )
        XCTAssertEqual(
            results.map(\.payee.id),
            [canonicalPrefix.id, aliasPrefix.id, frequentContains.id]
        )
        XCTAssertEqual(results[1].matchedAlias, "Markt Center")
        XCTAssertEqual(results.map(\.usageCount), [2, 1, 3])
        XCTAssertEqual(
            PayeeSmartFill.suggestions(
                payees: payees,
                transactions: transactions,
                query: "cafe"
            ).map(\.payee.id),
            [diacriticAlias.id]
        )
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
        let defaultTagIDs = [privateTag.id, childTag.id].sorted {
            $0.uuidString < $1.uuidString
        }
        let payee = FinancePayee(
            id: UUID(), canonicalName: "EDEKA Markt",
            aliases: ["EDEKA", "EDEKA Center"], address: "Musterstraße 1",
            email: "", phone: "", iban: "", bic: "",
            creditorID: "DE98ZZZ09999999999",
            defaultCategoryID: category.id,
            defaultTagIDs: defaultTagIDs,
            preferredAccountID: account.id,
            note: "Lebensmittel", isActive: true
        )
        try context.store.savePayee(payee)
        let mandate = FinanceSEPAMandate(
            id: UUID(), payeeID: payee.id, reference: "MANDAT-2026-001",
            signedOn: Date(timeIntervalSince1970: 1_700_000_000),
            sequenceType: .recurring, note: "Stromvertrag", isActive: true
        )
        try context.store.saveSEPAMandate(mandate)
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
        let restoredMandate = try XCTUnwrap(context.store.sepaMandates().first)
        XCTAssertEqual(restoredMandate.id, mandate.id)
        XCTAssertEqual(restoredMandate.payeeID, payee.id)
        XCTAssertEqual(restoredMandate.reference, mandate.reference)
        XCTAssertEqual(restoredMandate.sequenceType, .recurring)
        XCTAssertEqual(restoredMandate.note, mandate.note)
        XCTAssertTrue(restoredMandate.isActive)
        XCTAssertEqual(
            try XCTUnwrap(restoredMandate.signedOn).timeIntervalSince1970,
            1_699_920_000,
            accuracy: 1
        )
        XCTAssertTrue(SEPACreditorIDValidator.isValid(payee.creditorID))
        XCTAssertFalse(SEPACreditorIDValidator.isValid("DE00ZZZ09999999999"))
        var invalidPayee = payee
        invalidPayee.creditorID = "DE00ZZZ09999999999"
        XCTAssertThrowsError(try context.store.savePayee(invalidPayee))
        let invalidMandate = FinanceSEPAMandate(
            id: UUID(), payeeID: payee.id, reference: "<nicht erlaubt>",
            signedOn: nil, sequenceType: .oneOff, note: "", isActive: true
        )
        XCTAssertThrowsError(try context.store.saveSEPAMandate(invalidMandate))
        let restored = try XCTUnwrap(context.store.transactions().first)
        XCTAssertEqual(restored.payeeID, payee.id)
        XCTAssertEqual(Set(restored.tagIDs), Set([privateTag.id, childTag.id]))
        XCTAssertEqual(Set(restored.splits[0].tagIDs), [privateTag.id])
        XCTAssertEqual(Set(restored.splits[1].tagIDs), [childTag.id])
        XCTAssertNoThrow(try restored.validate())

        var cyclicRoot = privateTag
        cyclicRoot.parentID = childTag.id
        XCTAssertThrowsError(try context.store.saveTag(cyclicRoot))
        var missingParent = childTag
        missingParent.parentID = UUID()
        XCTAssertThrowsError(try context.store.saveTag(missingParent))
        XCTAssertEqual(try context.store.tags(), [childTag, privateTag])
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
        XCTAssertEqual(
            try context.store.securityAllocations(),
            try context.store.allocations(securityID: security.id)
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
        try context.store.recordSecurityIncome(
            accountID: depot.id, securityID: security.id, date: secondDate,
            grossMinor: 10_000, feesMinor: 100, taxesMinor: 2_500,
            note: "Ausschüttung"
        )
        try context.store.recordSecurityFee(
            accountID: depot.id, securityID: security.id, date: secondDate,
            feeMinor: 250, note: "Depotgebühr"
        )
        XCTAssertThrowsError(
            try context.store.recordSecurityIncome(
                accountID: depot.id, securityID: security.id, date: secondDate,
                grossMinor: 100, feesMinor: 80, taxesMinor: 30
            )
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
        let prices = try context.store.securityPrices()
        XCTAssertEqual(prices.count, 1)
        XCTAssertEqual(prices.first?.securityID, security.id)
        XCTAssertEqual(prices.first?.priceMinor, 14_000)
        XCTAssertEqual(prices.first?.currency, "EUR")
        XCTAssertEqual(prices.first?.source, "Test")
        let position = try XCTUnwrap(context.store.portfolioPositions().first)
        XCTAssertEqual(position.quantityMicro, 3_000_000)
        XCTAssertEqual(position.costBasisMinor, 36_300)
        XCTAssertEqual(position.marketValueMinor, 42_000)
        XCTAssertEqual(position.unrealizedGainMinor, 5_700)
        let trades = try context.store.securityTrades()
        XCTAssertEqual(trades.filter { $0.type == .dividend }.count, 1)
        XCTAssertEqual(trades.filter { $0.type == .fee }.count, 1)
        XCTAssertEqual(trades.first { $0.type == .dividend }?.grossMinor, 10_000)
        XCTAssertEqual(trades.first { $0.type == .dividend }?.feesMinor, 100)
        XCTAssertEqual(trades.first { $0.type == .dividend }?.taxesMinor, 2_500)
        XCTAssertEqual(trades.first { $0.type == .fee }?.feesMinor, 250)
        let report = PortfolioReportEngine.snapshot(
            query: PortfolioReportQuery(dateFrom: nil, dateThrough: nil),
            positions: [position], trades: trades, accounts: [depot],
            securities: [security]
        )
        let reportTotal = try XCTUnwrap(report.totals.first)
        XCTAssertEqual(reportTotal.incomeMinor, 7_400)
        XCTAssertEqual(reportTotal.realizedGainMinor, 53_800)
        XCTAssertEqual(reportTotal.feesMinor, 2_850)
        XCTAssertEqual(reportTotal.taxesMinor, 2_500)

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
        XCTAssertEqual(schedule.first?.id, "\(loan.id.uuidString):1")
        XCTAssertEqual(
            schedule.map(\.id),
            try context.store.loanSchedule(loanID: loan.id).map(\.id)
        )
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

    func testLoanPaymentsMatchRealBookingsSplitAtomicallyAndReverseLosslessly() throws {
        let context = try TestDatabase()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let account = FinanceAccount(
            id: UUID(), name: "Ratenkonto", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 500_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let otherAccount = FinanceAccount(
            id: UUID(), name: "Fremdkonto", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(account)
        try context.store.saveAccount(otherAccount)
        let loan = FinanceLoan(
            id: UUID(), name: "Testdarlehen", lender: "Kreditbank",
            principalMinor: 100_000, disbursementDate: start,
            firstPaymentDate: start, fixedRateUntil: nil, termMonths: 24,
            installmentMinor: 10_000, regularFeeMinor: 100, dueDay: 15,
            linkedAccountID: account.id, currency: "EUR", note: "", isActive: true
        )
        try context.store.saveLoan(loan)
        try context.store.saveLoanInterestRate(
            LoanInterestRate(
                id: UUID(), loanID: loan.id, annualBasisPoints: 600,
                effectiveFrom: start, note: ""
            )
        )
        let schedule = try context.store.loanSchedule(loanID: loan.id)
        let first = try XCTUnwrap(schedule.first)
        let exactDate = calendar.date(byAdding: .day, value: 12, to: first.dueDate)!
        let closeDate = calendar.date(byAdding: .day, value: 2, to: first.dueDate)!
        let exact = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: exactDate,
            valueDate: exactDate, payee: "Kreditbank", purpose: "Rate exakt",
            categoryID: nil,
            amountMinor: -(first.installmentMinor + first.extraPaymentMinor),
            currency: "EUR", status: .booked, memo: "Original exakt",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        let withExtra = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: closeDate,
            valueDate: closeDate, payee: "Kreditbank", purpose: "Rate plus extra",
            categoryID: nil,
            amountMinor: -(first.installmentMinor + first.extraPaymentMinor + 500),
            currency: "EUR", status: .cleared, memo: "Originalnotiz",
            reference: "BANK-1", transferID: nil, importFingerprint: nil, splits: []
        )
        let wrongAccount = FinanceTransaction(
            id: UUID(), accountID: otherAccount.id, bookingDate: first.dueDate,
            valueDate: first.dueDate, payee: "Kreditbank", purpose: "Fremd",
            categoryID: nil, amountMinor: -first.installmentMinor,
            currency: "EUR", status: .booked, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(exact)
        try context.store.saveTransaction(withExtra)
        try context.store.saveTransaction(wrongAccount)

        let candidates = LoanPaymentMatchingEngine.candidates(
            for: first, loan: loan,
            transactions: try context.store.transactions(),
            alreadyMatchedTransactionIDs: [], calendar: calendar
        )
        XCTAssertEqual(candidates.map(\.id), [exact.id, withExtra.id])
        XCTAssertEqual(candidates[0].amountDifferenceMinor, 0)
        XCTAssertEqual(candidates[1].dayDistance, 2)
        let persistedOriginal = try XCTUnwrap(
            context.store.transactions().first { $0.id == withExtra.id }
        )

        let match = try context.store.matchLoanPayment(
            loanID: loan.id, scheduleEntryID: first.id,
            transactionID: withExtra.id
        )
        XCTAssertEqual(match.source, .linkedExisting)
        XCTAssertEqual(match.actualPaymentMinor, abs(withExtra.amountMinor))
        XCTAssertEqual(match.extraPaymentMinor, 500)
        let matched = try XCTUnwrap(
            context.store.transactions().first { $0.id == withExtra.id }
        )
        XCTAssertEqual(matched.splits.map(\.memo), ["Tilgung", "Sollzins", "Gebühr", "Sondertilgung"])
        XCTAssertEqual(matched.splits.reduce(0) { $0 + $1.amountMinor }, matched.amountMinor)
        XCTAssertTrue(matched.memo.contains("Originalnotiz"))
        XCTAssertTrue(matched.memo.contains("Kreditabgleich"))
        var forbiddenEdit = matched
        forbiddenEdit.purpose = "Darf nicht geändert werden"
        XCTAssertThrowsError(try context.store.saveTransaction(forbiddenEdit))
        XCTAssertThrowsError(try context.store.deleteTransaction(id: matched.id))
        XCTAssertThrowsError(
            try context.store.matchLoanPayment(
                loanID: loan.id, scheduleEntryID: first.id,
                transactionID: exact.id
            )
        )

        try context.store.removeLoanPaymentMatch(id: match.id)
        let restored = try XCTUnwrap(
            context.store.transactions().first { $0.id == withExtra.id }
        )
        XCTAssertEqual(restored, persistedOriginal)
        XCTAssertTrue(try context.store.loanPaymentMatches(loanID: loan.id).isEmpty)

        let second = schedule[1]
        let generated = try context.store.postLoanScheduleEntry(
            loanID: loan.id, scheduleEntryID: second.id
        )
        XCTAssertEqual(generated.source, .generated)
        let generatedBooking = try XCTUnwrap(
            context.store.transactions().first { $0.id == generated.transactionID }
        )
        XCTAssertEqual(generatedBooking.amountMinor, -generated.actualPaymentMinor)
        XCTAssertEqual(generatedBooking.splits.reduce(0) { $0 + $1.amountMinor }, generatedBooking.amountMinor)
        XCTAssertThrowsError(try context.store.deleteTransaction(id: generated.transactionID))
        try context.store.removeLoanPaymentMatch(id: generated.id)
        XCTAssertFalse(try context.store.transactions().contains { $0.id == generated.transactionID })
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testMigration36To37AddsReversibleLoanMatchMetadataAndGuards() throws {
        let context = try TestDatabase()
        let url = context.store.fileURL
        let account = FinanceAccount(
            id: UUID(), name: "Bestandskonto", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 12_300,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        context.store.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                """
                DROP TRIGGER loan_matched_transaction_guard_update;
                DROP TRIGGER loan_matched_transaction_guard_delete;
                DROP INDEX loan_payment_matches_loan_date;
                ALTER TABLE loan_payment_matches DROP COLUMN matched_transaction_json;
                ALTER TABLE loan_payment_matches DROP COLUMN original_transaction_json;
                ALTER TABLE loan_payment_matches DROP COLUMN source;
                ALTER TABLE loan_payment_matches DROP COLUMN extra_payment_minor;
                PRAGMA user_version=36;
                """,
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try migrated.accounts().map(\.id), [account.id])
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        for column in [
            "extra_payment_minor", "source", "original_transaction_json",
            "matched_transaction_json"
        ] {
            XCTAssertEqual(
                try sqliteScalar(
                    url,
                    "SELECT count(*) FROM pragma_table_info('loan_payment_matches') WHERE name='\(column)'"
                ),
                1
            )
        }
        XCTAssertEqual(
            try sqliteScalar(
                url,
                "SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'loan_matched_transaction_guard_%'"
            ),
            2
        )
        XCTAssertTrue(try migrated.loanPaymentMatches().isEmpty)
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testLoanReportFiltersPlanPeriodAndKeepsCurrenciesSeparate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let disbursement = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 12))
        )
        let firstDue = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 2, day: 1, hour: 12))
        )
        let euro = FinanceLoan(
            id: UUID(), name: "Immobiliendarlehen", lender: "Hausbank",
            principalMinor: 1_200_000, disbursementDate: disbursement,
            firstPaymentDate: firstDue, fixedRateUntil: nil,
            termMonths: 12, installmentMinor: 100_000, regularFeeMinor: 100,
            dueDay: 1, linkedAccountID: nil, currency: "EUR", note: "",
            isActive: true
        )
        let euroSchedule = try LoanAmortizationEngine.schedule(
            loan: euro,
            rates: [LoanInterestRate(
                id: UUID(), loanID: euro.id, annualBasisPoints: 600,
                effectiveFrom: disbursement, note: ""
            )],
            extraPayments: [LoanExtraPayment(
                id: UUID(), loanID: euro.id,
                paymentDate: calendar.date(byAdding: .month, value: 1, to: firstDue)!,
                amountMinor: 50_000, note: ""
            )],
            calendar: calendar
        )
        let dollar = FinanceLoan(
            id: UUID(), name: "USD-Darlehen", lender: "Bank",
            principalMinor: 20_000, disbursementDate: disbursement,
            firstPaymentDate: firstDue, fixedRateUntil: nil,
            termMonths: 2, installmentMinor: 10_000, regularFeeMinor: 0,
            dueDay: 1, linkedAccountID: nil, currency: "USD", note: "",
            isActive: false
        )
        let dollarSchedule = try LoanAmortizationEngine.schedule(
            loan: dollar,
            rates: [LoanInterestRate(
                id: UUID(), loanID: dollar.id, annualBasisPoints: 0,
                effectiveFrom: disbursement, note: ""
            )], extraPayments: [], calendar: calendar
        )
        let schedules = [euro.id: euroSchedule, dollar.id: dollarSchedule]

        let active = LoanReportEngine.snapshot(
            query: LoanReportQuery(), loans: [dollar, euro],
            schedulesByLoanID: schedules
        )
        XCTAssertEqual(active.summaries.map(\.loanID), [euro.id])
        XCTAssertEqual(active.rows.count, euroSchedule.count)
        XCTAssertEqual(active.totals.map(\.currency), ["EUR"])
        XCTAssertEqual(active.rows.first?.id, "\(euro.id.uuidString):1")

        let period = LoanReportEngine.snapshot(
            query: LoanReportQuery(
                dateFrom: euroSchedule[1].dueDate,
                dateThrough: euroSchedule[2].dueDate,
                loanIDs: [euro.id]
            ),
            loans: [dollar, euro], schedulesByLoanID: schedules
        )
        let summary = try XCTUnwrap(period.summaries.first)
        XCTAssertEqual(period.rows.map(\.sequence), [2, 3])
        XCTAssertEqual(summary.openingBalanceMinor, euroSchedule[1].openingBalanceMinor)
        XCTAssertEqual(summary.closingBalanceMinor, euroSchedule[2].closingBalanceMinor)
        XCTAssertEqual(
            summary.principalMinor + summary.extraPaymentMinor + summary.closingBalanceMinor,
            summary.openingBalanceMinor
        )
        XCTAssertEqual(summary.paymentCount, 2)
        XCTAssertEqual(summary.rowIDs, Set(period.rows.map(\.id)))
        XCTAssertEqual(summary.interestMinor, euroSchedule[1].interestMinor + euroSchedule[2].interestMinor)
        XCTAssertEqual(summary.feeMinor, 200)
        XCTAssertEqual(summary.extraPaymentMinor, 50_000)

        let matchedEntry = euroSchedule[1]
        let match = LoanPaymentMatch(
            id: UUID(), loanID: euro.id, transactionID: UUID(),
            scheduledDate: matchedEntry.dueDate,
            principalMinor: matchedEntry.principalMinor + 1_000,
            interestMinor: matchedEntry.interestMinor,
            feeMinor: matchedEntry.feeMinor,
            extraPaymentMinor: matchedEntry.extraPaymentMinor,
            matchedAt: matchedEntry.dueDate, source: .linkedExisting
        )
        let reconciled = LoanReportEngine.snapshot(
            query: LoanReportQuery(
                dateFrom: matchedEntry.dueDate, dateThrough: matchedEntry.dueDate,
                loanIDs: [euro.id]
            ),
            loans: [euro], schedulesByLoanID: schedules,
            matches: [match], calendar: calendar
        )
        let reconciledRow = try XCTUnwrap(reconciled.rows.first)
        let reconciledSummary = try XCTUnwrap(reconciled.summaries.first)
        XCTAssertEqual(reconciledRow.actualPaymentMinor, match.actualPaymentMinor)
        XCTAssertEqual(reconciledRow.paymentVarianceMinor, 1_000)
        XCTAssertEqual(reconciledRow.matchSource, .linkedExisting)
        XCTAssertEqual(reconciledRow.matchTransactionID, match.transactionID)
        XCTAssertEqual(reconciledSummary.actualPaymentMinor, match.actualPaymentMinor)
        XCTAssertEqual(reconciledSummary.paymentVarianceMinor, 1_000)
        XCTAssertEqual(reconciledSummary.matchedPaymentCount, 1)
        XCTAssertEqual(reconciled.totals.first?.matchedPaymentCount, 1)

        let inactiveDollar = LoanReportEngine.snapshot(
            query: LoanReportQuery(currencies: ["USD"], includeInactiveLoans: true),
            loans: [euro, dollar], schedulesByLoanID: schedules
        )
        XCTAssertEqual(inactiveDollar.summaries.map(\.loanID), [dollar.id])
        XCTAssertEqual(inactiveDollar.totals.map(\.currency), ["USD"])
        XCTAssertEqual(inactiveDollar.totals.first?.closingBalanceMinor, 0)
    }

    func testLoanReportCSVAndPDFAreDeterministicAndMultipage() throws {
        let loanID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let start = Date(timeIntervalSince1970: 1_735_689_600)
        let rows = (0..<80).map { index in
            LoanReportRow(
                id: "\(loanID.uuidString):\(index + 1)", loanID: loanID,
                loanName: "Darlehen;Nord", lender: "Bank \"Mitte\"",
                currency: "EUR", sequence: index + 1,
                dueDate: start.addingTimeInterval(Double(index) * 86_400),
                openingBalanceMinor: 1_000_000 - Int64(index) * 10_000,
                installmentMinor: 10_500, principalMinor: 10_000,
                interestMinor: 400, feeMinor: 100, extraPaymentMinor: 0,
                closingBalanceMinor: 990_000 - Int64(index) * 10_000,
                annualBasisPoints: 350
            )
        }
        let summary = LoanReportSummary(
            loanID: loanID, loanName: "Darlehen;Nord", lender: "Bank \"Mitte\"",
            currency: "EUR", originalPrincipalMinor: 1_000_000,
            openingBalanceMinor: 1_000_000,
            installmentMinor: 840_000, principalMinor: 800_000,
            interestMinor: 32_000, feeMinor: 8_000, extraPaymentMinor: 0,
            closingBalanceMinor: 200_000, payoffDate: nil, fixedRateUntil: nil,
            rowIDs: Set(rows.map(\.id))
        )
        let snapshot = LoanReportSnapshot(
            dateFrom: nil, dateThrough: nil, summaries: [summary], rows: rows,
            totals: [LoanReportCurrencyTotal(
                currency: "EUR", openingBalanceMinor: 1_000_000,
                paymentMinor: 840_000, principalMinor: 800_000,
                interestMinor: 32_000, feeMinor: 8_000,
                extraPaymentMinor: 0, closingBalanceMinor: 200_000
            )]
        )
        let metadata = LoanReportExportMetadata(
            title: "Kredit-, Zins- und Tilgungsbericht",
            dateLabel: "gesamter Tilgungsplan", filterSummary: "alle Darlehen; EUR",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let csv = LoanReportCSVExporter.data(snapshot: snapshot, metadata: metadata)
        let csvText = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(csvText.contains("Planwerte mit Ist-Zahlungsabgleich"))
        XCTAssertTrue(csvText.contains("Ist-Zahlungen;Abweichung"))
        XCTAssertTrue(csvText.contains("\"Darlehen;Nord\";\"Bank \"\"Mitte\"\"\""))
        XCTAssertTrue(csvText.contains("10000,00;10000,00;8400,00;0,00;0,00;8000,00;320,00;80,00"))
        XCTAssertEqual(csv, LoanReportCSVExporter.data(snapshot: snapshot, metadata: metadata))

        let pdf = try ComparisonReportPDFExporter.loanData(
            snapshot: snapshot, metadata: metadata, orientation: .landscape
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertGreaterThan(document.pageCount, 1)
        let text = (0..<document.pageCount).compactMap {
            document.page(at: $0)?.string
        }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Kredit-, Zins- und Tilgungsbericht"))
        XCTAssertTrue(text.contains("Plan und Ist"))
        XCTAssertTrue(text.contains("Darlehen;Nord"))
        XCTAssertTrue(text.contains("Restschuld"))
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

    func testAssetRegisterReportFiltersTotalsHierarchyAndExportsDeterministically() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
        )
        let start = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 9, day: 1))
        )
        let warranty = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))
        )
        let account = FinanceAccount(
            id: UUID(), name: "Haushaltskonto", institution: "Musterbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let parent = FinanceCategory(
            id: UUID(), parentID: nil, name: "Wohnen", kind: .expense,
            color: "#336699", isActive: true
        )
        let child = FinanceCategory(
            id: UUID(), parentID: parent.id, name: "Versicherung", kind: .expense,
            color: "#336699", isActive: true
        )
        let includedContract = FinanceContract(
            id: UUID(), provider: "Versicherung; Nord", contractNumber: "V-1",
            name: "Hausrat", type: .insurance, startDate: start,
            initialTermMonths: 12, renewalMonths: 12, cancellationNoticeDays: 14,
            amountMinor: 2_500, frequency: .monthly, accountID: account.id,
            categoryID: child.id, reminderDays: 14, note: "", isActive: true
        )
        let inactiveContract = FinanceContract(
            id: UUID(), provider: "Altanbieter", contractNumber: "A-1",
            name: "Alter Vertrag", type: .subscription, startDate: start,
            initialTermMonths: 12, renewalMonths: 12, cancellationNoticeDays: 14,
            amountMinor: 999, frequency: .monthly, accountID: nil,
            categoryID: nil, reminderDays: 7, note: "", isActive: false
        )
        let includedInventory = InventoryItem(
            id: UUID(), name: "Laptop", category: .electronics, room: "Büro",
            purchaseDate: start, purchasePriceMinor: 200_000,
            currentValueMinor: 120_000, insuranceValueMinor: 180_000,
            retailer: "Händler \"Mitte\"", serialNumber: "LT-1",
            warrantyEnd: warranty, note: "", isActive: true
        )
        let excludedInventory = InventoryItem(
            id: UUID(), name: "Sofa", category: .furniture, room: "Wohnzimmer",
            purchaseDate: start, purchasePriceMinor: 80_000,
            currentValueMinor: 40_000, insuranceValueMinor: 50_000,
            retailer: "Möbelhaus", serialNumber: "", warrantyEnd: nil,
            note: "", isActive: true
        )
        let query = AssetRegisterReportQuery(
            referenceDate: reference, horizon: .next30Days,
            includeInactive: false, contractTypes: [.insurance],
            inventoryCategories: [.electronics], text: ""
        )
        let snapshot = AssetRegisterReportEngine.snapshot(
            query: query, contracts: [inactiveContract, includedContract],
            inventory: [excludedInventory, includedInventory], accounts: [account],
            categories: [child, parent], calendar: calendar
        )
        XCTAssertEqual(snapshot.contracts.map(\.id), [includedContract.id])
        XCTAssertEqual(snapshot.inventory.map(\.id), [includedInventory.id])
        XCTAssertEqual(snapshot.contracts.first?.accountName, "Haushaltskonto")
        XCTAssertEqual(snapshot.contracts.first?.categoryPath, "Wohnen > Versicherung")
        XCTAssertEqual(snapshot.annualContractCostMinor, 30_000)
        XCTAssertEqual(snapshot.purchasePriceMinor, 200_000)
        XCTAssertEqual(snapshot.currentValueMinor, 120_000)
        XCTAssertEqual(snapshot.insuranceValueMinor, 180_000)

        let metadata = AssetRegisterReportExportMetadata(
            title: "Vertrags- und Inventarübersicht",
            filterSummary: "Nächste 30 Tage; nur aktiv",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let csv = AssetRegisterReportCSVExporter.data(
            snapshot: snapshot, metadata: metadata
        )
        XCTAssertEqual(
            csv,
            AssetRegisterReportCSVExporter.data(snapshot: snapshot, metadata: metadata)
        )
        let csvText = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(csvText.contains("\"Versicherung; Nord\""))
        XCTAssertTrue(csvText.contains("Wohnen > Versicherung"))
        XCTAssertTrue(csvText.contains("2000,00;1200,00;1800,00"))

        let pdf = try ComparisonReportPDFExporter.assetRegisterData(
            snapshot: snapshot, metadata: metadata, orientation: .landscape
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let pdfText = (0..<document.pageCount).compactMap {
            document.page(at: $0)?.string
        }.joined(separator: "\n")
        XCTAssertTrue(pdfText.contains("Vertrags- und Inventarübersicht"))
        XCTAssertTrue(pdfText.contains("Hausrat"))
        XCTAssertTrue(pdfText.contains("Laptop"))
        XCTAssertTrue(pdfText.contains("Versicherungswert"))
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

    func testCategoryHierarchyFilterFindsFullPathsAndKeepsRequiredAncestors() {
        let realEstate = FinanceCategory(
            id: UUID(), parentID: nil, name: "Immobilien",
            kind: .expense, color: "blue", isActive: true
        )
        let apartment = FinanceCategory(
            id: UUID(), parentID: realEstate.id, name: "Wohnung Köln",
            kind: .expense, color: "blue", isActive: true
        )
        var propertyTax = FinanceCategory(
            id: UUID(), parentID: apartment.id, name: "Grundsteuer",
            kind: .expense, color: "orange", isActive: true
        )
        propertyTax.description = "Kommunale Abgabe"
        propertyTax.germanTaxLine = "Anlage V"
        let inactiveLeaf = FinanceCategory(
            id: UUID(), parentID: apartment.id, name: "Alter Leerstand",
            kind: .expense, color: "gray", isActive: false
        )
        let inactiveParent = FinanceCategory(
            id: UUID(), parentID: nil, name: "Frühere Immobilie",
            kind: .expense, color: "gray", isActive: false
        )
        let activeReserve = FinanceCategory(
            id: UUID(), parentID: inactiveParent.id, name: "Rücklage",
            kind: .expense, color: "green", isActive: true
        )
        let categories = [
            realEstate, apartment, propertyTax, inactiveLeaf,
            inactiveParent, activeReserve
        ]

        XCTAssertEqual(
            CategoryHierarchyFilter.path(
                for: propertyTax, categories: categories
            ),
            "Immobilien:Wohnung Köln:Grundsteuer"
        )
        XCTAssertEqual(
            CategoryHierarchyFilter.visibleIDs(
                categories: categories,
                searchText: "immobilien koln grundsteuer",
                includeInactive: false
            ),
            [realEstate.id, apartment.id, propertyTax.id]
        )
        XCTAssertEqual(
            CategoryHierarchyFilter.visibleIDs(
                categories: categories,
                searchText: "kommunale anlage v",
                includeInactive: false
            ),
            [realEstate.id, apartment.id, propertyTax.id]
        )
        XCTAssertEqual(
            CategoryHierarchyFilter.visibleIDs(
                categories: categories,
                searchText: "rucklage",
                includeInactive: false
            ),
            [inactiveParent.id, activeReserve.id]
        )
        XCTAssertFalse(
            CategoryHierarchyFilter.visibleIDs(
                categories: categories,
                searchText: "leerstand",
                includeInactive: false
            ).contains(inactiveLeaf.id)
        )
        XCTAssertTrue(
            CategoryHierarchyFilter.visibleIDs(
                categories: categories,
                searchText: "leerstand",
                includeInactive: true
            ).isSuperset(of: [realEstate.id, apartment.id, inactiveLeaf.id])
        )
        XCTAssertTrue(
            CategoryHierarchyFilter.visibleIDs(
                categories: categories,
                searchText: "nicht vorhanden",
                includeInactive: true
            ).isEmpty
        )
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
        CREATE TABLE payees (id TEXT PRIMARY KEY);
        CREATE TABLE tags (id TEXT PRIMARY KEY);
        CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL DEFAULT '',
            booking_date TEXT NOT NULL
        );
        CREATE TABLE transaction_splits (id TEXT PRIMARY KEY);
        CREATE TABLE payment_orders (id TEXT PRIMARY KEY);
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
        let migrationFiles = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Sicherungen"),
            includingPropertiesForKeys: nil
        )
        let migrationBackups = migrationFiles.filter {
            $0.lastPathComponent.hasPrefix("FinanzVerwalter-vor-Migration-v10-")
                && $0.pathExtension == "qbackup"
        }
        XCTAssertEqual(migrationBackups.count, 1)
        XCTAssertFalse(migrationFiles.contains {
            $0.lastPathComponent.hasSuffix("-wal") || $0.lastPathComponent.hasSuffix("-shm")
        })
        XCTAssertNoThrow(try SQLiteFinanceStore.validateBackup(at: migrationBackups[0]))
    }

    func testFutureDatabaseSchemaIsRejectedWithoutMutation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-future-schema-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("future.qdata")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(database, "PRAGMA user_version=42", nil, nil, nil),
            SQLITE_OK
        )
        sqlite3_close(database)

        XCTAssertThrowsError(try SQLiteFinanceStore(fileURL: url)) { error in
            guard case let FinanceError.database(message) = error else {
                return XCTFail("Unerwarteter Fehler: \(error)")
            }
            XCTAssertTrue(message.contains("Schema 41"))
            XCTAssertTrue(message.contains("höchstens Schema 41"))
        }
        XCTAssertEqual(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 42)
        sqlite3_finalize(statement)
        sqlite3_close(database)
    }

    func testMigration32To34AddsEmptyScheduledChangesWithoutChangingSchedules() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-migration-32-33-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.qdata")
        var store: SQLiteFinanceStore? = try SQLiteFinanceStore(fileURL: url)
        let account = FinanceAccount(
            id: UUID(), name: "Migration", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try store?.saveAccount(account)
        let schedule = ScheduledTransaction(
            id: UUID(), name: "Bestehende Serie", accountID: account.id,
            payee: "Empfänger", purpose: "Zweck", categoryID: nil,
            amountMinor: -1_000, currency: "EUR", nextDueDate: Date(),
            endDate: nil, frequency: .monthly, action: .remind,
            reminderDays: 3, isActive: true
        )
        try store?.saveScheduledTransaction(schedule)
        store?.close()
        store = nil

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "DROP TABLE scheduled_transaction_exceptions; PRAGMA user_version=32;",
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try migrated.scheduledTransactions().map(\.id), [schedule.id])
        XCTAssertEqual(try migrated.scheduledTransactionExceptions(), [])
        XCTAssertEqual(try migrated.scheduledTransactionRevisions(), [])
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testMigration33To34AddsEmptyScheduledRevisionsWithoutChangingExceptions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-migration-33-34-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.qdata")
        var store: SQLiteFinanceStore? = try SQLiteFinanceStore(fileURL: url)
        let account = FinanceAccount(
            id: UUID(), name: "Migration", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try store?.saveAccount(account)
        let schedule = ScheduledTransaction(
            id: UUID(), name: "Bestehende Serie", accountID: account.id,
            payee: "Empfänger", purpose: "Zweck", categoryID: nil,
            amountMinor: -1_000, currency: "EUR", nextDueDate: Date(),
            endDate: nil, frequency: .monthly, action: .remind,
            reminderDays: 3, isActive: true
        )
        try store?.saveScheduledTransaction(schedule)
        let exception = ScheduledTransactionException(
            id: UUID(), scheduledTransactionID: schedule.id,
            originalDueDate: schedule.nextDueDate,
            effectiveDate: schedule.nextDueDate, payee: "Ausnahme",
            purpose: "Bleibt", categoryID: nil, amountMinor: -2_000,
            disposition: .modified, note: "Bestand", createdAt: Date(),
            updatedAt: Date()
        )
        try store?.saveScheduledTransactionException(exception)
        store?.close()
        store = nil

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "DROP TABLE scheduled_transaction_revisions; PRAGMA user_version=33;",
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try migrated.scheduledTransactions().map(\.id), [schedule.id])
        XCTAssertEqual(try migrated.scheduledTransactionExceptions().map(\.id), [exception.id])
        XCTAssertEqual(try migrated.scheduledTransactionRevisions(), [])
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testMigration29To30PreservesTransactionsAndAddsEmptyFXFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-migration-29-30-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.qdata")
        let account = FinanceAccount(
            id: UUID(), name: "Bestandskonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let transaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(),
            valueDate: nil, payee: "Altbestand", purpose: "Unverändert",
            categoryID: nil, amountMinor: -12_345, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        var initial: SQLiteFinanceStore? = try SQLiteFinanceStore(fileURL: url)
        try initial?.saveAccount(account)
        try initial?.saveTransaction(transaction)
        initial?.close()
        initial = nil

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let downgrade = """
        ALTER TABLE transactions DROP COLUMN exchange_rate_scaled;
        ALTER TABLE transactions DROP COLUMN original_currency;
        ALTER TABLE transactions DROP COLUMN original_amount_minor;
        PRAGMA user_version=29;
        """
        var message: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(
            sqlite3_exec(database, downgrade, nil, nil, &message),
            SQLITE_OK,
            message.map { String(cString: $0) } ?? ""
        )
        if let message { sqlite3_free(message) }
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        let restored = try XCTUnwrap(
            migrated.transactions().first { $0.id == transaction.id }
        )
        XCTAssertEqual(restored.amountMinor, -12_345)
        XCTAssertEqual(restored.currency, "EUR")
        XCTAssertNil(restored.originalAmountMinor)
        XCTAssertTrue(restored.originalCurrency.isEmpty)
        XCTAssertNil(restored.exchangeRateScaled)
        XCTAssertTrue(try migrated.integrityCheck())

        XCTAssertEqual(
            sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil),
            SQLITE_OK
        )
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), Int32(SQLiteFinanceStore.currentSchemaVersion))
        sqlite3_finalize(statement)
        sqlite3_close(database)
    }

    func testMigration14To30PreservesLegacyReconciliationHistory() throws {
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
        CREATE TABLE payees (id TEXT PRIMARY KEY);
        CREATE TABLE tags (id TEXT PRIMARY KEY);
        CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL DEFAULT '',
            booking_date TEXT NOT NULL DEFAULT '2025-01-01'
        );
        CREATE TABLE transaction_splits (id TEXT PRIMARY KEY);
        CREATE TABLE payment_orders (id TEXT PRIMARY KEY);
        CREATE TABLE standing_orders (id TEXT PRIMARY KEY);
        CREATE TABLE standing_order_runs (id TEXT PRIMARY KEY);
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
        XCTAssertEqual(sqlite3_column_int(statement, 0), Int32(SQLiteFinanceStore.currentSchemaVersion))
        sqlite3_finalize(statement)
    }

    func testMigration22To30PromotesLegacyPayeeBankData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-migration-22-23-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.qdata")
        let payee = FinancePayee(
            id: UUID(), canonicalName: "Legacy Lieferant", aliases: [],
            address: "", email: "", phone: "",
            iban: "DE89 3704 0044 0532 0130 00", bic: "COBADEFFXXX",
            defaultCategoryID: nil, preferredAccountID: nil,
            note: "", isActive: true
        )
        var original: SQLiteFinanceStore? = try SQLiteFinanceStore(fileURL: url)
        try original?.savePayee(payee)
        original?.close()
        original = nil

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        let downgradeSQL = """
        DROP TABLE payment_instruction_import_items;
        DROP TABLE payment_instruction_imports;
        DROP TABLE payment_status_report_items;
        DROP TABLE payment_status_reports;
        DROP TABLE payment_batch_items;
        DROP TABLE payment_batches;
        DROP TABLE direct_debit_orders;
        ALTER TABLE standing_order_runs DROP COLUMN banking_calendar_version;
        ALTER TABLE standing_order_runs DROP COLUMN banking_calendar_id;
        ALTER TABLE standing_orders DROP COLUMN banking_calendar_id;
        ALTER TABLE payment_orders DROP COLUMN purpose_code;
        ALTER TABLE payment_orders DROP COLUMN payee_bank_account_id;
        ALTER TABLE payment_orders DROP COLUMN payee_id;
        DROP TABLE payee_bank_accounts;
        ALTER TABLE transactions DROP COLUMN exchange_rate_scaled;
        ALTER TABLE transactions DROP COLUMN original_currency;
        ALTER TABLE transactions DROP COLUMN original_amount_minor;
        PRAGMA user_version=22;
        """
        var message: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(
            sqlite3_exec(database, downgradeSQL, nil, nil, &message),
            SQLITE_OK,
            message.map { String(cString: $0) } ?? ""
        )
        if let message { sqlite3_free(message) }
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        let bankAccount = try XCTUnwrap(
            migrated.payeeBankAccounts(payeeID: payee.id).first
        )
        XCTAssertEqual(bankAccount.label, "Standardkonto")
        XCTAssertEqual(bankAccount.accountHolder, payee.canonicalName)
        XCTAssertEqual(bankAccount.iban, "DE89370400440532013000")
        XCTAssertEqual(bankAccount.bic, "COBADEFFXXX")
        XCTAssertTrue(bankAccount.isDefault)
        XCTAssertTrue(bankAccount.isActive)
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
            transferID: UUID? = nil,
            flag: TransactionFlag? = nil
        ) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: accountID, bookingDate: date, valueDate: nil,
                payee: "Gemeinde", purpose: "Nebenkosten Grundsteuer",
                categoryID: tax.id, amountMinor: -600, currency: "EUR", status: status,
                memo: "Bescheid", reference: "", transferID: transferID,
                importFingerprint: nil, splits: [], payeeID: payeeID,
                tagIDs: [propertyATag.id], flag: flag
            )
        }
        let normal = transaction(accountID: visible.id, flag: .red)
        let hiddenValue = transaction(accountID: hidden.id, flag: .blue)
        let transfer = transaction(
            accountID: visible.id, transferID: UUID(), flag: .red
        )
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
        query.includeDetailRows = false
        query.includeSubtotals = false
        query.includeGrandTotals = false
        query.detailColumns = [.flag, .category, .amount]
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
        XCTAssertEqual(base.facts.first?.flag, .red)
        XCTAssertEqual(base.presentation.detailColumns, [.flag, .category, .amount])

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

        query.flagSelection = TransactionReportFlagSelection(
            flags: [.red], includeUnflagged: false
        )
        XCTAssertEqual(
            Set(TransactionReportEngine.snapshot(
                query: query, transactions: allTransactions,
                accounts: [visible, hidden], categories: [housing, tax],
                tags: [propertyTag, propertyATag]
            ).facts.map(\.transactionID)),
            [normal.id, transfer.id]
        )
        query.flagSelection = TransactionReportFlagSelection(
            flags: [], includeUnflagged: true
        )
        XCTAssertEqual(
            TransactionReportEngine.snapshot(
                query: query, transactions: allTransactions,
                accounts: [visible, hidden], categories: [housing, tax],
                tags: [propertyTag, propertyATag]
            ).facts.map(\.transactionID),
            [cancelled.id]
        )
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
            secondaryGrouping: .category,
            sort: .dateAscending
        )
        query.requireGermanTaxAssignment = true
        query.flagSelection = TransactionReportFlagSelection(
            flags: [.orange, .purple], includeUnflagged: false
        )
        query.detailColumns = [.date, .flag, .category, .tags, .amount, .currency]
        query.visualization = .pie
        query.chartMetric = .income
        let id = UUID()
        try context.store.saveReportTemplate(
            SavedReportTemplate(
                id: id,
                name: "Immobiliensteuer",
                definitionVersion: 2,
                query: query
            )
        )
        let restored = try XCTUnwrap(context.store.reportTemplates().first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.name, "Immobiliensteuer")
        XCTAssertEqual(restored.definitionVersion, 2)
        XCTAssertEqual(restored.query, query)

        query.text = "aktualisiert"
        try context.store.saveReportTemplate(
            SavedReportTemplate(
                id: id,
                name: "Immobiliensteuer aktualisiert",
                definitionVersion: 2,
                query: query
            )
        )
        XCTAssertEqual(try context.store.reportTemplates().count, 1)
        XCTAssertEqual(try context.store.reportTemplates().first?.query.text, "aktualisiert")
        try context.store.deleteReportTemplate(id: id)
        XCTAssertTrue(try context.store.reportTemplates().isEmpty)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testExternalReportWindowRequestRoundTripsQueryAndPinsFinanceFile() throws {
        var query = TransactionReportQuery(
            dateFrom: Date(timeIntervalSince1970: 1_700_000_000),
            dateThrough: Date(timeIntervalSince1970: 1_710_000_000),
            accountIDs: [UUID()], categoryIDs: [UUID()], tagIDs: [UUID()],
            statuses: [.booked, .reconciled], text: "Grundsteuer Köln",
            currencies: ["EUR"], includeTransfers: true,
            grouping: .category, secondaryGrouping: .tag,
            sort: .amountDescending
        )
        query.includeDetailRows = false
        query.includeSubtotals = true
        query.includeGrandTotals = true
        query.visualization = .bar
        query.chartMetric = .expense
        let fileURL = URL(fileURLWithPath: "/tmp/FinanzVerwalter/../FinanzVerwalter/Test.qdata")
        let request = try ReportWindowRequest(
            title: "  Immobilienbericht  ",
            financeFileURL: fileURL,
            query: query
        )

        XCTAssertEqual(request.title, "Immobilienbericht")
        XCTAssertEqual(try request.decodedQuery(), query)
        XCTAssertEqual(
            request.frameAutosaveName,
            "FinanzVerwalter.Auswertung.\(request.id.uuidString.lowercased())"
        )
        XCTAssertTrue(request.belongs(to: fileURL.standardizedFileURL))
        XCTAssertFalse(
            request.belongs(
                to: URL(fileURLWithPath: "/tmp/FinanzVerwalter/Andere.qdata")
            )
        )
        XCTAssertFalse(request.belongs(to: nil))

        let encoded = try JSONEncoder().encode(request)
        let restored = try JSONDecoder().decode(
            ReportWindowRequest.self, from: encoded
        )
        XCTAssertEqual(restored, request)
        XCTAssertEqual(try restored.decodedQuery(), query)

        var damagedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        damagedObject["queryData"] = Data("keine Abfrage".utf8).base64EncodedString()
        let damagedData = try JSONSerialization.data(withJSONObject: damagedObject)
        let damagedRequest = try JSONDecoder().decode(
            ReportWindowRequest.self, from: damagedData
        )
        XCTAssertThrowsError(try damagedRequest.decodedQuery())

        XCTAssertNotEqual(
            request.id,
            try ReportWindowRequest(
                title: request.title,
                financeFileURL: fileURL,
                query: query
            ).id
        )

        let launch = TransactionReportLaunchRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000471")!,
            title: "  Immobilienbericht  ",
            query: query
        )
        XCTAssertEqual(launch.title, "Immobilienbericht")
        XCTAssertEqual(launch.query, query)
        XCTAssertNil(
            TransactionReportLaunchRequest(title: " \n ", query: query).title
        )
    }

    func testSpecializedReportWindowRequestsRoundTripEveryQueryType() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/FinanzVerwalter/Fach.qdata")
        let accountID = UUID()
        let groupID = UUID()
        let from = Date(timeIntervalSince1970: 1_700_000_000)
        let through = Date(timeIntervalSince1970: 1_710_000_000)

        func assertRoundTrip<Payload: Codable & Equatable>(
            _ kind: SpecializedReportKind,
            payload: Payload,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let request = try SpecializedReportWindowRequest(
                kind: kind,
                financeFileURL: fileURL,
                payload: payload
            )
            XCTAssertTrue(request.belongs(to: fileURL), file: file, line: line)
            XCTAssertFalse(
                request.belongs(
                    to: URL(fileURLWithPath: "/tmp/FinanzVerwalter/Fremd.qdata")
                ),
                file: file,
                line: line
            )
            XCTAssertEqual(
                try request.decodedPayload(as: Payload.self),
                payload,
                file: file,
                line: line
            )
            XCTAssertTrue(
                request.frameAutosaveName.contains(".\(kind.rawValue)."),
                file: file,
                line: line
            )
            let restored = try JSONDecoder().decode(
                SpecializedReportWindowRequest.self,
                from: JSONEncoder().encode(request)
            )
            XCTAssertEqual(restored, request, file: file, line: line)
        }

        try assertRoundTrip(
            .accountBalances,
            payload: AccountBalanceReportQuery(
                asOf: through,
                accountIDs: [accountID],
                accountGroupIDs: [groupID],
                currencies: ["EUR"],
                includeHiddenAccounts: true,
                includeClosedAccounts: true,
                includeAccountsExcludedFromNetWorth: true
            )
        )
        try assertRoundTrip(
            .valueAddedTax,
            payload: VATReportQuery(
                dateFrom: from,
                dateThrough: through,
                accountIDs: [accountID],
                accountGroupIDs: [groupID],
                currencies: ["EUR"],
                statuses: [.booked, .reconciled],
                includeHiddenAccounts: true,
                includeAccountsExcludedFromReports: true,
                includeTransfers: true
            )
        )
        try assertRoundTrip(
            .loans,
            payload: LoanReportQuery(
                dateFrom: from,
                dateThrough: through,
                loanIDs: [UUID()],
                currencies: ["EUR"],
                includeInactiveLoans: true
            )
        )
        try assertRoundTrip(
            .periodComparison,
            payload: PeriodComparisonQuery(
                currentFrom: from,
                currentThrough: through,
                referenceFrom: from.addingTimeInterval(-1_000_000),
                referenceThrough: from.addingTimeInterval(-1),
                grouping: .account,
                metric: .net,
                referenceMode: .monthlyAverage,
                baseQuery: TransactionReportQuery(
                    dateFrom: nil,
                    dateThrough: nil,
                    accountIDs: [accountID],
                    grouping: .category,
                    sort: .dateAscending
                )
            )
        )
        try assertRoundTrip(
            .budgetComparison,
            payload: BudgetReportWindowPayload(
                budgetID: UUID(),
                query: BudgetReportQuery(
                    monthKeys: ["2026-01"],
                    includeZeroRows: true
                )
            )
        )
        try assertRoundTrip(
            .portfolio,
            payload: PortfolioReportQuery(
                dateFrom: from,
                dateThrough: through,
                accountIDs: [accountID],
                securityIDs: [UUID()],
                securityTypes: [.etf],
                currencies: ["EUR"],
                includeInactiveSecurities: true,
                includeClosedAccounts: true
            )
        )
        try assertRoundTrip(
            .assetRegister,
            payload: AssetRegisterReportQuery(
                referenceDate: through,
                horizon: .next90Days,
                includeInactive: true,
                contractTypes: [.insurance],
                inventoryCategories: [.electronics],
                text: "Köln"
            )
        )
        try assertRoundTrip(
            .taxAllowances,
            payload: TaxAllowanceReportQuery(
                taxYear: 2026,
                personIDs: [UUID()],
                institutionText: "Sparkasse",
                includeInactive: true
            )
        )
        XCTAssertEqual(SpecializedReportKind.allCases.count, 8)
    }

    func testSpecializedReportLaunchRequestsPreserveEveryEditedQuery() throws {
        let from = Date(timeIntervalSince1970: 1_700_000_000)
        let through = Date(timeIntervalSince1970: 1_710_000_000)

        func assertLaunch(
            _ payload: SpecializedReportLaunchPayload,
            kind: SpecializedReportKind,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let id = UUID()
            let request = SpecializedReportLaunchRequest(id: id, payload: payload)
            XCTAssertEqual(request.id, id, file: file, line: line)
            XCTAssertEqual(request.kind, kind, file: file, line: line)
            let restored = try JSONDecoder().decode(
                SpecializedReportLaunchRequest.self,
                from: JSONEncoder().encode(request)
            )
            XCTAssertEqual(restored, request, file: file, line: line)
            XCTAssertNotEqual(
                SpecializedReportLaunchRequest(payload: payload).id,
                SpecializedReportLaunchRequest(payload: payload).id,
                file: file,
                line: line
            )
        }

        try assertLaunch(
            .accountBalances(AccountBalanceReportQuery(
                asOf: through, accountIDs: [UUID()], currencies: ["EUR"],
                includeClosedAccounts: true
            )),
            kind: .accountBalances
        )
        try assertLaunch(
            .valueAddedTax(VATReportQuery(
                dateFrom: from, dateThrough: through,
                statuses: [.booked], includeTransfers: true
            )),
            kind: .valueAddedTax
        )
        try assertLaunch(
            .loans(LoanReportQuery(
                dateFrom: from, dateThrough: through,
                loanIDs: [UUID()], includeInactiveLoans: true
            )),
            kind: .loans
        )
        try assertLaunch(
            .periodComparison(PeriodComparisonQuery(
                currentFrom: from, currentThrough: through,
                referenceFrom: from.addingTimeInterval(-86_400),
                referenceThrough: through.addingTimeInterval(-86_400),
                grouping: .payee, metric: .income,
                referenceMode: .monthlyAverage,
                baseQuery: TransactionReportQuery(text: "Miete")
            )),
            kind: .periodComparison
        )
        try assertLaunch(
            .budgetComparison(BudgetReportWindowPayload(
                budgetID: UUID(),
                query: BudgetReportQuery(
                    monthKeys: ["2026-08"], includeZeroRows: true
                )
            )),
            kind: .budgetComparison
        )
        try assertLaunch(
            .portfolio(PortfolioReportQuery(
                dateFrom: from, dateThrough: through,
                accountIDs: [UUID()], securityIDs: [UUID()],
                securityTypes: [.stock], currencies: ["EUR"],
                includeInactiveSecurities: true,
                includeClosedAccounts: true
            )),
            kind: .portfolio
        )
        try assertLaunch(
            .assetRegister(AssetRegisterReportQuery(
                referenceDate: through, horizon: .next30Days,
                includeInactive: true, text: "Versicherung"
            )),
            kind: .assetRegister
        )
        try assertLaunch(
            .taxAllowances(TaxAllowanceReportQuery(
                taxYear: 2026, personIDs: [UUID()],
                institutionText: "Bank", includeInactive: true
            )),
            kind: .taxAllowances
        )
    }

    func testPortfolioReportFiltersTotalsDrillDownAndExportsDeterministically() throws {
        let accountID = UUID()
        let closedAccountID = UUID()
        let securityID = UUID()
        let inactiveSecurityID = UUID()
        let equityClassID = UUID()
        let bondClassID = UUID()
        let from = Date(timeIntervalSince1970: 1_700_000_000)
        let through = Date(timeIntervalSince1970: 1_710_000_000)
        let account = FinanceAccount(
            id: accountID, name: "Depot Köln", institution: "Bank",
            type: .investment, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let closedAccount = FinanceAccount(
            id: closedAccountID, name: "Altes Depot", institution: "Bank",
            type: .investment, currency: "USD", openingBalanceMinor: 0,
            isHidden: false, isClosed: true, sortOrder: 1
        )
        let security = Security(
            id: securityID, name: "Europa ETF", shortName: "Europa",
            isin: "DE0000000001", wkn: "ETF001", ticker: "EUETF",
            type: .etf, currency: "EUR", exchange: "Xetra",
            priceDecimals: 2, allowsShort: false, isActive: true, note: ""
        )
        let inactiveSecurity = Security(
            id: inactiveSecurityID, name: "Altaktie", shortName: "Alt",
            isin: "US0000000002", wkn: "ALT002", ticker: "ALT",
            type: .stock, currency: "USD", exchange: "NYSE",
            priceDecimals: 2, allowsShort: false, isActive: false, note: ""
        )
        let equityClass = AssetClass(
            id: equityClassID, name: "Aktien Europa", color: "#3366CC", isActive: true
        )
        let bondClass = AssetClass(
            id: bondClassID, name: "Anleihen", color: "#66AA44", isActive: true
        )
        let allocations = [
            SecurityAllocation(
                id: UUID(), securityID: securityID,
                assetClassID: equityClassID, basisPoints: 6_000
            ),
            SecurityAllocation(
                id: UUID(), securityID: securityID,
                assetClassID: bondClassID, basisPoints: 4_000
            )
        ]
        let positions = [
            PortfolioPosition(
                security: security, accountID: accountID,
                quantityMicro: 2_000_000, costBasisMinor: 18_000,
                latestPriceMinor: 10_000
            ),
            PortfolioPosition(
                security: inactiveSecurity, accountID: closedAccountID,
                quantityMicro: 1_000_000, costBasisMinor: 5_000,
                latestPriceMinor: nil
            )
        ]
        let sell = SecurityTrade(
            id: UUID(), accountID: accountID, securityID: securityID,
            type: .sell, tradeDate: from.addingTimeInterval(100),
            quantityMicro: -500_000, priceMinor: 11_000,
            feesMinor: 100, taxesMinor: 200, grossMinor: 5_500,
            realizedGainMinor: 700, currency: "EUR", note: "Teilveräußerung"
        )
        let dividend = SecurityTrade(
            id: UUID(), accountID: accountID, securityID: securityID,
            type: .dividend, tradeDate: through.addingTimeInterval(-100),
            quantityMicro: 0, priceMinor: 0, feesMinor: 10, taxesMinor: 40,
            grossMinor: 500, realizedGainMinor: 0, currency: "EUR", note: "Ausschüttung"
        )
        let outside = SecurityTrade(
            id: UUID(), accountID: accountID, securityID: securityID,
            type: .fee, tradeDate: from.addingTimeInterval(-100),
            quantityMicro: 0, priceMinor: 0, feesMinor: 99, taxesMinor: 0,
            grossMinor: 0, realizedGainMinor: 0, currency: "EUR", note: "Alt"
        )

        let query = PortfolioReportQuery(
            dateFrom: from, dateThrough: through,
            securityTypes: [.etf], currencies: ["eur"]
        )
        let snapshot = PortfolioReportEngine.snapshot(
            query: query, positions: positions,
            trades: [outside, dividend, sell],
            accounts: [closedAccount, account],
            securities: [inactiveSecurity, security],
            allocationsBySecurityID: [securityID: allocations],
            assetClasses: [bondClass, equityClass]
        )
        XCTAssertEqual(snapshot.positions.map(\.securityID), [securityID])
        XCTAssertEqual(snapshot.trades.map(\.id), [dividend.id, sell.id])
        XCTAssertEqual(snapshot.trades(forSecurityID: securityID).count, 2)
        let total = try XCTUnwrap(snapshot.totals.first)
        XCTAssertEqual(total.currency, "EUR")
        XCTAssertEqual(total.costBasisMinor, 18_000)
        XCTAssertEqual(total.knownMarketValueMinor, 20_000)
        XCTAssertEqual(total.knownUnrealizedGainMinor, 2_000)
        XCTAssertEqual(total.realizedGainMinor, 700)
        XCTAssertEqual(total.incomeMinor, 450)
        XCTAssertEqual(total.feesMinor, 110)
        XCTAssertEqual(total.taxesMinor, 240)
        XCTAssertEqual(snapshot.positions.first?.gainBasisPoints, 1_111)
        XCTAssertEqual(snapshot.allocations.count, 2)
        let equity = try XCTUnwrap(
            snapshot.allocations.first { $0.assetClassID == equityClassID }
        )
        XCTAssertEqual(equity.positionCount, 1)
        XCTAssertEqual(equity.costBasisMinor, 10_800)
        XCTAssertEqual(equity.knownMarketValueMinor, 12_000)
        XCTAssertEqual(equity.marketShareBasisPoints, 6_000)
        XCTAssertEqual(equity.missingPriceCount, 0)
        let bond = try XCTUnwrap(
            snapshot.allocations.first { $0.assetClassID == bondClassID }
        )
        XCTAssertEqual(bond.costBasisMinor, 7_200)
        XCTAssertEqual(bond.knownMarketValueMinor, 8_000)
        XCTAssertEqual(bond.marketShareBasisPoints, 4_000)
        XCTAssertEqual(
            snapshot.allocations.reduce(0) { $0 + $1.costBasisMinor }, 18_000
        )
        XCTAssertEqual(
            snapshot.allocations.reduce(0) { $0 + $1.knownMarketValueMinor }, 20_000
        )

        let all = PortfolioReportEngine.snapshot(
            query: PortfolioReportQuery(
                dateFrom: nil, dateThrough: nil,
                includeInactiveSecurities: true,
                includeClosedAccounts: true
            ),
            positions: positions, trades: [],
            accounts: [account, closedAccount],
            securities: [security, inactiveSecurity],
            allocationsBySecurityID: [securityID: allocations],
            assetClasses: [equityClass, bondClass]
        )
        XCTAssertEqual(all.positions.count, 2)
        XCTAssertEqual(all.totals.first { $0.currency == "USD" }?.missingPriceCount, 1)
        let unassigned = try XCTUnwrap(
            all.allocations.first { $0.assetClassID == nil && $0.currency == "USD" }
        )
        XCTAssertEqual(unassigned.costBasisMinor, 5_000)
        XCTAssertEqual(unassigned.knownMarketValueMinor, 0)
        XCTAssertEqual(unassigned.marketShareBasisPoints, nil)
        XCTAssertEqual(unassigned.missingPriceCount, 1)

        let metadata = PortfolioReportExportMetadata(
            title: "Depotbestand & Erträge", dateLabel: "2023/2024",
            filterSummary: "ETF; aktiv", generatedAt: from
        )
        let csv = ComparisonReportCSVExporter.portfolioData(
            snapshot: snapshot, metadata: metadata
        )
        XCTAssertEqual(
            csv,
            ComparisonReportCSVExporter.portfolioData(
                snapshot: snapshot, metadata: metadata
            )
        )
        let csvText = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(csvText.contains("Depotbestand & Erträge"))
        XCTAssertTrue(csvText.contains("Depot Köln;Europa ETF;ETF"))
        XCTAssertTrue(csvText.contains("Teilveräußerung"))
        XCTAssertTrue(csvText.contains("Asset Allocation"))
        XCTAssertTrue(csvText.contains("Aktien Europa;1;0;108,00;120,00;60,00;EUR"))

        let pdf = try ComparisonReportPDFExporter.portfolioData(
            snapshot: snapshot, metadata: metadata
        )
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        let pdfDocument = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertGreaterThanOrEqual(pdfDocument.pageCount, 1)
        XCTAssertTrue(pdfDocument.string?.contains("Allokation") == true)
        XCTAssertTrue(pdfDocument.string?.contains("Teilveräußerung") == true)
    }

    func testPortfolioPerformanceSeparatesAbsoluteTWRAndXIRR() throws {
        let accountID = UUID()
        let securityID = UUID()
        let from = Date(timeIntervalSince1970: 1_704_067_200) // 01.01.2024 UTC
        let through = Date(timeIntervalSince1970: 1_735_689_600) // 01.01.2025 UTC
        let account = FinanceAccount(
            id: accountID, name: "Testdepot", institution: "Bank",
            type: .investment, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let security = Security(
            id: securityID, name: "Renditefonds", shortName: "Fonds",
            isin: "DE000PERF001", wkn: "PERF01", ticker: "PERF",
            type: .fund, currency: "EUR", exchange: "Xetra",
            priceDecimals: 2, allowsShort: false, isActive: true, note: ""
        )
        let buy = SecurityTrade(
            id: UUID(), accountID: accountID, securityID: securityID,
            type: .buy, tradeDate: from, quantityMicro: 1_000_000,
            priceMinor: 10_000, feesMinor: 0, taxesMinor: 0,
            grossMinor: 10_000, realizedGainMinor: 0,
            currency: "EUR", note: "Start"
        )
        let dividend = SecurityTrade(
            id: UUID(), accountID: accountID, securityID: securityID,
            type: .dividend, tradeDate: through, quantityMicro: 0,
            priceMinor: 0, feesMinor: 0, taxesMinor: 0,
            grossMinor: 1_000, realizedGainMinor: 0,
            currency: "EUR", note: "Ertrag"
        )
        let prices = [
            SecurityPrice(
                securityID: securityID, priceDate: from,
                priceMinor: 10_000, currency: "EUR", source: "Test"
            ),
            SecurityPrice(
                securityID: securityID, priceDate: through,
                priceMinor: 11_000, currency: "EUR", source: "Test"
            )
        ]
        let snapshot = PortfolioReportEngine.snapshot(
            query: PortfolioReportQuery(dateFrom: from, dateThrough: through),
            positions: [
                PortfolioPosition(
                    security: security, accountID: accountID,
                    quantityMicro: 1_000_000, costBasisMinor: 10_000,
                    latestPriceMinor: 11_000
                )
            ],
            trades: [buy, dividend], accounts: [account], securities: [security],
            prices: prices, valuationDate: through,
            calendar: Calendar(identifier: .gregorian)
        )
        let result = try XCTUnwrap(snapshot.performance.first)
        XCTAssertEqual(result.openingMarketValueMinor, 0)
        XCTAssertEqual(result.closingMarketValueMinor, 11_000)
        XCTAssertEqual(result.netContributionsMinor, 9_000)
        XCTAssertEqual(result.absoluteGainMinor, 2_000)
        XCTAssertEqual(result.absoluteReturnBasisPoints, 2_000)
        XCTAssertEqual(result.timeWeightedReturnBasisPoints, 2_000)
        XCTAssertEqual(result.incomeMinor, 1_000)
        XCTAssertEqual(result.feesMinor, 0)
        XCTAssertEqual(result.taxesMinor, 0)
        XCTAssertEqual(result.missingPriceCount, 0)
        XCTAssertEqual(result.oldestClosingPriceDate, through)
        XCTAssertTrue(
            (1_980...2_010).contains(
                try XCTUnwrap(result.moneyWeightedAnnualReturnBasisPoints)
            )
        )
        XCTAssertTrue(
            (1_980...2_010).contains(
                try XCTUnwrap(result.annualizedTimeWeightedReturnBasisPoints)
            )
        )

        let metadata = PortfolioReportExportMetadata(
            title: "Performance", dateLabel: "2024",
            filterSummary: "Testdepot", generatedAt: through
        )
        let csv = try XCTUnwrap(String(
            data: ComparisonReportCSVExporter.portfolioData(
                snapshot: snapshot, metadata: metadata
            ),
            encoding: .utf8
        ))
        XCTAssertTrue(csv.contains("Absolute Rendite %;TWR %;IRR p. a. %"))
        XCTAssertTrue(csv.contains("20,00;20,00"))
        let pdf = try ComparisonReportPDFExporter.portfolioData(
            snapshot: snapshot, metadata: metadata
        )
        XCTAssertTrue(PDFDocument(data: pdf)?.string?.contains("Performance") == true)
    }

    func testReportSecondaryGroupingIsStableAndLegacyQueryDecodes() throws {
        let giro = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let card = FinanceAccount(
            id: UUID(), name: "Karte", institution: "", type: .creditCard,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        let housing = FinanceCategory(
            id: UUID(), parentID: nil, name: "Wohnen", kind: .expense,
            color: "blue", isActive: true
        )
        let food = FinanceCategory(
            id: UUID(), parentID: nil, name: "Lebensmittel", kind: .expense,
            color: "green", isActive: true
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func transaction(
            accountID: UUID, categoryID: UUID, amount: Int64, day: Int
        ) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: accountID,
                bookingDate: now.addingTimeInterval(Double(day * 86_400)),
                valueDate: nil, payee: "Test", purpose: "Auswertung",
                categoryID: categoryID, amountMinor: amount, currency: "EUR",
                status: .booked, memo: "", reference: "", transferID: nil,
                importFingerprint: nil, splits: []
            )
        }
        let snapshot = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(
                grouping: .category, secondaryGrouping: .account,
                sort: .labelAscending
            ),
            transactions: [
                transaction(accountID: giro.id, categoryID: housing.id, amount: -100, day: 0),
                transaction(accountID: giro.id, categoryID: food.id, amount: -200, day: 1),
                transaction(accountID: card.id, categoryID: housing.id, amount: -300, day: 2)
            ],
            accounts: [giro, card], categories: [housing, food], tags: []
        )
        XCTAssertEqual(
            Set(snapshot.groups.filter { $0.level == .detail }.map(\.label)),
            ["Wohnen › Giro", "Lebensmittel › Giro", "Wohnen › Karte"]
        )
        XCTAssertEqual(
            Set(snapshot.groups.filter { $0.level == .subtotal }.map(\.label)),
            ["Summe Lebensmittel", "Summe Wohnen"]
        )
        XCTAssertEqual(
            snapshot.groups.filter { $0.level == .detail }
                .reduce(0) { $0 + $1.bookingCount },
            3
        )
        let housingSubtotal = try XCTUnwrap(
            snapshot.groups.first { $0.label == "Summe Wohnen" }
        )
        XCTAssertEqual(housingSubtotal.expenseMinor, 400)
        XCTAssertEqual(
            Set(snapshot.facts(inGroupID: housingSubtotal.id).map(\.accountName)),
            ["Giro", "Karte"]
        )

        let currentData = try JSONEncoder().encode(TransactionReportQuery())
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "secondaryGrouping")
        legacyObject.removeValue(forKey: "includeDetailRows")
        legacyObject.removeValue(forKey: "includeSubtotals")
        legacyObject.removeValue(forKey: "includeGrandTotals")
        legacyObject.removeValue(forKey: "requireGermanTaxAssignment")
        legacyObject.removeValue(forKey: "visualization")
        legacyObject.removeValue(forKey: "chartMetric")
        legacyObject.removeValue(forKey: "flagSelection")
        legacyObject.removeValue(forKey: "detailColumns")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decoded = try JSONDecoder().decode(
            TransactionReportQuery.self, from: legacyData
        )
        XCTAssertNil(decoded.secondaryGrouping)
        XCTAssertTrue(decoded.showsDetailRows)
        XCTAssertTrue(decoded.showsSubtotals)
        XCTAssertTrue(decoded.showsGrandTotals)
        XCTAssertFalse(decoded.requireGermanTaxAssignment == true)
        XCTAssertEqual(decoded.selectedVisualization, .table)
        XCTAssertEqual(decoded.selectedChartMetric, .expense)
        XCTAssertNil(decoded.flagSelection)
        XCTAssertNil(decoded.detailColumns)
        XCTAssertEqual(
            decoded.selectedDetailColumns,
            TransactionReportDetailColumn.standard
        )
        let customColumns: [TransactionReportDetailColumn] = [
            .flag, .amount, .date
        ]
        XCTAssertEqual(
            TransactionReportDetailColumn.moving(
                .date, to: 0, in: customColumns
            ),
            [.date, .flag, .amount]
        )
        XCTAssertEqual(
            TransactionReportDetailColumn.settingVisibility(
                of: .memo, to: true, in: customColumns
            ),
            [.flag, .amount, .date, .memo]
        )
        XCTAssertEqual(
            TransactionReportDetailColumn.settingVisibility(
                of: .flag, to: false, in: [.flag]
            ),
            [.flag]
        )
    }

    func testTransactionReportStandardPresetsAreDeterministicAndDistinct() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 7, day: 14, hour: 12))
        )
        let expectedStart = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))
        )
        let expectedEnd = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        ).addingTimeInterval(-0.001)

        let presets = TransactionReportStandardPreset.allCases
        XCTAssertEqual(presets.count, 8)
        let queries = presets.map { $0.query(now: now, calendar: calendar) }
        XCTAssertTrue(queries.allSatisfy { $0.dateFrom == expectedStart })
        XCTAssertTrue(queries.allSatisfy { $0.dateThrough == expectedEnd })
        XCTAssertEqual(Set(queries.map { "\($0.grouping.rawValue):\($0.secondaryGrouping?.rawValue ?? "-"):\($0.sort.rawValue)" }).count, 8)

        let journal = TransactionReportStandardPreset.bookingJournal.query(
            now: now, calendar: calendar
        )
        XCTAssertEqual(journal.grouping, .none)
        XCTAssertNil(journal.secondaryGrouping)
        XCTAssertEqual(journal.sort, .dateAscending)

        let cashFlow = TransactionReportStandardPreset.cashFlow.query(
            now: now, calendar: calendar
        )
        XCTAssertEqual(cashFlow.grouping, .account)
        XCTAssertEqual(cashFlow.secondaryGrouping, .category)
        XCTAssertFalse(cashFlow.includeTransfers)
        XCTAssertTrue(cashFlow.expandSplits)

        let monthly = TransactionReportStandardPreset.monthlyCashFlow.query(
            now: now, calendar: calendar
        )
        XCTAssertEqual(monthly.grouping, .month)
        XCTAssertEqual(monthly.sort, .labelAscending)
        XCTAssertEqual(monthly.selectedVisualization, .line)
        XCTAssertEqual(monthly.selectedChartMetric, .expense)

        let tax = TransactionReportStandardPreset.germanTaxReport.query(
            now: now, calendar: calendar
        )
        XCTAssertEqual(tax.grouping, .germanTaxLine)
        XCTAssertEqual(tax.secondaryGrouping, .category)
        XCTAssertTrue(tax.requireGermanTaxAssignment == true)
    }

    func testGermanTaxReportFiltersAssignmentsAndKeepsCategoryDrillDown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 7, day: 14))
        )
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let root = FinanceCategory(
            id: UUID(), parentID: nil, name: "Immobilie A", kind: .expense,
            color: "", isActive: true
        )
        let assigned = FinanceCategory(
            id: UUID(), parentID: root.id, name: "Grundsteuer", kind: .expense,
            color: "", isActive: true,
            germanTaxLine: "Anlage V · öffentliche Lasten"
        )
        let unassigned = FinanceCategory(
            id: UUID(), parentID: root.id, name: "Instandhaltung", kind: .expense,
            color: "", isActive: true
        )
        let splitTransaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: now, valueDate: nil,
            payee: "Gemeinde", purpose: "Bescheid", categoryID: nil,
            amountMinor: -1_000, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: assigned.id, amountMinor: -700,
                    memo: "Grundsteuer", sortOrder: 0
                ),
                FinanceSplit(
                    id: UUID(), categoryID: unassigned.id, amountMinor: -300,
                    memo: "Reparatur", sortOrder: 1
                )
            ]
        )
        let direct = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: now, valueDate: nil,
            payee: "Gemeinde", purpose: "Nachzahlung", categoryID: assigned.id,
            amountMinor: -200, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: []
        )
        let snapshot = TransactionReportEngine.snapshot(
            query: TransactionReportStandardPreset.germanTaxReport.query(
                now: now, calendar: calendar
            ),
            transactions: [splitTransaction, direct], accounts: [account],
            categories: [root, assigned, unassigned], tags: []
        )

        XCTAssertEqual(snapshot.facts.count, 2)
        XCTAssertEqual(Set(snapshot.facts.map(\.transactionID)), [splitTransaction.id, direct.id])
        XCTAssertTrue(snapshot.facts.allSatisfy {
            $0.germanTaxLine == "Anlage V · öffentliche Lasten"
        })
        XCTAssertEqual(snapshot.totals.first?.expenseMinor, 900)
        let detail = try XCTUnwrap(
            snapshot.groups.first { $0.level == .detail }
        )
        XCTAssertEqual(
            detail.label,
            "Anlage V · öffentliche Lasten › Immobilie A › Grundsteuer"
        )
        XCTAssertEqual(detail.expenseMinor, 900)
        XCTAssertEqual(snapshot.facts(inGroupID: detail.id).count, 2)
    }

    func testReportChartsAggregateTopSegmentsExactlyAndSeparateCurrencies() throws {
        let euro = FinanceAccount(
            id: UUID(), name: "Euro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let dollar = FinanceAccount(
            id: UUID(), name: "Dollar", institution: "", type: .foreignCurrency,
            currency: "USD", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        let categories = (0..<7).map { index in
            FinanceCategory(
                id: UUID(), parentID: nil, name: "Kategorie \(index)",
                kind: .expense, color: "", isActive: true
            )
        }
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let euroTransactions = (0..<5).map { index in
            FinanceTransaction(
                id: UUID(), accountID: euro.id, bookingDate: date, valueDate: nil,
                payee: "Test", purpose: "EUR \(index)", categoryID: categories[index].id,
                amountMinor: -Int64((index + 1) * 100), currency: "EUR", status: .booked,
                memo: "", reference: "", transferID: nil, importFingerprint: nil,
                splits: []
            )
        }
        let dollarTransactions = (5..<7).map { index in
            FinanceTransaction(
                id: UUID(), accountID: dollar.id, bookingDate: date, valueDate: nil,
                payee: "Test", purpose: "USD \(index)", categoryID: categories[index].id,
                amountMinor: -Int64((index - 4) * 700), currency: "USD", status: .booked,
                memo: "", reference: "", transferID: nil, importFingerprint: nil,
                splits: []
            )
        }
        let snapshot = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(grouping: .category),
            transactions: euroTransactions + dollarTransactions,
            accounts: [euro, dollar], categories: categories, tags: []
        )

        let first = ReportChartEngine.series(
            snapshot: snapshot, metric: .expense, maximumSegments: 3
        )
        let second = ReportChartEngine.series(
            snapshot: snapshot, metric: .expense, maximumSegments: 3
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.currency), ["EUR", "USD"])
        let euroSeries = try XCTUnwrap(first.first { $0.currency == "EUR" })
        let usdSeries = try XCTUnwrap(first.first { $0.currency == "USD" })
        XCTAssertEqual(euroSeries.values.count, 3)
        XCTAssertEqual(euroSeries.values.map(\.amountMinor), [500, 400, 600])
        XCTAssertEqual(euroSeries.values.last?.label, "Weitere (3)")
        XCTAssertTrue(euroSeries.values.last?.isRemainder == true)
        XCTAssertEqual(euroSeries.totalMinor, 1_500)
        XCTAssertEqual(usdSeries.values.count, 2)
        XCTAssertFalse(usdSeries.values.contains { $0.isRemainder })
        XCTAssertEqual(usdSeries.totalMinor, 2_100)
        XCTAssertEqual(first.reduce(0) { $0 + $1.totalMinor }, 3_600)
    }

    func testMonthlyTimeSeriesIsChronologicalCompleteAndUsesExactFacts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let category = FinanceCategory(
            id: UUID(), parentID: nil, name: "Laufende Kosten",
            kind: .expense, color: "", isActive: true
        )
        let transactions = try (0..<14).map { offset in
            let date = try XCTUnwrap(
                calendar.date(
                    byAdding: .month,
                    value: offset,
                    to: XCTUnwrap(
                        calendar.date(
                            from: DateComponents(
                                year: 2025, month: 1, day: 15, hour: 12
                            )
                        )
                    )
                )
            )
            return FinanceTransaction(
                id: UUID(), accountID: account.id, bookingDate: date,
                valueDate: nil, payee: "Lieferant", purpose: "Monat \(offset)",
                categoryID: category.id, amountMinor: -Int64((offset + 1) * 100),
                currency: "EUR", status: .booked, memo: "", reference: "",
                transferID: nil, importFingerprint: nil, splits: []
            )
        }
        let snapshot = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(
                grouping: .month, sort: .labelAscending
            ),
            transactions: transactions, accounts: [account],
            categories: [category], tags: []
        )

        XCTAssertEqual(snapshot.groups.count, 14)
        XCTAssertEqual(snapshot.groups.first?.label, "2025-01")
        XCTAssertEqual(snapshot.groups.last?.label, "2026-02")
        let series = try XCTUnwrap(
            ReportChartEngine.series(
                snapshot: snapshot,
                metric: .expense,
                order: .labelAscending,
                maximumSegments: nil
            ).first
        )
        XCTAssertEqual(series.values.count, 14)
        XCTAssertFalse(series.values.contains { $0.isRemainder })
        XCTAssertEqual(series.values.map(\.label), snapshot.groups.map(\.label))
        XCTAssertEqual(series.values.first?.amountMinor, 100)
        XCTAssertEqual(series.values.last?.amountMinor, 1_400)
        XCTAssertEqual(
            series.values.reduce(into: Set<String>()) {
                $0.formUnion($1.factIDs)
            },
            Set(snapshot.facts.map(\.id))
        )
        XCTAssertEqual(series.totalMinor, 10_500)
    }

    func testVATReportUsesRoundedSplitLinesAndSeparatesCurrencies() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 6, day: 15, hour: 12))
        )
        let groupID = UUID()
        let euro = FinanceAccount(
            id: UUID(), name: "Geschäftskonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0, groupID: groupID
        )
        let dollar = FinanceAccount(
            id: UUID(), name: "USD-Konto", institution: "", type: .foreignCurrency,
            currency: "USD", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1, groupID: groupID
        )
        let income = FinanceCategory(
            id: UUID(), parentID: nil, name: "Umsätze", kind: .income,
            color: "", isActive: true
        )
        let office = FinanceCategory(
            id: UUID(), parentID: nil, name: "Betrieb", kind: .expense,
            color: "", isActive: true
        )
        let supplies = FinanceCategory(
            id: UUID(), parentID: office.id, name: "Material", kind: .expense,
            color: "", isActive: true
        )
        let code19 = VATCode(
            id: UUID(), name: "USt. 19 %", rateBasisPoints: 1_900,
            description: "", isActive: true
        )
        let code7 = VATCode(
            id: UUID(), name: "USt. 7 %", rateBasisPoints: 700,
            description: "", isActive: true
        )
        let sale = try VATCalculator.automatic(
            grossMinor: 11_900, rateBasisPoints: code19.rateBasisPoints
        )
        let purchase19 = try VATCalculator.automatic(
            grossMinor: -11_900, rateBasisPoints: code19.rateBasisPoints
        )
        let purchase7 = try VATCalculator.automatic(
            grossMinor: -10_700, rateBasisPoints: code7.rateBasisPoints
        )
        let purchaseRefund = try VATCalculator.automatic(
            grossMinor: 1_070, rateBasisPoints: code7.rateBasisPoints
        )
        let receipt = try VATCalculator.receipt([purchase19, purchase7])
        let euroSale = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: date, valueDate: nil,
            payee: "Kunde", purpose: "Rechnung", categoryID: income.id,
            amountMinor: sale.grossMinor, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [], vatCodeID: code19.id, vatMode: .automatic,
            netMinor: sale.netMinor, taxMinor: sale.taxMinor
        )
        let euroPurchase = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: date.addingTimeInterval(60),
            valueDate: nil, payee: "Lieferant", purpose: "Gemischter Beleg",
            categoryID: nil, amountMinor: receipt.grossMinor, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil,
            splits: [
                FinanceSplit(
                    id: UUID(), categoryID: supplies.id,
                    amountMinor: purchase19.grossMinor, memo: "19 %", sortOrder: 0,
                    vatCodeID: code19.id, vatMode: .automatic,
                    netMinor: purchase19.netMinor, taxMinor: purchase19.taxMinor
                ),
                FinanceSplit(
                    id: UUID(), categoryID: supplies.id,
                    amountMinor: purchase7.grossMinor, memo: "7 %", sortOrder: 1,
                    vatCodeID: code7.id, vatMode: .manual,
                    netMinor: purchase7.netMinor, taxMinor: purchase7.taxMinor
                )
            ], vatCodeID: nil, vatMode: .none,
            netMinor: receipt.netMinor, taxMinor: receipt.taxMinor
        )
        let dollarSale = FinanceTransaction(
            id: UUID(), accountID: dollar.id, bookingDate: date, valueDate: nil,
            payee: "US Customer", purpose: "Invoice", categoryID: income.id,
            amountMinor: sale.grossMinor, currency: "USD", status: .booked,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [], vatCodeID: code19.id, vatMode: .automatic,
            netMinor: sale.netMinor, taxMinor: sale.taxMinor
        )
        let euroRefund = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: date.addingTimeInterval(120),
            valueDate: nil, payee: "Lieferant", purpose: "Materialgutschrift",
            categoryID: supplies.id, amountMinor: purchaseRefund.grossMinor,
            currency: "EUR", status: .booked, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: [],
            vatCodeID: code7.id, vatMode: .automatic,
            netMinor: purchaseRefund.netMinor, taxMinor: purchaseRefund.taxMinor
        )
        let cancelled = FinanceTransaction(
            id: UUID(), accountID: euro.id, bookingDate: date, valueDate: nil,
            payee: "Storniert", purpose: "", categoryID: income.id,
            amountMinor: sale.grossMinor, currency: "EUR", status: .cancelled,
            memo: "", reference: "", transferID: nil, importFingerprint: nil,
            splits: [], vatCodeID: code19.id, vatMode: .automatic,
            netMinor: sale.netMinor, taxMinor: sale.taxMinor
        )
        try [euroSale, euroPurchase, dollarSale, euroRefund, cancelled]
            .forEach { try $0.validate() }

        let snapshot = VATReportEngine.snapshot(
            query: VATReportQuery(
                dateFrom: date.addingTimeInterval(-3_600),
                dateThrough: date.addingTimeInterval(3_600),
                accountGroupIDs: [groupID]
            ),
            transactions: [cancelled, dollarSale, euroRefund, euroPurchase, euroSale],
            accounts: [euro, dollar], categories: [income, office, supplies],
            vatCodes: [code19, code7]
        )

        XCTAssertEqual(snapshot.facts.count, 5)
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.totals.count, 2)
        let euroTotal = try XCTUnwrap(snapshot.totals.first { $0.currency == "EUR" })
        XCTAssertEqual(euroTotal.grossSalesMinor, 11_900)
        XCTAssertEqual(euroTotal.netSalesMinor, 10_000)
        XCTAssertEqual(euroTotal.outputTaxMinor, 1_900)
        XCTAssertEqual(euroTotal.grossPurchasesMinor, 21_530)
        XCTAssertEqual(euroTotal.netPurchasesMinor, 19_000)
        XCTAssertEqual(euroTotal.inputTaxMinor, 2_530)
        XCTAssertEqual(euroTotal.payableMinor, -630)
        let dollarTotal = try XCTUnwrap(snapshot.totals.first { $0.currency == "USD" })
        XCTAssertEqual(dollarTotal.outputTaxMinor, 1_900)
        XCTAssertEqual(dollarTotal.inputTaxMinor, 0)
        XCTAssertEqual(dollarTotal.payableMinor, 1_900)
        let code19Euro = try XCTUnwrap(snapshot.rows.first {
            $0.vatCodeID == code19.id && $0.currency == "EUR"
        })
        XCTAssertEqual(code19Euro.bookingCount, 2)
        XCTAssertEqual(code19Euro.payableMinor, 0)
        XCTAssertEqual(snapshot.facts(inRowID: code19Euro.id).count, 2)
        XCTAssertTrue(snapshot.facts.contains { $0.categoryPath == "Betrieb › Material" })
        XCTAssertEqual(Set(snapshot.facts.map(\.id)).count, snapshot.facts.count)
    }

    func testVATReportCSVAndPDFUseTheSameSnapshotDeterministically() throws {
        let codeID = UUID(uuidString: "00000000-0000-0000-0000-000000000019")!
        let fact = VATReportFact(
            id: "fact-1", transactionID: UUID(), splitID: nil,
            bookingDate: Date(timeIntervalSince1970: 1_735_689_600),
            accountName: "Geschäft;Giro", payee: "Kunde \"Nord\"",
            categoryPath: "Umsätze › Beratung", categoryKind: .income,
            vatCodeID: codeID,
            vatCodeName: "USt. 19 %", rateBasisPoints: 1_900,
            grossMinor: 11_900, netMinor: 10_000, taxMinor: 1_900,
            currency: "EUR"
        )
        let row = VATReportRow(
            id: "row-1", vatCodeID: codeID, vatCodeName: "USt. 19 %",
            rateBasisPoints: 1_900, currency: "EUR",
            grossSalesMinor: 11_900, netSalesMinor: 10_000,
            outputTaxMinor: 1_900, grossPurchasesMinor: 0,
            netPurchasesMinor: 0, inputTaxMinor: 0, payableMinor: 1_900,
            factIDs: [fact.id]
        )
        let snapshot = VATReportSnapshot(
            dateFrom: fact.bookingDate, dateThrough: fact.bookingDate,
            facts: [fact], rows: [row],
            totals: [VATReportCurrencyTotal(
                currency: "EUR", grossSalesMinor: 11_900, netSalesMinor: 10_000,
                outputTaxMinor: 1_900, grossPurchasesMinor: 0,
                netPurchasesMinor: 0, inputTaxMinor: 0, payableMinor: 1_900
            )]
        )
        let metadata = VATReportExportMetadata(
            title: "Umsatzsteuerbericht", dateLabel: "01.01.2025–31.12.2025",
            filterSummary: "alle Konten; EUR", generatedAt: Date(timeIntervalSince1970: 0)
        )
        let csv = VATReportCSVExporter.data(snapshot: snapshot, metadata: metadata)
        let csvText = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(csvText.contains("119,00;100,00;19,00"))
        XCTAssertTrue(csvText.contains("\"Geschäft;Giro\";\"Kunde \"\"Nord\"\"\""))
        XCTAssertTrue(csvText.contains("Umsätze › Beratung"))
        XCTAssertEqual(csv, VATReportCSVExporter.data(snapshot: snapshot, metadata: metadata))

        let pdf = try ComparisonReportPDFExporter.vatData(
            snapshot: snapshot, metadata: metadata, orientation: .landscape
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let text = (0..<document.pageCount).compactMap {
            document.page(at: $0)?.string
        }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Umsatzsteuerbericht"))
        XCTAssertTrue(text.contains("USt. 19 %"))
        XCTAssertTrue(text.contains("Zahllast"))
    }

    func testAccountBalanceReportUsesHistoricalCutoffAndSeparatesCurrencies() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let cutoff = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 6, day: 30, hour: 12))
        )
        let group = AccountGroup(id: UUID(), name: "Liquidität", sortOrder: 0, isActive: true)
        let euro = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0, groupID: group.id,
            openingDate: calendar.date(byAdding: .day, value: -4, to: cutoff)
        )
        let debt = FinanceAccount(
            id: UUID(), name: "Karte", institution: "", type: .creditCard,
            currency: "EUR", openingBalanceMinor: -2_000,
            isHidden: false, isClosed: false, sortOrder: 1, groupID: group.id
        )
        let dollar = FinanceAccount(
            id: UUID(), name: "Dollar", institution: "", type: .foreignCurrency,
            currency: "USD", openingBalanceMinor: 5_000,
            isHidden: false, isClosed: false, sortOrder: 2
        )
        let excluded = FinanceAccount(
            id: UUID(), name: "Privat", institution: "", type: .cash,
            currency: "EUR", openingBalanceMinor: 99_999,
            isHidden: false, isClosed: false, sortOrder: 3, includeNetWorth: false
        )
        func transaction(
            account: FinanceAccount, amount: Int64, day: Int,
            status: TransactionStatus = .booked, currency: String? = nil
        ) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: account.id,
                bookingDate: calendar.date(byAdding: .day, value: day, to: cutoff)!,
                valueDate: nil, payee: "", purpose: "", categoryID: nil,
                amountMinor: amount, currency: currency ?? account.currency,
                status: status, memo: "", reference: "", transferID: nil,
                importFingerprint: nil, splits: []
            )
        }
        let snapshot = AccountBalanceReportEngine.snapshot(
            query: AccountBalanceReportQuery(asOf: cutoff),
            accounts: [excluded, dollar, debt, euro], accountGroups: [group],
            transactions: [
                transaction(account: euro, amount: 2_500, day: -1),
                transaction(account: euro, amount: 4_000, day: -5),
                transaction(account: euro, amount: 8_000, day: 1),
                transaction(account: euro, amount: 7_000, day: -2, status: .cancelled),
                transaction(account: euro, amount: 6_000, day: -3, currency: "USD"),
                transaction(account: debt, amount: -1_000, day: 0),
                transaction(account: dollar, amount: 500, day: 0)
            ],
            calendar: calendar
        )
        XCTAssertEqual(snapshot.rows.map(\.accountName), ["Dollar", "Giro", "Karte"])
        XCTAssertEqual(snapshot.rows.first { $0.accountID == euro.id }?.movementMinor, 2_500)
        XCTAssertEqual(snapshot.rows.first { $0.accountID == euro.id }?.balanceMinor, 12_500)
        XCTAssertEqual(snapshot.rows.first { $0.accountID == debt.id }?.balanceMinor, -3_000)
        XCTAssertEqual(snapshot.rows.first { $0.accountID == dollar.id }?.balanceMinor, 5_500)
        XCTAssertEqual(
            snapshot.totals,
            [
                AccountBalanceReportCurrencyTotal(
                    currency: "EUR", assetsMinor: 12_500,
                    liabilitiesMinor: 3_000, netWorthMinor: 9_500
                ),
                AccountBalanceReportCurrencyTotal(
                    currency: "USD", assetsMinor: 5_500,
                    liabilitiesMinor: 0, netWorthMinor: 5_500
                )
            ]
        )
    }

    func testAccountBalanceReportCSVIsDeterministicAndGermanFormatted() throws {
        let snapshot = AccountBalanceReportSnapshot(
            asOf: Date(timeIntervalSince1970: 1_735_689_599),
            rows: [
                AccountBalanceReportRow(
                    accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    groupName: "Bank;Privat", accountName: "Giro \"Nord\"",
                    accountType: .checking, currency: "EUR",
                    openingBalanceMinor: 12_345, movementMinor: -345,
                    balanceMinor: 12_000, isHidden: false, isClosed: false,
                    includeNetWorth: true
                )
            ],
            totals: [
                AccountBalanceReportCurrencyTotal(
                    currency: "EUR", assetsMinor: 12_000,
                    liabilitiesMinor: 0, netWorthMinor: 12_000
                )
            ]
        )
        let data = AccountBalanceReportCSVExporter.data(
            snapshot: snapshot,
            metadata: AccountBalanceReportExportMetadata(
                title: "Kontosalden", filterSummary: "alle Vermögenskonten",
                generatedAt: Date(timeIntervalSince1970: 0)
            )
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"Bank;Privat\";\"Giro \"\"Nord\"\"\""))
        XCTAssertTrue(text.contains("123,45;-3,45;120,00;EUR"))
        XCTAssertTrue(text.contains("EUR;120,00;0,00;120,00"))
        XCTAssertEqual(
            data,
            AccountBalanceReportCSVExporter.data(
                snapshot: snapshot,
                metadata: AccountBalanceReportExportMetadata(
                    title: "Kontosalden", filterSummary: "alle Vermögenskonten",
                    generatedAt: Date(timeIntervalSince1970: 0)
                )
            )
        )
    }

    func testAccountBalanceReportPDFIsReadableAndMultipage() throws {
        let rows = (0..<80).map { index in
            AccountBalanceReportRow(
                accountID: UUID(), groupName: "Bankkonten",
                accountName: "Konto \(index)", accountType: .checking,
                currency: "EUR", openingBalanceMinor: 10_000,
                movementMinor: Int64(index), balanceMinor: 10_000 + Int64(index),
                isHidden: false, isClosed: false, includeNetWorth: true
            )
        }
        let snapshot = AccountBalanceReportSnapshot(
            asOf: Date(timeIntervalSince1970: 1_735_689_599),
            rows: rows,
            totals: [
                AccountBalanceReportCurrencyTotal(
                    currency: "EUR",
                    assetsMinor: rows.reduce(0) { $0 + $1.balanceMinor },
                    liabilitiesMinor: 0,
                    netWorthMinor: rows.reduce(0) { $0 + $1.balanceMinor }
                )
            ]
        )
        let data = try AccountBalanceReportPDFExporter.data(
            snapshot: snapshot,
            metadata: AccountBalanceReportExportMetadata(
                title: "Kontosalden und Nettovermögen",
                filterSummary: "alle Vermögenskonten",
                generatedAt: Date(timeIntervalSince1970: 0)
            )
        )
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("Kontosalden und Nettovermögen"))
        XCTAssertTrue(text.contains("Konto 0"))
        XCTAssertTrue(text.contains("Konto 79"))
        XCTAssertTrue(text.contains("Nettovermögen EUR"))
        XCTAssertTrue(text.contains("Seite 1 von"))
    }

    func testPeriodComparisonAlignsGroupsAndCalculatesAmountAndPercent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        func day(_ year: Int, _ month: Int, _ value: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(
                year: year, month: month, day: value, hour: hour
            ))!
        }
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let parent = FinanceCategory(
            id: UUID(), parentID: nil, name: "Haushalt", kind: .expense,
            color: "#000000", isActive: true
        )
        let food = FinanceCategory(
            id: UUID(), parentID: parent.id, name: "Lebensmittel", kind: .expense,
            color: "#000000", isActive: true
        )
        let travel = FinanceCategory(
            id: UUID(), parentID: nil, name: "Reisen", kind: .expense,
            color: "#000000", isActive: true
        )
        func transaction(_ date: Date, _ amount: Int64, _ categoryID: UUID) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: account.id, bookingDate: date,
                valueDate: nil, payee: "", purpose: "", categoryID: categoryID,
                amountMinor: amount, currency: "EUR", status: .booked,
                memo: "", reference: "", transferID: nil,
                importFingerprint: nil, splits: []
            )
        }
        let transactions = [
            transaction(day(2025, 1, 10), -10_000, food.id),
            transaction(day(2025, 2, 10), -15_000, food.id),
            transaction(day(2025, 2, 11), -5_000, travel.id),
            transaction(day(2025, 3, 10), -25_000, food.id)
        ]
        let snapshot = PeriodComparisonEngine.snapshot(
            query: PeriodComparisonQuery(
                currentFrom: day(2025, 2, 1, 0),
                currentThrough: day(2025, 2, 28, 23),
                referenceFrom: day(2025, 1, 1, 0),
                referenceThrough: day(2025, 1, 31, 23),
                grouping: .category, metric: .expense,
                baseQuery: TransactionReportQuery(dateFrom: nil, dateThrough: nil)
            ),
            transactions: transactions,
            accounts: [account], categories: [travel, food, parent], tags: []
        )
        XCTAssertEqual(snapshot.rows.map(\.label), ["Haushalt › Lebensmittel", "Reisen"])
        let foodRow = try XCTUnwrap(snapshot.rows.first { $0.label.contains("Lebensmittel") })
        XCTAssertEqual(foodRow.currentMinor, 15_000)
        XCTAssertEqual(foodRow.referenceMinor, 10_000)
        XCTAssertEqual(foodRow.differenceMinor, 5_000)
        XCTAssertEqual(foodRow.percentBasisPoints, 5_000)
        let travelRow = try XCTUnwrap(snapshot.rows.first { $0.label == "Reisen" })
        XCTAssertEqual(travelRow.currentMinor, 5_000)
        XCTAssertEqual(travelRow.referenceMinor, 0)
        XCTAssertNil(travelRow.percentBasisPoints)
        XCTAssertEqual(foodRow.currentFactIDs.count, 1)
        XCTAssertEqual(foodRow.referenceFactIDs.count, 1)
        let total = try XCTUnwrap(snapshot.totals.first)
        XCTAssertEqual(total.currentMinor, 20_000)
        XCTAssertEqual(total.referenceMinor, 10_000)
        XCTAssertEqual(total.differenceMinor, 10_000)
        XCTAssertEqual(total.percentBasisPoints, 10_000)

        let average = PeriodComparisonEngine.snapshot(
            query: PeriodComparisonQuery(
                currentFrom: day(2025, 3, 1, 0),
                currentThrough: day(2025, 3, 31, 23),
                referenceFrom: day(2025, 1, 1, 0),
                referenceThrough: day(2025, 2, 28, 23),
                grouping: .category, metric: .expense,
                referenceMode: .monthlyAverage,
                baseQuery: TransactionReportQuery(dateFrom: nil, dateThrough: nil)
            ),
            transactions: transactions, accounts: [account],
            categories: [travel, food, parent], tags: [], calendar: calendar
        )
        let averageFood = try XCTUnwrap(
            average.rows.first { $0.label.contains("Lebensmittel") }
        )
        XCTAssertEqual(averageFood.currentMinor, 25_000)
        XCTAssertEqual(averageFood.referenceMinor, 12_500)
        XCTAssertEqual(averageFood.differenceMinor, 12_500)
        XCTAssertEqual(averageFood.percentBasisPoints, 10_000)
    }

    func testBudgetReportUsesBusinessYearSplitsAndEligibleAccounts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let budget = FinanceBudget(
            id: UUID(), name: "Haushalt 2025/26", startYear: 2025,
            startMonth: 7, currency: "EUR", isActive: true
        )
        let included = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let excluded = FinanceAccount(
            id: UUID(), name: "Außer Budget", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1, includeBudget: false
        )
        let parent = FinanceCategory(
            id: UUID(), parentID: nil, name: "Wohnen", kind: .expense,
            color: "#000000", isActive: true
        )
        let energy = FinanceCategory(
            id: UUID(), parentID: parent.id, name: "Energie", kind: .expense,
            color: "#000000", isActive: true
        )
        let salary = FinanceCategory(
            id: UUID(), parentID: nil, name: "Gehalt", kind: .income,
            color: "#000000", isActive: true
        )
        let july = calendar.date(from: DateComponents(year: 2025, month: 7, day: 10))!
        let august = calendar.date(from: DateComponents(year: 2025, month: 8, day: 10))!
        let expenseSplit = FinanceSplit(
            id: UUID(), categoryID: energy.id, amountMinor: -12_000,
            memo: "Strom", sortOrder: 0
        )
        func transaction(
            accountID: UUID, date: Date, amount: Int64,
            categoryID: UUID?, splits: [FinanceSplit] = []
        ) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: accountID, bookingDate: date,
                valueDate: nil, payee: "", purpose: "", categoryID: categoryID,
                amountMinor: amount, currency: "EUR", status: .booked,
                memo: "", reference: "", transferID: nil,
                importFingerprint: nil, splits: splits
            )
        }
        let lines = [
            BudgetLine(
                id: UUID(), budgetID: budget.id, categoryID: energy.id,
                year: 2025, month: 7, plannedMinor: 10_000,
                rolloverPositive: false, rolloverNegative: false
            ),
            BudgetLine(
                id: UUID(), budgetID: budget.id, categoryID: salary.id,
                year: 2025, month: 7, plannedMinor: 20_000,
                rolloverPositive: false, rolloverNegative: false
            ),
            BudgetLine(
                id: UUID(), budgetID: budget.id, categoryID: energy.id,
                year: 2025, month: 8, plannedMinor: 99_000,
                rolloverPositive: false, rolloverNegative: false
            )
        ]
        let snapshot = BudgetReportEngine.snapshot(
            budget: budget,
            query: BudgetReportQuery(monthKeys: ["2025-07"]),
            lines: lines,
            transactions: [
                transaction(accountID: included.id, date: july, amount: -12_000,
                            categoryID: nil, splits: [expenseSplit]),
                transaction(accountID: included.id, date: july, amount: 25_000,
                            categoryID: salary.id),
                transaction(accountID: excluded.id, date: july, amount: -50_000,
                            categoryID: energy.id),
                transaction(accountID: included.id, date: august, amount: -40_000,
                            categoryID: energy.id)
            ],
            accounts: [included, excluded], categories: [energy, salary, parent],
            tags: [], calendar: calendar
        )
        XCTAssertEqual(snapshot.includedMonths.map {
            BudgetReportEngine.monthKey($0, calendar: calendar)
        }, ["2025-07"])
        XCTAssertEqual(snapshot.rows.map(\.categoryPath), ["Wohnen › Energie", "Gehalt"])
        let energyRow = try XCTUnwrap(snapshot.rows.first { $0.categoryID == energy.id })
        XCTAssertEqual(energyRow.plannedMinor, 10_000)
        XCTAssertEqual(energyRow.actualMinor, 12_000)
        XCTAssertEqual(energyRow.varianceMinor, 2_000)
        XCTAssertEqual(energyRow.completionBasisPoints, 12_000)
        XCTAssertEqual(energyRow.factIDs.count, 1)
        let salaryRow = try XCTUnwrap(snapshot.rows.first { $0.categoryID == salary.id })
        XCTAssertEqual(salaryRow.plannedMinor, 20_000)
        XCTAssertEqual(salaryRow.actualMinor, 25_000)
        XCTAssertEqual(snapshot.plannedExpenseMinor, 10_000)
        XCTAssertEqual(snapshot.actualExpenseMinor, 12_000)
        XCTAssertEqual(snapshot.plannedIncomeMinor, 20_000)
        XCTAssertEqual(snapshot.actualIncomeMinor, 25_000)
    }

    func testBudgetPlanningRollsPositiveAndOptionallyNegativeBalances() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let budget = FinanceBudget(
            id: UUID(), name: "Roll-over 2025", startYear: 2025,
            startMonth: 1, currency: "EUR", isActive: true
        )
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let category = FinanceCategory(
            id: UUID(), parentID: nil, name: "Freizeit", kind: .expense,
            color: "#000000", isActive: true
        )
        func line(_ month: Int, negative: Bool) -> BudgetLine {
            BudgetLine(
                id: UUID(), budgetID: budget.id, categoryID: category.id,
                year: 2025, month: month, plannedMinor: 10_000,
                rolloverPositive: true, rolloverNegative: negative
            )
        }
        func transaction(_ month: Int, amount: Int64) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: account.id,
                bookingDate: calendar.date(from: DateComponents(
                    year: 2025, month: month, day: 10, hour: 12
                ))!,
                valueDate: nil, payee: "", purpose: "", categoryID: category.id,
                amountMinor: amount, currency: "EUR", status: .booked,
                memo: "", reference: "", transferID: nil,
                importFingerprint: nil, splits: []
            )
        }
        let transactions = [transaction(1, amount: -7_500), transaction(2, amount: -15_000)]
        let allBalances = BudgetPlanningEngine.snapshot(
            budget: budget,
            lines: [line(1, negative: true), line(2, negative: true), line(3, negative: true)],
            transactions: transactions, accounts: [account], categories: [category],
            tags: [], calendar: calendar
        )
        let january = try XCTUnwrap(allBalances.rows.first { $0.monthKey == "2025-01" })
        XCTAssertEqual(january.basePlannedMinor, 10_000)
        XCTAssertEqual(january.actualMinor, 7_500)
        XCTAssertEqual(january.balanceMinor, 2_500)
        XCTAssertEqual(january.rolloverOutMinor, 2_500)
        let february = try XCTUnwrap(allBalances.rows.first { $0.monthKey == "2025-02" })
        XCTAssertEqual(february.rolloverInMinor, 2_500)
        XCTAssertEqual(february.effectivePlannedMinor, 12_500)
        XCTAssertEqual(february.balanceMinor, -2_500)
        XCTAssertEqual(february.rolloverOutMinor, -2_500)
        let march = try XCTUnwrap(allBalances.rows.first { $0.monthKey == "2025-03" })
        XCTAssertEqual(march.rolloverInMinor, -2_500)
        XCTAssertEqual(march.effectivePlannedMinor, 7_500)
        XCTAssertEqual(allBalances.rolloverReserve(after: "2025-02"), -2_500)

        let positiveOnly = BudgetPlanningEngine.snapshot(
            budget: budget,
            lines: [line(1, negative: false), line(2, negative: false),
                    line(3, negative: false)],
            transactions: transactions, accounts: [account], categories: [category],
            tags: [], calendar: calendar
        )
        let positiveFebruary = try XCTUnwrap(
            positiveOnly.rows.first { $0.monthKey == "2025-02" }
        )
        XCTAssertEqual(positiveFebruary.balanceMinor, -2_500)
        XCTAssertEqual(positiveFebruary.rolloverOutMinor, 0)
        XCTAssertEqual(
            positiveOnly.rows.first { $0.monthKey == "2025-03" }?.rolloverInMinor, 0
        )

        let inheritedMode = BudgetPlanningEngine.snapshot(
            budget: budget, lines: [line(1, negative: false)],
            transactions: [transaction(1, amount: -7_500)],
            accounts: [account], categories: [category], tags: [], calendar: calendar
        )
        XCTAssertEqual(
            inheritedMode.rows.first { $0.monthKey == "2025-02" }?.rolloverInMinor, 2_500
        )
        XCTAssertEqual(
            inheritedMode.rows.first { $0.monthKey == "2025-03" }?.rolloverInMinor, 2_500,
            "Eine Kategorie-Roll-over-Einstellung gilt vorwärts, auch ohne leere Monatszeilen."
        )
        XCTAssertEqual(
            inheritedMode.rows.first { $0.monthKey == "2025-03" }?.rolloverMode,
            .positiveOnly
        )

        let februaryReport = BudgetReportEngine.snapshot(
            budget: budget, query: BudgetReportQuery(monthKeys: ["2025-02"]),
            lines: [line(1, negative: true), line(2, negative: true), line(3, negative: true)],
            transactions: transactions, accounts: [account], categories: [category],
            tags: [], calendar: calendar
        )
        let reportRow = try XCTUnwrap(februaryReport.rows.first)
        XCTAssertEqual(reportRow.plannedMinor, 10_000)
        XCTAssertEqual(reportRow.rolloverMinor, 2_500)
        XCTAssertEqual(reportRow.effectivePlannedMinor, 12_500)
        XCTAssertEqual(reportRow.actualMinor, 15_000)
        XCTAssertEqual(reportRow.varianceMinor, 2_500)
        XCTAssertEqual(februaryReport.rolloverReserveMinor, -2_500)
        let csv = ComparisonReportCSVExporter.budgetData(
            snapshot: februaryReport,
            metadata: ComparisonReportExportMetadata(
                title: "Budgettest", currentLabel: "Februar 2025",
                referenceLabel: "Plan gegenüber Ist",
                generatedAt: Date(timeIntervalSince1970: 0)
            )
        )
        let csvText = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(csvText.contains(
            "Freizeit;Ausgabe;100,00;25,00;125,00;150,00;25,00;120,00;EUR"
        ))
        XCTAssertTrue(csvText.contains("Roll-over-Reserve;;;;-25,00;;;;EUR"))
        let pdf = try ComparisonReportPDFExporter.budgetData(
            snapshot: februaryReport,
            metadata: ComparisonReportExportMetadata(
                title: "Budgettest", currentLabel: "Februar 2025",
                referenceLabel: "Plan gegenüber Ist",
                generatedAt: Date(timeIntervalSince1970: 0)
            ),
            orientation: .landscape
        )
        let pdfDocument = try XCTUnwrap(PDFDocument(data: pdf))
        let pdfText = (0..<pdfDocument.pageCount)
            .compactMap { pdfDocument.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(pdfText.contains("Budgettest"))
        XCTAssertTrue(pdfText.contains("Freizeit"))
        XCTAssertTrue(pdfText.contains("Roll-over-Reserve"))
        XCTAssertTrue(pdfText.contains("125,00 €"))
    }

    func testBudgetYearBatchDuplicateRenameAndDeleteAreAtomic() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let context = try TestDatabase()
        let category = try XCTUnwrap(
            context.store.categories().first { $0.name == "Lebensmittel" }
        )
        var source = FinanceBudget(
            id: UUID(), name: "Haushalt 2025/26", startYear: 2025,
            startMonth: 7, currency: "EUR", isActive: true
        )
        try context.store.saveBudget(source)
        let sourceMonths = source.months(calendar: calendar)
        let sourceLines = sourceMonths.enumerated().map { index, month -> BudgetLine in
            let components = calendar.dateComponents([.year, .month], from: month)
            return BudgetLine(
                id: UUID(), budgetID: source.id, categoryID: category.id,
                year: components.year!, month: components.month!,
                plannedMinor: Int64(index + 1) * 1_000,
                rolloverPositive: true, rolloverNegative: index.isMultiple(of: 2)
            )
        }
        try context.store.saveBudgetLines(sourceLines)
        XCTAssertEqual(try context.store.budgetLines(budgetID: source.id).count, 12)

        let duplicateLine = sourceLines[0]
        XCTAssertThrowsError(try context.store.saveBudgetLines([
            duplicateLine,
            BudgetLine(
                id: UUID(), budgetID: source.id, categoryID: category.id,
                year: duplicateLine.year, month: duplicateLine.month,
                plannedMinor: 99_999, rolloverPositive: false, rolloverNegative: false
            )
        ]))
        XCTAssertEqual(
            try context.store.budgetLines(
                budgetID: source.id, year: duplicateLine.year, month: duplicateLine.month
            ).first?.plannedMinor,
            1_000
        )

        source.name = "Haushalt – überarbeitet"
        try context.store.saveBudget(source)
        XCTAssertEqual(try context.store.budgets().first?.name, source.name)
        let conflicting = FinanceBudget(
            id: UUID(), name: source.name.uppercased(), startYear: 2026,
            startMonth: 1, currency: "EUR", isActive: true
        )
        XCTAssertThrowsError(try context.store.saveBudget(conflicting))
        XCTAssertEqual(try context.store.budgets().count, 1)

        let target = FinanceBudget(
            id: UUID(), name: "Haushalt 2026/27", startYear: 2026,
            startMonth: 10, currency: "EUR", isActive: true
        )
        try context.store.duplicateBudget(
            sourceID: source.id, target: target, calendar: calendar
        )
        let copied = try context.store.budgetLines(budgetID: target.id)
        XCTAssertEqual(copied.count, 12)
        XCTAssertEqual(copied.first?.year, 2026)
        XCTAssertEqual(copied.first?.month, 10)
        XCTAssertEqual(copied.first?.plannedMinor, 1_000)
        XCTAssertEqual(copied.last?.year, 2027)
        XCTAssertEqual(copied.last?.month, 9)
        XCTAssertEqual(copied.last?.plannedMinor, 12_000)
        XCTAssertTrue(Set(copied.map(\.id)).isDisjoint(with: Set(sourceLines.map(\.id))))
        XCTAssertThrowsError(try context.store.duplicateBudget(
            sourceID: source.id,
            target: FinanceBudget(
                id: UUID(), name: target.name, startYear: 2028,
                startMonth: 1, currency: "EUR", isActive: true
            ),
            calendar: calendar
        ))
        XCTAssertEqual(try context.store.budgets().count, 2)

        try context.store.deleteBudget(id: target.id)
        XCTAssertEqual(try context.store.budgets(), [source])
        XCTAssertTrue(try context.store.budgetLines(budgetID: target.id).isEmpty)
        XCTAssertEqual(try context.store.budgetLines(budgetID: source.id).count, 12)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testComparisonCSVAndPDFAreDeterministicAndMultipage() throws {
        let rows = (0..<80).map { index in
            PeriodComparisonRow(
                id: "row-\(index)", label: "Kategorie \(index)", currency: "EUR",
                currentMinor: 15_000 + Int64(index), referenceMinor: 10_000,
                differenceMinor: 5_000 + Int64(index), percentBasisPoints: 5_000,
                currentFactIDs: [], referenceFactIDs: []
            )
        }
        let snapshot = PeriodComparisonSnapshot(
            currentFrom: Date(timeIntervalSince1970: 1_738_368_000),
            currentThrough: Date(timeIntervalSince1970: 1_740_787_199),
            referenceFrom: Date(timeIntervalSince1970: 1_735_689_600),
            referenceThrough: Date(timeIntervalSince1970: 1_738_367_999),
            metric: .expense, rows: rows, currentFacts: [], referenceFacts: []
        )
        let metadata = ComparisonReportExportMetadata(
            title: "Zeitvergleich Ausgaben", currentLabel: "Februar 2025",
            referenceLabel: "Januar 2025", generatedAt: Date(timeIntervalSince1970: 0)
        )
        let csv = ComparisonReportCSVExporter.periodData(
            snapshot: snapshot, metadata: metadata
        )
        let text = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(text.contains("Kategorie 0;150,00;100,00;50,00;50,00;EUR"))
        XCTAssertTrue(text.contains("Gesamt;12031,60;8000,00;4031,60;50,40;EUR"))
        XCTAssertEqual(
            csv,
            ComparisonReportCSVExporter.periodData(snapshot: snapshot, metadata: metadata)
        )
        let pdf = try ComparisonReportPDFExporter.periodData(
            snapshot: snapshot, metadata: metadata, orientation: .landscape
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertGreaterThan(document.pageCount, 1)
        let pdfText = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(pdfText.contains("Zeitvergleich Ausgaben"))
        XCTAssertTrue(pdfText.contains("Kategorie 0"))
        XCTAssertTrue(pdfText.contains("Kategorie 79"))
        XCTAssertTrue(pdfText.contains("Gesamt"))
        XCTAssertTrue(pdfText.contains("Seite 1 von"))
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
            detail: "Interne Notiz",
            categoryID: nil,
            categoryPath: "Haushalt › Lebensmittel",
            tagIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000103")!],
            tagPaths: ["Immobilien › Objekt A"],
            status: .booked,
            flag: .purple,
            amountMinor: -123_456,
            currency: "EUR",
            isTransfer: false
        )
        var snapshot = TransactionReportSnapshot(
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
        snapshot.presentation.detailColumns = [
            .flag, .memo, .tags, .amount, .currency, .split
        ]
        let metadata = ReportExportMetadata(
            title: "Buchungsbericht",
            dateLabel: "Gesamter Zeitraum",
            filterSummary: "ohne Umbuchungen",
            baseCurrency: "EUR",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let data = try TransactionReportCSVExporter.data(
            snapshot: snapshot,
            metadata: metadata,
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
            "Buchungen und Splitpositionen",
            "Kennzeichen;Memo;Klasse/Tags;Betrag;Währung;Split",
            "Violett;Interne Notiz;Immobilien › Objekt A;-1234,56;EUR;Ja",
            "",
            "Gesamtsummen",
            "Währung;Einnahmen;Ausgaben;Saldo",
            "EUR;0,00;1234,56;-1234,56"
        ].joined(separator: "\r\n") + "\r\n"
        XCTAssertEqual(text, expected)

        let html = TransactionReportHTMLExporter.html(
            snapshot: snapshot, metadata: metadata
        )
        XCTAssertTrue(html.contains("<th>Kennzeichen</th>"))
        XCTAssertTrue(html.contains("Violett"))
        XCTAssertTrue(html.contains("Interne Notiz"))
        XCTAssertTrue(html.contains("Immobilien › Objekt A"))
        XCTAssertFalse(html.contains("<th>Datum</th>"))

        let clipboard = try TransactionReportClipboardExporter.payload(
            snapshot: snapshot, metadata: metadata
        )
        XCTAssertTrue(
            clipboard.plainText.contains(
                "Kennzeichen\tMemo\tKlasse/Tags\tBetrag\tWährung\tSplit"
            )
        )
        let clipboardHTML = try XCTUnwrap(
            String(data: clipboard.html, encoding: .utf8)
        )
        XCTAssertTrue(clipboardHTML.contains("Violett"))

        let pdf = try TransactionReportPDFExporter.data(
            snapshot: snapshot,
            metadata: metadata,
            options: ReportPDFOptions(orientation: .landscape)
        )
        let pdfText = try XCTUnwrap(PDFDocument(data: pdf)?.string)
        XCTAssertTrue(pdfText.contains("Kennzeichen"))
        XCTAssertTrue(pdfText.contains("Violett"))
        XCTAssertTrue(pdfText.contains("Interne Notiz"))
        XCTAssertFalse(pdfText.contains("Datum"))
    }

    func testReportHTMLExportIsDeterministicEscapedAndPresentationAware() throws {
        let fact = TransactionReportFact(
            id: "html-fact",
            transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            splitID: nil,
            bookingDate: Date(timeIntervalSince1970: 0),
            accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            accountName: "Giro <Privat>",
            payee: "Händler & Sohn",
            payeeID: nil,
            purpose: "</script><script>alert(\"x\")</script>",
            detail: "",
            categoryID: nil,
            categoryPath: "Wohnen › Miete",
            tagIDs: [],
            tagPaths: [],
            status: .booked,
            amountMinor: -123_456,
            currency: "EUR",
            isTransfer: false
        )
        let subtotal = TransactionReportGroup(
            id: "subtotal",
            label: "Summe Wohnen & Haus",
            currency: "EUR",
            incomeMinor: 0,
            expenseMinor: 123_456,
            netMinor: -123_456,
            factIDs: [fact.id],
            primaryLabel: "Wohnen & Haus",
            secondaryLabel: "",
            level: .subtotal
        )
        let snapshot = TransactionReportSnapshot(
            facts: [fact],
            groups: [subtotal],
            totals: [
                TransactionReportCurrencyTotal(
                    currency: "EUR",
                    incomeMinor: 0,
                    expenseMinor: 123_456,
                    netMinor: -123_456
                )
            ]
        )
        let metadata = ReportExportMetadata(
            title: "Miete <2025>",
            dateLabel: "Gesamter Zeitraum",
            filterSummary: "Empfänger & Kategorie",
            baseCurrency: "EUR",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let data = TransactionReportHTMLExporter.data(
            snapshot: snapshot,
            metadata: metadata
        )
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("Miete &lt;2025&gt;"))
        XCTAssertTrue(html.contains("Giro &lt;Privat&gt;"))
        XCTAssertTrue(html.contains("Händler &amp; Sohn"))
        XCTAssertTrue(html.contains("&lt;/script&gt;&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("class=\"subtotal\""))
        XCTAssertTrue(html.contains("Gesamtsummen"))
        XCTAssertTrue(html.contains("1234,56"))
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(
            digest,
            "c7334e518c0b3c9a93f84adf0f2496c3a7b85dfd9c1ffe2fa6b9064285606dd9"
        )

        var summaryOnly = snapshot
        summaryOnly.presentation = TransactionReportPresentation(
            includeDetailRows: false,
            includeSubtotals: true,
            includeGrandTotals: false
        )
        let summaryHTML = TransactionReportHTMLExporter.html(
            snapshot: summaryOnly,
            metadata: metadata
        )
        XCTAssertFalse(summaryHTML.contains("Buchungen und Splitpositionen"))
        XCTAssertFalse(summaryHTML.contains("Gesamtsummen"))
        XCTAssertTrue(summaryHTML.contains("Gruppenübersicht"))
    }

    func testReportXLSXExportIsValidDeterministicNumericAndEscaped() throws {
        let fact = TransactionReportFact(
            id: "xlsx-fact",
            transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            splitID: nil,
            bookingDate: Date(timeIntervalSince1970: 0),
            accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            accountName: "Giro <Privat>",
            payee: "=2+2 & Händler",
            payeeID: nil,
            purpose: "Zeile 1\u{0001} / \"Zeile 2\"",
            detail: "Interne Notiz",
            categoryID: nil,
            categoryPath: "Wohnen › Miete",
            tagIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000103")!],
            tagPaths: ["Immobilien › Objekt A"],
            status: .booked,
            flag: .purple,
            amountMinor: -123_456,
            currency: "EUR",
            isTransfer: false
        )
        var snapshot = TransactionReportSnapshot(
            facts: [fact],
            groups: [
                TransactionReportGroup(
                    id: "xlsx-subtotal",
                    label: "Summe Wohnen & Haus",
                    currency: "EUR",
                    incomeMinor: 0,
                    expenseMinor: 123_456,
                    netMinor: -123_456,
                    factIDs: [fact.id],
                    primaryLabel: "Wohnen & Haus",
                    secondaryLabel: "",
                    level: .subtotal
                )
            ],
            totals: [
                TransactionReportCurrencyTotal(
                    currency: "EUR",
                    incomeMinor: 0,
                    expenseMinor: 123_456,
                    netMinor: -123_456
                ),
                TransactionReportCurrencyTotal(
                    currency: "JPY",
                    incomeMinor: 5_000,
                    expenseMinor: 0,
                    netMinor: 5_000
                )
            ]
        )
        snapshot.presentation.detailColumns = [
            .flag, .memo, .tags, .amount, .currency, .split
        ]
        let metadata = ReportExportMetadata(
            title: "Miete <2025>",
            dateLabel: "Gesamter Zeitraum",
            filterSummary: "Empfänger & Kategorie",
            baseCurrency: "EUR",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let first = TransactionReportXLSXExporter.data(
            snapshot: snapshot,
            metadata: metadata
        )
        let second = TransactionReportXLSXExporter.data(
            snapshot: snapshot,
            metadata: metadata
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))

        let digest = SHA256.hash(data: first)
            .map { String(format: "%02x", $0) }
            .joined()
        if let outputPath = ProcessInfo.processInfo.environment[
            "FINANZVERWALTER_XLSX_QA_OUTPUT"
        ] {
            try first.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        XCTAssertEqual(
            digest,
            "ba7fc4929cbd835136c12932a6b332b438ba61cfc9ee1806be83e542acfa7c47"
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinanzVerwalter-XLSX-\(UUID().uuidString).xlsx")
        try first.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let testArchive = Process()
        testArchive.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        testArchive.arguments = ["-t", url.path]
        testArchive.standardOutput = Pipe()
        testArchive.standardError = Pipe()
        try testArchive.run()
        testArchive.waitUntilExit()
        XCTAssertEqual(testArchive.terminationStatus, 0)

        func archiveEntry(_ path: String) throws -> Data {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", url.path, path]
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            return data
        }

        let sheetData = try archiveEntry("xl/worksheets/sheet1.xml")
        _ = try XMLDocument(data: sheetData)
        let sheet = try XCTUnwrap(String(data: sheetData, encoding: .utf8))
        XCTAssertTrue(sheet.contains("Miete &lt;2025&gt;"))
        XCTAssertTrue(sheet.contains("Kennzeichen"))
        XCTAssertTrue(sheet.contains("Violett"))
        XCTAssertTrue(sheet.contains("Interne Notiz"))
        XCTAssertTrue(sheet.contains("Immobilien › Objekt A"))
        XCTAssertFalse(sheet.contains("Giro &lt;Privat&gt;"))
        XCTAssertFalse(sheet.contains("=2+2 &amp; Händler"))
        XCTAssertFalse(sheet.contains("\u{0001}"))
        XCTAssertFalse(sheet.contains("<f>"))
        XCTAssertTrue(sheet.contains("<v>-1234.56</v>"))
        XCTAssertTrue(sheet.contains("<v>5000</v>"))
        XCTAssertTrue(sheet.contains("s=\"12\"><v>1234.56</v>"))
        _ = try XMLDocument(data: archiveEntry("\\[Content_Types\\].xml"))
        _ = try XMLDocument(data: archiveEntry("xl/styles.xml"))

        let environment = ProcessInfo.processInfo.environment
        let executablePaths = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let configuredSoffice = environment["FINANZVERWALTER_SOFFICE_PATH"]
            .map { URL(fileURLWithPath: $0) }
        if let soffice = ([configuredSoffice].compactMap { $0 } + executablePaths
            .map({ URL(fileURLWithPath: $0).appendingPathComponent("soffice") }))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            let conversionDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("FinanzVerwalter-XLSX-Office-\(UUID().uuidString)")
            let profileDirectory = conversionDirectory.appendingPathComponent("profile")
            try FileManager.default.createDirectory(
                at: conversionDirectory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: conversionDirectory) }
            let office = Process()
            office.executableURL = soffice
            office.arguments = [
                "-env:UserInstallation=\(profileDirectory.absoluteString)",
                "--headless", "--convert-to", "csv", "--outdir",
                conversionDirectory.path, url.path
            ]
            office.standardOutput = Pipe()
            office.standardError = Pipe()
            try office.run()
            office.waitUntilExit()
            XCTAssertEqual(office.terminationStatus, 0)
            let converted = conversionDirectory
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("csv")
            let convertedText = try String(contentsOf: converted, encoding: .utf8)
            XCTAssertTrue(convertedText.contains("Miete <2025>"))
            XCTAssertTrue(
                convertedText.contains("-1234.56")
                    || convertedText.contains("-1234,56")
            )
        }
    }

    func testReportClipboardUsesMatchingTabularAndHTMLRepresentations() throws {
        let fact = TransactionReportFact(
            id: "clipboard-fact",
            transactionID: UUID(),
            splitID: nil,
            bookingDate: Date(timeIntervalSince1970: 0),
            accountID: UUID(),
            accountName: "Giro",
            payee: "Händler & Sohn",
            payeeID: nil,
            purpose: "Rechnung\tmit Tab",
            detail: "",
            categoryID: nil,
            categoryPath: "Haushalt › Lebensmittel",
            tagIDs: [],
            tagPaths: [],
            status: .booked,
            amountMinor: -1_234,
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
                    expenseMinor: 1_234,
                    netMinor: -1_234
                )
            ]
        )
        let metadata = ReportExportMetadata(
            title: "Kopierbericht",
            dateLabel: "Gesamter Zeitraum",
            filterSummary: "alle Konten",
            baseCurrency: "EUR",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let payload = try TransactionReportClipboardExporter.payload(
            snapshot: snapshot,
            metadata: metadata
        )
        XCTAssertTrue(payload.plainText.contains("Datum\tKonto\tEmpfänger"))
        XCTAssertTrue(payload.plainText.contains("\"Rechnung\tmit Tab\""))
        XCTAssertTrue(payload.plainText.contains("EUR\t0,00\t12,34\t-12,34"))
        let html = try XCTUnwrap(String(data: payload.html, encoding: .utf8))
        XCTAssertTrue(html.contains("Händler &amp; Sohn"))
        XCTAssertTrue(html.contains("12,34"))
        XCTAssertTrue(html.contains("Gesamtsummen"))
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
        XCTAssertTrue(text.contains("1.234,56"))
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
            visibleColumns: columns,
            sortColumnRawValue: RegisterColumn.category.rawValue,
            sortAscending: false,
            amountColumnModeRawValue: RegisterAmountColumnMode.debitCredit.rawValue
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
        XCTAssertEqual(restored.sortColumnRawValue, RegisterColumn.category.rawValue)
        XCTAssertEqual(restored.sortAscending, false)
        XCTAssertEqual(
            restored.amountColumnModeRawValue,
            RegisterAmountColumnMode.debitCredit.rawValue
        )
        XCTAssertNil(
            RegisterPreferencesCodec.decodeViews(oldViews).first?.sortColumnRawValue
        )
        XCTAssertNil(
            RegisterPreferencesCodec.decodeViews(oldViews).first?.sortAscending
        )
        XCTAssertNil(
            RegisterPreferencesCodec.decodeViews(oldViews).first?
                .amountColumnModeRawValue
        )
        XCTAssertTrue(
            RegisterPreferencesCodec.decodeViews("{nicht-json").isEmpty
        )
    }

    func testRegisterAmountColumnLayoutSeparatesDebitAndCreditLosslessly() {
        let visible: Set<RegisterColumn> = [.date, .amount, .balance]
        XCTAssertEqual(
            RegisterColumnLayout.columns(
                visible: visible,
                amountMode: .amount
            ),
            [.date, .amount, .balance]
        )
        XCTAssertEqual(
            RegisterColumnLayout.columns(
                visible: visible,
                amountMode: .debitCredit
            ),
            [.date, .debit, .credit, .balance]
        )
        XCTAssertEqual(
            RegisterColumnLayout.columns(
                visible: [.date, .balance],
                amountMode: .debitCredit
            ),
            [.date, .balance]
        )

        XCTAssertEqual(
            RegisterAmountPresentation.minorUnits(
                for: .amount,
                amountMinor: -12_345
            ),
            -12_345
        )
        XCTAssertEqual(
            RegisterAmountPresentation.minorUnits(
                for: .debit,
                amountMinor: -12_345
            ),
            12_345
        )
        XCTAssertNil(
            RegisterAmountPresentation.minorUnits(
                for: .credit,
                amountMinor: -12_345
            )
        )
        XCTAssertEqual(
            RegisterAmountPresentation.minorUnits(
                for: .credit,
                amountMinor: 12_345
            ),
            12_345
        )
        XCTAssertNil(
            RegisterAmountPresentation.minorUnits(
                for: .debit,
                amountMinor: 12_345
            )
        )
        XCTAssertNil(
            RegisterAmountPresentation.minorUnits(
                for: .debit,
                amountMinor: 0
            )
        )
        XCTAssertNil(
            RegisterAmountPresentation.minorUnits(
                for: .credit,
                amountMinor: 0
            )
        )
    }

    func testRegisterSorterUsesCompleteLabelsAmountsBalancesAndStableTies() throws {
        let accountID = UUID()
        func transaction(
            id: String,
            day: TimeInterval,
            payee: String,
            amount: Int64,
            status: TransactionStatus
        ) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(uuidString: id)!,
                accountID: accountID,
                bookingDate: Date(timeIntervalSince1970: day),
                valueDate: nil,
                payee: payee,
                purpose: "",
                categoryID: nil,
                amountMinor: amount,
                currency: "EUR",
                status: status,
                memo: "",
                reference: "",
                transferID: nil,
                importFingerprint: nil,
                splits: []
            )
        }
        let berlin = transaction(
            id: "00000000-0000-0000-0000-000000000001",
            day: 300,
            payee: "Ärztehaus 10",
            amount: -5_000,
            status: .booked
        )
        let hamburg = transaction(
            id: "00000000-0000-0000-0000-000000000002",
            day: 200,
            payee: "Ärztehaus 2",
            amount: -15_000,
            status: .cleared
        )
        let travel = transaction(
            id: "00000000-0000-0000-0000-000000000003",
            day: 100,
            payee: "Bahn",
            amount: 20_000,
            status: .pending
        )
        let secondBerlin = transaction(
            id: "00000000-0000-0000-0000-000000000004",
            day: 400,
            payee: "Ärztehaus 10",
            amount: -5_000,
            status: .booked
        )
        let values = [berlin, hamburg, travel, secondBerlin]
        let labels: [UUID: RegisterSortLabels] = [
            berlin.id: .init(
                account: "Giro", category: "Immobilien › Berlin › Grundsteuer",
                tags: "Steuer › Haus"
            ),
            hamburg.id: .init(
                account: "Giro", category: "Immobilien › Hamburg › Grundsteuer",
                tags: "Steuer › Haus"
            ),
            travel.id: .init(
                account: "Karte", category: "Reisen › Bahn", tags: "Urlaub"
            ),
            secondBerlin.id: .init(
                account: "Giro", category: "Immobilien › Berlin › Grundsteuer",
                tags: "Steuer › Haus"
            )
        ]
        let balances: [UUID: Int64] = [
            berlin.id: 10_000,
            hamburg.id: 5_000,
            travel.id: 25_000,
            secondBerlin.id: 30_000
        ]

        XCTAssertEqual(
            RegisterSorter.sorted(
                values, by: .category, ascending: true,
                runningBalances: balances, labels: labels
            ).map(\.id),
            [berlin.id, secondBerlin.id, hamburg.id, travel.id]
        )
        XCTAssertEqual(
            RegisterSorter.sorted(
                values, by: .payee, ascending: true,
                runningBalances: balances, labels: labels
            ).map(\.id),
            [hamburg.id, berlin.id, secondBerlin.id, travel.id]
        )
        XCTAssertEqual(
            RegisterSorter.sorted(
                values, by: .amount, ascending: false,
                runningBalances: balances, labels: labels
            ).map(\.id),
            [travel.id, berlin.id, secondBerlin.id, hamburg.id]
        )
        XCTAssertEqual(
            RegisterSorter.sorted(
                values, by: .balance, ascending: true,
                runningBalances: balances, labels: labels
            ).map(\.id),
            [hamburg.id, berlin.id, travel.id, secondBerlin.id]
        )
        XCTAssertEqual(
            RegisterSorter.sorted(
                values, by: .date, ascending: false,
                runningBalances: balances, labels: labels
            ).map(\.id),
            [secondBerlin.id, berlin.id, hamburg.id, travel.id]
        )
        XCTAssertEqual(
            RegisterSorter.sorted(
                values, by: .status, ascending: true,
                runningBalances: balances, labels: labels
            ).map(\.id),
            [travel.id, berlin.id, secondBerlin.id, hamburg.id]
        )
        for column in RegisterColumn.allCases {
            for ascending in [true, false] {
                let first = RegisterSorter.sorted(
                    values, by: column, ascending: ascending,
                    runningBalances: balances, labels: labels
                ).map(\.id)
                let second = RegisterSorter.sorted(
                    Array(values.reversed()), by: column, ascending: ascending,
                    runningBalances: balances, labels: labels
                ).map(\.id)
                let native = values.sorted(
                    using: RegisterTableComparator(
                        column: column,
                        order: ascending ? .forward : .reverse,
                        runningBalances: balances,
                        labels: labels
                    )
                ).map(\.id)
                XCTAssertEqual(
                    first, second,
                    "Instabile Sortierung für \(column.title)"
                )
                XCTAssertEqual(
                    native, first,
                    "Tabellenkopf weicht bei \(column.title) ab"
                )
                XCTAssertEqual(Set(first), Set(values.map(\.id)))
            }
        }
    }

    func testRegisterSortHeaderBindingAcceptsNativeColumnAndDirection() {
        let fallback = RegisterSortState(column: .date, ascending: false)
        var state = RegisterSortInteraction.state(
            from: [RegisterTableComparator(column: .category, order: .forward)],
            fallback: fallback
        )
        XCTAssertEqual(state, RegisterSortState(column: .category, ascending: true))

        state = RegisterSortInteraction.state(
            from: [RegisterTableComparator(column: .category, order: .reverse)],
            fallback: state
        )
        XCTAssertEqual(state, RegisterSortState(column: .category, ascending: false))

        state = RegisterSortInteraction.state(
            from: [RegisterTableComparator(column: .amount, order: .forward)],
            fallback: state
        )
        XCTAssertEqual(state, RegisterSortState(column: .amount, ascending: true))
        XCTAssertEqual(
            RegisterSortInteraction.state(from: [], fallback: state),
            state
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

    func testRegisterAccessibilityLabelsPreserveFullValuesAndSelection() {
        XCTAssertEqual(
            RegisterAccessibility.cellLabel(
                column: .category,
                value: "Immobilien:Berlin:Grundsteuer"
            ),
            "Kategorie: Immobilien:Berlin:Grundsteuer"
        )
        XCTAssertEqual(
            RegisterAccessibility.cellLabel(column: .balance, value: "1.234,56 €"),
            "Saldo: 1.234,56 €"
        )
        XCTAssertEqual(
            RegisterAccessibility.cellLabel(column: .purpose, value: "  \n"),
            "Verwendungszweck: Leer"
        )
        XCTAssertEqual(
            RegisterAccessibility.tableValue(visibleCount: 1, selectedCount: 0),
            "1 Buchung"
        )
        XCTAssertEqual(
            RegisterAccessibility.tableValue(visibleCount: 27, selectedCount: 3),
            "27 Buchungen, 3 ausgewählt"
        )
        let transaction = FinanceTransaction(
            id: UUID(), accountID: UUID(),
            bookingDate: Date(timeIntervalSince1970: 1_700_000_000),
            valueDate: nil, payee: "Stadt\tBerlin", purpose: "Grund\tsteuer",
            categoryID: nil, amountMinor: -1_234, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        XCTAssertEqual(
            RegisterClipboard.tsv(
                transaction: transaction,
                categoryPath: "Immobilien\tBerlin:Grundsteuer"
            ),
            "14.11.2023\tStadt Berlin\tGrund steuer\t"
                + "Immobilien Berlin:Grundsteuer\t-12,34\tEUR"
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

    func testRegisterCSVContainsExactlyVisibleColumnsAndEscapesDeterministically() throws {
        let snapshot = RegisterPrintSnapshot(
            title: "Kontoblatt – Girokonto",
            filterSummary: "Kategorie: Immobilie › Haus; Berlin",
            generatedAt: Date(timeIntervalSince1970: 0),
            columns: [.date, .payee, .category, .amount, .balance],
            rows: [[
                "01.07.2025",
                "Müller, \"Markt\"",
                "Immobilie › Haus\nGrundsteuer",
                "-12,34 EUR",
                "1.234,56 EUR"
            ]]
        )
        let first = try RegisterCSVExporter.data(snapshot: snapshot)
        let second = try RegisterCSVExporter.data(snapshot: snapshot)
        XCTAssertEqual(first, second)
        let text = try XCTUnwrap(String(data: first, encoding: .utf8))
        XCTAssertEqual(
            text,
            "Bericht;Kontoblatt – Girokonto\r\n"
                + "Filter;\"Kategorie: Immobilie › Haus; Berlin\"\r\n"
                + "Erstellt;01.01.1970 00:00\r\n\r\n"
                + "Datum;Empfänger;Kategorie;Betrag;Saldo\r\n"
                + "01.07.2025;\"Müller, \"\"Markt\"\"\";"
                + "\"Immobilie › Haus\nGrundsteuer\";-12,34 EUR;1.234,56 EUR\r\n"
        )
        XCTAssertFalse(text.contains("Verwendungszweck"))
        XCTAssertFalse(text.contains("Belegnummer"))
    }

    func testRegisterCSVSupportsSelectableDelimiterAndEncodingWithoutLoss() throws {
        var snapshot = RegisterPrintSnapshot(
            title: "Sammelkontoblatt",
            filterSummary: "Empfänger enthält Müller",
            generatedAt: Date(timeIntervalSince1970: 0),
            columns: [.payee, .amount],
            rows: [["Müller, Markt", "-12,34 EUR"]]
        )
        let commaData = try RegisterCSVExporter.data(
            snapshot: snapshot,
            format: .commaUTF8
        )
        let commaText = try XCTUnwrap(String(data: commaData, encoding: .utf8))
        XCTAssertTrue(commaText.contains("Empfänger,Betrag\r\n"))
        XCTAssertTrue(commaText.contains("\"Müller, Markt\",\"-12,34 EUR\"\r\n"))

        let windowsData = try RegisterCSVExporter.data(
            snapshot: snapshot,
            format: .semicolonWindows1252
        )
        XCTAssertEqual(
            String(data: windowsData, encoding: .windowsCP1252)?.contains("Müller"),
            true
        )
        snapshot.rows = [["Nicht darstellbar 🧾", "1,00 EUR"]]
        XCTAssertThrowsError(
            try RegisterCSVExporter.data(
                snapshot: snapshot,
                format: .semicolonWindows1252
            )
        )
    }

    func testRegisterQuickEntryEvaluatesPersistsAndRejectsClosedAccount() throws {
        let database = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let category = FinanceCategory(
            id: UUID(), parentID: nil, name: "Haushalt",
            kind: .expense, color: "#123456", isActive: true
        )
        try database.store.saveAccount(account)
        try database.store.saveCategory(category)
        let bookingDate = Date(timeIntervalSince1970: 1_754_044_800)
        let resolved = try RegisterQuickEntryDraft(
            accountID: account.id,
            bookingDate: bookingDate,
            payee: "  Stadtwerke  ",
            purpose: "  Abschlag August  ",
            categoryID: category.id,
            amountText: "=-(100 + 23,45)",
            status: .cleared
        ).resolved(accounts: [account])
        XCTAssertEqual(resolved.accountID, account.id)
        XCTAssertEqual(resolved.payee, "Stadtwerke")
        XCTAssertEqual(resolved.purpose, "Abschlag August")
        XCTAssertEqual(resolved.categoryID, category.id)
        XCTAssertEqual(resolved.money.minorUnits, -12_345)
        XCTAssertEqual(resolved.money.currency, "EUR")
        XCTAssertEqual(resolved.status, .cleared)
        XCTAssertTrue(Calendar.current.isDate(resolved.bookingDate, inSameDayAs: bookingDate))

        let transactionID = UUID()
        try database.store.saveTransaction(resolved.transaction(id: transactionID))
        let stored = try XCTUnwrap(
            database.store.transactions(accountID: account.id).first {
                $0.id == transactionID
            }
        )
        XCTAssertEqual(stored.payee, "Stadtwerke")
        XCTAssertEqual(stored.purpose, "Abschlag August")
        XCTAssertEqual(stored.categoryID, category.id)
        XCTAssertEqual(stored.amountMinor, -12_345)
        XCTAssertEqual(stored.status, .cleared)
        XCTAssertEqual(stored.valueDate, stored.bookingDate)
        XCTAssertTrue(stored.splits.isEmpty)
        XCTAssertNil(stored.transferID)
        XCTAssertNil(stored.importFingerprint)

        var closed = account
        closed.isClosed = true
        XCTAssertThrowsError(
            try RegisterQuickEntryDraft(
                accountID: closed.id,
                bookingDate: bookingDate,
                payee: "",
                purpose: "",
                categoryID: nil,
                amountText: "1,00"
            ).resolved(accounts: [closed])
        )
        XCTAssertThrowsError(
            try RegisterQuickEntryDraft(
                accountID: account.id,
                bookingDate: bookingDate,
                payee: "",
                purpose: "",
                categoryID: nil,
                amountText: "1 +"
            ).resolved(accounts: [account])
        )
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

    func testContextualShortcutsDoNotStealTableOrTextEditingKeys() {
        XCTAssertFalse(
            ContextualShortcutMonitor.shouldConsume(
                action: .accept,
                hasPresentedSheet: false,
                isTextEditing: false
            )
        )
        XCTAssertFalse(
            ContextualShortcutMonitor.shouldConsume(
                action: .cancel,
                hasPresentedSheet: false,
                isTextEditing: false
            )
        )
        XCTAssertTrue(
            ContextualShortcutMonitor.shouldConsume(
                action: .accept,
                hasPresentedSheet: true,
                isTextEditing: false
            )
        )
        XCTAssertFalse(
            ContextualShortcutMonitor.shouldConsume(
                action: .deleteSelection,
                hasPresentedSheet: false,
                isTextEditing: true
            )
        )
        XCTAssertTrue(
            ContextualShortcutMonitor.shouldConsume(
                action: .deleteSelection,
                hasPresentedSheet: false,
                isTextEditing: false
            )
        )
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
        let templateRate = try ExchangeRate.derived(
            originalMinor: -110_000,
            originalCurrency: "USD",
            bookedMinor: -100_000,
            bookedCurrency: "EUR"
        )
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
            ],
            originalAmountMinor: -110_000,
            originalCurrency: "USD",
            exchangeRateScaled: templateRate.scaledValue
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
        XCTAssertEqual(restored.originalAmountMinor, -110_000)
        XCTAssertEqual(restored.originalCurrency, "USD")
        XCTAssertEqual(restored.exchangeRateScaled, templateRate.scaledValue)
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
        XCTAssertEqual(draft.originalAmountMinor, -110_000)
        XCTAssertEqual(draft.originalCurrency, "USD")
        XCTAssertEqual(draft.exchangeRateScaled, templateRate.scaledValue)
        try draft.validate()

        try context.store.deleteTransactionTemplate(id: restored.id)
        XCTAssertTrue(try context.store.transactionTemplates().isEmpty)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testTransactionTemplatePartialApplicationUsageAndActivation() throws {
        let context = try TestDatabase()
        let sourceAccount = FinanceAccount(
            id: UUID(), name: "Vorlagenkonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let targetAccount = FinanceAccount(
            id: UUID(), name: "Aktuelles Konto", institution: "",
            type: .savings, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(sourceAccount)
        try context.store.saveAccount(targetAccount)
        let source = FinanceTransaction(
            id: UUID(), accountID: sourceAccount.id, bookingDate: .now,
            valueDate: .now, payee: "Stadtwerke", purpose: "Abschlag",
            categoryID: UUID(), amountMinor: -8_500, currency: "EUR",
            status: .pending, memo: "Nicht übernehmen", reference: "ALT",
            transferID: nil, importFingerprint: nil, splits: [],
            tagIDs: [UUID()], flag: .blue
        )
        let fields: Set<TransactionTemplateField> = [
            .payee, .purpose, .amount, .flag
        ]
        let template = TransactionTemplate(
            name: "Energie-Teilvorlage",
            transaction: source,
            includedFields: fields
        )
        try context.store.saveTransactionTemplate(template)

        var restored = try XCTUnwrap(context.store.transactionTemplates().first)
        XCTAssertEqual(restored.effectiveFields, fields)
        XCTAssertTrue(restored.isPartial)
        XCTAssertTrue(restored.effectiveIsActive)
        XCTAssertEqual(restored.effectiveUsageCount, 0)

        let draft = restored.appliedTransaction(
            on: Date(timeIntervalSince1970: 1_000),
            compatibleAccountID: targetAccount.id
        )
        XCTAssertEqual(draft.accountID, targetAccount.id)
        XCTAssertEqual(draft.payee, source.payee)
        XCTAssertEqual(draft.purpose, source.purpose)
        XCTAssertEqual(draft.amountMinor, source.amountMinor)
        XCTAssertEqual(draft.flag, .blue)
        XCTAssertNil(draft.categoryID)
        XCTAssertEqual(draft.status, .booked)
        XCTAssertEqual(draft.memo, "")
        XCTAssertTrue(draft.tagIDs.isEmpty)
        XCTAssertTrue(draft.splits.isEmpty)

        try context.store.recordTransactionTemplateUse(id: template.id)
        try context.store.recordTransactionTemplateUse(id: template.id)
        restored = try XCTUnwrap(context.store.transactionTemplates().first)
        XCTAssertEqual(restored.effectiveUsageCount, 2)
        XCTAssertNotNil(restored.lastUsedAt)

        try context.store.setTransactionTemplateActive(
            id: template.id,
            isActive: false
        )
        XCTAssertThrowsError(
            try context.store.recordTransactionTemplateUse(id: template.id)
        )
        restored = try XCTUnwrap(context.store.transactionTemplates().first)
        XCTAssertFalse(restored.effectiveIsActive)
        XCTAssertEqual(restored.effectiveUsageCount, 2)

        try context.store.setTransactionTemplateActive(
            id: template.id,
            isActive: true
        )
        try context.store.recordTransactionTemplateUse(id: template.id)
        restored = try XCTUnwrap(context.store.transactionTemplates().first)
        XCTAssertTrue(restored.effectiveIsActive)
        XCTAssertEqual(restored.effectiveUsageCount, 3)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testTransactionTemplateRejectsEmptyOrAmountDependentFieldSets() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Vorlagenkonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let source = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: .now, payee: "Quelle", purpose: "Test",
            categoryID: nil, amountMinor: -1_000, currency: "EUR",
            status: .booked, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: []
        )

        for fields in [
            Set<TransactionTemplateField>(),
            Set<TransactionTemplateField>([.splits]),
            Set<TransactionTemplateField>([.vat]),
            Set<TransactionTemplateField>([.foreignCurrency])
        ] {
            XCTAssertThrowsError(
                try context.store.saveTransactionTemplate(
                    TransactionTemplate(
                        name: "Ungültig",
                        transaction: source,
                        includedFields: fields
                    )
                )
            )
        }
        XCTAssertTrue(try context.store.transactionTemplates().isEmpty)
    }

    func testTransactionTemplateOrderingPrioritizesAccountUsageAndRecency() {
        let selectedAccountID = UUID()
        let otherAccountID = UUID()
        let transaction = FinanceTransaction(
            id: UUID(), accountID: otherAccountID, bookingDate: .now,
            valueDate: .now, payee: "", purpose: "",
            categoryID: nil, amountMinor: -1_000, currency: "EUR",
            status: .booked, memo: "", reference: "",
            transferID: nil, importFingerprint: nil, splits: []
        )
        var selectedRecent = TransactionTemplate(
            name: "Aktuelles Konto, neuer",
            transaction: transaction,
            usageCount: 2,
            lastUsedAt: Date(timeIntervalSince1970: 200)
        )
        selectedRecent.accountID = selectedAccountID
        var selectedOlder = TransactionTemplate(
            name: "Aktuelles Konto, älter",
            transaction: transaction,
            usageCount: 2,
            lastUsedAt: Date(timeIntervalSince1970: 100)
        )
        selectedOlder.accountID = selectedAccountID
        let frequentOther = TransactionTemplate(
            name: "Anderes Konto, häufig",
            transaction: transaction,
            usageCount: 50
        )
        let inactive = TransactionTemplate(
            name: "Inaktiv",
            transaction: transaction,
            isActive: false,
            usageCount: 100
        )

        let ordered = TransactionTemplateLibrary.orderedForUse(
            [frequentOther, inactive, selectedOlder, selectedRecent],
            selectedAccountID: selectedAccountID
        )
        XCTAssertEqual(
            ordered.map(\.id),
            [selectedRecent.id, selectedOlder.id, frequentOther.id]
        )
    }

    func testMigration40To41PreservesLegacyTemplatesAsActiveAndComplete() throws {
        let context = try TestDatabase()
        let url = context.store.fileURL
        let account = FinanceAccount(
            id: UUID(), name: "Altbestand", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let source = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: .now, payee: "Alt-Empfänger", purpose: "Alt-Zweck",
            categoryID: nil, amountMinor: -1_234, currency: "EUR",
            status: .booked, memo: "Alt-Notiz", reference: "",
            transferID: nil, importFingerprint: nil, splits: []
        )
        let template = TransactionTemplate(name: "Altvorlage", transaction: source)
        try context.store.saveTransactionTemplate(template)
        context.store.close()

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                """
                UPDATE transaction_templates
                SET payload_json=json_remove(
                    payload_json,'$.includedFields','$.isActive',
                    '$.usageCount','$.lastUsedAt'
                );
                DROP INDEX transaction_templates_active_usage;
                ALTER TABLE transaction_templates DROP COLUMN last_used_at;
                ALTER TABLE transaction_templates DROP COLUMN usage_count;
                ALTER TABLE transaction_templates DROP COLUMN is_active;
                PRAGMA user_version=40;
                """,
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        defer { migrated.close() }
        XCTAssertEqual(
            try sqliteScalar(url, "PRAGMA user_version"),
            Int64(SQLiteFinanceStore.currentSchemaVersion)
        )
        for column in ["is_active", "usage_count", "last_used_at"] {
            XCTAssertEqual(
                try sqliteScalar(
                    url,
                    "SELECT COUNT(*) FROM pragma_table_info('transaction_templates') WHERE name='\(column)'"
                ),
                1
            )
        }
        let restored = try XCTUnwrap(migrated.transactionTemplates().first)
        XCTAssertEqual(restored.id, template.id)
        XCTAssertEqual(
            restored.effectiveFields,
            Set(TransactionTemplateField.allCases)
        )
        XCTAssertTrue(restored.effectiveIsActive)
        XCTAssertEqual(restored.effectiveUsageCount, 0)
        XCTAssertNil(restored.lastUsedAt)
        XCTAssertTrue(try migrated.integrityCheck())
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

    func testGroupBankingLaunchSelectsOnlyMappedAccountsOnBestConnection() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let disabledID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let accounts = [UUID(), UUID(), UUID()]
        let connections = [
            BankingConnection(
                id: firstID, name: "Erste", providerKind: .simulator,
                adapterIdentifier: "sim.first", institutionName: "Bank A",
                status: .ready, consentValidUntil: nil, lastSyncAt: nil,
                lastUserMessage: "", isEnabled: true
            ),
            BankingConnection(
                id: secondID, name: "Zweite", providerKind: .simulator,
                adapterIdentifier: "sim.second", institutionName: "Bank B",
                status: .ready, consentValidUntil: nil, lastSyncAt: nil,
                lastUserMessage: "", isEnabled: true
            ),
            BankingConnection(
                id: disabledID, name: "Inaktiv", providerKind: .simulator,
                adapterIdentifier: "sim.disabled", institutionName: "Bank C",
                status: .inactive, consentValidUntil: nil, lastSyncAt: nil,
                lastUserMessage: "", isEnabled: false
            )
        ]
        let mappings = [
            BankingAccountMapping(
                id: UUID(), connectionID: firstID, externalAccountID: "first-a",
                remoteName: "A", remoteIBAN: "", currency: "EUR",
                localAccountID: accounts[0], isEnabled: true
            ),
            BankingAccountMapping(
                id: UUID(), connectionID: secondID, externalAccountID: "second-a",
                remoteName: "A", remoteIBAN: "", currency: "EUR",
                localAccountID: accounts[0], isEnabled: true
            ),
            BankingAccountMapping(
                id: UUID(), connectionID: secondID, externalAccountID: "second-b",
                remoteName: "B", remoteIBAN: "", currency: "EUR",
                localAccountID: accounts[1], isEnabled: true
            ),
            BankingAccountMapping(
                id: UUID(), connectionID: secondID, externalAccountID: "disabled-map",
                remoteName: "C", remoteIBAN: "", currency: "EUR",
                localAccountID: accounts[2], isEnabled: false
            ),
            BankingAccountMapping(
                id: UUID(), connectionID: disabledID, externalAccountID: "disabled-connection",
                remoteName: "C", remoteIBAN: "", currency: "EUR",
                localAccountID: accounts[2], isEnabled: true
            ),
            BankingAccountMapping(
                id: UUID(), connectionID: secondID, externalAccountID: "unrelated",
                remoteName: "Fremd", remoteIBAN: "", currency: "EUR",
                localAccountID: UUID(), isEnabled: true
            )
        ]

        let selection = try XCTUnwrap(
            BankingLaunchSelectionResolver.resolve(
                scope: .group(
                    id: UUID(), name: "Bankkonten",
                    accountIDs: Set(accounts)
                ),
                connections: connections,
                mappings: mappings
            )
        )

        XCTAssertEqual(selection.connectionID, secondID)
        XCTAssertEqual(selection.externalAccountIDs, ["second-a", "second-b"])
        XCTAssertEqual(selection.matchedLocalAccountIDs, Set(accounts.prefix(2)))
        XCTAssertEqual(selection.unmatchedLocalAccountIDs, [accounts[2]])
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

    func testRegisterSearchIndexCoversAllFieldsAcrossViewsAndStaysResponsive() throws {
        let account = FinanceAccount(
            id: UUID(), name: "Haushaltskonto", institution: "Musterbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let parentCategory = FinanceCategory(
            id: UUID(), parentID: nil, name: "Immobilie Köln",
            kind: .expense, color: "#336699", isActive: true
        )
        let category = FinanceCategory(
            id: UUID(), parentID: parentCategory.id, name: "Grundsteuer",
            kind: .expense, color: "#336699", isActive: true
        )
        let parentTag = FinanceTag(
            id: UUID(), parentID: nil, name: "Objekt", color: "#445566",
            description: "", isActive: true
        )
        let tag = FinanceTag(
            id: UUID(), parentID: parentTag.id, name: "Wohnung Süd",
            color: "#445566", description: "", isActive: true
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let bookingDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 8, day: 7))
        )
        let transaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: bookingDate,
            valueDate: bookingDate, payee: "Stadt Köln", purpose: "Bescheid 2025",
            categoryID: category.id, amountMinor: -123_456, currency: "EUR",
            status: .reconciled, memo: "Fälligkeit August", reference: "BELEG-4711",
            transferID: nil, importFingerprint: nil, splits: [], tagIDs: [tag.id],
            externalProvider: "FinTS Musterbank", externalTransactionID: "BANK-99",
            counterpartyIBAN: "DE02120300000000202051",
            endToEndID: "E2E-GRUNDA", mandateReference: "MANDAT-8",
            bankBalanceAfterMinor: 876_544, counterpartyBIC: "BYLADEM1001",
            creditorID: "DE98ZZZ09999999999", bookingText: "LASTSCHRIFT"
        )
        let index = RegisterSearchIndex.build(
            transactions: [transaction], accounts: [account],
            categories: [parentCategory, category], tags: [parentTag, tag],
            runningBalances: [transaction.id: 876_544]
        )
        let matchingQueries = [
            "Haushaltskonto Grundsteuer 1.234,56",
            "immobilie koln beleg 4711",
            "wohnung sud abgeglichen",
            "steuer 4711",
            "8.765,44 eur",
            "DE02120300000000202051 E2E-GRUNDA",
            "07.08.2025 lastschrift"
        ]
        for text in matchingQueries {
            XCTAssertTrue(
                index.matches(
                    transactionID: transaction.id,
                    query: RegisterSearchQuery(text)
                ),
                "Volltextabfrage sollte treffen: \(text)"
            )
        }
        XCTAssertFalse(index.matches(
            transactionID: transaction.id,
            query: RegisterSearchQuery("anderes konto gehalt")
        ))

        let secondary = RegisterSecondaryQuery.visible(
            transactions: [transaction], accountID: account.id, status: nil,
            category: .all, period: .all, customStart: .distantPast,
            customEnd: .distantFuture,
            searchText: "Haushaltskonto Wohnung Süd 1.234,56",
            searchMatches: { value, query in
                index.matchingTransactionIDs(query).contains(value.id)
            }
        ) { _ in "Immobilie Köln › Grundsteuer" }
        XCTAssertEqual(secondary.map(\.id), [transaction.id])

        let combined = CombinedRegisterQuery.evaluate(
            transactions: [transaction], forecastTransactions: [],
            allAccountIDs: [account.id], includedAccountIDs: [], status: nil,
            category: .all, period: .all, customStart: .distantPast,
            customEnd: .distantFuture,
            searchText: "Musterbank Grundsteuer BELEG-4711",
            includeForecast: false,
            searchMatches: { value, query in
                index.matchingTransactionIDs(query).contains(value.id)
            }
        ) { _ in "Immobilie Köln › Grundsteuer" }
        XCTAssertEqual(combined.rows.map(\.id), [transaction.id])
        XCTAssertTrue(combined.isFiltered)

        let document = try XCTUnwrap(index.documents[transaction.id])
        let decoy = RegisterSearchDocument(fields: [
            "Anderes Konto", "Unabhängige Buchung", "999,00 EUR"
        ])
        var performanceDocuments: [UUID: RegisterSearchDocument] = [:]
        performanceDocuments.reserveCapacity(100_000)
        for offset in 0..<100_000 {
            performanceDocuments[UUID()] = offset < 100 ? document : decoy
        }
        let performanceIndex = RegisterSearchIndex(
            documents: performanceDocuments
        )
        let performanceQuery = RegisterSearchQuery(
            "E2E-GRUNDA Grundsteuer"
        )
        let startedAt = Date.timeIntervalSinceReferenceDate
        let matchCount = performanceIndex.matchingTransactionIDs(
            performanceQuery
        ).count
        let elapsed = Date.timeIntervalSinceReferenceDate - startedAt
        XCTAssertEqual(matchCount, 100)
        XCTAssertLessThan(
            elapsed,
            0.100,
            "100.000 vorindexierte Buchungen müssen in unter 100 ms reagieren"
        )
    }

    @MainActor
    func testReferenceRegisterDatasetIsDeterministicPersistentAndReportChecked() throws {
        let context = try TestDatabase()
        let appStore = FinanceAppStore(repository: context.store)
        let manifest = try appStore.seedReferenceRegisterDataset()
        let accounts = try context.store.accounts()
        let transactions = try context.store.transactions()

        XCTAssertEqual(manifest.accountCount, 12)
        XCTAssertEqual(accounts.count, manifest.accountCount)
        XCTAssertEqual(Set(accounts.compactMap(\.groupID)).count, 4)
        XCTAssertEqual(Set(accounts.map(\.currency)), manifest.currencies)
        XCTAssertEqual(transactions.count, manifest.transactionCount)
        XCTAssertEqual(
            try sqliteScalar(
                context.store.fileURL,
                "SELECT COUNT(*) FROM transaction_splits"
            ),
            Int64(manifest.splitRowCount)
        )
        XCTAssertEqual(
            try sqliteScalar(
                context.store.fileURL,
                "SELECT COUNT(DISTINCT transfer_id) FROM transactions "
                    + "WHERE transfer_id IS NOT NULL"
            ),
            Int64(manifest.transferCount)
        )
        XCTAssertEqual(transactions.map(\.bookingDate).min(), manifest.earliestBookingDate)
        XCTAssertEqual(transactions.map(\.bookingDate).max(), manifest.latestBookingDate)

        let snapshot = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(
                dateFrom: nil, dateThrough: nil,
                grouping: .category, sort: .amountDescending
            ),
            transactions: transactions, accounts: accounts,
            categories: try context.store.categories(), tags: []
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: snapshot.totals.map {
                ($0.currency, $0.netMinor)
            }),
            manifest.expectedReportNetByCurrency
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    @MainActor
    func testHundredThousandBookingReferencePerformanceTargets() throws {
        let explicitEnvironment = ProcessInfo.processInfo.environment[
            "RUN_LARGE_PERFORMANCE_TESTS"
        ] == "1"
        let explicitSentinel = FileManager.default.fileExists(
            atPath: "/tmp/finanzverwalter-run-large-performance-tests"
        )
        guard explicitEnvironment || explicitSentinel else {
            throw XCTSkip(
                "Großer 100.000-Buchungen-Lauf ist nur mit RUN_LARGE_PERFORMANCE_TESTS=1 aktiv."
            )
        }
        let context = try TestDatabase()
        let seedingStore = FinanceAppStore(repository: context.store)
        _ = try seedingStore.seedReferenceRegisterDataset()
        let accounts = try context.store.accounts()
        let categories = try context.store.categories()
        let expenseCategory = try XCTUnwrap(
            categories.first { $0.kind == .expense }
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 12, day: 31)
        ))
        var additions: [FinanceTransaction] = []
        additions.reserveCapacity(90_000)
        for offset in 0..<90_000 {
            let account = accounts[offset % accounts.count]
            let date = try XCTUnwrap(calendar.date(
                byAdding: .day, value: -(offset % 3_653), to: endDate
            ))
            additions.append(
                FinanceTransaction(
                    id: UUID(), accountID: account.id,
                    bookingDate: date, valueDate: date,
                    payee: "Lasttest \(offset % 1_000)",
                    purpose: "Zusätzliche Referenzbuchung \(offset + 1)",
                    categoryID: expenseCategory.id,
                    amountMinor: -Int64(100 + offset % 10_000),
                    currency: account.currency, status: .booked,
                    memo: "100.000-Buchungen-Test", reference: "LOAD-\(offset + 1)",
                    transferID: nil, importFingerprint: nil, splits: []
                )
            )
        }
        let importStartedAt = Date.timeIntervalSinceReferenceDate
        try context.store.seedReferenceTransactions(additions)
        let importElapsed = Date.timeIntervalSinceReferenceDate - importStartedAt
        XCTAssertLessThan(
            importElapsed, 30,
            "90.000 zusätzliche validierte Zeilen müssen unter 30 Sekunden persistieren"
        )

        let launchStartedAt = Date.timeIntervalSinceReferenceDate
        let reopenedRepository = try SQLiteFinanceStore(fileURL: context.store.fileURL)
        let loadedStore = FinanceAppStore(repository: reopenedRepository)
        let launchElapsed = Date.timeIntervalSinceReferenceDate - launchStartedAt
        let loadedTransactions = loadedStore.transactions
        let loadedAccounts = loadedStore.accounts
        let loadedCategories = loadedStore.categories
        let loadedTags = loadedStore.tags
        XCTAssertEqual(loadedTransactions.count, 100_000)
        XCTAssertLessThan(
            launchElapsed, 3,
            "Startkern bis vollständig geladener Store muss unter 3 Sekunden bleiben"
        )

        let registerStartedAt = Date.timeIntervalSinceReferenceDate
        let balances = CombinedRegisterQuery.runningBalances(
            accounts: loadedAccounts,
            transactions: loadedTransactions
        )
        let registerResult = CombinedRegisterQuery.evaluate(
            transactions: loadedTransactions, forecastTransactions: [],
            allAccountIDs: Set(loadedAccounts.map(\.id)),
            includedAccountIDs: [loadedAccounts[0].id], status: nil,
            category: .all, period: .all,
            customStart: .distantPast, customEnd: .distantFuture,
            searchText: "", includeForecast: false
        ) { _ in "" }
        let registerElapsed = Date.timeIntervalSinceReferenceDate - registerStartedAt
        XCTAssertFalse(balances.isEmpty)
        XCTAssertFalse(registerResult.rows.isEmpty)
        XCTAssertLessThan(
            registerElapsed, 0.5,
            "Kontenblattberechnung muss unter 500 ms bleiben"
        )

        let reportStartedAt = Date.timeIntervalSinceReferenceDate
        let report = TransactionReportEngine.snapshot(
            query: TransactionReportQuery(
                dateFrom: nil, dateThrough: nil,
                grouping: .category, sort: .amountDescending
            ),
            transactions: loadedTransactions,
            accounts: loadedAccounts,
            categories: loadedCategories, tags: loadedTags
        )
        let reportElapsed = Date.timeIntervalSinceReferenceDate - reportStartedAt
        XCTAssertFalse(report.facts.isEmpty)
        XCTAssertLessThan(
            reportElapsed, 2,
            "Standardbericht muss unter 2 Sekunden bleiben"
        )
        let measuredValues = String(
            format: "PERF_REFERENCE import=%.3fs launch=%.3fs register=%.3fs report=%.3fs",
            importElapsed, launchElapsed, registerElapsed, reportElapsed
        )
        XCTContext.runActivity(named: measuredValues) { _ in }
        XCTAssertTrue(try reopenedRepository.integrityCheck())
    }

    func testCombinedRegisterQueryForecastBalancesAndSavedViewRoundTrip() throws {
        let firstAccount = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 1_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let secondAccount = FinanceAccount(
            id: UUID(), name: "Dollar", institution: "", type: .cash,
            currency: "USD", openingBalanceMinor: 2_000,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        let categoryID = UUID()
        let tagID = UUID()
        let booked = FinanceTransaction(
            id: UUID(), accountID: firstAccount.id,
            bookingDate: Date(timeIntervalSince1970: 100), valueDate: nil,
            payee: "Miete", purpose: "Wohnung", categoryID: categoryID,
            amountMinor: -100, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: [], tagIDs: [tagID]
        )
        let cancelled = FinanceTransaction(
            id: UUID(), accountID: firstAccount.id,
            bookingDate: Date(timeIntervalSince1970: 200), valueDate: nil,
            payee: "Storno", purpose: "", categoryID: categoryID,
            amountMinor: -500, currency: "EUR", status: .cancelled,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let dollar = FinanceTransaction(
            id: UUID(), accountID: secondAccount.id,
            bookingDate: Date(timeIntervalSince1970: 300), valueDate: nil,
            payee: "Kunde", purpose: "Erstattung", categoryID: nil,
            amountMinor: 200, currency: "USD", status: .booked,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let forecast = FinanceTransaction(
            id: UUID(), accountID: firstAccount.id,
            bookingDate: Date(timeIntervalSince1970: 400), valueDate: nil,
            payee: "Miete", purpose: "Zukunft", categoryID: categoryID,
            amountMinor: -50, currency: "EUR", status: .expected,
            memo: "", reference: "SCHEDULED:test", transferID: nil,
            importFingerprint: nil, splits: [], origin: .scheduled
        )
        let allAccountIDs: Set<UUID> = [firstAccount.id, secondAccount.id]
        let result = CombinedRegisterQuery.evaluate(
            transactions: [booked, cancelled, dollar],
            forecastTransactions: [forecast],
            allAccountIDs: allAccountIDs,
            includedAccountIDs: [],
            status: nil,
            category: .all,
            period: .all,
            customStart: .distantPast,
            customEnd: .distantFuture,
            searchText: "",
            includeForecast: true
        ) { transaction in
            transaction.categoryID == categoryID ? "Wohnen › Miete" : ""
        }
        XCTAssertFalse(result.isFiltered)
        XCTAssertEqual(result.rows.map(\.id), [
            booked.id, cancelled.id, dollar.id, forecast.id
        ])
        XCTAssertEqual(result.totalsByCurrency["EUR"], -150)
        XCTAssertEqual(result.totalsByCurrency["USD"], 200)

        let filtered = CombinedRegisterQuery.evaluate(
            transactions: [booked, cancelled, dollar],
            forecastTransactions: [forecast],
            allAccountIDs: allAccountIDs,
            includedAccountIDs: [firstAccount.id],
            status: .booked,
            category: .category(categoryID),
            period: .all,
            customStart: .distantPast,
            customEnd: .distantFuture,
            searchText: "Wohnen",
            includeForecast: true
        ) { _ in "Wohnen › Miete" }
        XCTAssertTrue(filtered.isFiltered)
        XCTAssertEqual(filtered.rows.map(\.id), [booked.id])

        let tagFiltered = CombinedRegisterQuery.evaluate(
            transactions: [booked, cancelled, dollar],
            forecastTransactions: [forecast],
            allAccountIDs: allAccountIDs,
            includedAccountIDs: [],
            status: nil,
            category: .all,
            tagID: tagID,
            period: .all,
            customStart: .distantPast,
            customEnd: .distantFuture,
            searchText: "",
            includeForecast: true
        ) { _ in "" }
        XCTAssertTrue(tagFiltered.isFiltered)
        XCTAssertEqual(tagFiltered.rows.map(\.id), [booked.id])

        let balances = CombinedRegisterQuery.runningBalances(
            accounts: [firstAccount, secondAccount],
            transactions: [booked, cancelled, dollar, forecast]
        )
        XCTAssertEqual(balances[booked.id], 900)
        XCTAssertEqual(balances[cancelled.id], 900)
        XCTAssertEqual(balances[forecast.id], 850)
        XCTAssertEqual(balances[dollar.id], 2_200)

        let view = SavedCombinedRegisterView(
            id: UUID(), name: "Zukunft Miete",
            includedAccountIDs: [firstAccount.id],
            statusRawValue: TransactionStatus.expected.rawValue,
            categorySelection: .category(categoryID),
            tagID: tagID,
            periodRawValue: RegisterPeriodFilter.currentYear.rawValue,
            customStart: Date(timeIntervalSince1970: 10),
            customEnd: Date(timeIntervalSince1970: 20),
            includeForecast: true,
            rowModeRawValue: "twoLines",
            visibleColumns: [.date, .payee, .amount, .balance]
        )
        let encoded = try RegisterPreferencesCodec.encodeCombinedViews([view])
        XCTAssertEqual(
            RegisterPreferencesCodec.decodeCombinedViews(encoded),
            [view]
        )
        let legacyEncoded = encoded.replacingOccurrences(
            of: ",\"tagID\":\"\(tagID.uuidString)\"",
            with: ""
        )
        XCTAssertNil(
            RegisterPreferencesCodec.decodeCombinedViews(legacyEncoded).first?.tagID
        )
    }

    func testCombinedRegisterChartUsesTrueBalancesOrFilteredMovementsByDay() {
        let euroAccount = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 1_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let euroCash = FinanceAccount(
            id: UUID(), name: "Kasse", institution: "", type: .cash,
            currency: "EUR", openingBalanceMinor: 500,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        let dollarAccount = FinanceAccount(
            id: UUID(), name: "Dollar", institution: "", type: .cash,
            currency: "USD", openingBalanceMinor: 2_000,
            isHidden: false, isClosed: false, sortOrder: 2
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOne = Date(timeIntervalSince1970: 1_720_000_000)
        let dayTwo = calendar.date(byAdding: .day, value: 1, to: dayOne)!
        let dayThree = calendar.date(byAdding: .day, value: 2, to: dayOne)!
        func transaction(
            accountID: UUID,
            date: Date,
            amount: Int64,
            currency: String,
            status: TransactionStatus = .booked,
            transferID: UUID? = nil
        ) -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: accountID, bookingDate: date,
                valueDate: nil, payee: "Test", purpose: "", categoryID: nil,
                amountMinor: amount, currency: currency, status: status,
                memo: "", reference: "", transferID: transferID,
                importFingerprint: nil, splits: []
            )
        }
        let booked = transaction(
            accountID: euroAccount.id,
            date: dayOne,
            amount: -100,
            currency: "EUR"
        )
        let cancelled = transaction(
            accountID: euroAccount.id,
            date: dayOne.addingTimeInterval(60),
            amount: -500,
            currency: "EUR",
            status: .cancelled
        )
        let transferID = UUID()
        let transferOut = transaction(
            accountID: euroAccount.id,
            date: dayTwo,
            amount: -200,
            currency: "EUR",
            transferID: transferID
        )
        let transferIn = transaction(
            accountID: euroCash.id,
            date: dayTwo.addingTimeInterval(60),
            amount: 200,
            currency: "EUR",
            transferID: transferID
        )
        let dollar = transaction(
            accountID: dollarAccount.id,
            date: dayTwo,
            amount: 300,
            currency: "USD"
        )
        let forecast = transaction(
            accountID: euroAccount.id,
            date: dayThree,
            amount: -50,
            currency: "EUR",
            status: .expected
        )
        let rows = [
            forecast, transferIn, cancelled, dollar, booked, transferOut
        ]

        let balance = CombinedRegisterChartEngine.make(
            accounts: [euroAccount, euroCash, dollarAccount],
            rows: rows,
            isFiltered: false,
            calendar: calendar
        )
        XCTAssertEqual(balance.mode, .balance)
        XCTAssertEqual(balance.pointCount, 4)
        let euroBalance = balance.series.first { $0.currency == "EUR" }
        XCTAssertEqual(euroBalance?.points.map(\.valueMinor), [1_400, 1_400, 1_350])
        XCTAssertEqual(euroBalance?.points.first?.lastTransactionID, booked.id)
        XCTAssertEqual(euroBalance?.points.last?.lastTransactionID, forecast.id)
        XCTAssertEqual(
            balance.series.first { $0.currency == "USD" }?.points.map(\.valueMinor),
            [2_300]
        )

        let filtered = CombinedRegisterChartEngine.make(
            accounts: [euroAccount, euroCash, dollarAccount],
            rows: rows,
            isFiltered: true,
            calendar: calendar
        )
        XCTAssertEqual(filtered.mode, .filteredMovement)
        let euroMovement = filtered.series.first { $0.currency == "EUR" }
        XCTAssertEqual(euroMovement?.points.map(\.valueMinor), [-100, -150])
        XCTAssertEqual(euroMovement?.points.map(\.lastTransactionID), [
            booked.id, forecast.id
        ])
        XCTAssertEqual(
            filtered.series.first { $0.currency == "USD" }?.points.map(\.valueMinor),
            [300]
        )
        XCTAssertFalse(
            filtered.series.flatMap(\.points).contains {
                $0.lastTransactionID == cancelled.id
                    || $0.lastTransactionID == transferOut.id
                    || $0.lastTransactionID == transferIn.id
            }
        )
    }

    @MainActor
    func testDirectReportFiltersExactSelectionAndIncludesScheduledFuture() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Giro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let matching = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Müller GmbH", purpose: "Rechnung",
            categoryID: nil, amountMinor: -1_000, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let other = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Andere GmbH", purpose: "Rechnung",
            categoryID: nil, amountMinor: -2_000, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(matching)
        try context.store.saveTransaction(other)
        try context.store.saveScheduledTransaction(
            ScheduledTransaction(
                id: UUID(), name: "Müller Zukunft", accountID: account.id,
                payee: "muller gmbh", purpose: "Regelmäßig",
                categoryID: nil, amountMinor: -3_000, currency: "EUR",
                nextDueDate: Calendar.current.date(
                    byAdding: .day,
                    value: 2,
                    to: .now
                )!,
                endDate: nil, frequency: .monthly, action: .remind,
                reminderDays: 3, isActive: true
            )
        )
        let app = FinanceAppStore(repository: context.store)
        let payeeQuery = TransactionReportQuery(
            exactPayee: "MÜLLER GMBH",
            includeForecast: true
        )
        let payeeSnapshot = app.transactionReport(payeeQuery)
        XCTAssertTrue(
            payeeSnapshot.facts.contains { $0.transactionID == matching.id }
        )
        XCTAssertFalse(
            payeeSnapshot.facts.contains { $0.transactionID == other.id }
        )
        XCTAssertTrue(
            payeeSnapshot.facts.contains { $0.status == .expected }
        )

        let exactSelection = app.transactionReport(
            TransactionReportQuery(
                statuses: Set(TransactionStatus.allCases),
                transactionIDs: [other.id]
            )
        )
        XCTAssertEqual(Set(exactSelection.facts.map(\.transactionID)), [other.id])

        let encoded = try JSONEncoder().encode(TransactionReportQuery())
        let decoded = try JSONDecoder().decode(
            TransactionReportQuery.self,
            from: encoded
        )
        XCTAssertNil(decoded.transactionIDs)
        XCTAssertNil(decoded.exactPayee)
        XCTAssertNil(decoded.includeForecast)
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

    func testOFXXMLParsesMultipleAccountsAndCommitsAtomically() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <OFX>
          <BANKMSGSRSV1><STMTTRNRS><STMTRS>
            <CURDEF>EUR</CURDEF>
            <BANKACCTFROM><BANKID>10020030</BANKID><ACCTID>DE001234</ACCTID><ACCTTYPE>CHECKING</ACCTTYPE></BANKACCTFROM>
            <BANKTRANLIST>
              <STMTTRN><TRNTYPE>DEBIT</TRNTYPE><DTPOSTED>20250714120000.000[+1:CET]</DTPOSTED><DTUSER>20250715</DTUSER><TRNAMT>-12.34</TRNAMT><FITID>bank-1</FITID><NAME>Bäckerei</NAME><MEMO>Frühstück</MEMO><REFNUM>ref-1</REFNUM></STMTTRN>
            </BANKTRANLIST>
          </STMTRS></STMTTRNRS></BANKMSGSRSV1>
          <CREDITCARDMSGSRSV1><CCSTMTTRNRS><CCSTMTRS>
            <CURDEF>EUR</CURDEF><CCACCTFROM><ACCTID>99887766</ACCTID></CCACCTFROM>
            <BANKTRANLIST><STMTTRN><TRNTYPE>CREDIT</TRNTYPE><DTPOSTED>20250716</DTPOSTED><TRNAMT>50.00</TRNAMT><FITID>cc-1</FITID><NAME>Erstattung</NAME></STMTTRN></BANKTRANLIST>
          </CCSTMTRS></CCSTMTTRNRS></CREDITCARDMSGSRSV1>
        </OFX>
        """
        let package = try BankStatementImporter.parse(data: Data(xml.utf8), format: .ofx)
        XCTAssertEqual(package.accounts.count, 2)
        XCTAssertEqual(package.records.count, 2)
        XCTAssertTrue(package.rejectedRows.isEmpty)

        let context = try TestDatabase()
        let checking = FinanceAccount(
            id: UUID(), name: "Giro", institution: "Testbank", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        let card = FinanceAccount(
            id: UUID(), name: "Kreditkarte", institution: "Testbank", type: .creditCard,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(checking)
        try context.store.saveAccount(card)
        let bankSource = try XCTUnwrap(package.accounts.first { !$0.isCreditCard })
        let cardSource = try XCTUnwrap(package.accounts.first { $0.isCreditCard })
        let preview = try package.preview(
            mappings: [bankSource.id: checking.id, cardSource.id: card.id],
            localAccounts: [checking, card]
        )
        XCTAssertEqual(preview.rows.map(\.amountMinor).sorted(), [-1_234, 5_000])
        XCTAssertEqual(preview.rows.first { $0.externalTransactionID == "bank-1" }?.valueDate.map {
            Calendar(identifier: .gregorian).component(.day, from: $0)
        }, 15)
        XCTAssertEqual(preview.rows.first { $0.externalTransactionID == "bank-1" }?.reference, "ref-1")
        XCTAssertEqual(try context.store.commitImport(preview).importedCount, 2)
        XCTAssertThrowsError(try context.store.commitImport(preview)) { error in
            XCTAssertEqual(error as? FinanceError, .duplicateImport)
        }
        XCTAssertEqual(try context.store.transactions().count, 2)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testQFXSGMLAcceptsUnclosedLeafTagsAndRejectsBadRows() throws {
        let sgml = """
        OFXHEADER:100
        DATA:OFXSGML
        VERSION:102

        <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS>
        <CURDEF>EUR
        <BANKACCTFROM><BANKID>50050000<ACCTID>12345678<ACCTTYPE>SAVINGS</BANKACCTFROM>
        <BANKTRANLIST>
        <STMTTRN><TRNTYPE>INT<DTPOSTED>20250102000000<TRNAMT>1.255<FITID>sgml-1<NAME>Zins<MEMO>Jahreszins</STMTTRN>
        <STMTTRN><TRNTYPE>DEBIT<DTPOSTED>kaputt<TRNAMT>-4.00<FITID>sgml-2</STMTTRN>
        </BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
        """
        let package = try BankStatementImporter.parse(data: Data(sgml.utf8), format: .qfx)
        XCTAssertEqual(package.accounts.count, 1)
        XCTAssertEqual(package.records.count, 1)
        XCTAssertEqual(package.records.first?.amountMinor, 126)
        XCTAssertEqual(package.records.first?.externalID, "sgml-1")
        XCTAssertEqual(package.rejectedRows.count, 1)

        let local = FinanceAccount(
            id: UUID(), name: "Tagesgeld", institution: "", type: .savings,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        let preview = try package.preview(
            mappings: [package.accounts[0].id: local.id],
            localAccounts: [local]
        )
        XCTAssertEqual(preview.rows.first?.externalProvider, "QFX")
        XCTAssertEqual(preview.rejectedRows.count, 1)
    }

    func testBankStatementPreviewRequiresMappingsAndMatchingCurrency() throws {
        let xml = """
        <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><CURDEF>USD</CURDEF>
        <BANKACCTFROM><BANKID>1</BANKID><ACCTID>2</ACCTID><ACCTTYPE>CHECKING</ACCTTYPE></BANKACCTFROM>
        <BANKTRANLIST><STMTTRN><DTPOSTED>20250101</DTPOSTED><TRNAMT>10.00</TRNAMT><FITID>x</FITID></STMTTRN></BANKTRANLIST>
        </STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
        """
        let package = try BankStatementImporter.parse(data: Data(xml.utf8), format: .ofx)
        let euro = FinanceAccount(
            id: UUID(), name: "Euro", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        let unmapped = try package.preview(mappings: [:], localAccounts: [euro])
        XCTAssertTrue(unmapped.rows.isEmpty)
        XCTAssertEqual(unmapped.rejectedRows.count, 1)
        let mismatch = try package.preview(
            mappings: [package.accounts[0].id: euro.id],
            localAccounts: [euro]
        )
        XCTAssertTrue(mismatch.rows.isEmpty)
        XCTAssertTrue(mismatch.rejectedRows[0].contains("Währung USD"))
    }

    func testMT940ParsesMultipleStatementsAndStructured86Data() throws {
        let mt940 = """
        :20:START-1
        :25:10020030/12345678
        :28C:00001/001
        :60F:C250101EUR0,00
        :61:2501020103D12,34NTRFNONREF//BANK-1
        :86:105?20RECHNUNG 2025?21KUNDENNUMMER 7?30GENODEF1XXX?31DE021002003012345678?32MUSTER GMBH
        :62F:C250102EUR-12,34
        :20:START-2
        :25:50050000/87654321
        :28C:00002/001
        :60F:C250103EUR100,00
        :61:2501040104C50,00NMSCREFUND//BANK-2
        :86:105?20ERSTATTUNG?32VERSICHERUNG AG
        :62F:C250104EUR150,00
        """
        let package = try BankStatementImporter.parse(
            data: Data(mt940.utf8),
            format: .mt940
        )
        XCTAssertEqual(package.accounts.count, 2)
        XCTAssertEqual(package.records.count, 2)
        XCTAssertTrue(package.rejectedRows.isEmpty)
        let debit = try XCTUnwrap(package.records.first { $0.externalID == "BANK-1" })
        XCTAssertEqual(debit.amountMinor, -1_234)
        XCTAssertEqual(debit.name, "MUSTER GMBH")
        XCTAssertEqual(debit.counterpartyIBAN, "DE021002003012345678")
        XCTAssertEqual(debit.counterpartyBIC, "GENODEF1XXX")
        XCTAssertTrue(debit.memo.contains("RECHNUNG 2025"))
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.day, from: debit.bookingDate), 3)
        XCTAssertEqual(
            Calendar(identifier: .gregorian).component(.day, from: try XCTUnwrap(debit.valueDate)),
            2
        )
        XCTAssertEqual(package.records.first { $0.externalID == "BANK-2" }?.amountMinor, 5_000)
    }

    func testCamt053ParsesBatchDetailsAndBankIdentity() throws {
        let camt = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08">
          <BkToCstmrStmt><Stmt>
            <Id>STMT-1</Id>
            <Acct><Id><IBAN>DE021002003012345678</IBAN></Id><Ccy>EUR</Ccy><Svcr><FinInstnId><BICFI>TESTDEFFXXX</BICFI></FinInstnId></Svcr></Acct>
            <Ntry>
              <Amt Ccy="EUR">30.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts>
              <BookgDt><Dt>2025-07-20</Dt></BookgDt><ValDt><Dt>2025-07-21</Dt></ValDt>
              <BkTxCd><Prtry><Cd>SEPA-ÜBERWEISUNG</Cd></Prtry></BkTxCd>
              <NtryDtls>
                <TxDtls><Refs><AcctSvcrRef>svc-1</AcctSvcrRef><EndToEndId>e2e-1</EndToEndId><MndtId>mandat-1</MndtId></Refs><AmtDtls><TxAmt><Amt Ccy="EUR">10.00</Amt></TxAmt></AmtDtls><RltdPties><Cdtr><Nm>Empfänger Eins</Nm></Cdtr><CdtrAcct><Id><IBAN>DE11111111111111111111</IBAN></Id></CdtrAcct></RltdPties><RltdAgts><CdtrAgt><FinInstnId><BICFI>BICONE11</BICFI></FinInstnId></CdtrAgt></RltdAgts><RmtInf><Ustrd>Zweck eins</Ustrd></RmtInf></TxDtls>
                <TxDtls><Refs><AcctSvcrRef>svc-2</AcctSvcrRef><EndToEndId>e2e-2</EndToEndId></Refs><AmtDtls><TxAmt><Amt Ccy="EUR">20.00</Amt></TxAmt></AmtDtls><RltdPties><Cdtr><Nm>Empfänger Zwei</Nm></Cdtr></RltdPties><RmtInf><Ustrd>Zweck zwei</Ustrd></RmtInf></TxDtls>
              </NtryDtls>
            </Ntry>
          </Stmt></BkToCstmrStmt>
        </Document>
        """
        let package = try BankStatementImporter.parse(
            data: Data(camt.utf8),
            format: .camt
        )
        XCTAssertEqual(package.accounts.count, 1)
        XCTAssertEqual(package.accounts[0].bankID, "TESTDEFFXXX")
        XCTAssertEqual(package.records.count, 2)
        XCTAssertEqual(package.records.map(\.amountMinor).sorted(), [-2_000, -1_000])
        let first = try XCTUnwrap(package.records.first { $0.externalID == "svc-1" })
        XCTAssertEqual(first.name, "Empfänger Eins")
        XCTAssertEqual(first.endToEndID, "e2e-1")
        XCTAssertEqual(first.mandateReference, "mandat-1")
        XCTAssertEqual(first.counterpartyIBAN, "DE11111111111111111111")
        XCTAssertEqual(first.counterpartyBIC, "BICONE11")
        XCTAssertEqual(
            Calendar(identifier: .gregorian).component(.day, from: try XCTUnwrap(first.valueDate)),
            21
        )

        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "camt-Giro", institution: "Testbank", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let preview = try package.preview(
            mappings: [package.accounts[0].id: account.id],
            localAccounts: [account]
        )
        XCTAssertEqual(preview.rows.count, 2)
        XCTAssertEqual(preview.rows.first { $0.externalTransactionID == "svc-1" }?.endToEndID, "e2e-1")
        XCTAssertEqual(try context.store.commitImport(preview).importedCount, 2)
        XCTAssertThrowsError(try context.store.commitImport(preview)) { error in
            XCTAssertEqual(error as? FinanceError, .duplicateImport)
        }
        XCTAssertEqual(try context.store.transactions().count, 2)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testCamtRejectsExternalEntitiesAndMalformedEntriesWithoutPartialCommit() throws {
        let externalEntity = """
        <?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
        <Document><BkToCstmrStmt><Stmt><Acct><Id><IBAN>DE00</IBAN></Id><Ccy>EUR</Ccy></Acct>
        <Ntry><Amt Ccy="EUR">1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2025-01-01</Dt></BookgDt><AddtlNtryInf>&xxe;</AddtlNtryInf></Ntry>
        </Stmt></BkToCstmrStmt></Document>
        """
        XCTAssertThrowsError(
            try BankStatementImporter.parse(data: Data(externalEntity.utf8), format: .camt)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Sicherheitsgründen"))
            XCTAssertFalse(error.localizedDescription.contains("root:"))
        }

        let malformed = """
        <?xml version="1.0"?>
        <Document><BkToCstmrStmt><Stmt><Acct><Id><IBAN>DE00</IBAN></Id><Ccy>EUR</Ccy></Acct>
        <Ntry><Amt Ccy="EUR">1.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>kaputt</Dt></BookgDt></Ntry>
        </Stmt></BkToCstmrStmt></Document>
        """
        let package = try BankStatementImporter.parse(
            data: Data(malformed.utf8),
            format: .camt
        )
        XCTAssertTrue(package.records.isEmpty)
        XCTAssertEqual(package.rejectedRows.count, 1)
        XCTAssertFalse(package.rejectedRows[0].contains("root:"))
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

    func testTransactionUndoRestoresCompleteEditAndThenUndoesCreation() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Undo-Konto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let category = FinanceCategory(
            id: UUID(), parentID: nil, name: "Undo-Kategorie",
            kind: .expense, color: "blue", isActive: true
        )
        try context.store.saveCategory(category)
        let tag = FinanceTag(
            id: UUID(), parentID: nil, name: "Undo-Klasse", color: "green",
            description: "", isActive: true
        )
        try context.store.saveTag(tag)
        let transactionID = UUID()
        try context.store.saveTransaction(
            FinanceTransaction(
                id: transactionID, accountID: account.id,
                bookingDate: Date(timeIntervalSince1970: 1_700_000_000),
                valueDate: nil, payee: "Vorher", purpose: "Original",
                categoryID: nil, amountMinor: -1_000, currency: "EUR",
                status: .booked, memo: "Notiz", reference: "R-1",
                transferID: nil, importFingerprint: nil,
                splits: [
                    FinanceSplit(
                        id: UUID(), categoryID: category.id,
                        amountMinor: -1_000, memo: "Split vorher", sortOrder: 0,
                        tagIDs: [tag.id]
                    )
                ],
                tagIDs: [tag.id]
            )
        )
        let original = try XCTUnwrap(
            context.store.transactions().first { $0.id == transactionID }
        )
        XCTAssertEqual(try context.store.latestTransactionUndo()?.title, "Buchung erstellt")

        var edited = original
        edited.payee = "Nachher"
        edited.purpose = "Geändert"
        edited.amountMinor = -1_250
        edited.splits[0].amountMinor = -1_250
        edited.splits[0].memo = "Split nachher"
        try context.store.saveTransaction(edited)

        let editUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(editUndo.title, "Buchung bearbeitet")
        XCTAssertEqual(editUndo.transactionCount, 1)
        XCTAssertEqual(try context.store.undoTransactionMutation(id: editUndo.id), 1)
        XCTAssertEqual(
            try context.store.transactions().first { $0.id == transactionID },
            original
        )
        XCTAssertThrowsError(
            try context.store.undoTransactionMutation(id: editUndo.id)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("bereits verwendet"))
        }

        let creationUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(creationUndo.title, "Buchung erstellt")
        XCTAssertEqual(try context.store.undoTransactionMutation(id: creationUndo.id), 1)
        XCTAssertTrue(try context.store.transactions().isEmpty)
        XCTAssertNil(try context.store.latestTransactionUndo())
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testTransactionUndoRejectsStaleSnapshotWithoutPartialMutation() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Konfliktkonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        var value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "A", purpose: "Erstellt", categoryID: nil,
            amountMinor: -100, currency: "EUR", status: .booked, memo: "",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(value)
        value = try XCTUnwrap(context.store.transactions().first)
        value.purpose = "Erste Änderung"
        try context.store.saveTransaction(value)
        let staleUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        value = try XCTUnwrap(context.store.transactions().first)
        value.purpose = "Zweite Änderung"
        try context.store.saveTransaction(value)

        XCTAssertThrowsError(
            try context.store.undoTransactionMutation(id: staleUndo.id)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("vollständig abgebrochen"))
        }
        XCTAssertEqual(try context.store.transactions().first?.purpose, "Zweite Änderung")
        XCTAssertEqual(try context.store.latestTransactionUndo()?.title, "Buchung bearbeitet")
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testTransactionUndoRestoresDeletedTransferPairAtomically() throws {
        let context = try TestDatabase()
        let source = FinanceAccount(
            id: UUID(), name: "Quelle", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        let destination = FinanceAccount(
            id: UUID(), name: "Ziel", institution: "", type: .savings,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(source)
        try context.store.saveAccount(destination)
        try context.store.createTransfer(
            from: source, to: destination, amountMinor: 5_000,
            date: Date(timeIntervalSince1970: 1_700_000_000), purpose: "Umbuchung"
        )
        let pair = try context.store.transactions().sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        XCTAssertEqual(pair.count, 2)
        try context.store.deleteTransaction(id: pair[0].id)
        XCTAssertTrue(try context.store.transactions().isEmpty)

        let deletionUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(deletionUndo.title, "2 Buchungen gelöscht")
        XCTAssertEqual(deletionUndo.transactionCount, 2)
        XCTAssertEqual(try context.store.undoTransactionMutation(id: deletionUndo.id), 2)
        XCTAssertEqual(
            try context.store.transactions().sorted { $0.id.uuidString < $1.id.uuidString },
            pair
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testTransactionUndoHandlesMoveAndBulkOrganization() throws {
        let context = try TestDatabase()
        let source = FinanceAccount(
            id: UUID(), name: "A", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        let destination = FinanceAccount(
            id: UUID(), name: "B", institution: "", type: .cash,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(source)
        try context.store.saveAccount(destination)
        let category = FinanceCategory(
            id: UUID(), parentID: nil, name: "Organisation",
            kind: .expense, color: "orange", isActive: true
        )
        try context.store.saveCategory(category)
        let value = FinanceTransaction(
            id: UUID(), accountID: source.id, bookingDate: .now,
            valueDate: nil, payee: "Test", purpose: "", categoryID: nil,
            amountMinor: -100, currency: "EUR", status: .booked, memo: "",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(value)
        try context.store.moveTransaction(id: value.id, toAccountID: destination.id)
        let moveUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(moveUndo.title, "Buchung verschoben")
        XCTAssertEqual(try context.store.undoTransactionMutation(id: moveUndo.id), 1)
        XCTAssertEqual(try context.store.transactions().first?.accountID, source.id)

        _ = try context.store.bulkUpdateTransactionCategory(
            ids: [value.id], categoryID: category.id
        )
        XCTAssertEqual(try context.store.transactions().first?.categoryID, category.id)
        let bulkUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(bulkUndo.title, "Buchung organisiert")
        XCTAssertEqual(try context.store.undoTransactionMutation(id: bulkUndo.id), 1)
        XCTAssertNil(try context.store.transactions().first?.categoryID)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testMigration30To31AddsPersistentTransactionUndoWithoutChangingBookings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-migration-30-31-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.qdata")
        let account = FinanceAccount(
            id: UUID(), name: "Schema-30-Konto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Bestand", purpose: "Unverändert",
            categoryID: nil, amountMinor: -321, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        var initial: SQLiteFinanceStore? = try SQLiteFinanceStore(fileURL: url)
        try initial?.saveAccount(account)
        try initial?.saveTransaction(value)
        initial?.close()
        initial = nil

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "DROP TABLE transaction_undo_runs; PRAGMA user_version=30;",
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try migrated.transactions().first?.id, value.id)
        XCTAssertEqual(try migrated.transactions().first?.amountMinor, -321)
        XCTAssertNil(try migrated.latestTransactionUndo())
        var edited = try XCTUnwrap(migrated.transactions().first)
        edited.purpose = "Nach Migration"
        try migrated.saveTransaction(edited)
        XCTAssertEqual(try migrated.latestTransactionUndo()?.title, "Buchung bearbeitet")
        XCTAssertTrue(try migrated.integrityCheck())
        migrated.close()

        XCTAssertEqual(
            sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil),
            SQLITE_OK
        )
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), Int32(SQLiteFinanceStore.currentSchemaVersion))
        sqlite3_finalize(statement)
        sqlite3_close(database)
    }

    func testAttachmentsDeduplicateVerifyPreviewAndCleanUpLastBlob() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Belegkonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let firstTransaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Lieferant A", purpose: "Rechnung",
            categoryID: nil, amountMinor: -1_234, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let secondTransaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Lieferant B", purpose: "Rechnung",
            categoryID: nil, amountMinor: -5_678, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(firstTransaction)
        try context.store.saveTransaction(secondTransaction)
        let payload = Data("%PDF-1.7\nFinanzVerwalter-Testbeleg\n%%EOF\n".utf8)
        let source = context.directory.appendingPathComponent("rechnung.pdf")
        try payload.write(to: source, options: .atomic)

        let first = try context.store.addAttachment(
            from: source, to: .transaction, entityID: firstTransaction.id
        )
        let repeated = try context.store.addAttachment(
            from: source, to: .transaction, entityID: firstTransaction.id
        )
        let second = try context.store.addAttachment(
            from: source, to: .transaction, entityID: secondTransaction.id
        )
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.sha256, SHA256.hash(data: payload).hexString)
        XCTAssertEqual(first.mimeType, "application/pdf")
        XCTAssertEqual(first.byteCount, Int64(payload.count))
        XCTAssertEqual(
            try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_blobs"),
            1
        )
        XCTAssertEqual(
            try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_links"),
            2
        )

        let backupURL = context.directory.appendingPathComponent("anhaenge.qbackup")
        try context.store.backup(to: backupURL)
        let backup = try SQLiteFinanceStore(fileURL: backupURL)
        XCTAssertEqual(
            try backup.attachments(
                entityType: .transaction, entityID: firstTransaction.id
            ).map(\.sha256),
            [first.sha256]
        )
        XCTAssertEqual(
            try backup.attachments(
                entityType: .transaction, entityID: secondTransaction.id
            ).map(\.sha256),
            [second.sha256]
        )
        XCTAssertTrue(try backup.integrityCheck())
        backup.close()

        let preview = try context.store.attachmentPreviewURL(id: first.id)
        defer { try? FileManager.default.removeItem(at: preview) }
        XCTAssertEqual(try Data(contentsOf: preview), payload)
        let permissions = try FileManager.default.attributesOfItem(atPath: preview.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try context.store.removeAttachment(id: first.id)
        XCTAssertEqual(
            try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_blobs"),
            1
        )
        try context.store.removeAttachment(id: second.id)
        XCTAssertEqual(
            try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_blobs"),
            0
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testAttachmentsRejectUnsafeInputsAndScannerFailureAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("finanzverwalter-attachment-reject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteFinanceStore(
            fileURL: directory.appendingPathComponent("test.qdata"),
            attachmentScanHook: { _, fileName in
                if fileName == "gesperrt.txt" {
                    throw FinanceError.database("Testscanner hat den Anhang gesperrt.")
                }
            }
        )
        defer { store.close() }
        let account = FinanceAccount(
            id: UUID(), name: "Prüfkonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try store.saveAccount(account)
        let value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Test", purpose: "", categoryID: nil,
            amountMinor: -1, currency: "EUR", status: .booked, memo: "",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try store.saveTransaction(value)

        let executable = directory.appendingPathComponent("schadcode.exe")
        try Data("MZ".utf8).write(to: executable)
        XCTAssertThrowsError(try store.addAttachment(from: executable, to: .transaction, entityID: value.id))
        let fakePDF = directory.appendingPathComponent("falsch.pdf")
        try Data("kein pdf".utf8).write(to: fakePDF)
        XCTAssertThrowsError(try store.addAttachment(from: fakePDF, to: .transaction, entityID: value.id))
        let blocked = directory.appendingPathComponent("gesperrt.txt")
        try Data("Scanner-Test".utf8).write(to: blocked)
        XCTAssertThrowsError(try store.addAttachment(from: blocked, to: .transaction, entityID: value.id))
        let link = directory.appendingPathComponent("verknuepfung.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: blocked)
        XCTAssertThrowsError(try store.addAttachment(from: link, to: .transaction, entityID: value.id))
        let oversized = directory.appendingPathComponent("zu-gross.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(50 * 1_024 * 1_024 + 1))
        try handle.close()
        XCTAssertThrowsError(try store.addAttachment(from: oversized, to: .transaction, entityID: value.id))
        XCTAssertThrowsError(try store.addAttachment(from: blocked, to: .transaction, entityID: UUID()))
        XCTAssertEqual(
            try sqliteScalar(store.fileURL, "SELECT COUNT(*) FROM attachment_blobs"),
            0
        )
        XCTAssertEqual(
            try sqliteScalar(store.fileURL, "SELECT COUNT(*) FROM attachment_links"),
            0
        )
        XCTAssertTrue(try store.integrityCheck())
    }

    func testAttachmentPreviewRejectsPayloadManipulation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("finanzverwalter-attachment-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("test.qdata")
        var store: SQLiteFinanceStore? = try SQLiteFinanceStore(fileURL: databaseURL)
        let account = FinanceAccount(
            id: UUID(), name: "Manipulationsprüfung", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try store?.saveAccount(account)
        let value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Test", purpose: "", categoryID: nil,
            amountMinor: -1, currency: "EUR", status: .booked, memo: "",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try store?.saveTransaction(value)
        let source = directory.appendingPathComponent("beleg.txt")
        try Data("unveränderter Beleg".utf8).write(to: source)
        let attachment = try XCTUnwrap(
            try store?.addAttachment(from: source, to: .transaction, entityID: value.id)
        )
        store?.close()
        store = nil

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(database, "UPDATE attachment_blobs SET payload=zeroblob(byte_count)", nil, nil, nil),
            SQLITE_OK
        )
        sqlite3_close(database)
        store = try SQLiteFinanceStore(fileURL: databaseURL)
        XCTAssertThrowsError(try store?.attachmentPreviewURL(id: attachment.id))
        let corruptExport = directory.appendingPathComponent("manipuliert.txt")
        XCTAssertThrowsError(
            try store?.exportAttachment(id: attachment.id, to: corruptExport)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptExport.path))
        store?.close()
    }

    func testMigration31To32AddsEmptyAttachmentStoreWithoutChangingBookings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("finanzverwalter-migration-31-32-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.qdata")
        let account = FinanceAccount(
            id: UUID(), name: "Schema-31-Konto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Bestand", purpose: "Bleibt erhalten",
            categoryID: nil, amountMinor: -987, currency: "EUR",
            status: .booked, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        var initial: SQLiteFinanceStore? = try SQLiteFinanceStore(fileURL: url)
        try initial?.saveAccount(account)
        try initial?.saveTransaction(value)
        initial?.close()
        initial = nil
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "DROP TABLE attachment_links; DROP TABLE attachment_blobs; PRAGMA user_version=31;",
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try migrated.transactions().first?.id, value.id)
        XCTAssertEqual(try migrated.transactions().first?.amountMinor, -987)
        XCTAssertEqual(try migrated.attachments(entityType: .transaction, entityID: value.id), [])
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertEqual(try sqliteScalar(url, "SELECT COUNT(*) FROM attachment_blobs"), 0)
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testTransactionUndoRemovesAttachmentsOfUndoneCreationAndRestoresDeletedBookingLink() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Undo-Belege", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let source = context.directory.appendingPathComponent("undo-beleg.txt")
        try Data("Undo-Beleg".utf8).write(to: source)

        let created = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Neu", purpose: "", categoryID: nil,
            amountMinor: -100, currency: "EUR", status: .booked, memo: "",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(created)
        _ = try context.store.addAttachment(
            from: source, to: .transaction, entityID: created.id
        )
        let creationUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(try context.store.undoTransactionMutation(id: creationUndo.id), 1)
        XCTAssertFalse(try context.store.transactions().contains { $0.id == created.id })
        XCTAssertEqual(try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_links"), 0)
        XCTAssertEqual(try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_blobs"), 0)

        let deleted = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Löschen", purpose: "", categoryID: nil,
            amountMinor: -200, currency: "EUR", status: .booked, memo: "",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(deleted)
        let attachment = try context.store.addAttachment(
            from: source, to: .transaction, entityID: deleted.id
        )
        try context.store.deleteTransactions(ids: Set([deleted.id]))
        XCTAssertFalse(try context.store.transactions().contains { $0.id == deleted.id })
        let deletionUndo = try XCTUnwrap(try context.store.latestTransactionUndo())
        XCTAssertEqual(try context.store.undoTransactionMutation(id: deletionUndo.id), 1)
        XCTAssertTrue(try context.store.transactions().contains { $0.id == deleted.id })
        XCTAssertEqual(
            try context.store.attachments(entityType: .transaction, entityID: deleted.id).map(\.id),
            [attachment.id]
        )
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testSameAttachmentBlobLinksToAccountContractSecurityAndInventory() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Dokumentkonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let security = Security(
            id: UUID(), name: "Dokumentwertpapier", shortName: "DOK",
            isin: "", wkn: "", ticker: "DOK", type: .stock,
            currency: "EUR", exchange: "Xetra", priceDecimals: 2,
            allowsShort: false, isActive: true, note: ""
        )
        let contract = FinanceContract(
            id: UUID(), provider: "Dokumentanbieter", contractNumber: "A-1",
            name: "Dokumentvertrag", type: .insurance, startDate: .now,
            initialTermMonths: 12, renewalMonths: 12,
            cancellationNoticeDays: 30, amountMinor: 1_000,
            frequency: .monthly, accountID: account.id, categoryID: nil,
            reminderDays: 14, note: "", isActive: true
        )
        let inventory = InventoryItem(
            id: UUID(), name: "Dokumentgegenstand", category: .electronics,
            room: "Büro", purchaseDate: .now, purchasePriceMinor: 10_000,
            currentValueMinor: 8_000, insuranceValueMinor: 10_000,
            retailer: "", serialNumber: "DOK-1", warrantyEnd: nil,
            note: "", isActive: true
        )
        try context.store.saveAccount(account)
        try context.store.saveSecurity(security)
        try context.store.saveContract(contract)
        try context.store.saveInventoryItem(inventory)
        let source = context.directory.appendingPathComponent("gemeinsam.txt")
        let payload = Data("Ein Original für vier Fachakten".utf8)
        try payload.write(to: source)

        let targets: [(AttachmentEntityType, UUID)] = [
            (.account, account.id),
            (.contract, contract.id),
            (.security, security.id),
            (.inventory, inventory.id)
        ]
        var linked: [FinanceAttachment] = []
        for (entityType, entityID) in targets {
            linked.append(
                try context.store.addAttachment(
                    from: source, to: entityType, entityID: entityID
                )
            )
            let values = try context.store.attachments(
                entityType: entityType, entityID: entityID
            )
            XCTAssertEqual(values.count, 1)
            XCTAssertEqual(values.first?.entityType, entityType)
            XCTAssertEqual(values.first?.entityID, entityID)
            XCTAssertEqual(values.first?.sha256, SHA256.hash(data: payload).hexString)
        }
        XCTAssertEqual(Set(linked.map(\.sha256)).count, 1)
        XCTAssertEqual(try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_blobs"), 1)
        XCTAssertEqual(try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_links"), 4)

        for attachment in linked {
            try context.store.removeAttachment(id: attachment.id)
        }
        XCTAssertEqual(try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_blobs"), 0)
        XCTAssertEqual(try sqliteScalar(context.store.fileURL, "SELECT COUNT(*) FROM attachment_links"), 0)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testAttachmentExportVerifiesPayloadProtectsTargetsAndUsesPrivatePermissions() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Exportkonto", institution: "",
            type: .checking, currency: "EUR", openingBalanceMinor: 0,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let value = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: .now,
            valueDate: nil, payee: "Export", purpose: "Beleg", categoryID: nil,
            amountMinor: -100, currency: "EUR", status: .booked, memo: "",
            reference: "", transferID: nil, importFingerprint: nil, splits: []
        )
        try context.store.saveTransaction(value)
        let payload = Data("Verifizierter Exportinhalt".utf8)
        let source = context.directory.appendingPathComponent("original.txt")
        try payload.write(to: source)
        let attachment = try context.store.addAttachment(
            from: source, to: .transaction, entityID: value.id
        )

        let destination = context.directory.appendingPathComponent("export.txt")
        XCTAssertEqual(
            try context.store.exportAttachment(id: attachment.id, to: destination),
            destination
        )
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: destination.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertThrowsError(
            try context.store.exportAttachment(id: attachment.id, to: destination)
        )
        try Data("wird ersetzt".utf8).write(to: destination, options: .atomic)
        XCTAssertNoThrow(
            try context.store.exportAttachment(
                id: attachment.id, to: destination, replaceExisting: true
            )
        )
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(
            try sqliteScalar(
                context.store.fileURL,
                "SELECT COUNT(*) FROM audit_events WHERE entity_type='attachment' AND action='export'"
            ),
            2
        )

        let wrongSuffix = context.directory.appendingPathComponent("export.pdf")
        XCTAssertThrowsError(
            try context.store.exportAttachment(id: attachment.id, to: wrongSuffix)
        )
        let symlinkTarget = context.directory.appendingPathComponent("ziel.txt")
        let symlink = context.directory.appendingPathComponent("link.txt")
        try Data("fremd".utf8).write(to: symlinkTarget)
        try FileManager.default.createSymbolicLink(
            at: symlink, withDestinationURL: symlinkTarget
        )
        XCTAssertThrowsError(
            try context.store.exportAttachment(
                id: attachment.id, to: symlink, replaceExisting: true
            )
        )
        XCTAssertEqual(try Data(contentsOf: symlinkTarget), Data("fremd".utf8))
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testFinanceCalendarLayoutCoversLeapMonthAndYearBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.locale = Locale(identifier: "de_DE")
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: year, month: month, day: day, hour: 12
            )))
        }

        let leapMonth = FinanceCalendarLayout.days(
            containing: try date(2024, 2, 15), mode: .month, calendar: calendar
        )
        XCTAssertEqual(leapMonth.count, 35)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(leapMonth.first).date),
            DateComponents(year: 2024, month: 1, day: 29)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(leapMonth.last).date),
            DateComponents(year: 2024, month: 3, day: 3)
        )
        XCTAssertEqual(leapMonth.filter(\.isInFocusedPeriod).count, 29)

        let yearWeek = FinanceCalendarLayout.days(
            containing: try date(2026, 1, 1), mode: .week, calendar: calendar
        )
        XCTAssertEqual(yearWeek.count, 7)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(yearWeek.first).date),
            DateComponents(year: 2025, month: 12, day: 29)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(yearWeek.last).date),
            DateComponents(year: 2026, month: 1, day: 4)
        )
        XCTAssertTrue(
            FinanceCalendarLayout.days(
                containing: try date(2026, 1, 1), mode: .list, calendar: calendar
            ).isEmpty
        )

        let shiftedMonth = FinanceCalendarLayout.shiftedFocus(
            from: try date(2025, 12, 31), mode: .month, offset: 1, calendar: calendar
        )
        XCTAssertEqual(calendar.component(.year, from: shiftedMonth), 2026)
        XCTAssertEqual(calendar.component(.month, from: shiftedMonth), 1)
        let shiftedWeek = FinanceCalendarLayout.shiftedFocus(
            from: try date(2025, 12, 29), mode: .week, offset: 1, calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: shiftedWeek),
            DateComponents(year: 2026, month: 1, day: 5)
        )
    }

    func testFinanceCalendarClassifiesAllTransactionStates() {
        XCTAssertEqual(
            FinanceCalendarEntryKind.classify(status: .expected, isRecurring: true),
            .recurring
        )
        XCTAssertEqual(
            FinanceCalendarEntryKind.classify(status: .expected, isRecurring: false),
            .expected
        )
        XCTAssertEqual(
            FinanceCalendarEntryKind.classify(status: .pending, isRecurring: false),
            .pending
        )
        for status in [TransactionStatus.booked, .cleared, .reconciled] {
            XCTAssertEqual(
                FinanceCalendarEntryKind.classify(status: status, isRecurring: false),
                .booked
            )
        }
        XCTAssertEqual(
            FinanceCalendarEntryKind.classify(status: .cancelled, isRecurring: false),
            .cancelled
        )
    }

    func testFinanceCalendarMoveValidatesExpectedTransactionsAndDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        func date(_ day: Int, hour: Int = 12) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 8, day: day, hour: hour
            )))
        }
        var transaction = FinanceTransaction(
            id: UUID(), accountID: UUID(), bookingDate: try date(10),
            valueDate: try date(10), payee: "Plan", purpose: "Prognose",
            categoryID: nil, amountMinor: -1_250, currency: "EUR",
            status: .expected, memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        )
        let moved = try FinanceCalendarMovePolicy.movedExpectedTransaction(
            transaction, to: try date(14), now: try date(7), calendar: calendar
        )
        XCTAssertEqual(moved.id, transaction.id)
        XCTAssertEqual(moved.bookingDate, try date(14, hour: 0))
        XCTAssertEqual(moved.valueDate, try date(14, hour: 0))

        transaction.valueDate = try date(11)
        let customValueDate = try FinanceCalendarMovePolicy.movedExpectedTransaction(
            transaction, to: try date(15), now: try date(7), calendar: calendar
        )
        XCTAssertEqual(customValueDate.valueDate, try date(11))

        transaction.status = .booked
        XCTAssertThrowsError(try FinanceCalendarMovePolicy.movedExpectedTransaction(
            transaction, to: try date(16), now: try date(7), calendar: calendar
        )) { XCTAssertEqual($0 as? FinanceCalendarMoveError, .unsupportedStatus) }
        transaction.status = .expected
        transaction.transferID = UUID()
        XCTAssertThrowsError(try FinanceCalendarMovePolicy.movedExpectedTransaction(
            transaction, to: try date(16), now: try date(7), calendar: calendar
        )) { XCTAssertEqual($0 as? FinanceCalendarMoveError, .linkedTransfer) }
        transaction.transferID = nil
        XCTAssertThrowsError(try FinanceCalendarMovePolicy.movedExpectedTransaction(
            transaction, to: try date(6), now: try date(7), calendar: calendar
        )) { XCTAssertEqual($0 as? FinanceCalendarMoveError, .pastDestination) }
        XCTAssertThrowsError(try FinanceCalendarMovePolicy.movedExpectedTransaction(
            transaction, to: try date(10), now: try date(7), calendar: calendar
        )) { XCTAssertEqual($0 as? FinanceCalendarMoveError, .sameDay) }
    }

    func testFinanceCalendarMoveCreatesStableRecurringException() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        func date(_ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 8, day: day, hour: 12
            )))
        }
        let scheduleID = UUID()
        let source = try date(10)
        let transaction = FinanceTransaction(
            id: UUID(), accountID: UUID(), bookingDate: source, valueDate: source,
            payee: "Miete", purpose: "August", categoryID: UUID(),
            amountMinor: -80_000, currency: "EUR", status: .expected, memo: "",
            reference: "schedule:\(scheduleID.uuidString):\(source.timeIntervalSince1970)",
            transferID: nil, importFingerprint: nil, splits: []
        )
        let created = try FinanceCalendarMovePolicy.movedRecurringException(
            for: transaction, existing: nil, to: try date(13),
            now: try date(7), calendar: calendar
        )
        XCTAssertEqual(created.scheduledTransactionID, scheduleID)
        XCTAssertEqual(created.originalDueDate, source)
        XCTAssertEqual(created.effectiveDate, calendar.startOfDay(for: try date(13)))
        XCTAssertEqual(created.disposition, .modified)
        XCTAssertEqual(created.payee, transaction.payee)
        XCTAssertEqual(created.amountMinor, transaction.amountMinor)

        let updated = try FinanceCalendarMovePolicy.movedRecurringException(
            for: transaction, existing: created, to: try date(14),
            now: try date(8), calendar: calendar
        )
        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.createdAt, created.createdAt)
        XCTAssertEqual(updated.note, created.note)
        XCTAssertEqual(updated.effectiveDate, calendar.startOfDay(for: try date(14)))

        var invalid = transaction
        invalid.reference = "manuell"
        XCTAssertThrowsError(try FinanceCalendarMovePolicy.movedRecurringException(
            for: invalid, existing: nil, to: try date(14),
            now: try date(7), calendar: calendar
        )) { XCTAssertEqual($0 as? FinanceCalendarMoveError, .invalidRecurringReference) }
    }

    func testLiquidityForecastCombinesOriginsIntervalsAndScenarioWithoutCurrencyMixing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        func date(_ year: Int = 2026, _ month: Int = 8, _ day: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
        }
        let account = FinanceAccount(
            id: UUID(), name: "Plan", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        func transaction(_ day: Int, _ amount: Int64, _ status: TransactionStatus) throws -> FinanceTransaction {
            FinanceTransaction(
                id: UUID(), accountID: account.id, bookingDate: try date(2026, 8, day),
                valueDate: nil, payee: status.title, purpose: "", categoryID: nil,
                amountMinor: amount, currency: "EUR", status: status, memo: "",
                reference: "", transferID: nil, importFingerprint: nil, splits: []
            )
        }
        let prior = try transaction(2, 500, .booked)
        let expected = try transaction(3, -3_000, .expected)
        let pending = try transaction(4, -1_000, .pending)
        let booked = try transaction(5, 2_000, .booked)
        var duplicateBooked = try transaction(5, -700, .booked)
        duplicateBooked.payee = "Doppelter Auftrag"
        var recurring = try transaction(6, -4_000, .expected)
        recurring.reference = "schedule:\(UUID().uuidString):\(recurring.bookingDate.timeIntervalSince1970)"
        let paymentDuplicate = PaymentOrder(
            id: UUID(), accountID: account.id, type: .scheduledCreditTransfer,
            recipientName: "Doppelter Auftrag", iban: "DE12500105170648489890", bic: "",
            amountMinor: 700, currency: "EUR", executionDate: try date(2026, 8, 5),
            purpose: "Test", endToEndID: "NOTPROVIDED", status: .accepted,
            idempotencyKey: "duplicate", bankReference: "", createdAt: Date(), updatedAt: Date()
        )
        let payment = PaymentOrder(
            id: UUID(), accountID: account.id, type: .scheduledCreditTransfer,
            recipientName: "Miete", iban: "DE12500105170648489890", bic: "",
            amountMinor: 900, currency: "EUR", executionDate: try date(2026, 8, 6),
            purpose: "Test", endToEndID: "NOTPROVIDED", status: .submitted,
            idempotencyKey: "payment", bankReference: "", createdAt: Date(), updatedAt: Date()
        )
        let standing = StandingOrder(
            id: UUID(), accountID: account.id, name: "Energie",
            recipientName: "Stadtwerke", iban: "DE12500105170648489890", bic: "",
            amountMinor: 800, currency: "EUR", purpose: "Abschlag",
            nextExecutionDate: try date(2026, 8, 8), endDate: nil,
            frequency: .monthly, businessDayAdjustment: .none, status: .active,
            createdAt: Date(), updatedAt: Date()
        )
        let scenario = ForecastScenarioEntry(
            id: UUID(), scenarioID: UUID(), accountID: account.id,
            date: try date(2026, 8, 7), name: "Reparatur", amountMinor: -6_000,
            isEnabled: true, note: "", createdAt: Date(), updatedAt: Date()
        )
        let buckets = LiquidityForecastEngine.buckets(
            accounts: [account],
            transactions: [prior, expected, pending, booked, duplicateBooked],
            paymentOrders: [paymentDuplicate, payment], standingOrders: [standing],
            recurring: [recurring], scenarioEntries: [scenario],
            accountIDs: [account.id], from: try date(2026, 8, 3),
            through: try date(2026, 8, 9), interval: .weekly, calendar: calendar
        )
        XCTAssertEqual(buckets.count, 1)
        let bucket = try XCTUnwrap(buckets.first)
        XCTAssertEqual(bucket.openingBalanceMinor, 10_500)
        XCTAssertEqual(bucket.changeMinor, -14_400)
        XCTAssertEqual(bucket.closingBalanceMinor, -3_900)
        XCTAssertEqual(bucket.minimumBalanceMinor, -3_900)
        XCTAssertEqual(bucket.maximumBalanceMinor, 10_500)
        XCTAssertEqual(
            Set(bucket.positions.map(\.origin)),
            [.expected, .pending, .booked, .paymentOrder, .standingOrder, .recurring, .scenario]
        )
        XCTAssertEqual(bucket.positions.filter { $0.title == "Doppelter Auftrag" }.count, 1)

        let monthly = LiquidityForecastEngine.buckets(
            accounts: [account], transactions: [], recurring: [], scenarioEntries: [],
            accountIDs: [account.id], from: try date(2026, 1, 30),
            through: try date(2026, 2, 3), interval: .monthly, calendar: calendar
        )
        XCTAssertEqual(monthly.count, 2)
        XCTAssertEqual(calendar.component(.day, from: monthly[0].endDate), 31)
        XCTAssertEqual(calendar.component(.day, from: monthly[1].startDate), 1)

        let usd = FinanceAccount(
            id: UUID(), name: "USD", institution: "", type: .checking,
            currency: "USD", openingBalanceMinor: 100, isHidden: false,
            isClosed: false, sortOrder: 1
        )
        XCTAssertTrue(LiquidityForecastEngine.buckets(
            accounts: [account, usd], transactions: [], recurring: [], scenarioEntries: [],
            accountIDs: [account.id, usd.id], from: try date(2026, 8, 3),
            through: try date(2026, 8, 9), interval: .daily, calendar: calendar
        ).isEmpty)
    }

    func testAccountClosureImpactCountsOnlyOpenItemsForSelectedAccount() throws {
        let accountID = UUID()
        let otherID = UUID()
        let now = Date()
        func schedule(_ id: UUID, active: Bool) -> ScheduledTransaction {
            ScheduledTransaction(
                id: UUID(), name: "Plan", accountID: id, payee: "Empfänger",
                purpose: "Zweck", categoryID: nil, amountMinor: -100,
                currency: "EUR", nextDueDate: now, endDate: nil,
                frequency: .monthly, action: .remind, reminderDays: 3,
                isActive: active
            )
        }
        func standing(_ id: UUID, status: StandingOrderStatus) -> StandingOrder {
            StandingOrder(
                id: UUID(), accountID: id, name: "Dauerauftrag",
                recipientName: "Empfänger", iban: "DE12500105170648489890",
                bic: "", amountMinor: 100, currency: "EUR", purpose: "Zweck",
                nextExecutionDate: now, endDate: nil, frequency: .monthly,
                businessDayAdjustment: .none, status: status,
                createdAt: now, updatedAt: now
            )
        }
        func payment(_ id: UUID, status: PaymentStatus) -> PaymentOrder {
            PaymentOrder(
                id: UUID(), accountID: id, type: .sepaCreditTransfer,
                recipientName: "Empfänger", iban: "DE12500105170648489890",
                bic: "", amountMinor: 100, currency: "EUR", executionDate: now,
                purpose: "Zweck", endToEndID: "NOTPROVIDED", status: status,
                idempotencyKey: UUID().uuidString, bankReference: "",
                createdAt: now, updatedAt: now
            )
        }
        let impact = AccountClosureImpact.evaluate(
            accountID: accountID,
            scheduledTransactions: [schedule(accountID, active: true), schedule(accountID, active: false), schedule(otherID, active: true)],
            standingOrders: [standing(accountID, status: .active), standing(accountID, status: .paused), standing(otherID, status: .active)],
            paymentOrders: [payment(accountID, status: .draft), payment(accountID, status: .submitted), payment(accountID, status: .accepted), payment(accountID, status: .rejected), payment(accountID, status: .cancelled), payment(otherID, status: .draft)]
        )
        XCTAssertEqual(impact.activeScheduledTransactions, 1)
        XCTAssertEqual(impact.activeStandingOrders, 1)
        XCTAssertEqual(impact.openPaymentOrders, 2)
        XCTAssertEqual(impact.openItemCount, 4)
    }

    @MainActor
    func testForecastScenarioPersistsUpdatesAuditsAndCascadesEntries() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Szenariokonto", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        let now = Date()
        var scenario = ForecastScenario(
            id: UUID(), name: "Umzug", note: "Test", isActive: true,
            createdAt: now, updatedAt: now
        )
        try context.store.saveForecastScenario(scenario)
        var entry = ForecastScenarioEntry(
            id: UUID(), scenarioID: scenario.id, accountID: account.id,
            date: now, name: "Kaution", amountMinor: -120_000,
            isEnabled: true, note: "einmalig", createdAt: now, updatedAt: now
        )
        try context.store.saveForecastScenarioEntry(entry)
        scenario.name = "Umzug Berlin"
        entry.amountMinor = -130_000
        try context.store.saveForecastScenario(scenario)
        try context.store.saveForecastScenarioEntry(entry)
        XCTAssertEqual(try context.store.forecastScenarios().first?.name, "Umzug Berlin")
        XCTAssertEqual(try context.store.forecastScenarioEntries().first?.amountMinor, -130_000)
        XCTAssertEqual(try sqliteScalar(context.store.fileURL, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertEqual(try sqliteScalar(
            context.store.fileURL,
            "SELECT COUNT(*) FROM audit_events WHERE entity_type IN ('forecast_scenario','forecast_scenario_entry') AND action='save'"
        ), 4)
        scenario.isActive = false
        try context.store.saveForecastScenario(scenario)
        let appStore = FinanceAppStore(repository: context.store)
        let inactiveBuckets = appStore.liquidityForecast(
            accountIDs: [account.id], scenarioID: scenario.id,
            from: Calendar.current.startOfDay(for: now),
            through: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now,
            interval: .daily
        )
        XCTAssertFalse(inactiveBuckets.flatMap(\.positions).contains { $0.origin == .scenario })
        try context.store.deleteForecastScenario(id: scenario.id)
        XCTAssertTrue(try context.store.forecastScenarios().isEmpty)
        XCTAssertTrue(try context.store.forecastScenarioEntries().isEmpty)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testMigration34To35AddsEmptyForecastScenariosWithoutChangingBookings() throws {
        let context = try TestDatabase()
        let url = context.store.fileURL
        let account = FinanceAccount(
            id: UUID(), name: "Bestand", institution: "", type: .checking,
            currency: "EUR", openingBalanceMinor: 1_000, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        context.store.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(
            database,
            "DROP TABLE forecast_scenario_entries; DROP TABLE forecast_scenarios; PRAGMA user_version=34;",
            nil, nil, nil
        ), SQLITE_OK)
        sqlite3_close(database)
        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try migrated.accounts().map(\.id), [account.id])
        XCTAssertTrue(try migrated.forecastScenarios().isEmpty)
        XCTAssertTrue(try migrated.forecastScenarioEntries().isEmpty)
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertTrue(try migrated.integrityCheck())
    }

    @MainActor
    func testTaxAllowancesPersistValidateLimitsUsageAccountsAuditAndReports() throws {
        let context = try TestDatabase()
        let bankA = FinanceAccount(
            id: UUID(), name: "Tagesgeld", institution: "Bank; A", type: .savings,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 0
        )
        let bankB = FinanceAccount(
            id: UUID(), name: "Depotkonto", institution: "Bank B", type: .investment,
            currency: "EUR", openingBalanceMinor: 0, isHidden: false,
            isClosed: false, sortOrder: 1
        )
        try context.store.saveAccount(bankA)
        try context.store.saveAccount(bankB)
        let person = TaxPerson(
            id: UUID(), displayName: "Ada Beispiel", taxIDLastFour: "1234",
            taxIDConfirmed: true, isActive: true
        )
        let partner = TaxPerson(
            id: UUID(), displayName: "Bert Beispiel", taxIDLastFour: "5678",
            taxIDConfirmed: true, isActive: true
        )
        try context.store.saveTaxPerson(person)
        try context.store.saveTaxPerson(partner)
        XCTAssertEqual(try context.store.taxAllowanceRules().count, 4)
        XCTAssertEqual(
            TaxAllowanceRuleEngine.rule(
                for: 2022, assessmentType: .individual,
                rules: try context.store.taxAllowanceRules()
            )?.allowanceMinor,
            80_100
        )
        XCTAssertEqual(
            TaxAllowanceRuleEngine.rule(
                for: 2026, assessmentType: .joint,
                rules: try context.store.taxAllowanceRules()
            )?.allowanceMinor,
            200_000
        )
        var first = TaxAllowanceOrder(
            id: UUID(), institution: "Bank; A", assessmentType: .individual,
            primaryPersonID: person.id, partnerPersonID: nil,
            allowanceMinor: 70_000, validFromYear: 2026, validThroughYear: nil,
            accountIDs: [bankA.id], note: "Hauptauftrag", isActive: true
        )
        try context.store.saveTaxAllowanceOrder(first)
        let second = TaxAllowanceOrder(
            id: UUID(), institution: "Bank B", assessmentType: .individual,
            primaryPersonID: person.id, partnerPersonID: nil,
            allowanceMinor: 30_000, validFromYear: 2026, validThroughYear: 2026,
            accountIDs: [bankB.id], note: "", isActive: true
        )
        try context.store.saveTaxAllowanceOrder(second)
        let usage = TaxAllowanceUsage(
            id: UUID(), orderID: first.id, taxYear: 2026, usedMinor: 25_000
        )
        try context.store.saveTaxAllowanceUsage(usage)
        XCTAssertThrowsError(try context.store.saveTaxAllowanceOrder(
            TaxAllowanceOrder(
                id: UUID(), institution: "Dritte Bank", assessmentType: .individual,
                primaryPersonID: person.id, partnerPersonID: nil,
                allowanceMinor: 1, validFromYear: 2026, validThroughYear: 2026,
                accountIDs: [], note: "", isActive: true
            )
        ))
        XCTAssertThrowsError(try context.store.saveTaxAllowanceOrder(
            TaxAllowanceOrder(
                id: UUID(), institution: "Bank; A", assessmentType: .individual,
                primaryPersonID: person.id, partnerPersonID: nil,
                allowanceMinor: 1_000, validFromYear: 2026, validThroughYear: 2026,
                accountIDs: [bankB.id], note: "falsches Institut", isActive: true
            )
        ))
        first.allowanceMinor = 20_000
        XCTAssertThrowsError(try context.store.saveTaxAllowanceOrder(first))
        XCTAssertThrowsError(try context.store.saveTaxAllowanceUsage(
            TaxAllowanceUsage(
                id: UUID(), orderID: first.id, taxYear: 2026, usedMinor: 70_001
            )
        ))
        let joint = TaxAllowanceOrder(
            id: UUID(), institution: "Gemeinschaftsbank", assessmentType: .joint,
            primaryPersonID: person.id, partnerPersonID: partner.id,
            allowanceMinor: 100_000, validFromYear: 2026, validThroughYear: nil,
            accountIDs: [], note: "Gemeinsam", isActive: true
        )
        try context.store.saveTaxAllowanceOrder(joint)
        XCTAssertThrowsError(try context.store.saveTaxAllowanceOrder(
            TaxAllowanceOrder(
                id: UUID(), institution: "Partnerbank", assessmentType: .individual,
                primaryPersonID: partner.id, partnerPersonID: nil,
                allowanceMinor: 1, validFromYear: 2026, validThroughYear: 2026,
                accountIDs: [], note: "würde gemeinsamen Rahmen überschreiten", isActive: true
            )
        ))
        let snapshot = TaxAllowanceRuleEngine.snapshot(
            query: TaxAllowanceReportQuery(taxYear: 2026),
            orders: try context.store.taxAllowanceOrders(),
            usages: try context.store.taxAllowanceUsages(),
            people: try context.store.taxPeople(), accounts: try context.store.accounts(),
            rules: try context.store.taxAllowanceRules()
        )
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.allocatedMinor, 200_000)
        XCTAssertEqual(snapshot.usedMinor, 25_000)
        XCTAssertEqual(snapshot.subjectTotals.count, 1)
        XCTAssertEqual(
            snapshot.subjectTotals.first?.remainingAllocationMinor,
            0
        )
        XCTAssertEqual(
            snapshot.rows.first { $0.id == first.id }?.accountNames,
            "Tagesgeld"
        )
        XCTAssertTrue(snapshot.rows.allSatisfy(\.taxIDComplete))
        let csv = try XCTUnwrap(String(
            data: TaxAllowanceReportCSVExporter.data(
                snapshot: snapshot, generatedAt: Date(timeIntervalSince1970: 0)
            ), encoding: .utf8
        ))
        XCTAssertTrue(csv.contains("\"Bank; A\""))
        XCTAssertTrue(csv.contains("250,00"))
        let pdf = try ComparisonReportPDFExporter.taxAllowanceData(
            snapshot: snapshot, generatedAt: Date(timeIntervalSince1970: 0)
        )
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let pdfText = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(pdfText.contains("Freistellungsaufträge"))
        XCTAssertTrue(pdfText.contains("Ada Beispiel"))
        XCTAssertEqual(try sqliteScalar(
            context.store.fileURL,
            "SELECT COUNT(*) FROM audit_events WHERE entity_type IN ('tax_person','tax_allowance_order','tax_allowance_usage')"
        ), 6)
        XCTAssertTrue(try context.store.integrityCheck())
    }

    func testMigration35To36AddsTaxAllowanceRulesWithoutChangingAccounts() throws {
        let context = try TestDatabase()
        let url = context.store.fileURL
        let account = FinanceAccount(
            id: UUID(), name: "Bestandskonto", institution: "Bank", type: .checking,
            currency: "EUR", openingBalanceMinor: 12_300,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try context.store.saveAccount(account)
        context.store.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(
            database,
            """
            DROP TABLE tax_allowance_usages;
            DROP TABLE tax_allowance_order_accounts;
            DROP TABLE tax_allowance_orders;
            DROP TABLE tax_allowance_rules;
            DROP TABLE tax_people;
            PRAGMA user_version=35;
            """,
            nil, nil, nil
        ), SQLITE_OK)
        sqlite3_close(database)
        let migrated = try SQLiteFinanceStore(fileURL: url)
        XCTAssertEqual(try migrated.accounts().map(\.id), [account.id])
        XCTAssertTrue(try migrated.taxPeople().isEmpty)
        XCTAssertTrue(try migrated.taxAllowanceOrders().isEmpty)
        XCTAssertTrue(try migrated.taxAllowanceUsages().isEmpty)
        XCTAssertEqual(try migrated.taxAllowanceRules().count, 4)
        XCTAssertEqual(try sqliteScalar(url, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertTrue(try migrated.integrityCheck())
    }

    func testSecureNoteLinksPermitOnlyConfirmedHTTPSAndSafeRegularLocalFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-note-links-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = directory.appendingPathComponent("Vertrag 2026.pdf")
        try Data("lokaler Testbeleg".utf8).write(to: document)
        let https = try XCTUnwrap(URL(string: "https://example.org/hilfe?privat=1"))
        let note = "Web \(https.absoluteString), Datei \(document.absoluteString), unsicher http://example.org und ftp://example.org/datei."

        let links = SecureNoteLinkPolicy.links(in: note)
        XCTAssertEqual(links.map(\.kind), [.https, .localFile])
        XCTAssertEqual(links.first?.displayName, "example.org/hilfe")
        XCTAssertEqual(links.last?.displayName, "Vertrag 2026.pdf")
        XCTAssertEqual(
            try SecureNoteLinkPolicy.validatedURLForOpening(https),
            https
        )
        XCTAssertEqual(
            try SecureNoteLinkPolicy.validatedURLForOpening(document),
            document.standardizedFileURL
        )
        XCTAssertThrowsError(
            try SecureNoteLinkPolicy.validatedURLForOpening(
                try XCTUnwrap(URL(string: "http://example.org"))
            )
        )
        XCTAssertThrowsError(
            try SecureNoteLinkPolicy.validatedURLForOpening(
                try XCTUnwrap(URL(string: "https://user:secret@example.org"))
            )
        )

        let executable = directory.appendingPathComponent("start.command")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path
        )
        XCTAssertThrowsError(
            try SecureNoteLinkPolicy.validatedURLForOpening(executable)
        )
        let symlink = directory.appendingPathComponent("verweis.pdf")
        try FileManager.default.createSymbolicLink(
            at: symlink, withDestinationURL: document
        )
        XCTAssertThrowsError(
            try SecureNoteLinkPolicy.validatedURLForOpening(symlink)
        )
        XCTAssertTrue(
            SecureNoteLinkPolicy.links(
                in: "Nur http://example.org und javascript:alert(1)"
            ).isEmpty
        )
    }

    @MainActor
    func testFinanceFilesCanBeCreatedSwitchedAndRemainStrictlyIsolated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-multiple-files-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "FinanzVerwalterTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let firstURL = directory.appendingPathComponent("Privat.qdata")
        let secondURL = directory.appendingPathComponent("Verein.qdata")
        let firstRepository = try SQLiteFinanceStore(fileURL: firstURL)
        let app = FinanceAppStore(
            repository: firstRepository,
            preferences: preferences
        )
        XCTAssertTrue(app.saveAccount(
            name: "Privatkonto", institution: "Hausbank",
            type: .checking, openingBalance: "100,00"
        ))

        XCTAssertTrue(app.createFinanceFile(at: secondURL, name: "Vereinskasse"))
        XCTAssertEqual(app.currentFinanceFileURL?.path, secondURL.path)
        XCTAssertEqual(app.fileInfo?.name, "Vereinskasse")
        XCTAssertTrue(app.accounts.isEmpty)
        XCTAssertTrue(app.saveAccount(
            name: "Vereinskonto", institution: "Genossenschaftsbank",
            type: .checking, openingBalance: "250,00"
        ))
        XCTAssertEqual(app.accounts.map(\.name), ["Vereinskonto"])

        XCTAssertTrue(app.openFinanceFile(at: firstURL))
        XCTAssertEqual(app.currentFinanceFileURL?.path, firstURL.path)
        XCTAssertEqual(app.accounts.map(\.name), ["Privatkonto"])
        XCTAssertEqual(
            FinanceFilePreferences.lastFileURL(from: preferences)?.path,
            firstURL.path
        )
        XCTAssertEqual(
            app.recentFinanceFileURLs.map(\.path),
            [firstURL.path, secondURL.path]
        )

        let secondRepository = try SQLiteFinanceStore(fileURL: secondURL)
        XCTAssertEqual(try secondRepository.accounts().map(\.name), ["Vereinskonto"])
        XCTAssertTrue(try secondRepository.integrityCheck())
        secondRepository.close()
        XCTAssertTrue(try XCTUnwrap(app.currentFinanceFileURL).path == firstURL.path)
        let backupDirectory = AutomaticBackupManager.defaultDirectory(for: secondURL)
        XCTAssertFalse(try AutomaticBackupManager.backups(in: backupDirectory).isEmpty)
    }

    @MainActor
    func testFinanceFileSwitchRejectsUnsafeOrInvalidTargetsWithoutLosingState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-file-switch-safety-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "FinanzVerwalterTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let originalURL = directory.appendingPathComponent("Original.qdata")
        let app = FinanceAppStore(
            repository: try SQLiteFinanceStore(fileURL: originalURL),
            preferences: preferences
        )
        XCTAssertTrue(app.saveAccount(
            name: "Bleibt erhalten", institution: "Bank",
            type: .checking, openingBalance: "42,00"
        ))

        let invalidURL = directory.appendingPathComponent("Defekt.qdata")
        try Data("keine SQLite-Datei".utf8).write(to: invalidURL)
        XCTAssertFalse(app.openFinanceFile(at: invalidURL))
        XCTAssertEqual(app.currentFinanceFileURL?.path, originalURL.path)
        XCTAssertEqual(app.accounts.map(\.name), ["Bleibt erhalten"])

        let symlinkURL = directory.appendingPathComponent("Verweis.qdata")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL, withDestinationURL: originalURL
        )
        XCTAssertFalse(app.openFinanceFile(at: symlinkURL))
        XCTAssertFalse(app.openFinanceFile(
            at: directory.appendingPathComponent("Original.sqlite")
        ))
        XCTAssertFalse(app.createFinanceFile(at: originalURL, name: "Doppelt"))
        XCTAssertFalse(app.createFinanceFile(
            at: directory.appendingPathComponent("Leer.qdata"), name: "\n"
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Leer.qdata").path
        ))
        XCTAssertEqual(app.currentFinanceFileURL?.path, originalURL.path)
        XCTAssertEqual(app.accounts.map(\.name), ["Bleibt erhalten"])
    }

    @MainActor
    func testFinanceFileCopyAndArchiveAreAtomicValidatedAndPermissioned() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-file-snapshots-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("Quelle.qdata")
        let repository = try SQLiteFinanceStore(fileURL: sourceURL)
        let account = FinanceAccount(
            id: UUID(), name: "Quellkonto", institution: "Bank", type: .checking,
            currency: "EUR", openingBalanceMinor: 12_345,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try repository.saveAccount(account)
        let app = FinanceAppStore(repository: repository)

        let copyURL = directory.appendingPathComponent("Geprüfte Kopie.qdata")
        let copy = try XCTUnwrap(app.createFinanceFileCopy(at: copyURL))
        XCTAssertEqual(copy.url.path, copyURL.path)
        XCTAssertGreaterThan(copy.byteCount, 0)
        XCTAssertEqual(copy.sha256.count, 64)
        XCTAssertEqual(
            copy,
            try FinanceFileSnapshotManager.snapshot(for: copyURL)
        )
        let copyAttributes = try FileManager.default.attributesOfItem(
            atPath: copyURL.path
        )
        let copyPermissions = try XCTUnwrap(
            copyAttributes[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(copyPermissions, 0o600)
        let copiedRepository = try SQLiteFinanceStore(fileURL: copyURL)
        XCTAssertEqual(try copiedRepository.accounts().map(\.id), [account.id])
        XCTAssertTrue(try copiedRepository.integrityCheck())
        copiedRepository.close()

        let archiveURL = directory.appendingPathComponent("Stand 2026.qarchive")
        let archive = try XCTUnwrap(app.archiveFinanceFile(at: archiveURL))
        XCTAssertEqual(archive.url.path, archiveURL.path)
        XCTAssertEqual(archive.sha256.count, 64)
        XCTAssertNoThrow(try SQLiteFinanceStore.validateBackup(at: archiveURL))
        let archiveAttributes = try FileManager.default.attributesOfItem(
            atPath: archiveURL.path
        )
        let archivePermissions = try XCTUnwrap(
            archiveAttributes[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(archivePermissions, 0o400)

        XCTAssertTrue(app.saveAccount(
            name: "Nach dem Archiv", institution: "Bank",
            type: .savings, openingBalance: "1,00"
        ))
        XCTAssertEqual(app.accounts.count, 2)
        XCTAssertTrue(app.restoreBackup(from: archiveURL))
        XCTAssertEqual(app.accounts.map(\.id), [account.id])
        XCTAssertEqual(app.currentFinanceFileURL?.path, sourceURL.path)
        app.checkIntegrity()
        XCTAssertEqual(app.statusText, "Datenbank-Integritätsprüfung: OK")

        XCTAssertNil(app.createFinanceFileCopy(at: copyURL))
        XCTAssertNil(app.createFinanceFileCopy(at: sourceURL))
        XCTAssertNil(app.archiveFinanceFile(
            at: directory.appendingPathComponent("Falsche Endung.qdata")
        ))
        let realDirectory = directory.appendingPathComponent("Echt", isDirectory: true)
        let linkedDirectory = directory.appendingPathComponent("Link", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realDirectory, withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedDirectory, withDestinationURL: realDirectory
        )
        XCTAssertNil(app.createFinanceFileCopy(
            at: linkedDirectory.appendingPathComponent("Unsicher.qdata")
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: realDirectory.appendingPathComponent("Unsicher.qdata").path
        ))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix(".finanzverwalter-") }
        )
        XCTAssertEqual(app.accounts.map(\.id), [account.id])
    }

    @MainActor
    func testRepairCopyRebuildsOnlyIndependentValidatedCopy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-repair-copy-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Quelle.qdata")
        let repository = try SQLiteFinanceStore(fileURL: sourceURL)
        let account = FinanceAccount(
            id: UUID(), name: "Reparaturtest", institution: "Bank",
            type: .checking, currency: "EUR", openingBalanceMinor: 10_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        try repository.saveAccount(account)
        let transaction = FinanceTransaction(
            id: UUID(), accountID: account.id, bookingDate: Date(timeIntervalSince1970: 1_767_225_600),
            valueDate: nil, payee: "Werkstatt", purpose: "Kopie warten",
            categoryID: nil, amountMinor: -1_234, currency: "EUR",
            status: .booked, memo: "Quelle bleibt offen", reference: "R-1",
            transferID: nil, importFingerprint: nil, splits: []
        )
        try repository.saveTransaction(transaction)
        let sourceSnapshotBefore = try FinanceFileSnapshotManager.snapshot(
            for: sourceURL
        )
        let sourceAccountsBefore = try repository.accounts()
        let sourceTransactionsBefore = try repository.transactions()
        let app = FinanceAppStore(repository: repository)

        let repairURL = directory.appendingPathComponent(
            "Quelle Reparaturkopie.qdata"
        )
        let repaired = try XCTUnwrap(app.createRepairCopy(at: repairURL))

        XCTAssertEqual(repaired.url.path, repairURL.path)
        XCTAssertEqual(
            repaired,
            try FinanceFileSnapshotManager.snapshot(for: repairURL)
        )
        XCTAssertEqual(
            try FinanceFileSnapshotManager.snapshot(for: sourceURL),
            sourceSnapshotBefore
        )
        XCTAssertEqual(try repository.accounts(), sourceAccountsBefore)
        XCTAssertEqual(try repository.transactions(), sourceTransactionsBefore)
        XCTAssertEqual(app.currentFinanceFileURL?.path, sourceURL.path)
        XCTAssertEqual(app.accounts.map(\.id), [account.id])
        XCTAssertTrue(app.statusText.contains("Reparaturkopie erstellt"))

        let attributes = try FileManager.default.attributesOfItem(
            atPath: repairURL.path
        )
        let permissions = try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(permissions, 0o600)
        XCTAssertNoThrow(try SQLiteFinanceStore.validateBackup(at: repairURL))
        XCTAssertEqual(
            try sqliteScalar(
                repairURL,
                "SELECT COUNT(*) FROM pragma_foreign_key_check"
            ),
            0
        )
        for suffix in ["-wal", "-shm", "-journal"] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: repairURL.path + suffix)
            )
        }

        let repairedStore = try SQLiteFinanceStore(fileURL: repairURL)
        XCTAssertEqual(try repairedStore.accounts().map(\.id), [account.id])
        XCTAssertEqual(
            try repairedStore.transactions().map(\.id), [transaction.id]
        )
        XCTAssertTrue(try repairedStore.integrityCheck())
        repairedStore.close()

        let repairedAfterOpening = try FinanceFileSnapshotManager.snapshot(
            for: repairURL
        )
        XCTAssertNil(app.createRepairCopy(at: repairURL))
        XCTAssertEqual(
            try FinanceFileSnapshotManager.snapshot(for: repairURL),
            repairedAfterOpening
        )
        XCTAssertNil(app.createRepairCopy(at: sourceURL))
        XCTAssertNil(app.createRepairCopy(
            at: directory.appendingPathComponent("Falsche Endung.qbackup")
        ))
        let occupiedURL = directory.appendingPathComponent("Belegt.qdata")
        let sentinel = Data("bestehende Datei bleibt erhalten".utf8)
        try sentinel.write(to: occupiedURL)
        XCTAssertThrowsError(try repository.repairCopy(to: occupiedURL))
        XCTAssertEqual(try Data(contentsOf: occupiedURL), sentinel)
        XCTAssertEqual(try repository.accounts(), sourceAccountsBefore)
        XCTAssertEqual(try repository.transactions(), sourceTransactionsBefore)
        XCTAssertTrue(try repository.integrityCheck())
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix(".finanzverwalter-") }
        )
    }

    func testOpenDataArchiveExportsEveryTableCSVAttachmentsAndSafeSettings() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Exportkonto", institution: "Testbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 12_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let category = FinanceCategory(
            id: UUID(), parentID: nil, name: "Exportkategorie",
            kind: .expense, color: "orange", isActive: true
        )
        let tag = FinanceTag(
            id: UUID(), parentID: nil, name: "Exportklasse", color: "blue",
            description: "Offener Export", isActive: true
        )
        try context.store.saveAccount(account)
        try context.store.saveCategory(category)
        try context.store.saveTag(tag)
        let split = FinanceSplit(
            id: UUID(), categoryID: category.id, amountMinor: -1_234,
            memo: "vollständig", sortOrder: 0, tagIDs: [tag.id]
        )
        let transaction = FinanceTransaction(
            id: UUID(), accountID: account.id,
            bookingDate: Date(timeIntervalSince1970: 1_767_225_600),
            valueDate: Date(timeIntervalSince1970: 1_767_312_000),
            payee: "Exportlieferant", purpose: "JSON, CSV und Anhang",
            categoryID: nil, amountMinor: -1_234, currency: "EUR",
            status: .booked, memo: "portable Daten", reference: "EXP-1",
            transferID: nil, importFingerprint: nil, splits: [split],
            tagIDs: [tag.id]
        )
        try context.store.saveTransaction(transaction)
        let attachmentPayload = Data(
            "%PDF-1.7\nOffener FinanzVerwalter Export\n%%EOF\n".utf8
        )
        let attachmentSource = context.directory.appendingPathComponent(
            "exportbeleg.pdf"
        )
        try attachmentPayload.write(to: attachmentSource)
        let attachment = try context.store.addAttachment(
            from: attachmentSource,
            to: .transaction,
            entityID: transaction.id
        )

        let suiteName = "FinanzVerwalterOpenExport.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("dark", forKey: "appearanceMode")
        defaults.set(false, forKey: AutomaticBackupPreferences.enabledKey)
        defaults.set("/privater/pfad/Finanzen.qdata", forKey: "lastFinanceFilePath")
        defaults.set("niemals-exportieren", forKey: "bankingAccessToken")
        let safeSettings = OpenDataExportPreferences.values(from: defaults)
        XCTAssertEqual(safeSettings["appearanceMode"], "dark")
        XCTAssertEqual(
            safeSettings[AutomaticBackupPreferences.enabledKey], "0"
        )
        XCTAssertNil(safeSettings["lastFinanceFilePath"])
        XCTAssertNil(safeSettings["bankingAccessToken"])

        let sourceBefore = try FinanceFileSnapshotManager.snapshot(
            for: context.store.fileURL
        )
        let fixedExportDate = Date(timeIntervalSince1970: 1_775_001_600)
        let firstURL = context.directory.appendingPathComponent(
            "Offener Export 1.finanzarchiv", isDirectory: true
        )
        let secondURL = context.directory.appendingPathComponent(
            "Offener Export 2.finanzarchiv", isDirectory: true
        )
        let first = try context.store.exportOpenDataArchive(
            to: firstURL,
            settings: safeSettings,
            exportedAt: fixedExportDate
        )
        let second = try context.store.exportOpenDataArchive(
            to: secondURL,
            settings: safeSettings,
            exportedAt: fixedExportDate
        )

        let expectedTableCount = Int(try sqliteScalar(
            context.store.fileURL,
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ))
        XCTAssertEqual(first.formatVersion, 1)
        XCTAssertEqual(first.tableCount, expectedTableCount)
        XCTAssertEqual(first.attachmentCount, 1)
        XCTAssertGreaterThan(first.rowCount, 0)
        XCTAssertEqual(
            first.fileCount,
            expectedTableCount + first.attachmentCount + 5
        )
        XCTAssertGreaterThan(first.byteCount, 0)
        XCTAssertEqual(first.checksumManifestSHA256.count, 64)
        XCTAssertEqual(
            first.checksumManifestSHA256,
            second.checksumManifestSHA256
        )
        XCTAssertEqual(
            try Data(contentsOf: firstURL.appendingPathComponent("checksums.sha256")),
            try Data(contentsOf: secondURL.appendingPathComponent("checksums.sha256"))
        )
        XCTAssertEqual(
            try FinanceFileSnapshotManager.snapshot(for: context.store.fileURL),
            sourceBefore
        )
        XCTAssertTrue(try context.store.integrityCheck())

        let data = try Data(
            contentsOf: firstURL.appendingPathComponent("data.json")
        )
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            root["format"] as? String,
            "de.pixelpuxel.finanzverwalter.open-data"
        )
        XCTAssertEqual((root["format_version"] as? NSNumber)?.intValue, 1)
        let tables = try XCTUnwrap(root["tables"] as? [[String: Any]])
        XCTAssertEqual(tables.count, expectedTableCount)
        XCTAssertEqual(Set(tables.compactMap { $0["name"] as? String }).count,
                       expectedTableCount)

        func exportedTable(_ name: String) throws -> [String: Any] {
            try XCTUnwrap(tables.first { ($0["name"] as? String) == name })
        }
        let accounts = try exportedTable("accounts")
        let accountColumns = try XCTUnwrap(accounts["columns"] as? [String])
        let accountRows = try XCTUnwrap(accounts["rows"] as? [[Any]])
        let accountIDIndex = try XCTUnwrap(accountColumns.firstIndex(of: "id"))
        XCTAssertTrue(accountRows.contains {
            ($0[accountIDIndex] as? String) == account.id.uuidString
        })
        let transactions = try exportedTable("transactions")
        let transactionColumns = try XCTUnwrap(
            transactions["columns"] as? [String]
        )
        let transactionRows = try XCTUnwrap(transactions["rows"] as? [[Any]])
        let transactionIDIndex = try XCTUnwrap(
            transactionColumns.firstIndex(of: "id")
        )
        XCTAssertTrue(transactionRows.contains {
            ($0[transactionIDIndex] as? String) == transaction.id.uuidString
        })
        let splitTable = try exportedTable("transaction_splits")
        let splitColumns = try XCTUnwrap(splitTable["columns"] as? [String])
        let splitRows = try XCTUnwrap(splitTable["rows"] as? [[Any]])
        let splitIDIndex = try XCTUnwrap(splitColumns.firstIndex(of: "id"))
        XCTAssertTrue(splitRows.contains {
            ($0[splitIDIndex] as? String) == split.id.uuidString
        })
        let blobs = try exportedTable("attachment_blobs")
        let blobColumns = try XCTUnwrap(blobs["columns"] as? [String])
        XCTAssertFalse(blobColumns.contains("payload"))
        XCTAssertTrue(blobColumns.contains("relative_path"))
        XCTAssertFalse(
            String(decoding: data, as: UTF8.self).contains(
                attachmentPayload.base64EncodedString()
            )
        )

        let attachmentURL = firstURL.appendingPathComponent(
            "attachments/\(attachment.sha256).pdf"
        )
        XCTAssertEqual(try Data(contentsOf: attachmentURL), attachmentPayload)
        let csvFiles = try FileManager.default.contentsOfDirectory(
            at: firstURL.appendingPathComponent("csv"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(csvFiles.filter { $0.pathExtension == "csv" }.count,
                       expectedTableCount)
        let transactionCSV = try Data(contentsOf: firstURL
            .appendingPathComponent("csv/transactions.csv"))
        XCTAssertTrue(transactionCSV.starts(with: Data([0xEF, 0xBB, 0xBF])))
        XCTAssertTrue(String(decoding: transactionCSV, as: UTF8.self)
            .contains(transaction.id.uuidString))

        let settingsText = try String(
            contentsOf: firstURL.appendingPathComponent("settings.json"),
            encoding: .utf8
        )
        XCTAssertTrue(settingsText.contains("appearanceMode"))
        XCTAssertFalse(settingsText.contains("privater/pfad"))
        XCTAssertFalse(settingsText.contains("niemals-exportieren"))
        let schemaText = try String(
            contentsOf: firstURL.appendingPathComponent("schema.json"),
            encoding: .utf8
        )
        XCTAssertTrue(schemaText.contains("bookmark_data"))
        XCTAssertTrue(schemaText.contains("inventory_attachments.bookmark_data"))
        XCTAssertTrue(schemaText.contains("attachment_blobs.payload"))

        let rootPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: firstURL.path)[.posixPermissions]
                as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(rootPermissions, 0o700)
        let dataPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: firstURL.appendingPathComponent("data.json").path
            )[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(dataPermissions, 0o600)

        let checksumText = try String(
            contentsOf: firstURL.appendingPathComponent("checksums.sha256"),
            encoding: .utf8
        )
        for line in checksumText.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            XCTAssertEqual(parts.count, 2)
            let expected = String(parts[0])
            let relative = String(parts[1])
            let payload = try Data(contentsOf: firstURL.appendingPathComponent(relative))
            XCTAssertEqual(SHA256.hash(data: payload).hexString, expected)
        }

        let occupied = context.directory.appendingPathComponent(
            "Belegt.finanzarchiv"
        )
        let sentinel = Data("nicht überschreiben".utf8)
        try sentinel.write(to: occupied)
        XCTAssertThrowsError(try context.store.exportOpenDataArchive(
            to: occupied, settings: [:]
        ))
        XCTAssertEqual(try Data(contentsOf: occupied), sentinel)
        XCTAssertThrowsError(try context.store.exportOpenDataArchive(
            to: context.directory.appendingPathComponent("Falsch.json"),
            settings: [:]
        ))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: context.directory.path)
                .contains { $0.hasPrefix(".finanzverwalter-export-") }
        )
    }

    func testOpenDataArchiveImportsEveryTableAttachmentAndRejectsManipulation() throws {
        let context = try TestDatabase()
        let account = FinanceAccount(
            id: UUID(), name: "Rückimportkonto", institution: "Archivbank",
            type: .checking, currency: "EUR", openingBalanceMinor: 45_600,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let category = FinanceCategory(
            id: UUID(), parentID: nil, name: "Archivkategorie",
            kind: .expense, color: "purple", isActive: true
        )
        let tag = FinanceTag(
            id: UUID(), parentID: nil, name: "Archivklasse", color: "teal",
            description: "Roundtrip", isActive: true
        )
        try context.store.saveAccount(account)
        try context.store.saveCategory(category)
        try context.store.saveTag(tag)
        let split = FinanceSplit(
            id: UUID(), categoryID: category.id, amountMinor: -7_890,
            memo: "Archivsplit", sortOrder: 0, tagIDs: [tag.id]
        )
        let transaction = FinanceTransaction(
            id: UUID(), accountID: account.id,
            bookingDate: Date(timeIntervalSince1970: 1_767_225_600),
            valueDate: Date(timeIntervalSince1970: 1_767_312_000),
            payee: "Archivempfänger", purpose: "Vollständiger Rückimport",
            categoryID: nil, amountMinor: -7_890, currency: "EUR",
            status: .cleared, memo: "JSON-Roundtrip", reference: "ARC-1",
            transferID: nil, importFingerprint: nil, splits: [split],
            tagIDs: [tag.id]
        )
        try context.store.saveTransaction(transaction)
        let attachmentPayload = Data(
            "%PDF-1.7\nRückimportierter Originalbeleg\n%%EOF\n".utf8
        )
        let attachmentSource = context.directory.appendingPathComponent(
            "rueckimport.pdf"
        )
        try attachmentPayload.write(to: attachmentSource)
        let attachment = try context.store.addAttachment(
            from: attachmentSource, to: .transaction,
            entityID: transaction.id
        )

        let archiveURL = context.directory.appendingPathComponent(
            "Roundtrip.finanzarchiv", isDirectory: true
        )
        let export = try context.store.exportOpenDataArchive(
            to: archiveURL,
            settings: ["appearanceMode": "dark", "registerRowDensity": "compact"],
            exportedAt: Date(timeIntervalSince1970: 1_775_001_600)
        )
        let sourceBeforeImport = try FinanceFileSnapshotManager.snapshot(
            for: context.store.fileURL
        )
        let sourceCounts = try sqliteTableCounts(context.store.fileURL)
        let importedURL = context.directory.appendingPathComponent(
            "Aus offenem Archiv.qdata"
        )
        let summary = try context.store.importOpenDataArchive(
            from: archiveURL, to: importedURL
        )

        XCTAssertEqual(summary.archiveURL, archiveURL.standardizedFileURL)
        XCTAssertEqual(summary.financeFileURL, importedURL.standardizedFileURL)
        XCTAssertEqual(summary.formatVersion, 1)
        XCTAssertEqual(summary.tableCount, export.tableCount)
        XCTAssertEqual(summary.rowCount, export.rowCount)
        XCTAssertEqual(summary.attachmentCount, 1)
        XCTAssertEqual(summary.importedSettings["appearanceMode"], "dark")
        XCTAssertEqual(summary.importedSettings["registerRowDensity"], "compact")
        XCTAssertEqual(
            summary.checksumManifestSHA256,
            export.checksumManifestSHA256
        )
        XCTAssertEqual(
            try FinanceFileSnapshotManager.snapshot(for: context.store.fileURL),
            sourceBeforeImport
        )
        XCTAssertEqual(try sqliteTableCounts(importedURL), sourceCounts)
        XCTAssertEqual(
            try XCTUnwrap(
                FileManager.default.attributesOfItem(
                    atPath: importedURL.path
                )[.posixPermissions] as? NSNumber
            ).intValue & 0o777,
            0o600
        )
        for suffix in ["-wal", "-shm", "-journal"] {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: importedURL.path + suffix
            ))
        }

        let importedStore = try SQLiteFinanceStore(fileURL: importedURL)
        defer { importedStore.close() }
        XCTAssertEqual(try importedStore.accounts(), try context.store.accounts())
        XCTAssertEqual(try importedStore.categories(), try context.store.categories())
        XCTAssertEqual(try importedStore.tags(), try context.store.tags())
        XCTAssertEqual(
            try importedStore.transactions(), try context.store.transactions()
        )
        let importedAttachment = try XCTUnwrap(
            importedStore.attachments(
                entityType: .transaction, entityID: transaction.id
            ).first
        )
        XCTAssertEqual(importedAttachment.id, attachment.id)
        XCTAssertEqual(importedAttachment.sha256, attachment.sha256)
        let restoredAttachmentURL = context.directory.appendingPathComponent(
            "wiederhergestellt.pdf"
        )
        _ = try importedStore.exportAttachment(
            id: importedAttachment.id, to: restoredAttachmentURL
        )
        XCTAssertEqual(
            try Data(contentsOf: restoredAttachmentURL), attachmentPayload
        )
        XCTAssertTrue(try importedStore.integrityCheck())

        let occupiedURL = context.directory.appendingPathComponent(
            "Belegtes Importziel.qdata"
        )
        let sentinel = Data("bestehendes Ziel bleibt".utf8)
        try sentinel.write(to: occupiedURL)
        XCTAssertThrowsError(try context.store.importOpenDataArchive(
            from: archiveURL, to: occupiedURL
        ))
        XCTAssertEqual(try Data(contentsOf: occupiedURL), sentinel)

        let sidecarTarget = context.directory.appendingPathComponent(
            "Ziel mit Sidecar.qdata"
        )
        let sidecarURL = URL(fileURLWithPath: sidecarTarget.path + "-wal")
        let sidecarSentinel = Data("fremdes SQLite-Sidecar bleibt".utf8)
        try sidecarSentinel.write(to: sidecarURL)
        XCTAssertThrowsError(try context.store.importOpenDataArchive(
            from: archiveURL, to: sidecarTarget
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarTarget.path))
        XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarSentinel)

        let corruptArchive = context.directory.appendingPathComponent(
            "Manipuliert.finanzarchiv", isDirectory: true
        )
        try FileManager.default.copyItem(at: archiveURL, to: corruptArchive)
        let corruptDataURL = corruptArchive.appendingPathComponent("data.json")
        var corruptData = try Data(contentsOf: corruptDataURL)
        corruptData.append(0x20)
        try corruptData.write(to: corruptDataURL, options: .atomic)
        let corruptTarget = context.directory.appendingPathComponent(
            "Manipuliert.qdata"
        )
        XCTAssertThrowsError(try context.store.importOpenDataArchive(
            from: corruptArchive, to: corruptTarget
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptTarget.path))

        let traversalArchive = context.directory.appendingPathComponent(
            "Traversal.finanzarchiv", isDirectory: true
        )
        try FileManager.default.copyItem(at: archiveURL, to: traversalArchive)
        let traversalManifest = traversalArchive.appendingPathComponent(
            "checksums.sha256"
        )
        var traversalText = try String(
            contentsOf: traversalManifest, encoding: .utf8
        )
        traversalText += String(repeating: "0", count: 64)
            + "  ../ausbruch\n"
        try Data(traversalText.utf8).write(
            to: traversalManifest, options: .atomic
        )
        let traversalTarget = context.directory.appendingPathComponent(
            "Traversal.qdata"
        )
        XCTAssertThrowsError(try context.store.importOpenDataArchive(
            from: traversalArchive, to: traversalTarget
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: traversalTarget.path))

        let symlinkArchive = context.directory.appendingPathComponent(
            "Symlink.finanzarchiv", isDirectory: true
        )
        try FileManager.default.copyItem(at: archiveURL, to: symlinkArchive)
        try FileManager.default.createSymbolicLink(
            at: symlinkArchive.appendingPathComponent("unerlaubt"),
            withDestinationURL: context.store.fileURL
        )
        let symlinkTarget = context.directory.appendingPathComponent(
            "Symlink.qdata"
        )
        XCTAssertThrowsError(try context.store.importOpenDataArchive(
            from: symlinkArchive, to: symlinkTarget
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkTarget.path))

        let extraFileArchive = context.directory.appendingPathComponent(
            "Zusatzdatei.finanzarchiv", isDirectory: true
        )
        try FileManager.default.copyItem(at: archiveURL, to: extraFileArchive)
        let extraPayload = Data("nicht dokumentierte Nutzlast".utf8)
        try extraPayload.write(
            to: extraFileArchive.appendingPathComponent("unerwartet.bin")
        )
        let extraManifestURL = extraFileArchive.appendingPathComponent(
            "checksums.sha256"
        )
        var extraManifest = try String(
            contentsOf: extraManifestURL, encoding: .utf8
        )
        extraManifest += SHA256.hash(data: extraPayload).hexString
            + "  unerwartet.bin\n"
        try Data(extraManifest.utf8).write(
            to: extraManifestURL, options: .atomic
        )
        let extraFileTarget = context.directory.appendingPathComponent(
            "Zusatzdatei.qdata"
        )
        XCTAssertThrowsError(try context.store.importOpenDataArchive(
            from: extraFileArchive, to: extraFileTarget
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: extraFileTarget.path
        ))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: context.directory.path)
                .contains { $0.hasPrefix(".finanzverwalter-import-") }
        )
    }

    func testBackupPreviewIsReadOnlyAndSummarizesRestoreContents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-backup-preview-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("Quelle.qdata")
        let backupURL = directory.appendingPathComponent("Vorschau.qbackup")
        let repository = try SQLiteFinanceStore(fileURL: sourceURL)
        try repository.renameFinanceFile("Haushalt 2026")
        let firstAccount = FinanceAccount(
            id: UUID(), name: "Giro", institution: "Bank", type: .checking,
            currency: "EUR", openingBalanceMinor: 1_000,
            isHidden: false, isClosed: false, sortOrder: 0
        )
        let secondAccount = FinanceAccount(
            id: UUID(), name: "Bar", institution: "", type: .cash,
            currency: "EUR", openingBalanceMinor: 500,
            isHidden: false, isClosed: false, sortOrder: 1
        )
        try repository.saveAccount(firstAccount)
        try repository.saveAccount(secondAccount)
        let bookingDate = Date(timeIntervalSince1970: 1_767_225_600)
        try repository.saveTransaction(FinanceTransaction(
            id: UUID(), accountID: firstAccount.id,
            bookingDate: bookingDate, valueDate: bookingDate,
            payee: "Vorschau", purpose: "Bestand prüfen", categoryID: nil,
            amountMinor: -123, currency: "EUR", status: .booked,
            memo: "", reference: "", transferID: nil,
            importFingerprint: nil, splits: []
        ))
        let expectedCategoryCount = Int64(try repository.categories().count)
        try repository.backup(to: backupURL)
        let before = try FinanceFileSnapshotManager.snapshot(for: backupURL)

        let preview = try SQLiteFinanceStore.backupPreview(at: backupURL)

        XCTAssertEqual(preview.url.path, backupURL.path)
        XCTAssertEqual(preview.financeFileName, "Haushalt 2026")
        XCTAssertEqual(preview.baseCurrency, "EUR")
        XCTAssertEqual(preview.schemaVersion, SQLiteFinanceStore.currentSchemaVersion)
        XCTAssertEqual(preview.accountCount, 2)
        XCTAssertEqual(preview.categoryCount, expectedCategoryCount)
        XCTAssertEqual(preview.transactionCount, 1)
        XCTAssertEqual(preview.latestBookingDate, bookingDate)
        XCTAssertEqual(preview.byteCount, before.byteCount)
        XCTAssertNotNil(preview.modifiedAt)
        XCTAssertEqual(
            try FinanceFileSnapshotManager.snapshot(for: backupURL), before
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path + "-shm"))
        repository.close()
    }

    @MainActor
    func testFutureSchemaBackupIsRejectedBeforeActiveFileChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-future-restore-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let activeURL = directory.appendingPathComponent("Aktiv.qdata")
        let app = FinanceAppStore(
            repository: try SQLiteFinanceStore(fileURL: activeURL)
        )
        XCTAssertTrue(app.saveAccount(
            name: "Muss bleiben", institution: "Bank",
            type: .checking, openingBalance: "42,00"
        ))

        let futureURL = directory.appendingPathComponent("Zukunft.qbackup")
        let futureStore = try SQLiteFinanceStore(fileURL: futureURL)
        try futureStore.renameFinanceFile("Nicht kompatibel")
        futureStore.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(futureURL.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                database,
                "PRAGMA journal_mode=DELETE; PRAGMA user_version=42;",
                nil, nil, nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        XCTAssertThrowsError(try SQLiteFinanceStore.backupPreview(at: futureURL)) {
            guard case let FinanceError.database(message) = $0 else {
                return XCTFail("Unerwarteter Fehler: \($0)")
            }
            XCTAssertTrue(message.contains("Schema 41"))
            XCTAssertTrue(message.contains("höchstens Schema 41"))
        }
        XCTAssertFalse(app.restoreBackup(from: futureURL))
        XCTAssertEqual(app.currentFinanceFileURL?.path, activeURL.path)
        XCTAssertEqual(app.accounts.map(\.name), ["Muss bleiben"])
        XCTAssertEqual(try sqliteScalar(activeURL, "PRAGMA user_version"), Int64(SQLiteFinanceStore.currentSchemaVersion))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix("Autosicherung-vor-Wiederherstellung-") }
        )
    }

    @MainActor
    func testFinanceFileCloseClearsAllStateBacksUpAndAllowsReopeningOrCreating() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "finanzverwalter-file-close-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "FinanzVerwalterTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let sourceURL = directory.appendingPathComponent("Geöffnet.qdata")
        let app = FinanceAppStore(
            repository: try SQLiteFinanceStore(fileURL: sourceURL),
            preferences: preferences
        )
        XCTAssertTrue(app.saveAccount(
            name: "Wieder da", institution: "Bank",
            type: .checking, openingBalance: "33,00"
        ))
        XCTAssertTrue(app.saveCategory(name: "Testkategorie", kind: .expense))
        XCTAssertFalse(app.accounts.isEmpty)
        XCTAssertFalse(app.categories.isEmpty)

        XCTAssertTrue(app.closeFinanceFile())
        XCTAssertNil(app.currentFinanceFileURL)
        XCTAssertNil(app.fileInfo)
        XCTAssertTrue(app.accounts.isEmpty)
        XCTAssertTrue(app.categories.isEmpty)
        XCTAssertTrue(app.transactions.isEmpty)
        XCTAssertTrue(app.balances.isEmpty)
        XCTAssertNil(app.selectedAccountID)
        XCTAssertEqual(app.registerSearchIndex, .empty)
        XCTAssertEqual(app.statusText, "Keine Finanzdatei geöffnet")
        XCTAssertFalse(
            try AutomaticBackupManager.backups(
                in: AutomaticBackupManager.defaultDirectory(for: sourceURL)
            ).isEmpty
        )

        XCTAssertTrue(app.openFinanceFile(at: sourceURL))
        XCTAssertEqual(app.accounts.map(\.name), ["Wieder da"])
        XCTAssertTrue(app.categories.contains { $0.name == "Testkategorie" })
        XCTAssertTrue(app.closeFinanceFile())
        let newURL = directory.appendingPathComponent("Neu nach Schließen.qdata")
        XCTAssertTrue(app.createFinanceFile(at: newURL, name: "Neu nach Schließen"))
        XCTAssertEqual(app.currentFinanceFileURL?.path, newURL.path)
        XCTAssertEqual(app.fileInfo?.name, "Neu nach Schließen")
        XCTAssertTrue(app.accounts.isEmpty)
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

private func sqliteScalar(_ url: URL, _ sql: String) throws -> Int64 {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw FinanceError.database("Testdatenbank konnte nicht gelesen werden.")
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
        throw FinanceError.database("Testabfrage konnte nicht vorbereitet werden.")
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw FinanceError.database("Testabfrage lieferte keinen Wert.")
    }
    return sqlite3_column_int64(statement, 0)
}

private func sqliteTableCounts(_ url: URL) throws -> [String: Int64] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(
        url.path, &database, SQLITE_OPEN_READONLY, nil
    ) == SQLITE_OK else {
        throw FinanceError.database("Testdatenbank konnte nicht gelesen werden.")
    }
    defer { sqlite3_close(database) }
    var namesStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        -1, &namesStatement, nil
    ) == SQLITE_OK else {
        throw FinanceError.database("Testtabellen konnten nicht gelesen werden.")
    }
    var names: [String] = []
    while sqlite3_step(namesStatement) == SQLITE_ROW,
          let raw = sqlite3_column_text(namesStatement, 0) {
        names.append(String(cString: raw))
    }
    sqlite3_finalize(namesStatement)
    var result: [String: Int64] = [:]
    for name in names {
        let quoted = "\"" + name.replacingOccurrences(
            of: "\"", with: "\"\""
        ) + "\""
        var countStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database, "SELECT COUNT(*) FROM \(quoted)",
            -1, &countStatement, nil
        ) == SQLITE_OK,
              sqlite3_step(countStatement) == SQLITE_ROW else {
            if let countStatement { sqlite3_finalize(countStatement) }
            throw FinanceError.database(
                "Testzeilen von \(name) konnten nicht gelesen werden."
            )
        }
        result[name] = sqlite3_column_int64(countStatement, 0)
        sqlite3_finalize(countStatement)
    }
    return result
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
        store.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
