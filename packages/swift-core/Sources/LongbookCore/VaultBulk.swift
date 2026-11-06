// Many rows in one write: a Category or a Person across commitments, many charges, commitments
// or entities deleted, two or more people or accounts merged. One write is one entry in
// History, so every function here builds the whole change before anything reaches the file.
import Foundation

extension VaultPatch {
    /// The key a kept person or account lists the names merged into it under, in `details`.
    public static let mergedNamesKey = "merged_names"

    /// The names merged into a person's or an account's row. A statement printing one means this row.
    public static func mergedNames(of row: [String: Any]) -> [String] {
        (row["details"] as? [String: Any])?[mergedNamesKey] as? [String] ?? []
    }

    /// What a bulk change reaches. Several cards of one commitment change it once.
    public struct BulkReach: Equatable, Sendable {
        /// The cards chosen.
        public let cards: Int
        /// The commitments those cards belong to.
        public let commitments: Int
        /// The charges those commitments hold, chosen or not: a commitment's change reaches them all.
        public let charges: Int
        /// Those commitments that are transfers, whose people come from their accounts' owners.
        public let transfers: Int
    }

    /// The reach of the cards naming these commitments, one id per card.
    public static func bulkReach(cardsOf ids: [String], in raw: [String: Any]) -> BulkReach {
        let wanted = Set(ids)
        let charges = chargeRows(raw).filter { wanted.contains($0["commitment_id"] as? String ?? "") }.count
        let rows = (raw["commitments"] as? [[String: Any]] ?? []).filter { wanted.contains($0["id"] as? String ?? "") }
        let transfers = rows.filter { storedDirection($0["direction"] as? String) == "transfer" }.count
        return BulkReach(cards: ids.count, commitments: rows.count, charges: charges, transfers: transfers)
    }

    /// Changes each named commitment `change` says changed, and signs those. An id the vault
    /// does not hold refuses the whole change.
    private static func changing(
        _ ids: [String], in raw: [String: Any], now: Date, _ change: (inout [String: Any]) -> Bool
    ) throws -> [String: Any] {
        let wanted = Set(ids)
        var rows = raw["commitments"] as? [[String: Any]] ?? []
        let held = Set(rows.compactMap { $0["id"] as? String })
        if let missing = wanted.subtracting(held).sorted().first { throw WriteError.notFound(missing) }
        var changed: [String] = []
        let stamp = iso8601(now)
        for index in rows.indices {
            guard let id = rows[index]["id"] as? String, wanted.contains(id), change(&rows[index]) else { continue }
            rows[index]["updated_at"] = stamp
            changed.append(id)
        }
        guard !changed.isEmpty else { return raw }
        var vault = raw
        vault["commitments"] = rows
        return sign(ids: changed, in: vault, now: now)
    }

    /// One category on every named commitment; nil takes it off. A new name joins the registry.
    public static func setCategory(_ tag: String?, onCommitments ids: [String], in raw: [String: Any], now: Date) throws -> [String: Any] {
        let clean = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = clean?.isEmpty == false ? clean : nil
        if let wanted { try refuseSecrets(wanted) }
        let next = try changing(ids, in: raw, now: now) { row in
            guard row["tag"] as? String != wanted else { return false }
            setOrClear(&row, "tag", wanted)
            return true
        }
        return wanted.map { ensureTag(kind: "commitment", named: $0, in: next, now: now) } ?? next
    }

    /// One person on every named commitment: To Person on money out, From Person on money in.
    /// Nil takes them off. A transfer stays as it is: its people are its accounts' owners.
    public static func setPerson(_ memberId: String?, onCommitments ids: [String], in raw: [String: Any], now: Date) throws -> [String: Any] {
        if let memberId {
            let people = raw[EntityKind.familyMember.rawValue] as? [[String: Any]] ?? []
            guard people.contains(where: { $0["id"] as? String == memberId }) else {
                throw WriteError.invalid("That person isn't in the vault.")
            }
        }
        return try changing(ids, in: raw, now: now) { row in
            guard storedDirection(row["direction"] as? String) != "transfer", row["member_id"] as? String != memberId else { return false }
            setOrClear(&row, "member_id", memberId)
            return true
        }
    }

