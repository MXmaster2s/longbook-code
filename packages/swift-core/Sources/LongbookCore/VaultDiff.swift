// An id-keyed diff between two RAW vault dictionaries — how the app tells the owner
// what an outside edit did, in the vault's own field names. Raw on purpose: a field
// this build has no model for still shows when someone else changes it.
import Foundation

public struct FieldChange {
    public let key: String
    public let before: String
    public let after: String
}

public struct RowChange {
    public let id: String
    /// The row's name, or its id when it has none — a change needs a subject.
    public let name: String
    public let fields: [FieldChange]
}

/// A row named well enough to act on: the id keys any follow-up, the name is what a
/// person reads. Added and removed rows also carry the money and a short note — a
/// commitment's cycle and tag, a charge's paid state — so a review can judge them.
public struct RowRef: Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let amount: Double?
    public let currency: String?
    /// The facts joined for one-line surfaces; the parts below are the same facts, apart.
    public let note: String?
    /// "Monthly", "Yearly", "One-time" or "Every N days".
    public let cycle: String?
    /// The category as written.
    public let tag: String?
    /// "Paid", "Paid on 2 Sep 2026" or "Planned".
    public let paid: String?
    /// "in" or "transfer" as the file keeps it, a charge borrowing its commitment's; nil
    /// for spending. A reviewer must be able to tell a transfer from a spend before keeping it.
    public let direction: String?

    public init(
        id: String, name: String, amount: Double? = nil, currency: String? = nil,
        note: String? = nil, cycle: String? = nil, tag: String? = nil, paid: String? = nil,
        direction: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.note = note
        self.cycle = cycle
        self.tag = tag
        self.paid = paid
        self.direction = direction
    }

    /// The direction in the reader's words, "Transfer" or "Money in"; nil for spending.
    public var directionWord: String? { movesWord(direction) }
}

private func movesWord(_ direction: String?) -> String? {
    switch direction {
    case "transfer": "Transfer"
    case "in": "Money in"
    default: nil
    }
}

public struct EntityDiff {
    /// "commitments", "accounts", "members", "tags" or "charges".
    public let kind: String
    /// Added rows, id and name both.
    public let added: [RowRef]
    /// Removed rows, id and name both.
    public let removed: [RowRef]
    public let changed: [RowChange]
}

/// Timestamps churn on every save; comparing them would call every write a change.
private let skippedKeys: Set<String> = ["updated_at", "created_at", "written_at"]

/// The row arrays, in the order the review presents them. Everything else at the
/// top level — _provenance, merge_undo — moves on every write and is never compared.
private let diffedKinds = ["commitments", "accounts", "members"]

/// Compare two raw vaults by row id. Only kinds with at least one change come back,
/// so a vault diffed against itself is an empty array.
public func vaultDiff(from old: [String: Any], to new: [String: Any]) -> [EntityDiff] {
    var diffs = diffedKinds.compactMap { kind in
        entityDiff(kind: kind, oldRows: rows(old[kind]), newRows: rows(new[kind]))
    }
    if let tags = entityDiff(kind: "tags", oldRows: tagRows(old["tags"]), newRows: tagRows(new["tags"])) {
        diffs.append(tags)
    }
    if let charges = chargesDiff(from: old, to: new) {
        diffs.append(charges)
    }
    return diffs
}

/// One kind's diff over rows already keyed. Nil when nothing in the kind moved, so an
/// untouched kind never reaches the story.
private func entityDiff(
    kind: String,
    oldRows: [(id: String, row: [String: Any])],
    newRows: [(id: String, row: [String: Any])]
) -> EntityDiff? {
    let oldById = Dictionary(oldRows.map { ($0.id, $0.row) }, uniquingKeysWith: { first, _ in first })
    let newById = Dictionary(newRows.map { ($0.id, $0.row) }, uniquingKeysWith: { first, _ in first })

    let added = newRows.filter { oldById[$0.id] == nil }
        .map { rowRef(kind: kind, $0.row, $0.id) }
    let removed = oldRows.filter { newById[$0.id] == nil }
        .map { rowRef(kind: kind, $0.row, $0.id) }
    let changed = newRows.compactMap { item -> RowChange? in
        guard let before = oldById[item.id] else { return nil }
        let fields = fieldChanges(before, item.row)
        return fields.isEmpty ? nil : RowChange(id: item.id, name: displayName(item.row, item.id), fields: fields)
    }

    if added.isEmpty && removed.isEmpty && changed.isEmpty { return nil }
    return EntityDiff(kind: kind, added: added, removed: removed, changed: changed)
}

/// Tag rows keyed by id, or by kind and name_key when an outside writer omitted the id.
/// The same tag then still matches itself across versions instead of reading as new.
private func tagRows(_ value: Any?) -> [(id: String, row: [String: Any])] {
    (value as? [[String: Any]] ?? []).compactMap { row in
        if let id = row["id"] as? String { return (id: id, row: row) }
        guard let kind = row["kind"] as? String, let key = row["name_key"] as? String else { return nil }
        return (id: "\(kind)/\(key)", row: row)
    }
}

