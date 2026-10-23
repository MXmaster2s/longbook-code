// The banks a person here is likely to use, for setup's second question: a name, the
// short word an account is called by, and the colour its mark wears. No logo ships;
// a monogram in the bank's colour stands where one would.
import Foundation

public struct Bank: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// The word an account takes: "HDFC savings", "SBI credit card".
    public let short: String
    /// Two or three letters for the mark.
    public let monogram: String
    /// The mark's colour as hex, and whether its letters read dark on it.
    public let colour: String
    public let darkInk: Bool
    public let popular: Bool

    public init(id: String, name: String, short: String, monogram: String, colour: String, darkInk: Bool = false, popular: Bool = false) {
        self.id = id
        self.name = name
        self.short = short
        self.monogram = monogram
        self.colour = colour
        self.darkInk = darkInk
        self.popular = popular
    }
}

/// The kinds of account a bank holds for a person, as setup offers them.
public enum BankAccountKind: String, CaseIterable, Sendable {
    case savings = "Savings"
    case current = "Current"
    case credit = "Credit card"
    case debit = "Debit card"

    /// The word after the bank's short name.
    public var word: String {
        switch self {
        case .savings: "savings"
        case .current: "current"
        case .credit: "credit card"
        case .debit: "debit card"
        }
    }

    /// The library's account tag for the kind.
    public var tag: String {
        switch self {
        case .savings, .current: "bank account"
        case .credit: "credit card"
        case .debit: "debit card"
        }
    }
}

public enum BankDirectory {
    public static let banks: [Bank] = [
        Bank(id: "hdfc", name: "HDFC Bank", short: "HDFC", monogram: "HD", colour: "#004C8F", popular: true),
        Bank(id: "icici", name: "ICICI Bank", short: "ICICI", monogram: "IC", colour: "#F58220", popular: true),
        Bank(id: "sbi", name: "State Bank of India", short: "SBI", monogram: "SBI", colour: "#22409A", popular: true),
        Bank(id: "axis", name: "Axis Bank", short: "Axis", monogram: "AX", colour: "#97144D", popular: true),
        Bank(id: "kotak", name: "Kotak Mahindra Bank", short: "Kotak", monogram: "KO", colour: "#ED1C24", popular: true),
        Bank(id: "idfc", name: "IDFC FIRST Bank", short: "IDFC First", monogram: "ID", colour: "#9C1D26", popular: true),
        Bank(id: "yes", name: "Yes Bank", short: "Yes Bank", monogram: "YES", colour: "#00204E", popular: true),
        Bank(id: "indusind", name: "IndusInd Bank", short: "IndusInd", monogram: "IN", colour: "#98272A", popular: true),
        Bank(id: "bob", name: "Bank of Baroda", short: "BoB", monogram: "BOB", colour: "#F26522"),
        Bank(id: "pnb", name: "Punjab National Bank", short: "PNB", monogram: "PNB", colour: "#A20E37"),
        Bank(id: "canara", name: "Canara Bank", short: "Canara", monogram: "CA", colour: "#0E6DB5"),
        Bank(id: "union", name: "Union Bank of India", short: "Union Bank", monogram: "UB", colour: "#1E3A8A"),
        Bank(id: "boi", name: "Bank of India", short: "BoI", monogram: "BOI", colour: "#E87722"),
        Bank(id: "indian", name: "Indian Bank", short: "Indian Bank", monogram: "IB", colour: "#0E4C92"),
        Bank(id: "central", name: "Central Bank of India", short: "Central Bank", monogram: "CB", colour: "#C8102E"),
        Bank(id: "federal", name: "Federal Bank", short: "Federal", monogram: "FB", colour: "#0B5394"),
        Bank(id: "rbl", name: "RBL Bank", short: "RBL", monogram: "RBL", colour: "#1F4E9C"),
        Bank(id: "au", name: "AU Small Finance Bank", short: "AU", monogram: "AU", colour: "#F26F21"),
        Bank(id: "bandhan", name: "Bandhan Bank", short: "Bandhan", monogram: "BA", colour: "#E31E24"),
        Bank(id: "idbi", name: "IDBI Bank", short: "IDBI", monogram: "IDBI", colour: "#00875A"),
        Bank(id: "sc", name: "Standard Chartered", short: "StanChart", monogram: "SC", colour: "#0072AA"),
        Bank(id: "hsbc", name: "HSBC", short: "HSBC", monogram: "HS", colour: "#DB0011"),
        Bank(id: "citi", name: "Citibank", short: "Citi", monogram: "CI", colour: "#003B70"),
        Bank(id: "dbs", name: "DBS Bank", short: "DBS", monogram: "DBS", colour: "#D71920"),
        Bank(id: "deutsche", name: "Deutsche Bank", short: "Deutsche", monogram: "DB", colour: "#0018A8"),
        Bank(id: "amex", name: "American Express", short: "Amex", monogram: "AM", colour: "#006FCF"),
        Bank(id: "onecard", name: "OneCard", short: "OneCard", monogram: "ONE", colour: "#1B1B1B"),
        Bank(id: "chase", name: "Chase", short: "Chase", monogram: "CH", colour: "#117ACA"),
        Bank(id: "bofa", name: "Bank of America", short: "BofA", monogram: "BA", colour: "#E31837"),
        Bank(id: "wells", name: "Wells Fargo", short: "Wells Fargo", monogram: "WF", colour: "#D71E28"),
        Bank(id: "capitalone", name: "Capital One", short: "Capital One", monogram: "C1", colour: "#004977"),
        Bank(id: "barclays", name: "Barclays", short: "Barclays", monogram: "BC", colour: "#00AEEF"),
        Bank(id: "lloyds", name: "Lloyds Bank", short: "Lloyds", monogram: "LL", colour: "#006A4D"),
        Bank(id: "natwest", name: "NatWest", short: "NatWest", monogram: "NW", colour: "#5A287D"),
        Bank(id: "monzo", name: "Monzo", short: "Monzo", monogram: "MZ", colour: "#FF4F40"),
        Bank(id: "revolut", name: "Revolut", short: "Revolut", monogram: "RV", colour: "#191C1F"),
        Bank(id: "wise", name: "Wise", short: "Wise", monogram: "WI", colour: "#9FE870", darkInk: true),
        Bank(id: "n26", name: "N26", short: "N26", monogram: "N26", colour: "#36A18B"),
        Bank(id: "ing", name: "ING", short: "ING", monogram: "ING", colour: "#FF6200"),
        Bank(id: "bnp", name: "BNP Paribas", short: "BNP", monogram: "BNP", colour: "#00915A"),
        Bank(id: "cba", name: "Commonwealth Bank", short: "CommBank", monogram: "CBA", colour: "#FFCC00", darkInk: true),
        Bank(id: "anz", name: "ANZ", short: "ANZ", monogram: "ANZ", colour: "#007DBA"),
        Bank(id: "nab", name: "NAB", short: "NAB", monogram: "NAB", colour: "#C20000"),
        Bank(id: "westpac", name: "Westpac", short: "Westpac", monogram: "WP", colour: "#DA1710"),
        Bank(id: "td", name: "TD Bank", short: "TD", monogram: "TD", colour: "#54B848"),
        Bank(id: "rbc", name: "RBC", short: "RBC", monogram: "RBC", colour: "#005DAA"),
        Bank(id: "scotia", name: "Scotiabank", short: "Scotia", monogram: "SB", colour: "#EC111A"),
        Bank(id: "ocbc", name: "OCBC", short: "OCBC", monogram: "OC", colour: "#E4002B"),
        Bank(id: "uob", name: "UOB", short: "UOB", monogram: "UOB", colour: "#005EB8"),
        Bank(id: "enbd", name: "Emirates NBD", short: "Emirates NBD", monogram: "EN", colour: "#0E4C92"),
        Bank(id: "adcb", name: "ADCB", short: "ADCB", monogram: "AD", colour: "#C8102E"),
        Bank(id: "mashreq", name: "Mashreq", short: "Mashreq", monogram: "MQ", colour: "#F36F21"),
    ]

