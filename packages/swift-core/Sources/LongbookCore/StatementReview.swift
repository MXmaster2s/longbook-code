// A statement review's Add, built whole over one raw vault: the people and accounts, every
// file's rows, the charges that join commitments already held, balances, promoted repeats
// and placeholders. Pure, so the app writes it to disk once and it is proved without one.
import Foundation

extension StatementImport {
    /// One file's share of the review, as the review sheet decided it.
    public struct ReviewFile: @unchecked Sendable {
        /// The lines that become one-time rows; unticked ones are carried and never written.
        public var rows: [StatementCandidate]
        /// Kept lines that are charges of a recurring commitment already held, by its id.
        public var attached: [(id: String, charges: [[String: Any]])]
        public var account: String
        /// Ticked: the statement's own account is added even with no line kept.
        public var addsAccount: Bool
        /// Where the statement was filed in documents; nil when no line of it is kept.
        public var source: String?
        public var balance: Double?
        public var balanceDate: String?
        /// The statement's holder, who owns its account and is Self; nil when it prints none.
        public var owner: String?

        public init(rows: [StatementCandidate], attached: [(id: String, charges: [[String: Any]])] = [], account: String,
                    addsAccount: Bool, source: String?, balance: Double? = nil, balanceDate: String? = nil, owner: String? = nil) {
            self.owner = owner
            self.rows = rows
            self.attached = attached
            self.account = account
            self.addsAccount = addsAccount
            self.source = source
            self.balance = balance
            self.balanceDate = balanceDate
        }

        /// Whether anything of this file is written: its statement is filed only then.
        public var keepsALine: Bool { rows.contains(where: \.keep) || !attached.isEmpty }
    }

    /// Everything one Add writes.
    public struct Review: @unchecked Sendable {
        public var members: [String]
        /// The accounts to add, each with its owner when a line printed the person.
        public var accounts: [StatementCounterparts.Account]
        public var files: [ReviewFile]
        public var currency: String
        /// The ticked repeats, each with the placeholder it waits as when no lines carry it.
        public var repeats: [(repeated: StatementCloud.Repeat, placeholder: CommitmentPlaceholder)]
        /// What already waits on the timeline.
        public var waiting: [CommitmentPlaceholder]

        public init(members: [String], accounts: [StatementCounterparts.Account], files: [ReviewFile], currency: String,
                    repeats: [(repeated: StatementCloud.Repeat, placeholder: CommitmentPlaceholder)], waiting: [CommitmentPlaceholder]) {
            self.members = members
            self.accounts = accounts
            self.files = files
            self.currency = currency
            self.repeats = repeats
            self.waiting = waiting
        }
    }

    public struct Written: @unchecked Sendable {
        public let vault: [String: Any]
        /// Charges written, one-time rows and attached charges together.
        public let charges: Int
        public let promoted: Set<String>
    }

