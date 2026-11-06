// Data minimization by design (Financial-Memory-Data-Policy). Mirrors
// packages/core/src/domain/dataPolicy.ts in BEHAVIOUR — same patterns, same refusal message,
// same conformance fixtures. The memory has no field for a card number, CVV, expiry, or PIN
// (see Vault.swift); this is the second enforcement layer, scanning free text before a write.
import Foundation

enum DataPolicyViolationKind: String {
    case cardNumber = "card_number"
    case expiry
    case cvv
    case iban
    case secret
}

struct DataPolicyViolation {
    let kind: DataPolicyViolationKind
    let match: String
}

let dataPolicyRefusal =
    "longbook is designed not to hold this. If this data ever leaked, you'd want it not to have been here."

private let kindWords: [DataPolicyViolationKind: String] = [
    .cardNumber: "a card number", .expiry: "a card expiry date", .cvv: "a card security code",
    .iban: "an IBAN", .secret: "a password, PIN or key",
]

/// The refusal with what was found and where, never the value itself, and how to file again,
/// so the AI that wrote it can fix it. Mirrors policyFix in dataPolicy.ts.
func policyRefusal(_ violation: DataPolicyViolation, field: String? = nil) -> String {
    let place = field.map { " in \($0)" } ?? ""
    return dataPolicyRefusal + " Found what looks like \(kindWords[violation.kind] ?? "a secret")\(place)."
        + " Remove it (a card's last four digits are fine) and file again."
}

/// Luhn checksum — same check card issuers use, so a false-positive digit run this long and
/// this well-formed is vanishingly rare.
private func passesLuhn(_ digits: String) -> Bool {
    var sum = 0
    var double = false
    for ch in digits.reversed() {
        guard var d = ch.wholeNumberValue else { return false }
        if double {
            d *= 2
            if d > 9 { d -= 9 }
        }
        sum += d
        double.toggle()
    }
    return sum % 10 == 0
}

private let cardLikeRun = try! NSRegularExpression(pattern: #"\b(?:\d[ -]?){12,18}\d\b"#)
private let expiryKeyword = try! NSRegularExpression(pattern: #"\b(exp(iry|ires)?|valid\s*thru|valid\s*to)\b"#, options: .caseInsensitive)
private let expiryPattern = try! NSRegularExpression(pattern: #"\b(0[1-9]|1[0-2])\s?/\s?\d{2}\b"#)
private let cvvKeyword = try! NSRegularExpression(pattern: #"\b(cvv2?|cvc2?|security\s*code|card\s*verification)\b"#, options: .caseInsensitive)
private let cvvNearbyDigits = try! NSRegularExpression(pattern: #"\b\d{3,4}\b"#)
private let ibanLike = try! NSRegularExpression(pattern: #"\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b"#)
private let secretKeyValue = try! NSRegularExpression(
    pattern: #"\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|pin)\s*[:=]\s*\S+"#,
    options: .caseInsensitive
)

private let nearbyWindow = 40

private func matches(_ re: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
    re.matches(in: text, range: NSRange(text.startIndex..., in: text))
}

private func substring(_ text: String, _ range: NSRange) -> String {
    guard let r = Range(range, in: text) else { return "" }
    return String(text[r])
}

private func withinWindow(_ text: String, _ location: Int, _ keyword: NSRegularExpression) -> Bool {
    let nsText = text as NSString
    let start = max(0, location - nearbyWindow)
    let end = min(nsText.length, location + nearbyWindow)
    let window = nsText.substring(with: NSRange(location: start, length: end - start))
    return keyword.firstMatch(in: window, range: NSRange(location: 0, length: (window as NSString).length)) != nil
}

/// Scan one string for a data-policy violation. Returns the first hit, or nil if the text is
/// clean. Order mirrors dataPolicy.ts: card number, then IBAN, then secret, then expiry, then CVV.
func scanText(_ text: String) -> DataPolicyViolation? {
    guard !text.isEmpty else { return nil }

    for m in matches(cardLikeRun, in: text) {
        let raw = substring(text, m.range)
        let digits = raw.filter(\.isNumber)
        if digits.count >= 13, digits.count <= 19, passesLuhn(digits) {
            return DataPolicyViolation(kind: .cardNumber, match: raw)
        }
    }

    if let m = matches(ibanLike, in: text).first {
        return DataPolicyViolation(kind: .iban, match: substring(text, m.range))
    }

    if let m = secretKeyValue.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
        return DataPolicyViolation(kind: .secret, match: substring(text, m.range))
    }

    for m in matches(expiryPattern, in: text) where withinWindow(text, m.range.location, expiryKeyword) {
        return DataPolicyViolation(kind: .expiry, match: substring(text, m.range))
    }

    for m in matches(cvvNearbyDigits, in: text) where withinWindow(text, m.range.location, cvvKeyword) {
        return DataPolicyViolation(kind: .cvv, match: substring(text, m.range))
    }

    return nil
}

/// Scan a set of an entity's free-text field values and return every violation found.
func scanFields(_ fields: [String: String?]) -> [DataPolicyViolation] {
    fields.values.compactMap { $0 }.compactMap(scanText)
}