    public static var popular: [Bank] { banks.filter(\.popular) }

    public static func bank(id: String) -> Bank? { banks.first { $0.id == id } }

    /// Banks whose name or short word carries the typed letters.
    public static func search(_ query: String) -> [Bank] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return banks.filter { $0.name.lowercased().contains(q) || $0.short.lowercased().contains(q) || $0.monogram.lowercased() == q }
    }

    /// The bank an account name starts with, and what follows it: "HDFC credit card" is
    /// HDFC and "credit card".
    public static func split(accountName: String) -> (bank: Bank, rest: String)? {
        let name = accountName.trimmingCharacters(in: .whitespaces)
        let lower = name.lowercased()
        let hit = banks
            .filter { lower.hasPrefix($0.short.lowercased() + " ") || lower == $0.short.lowercased() || lower.hasPrefix($0.name.lowercased()) }
            .max { $0.short.count < $1.short.count }
        guard let hit else { return nil }
        let head = lower.hasPrefix(hit.name.lowercased()) ? hit.name.count : hit.short.count
        let rest = name.dropFirst(head).trimmingCharacters(in: .whitespaces)
        return (hit, rest)
    }

    /// The apps and wallets money moves through, beside the banks.
    public static let apps: [(name: String, tag: String)] = [
        ("Google Pay", "upi"), ("PhonePe", "upi"), ("Paytm", "upi"), ("BHIM", "upi"), ("CRED", "upi"),
        ("Amazon Pay", "wallet"), ("Apple Pay", "wallet"), ("Cash", "wallet"),
    ]
}