    /// Takes the named days out and signs each as the app's own charge, so the removal reads
    /// as the owner's wherever the file lands next; each commitment's own entry is left as it
    /// is. Nothing named on file leaves the file as it was.
    public static func removeCharges(_ named: [(commitmentId: String, date: String)], in raw: [String: Any], now: Date) -> [String: Any] {
        var gone: [String: Set<String>] = [:]
        for row in named { gone[row.commitmentId, default: []].insert(row.date) }
        var removed: [String: Set<String>] = [:]
        let kept = chargeRows(raw).filter { row in
            guard let id = row["commitment_id"] as? String, let date = row["date"] as? String,
                  gone[id]?.contains(date) == true else { return true }
            removed[id, default: []].insert(date)
            return false
        }
        guard !removed.isEmpty else { return raw }
        var vault = setChargeRows(kept, in: raw)
        let stamp = iso8601(now)
        for (id, dates) in removed { signCharges(&vault, of: id, dates: dates, at: stamp) }
        return vault
    }

    /// Many charge cards deleted at once. A one-time commitment is its one charge, so one left
    /// with none goes too, or every card taken here would stay behind as an empty commitment.
    public static func deleteChargeCards(_ named: [(commitmentId: String, date: String)], in raw: [String: Any], now: Date) throws -> [String: Any] {
        let next = removeCharges(named, in: raw, now: now)
        let holding = Set(chargeRows(next).compactMap { $0["commitment_id"] as? String })
        let wanted = Set(named.map(\.commitmentId))
        let emptied = (next["commitments"] as? [[String: Any]] ?? []).compactMap { row -> String? in
            guard let id = row["id"] as? String, wanted.contains(id), !holding.contains(id),
                  row["billing_cycle"] as? String == BillingCycle.once.rawValue else { return nil }
            return id
        }
        return emptied.isEmpty ? next : try delete(ids: emptied, from: next, now: now)
    }

    /// Each commitment, and every charge of it, off the file. The commitment's entry and each
    /// removed charge's stay signed as the app's, so the owner's other device adopts the
    /// removal instead of asking. `pruneTombstones` sweeps them a month on.
    public static func delete(ids: [String], from raw: [String: Any], now: Date) throws -> [String: Any] {
        let wanted = Set(ids)
        var vault = raw
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        let held = Set(subs.compactMap { $0["id"] as? String })
        if let missing = wanted.subtracting(held).sorted().first { throw WriteError.notFound(missing) }
        subs.removeAll { wanted.contains($0["id"] as? String ?? "") }
        vault["commitments"] = subs
        let stamp = iso8601(now)
        var removed: [String: [String]] = [:]
        var kept: [[String: Any]] = []
        for row in chargeRows(vault) {
            if let id = row["commitment_id"] as? String, wanted.contains(id) {
                if let date = row["date"] as? String { removed[id, default: []].append(date) }
            } else {
                kept.append(row)
            }
        }
        for id in wanted.sorted() {
            vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
            signCharges(&vault, of: id, dates: removed[id] ?? [], at: stamp)
        }
        return setChargeRows(kept, in: vault)
    }

