import CryptoKit
import Foundation

enum BankStatementFormat: String, Sendable {
    case ofx = "OFX"
    case qfx = "QFX"
}

struct BankStatementAccount: Identifiable, Hashable, Sendable {
    let id: String
    let bankID: String
    let accountNumber: String
    let accountType: String
    let currency: String
    let isCreditCard: Bool

    var displayName: String {
        let suffix = accountNumber.count > 4
            ? String(accountNumber.suffix(4))
            : accountNumber
        let institution = bankID.isEmpty ? "Unbekanntes Institut" : bankID
        return "\(institution) · •••• \(suffix)"
    }
}

struct BankStatementRecord: Hashable, Sendable {
    let accountID: String
    let bookingDate: Date
    let valueDate: Date?
    let amountMinor: Int64
    let transactionType: String
    let externalID: String
    let name: String
    let memo: String
    let checkNumber: String
    let reference: String
}

struct BankStatementPackage: Sendable {
    let format: BankStatementFormat
    let fingerprint: String
    let accounts: [BankStatementAccount]
    let records: [BankStatementRecord]
    let rejectedRows: [String]

    func preview(
        mappings: [String: UUID],
        localAccounts: [FinanceAccount]
    ) throws -> ImportPreview {
        let accountByID = Dictionary(uniqueKeysWithValues: localAccounts.map { ($0.id, $0) })
        var rows: [FinanceTransaction] = []
        var rejected = rejectedRows
        for (index, record) in records.enumerated() {
            guard let localID = mappings[record.accountID],
                  let local = accountByID[localID]
            else {
                rejected.append("Datensatz \(index + 1): Das externe Konto ist nicht zugeordnet.")
                continue
            }
            let source = accounts.first { $0.id == record.accountID }
            let sourceCurrency = source?.currency.uppercased() ?? local.currency.uppercased()
            guard sourceCurrency == local.currency.uppercased() else {
                rejected.append(
                    "Datensatz \(index + 1): Währung \(sourceCurrency) passt nicht zu \(local.name) (\(local.currency))."
                )
                continue
            }
            let rowID = stableUUID(
                "\(fingerprint)|\(record.accountID)|\(record.externalID)|\(index)"
            )
            let purpose = [record.memo, record.transactionType]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            let transaction = FinanceTransaction(
                id: rowID,
                accountID: localID,
                bookingDate: record.bookingDate,
                valueDate: record.valueDate,
                payee: record.name,
                purpose: purpose,
                categoryID: nil,
                amountMinor: record.amountMinor,
                currency: local.currency,
                status: .booked,
                memo: record.memo,
                reference: record.reference.isEmpty ? record.checkNumber : record.reference,
                transferID: nil,
                importFingerprint: fingerprint,
                splits: [],
                origin: .fileImport,
                externalProvider: format.rawValue,
                externalTransactionID: record.externalID,
                bookingText: record.transactionType
            )
            try transaction.validate()
            rows.append(transaction)
        }
        return ImportPreview(
            rows: rows,
            rejectedRows: rejected,
            fingerprint: fingerprint
        )
    }

    private func stableUUID(_ value: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-a\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }
}

enum BankStatementImporter {
    private static let maximumBytes = 50 * 1_024 * 1_024
    private static let maximumRecords = 200_000

