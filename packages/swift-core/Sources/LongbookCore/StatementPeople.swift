// A person must be a person: what a statement's reader calls one is checked here on the
// device, against the banks the IFSC table names and the words a business prints, and a name
// is looked at beside the holder's. Pure, and tested.
import Foundation

public enum StatementPeople {
    /// Words a business prints and a person's name does not.
    static let companyWords: Set<String> = [
        "pvt", "private", "ltd", "limited", "llp", "llc", "inc", "corp", "corporation", "company", "gmbh", "plc", "sons", "brothers", "bros",
        "bank", "finance", "finserv", "financial", "fintech", "insurance", "assurance", "securities", "broking", "mutual", "investments", "capital",
        "services", "service", "solutions", "systems", "technologies", "technology", "tech", "software", "consultants", "consultancy", "consulting",
        "associates", "agency", "agencies", "enterprises", "enterprise", "ventures", "holdings", "industries", "international", "global", "exports", "imports",
        "traders", "trading", "store", "stores", "mart", "supermarket", "shop", "shoppe", "electronics", "motors", "automobiles", "garments", "textiles",
        "jewellers", "construction", "constructions", "builders", "developers", "realty", "properties", "infra", "logistics", "couriers", "travels",
        "airlines", "telecom", "broadband", "communications", "restaurant", "cafe", "hotel", "hotels", "bakery", "foods", "dairy", "caterers", "salon", "fitness",
        "hospital", "clinic", "pharmacy", "medical", "medicals", "diagnostics", "laboratories", "labs",
        "school", "college", "university", "institute", "academy", "foundation", "trust", "society",
    ]

    /// Letters that mean a bank wherever they stand. A bare "Kotak" is the bank; "Rajesh Kotak" is not.
    static let bankWords: Set<String> = ["hdfc", "icici", "sbi", "idfc", "idbi", "hsbc", "pnb", "rbl", "axis", "citibank", "paytm"]

    /// Banks whose whole name says so without the word "bank". "Bandhan" alone is a first name.
    static let bareBankNames: Set<String> = ["kotak", "kotak mahindra", "standard chartered"]

    /// Banks known by more words than the IFSC table says.
    private static let longerBankNames = ["Kotak Mahindra Bank", "Jammu and Kashmir Bank", "Punjab and Sind Bank"]

    private static let fillerWords: Set<String> = ["bank", "of", "and", "the"]

    /// Every bank's own words, without the filler, as a name's are compared.
    private static let bankNames: [Set<String>] = (Array(StatementLinePass.ifscBanks.values) + longerBankNames).map {
        Set(words($0)).subtracting(fillerWords)
    }

    private static func words(_ name: String) -> [String] {
        name.lowercased().replacingOccurrences(of: "&", with: " and ").split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// Whether a name reads as a bank or a company: a company word, a bank's letters, a bank's
    /// whole name, or a bank's words joined by "and", as "Mahindra And Kotak" or, cut off, "Punjab
    /// And Sin". Otherwise words count whole, so a person's cut-off name stays a person's.
    public static func readsAsCompany(_ name: String) -> Bool {
        let said = words(name)
        guard !said.isEmpty else { return false }
        if name.range(of: #"^\s*m/s\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if said.contains(where: { companyWords.contains($0) || bankWords.contains($0) }) { return true }
        if bareBankNames.contains(said.joined(separator: " ")) { return true }
        let own = Set(said).subtracting(fillerWords)
        guard said.contains("and"), !own.isEmpty else { return false }
        return bankNames.contains { bank in own.allSatisfy { word in bank.contains { close(word, $0) } } }
    }

    /// Whether a person's name shares a word with the holder's, whole or cut off, in any order:
    /// the holder spelled another way, or a relative, which only the holder can say. Initials
    /// say nothing. The holder's own name is not counted.
    public static func sharesWords(_ name: String, withHolder holder: String) -> Bool {
        guard nameKey(name) != nameKey(holder) else { return false }
        let others = StatementHolder.words(holder)
        return StatementHolder.words(name).contains { word in others.contains { close(word, $0) } }
    }

    /// One word whole, or one cut off from the other at three letters or more.
    private static func close(_ a: String, _ b: String) -> Bool {
        a == b || (min(a.count, b.count) >= 3 && (a.hasPrefix(b) || b.hasPrefix(a)))
    }
}
