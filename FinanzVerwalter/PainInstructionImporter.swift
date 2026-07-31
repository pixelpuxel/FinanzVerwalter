import CryptoKit
import Foundation

enum PainInstructionKind: String, Sendable {
    case creditTransfer
    case directDebit

    var title: String {
        self == .creditTransfer ? "Überweisung" : "Lastschrift"
    }
}

struct PainInstructionRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: PainInstructionKind
    let paymentInformationID: String
    let endToEndID: String
    let localPartyName: String
    let localIBAN: String
    let localBIC: String
    let counterpartyName: String
    let counterpartyIBAN: String
    let counterpartyBIC: String
    let amountMinor: Int64
    let requestedDate: Date
    let purpose: String
    let purposeCode: String
    let isInstant: Bool
    let creditorID: String
    let mandateReference: String
    let mandateSignedOn: Date?
    let sequenceType: SEPAMandateSequenceType?
}

struct PainInstructionDocument: Identifiable, Sendable {
    let fingerprint: String
    let kind: PainInstructionKind
    let messageID: String
    let createdAt: Date?
    let records: [PainInstructionRecord]
    let warnings: [String]

    var id: String { fingerprint }
}

struct PainInstructionMatch: Identifiable, Hashable, Sendable {
    let id: UUID
    let record: PainInstructionRecord
    let accountID: UUID?
    let accountTitle: String
    let payeeID: UUID?
    let payeeBankAccountID: UUID?
    let mandateID: UUID?
    let canImport: Bool
    let explanation: String
}

struct PainInstructionPreview: Identifiable, Sendable {
    let document: PainInstructionDocument
    let matches: [PainInstructionMatch]

    var id: String { document.fingerprint }
    var importableCount: Int { matches.filter(\.canImport).count }
}

struct PaymentInstructionImportSummary: Identifiable, Hashable, Sendable {
    let id: String
    let kind: PainInstructionKind
    let messageID: String
    let sourceCreatedAt: Date?
    let importedAt: Date
    let recordCount: Int
    let importedCount: Int
    let warningCount: Int
}

struct PaymentInstructionImportItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let importID: String
    let position: Int
    let kind: PainInstructionKind
    let paymentInformationID: String
    let endToEndID: String
    let accountID: UUID?
    let accountTitle: String
    let targetOrderID: UUID?
    let counterpartyName: String
    let counterpartyIBAN: String
    let amountMinor: Int64
    let requestedDate: Date
    let purpose: String
    let imported: Bool
}

enum PainInstructionImporter {
    private static let maximumBytes = 10 * 1_024 * 1_024
    private static let maximumRecords = 20_000
    private static let creditNamespace =
        "urn:iso:std:iso:20022:tech:xsd:pain.001.001.09"
    private static let debitNamespace =
        "urn:iso:std:iso:20022:tech:xsd:pain.008.001.08"

