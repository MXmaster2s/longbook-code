// Applying a proposed write — pure, so it is provable without a network.
//
// The servers validated the payload; this side re-validates anyway, through the app's own
// SubValidator and secret scan. The result is the raw vault the form would produce, signed
// with the KEY's name — the owner reads "· claude-daily-brief", not "longbook".
import Foundation

public enum PendingApply {
    public enum Outcome {
        /// A changed vault, ready for the ordinary write path.
        case vault([String: Any])
        /// A report for longbook to draw from the ledger: the AI names the days and scope,
        /// the app draws every figure. Nothing in the vault changes.
        case drawReport(ReportRequest)
        /// One note appended to insights.json.
        case insight(module: String, text: String)
    }

    /// What a create_report proposal asks for, every name resolved to the name the memory
    /// stores, so the draw's exact matching finds the charges.
    public struct ReportRequest: Equatable {
        public let title: String
        public let start: Date
        public let end: Date
        public let scope: ReportScope?

        public init(title: String, start: Date, end: Date, scope: ReportScope?) {
            self.title = title
            self.start = start
            self.end = end
            self.scope = scope
        }
    }

    public enum ApplyError: LocalizedError {
        case unknownKind(String)
        case invalid(String)
        case notFound(String)
        case ambiguous(String)

        public var errorDescription: String? {
            switch self {
            case .unknownKind(let kind): return "This version of longbook does not know how to apply \"\(kind)\"."
            case .invalid(let why): return why
            case .notFound(let what): return what
            case .ambiguous(let what): return what
            }
        }
    }

    /// One proposal onto one raw vault. Throws with a sentence the owner could read.
    public static func apply(_ write: PendingWrite, to raw: [String: Any], now: Date, schema: [String: Any]? = nil) throws -> Outcome {
        switch write.kind {
        case "add_commitments": return .vault(try addCommitments(write, to: raw, now: now, schema: schema))
        case "update_commitment": return .vault(try updateCommitment(write, to: raw, now: now, schema: schema))
        case "mark_paid": return .vault(try markPaid(write, to: raw, now: now))
        case "add_charges": return .vault(try addCharges(write, to: raw, now: now))
        case "remove_charges": return .vault(try removeCharges(write, to: raw, now: now))
        case "cancel_commitment": return .vault(try cancelCommitment(write, to: raw, now: now, schema: schema))
        case "promote_to_recurring": return .vault(try promote(write, to: raw, now: now, schema: schema))
        case "leave_insight": return try insight(write)
        case "update_account": return .vault(try updateEntity(.paymentMethod, write, to: raw, now: now))
        // "update_member" and "add_member" are the names before contract revision 41.
        case "update_person", "update_member": return .vault(try updateEntity(.familyMember, write, to: raw, now: now))
        case "update_charge": return .vault(try updateCharge(write, to: raw, now: now, schema: schema))
        case "set_planned_count": return .vault(try setPlannedCount(write, to: raw, now: now))
        case "add_person", "add_member": return .vault(try addEntity(.familyMember, write, to: raw, now: now))
        case "add_account": return .vault(try addEntity(.paymentMethod, write, to: raw, now: now))
        case "rename_tag": return .vault(try renameTag(write, to: raw, now: now))
        case "delete_tag": return .vault(try deleteTag(write, to: raw, now: now))
        case "delete_commitment": return .vault(try deleteCommitment(write, to: raw, now: now))
        case "create_report": return .drawReport(try reportRequest(write.payload, in: raw, now: now))
        default: throw ApplyError.unknownKind(write.kind)
        }
    }

    /// A field a proposal may clear: absent leaves it alone, null clears it, a string sets it.
    private static func clearable(_ payload: [String: Any], _ key: String) -> String?? {
        guard payload.keys.contains(key) else { return nil }
        return .some(payload[key] as? String)
    }

    // MARK: - the vault kinds

    private static func addCommitments(_ write: PendingWrite, to raw: [String: Any], now: Date, schema: [String: Any]?) throws -> [String: Any] {
        guard let rows = write.payload["rows"] as? [[String: Any]], !rows.isEmpty else {
            throw ApplyError.invalid("This proposal carried no commitments.")
        }
        var vault = raw
        var ids: [String] = []
        for (index, row) in rows.enumerated() {
            do {
                let (next, id) = try addOne(row, to: vault, now: now, schema: schema, takingDetails: writesDetails(write))
                vault = next
                ids.append(id)
            } catch {
                // Named by its name only when the name scans clean, else by its place alone, as
                // both MCP doors name it: a refusal never repeats what it refused.
                let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let which = name.isEmpty || scanText(name) != nil ? "Row \(index + 1)" : "Row \(index + 1) (\"\(name)\")"
                throw ApplyError.invalid("\(which) could not be added: \(error.friendlyDescription)")
            }
        }
        return sign(vault, from: raw, ids: ids, write: write, now: now)
    }

