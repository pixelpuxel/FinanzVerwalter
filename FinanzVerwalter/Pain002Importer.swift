import CryptoKit
import Foundation

enum Pain002TargetKind: String, Sendable {
    case creditTransfer
    case directDebit
    case batch

    var title: String {
        switch self {
        case .creditTransfer: "Überweisung"
        case .directDebit: "Lastschrift"
        case .batch: "Sammler"
        }
    }
}

struct Pain002StatusRecord: Hashable, Sendable {
    let originalMessageID: String
    let originalMessageNameID: String
    let originalPaymentInformationID: String
    let originalEndToEndID: String
    let statusCode: String
    let reasonCode: String
    let reasonText: String

    var proposedStatus: PaymentStatus? {
        switch statusCode {
        case "ACSC": .accepted
        case "RJCT": .rejected
        default: nil
        }
    }
}

struct Pain002Document: Sendable {
    let fingerprint: String
    let messageID: String
    let createdAt: Date?
    let records: [Pain002StatusRecord]
    let warnings: [String]
}

struct Pain002Match: Identifiable, Hashable, Sendable {
    let id: UUID
    let record: Pain002StatusRecord
    let targetKind: Pain002TargetKind?
    let targetID: UUID?
    let targetTitle: String
    let currentStatus: PaymentStatus?
    let canApply: Bool
    let explanation: String

    var proposedStatus: PaymentStatus? { record.proposedStatus }
}

struct Pain002Preview: Identifiable, Sendable {
    let document: Pain002Document
    let matches: [Pain002Match]

    var id: String { document.fingerprint }

    var applicableCount: Int { matches.filter(\.canApply).count }
    var unresolvedCount: Int { matches.filter { $0.targetID == nil }.count }
}

struct PaymentStatusReportSummary: Identifiable, Hashable, Sendable {
    let id: String
    let messageID: String
    let sourceCreatedAt: Date?
    let importedAt: Date
    let recordCount: Int
    let appliedCount: Int
    let warningCount: Int
}

struct PaymentStatusReportItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let reportID: String
    let position: Int
    let targetKind: Pain002TargetKind?
    let targetID: UUID?
    let targetTitle: String
    let statusCode: String
    let reasonCode: String
    let reasonText: String
    let previousStatus: PaymentStatus?
    let appliedStatus: PaymentStatus?
}

enum Pain002Importer {
    private static let maximumBytes = 10 * 1_024 * 1_024
    private static let maximumRecords = 20_000
    private static let namespace = "urn:iso:std:iso:20022:tech:xsd:pain.002.001.10"

