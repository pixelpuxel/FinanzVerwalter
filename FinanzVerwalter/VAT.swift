import Foundation

enum VATMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case automatic
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "Keine MwSt."
        case .automatic: "Automatisch aus Brutto"
        case .manual: "Steuerbetrag manuell"
        }
    }
}

struct VATCode: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rateBasisPoints: Int
    var description: String
    var isActive: Bool

    var percentageText: String {
        (Decimal(rateBasisPoints) / 100).formatted(
            .number
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(0...2))
        ) + " %"
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.invalidVAT("Der Name des MwSt.-Schlüssels fehlt.")
        }
        guard (0...10_000).contains(rateBasisPoints) else {
            throw FinanceError.invalidVAT("Der Steuersatz muss zwischen 0 % und 100 % liegen.")
        }
    }
}

struct VATBreakdown: Equatable, Sendable {
    let grossMinor: Int64
    let netMinor: Int64
    let taxMinor: Int64

    func validate() throws {
        guard netMinor + taxMinor == grossMinor else {
            throw FinanceError.invalidVAT(
                "Netto und Steuer ergeben nicht den Bruttobetrag."
            )
        }
    }
}

enum VATCalculator {
    static func basisPoints(parsing text: String) throws -> Int {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let rate = Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            throw FinanceError.invalidVAT("Der MwSt.-Satz ist keine gültige Zahl.")
        }
        var scaled = rate * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let value = NSDecimalNumber(decimal: rounded).intValue
        guard (0...10_000).contains(value) else {
            throw FinanceError.invalidVAT("Der MwSt.-Satz muss zwischen 0 % und 100 % liegen.")
        }
        return value
    }

    static func automatic(
        grossMinor: Int64,
        rateBasisPoints: Int
    ) throws -> VATBreakdown {
        guard (0...10_000).contains(rateBasisPoints) else {
            throw FinanceError.invalidVAT("Der MwSt.-Satz ist ungültig.")
        }
        let numerator = Decimal(grossMinor) * Decimal(10_000)
        let denominator = Decimal(10_000 + rateBasisPoints)
        let netMinor = roundedMinor(numerator / denominator)
        let result = VATBreakdown(
            grossMinor: grossMinor,
            netMinor: netMinor,
            taxMinor: grossMinor - netMinor
        )
        try result.validate()
        return result
    }

    static func manual(
        grossMinor: Int64,
        taxMinor: Int64
    ) throws -> VATBreakdown {
        guard abs(taxMinor) <= abs(grossMinor) else {
            throw FinanceError.invalidVAT(
                "Der Steuerbetrag darf den Bruttobetrag nicht überschreiten."
            )
        }
        guard taxMinor == 0 || grossMinor == 0
                || (taxMinor > 0) == (grossMinor > 0)
        else {
            throw FinanceError.invalidVAT(
                "Steuer- und Bruttobetrag müssen dasselbe Vorzeichen besitzen."
            )
        }
        let result = VATBreakdown(
            grossMinor: grossMinor,
            netMinor: grossMinor - taxMinor,
            taxMinor: taxMinor
        )
        try result.validate()
        return result
    }

    static func receipt(_ lines: [VATBreakdown]) throws -> VATBreakdown {
        try lines.forEach { try $0.validate() }
        let result = VATBreakdown(
            grossMinor: lines.reduce(0) { $0 + $1.grossMinor },
            netMinor: lines.reduce(0) { $0 + $1.netMinor },
            taxMinor: lines.reduce(0) { $0 + $1.taxMinor }
        )
        try result.validate()
        return result
    }

    private static func roundedMinor(_ value: Decimal) -> Int64 {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