/// Charges are keyed by (commitment_id, date) and carry fields that change — the amount,
/// paid, the day the money moved, a note — so they diff like any other row. Each is named
/// by its commitment and day so the review reads "Netflix — 2026-09-01".
private func chargesDiff(from old: [String: Any], to new: [String: Any]) -> EntityDiff? {
    // Names and currencies resolve against the newer vault first, then the older — a
    // charge of a commitment that was itself removed still reads by name, not by id.
    var names: [String: String] = [:]
    var currencies: [String: String] = [:]
    var directions: [String: String] = [:]
    for item in rows(old["commitments"]) + rows(new["commitments"]) {
        names[item.id] = displayName(item.row, item.id)
        if let currency = item.row["currency"] as? String { currencies[item.id] = currency }
        directions[item.id] = VaultPatch.storedDirection(item.row["direction"] as? String)
    }
    return entityDiff(
        kind: "charges",
        oldRows: chargeRows(old["charges"], names, currencies, directions),
        newRows: chargeRows(new["charges"], names, currencies, directions)
    )
}

/// Charge rows keyed by commitment and date, each given the name the review shows, its
/// commitment's currency when the row names none, and its commitment's direction. One map
/// serves both sides, so nothing borrowed is a change. A row missing half its identity
/// is skipped.
private func chargeRows(
    _ value: Any?, _ names: [String: String], _ currencies: [String: String], _ directions: [String: String]
) -> [(id: String, row: [String: Any])] {
    (value as? [[String: Any]] ?? []).compactMap { row in
        guard let commitment = row["commitment_id"] as? String, let date = row["date"] as? String else { return nil }
        var named = row
        named["name"] = "\(names[commitment] ?? commitment) — \(date)"
        if named["currency"] == nil || named["currency"] is NSNull {
            named["currency"] = currencies[commitment]
        }
        named["direction"] = directions[commitment]
        return (id: "\(commitment)@\(date)", row: named)
    }
}

/// Rows in file order, keyed by id. A row with no id can't be diffed and is skipped.
private func rows(_ value: Any?) -> [(id: String, row: [String: Any])] {
    (value as? [[String: Any]] ?? []).compactMap { row in
        (row["id"] as? String).map { (id: $0, row: row) }
    }
}

private func displayName(_ row: [String: Any], _ id: String) -> String {
    row["name"] as? String ?? id
}

/// An added or removed row with what a reviewer needs beside its name. Only the kinds
/// that carry money say any: a commitment its cycle and tag, a charge its paid state.
private func rowRef(kind: String, _ row: [String: Any], _ id: String) -> RowRef {
    let amount = (row["amount"] as? NSNumber)?.doubleValue
    let currency = row["currency"] as? String
    // Said first on a one-line surface: a transfer or money in must never read as a spend.
    let direction = VaultPatch.storedDirection(row["direction"] as? String)
    let moves = movesWord(direction)
    switch kind {
    case "commitments":
        let cycle: String? = switch row["billing_cycle"] as? String {
        case "monthly": "Monthly"
        case "yearly": "Yearly"
        case "once": "One-time"
        case "custom": "Every \((row["custom_cycle_days"] as? NSNumber)?.intValue ?? 30) days"
        default: nil
        }
        let tag = (row["tag"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let note = [moves, cycle, tag].compactMap { $0 }.joined(separator: " · ")
        return RowRef(id: id, name: displayName(row, id), amount: amount, currency: currency,
                      note: note.isEmpty ? nil : note, cycle: cycle, tag: tag, direction: direction)
    case "charges":
        let paid = (row["paid"] as? NSNumber)?.boolValue ?? false
        let paidOn = (row["paid_on"] as? String).flatMap { $0 == row["date"] as? String ? nil : $0 }
        let mark = paid ? (paidOn.map { "Paid on \(LB.parseDate($0).map(LB.longDate) ?? $0)" } ?? "Paid") : "Planned"
        let note = [moves, mark].compactMap { $0 }.joined(separator: " · ")
        return RowRef(id: id, name: displayName(row, id), amount: amount, currency: currency, note: note, paid: mark,
                      direction: direction)
    default:
        return RowRef(id: id, name: displayName(row, id))
    }
}

/// Field-level compare over the union of keys, alphabetical for a stable story. Equal
/// display strings mean no change — 1 and 1.0 read the same, so they are the same.
private func fieldChanges(_ old: [String: Any], _ new: [String: Any]) -> [FieldChange] {
    Set(old.keys).union(new.keys).subtracting(skippedKeys).sorted().compactMap { key in
        let before = display(old[key])
        let after = display(new[key])
        return before == after ? nil : FieldChange(key: key, before: before, after: after)
    }
}

/// A changed `details` object opened into its own keys, "details.card_name", each value
/// as a detail row reads everywhere else: "yes" or "no", a list joined, "—" when unset.
/// Nil when the field is not `details`, or either side is not a flat object.
public func detailChanges(_ field: FieldChange) -> [FieldChange]? {
    func object(_ text: String) -> Details? {
        if text == "—" { return [:] }
        return try? JSONDecoder().decode(Details.self, from: Data(text.utf8))
    }
    guard field.key == "details", let before = object(field.before), let after = object(field.after) else { return nil }
    func word(_ value: DetailValue?) -> String {
        let text = value?.display ?? ""
        return text.isEmpty ? "—" : text
    }
    return Set(before.keys).union(after.keys).sorted().compactMap { key in
        let was = word(before[key]), now = word(after[key])
        return was == now ? nil : FieldChange(key: "details.\(key)", before: was, after: now)
    }
}

/// A raw JSON value as the review renders it: "—" for null or absent, numbers without
/// a trailing .0, containers as canonical JSON. User data is never re-cased.
private func display(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "—" }
    if let text = value as? String { return text }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        let d = number.doubleValue
        return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : "\(d)"
    }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let json = String(data: data, encoding: .utf8) {
        return json
    }
    return "\(value)"
}