    /// The review applied in the order the sheet always wrote it. Every row it adds or
    /// changes is marked reviewed, as a Keep marks it, so the owner's other device adopts it.
    /// Throws the first refusal; nothing is half applied.
    public static func write(_ review: Review, to raw: [String: Any], now: Date, schema: [String: Any]?) throws -> Written {
        var vault = raw
        // The holder of each statement is a person, and Self, before anything refers to them.
        for file in review.files {
            if let holder = file.owner?.trimmingCharacters(in: .whitespaces), !holder.isEmpty {
                vault = try ensureHolder(holder, in: vault, now: now)
            }
        }
        for name in review.members {
            vault = try VaultPatch.ensureEntity(.familyMember, named: name, in: vault, now: now).vault
        }
        for account in review.accounts {
            let made = try VaultPatch.ensureAccount(named: account.name, ownerName: account.person, in: vault, now: now)
            vault = made.vault
            // An account a line printed beside a person belongs to that person, once both exist.
            if let person = account.person, let owner = memberId(named: person, in: vault) {
                vault = try VaultPatch.setEntityDetails(.paymentMethod, id: made.id, in: vault, now: now, ownerMemberId: .some(owner))
            }
        }
        let before = Set((raw["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        var written = 0
        var firstSource: String?
        // One-time rows a commitment's day had no room for: no repeat gathers them.
        var standsApart: Set<String> = []
        for file in review.files {
            let named = file.account.trimmingCharacters(in: .whitespaces)
            if file.addsAccount, !named.isEmpty {
                let made = try VaultPatch.ensureAccount(named: named, ownerName: file.owner, in: vault, now: now)
                vault = made.vault
                if let holder = file.owner, let owner = memberId(named: holder, in: vault) {
                    vault = try VaultPatch.setEntityDetails(.paymentMethod, id: made.id, in: vault, now: now, ownerMemberId: .some(owner))
                }
            }
            guard file.keepsALine, let source = file.source else { continue }
            firstSource = firstSource ?? source
            let own = file.rows.filter(\.keep)
            if !own.isEmpty {
                let write = proposal(file.rows, accounts: ["": named], currency: review.currency, source: source, accountOwner: file.owner)
                vault = try applied(write, to: vault, now: now, schema: schema)
                vault = linkCounterpartAccounts(in: vault, madeSince: before)
                written += own.count
            }
            for (id, charges) in file.attached {
                let lines = placed(charges, on: id, in: vault)
                if !lines.joining.isEmpty {
                    let write = PendingWrite(id: UUID(), kind: "add_charges", payload: ["id": id, "charges": lines.joining],
                                             sourceRef: source, keyName: "statement import", origin: "statement")
                    vault = try applied(write, to: vault, now: now, schema: schema)
                }
                if !lines.apart.isEmpty {
                    let rows = lines.apart.map { apartRow($0, from: id, in: vault, account: named, owner: file.owner, currency: review.currency) }
                    let write = PendingWrite(id: UUID(), kind: "add_commitments", payload: ["rows": rows],
                                             sourceRef: source, keyName: "statement import", origin: "statement")
                    let held = Set((vault["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
                    vault = try applied(write, to: vault, now: now, schema: schema)
                    standsApart.formUnion((vault["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.filter { !held.contains($0) })
                }
                written += charges.count
            }
            // The statement's last line is the account's balance, dated: an old statement never
            // rewinds a newer one.
            if let balance = file.balance, !named.isEmpty,
               let made = try? VaultPatch.ensureAccount(named: named, ownerName: file.owner, in: vault, now: now),
               balanceIsNewer(file.balanceDate, account: made.id, in: made.vault),
               let set = try? VaultPatch.setEntityDetails(.paymentMethod, id: made.id, in: made.vault, now: now,
                                                         balance: .some(balance), balanceDate: .some(file.balanceDate)) {
                vault = set
            }
        }
        let ticked = review.repeats.map(\.repeated)
        let promoted = firstSource.map { promote(ticked, madeSince: before.union(standsApart), in: &vault, source: $0, now: now, schema: schema) } ?? []
        let taken = Set(review.waiting.map { $0.name.lowercased() })
        let fresh = review.repeats.filter {
            !promoted.contains($0.repeated.name) && !taken.contains($0.repeated.name.lowercased()) && !holdsRecurring(named: $0.repeated.name, in: vault)
        }.map(\.placeholder)
        if !fresh.isEmpty { vault = VaultPatch.setToFillIn(review.waiting + fresh, in: vault, now: now) }
        vault = StatementTransfers.apply(vault, now: now)
        let ids = vaultDiff(from: raw, to: vault).filter { $0.kind != "tags" }
            .flatMap { $0.added.map(\.id) + $0.changed.map(\.id) + $0.removed.map(\.id) }
        return Written(vault: VaultPatch.markReviewed(ids: ids, in: vault, now: now), charges: written, promoted: promoted)
    }

    /// Where a commitment's lines land. One row per day, and a charge is a fact: a line fills
    /// a day's plan, or confirms a paid mark at its amount that no line backs yet. Any other
    /// line that day stands apart, and the row there stays.
    static func placed(_ charges: [[String: Any]], on id: String, in raw: [String: Any]) -> (joining: [[String: Any]], apart: [[String: Any]]) {
        let rows = Dictionary(VaultPatch.chargeRows(raw).filter { $0["commitment_id"] as? String == id }.compactMap { row in
            (row["date"] as? String).map { ($0, row) }
        }, uniquingKeysWith: { first, _ in first })
        var taken: Set<String> = []
        var joining: [[String: Any]] = []
        var apart: [[String: Any]] = []
        for charge in charges {
            guard let date = charge["date"] as? String else {
                joining.append(charge)
                continue
            }
            let held = rows[date]
            let isFact = held?["paid"] as? Bool == true || held?["basis"] as? String == "statement"
            let note = held?["note"] as? String
            let backed = note?.hasPrefix(notePrefix) == true || held?["basis"] as? String == "statement"
            let sameAmount = (held?["amount"] as? NSNumber)?.doubleValue == (charge["amount"] as? NSNumber)?.doubleValue
            if taken.contains(date) || (isFact && (backed || !sameAmount)) {
                apart.append(charge)
                continue
            }
            taken.insert(date)
            var joined = charge
            if isFact, note?.isEmpty == false { joined.removeValue(forKey: "note") }
            joining.append(joined)
        }
        return (joining, apart)
    }

    /// A line with no room on its commitment's day: a one-time row of the same name on the
    /// statement's account, filed as the commitment is, carrying its line.
    private static func apartRow(_ charge: [String: Any], from id: String, in raw: [String: Any], account: String, owner: String?, currency: String) -> [String: Any] {
        let home = (raw["commitments"] as? [[String: Any]] ?? []).first { $0["id"] as? String == id } ?? [:]
        var row: [String: Any] = ["name": home["name"] as? String ?? "", "billing_cycle": BillingCycle.once.rawValue, "currency": currency,
                                  "account": account, "paid": true, "basis": "statement"]
        for key in ["date", "amount", "note"] { row[key] = charge[key] }
        if let owner = owner?.trimmingCharacters(in: .whitespaces), !owner.isEmpty { row["account_owner"] = owner }
        if let tag = home["tag"] as? String, !tag.isEmpty { row["tag"] = tag }
        if let direction = VaultPatch.storedDirection(home["direction"] as? String) { row["direction"] = direction }
        let people = raw[VaultPatch.EntityKind.familyMember.rawValue] as? [[String: Any]] ?? []
        if let member = home["member_id"] as? String, let person = people.first(where: { $0["id"] as? String == member })?["name"] { row["member"] = person }
        var details: [String: Any] = [:]
        // The other side travels with it, so the Transfers rule reads this row as it reads the commitment.
        for key in [counterpartAccountIdKey, counterpartAccountKey, lineDirectionKey] {
            if let value = (home["details"] as? [String: Any])?[key] { details[key] = value }
        }
        if let note = charge["note"] as? String, note.hasPrefix(notePrefix) { details["statement_line"] = String(note.dropFirst(notePrefix.count)) }
        if !details.isEmpty { row["details"] = details }
        return row
    }

    private static func applied(_ write: PendingWrite, to vault: [String: Any], now: Date, schema: [String: Any]?) throws -> [String: Any] {
        guard case .vault(let next) = try PendingApply.apply(write, to: vault, now: now, schema: schema) else { return vault }
        return next
    }

    /// The id of the person named, matched as names match; nil when the book holds none.
    static func memberId(named name: String, in raw: [String: Any]) -> String? {
        let key = nameKey(name)
        let people = raw[VaultPatch.EntityKind.familyMember.rawValue] as? [[String: Any]] ?? []
        return (people.first { nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key }
            ?? people.first { VaultPatch.mergedNames(of: $0).contains { nameKey($0) == key } }
            ?? people.first { StatementHolder.same($0["name"] as? String ?? "", name) })?["id"] as? String
    }

    /// The id of the account an account name and its owner mean, matched as Accounts match
    /// two names for one account; one with no digits is also told apart by its owner. Nil
    /// when the book holds none.
    static func accountId(named name: String, owner: String? = nil, in raw: [String: Any]) -> String? {
        let ownerId = owner.flatMap { memberId(named: $0, in: raw) }
        return (raw[VaultPatch.EntityKind.paymentMethod.rawValue] as? [[String: Any]] ?? []).first { row in
            let names = [row["name"] as? String ?? ""] + VaultPatch.mergedNames(of: row)
            guard names.contains(where: { StatementCounterparts.sameAccount($0, name) }) else { return false }
            if name.contains(where: \.isNumber) { return true }
            return (row["member_id"] as? String) == ownerId
        }?["id"] as? String
    }

    /// A person made Self: the member, the registry's "self" tag, and the tag on a person who
    /// has none yet. A person the owner already gave another relationship keeps it.
    static func ensureHolder(_ name: String, in raw: [String: Any], now: Date) throws -> [String: Any] {
        let people = (raw[VaultPatch.EntityKind.familyMember.rawValue] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let said = StatementHolder.resolve(name, among: people)
        var made = try VaultPatch.ensureEntity(.familyMember, named: said, in: raw, now: now)
        made.vault = VaultPatch.ensureTag(kind: "member", named: StatementTransfers.selfTag, in: made.vault, now: now)
        let row = (made.vault[VaultPatch.EntityKind.familyMember.rawValue] as? [[String: Any]] ?? []).first { $0["id"] as? String == made.id }
        guard (row?["tag"] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true else { return made.vault }
        let tags = made.vault["tags"] as? [[String: Any]] ?? []
        let spelled = tags.first { ($0["kind"] as? String) == "member" && nameKey($0["name_key"] as? String ?? $0["name"] as? String) == StatementTransfers.selfTag }?["name"] as? String
        return try VaultPatch.setEntityDetails(.familyMember, id: made.id, in: made.vault, now: now, memberTag: .some(spelled ?? StatementTransfers.selfTag))
    }

    /// Every row written since `before` whose details name the other side's account gets
    /// that account's id beside the name, when the book holds the account; the owner it was
    /// resolved with is dropped from the details once it has.
    static func linkCounterpartAccounts(in raw: [String: Any], madeSince before: Set<String>) -> [String: Any] {
        var vault = raw
        var rows = vault["commitments"] as? [[String: Any]] ?? []
        var changed = false
        for index in rows.indices {
            guard let id = rows[index]["id"] as? String, !before.contains(id),
                  var details = rows[index]["details"] as? [String: Any],
                  let name = details[counterpartAccountKey] as? String else { continue }
            let owner = details.removeValue(forKey: counterpartOwnerKey) as? String
            if details[counterpartAccountIdKey] == nil, let accountId = accountId(named: name, owner: owner, in: vault) {
                details[counterpartAccountIdKey] = accountId
            }
            rows[index]["details"] = details
            changed = true
        }
        if changed { vault["commitments"] = rows }
        return vault
    }

    /// Whether a balance dated `day` is as new as the one the account holds. An undated
    /// balance counts as older than a dated one, and anything beats no balance at all.
    static func balanceIsNewer(_ day: String?, account id: String, in raw: [String: Any]) -> Bool {
        guard let row = (raw["accounts"] as? [[String: Any]] ?? []).first(where: { $0["id"] as? String == id }),
              row["balance"] != nil, !(row["balance"] is NSNull) else { return true }
        guard let held = row["balance_date"] as? String else { return true }
        guard let day else { return false }
        return day >= held
    }

    /// Each repeat promoted over the one-time rows it names among those written since
    /// `before`: one recurring commitment, planned ahead. A repeat the file refuses stays as
    /// its one-time rows. Returns the names that became commitments.
    static func promote(_ repeats: [StatementCloud.Repeat], madeSince before: Set<String>, in vault: inout [String: Any],
                        source: String, now: Date, schema: [String: Any]?) -> Set<String> {
        var made: Set<String> = []
        for repeated in repeats {
            let dates = Set(repeated.dates)
            let charged = Set(VaultPatch.chargeRows(vault).compactMap { row -> String? in
                guard let date = row["date"] as? String, dates.contains(date) else { return nil }
                if !repeated.sightings.isEmpty {
                    guard let amount = (row["amount"] as? NSNumber)?.doubleValue,
                          repeated.sightings.contains(StatementCompleteness.key(date, amount)) else { return nil }
                }
                return row["commitment_id"] as? String
            })
            let ids = (vault["commitments"] as? [[String: Any]] ?? []).compactMap { row -> String? in
                guard let id = row["id"] as? String, !before.contains(id), row["billing_cycle"] as? String == BillingCycle.once.rawValue,
                      (row["name"] as? String)?.caseInsensitiveCompare(repeated.name) == .orderedSame,
                      charged.contains(id) else { return nil }
                return id
            }
            guard !ids.isEmpty else { continue }
            // A guess is written as one: the name says so at its end, the notes open with why.
            var payload: [String: Any] = ["ids": ids, "billing_cycle": repeated.cycle, "plan_months": 24,
                                          "name": StatementNaming.clean(repeated.writtenName)]
            if let note = repeated.guessedNote { payload["notes"] = note }
            if let days = repeated.customDays { payload["custom_cycle_days"] = days }
            if let endsOn = repeated.endsOn { payload["ends_on"] = endsOn }
            if let tag = repeated.category { payload["tag"] = tag }
            let write = PendingWrite(id: UUID(), kind: "promote_to_recurring", payload: payload,
                                     sourceRef: source, keyName: "statement import", origin: "statement")
            if let next = try? applied(write, to: vault, now: now, schema: schema) {
                vault = next
                made.insert(repeated.name)
            }
        }
        return made
    }

    /// A recurring commitment by this name, as the timeline's placeholders ask.
    static func holdsRecurring(named name: String, in raw: [String: Any]) -> Bool {
        (raw["commitments"] as? [[String: Any]] ?? []).contains {
            ($0["billing_cycle"] as? String ?? "") != BillingCycle.once.rawValue
                && ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
