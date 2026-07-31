import Foundation

struct Money: Hashable, Comparable, Codable, Sendable {
    let minorUnits: Int64
    let currency: String

    init(minorUnits: Int64, currency: String = "EUR") {
        self.minorUnits = minorUnits
        self.currency = currency.uppercased()
    }

    init(parsing text: String, currency: String = "EUR") throws {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: "€", with: "")
        guard !cleaned.isEmpty else { throw FinanceError.invalidAmount(text) }

        let normalized: String
        if cleaned.contains(",") {
            normalized = cleaned
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = cleaned
        }
        guard var decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            throw FinanceError.invalidAmount(text)
        }
        var factor = Decimal(100)
        var scaled = Decimal()
        NSDecimalMultiply(&scaled, &decimal, &factor, .bankers)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else { throw FinanceError.invalidAmount(text) }
        self.init(minorUnits: number.int64Value, currency: currency)
    }

    var decimal: Decimal {
        Decimal(minorUnits) / Decimal(100)
    }

    var formatted: String {
        decimal.formatted(
            .currency(code: currency)
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(2))
        )
    }

    var editingString: String {
        decimal.formatted(
            .number
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(2))
        )
    }

    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency)
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency)
        return lhs.minorUnits < rhs.minorUnits
    }
}

struct SecurityQuantity: Hashable, Comparable, Codable, Sendable {
    static let scale: Int64 = 1_000_000
    let microUnits: Int64

    init(microUnits: Int64) {
        self.microUnits = microUnits
    }

    init(parsing text: String) throws {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard var decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            throw FinanceError.invalidQuantity(text)
        }
        var scale = Decimal(Self.scale)
        var scaled = Decimal()
        NSDecimalMultiply(&scaled, &decimal, &scale, .bankers)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else { throw FinanceError.invalidQuantity(text) }
        microUnits = number.int64Value
    }

    var formatted: String {
        (Decimal(microUnits) / Decimal(Self.scale)).formatted(
            .number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...6))
        )
    }

    static func < (lhs: SecurityQuantity, rhs: SecurityQuantity) -> Bool {
        lhs.microUnits < rhs.microUnits
    }
}

enum FinanceError: LocalizedError, Equatable {
    case invalidAmount(String)
    case splitMismatch(expected: Int64, actual: Int64)
    case missingAccount
    case database(String)
    case duplicateImport
    case invalidBackup
    case protectedTransaction
    case reconciliationDifference(Int64)
    case invalidIBAN
    case invalidPaymentTransition
    case duplicatePaymentOrder
    case invalidQuantity(String)
    case insufficientQuantity
    case allocationMismatch(Int)
    case invalidLoanTerms(String)

    var errorDescription: String? {
        switch self {
        case .invalidAmount(let value): "„\(value)“ ist kein gültiger Betrag."
        case .splitMismatch(let expected, let actual):
            "Die Splits ergeben \(Money(minorUnits: actual).formatted), erwartet sind \(Money(minorUnits: expected).formatted)."
        case .missingAccount: "Bitte wähle ein Konto."
        case .database(let message): "Datenbankfehler: \(message)"
        case .duplicateImport: "Diese Importdatei wurde bereits übernommen."
        case .invalidBackup: "Die Sicherungsdatei ist ungültig."
        case .protectedTransaction: "Eine abgeglichene Buchung ist gegen unbeabsichtigte Änderungen geschützt."
        case .reconciliationDifference(let value):
            "Der Kontoabgleich hat noch eine Differenz von \(Money(minorUnits: value).formatted)."
        case .invalidIBAN: "Die IBAN-Prüfsumme ist ungültig."
        case .invalidPaymentTransition: "Dieser Zahlungsstatus darf nicht in den gewünschten Zustand wechseln."
        case .duplicatePaymentOrder: "Dieser Zahlungsauftrag wurde mit derselben Idempotenzkennung bereits angelegt."
        case .invalidQuantity(let value): "„\(value)“ ist keine gültige Stückzahl."
        case .insufficientQuantity: "Der Verkauf würde einen negativen Bestand erzeugen."
        case .allocationMismatch(let basisPoints):
            "Die Vermögensklassen ergeben \(Decimal(basisPoints) / 100) %, erforderlich sind exakt 100 %."
        case .invalidLoanTerms(let message):
            "Der Tilgungsplan ist ungültig: \(message)"
        }
    }
}
