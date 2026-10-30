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

        public init(rows: [StatementCandidate], attached: [(id: String, charges: [[String: Any]])] = [], account: String,
                    addsAccount: Bool, source: String?, balance: Double? = nil, balanceDate: String? = nil) {
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
        public var accounts: [String]
        public var files: [ReviewFile]
        public var currency: String
        /// The ticked repeats, each with the placeholder it waits as when no lines carry it.
        public var repeats: [(repeated: StatementCloud.Repeat, placeholder: CommitmentPlaceholder)]
        /// What already waits on the timeline.
        public var waiting: [CommitmentPlaceholder]

        public init(members: [String], accounts: [String], files: [ReviewFile], currency: String,
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
        for name in review.members {
            vault = try VaultPatch.ensureEntity(.familyMember, named: name, in: vault, now: now).vault
        }
        for name in review.accounts {
            vault = try VaultPatch.ensureEntity(.paymentMethod, named: name, in: vault, now: now).vault
        }
        let before = Set((raw["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        var written = 0
        var firstSource: String?
        for file in review.files {
            let named = file.account.trimmingCharacters(in: .whitespaces)
            if file.addsAccount, !named.isEmpty {
                vault = try VaultPatch.ensureEntity(.paymentMethod, named: named, in: vault, now: now).vault
            }
            guard file.keepsALine, let source = file.source else { continue }
            firstSource = firstSource ?? source
            let own = file.rows.filter(\.keep)
            if !own.isEmpty {
                let write = proposal(file.rows, accounts: ["": named], currency: review.currency, source: source)
                vault = try applied(write, to: vault, now: now, schema: schema)
                written += own.count
            }
            for (id, charges) in file.attached {
                let write = PendingWrite(id: UUID(), kind: "add_charges", payload: ["id": id, "charges": charges],
                                         sourceRef: source, keyName: "statement import", origin: "statement")
                vault = try applied(write, to: vault, now: now, schema: schema)
                written += charges.count
            }
            // The statement's last line is the account's balance, dated: an old statement never
            // rewinds a newer one.
            if let balance = file.balance, !named.isEmpty,
               let made = try? VaultPatch.ensureEntity(.paymentMethod, named: named, in: vault, now: now),
               balanceIsNewer(file.balanceDate, account: made.id, in: made.vault),
               let set = try? VaultPatch.setEntityDetails(.paymentMethod, id: made.id, in: made.vault, now: now,
                                                         balance: .some(balance), balanceDate: .some(file.balanceDate)) {
                vault = set
            }
        }
        let ticked = review.repeats.map(\.repeated)
        let promoted = firstSource.map { promote(ticked, madeSince: before, in: &vault, source: $0, now: now, schema: schema) } ?? []
        let taken = Set(review.waiting.map { $0.name.lowercased() })
        let fresh = review.repeats.filter {
            !promoted.contains($0.repeated.name) && !taken.contains($0.repeated.name.lowercased()) && !holdsRecurring(named: $0.repeated.name, in: vault)
        }.map(\.placeholder)
        if !fresh.isEmpty { vault = VaultPatch.setToFillIn(review.waiting + fresh, in: vault) }
        let ids = vaultDiff(from: raw, to: vault).filter { $0.kind != "tags" }
            .flatMap { $0.added.map(\.id) + $0.changed.map(\.id) + $0.removed.map(\.id) }
        return Written(vault: VaultPatch.markReviewed(ids: ids, in: vault, now: now), charges: written, promoted: promoted)
    }

    private static func applied(_ write: PendingWrite, to vault: [String: Any], now: Date, schema: [String: Any]?) throws -> [String: Any] {
        guard case .vault(let next) = try PendingApply.apply(write, to: vault, now: now, schema: schema) else { return vault }
        return next
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
                return row["commitment_id"] as? String
            })
            let ids = (vault["commitments"] as? [[String: Any]] ?? []).compactMap { row -> String? in
                guard let id = row["id"] as? String, !before.contains(id), row["billing_cycle"] as? String == BillingCycle.once.rawValue,
                      (row["name"] as? String)?.caseInsensitiveCompare(repeated.name) == .orderedSame,
                      charged.contains(id) else { return nil }
                return id
            }
            guard !ids.isEmpty else { continue }
            var payload: [String: Any] = ["ids": ids, "billing_cycle": repeated.cycle, "plan_months": 24]
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
