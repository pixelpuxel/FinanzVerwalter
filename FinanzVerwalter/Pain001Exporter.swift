import Foundation

struct Pain001RulePackage: Equatable, Sendable {
    let identifier: String
    let namespace: String
    let validFrom: Date
    let validUntil: Date?
    let source: String

    static let epc2025 = Pain001RulePackage(
        identifier: "EPC-SCT-2025-V1.0",
        namespace: "urn:iso:std:iso:20022:tech:xsd:pain.001.001.09",
        validFrom: Pain001Exporter.gregorianDate(year: 2025, month: 10, day: 5),
        validUntil: nil,
        source: "EPC132-08 SCT C2PSP IG 2025 V1.0"
    )
}

enum Pain001ExportError: LocalizedError, Equatable {
    case unsupportedRuleDate
    case nonDraftOrder
    case accountMismatch
    case closedDebtorAccount
    case missingDebtorName
    case invalidDebtorIBAN
    case invalidBIC(String)
    case euroRequired
    case textTooLong(field: String, maximum: Int)
    case invalidIdentifier(String)
    case amountOutOfRange

    var errorDescription: String? {
        switch self {
        case .unsupportedRuleDate:
            "Für dieses Datum ist kein freigegebenes pain.001-Regelpaket hinterlegt."
        case .nonDraftOrder:
            "Nur unveränderte Zahlungsentwürfe dürfen als pain.001 exportiert werden."
        case .accountMismatch:
            "Zahlungsauftrag und Auftraggeberkonto passen nicht zusammen."
        case .closedDebtorAccount:
            "Das Auftraggeberkonto ist geschlossen."
        case .missingDebtorName:
            "Im Auftraggeberkonto fehlt der Kontoinhaber."
        case .invalidDebtorIBAN:
            "Die IBAN des Auftraggeberkontos ist ungültig."
        case .invalidBIC(let value):
            "„\(value)“ ist keine gültige BIC."
        case .euroRequired:
            "SEPA-pain.001 unterstützt in diesem Export ausschließlich EUR."
        case .textTooLong(let field, let maximum):
            "\(field) darf höchstens \(maximum) Zeichen enthalten."
        case .invalidIdentifier(let field):
            "\(field) darf nicht mit „/“ beginnen oder enden und kein „//“ enthalten."
        case .amountOutOfRange:
            "Der Betrag überschreitet den Wertebereich des pain.001-Formats."
        }
    }
}

struct Pain001ExportResult: Equatable, Sendable {
    let data: Data
    let fileName: String
    let rulePackage: Pain001RulePackage
}

enum Pain001Exporter {
    private static let maximumMinorUnits: Int64 = 999_999_999_999_999_999