    static func parse(data: Data) throws -> Pain002Document {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw FinanceError.invalidPaymentStatusReport(
                "Die Datei ist leer oder größer als 10 MB."
            )
        }
        let probe = String(data: data.prefix(1_048_576), encoding: .utf8)
            ?? String(data: data.prefix(1_048_576), encoding: .isoLatin1)
            ?? ""
        guard probe.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              probe.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw FinanceError.invalidPaymentStatusReport(
                "DTD- oder ENTITY-Deklarationen sind aus Sicherheitsgründen nicht zulässig."
            )
        }
        let tree = Pain002XMLTree()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = tree
        guard parser.parse(), let root = tree.root else {
            throw FinanceError.invalidPaymentStatusReport(
                parser.parserError?.localizedDescription
                    ?? "Das XML ist nicht wohlgeformt."
            )
        }
        guard tree.namespaceURI == namespace else {
            throw FinanceError.invalidPaymentStatusReport(
                "Unterstützt wird ausschließlich pain.002.001.10."
            )
        }
        guard let report = root.firstDescendant(named: "CstmrPmtStsRpt") else {
            throw FinanceError.invalidPaymentStatusReport(
                "Der CustomerPaymentStatusReport fehlt."
            )
        }
        let messageID = report.text(at: ["GrpHdr", "MsgId"]) ?? ""
        guard isIdentifier(messageID) else {
            throw FinanceError.invalidPaymentStatusReport(
                "Die Nachrichten-ID fehlt oder ist ungültig."
            )
        }
        let createdAt = isoDateTime(report.text(at: ["GrpHdr", "CreDtTm"]) ?? "")
        var records: [Pain002StatusRecord] = []
        var warnings: [String] = []

        for group in report.descendants(named: "OrgnlGrpInfAndSts") {
            let originalMessageID = group.text(at: ["OrgnlMsgId"]) ?? ""
            let originalMessageNameID = group.text(at: ["OrgnlMsgNmId"]) ?? ""
            let groupStatus = normalizedCode(group.text(at: ["GrpSts"]) ?? "")
            guard isIdentifier(originalMessageID) else {
                warnings.append("Eine Gruppenmeldung ohne gültige Original-Nachrichten-ID wurde übersprungen.")
                continue
            }
            if !groupStatus.isEmpty {
                let reason = statusReason(group)
                records.append(
                    Pain002StatusRecord(
                        originalMessageID: originalMessageID,
                        originalMessageNameID: originalMessageNameID,
                        originalPaymentInformationID: "",
                        originalEndToEndID: "",
                        statusCode: groupStatus,
                        reasonCode: reason.code,
                        reasonText: reason.text
                    )
                )
            }
        }

        for payment in report.descendants(named: "OrgnlPmtInfAndSts") {
            let group = report.descendants(named: "OrgnlGrpInfAndSts").first
            let originalMessageID = group?.text(at: ["OrgnlMsgId"]) ?? ""
            let originalMessageNameID = group?.text(at: ["OrgnlMsgNmId"]) ?? ""
            let paymentID = payment.text(at: ["OrgnlPmtInfId"]) ?? ""
            let transactions = payment.descendants(named: "TxInfAndSts")
            if transactions.isEmpty {
                let status = normalizedCode(payment.text(at: ["PmtInfSts"]) ?? "")
                if status.isEmpty {
                    warnings.append("Ein Zahlungsblock ohne Status wurde übersprungen.")
                } else {
                    let reason = statusReason(payment)
                    records.append(
                        Pain002StatusRecord(
                            originalMessageID: originalMessageID,
                            originalMessageNameID: originalMessageNameID,
                            originalPaymentInformationID: paymentID,
                            originalEndToEndID: "",
                            statusCode: status,
                            reasonCode: reason.code,
                            reasonText: reason.text
                        )
                    )
                }
            } else {
                for transaction in transactions {
                    guard records.count < maximumRecords else {
                        throw FinanceError.invalidPaymentStatusReport(
                            "Die Datei enthält mehr als 20.000 Statuspositionen."
                        )
                    }
                    let status = normalizedCode(transaction.text(at: ["TxSts"]) ?? "")
                    let endToEnd = transaction.text(at: ["OrgnlEndToEndId"]) ?? ""
                    guard !status.isEmpty else {
                        warnings.append("Eine Transaktionsmeldung ohne Status wurde übersprungen.")
                        continue
                    }
                    let reason = statusReason(transaction)
                    records.append(
                        Pain002StatusRecord(
                            originalMessageID: originalMessageID,
                            originalMessageNameID: originalMessageNameID,
                            originalPaymentInformationID: paymentID,
                            originalEndToEndID: endToEnd,
                            statusCode: status,
                            reasonCode: reason.code,
                            reasonText: reason.text
                        )
                    )
                }
            }
        }
        guard !records.isEmpty else {
            throw FinanceError.invalidPaymentStatusReport(
                "Die Datei enthält keinen verwendbaren Gruppen-, Zahlungs- oder Transaktionsstatus."
            )
        }
        return Pain002Document(
            fingerprint: SHA256.hash(data: data).map {
                String(format: "%02x", $0)
            }.joined(),
            messageID: messageID,
            createdAt: createdAt,
            records: records,
            warnings: warnings
        )
    }

    static func preview(
        document: Pain002Document,
        paymentOrders: [PaymentOrder],
        directDebitOrders: [DirectDebitOrder],
        batches: [PaymentBatch]
    ) -> Pain002Preview {
        let targets = targets(
            paymentOrders: paymentOrders,
            directDebitOrders: directDebitOrders,
            batches: batches
        )
        let matches = document.records.enumerated().map { index, record in
            let candidates = targets.filter { target in
                if !record.originalEndToEndID.isEmpty {
                    return target.kind != .batch
                        && target.endToEndIDs.contains(record.originalEndToEndID)
                }
                if !record.originalPaymentInformationID.isEmpty {
                    return target.paymentInformationID == record.originalPaymentInformationID
                }
                return target.messageID == record.originalMessageID
            }
            let stableID = stableUUID("\(document.fingerprint)|\(index)")
            guard candidates.count == 1, let target = candidates.first else {
                return Pain002Match(
                    id: stableID, record: record, targetKind: nil, targetID: nil,
                    targetTitle: candidates.isEmpty ? "Nicht zugeordnet" : "Mehrdeutig",
                    currentStatus: nil, canApply: false,
                    explanation: candidates.isEmpty
                        ? "Keine lokale Exportreferenz stimmt exakt überein."
                        : "Mehrere lokale Aufträge besitzen dieselbe Referenz."
                )
            }
            let finalStatus = record.proposedStatus
            let canApply = finalStatus != nil && !target.isBatched
                && (target.status == .submitted || target.status == .unknown)
            let explanation: String
            if finalStatus == nil {
                explanation = "Zwischenstatus wird historisiert und erzeugt keine Buchung."
            } else if target.isBatched {
                explanation = "Der Einzelstatus gehört zu einem Sammler und muss auf Sammlerebene bestätigt werden."
            } else if canApply {
                explanation = "Finaler Bankstatus kann atomar übernommen werden."
            } else {
                explanation = "Der lokale Auftrag wurde noch nicht übermittelt oder ist bereits endgültig."
            }
            return Pain002Match(
                id: stableID, record: record, targetKind: target.kind,
                targetID: target.id, targetTitle: target.title,
                currentStatus: target.status, canApply: canApply,
                explanation: explanation
            )
        }
        return Pain002Preview(document: document, matches: matches)
    }

    private struct Target {
        let id: UUID
        let kind: Pain002TargetKind
        let title: String
        let status: PaymentStatus
        let messageID: String
        let paymentInformationID: String
        let endToEndIDs: Set<String>
        let isBatched: Bool
    }

    private static func targets(
        paymentOrders: [PaymentOrder],
        directDebitOrders: [DirectDebitOrder],
        batches: [PaymentBatch]
    ) -> [Target] {
        var values = paymentOrders.map { order in
            let compact = compactID(order.id)
            return Target(
                id: order.id, kind: .creditTransfer,
                title: order.recipientName, status: order.status,
                messageID: "FV-\(compact)", paymentInformationID: "PI-\(compact)",
                endToEndIDs: [order.endToEndID].filter { !$0.isEmpty }.reduce(into: Set<String>()) { $0.insert($1) },
                isBatched: batches.contains { $0.memberOrderIDs.contains(order.id) }
            )
        }
        values += directDebitOrders.map { order in
            let compact = compactID(order.id)
            return Target(
                id: order.id, kind: .directDebit,
                title: order.debtorName, status: order.status,
                messageID: "DD-\(compact)", paymentInformationID: "DD-\(compact)",
                endToEndIDs: [order.endToEndID].filter { !$0.isEmpty }.reduce(into: Set<String>()) { $0.insert($1) },
                isBatched: batches.contains { $0.memberOrderIDs.contains(order.id) }
            )
        }
        let paymentsByID = Dictionary(uniqueKeysWithValues: paymentOrders.map { ($0.id, $0) })
        let debitsByID = Dictionary(uniqueKeysWithValues: directDebitOrders.map { ($0.id, $0) })
        values += batches.map { batch in
            let prefix = batch.kind == .creditTransfer ? "BT" : "DB"
            let references: Set<String>
            switch batch.kind {
            case .creditTransfer:
                references = Set(batch.memberOrderIDs.compactMap { paymentsByID[$0]?.endToEndID }.filter { !$0.isEmpty })
            case .directDebit:
                references = Set(batch.memberOrderIDs.compactMap { debitsByID[$0]?.endToEndID }.filter { !$0.isEmpty })
            }
            return Target(
                id: batch.id, kind: .batch, title: batch.name,
                status: batch.status, messageID: "\(prefix)-\(compactID(batch.id))",
                paymentInformationID: "\(prefix)-\(compactID(batch.id))",
                endToEndIDs: references, isBatched: false
            )
        }
        return values
    }

    private static func statusReason(_ node: Pain002XMLNode) -> (code: String, text: String) {
        let info = node.firstDescendant(named: "StsRsnInf")
        return (
            normalizedCode(info?.text(at: ["Rsn", "Cd"]) ?? ""),
            info?.descendants(named: "AddtlInf").map(\.trimmedText)
                .filter { !$0.isEmpty }.joined(separator: " · ") ?? ""
        )
    }

    private static func normalizedCode(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.count <= 35 && code.allSatisfy({ $0.isLetter || $0.isNumber }) ? code : ""
    }

    private static func isIdentifier(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= 35
            && !text.hasPrefix("/") && !text.hasSuffix("/") && !text.contains("//")
    }

    private static func compactID(_ id: UUID) -> String {
        id.uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }

    private static func stableUUID(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-a\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))")!
    }

    private static func isoDateTime(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private final class Pain002XMLNode {
    let name: String
    var text = ""
    var children: [Pain002XMLNode] = []

    init(name: String) { self.name = name }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func firstChild(named name: String) -> Pain002XMLNode? {
        children.first { $0.name == name }
    }

    func firstDescendant(named name: String) -> Pain002XMLNode? {
        for child in children {
            if child.name == name { return child }
            if let value = child.firstDescendant(named: name) { return value }
        }
        return nil
    }

    func descendants(named name: String) -> [Pain002XMLNode] {
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

private final class Pain002XMLTree: NSObject, XMLParserDelegate {
    private var stack: [Pain002XMLNode] = []
    private(set) var root: Pain002XMLNode?
    private(set) var namespaceURI = ""

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if root == nil { self.namespaceURI = namespaceURI ?? "" }
        let name = elementName.components(separatedBy: ":").last ?? elementName
        let node = Pain002XMLNode(name: name)
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