    static func parse(data: Data) throws -> PainInstructionDocument {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw invalid("Die Datei ist leer oder größer als 10 MB.")
        }
        let probe = String(data: data.prefix(1_048_576), encoding: .utf8)
            ?? String(data: data.prefix(1_048_576), encoding: .isoLatin1)
            ?? ""
        guard probe.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              probe.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw invalid("DTD- und ENTITY-Deklarationen sind nicht zulässig.")
        }
        let tree = InstructionXMLTree()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = tree
        guard parser.parse(), let root = tree.root else {
            throw invalid(parser.parserError?.localizedDescription ?? "Das XML ist nicht wohlgeformt.")
        }
        let kind: PainInstructionKind
        let containerName: String
        switch tree.namespaceURI {
        case creditNamespace:
            kind = .creditTransfer
            containerName = "CstmrCdtTrfInitn"
        case debitNamespace:
            kind = .directDebit
            containerName = "CstmrDrctDbtInitn"
        default:
            throw invalid("Unterstützt werden nur pain.001.001.09 und pain.008.001.08.")
        }
        guard let container = root.firstDescendant(named: containerName) else {
            throw invalid("Der erwartete Customer-to-PSP-Auftragsblock fehlt.")
        }
        let messageID = container.text(at: ["GrpHdr", "MsgId"]) ?? ""
        guard validIdentifier(messageID) else {
            throw invalid("Die Nachrichten-ID fehlt oder ist ungültig.")
        }
        let createdAt = try timestamp(container.text(at: ["GrpHdr", "CreDtTm"]))
        let fingerprint = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
        var records: [PainInstructionRecord] = []
        var warnings: [String] = []
        var paymentInformationIDs = Set<String>()
        for block in container.descendants(named: "PmtInf") {
            let parsed = try parseBlock(
                block, kind: kind, fingerprint: fingerprint,
                startPosition: records.count
            )
            guard records.count <= maximumRecords - parsed.count else {
                throw invalid("Die Datei enthält mehr als 20.000 Zahlungspositionen.")
            }
            guard let paymentID = parsed.first?.paymentInformationID,
                  paymentInformationIDs.insert(paymentID).inserted else {
                throw invalid("Zahlungsblock-IDs müssen innerhalb der Datei eindeutig sein.")
            }
            records.append(contentsOf: parsed)
            if block.text(at: ["BtchBookg"]) == nil {
                warnings.append("Ein Zahlungsblock enthält keine Buchungsart-Angabe.")
            }
        }
        guard !records.isEmpty else {
            throw invalid("Die Datei enthält keine Zahlungsposition.")
        }
        try validateControl(
            container.firstChild(named: "GrpHdr"),
            count: records.count, total: try sum(records.map(\.amountMinor)),
            label: "Gruppenkopf"
        )
        return PainInstructionDocument(
            fingerprint: fingerprint, kind: kind, messageID: messageID,
            createdAt: createdAt,
            records: records, warnings: warnings
        )
    }

    static func preview(
        document: PainInstructionDocument,
        accounts: [FinanceAccount], payees: [FinancePayee],
        bankAccounts: [FinancePayeeBankAccount],
        mandates: [FinanceSEPAMandate]
    ) -> PainInstructionPreview {
        let activePayeeIDs = Set(payees.filter(\.isActive).map(\.id))
        let matches = document.records.map { record in
            let accountCandidates = accounts.filter {
                !$0.isClosed && $0.currency.uppercased() == "EUR"
                    && IBANValidator.normalized($0.iban) == record.localIBAN
                    && $0.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        == record.localPartyName
                    && (record.localBIC.isEmpty
                        || $0.bic.uppercased().filter { !$0.isWhitespace }
                            == record.localBIC)
            }
            let activeBanks = bankAccounts.filter {
                $0.isActive && activePayeeIDs.contains($0.payeeID)
                    && IBANValidator.normalized($0.iban) == record.counterpartyIBAN
                    && $0.accountHolder.trimmingCharacters(in: .whitespacesAndNewlines)
                        == record.counterpartyName
                    && (record.counterpartyBIC.isEmpty
                        || $0.bic.uppercased().filter { !$0.isWhitespace }
                            == record.counterpartyBIC)
            }
            let bank = activeBanks.count == 1 ? activeBanks[0] : nil
            let mandateCandidates = bank.map { bank in
                mandates.filter {
                    $0.isActive && $0.payeeID == bank.payeeID
                        && $0.reference == record.mandateReference
                        && $0.sequenceType == record.sequenceType
                        && sameDay($0.signedOn, record.mandateSignedOn)
                }
            } ?? []
            let mandate = mandateCandidates.count == 1
                ? mandateCandidates[0] : nil
            let canImport: Bool
            let explanation: String
            if accountCandidates.count != 1 {
                canImport = false
                explanation = accountCandidates.isEmpty
                    ? "Kein offenes EUR-Konto stimmt in Name und IBAN exakt überein."
                    : "Mehrere lokale Konten passen; die Zuordnung ist mehrdeutig."
            } else if record.kind == .directDebit && bank == nil {
                canImport = false
                explanation = activeBanks.isEmpty
                    ? "Aktive Zahlerakte mit passender Bankverbindung fehlt."
                    : "Mehrere aktive Zahler-Bankverbindungen passen."
            } else if record.kind == .directDebit && mandate == nil {
                canImport = false
                explanation = mandateCandidates.isEmpty
                    ? "Aktives Mandat mit Referenz, Datum und Sequenz fehlt."
                    : "Mehrere aktive Mandate passen."
            } else if record.kind == .creditTransfer && activeBanks.count > 1 {
                canImport = false
                explanation = "Mehrere aktive Empfänger-Bankverbindungen passen."
            } else {
                canImport = true
                explanation = record.kind == .creditTransfer && bank == nil
                    ? "Importierbar; Empfänger bleibt mangels exakter Stammdaten unverbunden."
                    : "Alle erforderlichen Stammdaten sind exakt zugeordnet."
            }
            return PainInstructionMatch(
                id: record.id, record: record,
                accountID: accountCandidates.count == 1
                    ? accountCandidates[0].id : nil,
                accountTitle: accountCandidates.count == 1
                    ? accountCandidates[0].name : "Nicht zugeordnet",
                payeeID: bank?.payeeID, payeeBankAccountID: bank?.id,
                mandateID: mandate?.id, canImport: canImport,
                explanation: explanation
            )
        }
        return PainInstructionPreview(document: document, matches: matches)
    }

    private static func parseBlock(
        _ block: InstructionXMLNode, kind: PainInstructionKind,
        fingerprint: String, startPosition: Int
    ) throws -> [PainInstructionRecord] {
        switch kind {
        case .creditTransfer:
            try parseCreditBlock(block, fingerprint: fingerprint, start: startPosition)
        case .directDebit:
            try parseDebitBlock(block, fingerprint: fingerprint, start: startPosition)
        }
    }

    private static func sameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}