    static func export(
        order: PaymentOrder,
        account: FinanceAccount,
        createdAt: Date = Date(),
        messageID: String? = nil
    ) throws -> Pain001ExportResult {
        try order.validate()
        guard order.status == .draft else {
            throw Pain001ExportError.nonDraftOrder
        }
        guard order.accountID == account.id else {
            throw Pain001ExportError.accountMismatch
        }
        guard !account.isClosed else {
            throw Pain001ExportError.closedDebtorAccount
        }
        let debtorName = account.ownerName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !debtorName.isEmpty else {
            throw Pain001ExportError.missingDebtorName
        }
        let debtorIBAN = IBANValidator.normalized(account.iban)
        guard IBANValidator.isValid(debtorIBAN) else {
            throw Pain001ExportError.invalidDebtorIBAN
        }
        guard order.currency.uppercased() == "EUR",
              account.currency.uppercased() == "EUR" else {
            throw Pain001ExportError.euroRequired
        }
        guard order.amountMinor <= maximumMinorUnits else {
            throw Pain001ExportError.amountOutOfRange
        }

        let rules = try rulePackage(for: createdAt)
        let recipientName = order.recipientName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let purpose = order.purpose.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let endToEndID = normalizedEndToEndID(order.endToEndID)
        let compactOrderID = order.id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        let resolvedMessageID = messageID
            ?? "FV-\(compactOrderID)"
        let paymentInformationID = "PI-\(compactOrderID)"

        try validateLength(debtorName, field: "Kontoinhaber", maximum: 140)
        try validateLength(recipientName, field: "Empfänger", maximum: 140)
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

        let debtorBIC = try normalizedBIC(account.bic)
        let creditorBIC = try normalizedBIC(order.bic)
        let amount = decimalAmount(order.amountMinor)
        let executionDay = day(order.executionDate)
        let createdTimestamp = timestamp(createdAt)
        let localInstrument = order.type == .instantCreditTransfer
            ? "\n          <LclInstrm><Cd>INST</Cd></LclInstrm>" : ""
        let debtorAgent: String
        if debtorBIC.isEmpty {
            debtorAgent = """
              <DbtrAgt>
                <FinInstnId><Othr><Id>NOTPROVIDED</Id></Othr></FinInstnId>
              </DbtrAgt>
            """
        } else {
            debtorAgent = """
              <DbtrAgt>
                <FinInstnId><BICFI>\(xml(debtorBIC))</BICFI></FinInstnId>
              </DbtrAgt>
            """
        }
        let creditorAgent = creditorBIC.isEmpty ? "" : """

              <CdtrAgt>
                <FinInstnId><BICFI>\(xml(creditorBIC))</BICFI></FinInstnId>
              </CdtrAgt>
        """

        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Document xmlns="\(rules.namespace)">
          <CstmrCdtTrfInitn>
            <GrpHdr>
              <MsgId>\(xml(resolvedMessageID))</MsgId>
              <CreDtTm>\(createdTimestamp)</CreDtTm>
              <NbOfTxs>1</NbOfTxs>
              <CtrlSum>\(amount)</CtrlSum>
              <InitgPty><Nm>\(xml(debtorName))</Nm></InitgPty>
            </GrpHdr>
            <PmtInf>
              <PmtInfId>\(xml(paymentInformationID))</PmtInfId>
              <PmtMtd>TRF</PmtMtd>
              <BtchBookg>false</BtchBookg>
              <NbOfTxs>1</NbOfTxs>
              <CtrlSum>\(amount)</CtrlSum>
              <PmtTpInf>
                <SvcLvl><Cd>SEPA</Cd></SvcLvl>\(localInstrument)
              </PmtTpInf>
              <ReqdExctnDt><Dt>\(executionDay)</Dt></ReqdExctnDt>
              <Dbtr><Nm>\(xml(debtorName))</Nm></Dbtr>
              <DbtrAcct><Id><IBAN>\(debtorIBAN)</IBAN></Id></DbtrAcct>
        \(debtorAgent)
              <ChrgBr>SLEV</ChrgBr>
              <CdtTrfTxInf>
                <PmtId><EndToEndId>\(xml(endToEndID))</EndToEndId></PmtId>
                <Amt><InstdAmt Ccy="EUR">\(amount)</InstdAmt></Amt>\(creditorAgent)
                <Cdtr><Nm>\(xml(recipientName))</Nm></Cdtr>
                <CdtrAcct><Id><IBAN>\(IBANValidator.normalized(order.iban))</IBAN></Id></CdtrAcct>
                <RmtInf><Ustrd>\(xml(purpose))</Ustrd></RmtInf>
              </CdtTrfTxInf>
            </PmtInf>
          </CstmrCdtTrfInitn>
        </Document>

        """
        guard let data = content.data(using: .utf8) else {
            throw FinanceError.database("pain.001 konnte nicht als UTF-8 codiert werden.")
        }
        return Pain001ExportResult(
            data: data,
            fileName: "pain.001-\(executionDay)-\(order.id.uuidString.prefix(8)).xml",
            rulePackage: rules
        )
    }

    static func rulePackage(for date: Date) throws -> Pain001RulePackage {
        let package = Pain001RulePackage.epc2025
        guard date >= package.validFrom,
              package.validUntil.map({ date < $0 }) ?? true else {
            throw Pain001ExportError.unsupportedRuleDate
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

    private static func validateLength(
        _ value: String,
        field: String,
        maximum: Int
    ) throws {
        guard value.count <= maximum else {
            throw Pain001ExportError.textTooLong(
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
            throw Pain001ExportError.invalidIdentifier(field)
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
            throw Pain001ExportError.invalidBIC(value)
        }
        return bic
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
