import Foundation

struct Pain008RulePackage: Equatable, Sendable {
    let identifier: String
    let namespace: String
    let validFrom: Date
    let validUntil: Date?
    let source: String

    static let epc2025 = Pain008RulePackage(
        identifier: "EPC-SDD-CORE-2025-V1.1",
        namespace: "urn:iso:std:iso:20022:tech:xsd:pain.008.001.08",
        validFrom: Pain008Exporter.gregorianDate(
            year: 2025, month: 10, day: 5
        ),
        validUntil: nil,
        source: "EPC130-08 SDD Core C2PSP IG 2025 V1.0 / Rulebook V1.1"
    )
}

enum Pain008ExportError: LocalizedError, Equatable {
    case unsupportedRuleDate
    case nonDraftOrder
    case accountMismatch
    case closedCreditorAccount
    case invalidCreditorIBAN
    case invalidDebtorIBAN
    case invalidBIC(String)
    case euroRequired
    case textTooLong(field: String, maximum: Int)
    case invalidIdentifier(String)
    case amountOutOfRange

    var errorDescription: String? {
        switch self {
        case .unsupportedRuleDate:
            "Für dieses Datum ist kein freigegebenes pain.008-Regelpaket hinterlegt."
        case .nonDraftOrder:
            "Nur unveränderte Lastschriftentwürfe dürfen als pain.008 exportiert werden."
        case .accountMismatch:
            "Lastschrift und Gläubigerkonto passen nicht zusammen."
        case .closedCreditorAccount:
            "Das Gläubigerkonto ist geschlossen."
        case .invalidCreditorIBAN:
            "Die IBAN des Gläubigerkontos ist ungültig."
        case .invalidDebtorIBAN:
            "Die IBAN des Zahlers ist ungültig."
        case .invalidBIC(let value):
            "„\(value)“ ist keine gültige BIC."
        case .euroRequired:
            "SEPA-pain.008 unterstützt ausschließlich EUR."
        case .textTooLong(let field, let maximum):
            "\(field) darf höchstens \(maximum) Zeichen enthalten."
        case .invalidIdentifier(let field):
            "\(field) darf nicht mit „/“ beginnen oder enden und kein „//“ enthalten."
        case .amountOutOfRange:
            "Der Betrag überschreitet den Wertebereich des pain.008-Formats."
        }
    }
}

struct Pain008ExportResult: Equatable, Sendable {
    let data: Data
    let fileName: String
    let rulePackage: Pain008RulePackage
}

enum Pain008Exporter {
    private static let maximumMinorUnits: Int64 = 999_999_999_999_999_999