private extension PainInstructionImporter {
    static func parseCreditBlock(
        _ block: InstructionXMLNode, fingerprint: String, start: Int
    ) throws -> [PainInstructionRecord] {
        try validateBlockHeader(block, method: "TRF")
        let paymentID = try identifier(block.text(at: ["PmtInfId"]), "Zahlungsblock-ID")
        let localName = try text(block.text(at: ["Dbtr", "Nm"]), "Auftraggebername")
        let localIBAN = try iban(block.text(at: ["DbtrAcct", "Id", "IBAN"]), "Auftraggeber-IBAN")
        let localBIC = try bic(block.text(at: ["DbtrAgt", "FinInstnId", "BICFI"]), "Auftraggeber-BIC")
        let requestedDate = try day(
            block.text(at: ["ReqdExctnDt", "Dt"])
                ?? block.text(at: ["ReqdExctnDt"])
        )
        let instant = block.text(at: ["PmtTpInf", "LclInstrm", "Cd"]) == "INST"
        let nodes = block.descendants(named: "CdtTrfTxInf")
        guard !nodes.isEmpty else { throw invalid("Ein Überweisungsblock ist leer.") }
        let values = try nodes.enumerated().map { offset, node in
            let amount = try amount(node.firstDescendant(named: "InstdAmt"))
            return PainInstructionRecord(
                id: stableUUID("\(fingerprint)|\(start + offset)"),
                kind: .creditTransfer, paymentInformationID: paymentID,
                endToEndID: try identifier(node.text(at: ["PmtId", "EndToEndId"]), "End-to-End-ID"),
                localPartyName: localName, localIBAN: localIBAN,
                localBIC: localBIC,
                counterpartyName: try text(node.text(at: ["Cdtr", "Nm"]), "Empfänger"),
                counterpartyIBAN: try iban(node.text(at: ["CdtrAcct", "Id", "IBAN"]), "Empfänger-IBAN"),
                counterpartyBIC: try bic(node.text(at: ["CdtrAgt", "FinInstnId", "BICFI"]), "Empfänger-BIC"),
                amountMinor: amount, requestedDate: requestedDate,
                purpose: try text(node.text(at: ["RmtInf", "Ustrd"]), "Verwendungszweck"),
                purposeCode: try purposeCode(node.text(at: ["Purp", "Cd"])),
                isInstant: instant, creditorID: "", mandateReference: "",
                mandateSignedOn: nil, sequenceType: nil
            )
        }
        try validateControl(
            block, count: values.count,
            total: try sum(values.map(\.amountMinor)), label: "Überweisungsblock"
        )
        return values
    }

