import Foundation

struct Money: Hashable, Comparable, Codable, Sendable {
    let minorUnits: Int64
    let currency: String

    init(minorUnits: Int64, currency: String = "EUR") {
        self.minorUnits = minorUnits
        self.currency = currency.uppercased()
    }

    init(parsing text: String, currency: String = "EUR") throws {
        let normalizedCurrency = currency.uppercased()
        let cleaned = Self.cleanedInput(text, currency: normalizedCurrency)
        guard !cleaned.isEmpty else { throw FinanceError.invalidAmount(text) }

        guard let normalized = Self.normalizedValidatedNumber(cleaned),
              let decimal = Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            throw FinanceError.invalidAmount(text)
        }
        self.init(
            minorUnits: try Self.roundedMinorUnits(
                decimal, currency: normalizedCurrency, originalText: text
            ),
            currency: normalizedCurrency
        )
    }

    init(evaluating text: String, currency: String = "EUR") throws {
        let normalizedCurrency = currency.uppercased()
        var parser = MoneyExpressionParser(
            text: Self.cleanedInput(text, currency: normalizedCurrency),
            originalText: text
        )
        let decimal = try parser.parse()
        self.init(
            minorUnits: try Self.roundedMinorUnits(
                decimal, currency: normalizedCurrency, originalText: text
            ),
            currency: normalizedCurrency
        )
    }

    private static func cleanedInput(_ text: String, currency: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(
                of: currency,
                with: "",
                options: [.caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func normalizedNumber(_ value: String) -> String {
        if value.contains(",") {
            return value
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        }
        return value
    }

    fileprivate static func normalizedValidatedNumber(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        var unsigned = value
        if unsigned.first == "+" || unsigned.first == "-" {
            unsigned.removeFirst()
        }
        guard !unsigned.isEmpty,
              unsigned.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." })
        else { return nil }

        if unsigned.contains(",") {
            let parts = unsigned.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  !parts[0].isEmpty,
                  !parts[1].isEmpty,
                  parts[1].allSatisfy(\.isNumber),
                  validGermanIntegerPart(String(parts[0]))
            else { return nil }
        } else if unsigned.contains(".") {
            let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  !parts[0].isEmpty,
                  !parts[1].isEmpty,
                  parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
            else { return nil }
        } else if !unsigned.allSatisfy(\.isNumber) {
            return nil
        }
        return normalizedNumber(value)
    }

    private static func validGermanIntegerPart(_ value: String) -> Bool {
        let groups = value.split(separator: ".", omittingEmptySubsequences: false)
        guard groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return false
        }
        guard groups.count > 1 else { return true }
        return (1...3).contains(groups[0].count)
            && groups.dropFirst().allSatisfy({ $0.count == 3 })
    }

    private static func roundedMinorUnits(
        _ value: Decimal,
        currency: String,
        originalText: String
    ) throws -> Int64 {
        var decimal = value
        var factor = Decimal(Self.minorUnitFactor(for: currency))
        var scaled = Decimal()
        guard NSDecimalMultiply(&scaled, &decimal, &factor, .bankers) == .noError else {
            throw FinanceError.invalidAmount(originalText)
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber,
              number.compare(NSNumber(value: Int64.max)) != .orderedDescending,
              number.compare(NSNumber(value: Int64.min)) != .orderedAscending
        else {
            throw FinanceError.invalidAmount(originalText)
        }
        return number.int64Value
    }

    var decimal: Decimal {
        Decimal(minorUnits) / Decimal(Self.minorUnitFactor(for: currency))
    }

    var formatted: String {
        decimal.formatted(
            .currency(code: currency)
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(Self.fractionDigits(for: currency)))
        )
    }

    var editingString: String {
        decimal.formatted(
            .number
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(Self.fractionDigits(for: currency)))
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

    static func fractionDigits(for currency: String) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        return min(max(formatter.maximumFractionDigits, 0), 4)
    }

    static func minorUnitFactor(for currency: String) -> Int64 {
        (0..<fractionDigits(for: currency)).reduce(Int64(1)) { value, _ in
            value * 10
        }
    }
}

private struct MoneyExpressionParser {
    private let originalText: String
    private var characters: [Character]
    private var index = 0
    private var operationCount = 0

    init(text: String, originalText: String) {
        self.originalText = originalText
        let normalized = text
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
        characters = Array(normalized)
    }

    mutating func parse() throws -> Decimal {
        guard characters.count <= 256 else { throw invalid }
        skipWhitespace()
        if current == "=" { advance(); skipWhitespace() }
        guard index < characters.count else { throw invalid }
        let value = try expression(depth: 0)
        skipWhitespace()
        guard index == characters.count else { throw invalid }
        return value
    }

    private mutating func expression(depth: Int) throws -> Decimal {
        var value = try term(depth: depth)
        while true {
            skipWhitespace()
            guard current == "+" || current == "-" else { return value }
            let operation = current
            advance()
            let right = try term(depth: depth)
            value = try calculate(value, right, operation: operation)
        }
    }

    private mutating func term(depth: Int) throws -> Decimal {
        var value = try factor(depth: depth)
        while true {
            skipWhitespace()
            guard current == "*" || current == "/" else { return value }
            let operation = current
            advance()
            let right = try factor(depth: depth)
            if operation == "/", right == 0 { throw invalid }
            value = try calculate(value, right, operation: operation)
        }
    }

    private mutating func factor(depth: Int) throws -> Decimal {
        guard depth <= 32 else { throw invalid }
        skipWhitespace()
        if current == "+" {
            advance()
            return try factor(depth: depth + 1)
        }
        if current == "-" {
            advance()
            return -(try factor(depth: depth + 1))
        }
        if current == "(" {
            advance()
            let value = try expression(depth: depth + 1)
            skipWhitespace()
            guard current == ")" else { throw invalid }
            advance()
            return value
        }
        return try number()
    }

    private mutating func number() throws -> Decimal {
        skipWhitespace()
        let start = index
        while let character = current,
              character.isNumber || character == "," || character == "." {
            advance()
        }
        guard index > start else { throw invalid }
        let token = String(characters[start..<index])
        guard let normalized = Money.normalizedValidatedNumber(token),
              let value = Decimal(
                  string: normalized,
                  locale: Locale(identifier: "en_US_POSIX")
              )
        else { throw invalid }
        return value
    }

    private mutating func calculate(
        _ left: Decimal,
        _ right: Decimal,
        operation: Character?
    ) throws -> Decimal {
        operationCount += 1
        guard operationCount <= 128 else { throw invalid }
        var lhs = left
        var rhs = right
        var result = Decimal()
        let error: Decimal.CalculationError
        switch operation {
        case "+": error = NSDecimalAdd(&result, &lhs, &rhs, .bankers)
        case "-": error = NSDecimalSubtract(&result, &lhs, &rhs, .bankers)
        case "*": error = NSDecimalMultiply(&result, &lhs, &rhs, .bankers)
        case "/": error = NSDecimalDivide(&result, &lhs, &rhs, .bankers)
        default: throw invalid
        }
        guard error == .noError || error == .lossOfPrecision else { throw invalid }
        return result
    }

    private var current: Character? {
        index < characters.count ? characters[index] : nil
    }

    private mutating func advance() { index += 1 }

    private mutating func skipWhitespace() {
        while current?.isWhitespace == true { advance() }
    }

    private var invalid: FinanceError { .invalidAmount(originalText) }
}

struct ExchangeRate: Hashable, Codable, Sendable {
    static let scale: Int64 = 100_000_000
    let scaledValue: Int64

    init(scaledValue: Int64) throws {
        guard scaledValue > 0 else {
            throw FinanceError.invalidExchangeRate("Der Wechselkurs muss größer als null sein.")
        }
        self.scaledValue = scaledValue
    }

    init(parsing text: String) throws {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.contains(",")
            ? cleaned.replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            : cleaned
        guard var decimal = Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        ), decimal > 0 else {
            throw FinanceError.invalidExchangeRate("„\(text)“ ist kein gültiger Wechselkurs.")
        }
        var scale = Decimal(Self.scale)
        var scaled = Decimal()
        NSDecimalMultiply(&scaled, &decimal, &scale, .bankers)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber, number.compare(NSNumber(value: Int64.max)) != .orderedDescending,
              number.int64Value > 0 else {
            throw FinanceError.invalidExchangeRate("Der Wechselkurs liegt außerhalb des gültigen Bereichs.")
        }
        scaledValue = number.int64Value
    }

    static func derived(
        originalMinor: Int64,
        originalCurrency: String,
        bookedMinor: Int64,
        bookedCurrency: String
    ) throws -> ExchangeRate {
        guard originalMinor != 0, bookedMinor != 0 else {
            throw FinanceError.invalidExchangeRate("Für eine Währungsumrechnung sind zwei Beträge ungleich null erforderlich.")
        }
        let originalMajor = decimalMagnitude(originalMinor)
            / Decimal(Money.minorUnitFactor(for: originalCurrency))
        let bookedMajor = decimalMagnitude(bookedMinor)
            / Decimal(Money.minorUnitFactor(for: bookedCurrency))
        var rate = bookedMajor / originalMajor
        var scale = Decimal(Self.scale)
        var scaled = Decimal()
        NSDecimalMultiply(&scaled, &rate, &scale, .bankers)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        return try ExchangeRate(scaledValue: NSDecimalNumber(decimal: rounded).int64Value)
    }

    func convertedMinor(
        originalMinor: Int64,
        originalCurrency: String,
        bookedCurrency: String
    ) throws -> Int64 {
        var originalMajor = Decimal(originalMinor)
            / Decimal(Money.minorUnitFactor(for: originalCurrency))
        var rate = Decimal(scaledValue) / Decimal(Self.scale)
        var bookedMajor = Decimal()
        NSDecimalMultiply(&bookedMajor, &originalMajor, &rate, .bankers)
        var factor = Decimal(Money.minorUnitFactor(for: bookedCurrency))
        var bookedMinor = Decimal()
        NSDecimalMultiply(&bookedMinor, &bookedMajor, &factor, .bankers)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &bookedMinor, 0, .bankers)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber,
              number.compare(NSNumber(value: Int64.max)) != .orderedDescending,
              number.compare(NSNumber(value: Int64.min)) != .orderedAscending else {
            throw FinanceError.invalidExchangeRate("Der umgerechnete Betrag liegt außerhalb des gültigen Bereichs.")
        }
        return number.int64Value
    }

    var formatted: String {
        (Decimal(scaledValue) / Decimal(Self.scale)).formatted(
            .number
                .locale(Locale(identifier: "de_DE"))
                .precision(.fractionLength(0...8))
        )
    }

    private static func decimalMagnitude(_ value: Int64) -> Decimal {
        let decimal = Decimal(value)
        return decimal < 0 ? -decimal : decimal
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
    case invalidImportResolution(String)
    case qifPackageRequiresPackageImport
    case invalidQIFPackage
    case invalidBankStatement(String)
    case invalidBackup
    case protectedTransaction
    case protectedBulkEdit
    case reconciliationDifference(Int64)
    case invalidIBAN
    case invalidPaymentTransition
    case duplicatePaymentOrder
    case invalidDirectDebit(String)
    case duplicateDirectDebitOrder
    case invalidPaymentBatch(String)
    case duplicatePaymentBatch
    case invalidPaymentStatusReport(String)
    case invalidPaymentInstructionImport(String)
    case invalidStandingOrder(String)
    case inactiveStandingOrder
    case standingOrderRunFinalized
    case invalidQuantity(String)
    case insufficientQuantity
    case allocationMismatch(Int)
    case invalidLoanTerms(String)
    case invalidVAT(String)
    case invalidExchangeRate(String)

    var errorDescription: String? {
        switch self {
        case .invalidAmount(let value): "„\(value)“ ist kein gültiger Betrag."
        case .splitMismatch(let expected, let actual):
            "Die Splits ergeben \(Money(minorUnits: actual).formatted), erwartet sind \(Money(minorUnits: expected).formatted)."
        case .missingAccount: "Bitte wähle ein Konto."
        case .database(let message): "Datenbankfehler: \(message)"
        case .duplicateImport: "Diese Importdatei wurde bereits übernommen."
        case .invalidImportResolution(let reason):
            "Die Importentscheidung ist nicht mehr gültig: \(reason)"
        case .qifPackageRequiresPackageImport:
            "Die Datei enthält mehrere Konten oder zusätzliche QIF-Bereiche. Bitte verwende den Mehrkonten-Paketimport."
        case .invalidQIFPackage: "Das QIF-Paket enthält keine importierbaren Konten."
        case .invalidBankStatement(let message):
            "Der OFX/QFX-Kontoauszug ist ungültig: \(message)"
        case .invalidBackup: "Die Sicherungsdatei ist ungültig."
        case .protectedTransaction: "Eine abgeglichene Buchung ist gegen unbeabsichtigte Änderungen geschützt."
        case .protectedBulkEdit:
            "Die Auswahl enthält abgeglichene Buchungen, Umbuchungen oder Splitbuchungen. Es wurde nichts geändert."
        case .reconciliationDifference(let value):
            "Der Kontoabgleich hat noch eine Differenz von \(Money(minorUnits: value).formatted)."
        case .invalidIBAN: "Die IBAN-Prüfsumme ist ungültig."
        case .invalidPaymentTransition: "Dieser Zahlungsstatus darf nicht in den gewünschten Zustand wechseln."
        case .duplicatePaymentOrder: "Dieser Zahlungsauftrag wurde mit derselben Idempotenzkennung bereits angelegt."
        case .invalidDirectDebit(let message):
            "Die Lastschrift ist ungültig: \(message)"
        case .duplicateDirectDebitOrder:
            "Diese Lastschrift wurde mit derselben Idempotenzkennung bereits angelegt."
        case .invalidPaymentBatch(let message):
            "Der Sammler ist ungültig: \(message)"
        case .duplicatePaymentBatch:
            "Dieser Sammler wurde mit derselben Idempotenzkennung bereits angelegt."
        case .invalidPaymentStatusReport(let message):
            "Der pain.002-Statusbericht ist ungültig: \(message)"
        case .invalidPaymentInstructionImport(let message):
            "Der Zahlungsauftragsimport ist ungültig: \(message)"
        case .invalidStandingOrder(let message): "Der Dauerauftrag ist ungültig: \(message)"
        case .inactiveStandingOrder: "Nur aktive Daueraufträge können vorbereitet oder übersprungen werden."
        case .standingOrderRunFinalized:
            "Diese Dauerauftragsfälligkeit wurde bereits endgültig verarbeitet."
        case .invalidQuantity(let value): "„\(value)“ ist keine gültige Stückzahl."
        case .insufficientQuantity: "Der Verkauf würde einen negativen Bestand erzeugen."
        case .allocationMismatch(let basisPoints):
            "Die Vermögensklassen ergeben \(Decimal(basisPoints) / 100) %, erforderlich sind exakt 100 %."
        case .invalidLoanTerms(let message):
            "Der Tilgungsplan ist ungültig: \(message)"
        case .invalidVAT(let message):
            "Mehrwertsteuerfehler: \(message)"
        case .invalidExchangeRate(let message):
            "Währungsfehler: \(message)"
        }
    }
}