    static func export(
        order: DirectDebitOrder,
        account: FinanceAccount,
        createdAt: Date = Date(),
        messageID: String? = nil
    ) throws -> Pain008ExportResult {
        try order.validate()
        guard order.status == .draft else {
            throw Pain008ExportError.nonDraftOrder
        }
        guard order.creditorAccountID == account.id else {
            throw Pain008ExportError.accountMismatch
        }
        guard !account.isClosed else {
            throw Pain008ExportError.closedCreditorAccount
        }
        guard order.currency.uppercased() == "EUR",
              account.currency.uppercased() == "EUR" else {
            throw Pain008ExportError.euroRequired
        }
        let creditorIBAN = IBANValidator.normalized(order.creditorIBAN)
        guard IBANValidator.isValid(creditorIBAN) else {
            throw Pain008ExportError.invalidCreditorIBAN
        }
        let debtorIBAN = IBANValidator.normalized(order.debtorIBAN)
        guard IBANValidator.isValid(debtorIBAN) else {
            throw Pain008ExportError.invalidDebtorIBAN
        }
        guard order.amountMinor <= maximumMinorUnits else {
            throw Pain008ExportError.amountOutOfRange
        }

        let rules = try rulePackage(for: createdAt)
        let creditorName = order.creditorName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let debtorName = order.debtorName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let creditorID = SEPACreditorIDValidator.normalized(order.creditorID)
        let purpose = order.purpose.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let endToEndID = normalizedEndToEndID(order.endToEndID)
        let mandateReference = order.mandateReference.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let compactOrderID = order.id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        let resolvedMessageID = messageID ?? "DD-\(compactOrderID)"
        let paymentInformationID = "DD-\(compactOrderID)"

        try validateLength(creditorName, field: "Gläubigername", maximum: 140)
        try validateLength(debtorName, field: "Zahlername", maximum: 140)
        try validateLength(purpose, field: "Verwendungszweck", maximum: 140)
        try validateIdentifier(
            resolvedMessageID, field: "Nachrichten-ID", maximum: 35
        )
        try validateIdentifier(
            paymentInformationID, field: "Zahlungsblock-ID", maximum: 35
        )
        try validateIdentifier(
            endToEndID, field: "End-to-End-ID", maximum: 35
        )
        try validateIdentifier(
            mandateReference, field: "Mandatsreferenz", maximum: 35
        )
        try validateIdentifier(
            creditorID, field: "Gläubiger-ID", maximum: 35
        )

        let creditorBIC = try normalizedBIC(order.creditorBIC)
        let debtorBIC = try normalizedBIC(order.debtorBIC)
        let amount = decimalAmount(order.amountMinor)
        let collectionDay = day(order.collectionDate)
        let mandateDay = day(order.mandateSignedOn)
        let createdTimestamp = timestamp(createdAt)
        let sequenceCode = sequenceCode(order.sequenceType)
        let creditorAgent = agentXML(element: "CdtrAgt", bic: creditorBIC)
        let debtorAgent = agentXML(element: "DbtrAgt", bic: debtorBIC)

        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document xmlns="\(rules.namespace)">
          <CstmrDrctDbtInitn>
            <GrpHdr>
              <MsgId>\(xml(resolvedMessageID))</MsgId>
              <CreDtTm>\(createdTimestamp)</CreDtTm>
              <NbOfTxs>1</NbOfTxs>
              <CtrlSum>\(amount)</CtrlSum>
              <InitgPty><Nm>\(xml(creditorName))</Nm></InitgPty>
            </GrpHdr>
            <PmtInf>
              <PmtInfId>\(xml(paymentInformationID))</PmtInfId>
              <PmtMtd>DD</PmtMtd>
              <BtchBookg>false</BtchBookg>
              <NbOfTxs>1</NbOfTxs>
              <CtrlSum>\(amount)</CtrlSum>
              <PmtTpInf>
                <SvcLvl><Cd>SEPA</Cd></SvcLvl>
                <LclInstrm><Cd>CORE</Cd></LclInstrm>
                <SeqTp>\(sequenceCode)</SeqTp>
              </PmtTpInf>
              <ReqdColltnDt>\(collectionDay)</ReqdColltnDt>
              <Cdtr><Nm>\(xml(creditorName))</Nm></Cdtr>
              <CdtrAcct><Id><IBAN>\(creditorIBAN)</IBAN></Id></CdtrAcct>
        \(creditorAgent)
              <ChrgBr>SLEV</ChrgBr>
              <CdtrSchmeId>
                <Id><PrvtId><Othr>
                  <Id>\(xml(creditorID))</Id>
                  <SchmeNm><Prtry>SEPA</Prtry></SchmeNm>
                </Othr></PrvtId></Id>
              </CdtrSchmeId>
              <DrctDbtTxInf>
                <PmtId><EndToEndId>\(xml(endToEndID))</EndToEndId></PmtId>
                <InstdAmt Ccy="EUR">\(amount)</InstdAmt>
                <DrctDbtTx>
                  <MndtRltdInf>
                    <MndtId>\(xml(mandateReference))</MndtId>
                    <DtOfSgntr>\(mandateDay)</DtOfSgntr>
                  </MndtRltdInf>
                </DrctDbtTx>
            \(debtorAgent)
                <Dbtr><Nm>\(xml(debtorName))</Nm></Dbtr>
                <DbtrAcct><Id><IBAN>\(debtorIBAN)</IBAN></Id></DbtrAcct>
                <RmtInf><Ustrd>\(xml(purpose))</Ustrd></RmtInf>
              </DrctDbtTxInf>
            </PmtInf>
          </CstmrDrctDbtInitn>
        </Document>

        """
        guard let data = content.data(using: .utf8) else {
            throw FinanceError.invalidDirectDebit(
                "pain.008 konnte nicht als UTF-8 codiert werden."
            )
        }
        return Pain008ExportResult(
            data: data,
            fileName: "pain.008-\(collectionDay)-\(order.id.uuidString.prefix(8)).xml",
            rulePackage: rules
        )
    }

    static func export(
        batch: PaymentBatch,
        orders: [DirectDebitOrder],
        account: FinanceAccount,
        createdAt: Date = Date(),
        messageID: String? = nil
    ) throws -> Pain008ExportResult {
        try batch.validate()
        guard batch.kind == .directDebit else {
            throw FinanceError.invalidPaymentBatch(
                "Dieser Sammler enthält keine Lastschriften."
            )
        }
        guard batch.accountID == account.id else {
            throw Pain008ExportError.accountMismatch
        }
        guard orders.map(\.id) == batch.memberOrderIDs else {
            throw FinanceError.invalidPaymentBatch(
                "Mitglieder oder Reihenfolge stimmen nicht mit dem gespeicherten Sammler überein."
            )
        }
        guard let first = orders.first else {
            throw FinanceError.invalidPaymentBatch("Der Sammler ist leer.")
        }
        let requestedDay = day(batch.requestedDate)
        guard orders.allSatisfy({
            $0.creditorAccountID == batch.accountID
                && $0.status == .draft
                && $0.sequenceType == first.sequenceType
                && $0.creditorID == first.creditorID
                && $0.creditorName == first.creditorName
                && $0.creditorIBAN == first.creditorIBAN
                && $0.creditorBIC == first.creditorBIC
                && day($0.collectionDate) == requestedDay
        }) else {
            throw FinanceError.invalidPaymentBatch(
                "Gläubiger, Sequenztyp, Konto, Status oder Fälligkeit der Lastschriften stimmen nicht überein."
            )
        }
        for (index, order) in orders.enumerated() {
            _ = try export(
                order: order, account: account, createdAt: createdAt,
                messageID: "CHECK-\(index + 1)"
            )
        }
        var totalMinor: Int64 = 0
        for order in orders {
            let (sum, overflow) = totalMinor.addingReportingOverflow(order.amountMinor)
            guard !overflow, sum <= maximumMinorUnits else {
                throw Pain008ExportError.amountOutOfRange
            }
            totalMinor = sum
        }
        let rules = try rulePackage(for: createdAt)
        let compactBatchID = batch.id.uuidString
            .replacingOccurrences(of: "-", with: "").uppercased()
        let resolvedMessageID = messageID ?? "DB-\(compactBatchID)"
        let paymentInformationID = "DB-\(compactBatchID)"
        try validateIdentifier(
            resolvedMessageID, field: "Nachrichten-ID", maximum: 35
        )
        try validateIdentifier(
            paymentInformationID, field: "Zahlungsblock-ID", maximum: 35
        )

        let creditorBIC = try normalizedBIC(first.creditorBIC)
        let creditorAgent = agentXML(element: "CdtrAgt", bic: creditorBIC)
        let transactionXML = try orders.map { order -> String in
            let debtorBIC = try normalizedBIC(order.debtorBIC)
            let debtorAgent = agentXML(element: "DbtrAgt", bic: debtorBIC)
            return """
              <DrctDbtTxInf>
                <PmtId><EndToEndId>\(xml(normalizedEndToEndID(order.endToEndID)))</EndToEndId></PmtId>
                <InstdAmt Ccy="EUR">\(decimalAmount(order.amountMinor))</InstdAmt>
                <DrctDbtTx>
                  <MndtRltdInf>
                    <MndtId>\(xml(order.mandateReference))</MndtId>
                    <DtOfSgntr>\(day(order.mandateSignedOn))</DtOfSgntr>
                  </MndtRltdInf>
                </DrctDbtTx>
            \(debtorAgent)
                <Dbtr><Nm>\(xml(order.debtorName.trimmingCharacters(in: .whitespacesAndNewlines)))</Nm></Dbtr>
                <DbtrAcct><Id><IBAN>\(IBANValidator.normalized(order.debtorIBAN))</IBAN></Id></DbtrAcct>
                <RmtInf><Ustrd>\(xml(order.purpose.trimmingCharacters(in: .whitespacesAndNewlines)))</Ustrd></RmtInf>
              </DrctDbtTxInf>
            """
        }.joined(separator: "\n")
        let creditorName = first.creditorName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let creditorID = SEPACreditorIDValidator.normalized(first.creditorID)
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document xmlns="\(rules.namespace)">
          <CstmrDrctDbtInitn>
            <GrpHdr>
              <MsgId>\(xml(resolvedMessageID))</MsgId>
              <CreDtTm>\(timestamp(createdAt))</CreDtTm>
              <NbOfTxs>\(orders.count)</NbOfTxs>
              <CtrlSum>\(decimalAmount(totalMinor))</CtrlSum>
              <InitgPty><Nm>\(xml(creditorName))</Nm></InitgPty>
            </GrpHdr>
            <PmtInf>
              <PmtInfId>\(xml(paymentInformationID))</PmtInfId>
              <PmtMtd>DD</PmtMtd>
              <BtchBookg>true</BtchBookg>
              <NbOfTxs>\(orders.count)</NbOfTxs>
              <CtrlSum>\(decimalAmount(totalMinor))</CtrlSum>
              <PmtTpInf>
                <SvcLvl><Cd>SEPA</Cd></SvcLvl>
                <LclInstrm><Cd>CORE</Cd></LclInstrm>
                <SeqTp>\(sequenceCode(first.sequenceType))</SeqTp>
              </PmtTpInf>
              <ReqdColltnDt>\(requestedDay)</ReqdColltnDt>
              <Cdtr><Nm>\(xml(creditorName))</Nm></Cdtr>
              <CdtrAcct><Id><IBAN>\(IBANValidator.normalized(first.creditorIBAN))</IBAN></Id></CdtrAcct>
        \(creditorAgent)
              <ChrgBr>SLEV</ChrgBr>
              <CdtrSchmeId>
                <Id><PrvtId><Othr>
                  <Id>\(xml(creditorID))</Id>
                  <SchmeNm><Prtry>SEPA</Prtry></SchmeNm>
                </Othr></PrvtId></Id>
              </CdtrSchmeId>
        \(transactionXML)
            </PmtInf>
          </CstmrDrctDbtInitn>
        </Document>

        """
        guard let data = content.data(using: .utf8) else {
            throw FinanceError.invalidPaymentBatch(
                "pain.008 konnte nicht als UTF-8 codiert werden."
            )
        }
        return Pain008ExportResult(
            data: data,
            fileName: "pain.008-sammler-\(requestedDay)-\(batch.id.uuidString.prefix(8)).xml",
            rulePackage: rules
        )
    }

