// The other side of a statement's transfers and card payments, as Accounts and People would
// hold it: an account the way the owner says it ("HDFC savings ••4417"), a person by the
// name printed, each matched loosely against what the book and the statement already name.
import Foundation

public enum StatementCounterparts {
    /// An account a line prints on its other side, and the person it belongs to when the
    /// line names one beside it.
    public struct Account: Equatable, Sendable {
        public var name: String
        public var person: String?

        public init(name: String, person: String? = nil) {
            self.name = name
            self.person = person
        }
    }

    /// The accounts and people the charges name on their other side, new to the book.
    public struct Found: Equatable, Sendable {
        public var accounts: [Account]
        public var people: [String]

        public init(accounts: [Account] = [], people: [String] = []) {
            self.accounts = accounts
            self.people = people
        }

        public var accountNames: [String] { accounts.map(\.name) }
    }

    /// The account a line prints on its other side, as Accounts names it: the other side
    /// itself when that is an account, else the bank account printed beside a person, with
    /// the person. Nil when the line prints none.
    public static func account(on charge: StatementCloud.Charge) -> Account? {
        if charge.counterpartKind == "account", let raw = charge.counterpart, let name = accountName(raw) {
            return Account(name: name, person: nil)
        }
        guard let bank = charge.counterpartBank, let name = accountName(bank) else { return nil }
        let person = charge.counterpartKind == "person" ? charge.counterpart.flatMap(personName) : nil
        // With no digits printed, the person is what tells two accounts at one bank apart.
        if let person, !name.contains("••") { return Account(name: "\(person), \(name)", person: person) }
        return Account(name: name, person: person)
    }

    /// Every counterpart once, in the order the lines name them, leaving out any account or
    /// person `knownAccounts` or `knownPeople` already holds. An account seen first without
    /// its person takes the person a later line prints beside it.
    public static func found(in charges: [StatementCloud.Charge], knownAccounts: [String], knownPeople: [String]) -> Found {
        var out = Found()
        for charge in charges {
            if let account = account(on: charge) {
                if let at = out.accounts.firstIndex(where: { sameAccount($0.name, account.name) }) {
                    if out.accounts[at].person == nil { out.accounts[at].person = account.person }
                } else if !knownAccounts.contains(where: { sameAccount($0, account.name) }) {
                    out.accounts.append(account)
                }
            }
            guard charge.counterpartKind == "person", let raw = charge.counterpart, let name = personName(raw),
                  !(knownPeople + out.people).contains(where: { nameKey($0) == nameKey(name) }) else { continue }
            out.people.append(name)
        }
        return out
    }

    /// Words a bank prints around a transfer that are no part of the account's name.
    static let noise: Set<String> = [
        "trf", "transfer", "to", "from", "by", "via", "neft", "imps", "rtgs", "upi", "pymt", "payment", "pmt",
        "bill", "cred", "fund", "funds", "ac", "acct", "account", "no", "p2a", "p2p",
    ]
    /// A bank's word for the kind of account, as the owner says it.
    static let kinds: [String: String] = [
        "sav": "savings", "savings": "savings", "saving": "savings", "sb": "savings",
        "ca": "current", "cur": "current", "curr": "current", "current": "current",
        "cc": "card", "card": "card", "credit": "card", "wallet": "wallet", "loan": "loan",
    ]
    /// Banks known by their letters, kept in capitals.
    static let acronyms: Set<String> = [
        "HDFC", "SBI", "ICICI", "IDFC", "PNB", "BOB", "HSBC", "RBL", "IDBI", "UCO", "AU", "DBS", "IOB", "BOI",
        "CUB", "KVB", "CSB", "DCB", "AMEX", "UBI", "TSB", "RBS", "NAB", "ANZ", "UOB", "OCBC",
    ]

    /// An account as the owner would say it: bank, kind, then the last four after "••".
    /// "TRF TO HDFC SAV XX4417" is "HDFC savings ••4417". Nil when nothing is left to name.
    public static func accountName(_ raw: String) -> String? {
        let numbers = raw.matches(of: #/\d+/#).map { String($0.output) }.filter { $0.count >= 4 }
        let lastFour = numbers.last.map { String($0.suffix(4)) }
        var bank: [String] = []
        var kind: [String] = []
        for token in words(raw) where !token.contains(where: \.isNumber) && !noise.contains(token.lowercased()) {
            if let said = kinds[token.lowercased()] {
                if !kind.contains(said) { kind.append(said) }
            } else if bank.count < 4 {
                bank.append(cased(token, keepingLetters: acronyms.contains(token.uppercased()) || token.count <= 3))
            }
        }
        let named = (bank + kind).joined(separator: " ")
        switch (named.isEmpty, lastFour) {
        case (true, nil): return nil
        case (true, let four?): return "Account ••\(four)"
        case (false, nil): return named
        case (false, let four?): return "\(named) ••\(four)"
        }
    }

    /// A person as printed, without the transfer's own words or any number or handle:
    /// "UPI/RAMESH K" is "Ramesh K". Nil when no letters are left.
    public static func personName(_ raw: String) -> String? {
        let kept = words(raw).filter { token in
            !token.contains(where: \.isNumber) && !token.contains("@") && !noise.contains(token.lowercased())
        }
        let name = kept.prefix(4).map { cased($0, keepingLetters: false) }.joined(separator: " ")
        return name.contains(where: \.isLetter) ? name : nil
    }

    /// Two account names for one account: the same letters and digits, or the same bank
    /// word and the same last four ("HDFC 4417" and "HDFC savings ••4417").
    public static func sameAccount(_ a: String, _ b: String) -> Bool {
        let key = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        if key(a) == key(b) { return true }
        let four = { (s: String) in s.matches(of: #/\d{4,}/#).last.map { String($0.output.suffix(4)) } }
        let first = { (s: String) in words(s).first { !$0.contains(where: \.isNumber) && !noise.contains($0.lowercased()) }?.lowercased() }
        guard let x = four(a), x == four(b), let bank = first(a) else { return false }
        return bank == first(b)
    }

    private static func words(_ raw: String) -> [String] {
        raw.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "&" || $0 == "@" || $0 == "." || $0 == "'") })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }

    /// A word printed in capitals reads as a name ("RAMESH" is "Ramesh"); a bank's letters stay.
    private static func cased(_ word: String, keepingLetters: Bool) -> String {
        guard word == word.uppercased(), word.contains(where: \.isLetter), !keepingLetters else { return word }
        return word.prefix(1) + word.dropFirst().lowercased()
    }
}

extension StatementCloud.Prepared {
    /// The counterparts this statement names that the book holds neither as an account nor
    /// as a person; the statement's own account is never one.
    public func counterparts(knownAccounts: [String], knownPeople: [String]) -> StatementCounterparts.Found {
        StatementCounterparts.found(in: charges, knownAccounts: knownAccounts + [account], knownPeople: knownPeople)
    }
}
