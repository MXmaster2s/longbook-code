// The one rule for a transfer: its account and its counterpart account both belong to a
// person whose Relationship is Self. Nothing else is, whatever the line's words say.
// Applied from the data alone, so setting or clearing Self or an owner flips charges.
import Foundation

/// The person a statement belongs to, and how a name on a line is recognised as theirs.
public enum StatementHolder {
    static let titles: Set<String> = ["mr", "mrs", "ms", "miss", "shri", "smt", "sri", "mx"]

    /// The holder as the book would say it: no title in front, capitals read as a name.
    /// Nil when nothing readable is left.
    public static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var words = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while let first = words.first, titles.contains(first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            words.removeFirst()
        }
        let name = words.map { $0 == $0.uppercased() && $0.contains(where: \.isLetter) ? $0.prefix(1) + $0.dropFirst().lowercased() : $0 }
            .joined(separator: " ")
        return name.contains(where: \.isLetter) ? name : nil
    }

    /// The words of a name that can tell two people apart: letters only, no initials.
    static func words(_ name: String) -> Set<String> {
        Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 1 })
    }

    /// Whether two names are one person: the same name, or at least two words in common,
    /// in any order ("Rajesh K Sharma" and "Sharma Rajesh Kumar").
    public static func same(_ a: String, _ b: String) -> Bool {
        if !nameKey(a).isEmpty, nameKey(a) == nameKey(b) { return true }
        return words(a).intersection(words(b)).count >= 2
    }

    /// The name a book already holds for this person, else the name as printed.
    public static func resolve(_ holder: String, among names: [String]) -> String {
        names.first { nameKey($0) == nameKey(holder) } ?? names.first { same($0, holder) } ?? holder
    }
}

/// What the book already says about people and accounts, as far as the rule needs it.
public struct StatementBook: Equatable, Sendable {
    public struct Person: Equatable, Sendable {
        public var name: String
        public var tag: String?
        public init(name: String, tag: String? = nil) {
            self.name = name
            self.tag = tag
        }
    }

    public struct Account: Equatable, Sendable {
        public var name: String
        public var owner: String?
        public init(name: String, owner: String? = nil) {
            self.name = name
            self.owner = owner
        }
    }

    public var people: [Person]
    public var accounts: [Account]

    public init(people: [Person] = [], accounts: [Account] = []) {
        self.people = people
        self.accounts = accounts
    }

    /// The people and accounts of a raw vault; an account's owner by name.
    public init(raw: [String: Any]) {
        let members = raw["members"] as? [[String: Any]] ?? []
        let names = Dictionary(members.compactMap { row in
            (row["id"] as? String).flatMap { id in (row["name"] as? String).map { (id, $0) } }
        }, uniquingKeysWith: { first, _ in first })
        people = members.compactMap { row in
            (row["name"] as? String).map { Person(name: $0, tag: row["tag"] as? String) }
        }
        let rows = raw["accounts"] as? [[String: Any]] ?? []
        accounts = rows.compactMap { row in
            (row["name"] as? String).map { Account(name: $0, owner: (row["member_id"] as? String).flatMap { names[$0] }) }
        }
        // A name merged into a row reads as that row, after every name the book calls its own.
        people += members.flatMap { row in VaultPatch.mergedNames(of: row).map { Person(name: $0, tag: row["tag"] as? String) } }
        accounts += rows.flatMap { row in
            VaultPatch.mergedNames(of: row).map { Account(name: $0, owner: (row["member_id"] as? String).flatMap { names[$0] }) }
        }
    }

    /// A stored name as a person: itself while someone in People answers to it, else nil.
    public func person(_ name: String?) -> String? {
        guard let name, people.contains(where: { nameKey($0.name) == nameKey(name) }) else { return nil }
        return name
    }

    /// Whether a person is Self: tagged so in the book, or, with no tag yet, the holder the
    /// import is about to tag so.
    func isSelf(_ person: String, holder: String?) -> Bool {
        let isHolder = holder.map { StatementHolder.same(person, $0) } ?? false
        if let held = people.first(where: { StatementHolder.same($0.name, person) }) {
            let tag = held.tag?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            return tag == "self" || (tag.isEmpty && isHolder)
        }
        return isHolder
    }