    static func rulePackage(for date: Date) throws -> Pain008RulePackage {
        let package = Pain008RulePackage.epc2025
        guard date >= package.validFrom,
              package.validUntil.map({ date < $0 }) ?? true else {
            throw Pain008ExportError.unsupportedRuleDate
        }
        return package
    }

    static func gregorianDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    private static func agentXML(element: String, bic: String) -> String {
        if bic.isEmpty {
            return """
              <\(element)>
                <FinInstnId><Othr><Id>NOTPROVIDED</Id></Othr></FinInstnId>
              </\(element)>
            """
        }
        return """
              <\(element)>
                <FinInstnId><BICFI>\(xml(bic))</BICFI></FinInstnId>
              </\(element)>
            """
    }

    private static func validateLength(
        _ value: String,
        field: String,
        maximum: Int
    ) throws {
        guard value.count <= maximum else {
            throw Pain008ExportError.textTooLong(
                field: field, maximum: maximum
            )
        }
    }

    private static func validateIdentifier(
        _ value: String,
        field: String,
        maximum: Int
    ) throws {
        try validateLength(value, field: field, maximum: maximum)
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("//") else {
            throw Pain008ExportError.invalidIdentifier(field)
        }
    }

    private static func normalizedEndToEndID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "NOTPROVIDED" : trimmed
    }

    private static func normalizedBIC(_ value: String) throws -> String {
        let bic = value.uppercased().filter { !$0.isWhitespace }
        guard !bic.isEmpty else { return "" }
        guard bic.range(
            of: #"^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$"#,
            options: .regularExpression
        ) != nil else {
            throw Pain008ExportError.invalidBIC(value)
        }
        return bic
    }

    private static func sequenceCode(
        _ value: SEPAMandateSequenceType
    ) -> String {
        switch value {
        case .oneOff: "OOFF"
        case .first: "FRST"
        case .recurring: "RCUR"
        case .final: "FNAL"
        }
    }

    private static func decimalAmount(_ minorUnits: Int64) -> String {
        let whole = minorUnits / 100
        let cents = minorUnits % 100
        return "\(whole).\(cents < 10 ? "0" : "")\(cents)"
    }

    private static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            values.year ?? 0, values.month ?? 0, values.day ?? 0
        )
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func xml(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