    static func parse(data: Data, format: BankStatementFormat) throws -> BankStatementPackage {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw FinanceError.invalidBankStatement("Die Datei ist leer oder größer als 50 MB.")
        }
        guard let decoded = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1),
              decoded.range(of: "<OFX", options: .caseInsensitive) != nil
        else {
            throw FinanceError.invalidBankStatement("Die Datei enthält kein OFX-Dokument.")
        }
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let statementBlocks = blocks(named: "STMTRS", in: decoded)
            + blocks(named: "CCSTMTRS", in: decoded)
        guard !statementBlocks.isEmpty else {
            throw FinanceError.invalidBankStatement("Es wurde kein Kontoauszug gefunden.")
        }

        var accounts: [BankStatementAccount] = []
        var records: [BankStatementRecord] = []
        var rejected: [String] = []
        for statement in statementBlocks {
            let isCreditCard = statement.range(of: "<CCACCTFROM", options: .caseInsensitive) != nil
            let bankID = value(named: "BANKID", in: statement)
            let accountNumber = value(named: "ACCTID", in: statement)
            guard !accountNumber.isEmpty else {
                rejected.append("Ein Kontoauszug ohne ACCTID wurde übersprungen.")
                continue
            }
            let accountType = isCreditCard ? "CREDITCARD" : value(named: "ACCTTYPE", in: statement)
            let currency = value(named: "CURDEF", in: statement).uppercased()
            let accountID = [isCreditCard ? "CC" : "BANK", bankID, accountNumber, accountType]
                .joined(separator: "|")
            let account = BankStatementAccount(
                id: accountID,
                bankID: bankID,
                accountNumber: accountNumber,
                accountType: accountType,
                currency: currency.isEmpty ? "EUR" : currency,
                isCreditCard: isCreditCard
            )
            if !accounts.contains(where: { $0.id == account.id }) { accounts.append(account) }

            for (offset, raw) in transactionBlocks(in: statement).enumerated() {
                guard records.count < maximumRecords else {
                    throw FinanceError.invalidBankStatement("Die Datei enthält mehr als 200.000 Buchungen.")
                }
                do {
                    let dateText = value(named: "DTPOSTED", in: raw)
                    let amountText = value(named: "TRNAMT", in: raw)
                    guard let bookingDate = parseDate(dateText) else {
                        throw FinanceError.invalidAmount("ungültiges Buchungsdatum \(dateText)")
                    }
                    let amount = try parseAmount(amountText, currency: account.currency)
                    let externalID = clipped(value(named: "FITID", in: raw), limit: 256)
                    records.append(
                        BankStatementRecord(
                            accountID: account.id,
                            bookingDate: bookingDate,
                            valueDate: parseDate(value(named: "DTUSER", in: raw)),
                            amountMinor: amount.minorUnits,
                            transactionType: clipped(value(named: "TRNTYPE", in: raw), limit: 100),
                            externalID: externalID,
                            name: clipped(value(named: "NAME", in: raw), limit: 500),
                            memo: clipped(value(named: "MEMO", in: raw), limit: 4_000),
                            checkNumber: clipped(value(named: "CHECKNUM", in: raw), limit: 256),
                            reference: clipped(value(named: "REFNUM", in: raw), limit: 256)
                        )
                    )
                } catch {
                    rejected.append("Konto \(account.displayName), Datensatz \(offset + 1): \(error.localizedDescription)")
                }
            }
        }
        guard !accounts.isEmpty else {
            throw FinanceError.invalidBankStatement("Es wurde kein verwendbares Konto gefunden.")
        }
        return BankStatementPackage(
            format: format,
            fingerprint: fingerprint,
            accounts: accounts,
            records: records,
            rejectedRows: rejected
        )
    }

    private static func blocks(named tag: String, in text: String) -> [String] {
        let upper = text.uppercased()
        let opening = "<\(tag)"
        let closing = "</\(tag)>"
        var result: [String] = []
        var cursor = upper.startIndex
        while let start = upper.range(of: opening, range: cursor..<upper.endIndex) {
            guard let openEnd = upper[start.lowerBound...].firstIndex(of: ">") else { break }
            let contentStart = upper.index(after: openEnd)
            let end = upper.range(of: closing, range: contentStart..<upper.endIndex)?.lowerBound
                ?? upper.endIndex
            result.append(String(text[contentStart..<end]))
            cursor = end < upper.endIndex ? upper.index(after: end) : upper.endIndex
        }
        return result
    }

    private static func transactionBlocks(in statement: String) -> [String] {
        let upper = statement.uppercased()
        let opening = "<STMTTRN"
        var result: [String] = []
        var cursor = upper.startIndex
        while let start = upper.range(of: opening, range: cursor..<upper.endIndex) {
            guard let openEnd = upper[start.lowerBound...].firstIndex(of: ">") else { break }
            let contentStart = upper.index(after: openEnd)
            let close = upper.range(of: "</STMTTRN>", range: contentStart..<upper.endIndex)?.lowerBound
            let next = upper.range(of: opening, range: contentStart..<upper.endIndex)?.lowerBound
            let listEnd = upper.range(of: "</BANKTRANLIST>", range: contentStart..<upper.endIndex)?.lowerBound
            let end = [close, next, listEnd].compactMap { $0 }.min() ?? upper.endIndex
            result.append(String(statement[contentStart..<end]))
            cursor = end < upper.endIndex ? upper.index(after: end) : upper.endIndex
        }
        return result
    }

    private static func value(named tag: String, in text: String) -> String {
        let upper = text.uppercased()
        guard let start = upper.range(of: "<\(tag)") else { return "" }
        guard let openEnd = upper[start.lowerBound...].firstIndex(of: ">") else { return "" }
        let valueStart = upper.index(after: openEnd)
        let end = upper[valueStart...].firstIndex(of: "<")
            ?? upper[valueStart...].firstIndex(of: "\n")
            ?? upper.endIndex
        return String(text[valueStart..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
    }

    private static func parseDate(_ text: String) -> Date? {
        let digits = text.prefix(8)
        guard digits.count == 8, digits.allSatisfy(\.isNumber) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: String(digits))
    }

    private static func parseAmount(_ text: String, currency: String) throws -> Money {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.contains(",") else { throw FinanceError.invalidAmount(text) }
        return try Money(parsing: normalized, currency: currency)
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        String(value.prefix(limit))
    }
}
