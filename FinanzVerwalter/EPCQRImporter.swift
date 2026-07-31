import Foundation
import ImageIO
import Vision

enum EPCQRImportError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        guard case .invalid(let message) = self else { return nil }
        return "Der EPC-QR-Code ist ungültig: \(message)"
    }
}

struct EPCQRPayload: Equatable, Sendable {
    let version: String
    let characterSet: Int
    let bic: String
    let recipientName: String
    let iban: String
    let amountMinor: Int64?
    let purposeCode: String
    let creditorReference: String
    let remittanceText: String
    let information: String

    var paymentPurpose: String {
        creditorReference.isEmpty ? remittanceText : creditorReference
    }
}

enum EPCQRImporter {
    static let rulePackage = "EPC069-12-V3.1"
    private static let maximumImageBytes = 20 * 1_024 * 1_024
    private static let maximumDimension = 12_000

    static func parse(_ payload: String) throws -> EPCQRPayload {
        guard !payload.isEmpty, payload.utf8.count <= 1_024 else {
            throw invalid("Die Nutzlast ist leer oder ungewöhnlich groß.")
        }
        guard !payload.hasSuffix("\n"), !payload.hasSuffix("\r") else {
            throw invalid("Nach dem letzten befüllten Feld ist kein Zeilenende zulässig.")
        }
        let normalized = payload.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.contains("\r") else {
            throw invalid("Als Feldtrenner sind nur LF oder CRLF zulässig.")
        }
        var fields = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count >= 7, fields.count <= 12 else {
            throw invalid("Der Datensatz muss 7 bis 12 geordnete Felder enthalten.")
        }
        fields.append(contentsOf: repeatElement("", count: 12 - fields.count))
        guard fields[0] == "BCD" else { throw invalid("Der Service-Tag muss BCD lauten.") }
        guard fields[1] == "001" || fields[1] == "002" else {
            throw invalid("Unterstützt werden nur die EPC-Versionen 001 und 002.")
        }
        guard let characterSet = Int(fields[2]), (1...8).contains(characterSet) else {
            throw invalid("Die Zeichensatzkennung muss zwischen 1 und 8 liegen.")
        }
        guard let encoded = payload.data(using: encoding(characterSet)),
              encoded.count <= 331 else {
            throw invalid("Die Nutzlast passt nicht in den deklarierten Zeichensatz oder überschreitet 331 Byte.")
        }
        guard fields[3] == "SCT" else {
            throw invalid("Der Identifikationscode muss SCT lauten.")
        }
        let bic = fields[4].uppercased()
        if fields[1] == "001" && bic.isEmpty {
            throw invalid("Version 001 verlangt die BIC des Empfängerinstituts.")
        }
        guard bic.isEmpty || bic.range(
            of: "^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$", options: .regularExpression
        ) != nil else { throw invalid("Die Empfänger-BIC ist ungültig.") }

        let recipientName = try bounded(fields[5], name: "Empfängername", maximum: 70, required: true)
        let iban = IBANValidator.normalized(fields[6])
        guard IBANValidator.isValid(iban), iban.count <= 34 else {
            throw invalid("Die Empfänger-IBAN ist ungültig.")
        }
        let amountMinor = try amount(fields[7])
        let purposeCode = try purposeCode(fields[8])
        let reference = try bounded(fields[9], name: "strukturierte Referenz", maximum: 35)
        let remittance = try bounded(fields[10], name: "Verwendungszweck", maximum: 140)
        guard reference.isEmpty || remittance.isEmpty else {
            throw invalid("Strukturierte Referenz und freier Verwendungszweck dürfen nicht zugleich befüllt sein.")
        }
        if reference.uppercased().hasPrefix("RF") && !validRFReference(reference) {
            throw invalid("Die RF-Gläubigerreferenz hat keine gültige ISO-11649-Prüfsumme.")
        }
        let information = try bounded(fields[11], name: "Empfängerhinweis", maximum: 70)
        return EPCQRPayload(
            version: fields[1], characterSet: characterSet, bic: bic,
            recipientName: recipientName, iban: iban, amountMinor: amountMinor,
            purposeCode: purposeCode, creditorReference: reference,
            remittanceText: remittance, information: information
        )
    }

    static func decodeImage(at url: URL) throws -> EPCQRPayload {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0, fileSize <= maximumImageBytes else {
            throw invalid("Die Bilddatei fehlt, ist leer oder größer als 20 MB.")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              cgImage.width <= maximumDimension, cgImage.height <= maximumDimension else {
            throw invalid("Das Bildformat oder die Bildabmessungen werden nicht unterstützt.")
        }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let payloads = (request.results ?? []).compactMap(\.payloadStringValue)
        guard payloads.count == 1 else {
            throw invalid(payloads.isEmpty
                ? "Im Bild wurde kein lesbarer QR-Code gefunden."
                : "Das Bild enthält mehrere QR-Codes; bitte wähle einen eindeutigen Ausschnitt.")
        }
        return try parse(payloads[0])
    }

    private static func bounded(
        _ value: String, name: String, maximum: Int, required: Bool = false
    ) throws -> String {
        guard !value.contains("\n"), !value.contains("\r"), value.count <= maximum,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !required || !value.isEmpty else {
            throw invalid("\(name) fehlt oder überschreitet \(maximum) Zeichen.")
        }
        return value
    }

    private static func amount(_ value: String) throws -> Int64? {
        guard !value.isEmpty else { return nil }
        guard value.hasPrefix("EUR") else { throw invalid("Der Betrag muss mit EUR beginnen.") }
        let decimal = String(value.dropFirst(3))
        guard decimal.range(of: "^[0-9]{1,9}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let money = try? Money(parsing: decimal.replacingOccurrences(of: ".", with: ","), currency: "EUR"),
              money.minorUnits >= 1, money.minorUnits <= 99_999_999_999 else {
            throw invalid("Der Betrag muss zwischen EUR0.01 und EUR999999999.99 liegen.")
        }
        return money.minorUnits
    }

    private static func purposeCode(_ value: String) throws -> String {
        guard value.isEmpty || value.range(
            of: "^[A-Z0-9]{1,4}$", options: .regularExpression
        ) != nil else { throw invalid("Der SEPA-Zweckcode ist ungültig.") }
        return value
    }

    private static func validRFReference(_ value: String) -> Bool {
        let normalized = value.uppercased().filter { !$0.isWhitespace }
        guard normalized.range(of: "^RF[0-9]{2}[A-Z0-9]{1,21}$", options: .regularExpression) != nil else {
            return false
        }
        let rearranged = String(normalized.dropFirst(4)) + String(normalized.prefix(4))
        var remainder = 0
        for scalar in rearranged.unicodeScalars {
            let piece: String
            if CharacterSet.decimalDigits.contains(scalar) {
                piece = String(scalar)
            } else {
                piece = String(Int(scalar.value) - 55)
            }
            for digit in piece { remainder = (remainder * 10 + Int(String(digit))!) % 97 }
        }
        return remainder == 1
    }

    private static func encoding(_ identifier: Int) -> String.Encoding {
        if identifier == 1 { return .utf8 }
        let coreFoundationValues: [UInt32] = [
            0, 0, 0x0201, 0x0202, 0x0204, 0x0205, 0x0207, 0x020A, 0x020F
        ]
        return String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(coreFoundationValues[identifier])
            )
        )
    }

    private static func invalid(_ message: String) -> EPCQRImportError {
        .invalid(message)
    }
}