    static func parseDebitBlock(
        _ block: InstructionXMLNode, fingerprint: String, start: Int
    ) throws -> [PainInstructionRecord] {
        try validateBlockHeader(block, method: "DD")
        guard block.text(at: ["PmtTpInf", "LclInstrm", "Cd"]) == "CORE" else {
            throw invalid("Lastschriftimporte unterstützen ausschließlich SEPA CORE.")
        }
        let paymentID = try identifier(block.text(at: ["PmtInfId"]), "Zahlungsblock-ID")
        let localName = try text(block.text(at: ["Cdtr", "Nm"]), "Gläubigername")
        let localIBAN = try iban(block.text(at: ["CdtrAcct", "Id", "IBAN"]), "Gläubiger-IBAN")
        let localBIC = try bic(block.text(at: ["CdtrAgt", "FinInstnId", "BICFI"]), "Gläubiger-BIC")
        let creditorID = try text(
            block.text(at: ["CdtrSchmeId", "Id", "PrvtId", "Othr", "Id"]),
            "Gläubiger-ID"
        )
        guard SEPACreditorIDValidator.isValid(creditorID) else {
            throw invalid("Die Gläubiger-ID ist ungültig.")
        }
        let requestedDate = try day(block.text(at: ["ReqdColltnDt"]))
        let sequence = try sequence(block.text(at: ["PmtTpInf", "SeqTp"]))
        let nodes = block.descendants(named: "DrctDbtTxInf")
        guard !nodes.isEmpty else { throw invalid("Ein Lastschriftblock ist leer.") }
        let values = try nodes.enumerated().map { offset, node in
            PainInstructionRecord(
                id: stableUUID("\(fingerprint)|\(start + offset)"),
                kind: .directDebit, paymentInformationID: paymentID,
                endToEndID: try identifier(node.text(at: ["PmtId", "EndToEndId"]), "End-to-End-ID"),
                localPartyName: localName, localIBAN: localIBAN,
                localBIC: localBIC,
                counterpartyName: try text(node.text(at: ["Dbtr", "Nm"]), "Zahler"),
                counterpartyIBAN: try iban(node.text(at: ["DbtrAcct", "Id", "IBAN"]), "Zahler-IBAN"),
                counterpartyBIC: try bic(node.text(at: ["DbtrAgt", "FinInstnId", "BICFI"]), "Zahler-BIC"),
                amountMinor: try amount(node.firstChild(named: "InstdAmt")),
                requestedDate: requestedDate,
                purpose: try text(node.text(at: ["RmtInf", "Ustrd"]), "Verwendungszweck"),
                purposeCode: "",
                isInstant: false,
                creditorID: SEPACreditorIDValidator.normalized(creditorID),
                mandateReference: try identifier(
                    node.text(at: ["DrctDbtTx", "MndtRltdInf", "MndtId"]),
                    "Mandatsreferenz"
                ),
                mandateSignedOn: try day(
                    node.text(at: ["DrctDbtTx", "MndtRltdInf", "DtOfSgntr"])
                ),
                sequenceType: sequence
            )
        }
        try validateControl(
            block, count: values.count,
            total: try sum(values.map(\.amountMinor)), label: "Lastschriftblock"
        )
        return values
    }

    static func validateBlockHeader(
        _ block: InstructionXMLNode, method: String
    ) throws {
        guard block.text(at: ["PmtMtd"]) == method else {
            throw invalid("Die Zahlungsmethode passt nicht zum Dateityp.")
        }
        guard block.text(at: ["PmtTpInf", "SvcLvl", "Cd"]) == "SEPA" else {
            throw invalid("Unterstützt werden ausschließlich SEPA-Zahlungsblöcke.")
        }
        if let charge = block.text(at: ["ChrgBr"]), charge != "SLEV" {
            throw invalid("Für SEPA ist nur die Entgeltregel SLEV zulässig.")
        }
    }

    static func validateControl(
        _ node: InstructionXMLNode?, count: Int, total: Int64, label: String
    ) throws {
        guard let node,
              Int(node.text(at: ["NbOfTxs"]) ?? "") == count,
              try parseMinor(node.text(at: ["CtrlSum"]) ?? "") == total else {
            throw invalid("Anzahl oder Kontrollsumme im \(label) stimmt nicht.")
        }
    }

    static func amount(_ node: InstructionXMLNode?) throws -> Int64 {
        guard let node, node.attributes["Ccy"]?.uppercased() == "EUR" else {
            throw invalid("Jede Position muss einen EUR-Betrag enthalten.")
        }
        return try parseMinor(node.trimmedText)
    }