    /// longbook's own writes — a statement it read, a Siri or Shortcuts phrase. Only these
    /// write a commitment's details: the line the statement printed. No write tool takes them.
    private static func writesDetails(_ write: PendingWrite) -> Bool {
        write.origin == "statement" || write.origin == "intent"
    }

    /// The attributes a row names, resolved onto an edit — tags, members and accounts made
    /// as they are named. Shared by adding and promoting.
    private static func attributes(from row: [String: Any], onto edit: inout SubEdit, in raw: [String: Any], now: Date,
                                   takingDetails: Bool) throws -> [String: Any] {
        var vault = raw
        if let name = row["name"] as? String { edit.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let amount = number(row["amount"]) { edit.amount = amount }
        if let currency = row["currency"] as? String { edit.currency = currency.trimmingCharacters(in: .whitespaces).uppercased() }
        if let cycle = (row["billing_cycle"] as? String).flatMap(BillingCycle.init(rawValue:)) { edit.billingCycle = cycle }
        if row.keys.contains("custom_cycle_days") { edit.customCycleDays = (row["custom_cycle_days"] as? NSNumber)?.intValue }
        if let status = (row["status"] as? String).flatMap(SubStatus.init(rawValue:)) { edit.status = status }
        // "in" and "transfer" are kept; "out" or anything else is a charge, written as absence.
        if row.keys.contains("direction") { edit.direction = VaultPatch.storedDirection(row["direction"] as? String) }
        if row.keys.contains("ends_on") { edit.scheduledCancelDate = row["ends_on"] as? String }
        if row.keys.contains("notes") { edit.notes = row["notes"] as? String }
        if row.keys.contains("tag") {
            let tag = (row["tag"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            edit.tag = (tag?.isEmpty == false) ? tag : nil
            if let tag = edit.tag { vault = VaultPatch.ensureTag(kind: "commitment", named: tag, in: vault, now: now) }
        }
        // From anywhere else, details is a key no write takes. A proposal that carries some keeps
        // what they say, as lines of the notes.
        if let sent = row["details"] {
            let details = (sent as? [String: Any]).map(decodeDetails) ?? [:]
            if takingDetails { edit.details = details } else { edit.notes = folded(details, into: edit.notes) }
        }
        if row.keys.contains("member") {
            if let member = (row["member"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !member.isEmpty {
                let made = try VaultPatch.ensureEntity(.familyMember, named: member, in: vault, now: now)
                vault = made.vault
                edit.familyMemberId = made.id
            } else {
                edit.familyMemberId = nil
            }
        }
        if row.keys.contains("account") {
            if let account = (row["account"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty {
                // A statement's account is told apart by its owner when it prints no digits.
                let owner = takingDetails ? (row["account_owner"] as? String) : nil
                let made = try VaultPatch.ensureAccount(named: account, ownerName: owner, in: vault, now: now)
                vault = made.vault
                edit.paymentMethodId = made.id
            } else {
                edit.paymentMethodId = nil
            }
        }
        return vault
    }

    private static func addOne(_ row: [String: Any], to raw: [String: Any], now: Date, schema: [String: Any]?,
                               takingDetails: Bool) throws -> ([String: Any], String) {
        var edit = SubEdit()
        edit.currency = "INR"
        var vault = try attributes(from: row, onto: &edit, in: raw, now: now, takingDetails: takingDetails)
        // The first charge: `first_charge`, or `date` for a one-time row.
        edit.firstCharge = (row["first_charge"] as? String) ?? (row["date"] as? String)
        edit.planMonths = (row["plan_months"] as? NSNumber)?.intValue
        edit.planCount = (row["plan_count"] as? NSNumber)?.intValue
        let id = UUID().uuidString.lowercased()
        edit.id = id
        // A new row: apply() refuses an id it cannot find, so the row is seeded first.
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        subs.append(["id": id, "created_at": VaultPatch.iso8601(now)])
        vault["commitments"] = subs
        vault = try VaultPatch.apply(edit, to: vault, now: now, schema: schema)
        // A one-time row from a statement arrives already paid, with what backs it.
        if edit.billingCycle == .once, let date = edit.firstCharge,
           row["paid"] != nil || row["basis"] != nil || row["paid_on"] != nil || row["note"] != nil {
            vault = try VaultPatch.setCharge(commitmentId: id, date: date, paid: row["paid"] as? Bool,
                                             paidOn: clearable(row, "paid_on"), note: clearable(row, "note"),
                                             basis: row["basis"] as? String, in: vault, now: now)
        }
        return (vault, id)
    }

    private static func updateCommitment(_ write: PendingWrite, to raw: [String: Any], now: Date, schema: [String: Any]?) throws -> [String: Any] {
        guard let set = write.payload["set"] as? [String: Any], !set.isEmpty else {
            throw ApplyError.invalid("This proposal named no fields to change.")
        }
        let row = try find(write.payload, in: raw)
        var edit = SubEdit(from: try decode(row))
        let vault = try attributes(from: set, onto: &edit, in: raw, now: now, takingDetails: writesDetails(write))
        edit.amountFrom = set["from"] as? String
        edit.firstCharge = set["date"] as? String
        if let trial = set["free_trial"] as? Bool { edit.freeTrial = trial }
        let id = row["id"] as? String ?? ""
        let next = try VaultPatch.apply(edit, to: vault, now: now, schema: schema)
        return sign(next, from: raw, ids: [id], write: write, now: now)
    }

    private static func markPaid(_ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let date = write.payload["date"] as? String, !date.isEmpty else {
            throw ApplyError.invalid("This proposal named no date to mark.")
        }
        let row = try find(write.payload, in: raw)
        let id = row["id"] as? String ?? ""
        let paid = write.payload["paid"] as? Bool ?? true
        let next = try VaultPatch.setCharge(commitmentId: id, date: date, paid: paid,
                                            amount: number(write.payload["amount"]),
                                            paidOn: clearable(write.payload, "paid_on"),
                                            note: clearable(write.payload, "note"),
                                            in: raw, now: now)
        return sign(next, from: raw, ids: [id], write: write, now: now)
    }

    /// One charge's changes where it sits, as the form's own Save writes them: the day the money
    /// moved first, on the row named, then everything editCharge takes — a move carries it along.
    private static func updateCharge(_ write: PendingWrite, to raw: [String: Any], now: Date, schema: [String: Any]?) throws -> [String: Any] {
        guard let date = write.payload["date"] as? String, LB.parseDate(date) != nil else {
            throw ApplyError.invalid("This proposal named no day for the charge.")
        }
        guard let set = write.payload["set"] as? [String: Any], !set.isEmpty else {
            throw ApplyError.invalid("This proposal named no fields to change.")
        }
        let row = try find(write.payload, in: raw)
        let id = row["id"] as? String ?? ""
        guard VaultPatch.chargeRows(raw).contains(where: { $0["commitment_id"] as? String == id && $0["date"] as? String == date }) else {
            throw ApplyError.notFound("No charge on \(date) is written for \"\(row["name"] as? String ?? id)\".")
        }
        var vault = raw
        if let paidOn = clearable(set, "paid_on") {
            vault = try VaultPatch.setCharge(commitmentId: id, date: date, paidOn: paidOn, creating: false, in: vault, now: now)
        }
        vault = try VaultPatch.editCharge(commitmentId: id, from: date, to: set["date"] as? String,
                                          paid: set["paid"] as? Bool, amount: number(set["amount"]),
                                          note: clearable(set, "note"), andLater: set["and_later"] as? Bool ?? false,
                                          in: vault, now: now, schema: schema)
        return sign(vault, from: raw, ids: [id], write: write, now: now)
    }

    private static func setPlannedCount(_ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let count = (write.payload["count"] as? NSNumber)?.intValue, count >= 1 else {
            throw ApplyError.invalid("This proposal named no count of charges to plan.")
        }
        let row = try find(write.payload, in: raw)
        let id = row["id"] as? String ?? ""
        // The writer answers a one-time commitment with the file unchanged; the owner is told instead.
        if (row["billing_cycle"] as? String) == BillingCycle.once.rawValue {
            throw ApplyError.invalid("A one-time commitment has its one charge; there is nothing to plan.")
        }
        // A plan under a paused or cancelled commitment is one the form never writes, on any door.
        let status = displayStatus(try decode(row), LB.dayOf(now))
        if status != .active {
            throw ApplyError.invalid("\"\(row["name"] as? String ?? id)\" is \(status.rawValue); set its status to active first, then plan.")
        }
        return sign(try VaultPatch.setPlannedCount(commitmentId: id, count: count, in: raw, now: now), from: raw, ids: [id], write: write, now: now)
    }

    /// Removing the row outright, on the owner's own word: the commitment and every charge it had,
    /// as the app's own delete does. The tombstones it leaves carry the key's name, so the owner
    /// reviews the removal on every device rather than adopting it as their own.
    private static func deleteCommitment(_ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let id = (write.payload["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw ApplyError.invalid("This proposal named no commitment id.")
        }
        guard (raw["commitments"] as? [[String: Any]])?.contains(where: { $0["id"] as? String == id }) == true else {
            throw ApplyError.notFound("No commitment with id \(id) is in the memory any more.")
        }
        return sign(try VaultPatch.delete(id: id, from: raw, now: now), from: raw, ids: [id], write: write, now: now)
    }

    private static func addCharges(_ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let rows = write.payload["charges"] as? [[String: Any]], !rows.isEmpty else {
            throw ApplyError.invalid("This proposal carried no charges.")
        }
        let sub = try find(write.payload, in: raw)
        let id = sub["id"] as? String ?? ""
        var vault = raw
        for row in rows {
            guard let date = row["date"] as? String, LB.parseDate(date) != nil else {
                throw ApplyError.invalid("Every charge needs a real YYYY-MM-DD date.")
            }
            vault = try VaultPatch.setCharge(commitmentId: id, date: date, paid: row["paid"] as? Bool,
                                             amount: number(row["amount"]), paidOn: clearable(row, "paid_on"),
                                             note: clearable(row, "note"),
                                             basis: row["basis"] as? String ?? (row["paid"] as? Bool == true || row["amount"] != nil ? "user" : "plan"),
                                             in: vault, now: now)
        }
        return sign(vault, from: raw, ids: [id], write: write, now: now)
    }

    private static func removeCharges(_ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let dates = write.payload["dates"] as? [String], !dates.isEmpty else {
            throw ApplyError.invalid("This proposal named no dates to remove.")
        }
        let sub = try find(write.payload, in: raw)
        let id = sub["id"] as? String ?? ""
        return sign(VaultPatch.removeCharges(of: id, dates: dates, in: raw, now: now), from: raw, ids: [id], write: write, now: now)
    }

    private static func cancelCommitment(_ write: PendingWrite, to raw: [String: Any], now: Date, schema: [String: Any]?) throws -> [String: Any] {
        let row = try find(write.payload, in: raw)
        let id = row["id"] as? String ?? ""
        if (row["status"] as? String) == SubStatus.cancelled.rawValue {
            throw ApplyError.invalid("\"\(row["name"] as? String ?? id)\" was already cancelled.")
        }
        return sign(try VaultPatch.cancel(id: id, in: raw, now: now, schema: schema), from: raw, ids: [id], write: write, now: now)
    }

    private static func promote(_ write: PendingWrite, to raw: [String: Any], now: Date, schema: [String: Any]?) throws -> [String: Any] {
        guard let ids = write.payload["ids"] as? [String], !ids.isEmpty else {
            throw ApplyError.invalid("This proposal named no one-time commitments to promote.")
        }
        let rows = raw["commitments"] as? [[String: Any]] ?? []
        guard let first = rows.first(where: { $0["id"] as? String == ids[0] }) else {
            throw ApplyError.notFound("No commitment with id \(ids[0]) is in the memory any more.")
        }
        // One direction across the ids, or a row would move into or out of a sum.
        _ = try VaultPatch.sharedDirection(of: ids, in: raw)
        // The attributes start as the first one-time row's, then take whatever the proposal names.
        var edit = SubEdit(from: try decode(first))
        edit.id = nil
        edit.status = .active
        edit.billingCycle = (write.payload["billing_cycle"] as? String).flatMap(BillingCycle.init(rawValue:)) ?? .monthly
        guard edit.billingCycle != .once else { throw ApplyError.invalid("Promoting makes a recurring commitment; say monthly, yearly or custom.") }
        var overrides = write.payload
        overrides.removeValue(forKey: "billing_cycle")
        // A promotion names no direction; the rows' own is the only one it can carry.
        overrides.removeValue(forKey: "direction")
        let vault = try attributes(from: overrides, onto: &edit, in: raw, now: now, takingDetails: writesDetails(write))
        let made = try VaultPatch.promote(onceIds: ids, to: edit,
                                          planMonths: (write.payload["plan_months"] as? NSNumber)?.intValue,
                                          in: vault, now: now, schema: schema)
        // The merged rows' tombstones carry the key's name too, so their removal is reviewed, not adopted.
        return sign(made.vault, from: raw, ids: [made.id] + ids, write: write, now: now)
    }

    // MARK: - accounts and members

    /// An account or a person: renamed through renameEntity, described through
    /// setEntityDetails — the same refusals the app's own form meets.
    private static func updateEntity(_ kind: VaultPatch.EntityKind, _ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let set = write.payload["set"] as? [String: Any], !set.isEmpty else {
            throw ApplyError.invalid("This proposal named no fields to change.")
        }
        let row = try findEntity(kind, write.payload, in: raw)
        let id = row["id"] as? String ?? ""
        var vault = raw
        if let name = set["name"] as? String {
            vault = try VaultPatch.renameEntity(kind, id: id, to: name, in: vault, now: now)
        }
        vault = try describe(kind, id: id, row: row, set: set, write: write, in: vault, now: now)
        return sign(vault, from: raw, ids: [id], write: write, now: now)
    }

    /// The fields that describe a person or an account, as add_member and add_account carry them.
    private static let describing = ["tag", "email", "linked_to", "parent", "parent_account", "member", "notes",
                                     "balance", "balance_date", "card_name", "details", "starred"]

    /// A new person or account, written as ensureEntity writes a placeholder and then described;
    /// a name the list already holds is refused rather than doubled, in the form's own words.
    private static func addEntity(_ kind: VaultPatch.EntityKind, _ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        let word = kind == .paymentMethod ? "account" : "person"
        guard let name = (write.payload["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw ApplyError.invalid("This proposal named no \(word).")
        }
        let rows = raw[kind.rawValue] as? [[String: Any]] ?? []
        let key = nameKey(name)
        if rows.contains(where: { nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key }) {
            throw ApplyError.invalid("There's already \(word == "account" ? "an" : "a") \(word) called \(name).")
        }
        let made = try VaultPatch.ensureEntity(kind, named: name, in: raw, now: now)
        var vault = made.vault
        // Details that say nothing describe nothing; a placeholder stays one.
        let set = write.payload.filter { describing.contains($0.key) }
        if set.contains(where: { !["card_name", "details"].contains($0.key) || sends($0.value) }) {
            let row = (vault[kind.rawValue] as? [[String: Any]])?.first { $0["id"] as? String == made.id } ?? [:]
            vault = try describe(kind, id: made.id, row: row, set: set, write: write, in: vault, now: now)
            // Described, it is no longer only a name.
            var list = vault[kind.rawValue] as? [[String: Any]] ?? []
            if let index = list.firstIndex(where: { $0["id"] as? String == made.id }) {
                list[index]["is_incomplete"] = false
                vault[kind.rawValue] = list
            }
        }
        return sign(vault, from: raw, ids: [made.id], write: write, now: now)
    }

    /// What a set says about an account or a person, resolved and written through setEntityDetails.
    private static func describe(_ kind: VaultPatch.EntityKind, id: String, row: [String: Any], set: [String: Any],
                                 write: PendingWrite, in raw: [String: Any], now: Date) throws -> [String: Any] {
        // A person carries a name, a tag, an email and linked accounts. The doors refuse in the AI's
        // words; this is the owner's, read in Changes, so it opens in sentence case.
        if kind == .familyMember, sends(set["details"]) || sends(set["card_name"]) {
            throw ApplyError.invalid("Details are longbook's own — a member carries a name, a tag, an email and linked accounts.")
        }
        var vault = raw

        var accountTag: String?? = nil
        var parentAccountId: String?? = nil
        var email: String?? = nil
        var balance: Double?? = nil
        var balanceDate: String?? = nil
        var memberTag: String?? = nil
        var ownerMemberId: String?? = nil
        var accountNotes: String?? = nil
        if kind == .paymentMethod {
            if set.keys.contains("tag") {
                let tag = (set["tag"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                accountTag = .some(tag?.isEmpty == false ? tag : nil)
            }
            // The linked account, under its name or either of the two it had before.
            if let key = ["linked_to", "parent", "parent_account"].first(where: { set.keys.contains($0) }) {
                let wanted = (set[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let wanted, !wanted.isEmpty {
                    parentAccountId = .some(try linkedAccount(named: wanted, in: raw))
                } else {
                    parentAccountId = .some(nil)
                }
            }
            if set.keys.contains("member") {
                let wanted = (set["member"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let wanted, !wanted.isEmpty {
                    ownerMemberId = .some(try owner(named: wanted, in: raw))
                } else {
                    ownerMemberId = .some(nil)
                }
            }
            if set.keys.contains("notes") { accountNotes = .some(set["notes"] as? String) }
            // card_name and details are longbook's own on an account. A proposal that carries
            // either keeps what they say, as lines after the notes, as a commitment's are kept.
            var sent = (set["details"] as? [String: Any]).map(decodeDetails) ?? [:]
            if let name = set["card_name"].flatMap(detailValue) { sent[PaymentMethod.cardNameKey] = name }
            let base = set.keys.contains("notes") ? set["notes"] as? String : row["notes"] as? String
            if let next = folded(sent, into: base), next != base { accountNotes = .some(next) }
            if set.keys.contains("balance") {
                if let amount = number(set["balance"]) {
                    balance = .some(amount)
                    // A balance without its day is true as of the write: the day the proposal
                    // was filed, never the day the app happens to apply it.
                    let filed = write.createdAt ?? now
                    balanceDate = .some(set.keys.contains("balance_date") ? set["balance_date"] as? String : LB.toISO(filed))
                } else {
                    balance = .some(nil)
                    balanceDate = .some(nil)
                }
            } else if set.keys.contains("balance_date") {
                // The day alone moves a balance already held; it never stands undated or empty.
                guard number(row["balance"]) != nil else {
                    throw ApplyError.invalid("This account holds no balance to date — give balance with balance_date.")
                }
                guard let day = set["balance_date"] as? String else {
                    throw ApplyError.invalid("A balance carries its day — set balance to null to clear both.")
                }
                balanceDate = .some(day)
            }
        } else {
            if set.keys.contains("email") {
                let address = set["email"] as? String
                email = .some(address?.isEmpty == false ? address : nil)
            }
            if set.keys.contains("tag") {
                let tag = (set["tag"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                memberTag = .some(tag?.isEmpty == false ? tag : nil)
            }
        }

        // The star, on either kind; anything but a boolean is refused as the doors refuse it.
        var starred: Bool? = nil
        if let sent = set["starred"], !(sent is NSNull) {
            guard let flag = sent as? Bool, CFGetTypeID(sent as CFTypeRef) == CFBooleanGetTypeID() else {
                throw ApplyError.invalid("A star is on or off.")
            }
            starred = flag
        }

        let described = accountTag != nil || parentAccountId != nil || email != nil || balance != nil || balanceDate != nil
            || memberTag != nil || ownerMemberId != nil || accountNotes != nil || starred != nil
        if described {
            vault = try VaultPatch.setEntityDetails(
                kind, id: id, in: vault, now: now,
                accountTag: accountTag, parentAccountId: parentAccountId, email: email,
                balance: balance, balanceDate: balanceDate,
                memberTag: memberTag, ownerMemberId: ownerMemberId, accountNotes: accountNotes,
                starred: starred
            )
            if case .some(.some(let tag)) = accountTag {
                vault = VaultPatch.ensureTag(kind: "account", named: tag, in: vault, now: now)
            }
            if case .some(.some(let tag)) = memberTag {
                vault = VaultPatch.ensureTag(kind: "member", named: tag, in: vault, now: now)
            }
        }
        return vault
    }

    // MARK: - tags

    /// Whether a tag of this kind exists: registered, or worn by a row of its list.
    private static func tagHeld(kind: String, named name: String, in raw: [String: Any]) -> Bool {
        let key = nameKey(name)
        let registered = (raw["tags"] as? [[String: Any]] ?? []).contains {
            ($0["kind"] as? String) == kind && nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key
        }
        return registered || wearers(kind: kind, of: key, in: raw).count > 0
    }

    /// The ids of the rows wearing a tag, which a rename carries and a delete clears.
    private static func wearers(kind: String, of key: String, in raw: [String: Any]) -> [String] {
        let collection = ["commitment": "commitments", "member": "members", "account": "accounts"][kind] ?? ""
        return (raw[collection] as? [[String: Any]] ?? [])
            .filter { nameKey($0["tag"] as? String ?? "") == key }
            .compactMap { $0["id"] as? String }
    }

    private static func tagKind(_ write: PendingWrite) throws -> String {
        guard let kind = write.payload["kind"] as? String, ["commitment", "member", "account"].contains(kind) else {
            throw ApplyError.invalid("This proposal named no tag kind.")
        }
        return kind
    }

    private static func renameTag(_ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        let kind = try tagKind(write)
        guard let from = (write.payload["from"] as? String)?.trimmingCharacters(in: .whitespaces), !from.isEmpty,
              let to = write.payload["to"] as? String
        else { throw ApplyError.invalid("This proposal named no tag to rename.") }
        guard tagHeld(kind: kind, named: from, in: raw) else {
            throw ApplyError.notFound("No \(kind) tag in the memory is called \"\(from)\".")
        }
        let carried = wearers(kind: kind, of: nameKey(from), in: raw)
        let made = try VaultPatch.renameTag(kind: kind, from: from, to: to, in: raw, now: now)
        return sign(made.vault, from: raw, ids: carried, write: write, now: now)
    }

    private static func deleteTag(_ write: PendingWrite, to raw: [String: Any], now: Date) throws -> [String: Any] {
        let kind = try tagKind(write)
        guard let name = (write.payload["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            throw ApplyError.invalid("This proposal named no tag to delete.")
        }
        guard tagHeld(kind: kind, named: name, in: raw) else {
            throw ApplyError.notFound("No \(kind) tag in the memory is called \"\(name)\".")
        }
        let cleared = wearers(kind: kind, of: nameKey(name), in: raw)
        let made = VaultPatch.removeTag(kind: kind, named: name, in: raw, now: now)
        return sign(made.vault, from: raw, ids: cleared, write: write, now: now)
    }

    /// The linked account a set names — by id, else by a name only one account wears.
    private static func linkedAccount(named wanted: String, in raw: [String: Any]) throws -> String {
        try named(wanted, in: raw, kind: .paymentMethod, missing: "That linked account isn't in the vault.")
    }

    /// The person an account belongs to. Never made here: an update names people the memory holds.
    private static func owner(named wanted: String, in raw: [String: Any]) throws -> String {
        try named(wanted, in: raw, kind: .familyMember, missing: "No person in the memory is called \"\(wanted)\".")
    }

    /// A row a set names in passing — by id, else by a name only one row wears.
    private static func named(_ wanted: String, in raw: [String: Any], kind: VaultPatch.EntityKind, missing: String) throws -> String {
        let rows = raw[kind.rawValue] as? [[String: Any]] ?? []
        if let id = rows.first(where: { $0["id"] as? String == wanted })?["id"] as? String { return id }
        let key = nameKey(wanted)
        let matches = rows.filter { nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key }
        if matches.count > 1 {
            let word = kind == .paymentMethod ? "account" : "person"
            throw ApplyError.ambiguous("More than one \(word) is called \"\(wanted)\", so it could not be resolved to one of them — pass its id.")
        }
        guard let id = matches.first?["id"] as? String else { throw ApplyError.notFound(missing) }
        return id
    }

    /// The account or person a proposal names — by id, or by an exact name when unique.
    private static func findEntity(_ kind: VaultPatch.EntityKind, _ payload: [String: Any], in raw: [String: Any]) throws -> [String: Any] {
        let word = kind == .paymentMethod ? "account" : "person"
        let rows = raw[kind.rawValue] as? [[String: Any]] ?? []
        if let id = (payload["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            guard let row = rows.first(where: { $0["id"] as? String == id }) else {
                throw ApplyError.notFound("No \(word) with id \(id) is in the memory any more.")
            }
            return row
        }
        guard let name = (payload["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw ApplyError.invalid("This proposal named no \(word).")
        }
        let key = nameKey(name)
        let matches = rows.filter { nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key }
        if matches.isEmpty { throw ApplyError.notFound("No \(word) in the memory is called \"\(name)\".") }
        if matches.count > 1 { throw ApplyError.ambiguous("More than one \(word) is called \"\(name)\", so this could not be applied to one of them.") }
        return matches[0]
    }

    // MARK: - the file kinds

    /// Keys longbook fills in itself; a request that names them is refused, never half-read.
    private static let drawnKeys = ["id", "currency", "modules", "hidden_ids", "period", "scope", "subtitle"]

    /// A create_report payload checked again on this side — the days, the name and every
    /// account, person and category — and resolved to the memory's own names.
    public static func reportRequest(_ payload: [String: Any], in raw: [String: Any], now: Date) throws -> ReportRequest {
        if drawnKeys.contains(where: { payload[$0] != nil }) {
            throw ApplyError.invalid("longbook draws the report; name only title, start_date, end_date, accounts, members and categories.")
        }
        let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, title.count <= 80 else { throw ApplyError.invalid("A report needs a name of 1 to 80 characters.") }
        if let hit = scanText(title) { throw ApplyError.invalid(policyRefusal(hit, field: "title")) }
        guard let start = LB.parseDate(payload["start_date"] as? String), let end = LB.parseDate(payload["end_date"] as? String) else {
            throw ApplyError.invalid("A report needs a first and a last day, each a real day written YYYY-MM-DD.")
        }
        let today = LB.calendar.startOfDay(for: now)
        guard start <= end else { throw ApplyError.invalid("The report's first day comes after its last day.") }
        guard start <= today else { throw ApplyError.invalid("A report counts charges that have happened, so its first day cannot be after today.") }
        // 366 days counting both ends, as both MCP doors count them: a whole leap year passes.
        guard (LB.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 <= 366 else {
            throw ApplyError.invalid("A report covers at most 366 days.")
        }
        let scope = ReportScope(
            accounts: try names(payload, "accounts").map { try reportEntity($0, kind: .paymentMethod, none: "No account", in: raw) },
            members: try names(payload, "members").map { try reportEntity($0, kind: .familyMember, none: nil, in: raw) },
            categories: try names(payload, "categories").map { try reportCategory($0, in: raw) }
        )
        return ReportRequest(title: title, start: start, end: end, scope: scope.isEmpty ? nil : scope)
    }

    /// An optional list of names: absent or empty narrows nothing.
    private static func names(_ payload: [String: Any], _ key: String) throws -> [String] {
        guard let value = payload[key], !(value is NSNull) else { return [] }
        guard let list = value as? [Any], list.count <= 50 else { throw ApplyError.invalid("\(key) is a list of up to 50 names.") }
        var out: [String] = []
        for item in list {
            guard let name = (item as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 80 else {
                throw ApplyError.invalid("Each name in \(key) is 1 to 80 characters.")
            }
            if !out.contains(name) { out.append(name) }
        }
        return out
    }

    /// The account or person a report names, as the memory spells it. Never made here.
    private static func reportEntity(_ wanted: String, kind: VaultPatch.EntityKind, none: String?, in raw: [String: Any]) throws -> String {
        if let none, nameKey(wanted) == nameKey(none) { return none }
        let rows = raw[kind.rawValue] as? [[String: Any]] ?? []
        let word = kind == .paymentMethod ? "account" : "person"
        if let row = rows.first(where: { $0["id"] as? String == wanted }), let name = row["name"] as? String { return name }
        let matches = rows.filter { nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == nameKey(wanted) }
        if matches.count > 1 { throw ApplyError.ambiguous("More than one \(word) is called \"\(wanted)\".") }
        guard let name = matches.first?["name"] as? String else {
            let known = rows.compactMap { $0["name"] as? String }
            let list = known.isEmpty ? "There are none yet." : "The memory has: \(known.joined(separator: ", "))."
            throw ApplyError.notFound("No \(word) in the memory is called \"\(wanted)\". \(list)")
        }
        return name
    }

    /// A category as the commitments wear it, else as the tag list spells it.
    private static func reportCategory(_ wanted: String, in raw: [String: Any]) throws -> String {
        if nameKey(wanted) == nameKey("No category") { return "No category" }
        let worn = (raw["commitments"] as? [[String: Any]] ?? []).compactMap { ($0["tag"] as? String)?.trimmingCharacters(in: .whitespaces) }
        let listed = (raw["tags"] as? [[String: Any]] ?? [])
            .filter { ($0["kind"] as? String ?? "commitment") == "commitment" }
            .compactMap { $0["name"] as? String }
        if let found = (worn + listed).first(where: { !$0.isEmpty && nameKey($0) == nameKey(wanted) }) { return found }
        throw ApplyError.notFound("No category in the memory is called \"\(wanted)\".")
    }

    private static func insight(_ write: PendingWrite) throws -> Outcome {
        guard let module = (write.payload["module"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !module.isEmpty,
              let text = (write.payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { throw ApplyError.invalid("An insight needs a module and a note.") }
        return .insight(module: module, text: text)
    }

    // MARK: - shared

    /// Provenance for every row this proposal touched: the key's name, and where the data
    /// came from. VaultPatch already signed them as longbook, the commitment and each charge
    /// it wrote under it; this overwrites every entry the write added or changed with the truth.
    private static func sign(_ vault: [String: Any], from raw: [String: Any], ids: [String], write: PendingWrite, now: Date) -> [String: Any] {
        var next = vault
        var provenance = next["_provenance"] as? [String: Any] ?? [:]
        let before = raw["_provenance"] as? [String: Any] ?? [:]
        var entry: [String: Any] = ["edited_by": write.author, "edited_at": VaultPatch.iso8601(now)]
        if let source = write.sourceRef, !source.isEmpty { entry["source"] = source }
        for id in ids where !id.isEmpty {
            provenance[id] = entry
            for key in provenance.keys where key.hasPrefix(VaultPatch.chargeKey(id, "")) && !sameEntry(before[key], provenance[key]) {
                provenance[key] = entry
            }
        }
        next["_provenance"] = provenance
        return next
    }

    private static func sameEntry(_ a: Any?, _ b: Any?) -> Bool {
        guard let a = a as? [String: Any], let b = b as? [String: Any] else { return a == nil && b == nil }
        return NSDictionary(dictionary: a) == NSDictionary(dictionary: b)
    }

    /// The row a proposal names — by id, or by an exact name when it is unique.
    private static func find(_ payload: [String: Any], in raw: [String: Any]) throws -> [String: Any] {
        let rows = raw["commitments"] as? [[String: Any]] ?? []
        if let id = (payload["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            guard let row = rows.first(where: { $0["id"] as? String == id }) else {
                throw ApplyError.notFound("No commitment with id \(id) is in the memory any more.")
            }
            return row
        }
        guard let name = (payload["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw ApplyError.invalid("This proposal named no commitment.")
        }
        let key = nameKey(name)
        let matches = rows.filter { nameKey($0["name"] as? String ?? "") == key }
        if matches.isEmpty { throw ApplyError.notFound("Nothing in the memory is called \"\(name)\".") }
        if matches.count > 1 { throw ApplyError.ambiguous("More than one commitment is called \"\(name)\", so this could not be applied to one of them.") }
        return matches[0]
    }

    private static func decode(_ row: [String: Any]) throws -> Subscription {
        let data = try JSONSerialization.data(withJSONObject: row)
        return try JSONDecoder().decode(Subscription.self, from: data)
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    /// Details as lines after the notes, as `detailLines` words them; statement_line never folds.
    /// A line the notes hold by `noteLineKey` is not repeated; a card-name line naming another
    /// card stays beside the new one, both seen in Changes. The writer scans the result as any note.
    private static func folded(_ details: Details, into notes: String?) -> String? {
        var held = Set((notes ?? "").components(separatedBy: .newlines).map(noteLineKey))
        let lines = detailLines(details).filter { held.insert(noteLineKey($0)).inserted }
        guard !lines.isEmpty else { return notes }
        var kept = notes ?? ""
        while kept.last?.isWhitespace == true { kept.removeLast() }
        return ((kept.isEmpty ? [] : [kept]) + lines).joined(separator: "\n")
    }

    /// Whether a proposal sends a value, as the doors judge it: absent, null, or an empty text,
    /// list or object sends none.
    private static func sends(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let text = value as? String { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let list = value as? [Any] { return !list.isEmpty }
        if let object = value as? [String: Any] { return !object.isEmpty }
        return true
    }

    private static func decodeDetails(_ raw: [String: Any]) -> Details {
        var out: Details = [:]
        for (key, value) in raw {
            if let detail = detailValue(value) { out[key] = detail }
        }
        return out
    }

    private static func detailValue(_ value: Any) -> DetailValue? {
        switch value {
        case is NSNull: return .null
        case let b as Bool where type(of: value) == type(of: NSNumber(value: true)): return .bool(b)
        case let n as NSNumber:
            // NSNumber carries booleans too; the case above catches those first.
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let list as [Any]: return .list(list.compactMap(detailValue))
        default: return nil
        }
    }
}
