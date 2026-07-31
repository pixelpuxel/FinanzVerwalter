import CryptoKit
import Foundation

enum MT940StatementImporter {
    private struct Field {
        let tag: String
        var value: String
    }

    static func parse(data: Data) throws -> BankStatementPackage {
        guard !data.isEmpty, data.count <= 50 * 1_024 * 1_024 else {
            throw FinanceError.invalidBankStatement("Die MT940-Datei ist leer oder größer als 50 MB.")
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else {
            throw FinanceError.invalidBankStatement("Die MT940-Zeichenkodierung wird nicht unterstützt.")
        }
        let fingerprint = hash(data)
        let fields = parsedFields(text)
        guard fields.contains(where: { $0.tag == "20" }),
              fields.contains(where: { $0.tag == "25" })
        else {
            throw FinanceError.invalidBankStatement("Pflichtfelder :20: und :25: fehlen.")
        }
        let segments = statementSegments(fields)
        var accounts: [BankStatementAccount] = []
        var records: [BankStatementRecord] = []
        var rejected: [String] = []

        for (statementIndex, segment) in segments.enumerated() {
            let rawAccount = segment.first { $0.tag == "25" }?.value
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawAccount.isEmpty else {
                rejected.append("MT940-Auszug \(statementIndex + 1): Feld :25: ist leer.")
                continue
            }
            let bankID = rawAccount.components(separatedBy: "/").first ?? ""
            let currency = statementCurrency(segment) ?? "EUR"
            let externalAccountID = "MT940|\(rawAccount)|\(currency)"
            let account = BankStatementAccount(
                id: externalAccountID,
                bankID: bankID,
                accountNumber: rawAccount,
                accountType: "BANK",
                currency: currency,
                isCreditCard: false
            )
            if !accounts.contains(where: { $0.id == account.id }) { accounts.append(account) }

            for (fieldIndex, field) in segment.enumerated() where field.tag == "61" {
                guard records.count < 200_000 else {
                    throw FinanceError.invalidBankStatement("Die Datei enthält mehr als 200.000 Buchungen.")
                }
                do {
                    let details = try parseTransactionLine(field.value, currency: currency)
                    let info = fieldIndex + 1 < segment.count && segment[fieldIndex + 1].tag == "86"
                        ? structured86(segment[fieldIndex + 1].value)
                        : (payee: "", purpose: "", iban: "", bic: "")
                    records.append(
                        BankStatementRecord(
                            accountID: account.id,
                            bookingDate: details.bookingDate,
                            valueDate: details.valueDate,
                            amountMinor: details.amountMinor,
                            transactionType: details.transactionType,
                            externalID: clipped(details.bankReference, 256),
                            name: clipped(info.payee, 500),
                            memo: clipped(info.purpose, 4_000),
                            checkNumber: "",
                            reference: clipped(details.customerReference, 256),
                            counterpartyIBAN: clipped(info.iban, 100),
                            counterpartyBIC: clipped(info.bic, 100)
                        )
                    )
                } catch {
                    rejected.append(
                        "MT940-Auszug \(statementIndex + 1), :61: Nr. \(fieldIndex + 1): \(error.localizedDescription)"
                    )
                }
            }
        }
        guard !accounts.isEmpty else {
            throw FinanceError.invalidBankStatement("Es wurde kein verwendbares MT940-Konto gefunden.")
        }
        return BankStatementPackage(
            format: .mt940,
            fingerprint: fingerprint,
            accounts: accounts,
            records: records,
            rejectedRows: rejected
        )
    }

    private static func parsedFields(_ text: String) -> [Field] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var fields: [Field] = []
        for line in lines {
            if line.hasPrefix(":"),
               let secondColon = line.dropFirst().firstIndex(of: ":") {
                let tag = String(line[line.index(after: line.startIndex)..<secondColon])
                let valueStart = line.index(after: secondColon)
                fields.append(Field(tag: tag, value: String(line[valueStart...])))
            } else if !line.isEmpty, !fields.isEmpty {
                fields[fields.count - 1].value += "\n" + line
            }
        }
        return fields
    }

