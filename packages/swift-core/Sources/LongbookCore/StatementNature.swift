// What comes round by its nature: an insurer, a domain, a bill, a bank's own mandate mark. The
// statement rules say these make a commitment even when seen once, and the device holds them to it,
// so an answer that overlooks one can't lose it. Pure, and tested.
import Foundation

public enum StatementNature: Equatable, Sendable {
    /// Yearly unless its lines show another rhythm.
    case insurance, domain
    /// Monthly, so the recency rule still applies.
    case bill, mandate

    public var isYearly: Bool { self == .insurance || self == .domain }

    /// What one line is, by its name, its printed words and its category. Money in is no commitment.
    public static func of(name: String, line: String, tag: String?) -> StatementNature? {
        let text = "\(name) \(line) \(tag ?? "")".lowercased()
        if text.contains("refund") || text.contains("reversal") || text.contains("rvsl") || text.contains("payout") { return nil }
        let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let isFund = !words.isDisjoint(with: fundWords)
        if !isFund, insurerParts.contains(where: text.contains) || !words.isDisjoint(with: insurerWords) { return .insurance }
        if domainParts.contains(where: text.contains) || words.contains("domain") { return .domain }
        // A person's name can read as a bill's word, so a payment to someone is never one by words.
        if !name.lowercased().hasPrefix("payment ") {
            if billParts.contains(where: text.contains) || !words.isDisjoint(with: billWords) { return .bill }
            if text.range(of: #"\brent\b(?! a\b| the\b)"#, options: .regularExpression) != nil { return .bill }
        }
        return hasMandateMark(line) ? .mandate : nil
    }

    /// Whether the printed line carries the bank's own mark of a standing payment.
    public static func hasMandateMark(_ line: String) -> Bool {
        let printed = line.lowercased()
        return mandateParts.contains(where: printed.contains)
            || !Set(printed.split(whereSeparator: { !$0.isLetter }).map(String.init)).isDisjoint(with: mandateWords)
    }

    // Banks run words together ("FUTUREGENERALILIFEINS"), so distinctive names match inside a word.
    private static let insurerParts = [
        "insurance", "insurer", "lombard", "generali", "prudential", "licindia", "lic of india", "hdfc life", "hdfclife", "hdfc ergo", "hdfcergo",
        "sbi life", "sbilife", "sbi general", "tata aia", "tataaia", "tata aig", "tataaig", "max life", "maxlife", "bajaj allianz", "bajajallianz",
        "star health", "starhealth", "niva bupa", "nivabupa", "care health ins", "manipal cigna", "aditya birla health", "policybazaar", "godigit", "go digit",
        "geico", "allstate", "state farm", "statefarm",
    ]
    private static let insurerWords: Set<String> = ["lic", "licp", "acko", "aviva", "axa"]
    private static let fundWords: Set<String> = ["mutual", "mf", "amc", "sip", "fund", "funds"]
    private static let domainParts = ["namecheap", "name-cheap", "godaddy", "porkbun", "gandi.net"]
    private static let billParts = ["postpaid", "broadband", "electricity", "bescom", "gas bill", "water bill", "school fee", "tuition", "society maintenance", "apartment maintenance"]
    private static let billWords: Set<String> = ["emi", "emis", "landlord"]
    private static let mandateParts = ["autopay", "mandate", "standing instruction", "me dc si", "ach dr", "ach-dr", "achdr"]
    private static let mandateWords: Set<String> = ["nach", "ecs"]
}