    static func parseMinor(_ value: String) throws -> Int64 {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let whole = Int64(parts[0]), whole >= 0 else {
            throw invalid("Ein Betrag ist ungültig.")
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 2, fraction.allSatisfy(\.isNumber) else {
            throw invalid("EUR-Beträge dürfen höchstens zwei Nachkommastellen haben.")
        }
        let padded = fraction.padding(toLength: 2, withPad: "0", startingAt: 0)
        guard let cents = Int64(padded), whole <= (Int64.max - cents) / 100 else {
            throw invalid("Ein Betrag überschreitet den Wertebereich.")
        }
        let result = whole * 100 + cents
        guard result > 0 else { throw invalid("Beträge müssen positiv sein.") }
        return result
    }

    static func text(_ value: String?, _ field: String) throws -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty, normalized.count <= 140 else {
            throw invalid("\(field) fehlt oder ist länger als 140 Zeichen.")
        }
        return normalized
    }

    static func identifier(_ value: String?, _ field: String) throws -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard validIdentifier(normalized) else { throw invalid("\(field) ist ungültig.") }
        return normalized
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 35 && !value.hasPrefix("/")
            && !value.hasSuffix("/") && !value.contains("//")
    }

    static func iban(_ value: String?, _ field: String) throws -> String {
        let normalized = IBANValidator.normalized(value ?? "")
        guard IBANValidator.isValid(normalized) else { throw invalid("\(field) ist ungültig.") }
        return normalized
    }

    static func bic(_ value: String?, _ field: String) throws -> String {
        let normalized = (value ?? "").uppercased().filter { !$0.isWhitespace }
        guard normalized.isEmpty || normalized.range(
            of: "^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$", options: .regularExpression
        ) != nil else { throw invalid("\(field) ist ungültig.") }
        return normalized
    }

    static func purposeCode(_ value: String?) throws -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard normalized.isEmpty || normalized.range(
            of: "^[A-Z0-9]{1,4}$", options: .regularExpression
        ) != nil else { throw invalid("Der SEPA-Zweckcode ist ungültig.") }
        return normalized
    }

    static func timestamp(_ value: String?) throws -> Date {
        guard let value else { throw invalid("Der Erstellungszeitpunkt fehlt oder ist ungültig.") }
        let formatter = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ] {
            formatter.formatOptions = options
            if let result = formatter.date(from: value) { return result }
        }
        throw invalid("Der Erstellungszeitpunkt fehlt oder ist ungültig.")
    }

    static func day(_ value: String?) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let value, value.count == 10, let result = formatter.date(from: value) else {
            throw invalid("Ein Ausführungs-, Fälligkeits- oder Mandatsdatum ist ungültig.")
        }
        return result
    }

    static func sequence(_ value: String?) throws -> SEPAMandateSequenceType {
        switch value {
        case "OOFF": .oneOff
        case "FRST": .first
        case "RCUR": .recurring
        case "FNAL": .final
        default: throw invalid("Der Lastschrift-Sequenztyp ist ungültig.")
        }
    }

    static func sum(_ values: [Int64]) throws -> Int64 {
        try values.reduce(0) { partial, value in
            let (result, overflow) = partial.addingReportingOverflow(value)
            guard !overflow else { throw invalid("Die Kontrollsumme ist zu groß.") }
            return result
        }
    }

    static func stableUUID(_ value: String) -> UUID {
        let hex = SHA256.hash(data: Data(value.utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-a\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))")!
    }

    static func invalid(_ detail: String) -> FinanceError {
        .invalidPaymentInstructionImport(detail)
    }
}

private final class InstructionXMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [InstructionXMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func firstChild(named name: String) -> InstructionXMLNode? {
        children.first { $0.name == name }
    }

    func firstDescendant(named name: String) -> InstructionXMLNode? {
        for child in children {
            if child.name == name { return child }
            if let result = child.firstDescendant(named: name) { return result }
        }
        return nil
    }

    func descendants(named name: String) -> [InstructionXMLNode] {
        children.flatMap { child in
            (child.name == name ? [child] : []) + child.descendants(named: name)
        }
    }

    func text(at path: [String]) -> String? {
        let node = path.reduce(Optional(self)) { $0?.firstChild(named: $1) }
        let value = node?.trimmedText ?? ""
        return value.isEmpty ? nil : value
    }
}

private final class InstructionXMLTree: NSObject, XMLParserDelegate {
    private var stack: [InstructionXMLNode] = []
    private(set) var root: InstructionXMLNode?
    private(set) var namespaceURI = ""

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if root == nil { self.namespaceURI = namespaceURI ?? "" }
        let name = elementName.components(separatedBy: ":").last ?? elementName
        let node = InstructionXMLNode(name: name, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }
}