    private static func statementSegments(_ fields: [Field]) -> [[Field]] {
        var result: [[Field]] = []
        var current: [Field] = []
        for field in fields {
            if field.tag == "20", !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(field)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func statementCurrency(_ fields: [Field]) -> String? {
        for tag in ["60F", "60M", "62F", "62M"] {
            guard let value = fields.first(where: { $0.tag == tag })?.value else { continue }
            let compact = value.replacingOccurrences(of: " ", with: "")
            guard compact.count >= 10 else { continue }
            let start = compact.index(compact.startIndex, offsetBy: 7)
            let end = compact.index(start, offsetBy: 3, limitedBy: compact.endIndex) ?? compact.endIndex
            let currency = String(compact[start..<end]).uppercased()
            if currency.count == 3, currency.allSatisfy(\.isLetter) { return currency }
        }
        return nil
    }

    private static func parseTransactionLine(
        _ raw: String,
        currency: String
    ) throws -> (
        bookingDate: Date,
        valueDate: Date?,
        amountMinor: Int64,
        transactionType: String,
        customerReference: String,
        bankReference: String
    ) {
        let line = raw.components(separatedBy: .newlines).first ?? raw
        let pattern = #"^(\d{6})(\d{4})?([R]?)([DC])([A-Z])?([0-9,]+)([A-Z0-9]{4})(.*)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), match.range == range else {
            throw FinanceError.invalidBankStatement("Die Buchungszeile entspricht nicht SWIFT MT940.")
        }
        func group(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: line) else { return "" }
            return String(line[range])
        }
        guard let valueDate = swiftDate(group(1)) else {
            throw FinanceError.invalidBankStatement("Das Wertstellungsdatum ist ungültig.")
        }
        let bookingDate: Date
        if group(2).count == 4 {
            bookingDate = entryDate(group(2), relativeTo: valueDate) ?? valueDate
        } else {
            bookingDate = valueDate
        }
        var amount = try Money(
            parsing: group(6).replacingOccurrences(of: ",", with: "."),
            currency: currency
        ).minorUnits
        if group(4) == "D" { amount = -amount }
        if group(3) == "R" { amount = -amount }
        let tail = group(8)
        let references = tail.components(separatedBy: "//")
        return (
            bookingDate,
            valueDate,
            amount,
            group(7),
            references.first?.trimmingCharacters(in: .whitespaces) ?? "",
            references.dropFirst().first?.trimmingCharacters(in: .whitespaces) ?? ""
        )
    }

    private static func swiftDate(_ value: String) -> Date? {
        guard value.count == 6, value.allSatisfy(\.isNumber),
              let shortYear = Int(value.prefix(2))
        else { return nil }
        let century = shortYear >= 70 ? 1900 : 2000
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = century + shortYear
        components.month = Int(value.dropFirst(2).prefix(2))
        components.day = Int(value.suffix(2))
        return components.date
    }

