import CryptoKit
import Foundation

enum TransactionOrigin: String, Codable, CaseIterable, Sendable {
    case manual
    case fileImport
    case bankDownload
    case rule
    case scheduled
    case transfer

    var title: String {
        switch self {
        case .manual: "Manuell"
        case .fileImport: "Dateiimport"
        case .bankDownload: "Bankabruf"
        case .rule: "Regel"
        case .scheduled: "Regelmäßig"
        case .transfer: "Umbuchung"
        }
    }
}

enum ImportMatchTier: String, Codable, Sendable {
    case exactExternalID
    case strongFingerprint
    case possible

    var title: String {
        switch self {
        case .exactExternalID: "Exakte Bank-ID"
        case .strongFingerprint: "Starker Fingerabdruck"
        case .possible: "Möglicher Treffer"
        }
    }
}

struct ImportMatchCandidate: Identifiable, Hashable, Sendable {
    let transactionID: UUID
    let score: Int
    let tier: ImportMatchTier
    let reasons: [String]
    let isFinanciallyCompatible: Bool

    var id: UUID { transactionID }
}

enum ImportResolution: Hashable, Sendable {
    case importNew
    case skip
    case match(UUID)
}

struct ImportMatchAssessment: Hashable, Sendable {
    let rowID: UUID
    let candidates: [ImportMatchCandidate]
    let suggestedResolution: ImportResolution

    var bestCandidate: ImportMatchCandidate? { candidates.first }
}

enum ImportMatcher {
    static let automaticThreshold = 90
    static let candidateThreshold = 55
    static let defaultDateWindowDays = 4

    static func assess(
        rows: [FinanceTransaction],
        against existing: [FinanceTransaction],
        dateWindowDays: Int = defaultDateWindowDays
    ) -> [UUID: ImportMatchAssessment] {
        Dictionary(
            uniqueKeysWithValues: rows.map { row in
                let candidates = existing.compactMap {
                    candidate(
                        imported: row,
                        existing: $0,
                        dateWindowDays: max(0, dateWindowDays)
                    )
                }
                .filter { $0.score >= candidateThreshold }
                .sorted {
                    if $0.score != $1.score { return $0.score > $1.score }
                    return $0.transactionID.uuidString < $1.transactionID.uuidString
                }
                .prefix(3)
                let values = Array(candidates)
                let resolution: ImportResolution
                if let best = values.first,
                   best.tier == .exactExternalID {
                    resolution = .skip
                } else if let best = values.first,
                          best.score >= automaticThreshold,
                          best.isFinanciallyCompatible,
                          values.dropFirst().first?.score != best.score {
                    resolution = .match(best.transactionID)
                } else {
                    resolution = .importNew
                }
                return (
                    row.id,
                    ImportMatchAssessment(
                        rowID: row.id,
                        candidates: values,
                        suggestedResolution: resolution
                    )
                )
            }
        )
    }

    static func strongFingerprint(_ value: FinanceTransaction) -> String {
        let referenceParts = [
            normalized(value.reference),
            normalized(value.endToEndID),
            normalized(value.mandateReference)
        ]
        let material = [
            value.accountID.uuidString.lowercased(),
            String(value.amountMinor),
            value.currency.uppercased(),
            day(value.bookingDate),
            referenceParts.joined(separator: "|")
        ].joined(separator: "|")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func candidate(
        imported: FinanceTransaction,
        existing: FinanceTransaction,
        dateWindowDays: Int
    ) -> ImportMatchCandidate? {
        guard imported.accountID == existing.accountID else { return nil }

        let sameExternalID = !imported.externalProvider.isEmpty
            && !imported.externalTransactionID.isEmpty
            && imported.externalProvider == existing.externalProvider
            && imported.externalTransactionID == existing.externalTransactionID
        let financiallyCompatible = imported.amountMinor == existing.amountMinor
            && imported.currency.caseInsensitiveCompare(existing.currency) == .orderedSame
        if sameExternalID {
            return ImportMatchCandidate(
                transactionID: existing.id,
                score: 100,
                tier: .exactExternalID,
                reasons: [
                    "Konto, Provider und externe Transaktions-ID stimmen exakt überein",
                    financiallyCompatible
                        ? "Betrag und Währung stimmen überein"
                        : "Warnung: Betrag oder Währung weichen ab"
                ],
                isFinanciallyCompatible: financiallyCompatible
            )
        }
        guard financiallyCompatible else { return nil }

        var score = 45
        var reasons = ["Betrag und Währung stimmen überein"]
        let distance = dayDistance(
            imported.valueDate ?? imported.bookingDate,
            existing.valueDate ?? existing.bookingDate
        )
        guard distance <= dateWindowDays else { return nil }
        score += max(4, 20 - distance * 4)
        reasons.append(
            distance == 0
                ? "Datum stimmt überein"
                : "Datum weicht um \(distance) Tag\(distance == 1 ? "" : "e") ab"
        )

        let exactReference = exactNonempty(
            imported.reference,
            existing.reference
        )
        let exactEndToEnd = exactNonempty(
            imported.endToEndID,
            existing.endToEndID
        )
        let exactMandate = exactNonempty(
            imported.mandateReference,
            existing.mandateReference
        )
        if exactEndToEnd {
            score += 20
            reasons.append("End-to-End-ID stimmt überein")
        }
        if exactMandate {
            score += 15
            reasons.append("Mandatsreferenz stimmt überein")
        }
        if exactReference {
            score += 15
            reasons.append("Referenz stimmt überein")
        }
        if exactNonempty(imported.counterpartyIBAN, existing.counterpartyIBAN) {
            score += 15
            reasons.append("IBAN stimmt überein")
        }
        if exactNonempty(imported.payee, existing.payee) {
            score += 10
            reasons.append("Empfänger stimmt überein")
        } else {
            let similarity = tokenSimilarity(imported.payee, existing.payee)
            if similarity >= 0.5 {
                score += Int((similarity * 8).rounded())
                reasons.append("Empfänger ist ähnlich")
            }
        }
        let purposeSimilarity = tokenSimilarity(
            imported.purpose,
            existing.purpose
        )
        if purposeSimilarity >= 0.35 {
            score += Int((purposeSimilarity * 10).rounded())
            reasons.append("Verwendungszweck ist ähnlich")
        }

        let strong = distance == 0
            && (exactReference || exactEndToEnd || exactMandate)
        return ImportMatchCandidate(
            transactionID: existing.id,
            score: min(score, 99),
            tier: strong ? .strongFingerprint : .possible,
            reasons: reasons,
            isFinanciallyCompatible: true
        )
    }

    private static func exactNonempty(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        return !left.isEmpty && left == normalized(rhs)
    }

    private static func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(normalized(lhs).split(separator: " ").map(String.init))
        let right = Set(normalized(rhs).split(separator: " ").map(String.init))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count)
            / Double(left.union(right).count)
    }

    private static func dayDistance(_ lhs: Date, _ rhs: Date) -> Int {
        abs(
            Calendar(identifier: .gregorian).dateComponents(
                [.day],
                from: Calendar(identifier: .gregorian).startOfDay(for: lhs),
                to: Calendar(identifier: .gregorian).startOfDay(for: rhs)
            ).day ?? Int.max
        )
    }

    private static func day(_ value: Date) -> String {
        value.formatted(
            .iso8601
                .year()
                .month()
                .day()
                .dateSeparator(.dash)
        )
    }
}
