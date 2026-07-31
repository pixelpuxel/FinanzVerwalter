import XCTest
import SQLite3
import PDFKit
import AppKit
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
        try context.store.createDirectDebitOrder(order)
        XCTAssertThrowsError(try context.store.createDirectDebitOrder(order)) {
            XCTAssertEqual($0 as? FinanceError, .duplicateDirectDebitOrder)
        }
        let stored = try XCTUnwrap(context.store.directDebitOrders().first)
        XCTAssertEqual(stored, order)

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
            try context.store.directDebitOrders().first?.sequenceType,
            .recurring,
            "Ein bestehender Auftrag behält den Mandatsschnappschuss."
        )
        for status in [
            PaymentStatus.initiated, .challengeReceived, .awaitingUser,
            .submitted, .accepted
        ] {
            try context.store.transitionDirectDebitOrder(id: order.id, to: status)
        }
        let accepted = try XCTUnwrap(context.store.directDebitOrders().first)
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
    }

    func testMigration14To28PreservesLegacyReconciliationHistory() throws {
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
        XCTAssertEqual(sqlite3_column_int(statement, 0), 28)
        sqlite3_finalize(statement)
    }

    func testMigration22To28PromotesLegacyPayeeBankData() throws {
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
        ALTER TABLE payment_orders DROP COLUMN purpose_code;
        ALTER TABLE payment_orders DROP COLUMN payee_bank_account_id;
        ALTER TABLE payment_orders DROP COLUMN payee_id;
        DROP TABLE payee_bank_accounts;
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