    /// The owner of the account a name means, when the book holds it: two accounts with no
    /// digits at one bank are told apart by `owner` when it is known.
    func owner(ofAccount name: String, owner: String? = nil) -> String? {
        accounts.first { account in
            StatementCounterparts.sameAccount(account.name, name)
                && (name.contains(where: \.isNumber) || owner == nil || account.owner.map { StatementHolder.same($0, owner ?? "") } == true)
        }?.owner
    }
}

public enum StatementTransfers {
    /// The tag name of a person who is the owner: matched without regard to case.
    public static let selfTag = "self"

    /// Whether a line is a transfer by the rule, for a line not yet in the book: the
    /// statement's own account and the account on the other side must both be owned by Self.
    public static func isTransfer(fileAccount: String, fileOwner: String?, counterpart: String?, counterpartOwner: String?,
                                  holder: String?, book: StatementBook) -> Bool {
        guard let counterpart, !counterpart.isEmpty else { return false }
        guard let mine = fileOwner ?? book.owner(ofAccount: fileAccount),
              let theirs = counterpartOwner ?? book.owner(ofAccount: counterpart) else { return false }
        return book.isSelf(mine, holder: holder) && book.isSelf(theirs, holder: holder)
    }

    /// Every one-time row naming its counterpart account or how its line printed, or called
    /// a transfer, gets its direction by the rule. A transfer no longer meeting it returns to
    /// `line_direction`: "in", else money out. Rows changed are signed as the app's own.
    public static func apply(_ raw: [String: Any], now: Date = Date()) -> [String: Any] {
        let own = selfOwnedAccounts(in: raw)
        var rows = raw["commitments"] as? [[String: Any]] ?? []
        var changed: [String] = []
        for index in rows.indices {
            let details = rows[index]["details"] as? [String: Any] ?? [:]
            let held = VaultPatch.storedDirection(rows[index]["direction"] as? String)
            guard rows[index]["billing_cycle"] as? String == BillingCycle.once.rawValue,
                  held == "transfer" || details[StatementImport.counterpartAccountIdKey] != nil || details[StatementImport.lineDirectionKey] != nil
            else { continue }
            let transfer = (rows[index]["account_id"] as? String).map(own.contains) == true
                && (details[StatementImport.counterpartAccountIdKey] as? String).map(own.contains) == true
            let want: String? = transfer ? "transfer" : (held == "transfer" ? (details["line_direction"] as? String == "in" ? "in" : nil) : held)
            guard want != held else { continue }
            if let want { rows[index]["direction"] = want } else { rows[index].removeValue(forKey: "direction") }
            rows[index]["updated_at"] = VaultPatch.iso8601(now)
            if let id = rows[index]["id"] as? String { changed.append(id) }
        }
        guard !changed.isEmpty else { return raw }
        var vault = raw
        vault["commitments"] = rows
        return VaultPatch.sign(ids: changed, in: vault, now: now)
    }

    /// The accounts owned by a person whose Relationship is Self.
    static func selfOwnedAccounts(in raw: [String: Any]) -> Set<String> {
        let selves = Set((raw["members"] as? [[String: Any]] ?? []).compactMap { row -> String? in
            guard (row["tag"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased() == selfTag else { return nil }
            return row["id"] as? String
        })
        return Set((raw["accounts"] as? [[String: Any]] ?? []).compactMap { row -> String? in
            guard let owner = row["member_id"] as? String, selves.contains(owner) else { return nil }
            return row["id"] as? String
        })
    }

    /// How many rows change side from a vault as it stands to the next once the rule has run
    /// over it: charges that become transfers, transfers that go back to charges. Pure, and
    /// it writes nothing. A row the rule corrects is counted, since this write corrects it.
    public static func flips(from old: [String: Any], to new: [String: Any]) -> (intoTransfers: Int, intoCharges: Int) {
        func transfers(_ raw: [String: Any]) -> [String: Bool] {
            Dictionary((raw["commitments"] as? [[String: Any]] ?? []).compactMap { row in
                (row["id"] as? String).map { ($0, VaultPatch.storedDirection(row["direction"] as? String) == "transfer") }
            }, uniquingKeysWith: { first, _ in first })
        }
        let before = transfers(old), after = transfers(apply(new, now: Date(timeIntervalSince1970: 0)))
        var into = 0, out = 0
        for (id, now) in after {
            guard let was = before[id], was != now else { continue }
            if now { into += 1 } else { out += 1 }
        }
        return (into, out)
    }
}