    private static func entryDate(_ monthDay: String, relativeTo valueDate: Date) -> Date? {
        guard monthDay.count == 4,
              let month = Int(monthDay.prefix(2)),
              let day = Int(monthDay.suffix(2))
        else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let valueComponents = calendar.dateComponents([.year, .month], from: valueDate)
        guard var year = valueComponents.year, let valueMonth = valueComponents.month else { return nil }
        if valueMonth == 12, month == 1 { year += 1 }
        if valueMonth == 1, month == 12 { year -= 1 }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    private static func structured86(
        _ raw: String
    ) -> (payee: String, purpose: String, iban: String, bic: String) {
        var subfields: [String: String] = [:]
        let parts = raw.components(separatedBy: "?")
        for part in parts where part.count >= 2 {
            let key = String(part.prefix(2))
            subfields[key, default: ""] += String(part.dropFirst(2))
        }
        let payee = [subfields["32"], subfields["33"]]
            .compactMap { $0 }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let purpose = (20...29).compactMap { subfields[String($0)] }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (payee, purpose.isEmpty ? raw : purpose, subfields["31"] ?? "", subfields["30"] ?? "")
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func clipped(_ value: String, _ limit: Int) -> String {
        String(value.prefix(limit))
    }
}

enum CamtStatementImporter {
    static func parse(data: Data) throws -> BankStatementPackage {
        guard !data.isEmpty, data.count <= 50 * 1_024 * 1_024 else {
            throw FinanceError.invalidBankStatement("Die camt-Datei ist leer oder größer als 50 MB.")
        }
        let root = try CamtXMLTree.parse(data)
        let statements = root.descendants(named: "Stmt") + root.descendants(named: "Ntfctn")
        guard !statements.isEmpty else {
            throw FinanceError.invalidBankStatement("Es wurde weder ein camt-Statement noch eine Notification gefunden.")
        }
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var accounts: [BankStatementAccount] = []
        var records: [BankStatementRecord] = []
        var rejected: [String] = []

        for (statementIndex, statement) in statements.enumerated() {
            let rawAccount = statement.text(at: ["Acct", "Id", "IBAN"])
                ?? statement.text(at: ["Acct", "Id", "Othr", "Id"])
                ?? ""
            guard !rawAccount.isEmpty else {
                rejected.append("camt-Auszug \(statementIndex + 1): Kontokennung fehlt.")
                continue
            }
            let fallbackCurrency = statement.text(at: ["Acct", "Ccy"])
                ?? statement.descendants(named: "Amt").first?.attributes["Ccy"]
                ?? "EUR"
            let currency = fallbackCurrency.uppercased()
            let accountID = "CAMT|\(rawAccount)|\(currency)"
            let account = BankStatementAccount(
                id: accountID,
                bankID: statement.text(at: ["Acct", "Svcr", "FinInstnId", "BICFI"])
                    ?? statement.text(at: ["Acct", "Svcr", "FinInstnId", "BIC"])
                    ?? "",
                accountNumber: rawAccount,
                accountType: "BANK",
                currency: currency,
                isCreditCard: false
            )
            if !accounts.contains(where: { $0.id == account.id }) { accounts.append(account) }

            for (entryIndex, entry) in statement.descendants(named: "Ntry").enumerated() {
                let details = entry.descendants(named: "TxDtls")
                let sources = details.isEmpty ? [entry] : details
                for (detailIndex, source) in sources.enumerated() {
                    guard records.count < 200_000 else {
                        throw FinanceError.invalidBankStatement("Die Datei enthält mehr als 200.000 Buchungen.")
                    }
                    do {
                        records.append(
                            try record(
                                source: source,
                                entry: entry,
                                account: account,
                                entryIndex: entryIndex,
                                detailIndex: detailIndex
                            )
                        )
                    } catch {
                        rejected.append(
                            "camt-Auszug \(statementIndex + 1), Buchung \(entryIndex + 1).\(detailIndex + 1): \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
        guard !accounts.isEmpty else {
            throw FinanceError.invalidBankStatement("Es wurde kein verwendbares camt-Konto gefunden.")
        }
        return BankStatementPackage(
            format: .camt,
            fingerprint: fingerprint,
            accounts: accounts,
            records: records,
            rejectedRows: rejected
        )
    }

    private static func record(
        source: CamtNode,
        entry: CamtNode,
        account: BankStatementAccount,
        entryIndex: Int,
        detailIndex: Int
    ) throws -> BankStatementRecord {
        let bookingText = entry.text(at: ["BkTxCd", "Prtry", "Cd"])
            ?? entry.firstDescendant(named: "AddtlNtryInf")?.trimmedText
            ?? ""
        let bookingDateText = entry.text(at: ["BookgDt", "Dt"])
            ?? entry.text(at: ["BookgDt", "DtTm"])
            ?? ""
        guard let bookingDate = isoDate(bookingDateText) else {
            throw FinanceError.invalidBankStatement("Das Buchungsdatum fehlt oder ist ungültig.")
        }
        let amountNode = source.node(at: ["AmtDtls", "TxAmt", "Amt"])
            ?? source.firstChild(named: "Amt")
            ?? entry.firstChild(named: "Amt")
        guard let amountNode else {
            throw FinanceError.invalidBankStatement("Der Betrag fehlt.")
        }
        let amountCurrency = amountNode.attributes["Ccy"]?.uppercased() ?? account.currency
        guard amountCurrency == account.currency else {
            throw FinanceError.invalidBankStatement(
                "Buchungswährung \(amountCurrency) weicht von Kontowährung \(account.currency) ab."
            )
        }
        var amount = try Money(parsing: amountNode.trimmedText, currency: account.currency).minorUnits
        let indicator = source.firstDescendant(named: "CdtDbtInd")?.trimmedText
            ?? entry.firstDescendant(named: "CdtDbtInd")?.trimmedText
            ?? "CRDT"
        if indicator == "DBIT" { amount = -abs(amount) } else { amount = abs(amount) }

        let isDebit = indicator == "DBIT"
        let payeePath = isDebit
            ? ["RltdPties", "Cdtr", "Nm"]
            : ["RltdPties", "Dbtr", "Nm"]
        let ibanPath = isDebit
            ? ["RltdPties", "CdtrAcct", "Id", "IBAN"]
            : ["RltdPties", "DbtrAcct", "Id", "IBAN"]
        let bicPath = isDebit
            ? ["RltdAgts", "CdtrAgt", "FinInstnId", "BICFI"]
            : ["RltdAgts", "DbtrAgt", "FinInstnId", "BICFI"]
        let endToEnd = source.text(at: ["Refs", "EndToEndId"]) ?? ""
        let transactionID = source.text(at: ["Refs", "TxId"]) ?? ""
        let serviceReference = source.text(at: ["Refs", "AcctSvcrRef"])
            ?? entry.firstDescendant(named: "AcctSvcrRef")?.trimmedText
            ?? ""
        let entryReference = entry.firstDescendant(named: "NtryRef")?.trimmedText ?? ""
        let externalID = [serviceReference, transactionID, endToEnd, entryReference]
            .first { !$0.isEmpty }
            ?? "camt-\(entryIndex)-\(detailIndex)"
        let unstructured = source.descendants(named: "Ustrd").map(\.trimmedText)
            .filter { !$0.isEmpty }.joined(separator: " ")
        let additional = source.firstDescendant(named: "AddtlTxInf")?.trimmedText ?? ""
        let memo = [unstructured, additional].filter { !$0.isEmpty }.joined(separator: " · ")
        return BankStatementRecord(
            accountID: account.id,
            bookingDate: bookingDate,
            valueDate: isoDate(
                entry.text(at: ["ValDt", "Dt"])
                    ?? entry.text(at: ["ValDt", "DtTm"])
                    ?? ""
            ),
            amountMinor: amount,
            transactionType: clipped(bookingText, 100),
            externalID: clipped(externalID, 256),
            name: clipped(source.text(at: payeePath) ?? "", 500),
            memo: clipped(memo, 4_000),
            checkNumber: "",
            reference: clipped(transactionID.isEmpty ? entryReference : transactionID, 256),
            counterpartyIBAN: clipped(source.text(at: ibanPath) ?? "", 100),
            counterpartyBIC: clipped(source.text(at: bicPath) ?? "", 100),
            endToEndID: clipped(endToEnd, 256),
            mandateReference: clipped(source.text(at: ["Refs", "MndtId"]) ?? "", 256),
            creditorID: clipped(source.firstDescendant(named: "CdtrSchmeId")?.trimmedText ?? "", 256)
        )
    }

    private static func isoDate(_ value: String) -> Date? {
        guard value.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }

    private static func clipped(_ value: String, _ limit: Int) -> String {
        String(value.prefix(limit))
    }
}

final class CamtNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [CamtNode] = []

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func firstChild(named name: String) -> CamtNode? {
        children.first { $0.name == name }
    }

    func firstDescendant(named name: String) -> CamtNode? {
        for child in children {
            if child.name == name { return child }
            if let match = child.firstDescendant(named: name) { return match }
        }
        return nil
    }

    func descendants(named name: String) -> [CamtNode] {
        children.flatMap { child in
            (child.name == name ? [child] : []) + child.descendants(named: name)
        }
    }

    func node(at path: [String]) -> CamtNode? {
        path.reduce(Optional(self)) { node, name in node?.firstChild(named: name) }
    }

    func text(at path: [String]) -> String? {
        let value = node(at: path)?.trimmedText ?? ""
        return value.isEmpty ? nil : value
    }
}

private final class CamtXMLTree: NSObject, XMLParserDelegate {
    private var stack: [CamtNode] = []
    private(set) var root: CamtNode?

    static func parse(_ data: Data) throws -> CamtNode {
        let declarationProbe = String(data: data.prefix(1_048_576), encoding: .utf8)
            ?? String(data: data.prefix(1_048_576), encoding: .isoLatin1)
            ?? ""
        if declarationProbe.range(of: "<!DOCTYPE", options: .caseInsensitive) != nil
            || declarationProbe.range(of: "<!ENTITY", options: .caseInsensitive) != nil {
            throw FinanceError.invalidBankStatement(
                "camt-Dateien mit DTD- oder ENTITY-Deklarationen werden aus Sicherheitsgründen nicht importiert."
            )
        }
        let delegate = CamtXMLTree()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw FinanceError.invalidBankStatement(
                parser.parserError?.localizedDescription ?? "Das camt-XML ist nicht wohlgeformt."
            )
        }
        return root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        let normalizedAttributes = Dictionary(uniqueKeysWithValues: attributeDict.map {
            (($0.key.components(separatedBy: ":").last ?? $0.key), $0.value)
        })
        let node = CamtNode(name: localName, attributes: normalizedAttributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }
}