    /// Delete each, and unhook every commitment that pointed at one. The commitments stay: the
    /// money was still spent, it simply no longer says from where or for whom.
    public static func deleteEntities(
        _ kind: EntityKind, ids: [String], in raw: [String: Any], now: Date
    ) throws -> [String: Any] {
        let wanted = Set(ids)
        var vault = raw
        var rows = vault[kind.rawValue] as? [[String: Any]] ?? []
        let held = Set(rows.compactMap { $0["id"] as? String })
        if let missing = wanted.subtracting(held).sorted().first { throw WriteError.notFound(missing) }
        let goneNames = rows.filter { wanted.contains($0["id"] as? String ?? "") }.compactMap { $0["name"] as? String }
        rows.removeAll { wanted.contains($0["id"] as? String ?? "") }
        let surviving = rows.compactMap { $0["name"] as? String }

        let stamp = iso8601(now)
        // Its children stop hanging under it — an account that's gone can't be pointed at.
        for index in rows.indices where wanted.contains(rows[index]["parent_account_id"] as? String ?? "") {
            rows[index]["parent_account_id"] = NSNull()
            if let childId = rows[index]["id"] as? String {
                vault["_provenance"] = stamped(vault["_provenance"], id: childId, at: stamp)
            }
        }
        vault[kind.rawValue] = rows

        // A person's accounts stay, belonging to nobody: no member_id is left dangling.
        if kind == .familyMember {
            var accounts = vault[EntityKind.paymentMethod.rawValue] as? [[String: Any]] ?? []
            for index in accounts.indices where wanted.contains(accounts[index]["member_id"] as? String ?? "") {
                accounts[index]["member_id"] = NSNull()
                if let accountId = accounts[index]["id"] as? String {
                    vault["_provenance"] = stamped(vault["_provenance"], id: accountId, at: stamp)
                }
            }
            if vault[EntityKind.paymentMethod.rawValue] != nil { vault[EntityKind.paymentMethod.rawValue] = accounts }
        }

        let key = foreignKey(kind)
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        for index in subs.indices {
            var changed = false
            if wanted.contains(subs[index][key] as? String ?? "") {
                subs[index][key] = NSNull()
                changed = true
            }
            // Nor can a row name a gone account as its other side.
            if kind == .paymentMethod, namesGoneAccount(subs[index], ids: wanted, names: goneNames, surviving: surviving) {
                clearCounterpart(&subs[index])
                changed = true
            }
            guard changed else { continue }
            subs[index]["updated_at"] = stamp
            if let subId = subs[index]["id"] as? String {
                vault["_provenance"] = stamped(vault["_provenance"], id: subId, at: stamp)
            }
        }
        vault["commitments"] = subs
        // Each entity's own entry stays as a tombstone, so the other device adopts the delete.
        for id in wanted.sorted() { vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp) }
        // A Self person or an account gone can end a transfer.
        return StatementTransfers.apply(vault, now: now)
    }

    /// Whether a row's other side is one of these accounts: by id, or by a name no surviving
    /// account answers to.
    private static func namesGoneAccount(_ row: [String: Any], ids: Set<String>, names: [String], surviving: [String]) -> Bool {
        guard let details = row["details"] as? [String: Any] else { return false }
        if let id = details[StatementImport.counterpartAccountIdKey] as? String { return ids.contains(id) }
        guard let name = details[StatementImport.counterpartAccountKey] as? String else { return false }
        return names.contains { StatementCounterparts.sameAccount($0, name) } && !surviving.contains { StatementCounterparts.sameAccount($0, name) }
    }

    /// A row with no other side: both its keys go, and how its line printed stays for the rule.
    static func clearCounterpart(_ row: inout [String: Any]) {
        guard var details = row["details"] as? [String: Any] else { return }
        details.removeValue(forKey: StatementImport.counterpartAccountIdKey)
        details.removeValue(forKey: StatementImport.counterpartAccountKey)
        if details.isEmpty { row.removeValue(forKey: "details") } else { row["details"] = details }
    }

    // MARK: merging

    /// What a row's name is, or is about, rather than a field it can take from another.
    private static let ownKeys: Set<String> = [
        "id", "name", "name_key", "created_at", "is_incomplete", "avatar_seed", "details",
        "balance", "balance_date", "parent_account_id",
    ]

    /// Whether a field says nothing: absent, null or blank.
    private static func isBlank(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return true }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false
    }

    /// The kept row takes a field only where its own is empty, so a photo of its own stays and
    /// a merged one goes. A balance and its date are one fact, so they come together.
    private static func fill(_ kept: inout [String: Any], from row: [String: Any]) {
        for (key, value) in row where !ownKeys.contains(key) && isBlank(kept[key]) && !isBlank(value) { kept[key] = value }
        // Notes are what someone wrote, so neither side's is dropped: each on its own line.
        if let more = row["notes"] as? String, !isBlank(more), let own = kept["notes"] as? String,
           !own.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == more.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            kept["notes"] = own + "\n" + more
        }
        if isBlank(kept["balance"]), !isBlank(row["balance"]) {
            kept["balance"] = row["balance"]
            kept["balance_date"] = row["balance_date"] ?? NSNull()
        }
        if isBlank(kept["created_at"]), !isBlank(row["created_at"]) { kept["created_at"] = row["created_at"] }
        // A row described on either side is described.
        if kept["is_incomplete"] as? Bool == true, row["is_incomplete"] as? Bool != true { kept["is_incomplete"] = false }
        var details = kept["details"] as? [String: Any] ?? [:]
        for (key, value) in row["details"] as? [String: Any] ?? [:] where key != mergedNamesKey && isBlank(details[key]) { details[key] = value }
        if !details.isEmpty { kept["details"] = details }
    }

    /// Writes the merged rows' names, and whatever names were merged into them, into the kept row.
    private static func remember(_ merged: [[String: Any]], in kept: inout [String: Any]) {
        var seen = Set([nameKey(kept["name"] as? String)])
        var names: [String] = []
        for name in mergedNames(of: kept) + merged.flatMap({ [$0["name"] as? String ?? ""] + mergedNames(of: $0) })
        where !name.isEmpty && seen.insert(nameKey(name)).inserted {
            names.append(name)
        }
        guard !names.isEmpty else { return }
        var details = kept["details"] as? [String: Any] ?? [:]
        details[mergedNamesKey] = names
        kept["details"] = details
    }

    /// Accounts hang one level deep, so a kept account with a link of its own passes anything
    /// that hung under a merged one up to that link; with none it takes a merged one's link,
    /// unless something now hangs under it.
    private static func relink(_ rows: inout [[String: Any]], keep: String, gone: Set<String>, merged: [[String: Any]]) -> [String] {
        func parent(_ row: [String: Any]) -> String? { row["parent_account_id"] as? String }
        let inside = gone.union([keep])
        let underKeep = rows.contains { $0["id"] as? String != keep && parent($0).map(inside.contains) == true }
        guard let at = rows.firstIndex(where: { $0["id"] as? String == keep }) else { return [] }
        var link = parent(rows[at]).flatMap { inside.contains($0) ? nil : $0 }
        if link == nil, !underKeep { link = merged.lazy.compactMap(parent).first { !inside.contains($0) } }
        if let link { rows[at]["parent_account_id"] = link } else if parent(rows[at]) != nil { rows[at]["parent_account_id"] = NSNull() }
        var moved: [String] = []
        for index in rows.indices where index != at {
            guard let held = parent(rows[index]), inside.contains(held) else { continue }
            let wanted = link.flatMap { $0 == rows[index]["id"] as? String ? nil : $0 } ?? (link == nil ? keep : nil)
            if wanted == held { continue }
            rows[index]["parent_account_id"] = wanted ?? NSNull()
            if let id = rows[index]["id"] as? String { moved.append(id) }
        }
        return moved
    }

    /// Two or more people or accounts become one in one write: every link to a merged row moves
    /// to the kept one, the kept row fills its empty fields from them and remembers their names,
    /// and the Transfers rule runs over the result. Their entries stay as tombstones.
    public static func mergeEntities(
        _ kind: EntityKind, keeping keep: String, merging ids: [String], in raw: [String: Any], now: Date
    ) throws -> [String: Any] {
        let gone = Set(ids).subtracting([keep])
        guard !gone.isEmpty else { throw WriteError.invalid("Choose at least two to merge.") }
        var vault = raw
        var rows = vault[kind.rawValue] as? [[String: Any]] ?? []
        let held = Set(rows.compactMap { $0["id"] as? String })
        if let missing = gone.union([keep]).subtracting(held).sorted().first { throw WriteError.notFound(missing) }
        let merged = rows.filter { gone.contains($0["id"] as? String ?? "") }
        rows.removeAll { gone.contains($0["id"] as? String ?? "") }
        guard let at = rows.firstIndex(where: { $0["id"] as? String == keep }) else { throw WriteError.notFound(keep) }
        var kept = rows[at]
        for row in merged { fill(&kept, from: row) }
        remember(merged, in: &kept)
        rows[at] = kept
        let keptName = kept["name"] as? String ?? ""

        var touched = gone.union([keep])
        if kind == .paymentMethod { touched.formUnion(relink(&rows, keep: keep, gone: gone, merged: merged)) }
        vault[kind.rawValue] = rows
        if kind == .familyMember { touched.formUnion(moveOwners(in: &vault, keep: keep, keptName: keptName, gone: gone, merged: merged)) }
        touched.formUnion(moveCommitments(in: &vault, kind: kind, keep: keep, keptName: keptName, gone: gone, merged: merged, now: now))
        touched.formUnion(moveGroups(in: &vault, kind: kind, keep: keep, gone: gone))
        return StatementTransfers.apply(sign(ids: touched.sorted(), in: vault, now: now), now: now)
    }

    /// A merged person's accounts become the kept person's. A digit-less account's key names
    /// its owner, so it follows, unless the kept person holds one under that key already.
    private static func moveOwners(
        in vault: inout [String: Any], keep: String, keptName: String, gone: Set<String>, merged: [[String: Any]]
    ) -> [String] {
        var accounts = vault[EntityKind.paymentMethod.rawValue] as? [[String: Any]] ?? []
        var keys = Set(accounts.map { nameKey($0["name_key"] as? String) })
        var moved: [String] = []
        for index in accounts.indices where gone.contains(accounts[index]["member_id"] as? String ?? "") {
            accounts[index]["member_id"] = keep
            if let id = accounts[index]["id"] as? String { moved.append(id) }
            let key = nameKey(accounts[index]["name_key"] as? String)
            guard let bar = key.firstIndex(of: "|") else { continue }
            let next = key[..<bar] + "|" + nameKey(keptName)
            if keys.insert(String(next)).inserted { accounts[index]["name_key"] = String(next) }
        }
        if !moved.isEmpty { vault[EntityKind.paymentMethod.rawValue] = accounts }
        return moved
    }

    /// Every commitment naming a merged row names the kept one. A row naming the other side's
    /// account by id or by a name no surviving account answers to moves too.
    private static func moveCommitments(
        in vault: inout [String: Any], kind: EntityKind, keep: String, keptName: String, gone: Set<String>,
        merged: [[String: Any]], now: Date
    ) -> [String] {
        let key = foreignKey(kind)
        let goneNames = merged.compactMap { $0["name"] as? String }
        let surviving = (vault[kind.rawValue] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let stamp = iso8601(now)
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        var moved: [String] = []
        for index in subs.indices {
            var changed = false
            if gone.contains(subs[index][key] as? String ?? "") {
                subs[index][key] = keep
                changed = true
            }
            if kind == .paymentMethod, namesGoneAccount(subs[index], ids: gone, names: goneNames, surviving: surviving),
               var details = subs[index]["details"] as? [String: Any] {
                details[StatementImport.counterpartAccountIdKey] = keep
                details[StatementImport.counterpartAccountKey] = keptName
                subs[index]["details"] = details
                changed = true
            }
            // A transfer between the two is no transfer once they are one account.
            if kind == .paymentMethod, subs[index][key] as? String == keep,
               (subs[index]["details"] as? [String: Any])?[StatementImport.counterpartAccountIdKey] as? String == keep {
                clearCounterpart(&subs[index])
                changed = true
            }
            guard changed else { continue }
            subs[index]["updated_at"] = stamp
            if let id = subs[index]["id"] as? String { moved.append(id) }
        }
        if !moved.isEmpty { vault["commitments"] = subs }
        return moved
    }

    /// A group holding a merged row holds the kept one, once.
    private static func moveGroups(in vault: inout [String: Any], kind: EntityKind, keep: String, gone: Set<String>) -> [String] {
        let key = kind == .paymentMethod ? "account_ids" : "member_ids"
        guard var groups = vault["groups"] as? [[String: Any]] else { return [] }
        var moved: [String] = []
        for index in groups.indices {
            guard let held = groups[index][key] as? [String], held.contains(where: gone.contains) else { continue }
            var seen = Set<String>()
            groups[index][key] = held.map { gone.contains($0) ? keep : $0 }.filter { seen.insert($0).inserted }
            if let id = groups[index]["id"] as? String { moved.append(id) }
        }
        if !moved.isEmpty { vault["groups"] = groups }
        return moved
    }
}

extension ReportScope {
    /// The scope with these names of one kind called by the kept one. A scope holds names, so
    /// without this a trip naming a merged person could never be drawn again.
    public func merging(_ kind: VaultPatch.EntityKind, names: Set<String>, into kept: String) -> ReportScope {
        func moved(_ list: [String]) -> [String] {
            guard list.contains(where: names.contains) else { return list }
            var seen = Set<String>()
            return list.map { names.contains($0) ? kept : $0 }.filter { seen.insert($0).inserted }
        }
        return kind == .paymentMethod
            ? ReportScope(accounts: moved(accounts), members: members, categories: categories)
            : ReportScope(accounts: accounts, members: moved(members), categories: categories)
    }
}
