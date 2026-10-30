// Editing a vault this app only partly understands. The phone models a SLICE; the file
// holds more. "Decode, re-encode" would silently delete unknown fields, so instead: keep
// RAW JSON, patch only the touched keys.
//
// Three disciplines: SIGN THE EDIT, DON'T ROLL DATES FORWARD, PREFER CANCELLING TO DELETING.
import Foundation

/// Who we are in `_provenance`, on the phone and the Mac alike: one name, so a row signed
/// on either device reads as the owner's on the other. "phone", not "ios": says WHAT
/// edited, not which vendor. Retired "longbook-ios" stays one of ours forever.
let LB_PROVENANCE = "longbook-phone"

// MARK: - what an edit is

/// The form's output — only the fields the phone lets you touch. Anything absent here is a field
/// the phone doesn't model, and patching leaves it exactly as it was. Equatable so a form can
/// compare against the snapshot it opened with before discarding unsaved typing.
public struct SubEdit: Equatable {
    /// nil means "a new commitment"; otherwise the existing row's id, which is load-bearing and is
    /// never regenerated on an edit (it's what `family_member_id` links and what provenance keys).
    public var id: String?
    public var name: String = ""
    public var amount: Double = 0
    public var currency: String = "INR"
    public var billingCycle: BillingCycle = .monthly
    public var customCycleDays: Int?
    public var status: SubStatus = .active
    public var tag: String?
    public var notes: String?
    public var familyMemberId: String?
    public var paymentMethodId: String?
    /// ISO YYYY-MM-DD. The day it stops. Still active until then, and the row says so — this
    /// is the contract's preferred alternative to deleting something that really existed.
    public var scheduledCancelDate: String?
    /// nil leaves the row's details exactly as found; a value replaces the whole object. A
    /// commitment's details are longbook's own — the line a statement printed. Only its own writes
    /// bring new ones; an edit loaded from a row carries that row's, and the form clears it.
    public var details: Details?
    /// The first charge's day, ISO. Required for a new commitment — it is where the plan
    /// starts, or a one-time commitment's own date. An existing commitment one-time after the
    /// edit moves its single charge here, whatever its cycle was, and refuses it while holding
    /// several; a recurring one ignores it.
    public var firstCharge: String?
    /// How many months of charges to write for a new recurring commitment. nil plans the
    /// default; the rows are written once, and only more when someone asks.
    public var planMonths: Int?
    /// How many charges a new recurring commitment is planned with, counted from its first.
    /// When set, `planMonths` is not read: the count the form shows is the count written.
    public var planCount: Int?
    /// The day an amount change applies from, ISO. nil means today. Only unpaid planned
    /// charges on or after it take the new amount; nothing before today ever does.
    public var amountFrom: String?
    /// "in" for money that arrives, "transfer" for a movement between the owner's own
    /// accounts. nil or anything else is a charge.
    public var direction: String?
    /// The free trial tick: a flag on the row, `free_trial`, that `isFreeTrial` reads back as
    /// the pill. It writes no charge and moves nothing; false takes the key off the row.
    public var freeTrial: Bool = false

    public init(id: String? = nil) { self.id = id }

    /// Load an existing row into the form. Reads from the DECODED model — safe, because this
    /// direction only feeds the UI; the write path reads the raw dict.
    public init(from sub: Subscription) {
        id = sub.id
        name = sub.name
        amount = sub.amount
        currency = sub.currency
        billingCycle = sub.billingCycle
        customCycleDays = sub.customCycleDays
        status = sub.status
        tag = sub.tag
        notes = sub.notes
        familyMemberId = sub.familyMemberId
        paymentMethodId = sub.paymentMethodId
        scheduledCancelDate = sub.scheduledCancelDate
        direction = sub.direction
        details = sub.details
        freeTrial = sub.freeTrial == true
    }
}

/// How far a new recurring commitment is planned when nobody says: two years of charges,
/// written once. The app never extends a plan on its own; it says when one runs short.
public let DEFAULT_PLAN_MONTHS = 24

/// The largest amount a write takes. Past it a figure is a slip of the keyboard, and a
/// form could no longer show it digit for digit.
public let AMOUNT_LIMIT: Double = 1e15

/// The most days a custom cycle holds between charges, a hundred years. Every door refuses
/// more; one already in a file steps as this many.
public let CUSTOM_DAYS_LIMIT = 36_500

public enum WriteError: LocalizedError {
    case invalid(String)
    case conflict
    case notFound(String)
    case badDate
    case dayTaken(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let why): return why
        case .notFound(let id): return "That commitment is no longer in the vault (\(id))."
        case .badDate: return "That is not a day (YYYY-MM-DD)."
        case .dayTaken(let day):
            // The payload is the file's own ISO word; a reader is shown the day.
            let word = LB.parseDate(day).map { LB.longDate($0) } ?? day
            return "A charge already sits on \(word). Move or remove it first."
        case .conflict:
            // The desktop refuses the same way, with the same reasoning: the outside edit is data
            // someone deliberately made, and ours is a form we can simply present again.
            return "Your file changed on another device while you were editing. Your change wasn’t saved, so nothing was lost on either side. Reload and try again."
        }
    }
}

public extension Error {
    /// A message safe to show the owner. `WriteError`/`ReadError` already speak the product's voice;
    /// this passes those through. Everything else is Foundation's own wording — Title Case, sometimes
    /// a filename — so it gets an honest fallback instead, rather than a guessed-wrong specific one.
    var friendlyDescription: String {
        if let described = (self as? LocalizedError)?.errorDescription { return described }
        return "That didn’t work, and longbook can’t say more precisely why. Try again. If it keeps happening, check Settings → About for how to reach us."
    }
}

// MARK: - validation

/// What the owner typed, checked before it reaches the file. Deliberately NOT a general
/// JSON-Schema engine — checks only what a bad form entry can break: required fields,
/// enums in range, real ISO dates. Consults `longbook.schema.json` where available.
enum SubValidator {
    static let requiredKeys = ["id", "name", "amount", "currency", "billing_cycle", "status"]

    /// `schema` is the parsed `longbook.schema.json` when the vault has one. A price or a custom
    /// cycle the write leaves as it was is the file's already, so only a changed one meets its
    /// limits.
    static func validate(_ row: [String: Any], schema: [String: Any]? = nil, priceChanged: Bool = true,
                         daysChanged: Bool = true) throws {
        let required = schemaRequired(schema) ?? requiredKeys
        for key in required where row[key] == nil {
            throw WriteError.invalid("A commitment needs \(key.replacingOccurrences(of: "_", with: " ")).")
        }

        guard let name = row["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WriteError.invalid("Give it a name. That's what you'll recognise it by.")
        }
        guard let amount = row["amount"] as? Double else {
            throw WriteError.invalid("The amount has to be a number, and not a negative one.")
        }
        if priceChanged { try VaultPatch.checkAmount(amount) }
        guard let currency = row["currency"] as? String, !currency.isEmpty else {
            throw WriteError.invalid("Pick a currency. longbook never blends two of them into one total.")
        }

        try checkEnum(row, key: "billing_cycle", fallback: ["monthly", "yearly", "custom", "once"], schema: schema)
        try checkEnum(row, key: "status", fallback: ["active", "paused", "cancelled"], schema: schema)

        if let cancel = row["ends_on"] as? String, LB.parseDate(cancel) == nil {
            throw WriteError.invalid("That cancelling date isn’t a real calendar day.")
        }
        if (row["billing_cycle"] as? String) == "custom" {
            guard let days = row["custom_cycle_days"] as? Int else {
                throw WriteError.invalid("A custom cycle needs how many days between charges.")
            }
            if daysChanged, !(1...CUSTOM_DAYS_LIMIT).contains(days) {
                throw WriteError.invalid("A custom cycle is 1 to 36,500 days between charges.")
            }
        }
    }

    private static func checkEnum(_ row: [String: Any], key: String, fallback: [String], schema: [String: Any]?) throws {
        let allowed = schemaEnum(schema, key: key) ?? fallback
        guard let value = row[key] as? String, allowed.contains(value) else {
            throw WriteError.invalid("\(key.replacingOccurrences(of: "_", with: " ")) has to be one of: \(allowed.joined(separator: ", ")).")
        }
    }

    // The two readers below walk to `properties.subscriptions.items` in the shipped schema. If the
    // shape ever changes they return nil and the fallbacks apply — degrading to slightly-stale
    // rules, never to an unchecked write.
    private static func subItems(_ schema: [String: Any]?) -> [String: Any]? {
        guard let props = schema?["properties"] as? [String: Any],
              let subs = props["commitments"] as? [String: Any],
              let items = subs["items"] as? [String: Any]
        else { return nil }
        return items
    }

    private static func schemaRequired(_ schema: [String: Any]?) -> [String]? {
        subItems(schema)?["required"] as? [String]
    }

    private static func schemaEnum(_ schema: [String: Any]?, key: String) -> [String]? {
        guard let props = subItems(schema)?["properties"] as? [String: Any],
              let field = props[key] as? [String: Any]
        else { return nil }
        return field["enum"] as? [String]
    }
}

// MARK: - patching

public enum VaultPatch {
    /// An amount a write may hold: a number, not negative, within `AMOUNT_LIMIT`. Refused in the
    /// words every form shows, so a form can ask before it writes.
    public static func checkAmount(_ amount: Double) throws {
        guard amount.isFinite, amount >= 0 else {
            throw WriteError.invalid("The amount has to be a number, and not a negative one.")
        }
        guard amount <= AMOUNT_LIMIT else {
            throw WriteError.invalid("The amount can't be more than 1,000,000,000,000,000.")
        }
    }

    /// Why a recurring commitment holding several charges cannot become a one-time one: the
    /// switch would leave one charge standing for all of them. The form says it in these words.
    public static func oneTimeRefusal(charges: Int) -> String {
        "One-time holds a single charge, and this has \(charges). Cancel it instead to stop its plan."
    }

    /// Why a one-time commitment holding several charges takes no date: one day cannot stand
    /// for them all, so each moves from its own charge.
    public static func oneTimeMoveRefusal(charges: Int) -> String {
        "This one-time commitment has \(charges) charges. Move the one you mean from the charge itself."
    }

    /// Apply an edit to the raw vault, returning a NEW raw vault. Pure — no file work — so the tests
    /// can prove the preservation rule without touching a disk.
    ///
    /// `now` is injected rather than read from the clock, so the provenance timestamp is assertable.
    public static func apply(_ edit: SubEdit, to raw: [String: Any], now: Date, schema: [String: Any]? = nil) throws -> [String: Any] {
        var vault = raw
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        let stamp = iso8601(now)

        let id = edit.id ?? UUID().uuidString.lowercased()   // lowercase to match the desktop's randomUUID()
        let index = subs.firstIndex { $0["id"] as? String == id }
        if edit.id != nil && index == nil { throw WriteError.notFound(id) }

        // THE PRESERVATION RULE, in one line: start from the row that's on disk (every key it has,
        // known to this build or not) and overwrite only what the form owns. A new row starts empty.
        var row = index.map { subs[$0] } ?? [:]
        // A row seeded with only an id (the proposal path does this) is as new as no row.
        let previousAmount = row["amount"] as? Double
        let isNew = index == nil || previousAmount == nil
        let previousStatus = (row["status"] as? String).flatMap(SubStatus.init(rawValue:))
        let previousEnd = row["ends_on"] as? String
        let wasOnce = (row["billing_cycle"] as? String) == BillingCycle.once.rawValue
        // A custom cycle the file already holds, days and all, is the file's own.
        let sameDays = (row["billing_cycle"] as? String) == BillingCycle.custom.rawValue
            && (row["custom_cycle_days"] as? Int) == edit.customCycleDays
        let held = isNew ? 0 : chargeRows(raw).filter { $0["commitment_id"] as? String == id }.count
        // A recurring commitment's charges are its history and its plan; one row cannot hold them.
        if !wasOnce, edit.billingCycle == .once, held > 1 { throw WriteError.invalid(oneTimeRefusal(charges: held)) }
        // Nor can one date stand for a one-time commitment's several charges.
        if edit.billingCycle == .once, LB.parseDate(edit.firstCharge) != nil, held > 1 {
            throw WriteError.invalid(oneTimeMoveRefusal(charges: held))
        }
        row["id"] = id
        row["name"] = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        row["amount"] = edit.amount
        row["currency"] = edit.currency
        row["billing_cycle"] = edit.billingCycle.rawValue
        row["status"] = edit.status.rawValue
        setOrClear(&row, "custom_cycle_days", edit.billingCycle == .custom ? edit.customCycleDays : nil)
        setOrClear(&row, "tag", edit.tag)
        setOrClear(&row, "notes", edit.notes)
        setOrClear(&row, "member_id", edit.familyMemberId)
        setOrClear(&row, "account_id", edit.paymentMethodId)
        setOrClear(&row, "ends_on", edit.scheduledCancelDate)
        setOrClear(&row, "direction", storedDirection(edit.direction))
        // The trial is a flag on the row and nothing else; off, the key is not written at all.
        if edit.freeTrial { row["free_trial"] = true } else { row.removeValue(forKey: "free_trial") }
        if let details = edit.details {
            if details.isEmpty { row.removeValue(forKey: "details") }
            else { row["details"] = rawDetails(details) }
        }
        row["updated_at"] = stamp
        if isNew {
            row["created_at"] = stamp
        }

        try SubValidator.validate(row, schema: schema, priceChanged: isNew || previousAmount != edit.amount,
                                  daysChanged: isNew || !sameDays)
        try refuseSecrets(in: row)

        if let index { subs[index] = row } else { subs.append(row) }
        vault["commitments"] = subs
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
        // Every form save sweeps the month-old tombstones; a read never does.
        vault = pruneTombstones(in: vault, now: now)

        // The charges. A new commitment is planned from its first charge; an existing one's
        // rows follow the rules in Ledger-Model-Plan — the attributes never reach the past.
        let sub = try decodeSub(row)
        let today = LB.dayOf(now)
        if isNew {
            guard let first = LB.parseDate(edit.firstCharge) else {
                throw WriteError.invalid("Say when the first charge is. That is where the plan starts.")
            }
            var rows: [ChargeRow]
            if sub.billingCycle != .once, let count = edit.planCount {
                // Exactly that many from the first charge: months enough to hold them, then cut.
                let wanted = min(max(count, 1), PlannedCount.ceiling)
                rows = Array(planCharges(for: sub, from: first, months: monthsHolding(wanted, of: sub),
                                         amount: edit.amount, writtenAt: stamp).prefix(wanted))
            } else {
                let months = sub.billingCycle == .once ? 1 : max(1, edit.planMonths ?? DEFAULT_PLAN_MONTHS)
                rows = planCharges(for: sub, from: first, months: months, amount: edit.amount, writtenAt: stamp)
            }
            vault = upsertCharges(rows, in: vault)
            return vault
        }

        // A one-time commitment's charge follows its date, whatever the cycle was before: one
        // row loses nothing by moving, and one of several never moves.
        if sub.billingCycle == .once, let first = edit.firstCharge, LB.parseDate(first) != nil {
            vault = moveSingleCharge(of: id, to: first, in: vault)
        }
        if let previousAmount, previousAmount != edit.amount {
            let from = LB.parseDate(edit.amountFrom) ?? today
            vault = repriceUnpaidPlanned(of: id, from: from, to: edit.amount, in: vault,
                                         includingPast: sub.billingCycle == .once)
        }
        if edit.status != .active, previousStatus == .active || previousStatus == nil {
            vault = removeUnpaidPlanned(of: id, after: today, in: vault)
        }
        if let end = LB.parseDate(edit.scheduledCancelDate), edit.scheduledCancelDate != previousEnd {
            vault = removeUnpaidPlanned(of: id, after: end, in: vault)
        }
        return vault
    }

    /// Months enough to plan `count` charges of this cycle from the first: a month is never
    /// shorter than 28 days, and the plan's horizon is exclusive.
    private static func monthsHolding(_ count: Int, of sub: Subscription) -> Int {
        switch sub.billingCycle {
        case .monthly: return count
        case .yearly: return count * 12
        case .custom: return count * cycleDays(sub) / 28 + 1
        case .once: return 1
        }
    }

    // MARK: charges — the rows

    static func chargeRows(_ raw: [String: Any]) -> [[String: Any]] {
        raw["charges"] as? [[String: Any]] ?? []
    }

    private static func setChargeRows(_ rows: [[String: Any]], in raw: [String: Any]) -> [String: Any] {
        var vault = raw
        // Date order within a commitment, commitments in the order they appear: a file that
        // reads as a ledger, and one that diffs by row when a save changes one.
        var order: [String: Int] = [:]
        for (index, row) in chargeRows(raw).enumerated() {
            let id = row["commitment_id"] as? String ?? ""
            if order[id] == nil { order[id] = index }
        }
        let sorted = rows.sorted { a, b in
            let ca = a["commitment_id"] as? String ?? "", cb = b["commitment_id"] as? String ?? ""
            if ca != cb { return (order[ca] ?? Int.max, ca) < (order[cb] ?? Int.max, cb) }
            return (a["date"] as? String ?? "") < (b["date"] as? String ?? "")
        }
        // An emptied list leaves no key: absent and empty mean the same.
        if sorted.isEmpty { vault.removeValue(forKey: "charges") } else { vault["charges"] = sorted }
        return vault
    }

    private static func rawCharge(_ row: ChargeRow) -> [String: Any] {
        var out: [String: Any] = ["commitment_id": row.commitmentId, "date": row.date,
                                  "amount": row.amount, "paid": row.paid]
        if let currency = row.currency { out["currency"] = currency }
        if let paidOn = row.paidOn { out["paid_on"] = paidOn }
        if let basis = row.basis { out["basis"] = basis }
        if let note = row.note, !note.isEmpty { out["note"] = note }
        if let writtenAt = row.writtenAt { out["written_at"] = writtenAt }
        return out
    }

    private static func sameCharge(_ row: [String: Any], _ commitmentId: String, _ date: String) -> Bool {
        row["commitment_id"] as? String == commitmentId && row["date"] as? String == date
    }

    /// Writes rows in, one per (commitment, date): a row already there for that day is
    /// replaced by the one given, so planning again or reconciling a statement never doubles.
    public static func upsertCharges(_ rows: [ChargeRow], in raw: [String: Any]) -> [String: Any] {
        var all = chargeRows(raw)
        for row in rows {
            all.removeAll { sameCharge($0, row.commitmentId, row.date) }
            all.append(rawCharge(row))
        }
        return setChargeRows(all, in: raw)
    }

    /// Takes the named days out and signs each as the app's own charge, so the removal reads
    /// as the owner's wherever the file lands next; the commitment's own entry is left as it
    /// is. Nothing named on file leaves the file as it was.
    public static func removeCharges(of commitmentId: String, dates: [String], in raw: [String: Any], now: Date) -> [String: Any] {
        let gone = Set(dates)
        let all = chargeRows(raw)
        let removed = Set(all.filter { $0["commitment_id"] as? String == commitmentId }
            .compactMap { $0["date"] as? String }.filter(gone.contains))
        guard !removed.isEmpty else { return raw }
        let kept = all.filter { !($0["commitment_id"] as? String == commitmentId && removed.contains($0["date"] as? String ?? "")) }
        var vault = setChargeRows(kept, in: raw)
        signCharges(&vault, of: commitmentId, dates: removed, at: iso8601(now))
        return vault
    }

    /// The named charge and the plan after it taken off: that row and every unpaid row after
    /// it go, and `ends_on` lands the day before it, so nothing is planned past that day.
    /// Paid rows and every row before stay. Each day removed is signed as the app's charge.
    public static func removeChargeAndLater(of commitmentId: String, from date: String, in raw: [String: Any],
                                            now: Date, schema: [String: Any]? = nil) throws -> [String: Any] {
        guard let fromDay = LB.parseDate(date) else { throw WriteError.badDate }
        var subs = raw["commitments"] as? [[String: Any]] ?? []
        guard let index = subs.firstIndex(where: { $0["id"] as? String == commitmentId }) else {
            throw WriteError.notFound(commitmentId)
        }
        let all = chargeRows(raw)
        guard all.contains(where: { sameCharge($0, commitmentId, date) }) else {
            throw WriteError.notFound("\(commitmentId)@\(date)")
        }
        let gone = all.filter { row in
            guard row["commitment_id"] as? String == commitmentId, let day = LB.parseDate(row["date"] as? String) else { return false }
            return day == fromDay || (day > fromDay && row["paid"] as? Bool != true)
        }.compactMap { $0["date"] as? String }
        let stamp = iso8601(now)
        var row = subs[index]
        // An end already earlier stays; a later or missing one moves to the day before.
        let end = LB.toISO(LB.addDays(fromDay, -1))
        if LB.parseDate(row["ends_on"] as? String).map({ $0 > LB.addDays(fromDay, -1) }) ?? true {
            row["ends_on"] = end
        }
        row["updated_at"] = stamp
        try SubValidator.validate(row, schema: schema, priceChanged: false, daysChanged: false)
        subs[index] = row
        var vault = raw
        vault["commitments"] = subs
        vault["_provenance"] = stamped(vault["_provenance"], id: commitmentId, at: stamp)
        vault = setChargeRows(all.filter { !($0["commitment_id"] as? String == commitmentId && gone.contains($0["date"] as? String ?? "")) }, in: vault)
        signCharges(&vault, of: commitmentId, dates: gone, at: stamp)
        return vault
    }

    /// Sets what is known about one charge and signs that charge as the app's own; the
    /// commitment's entry is left as it is. A row not yet there is written; fields not given
    /// are left as they were. With `creating` false a missing row is refused, not written.
    public static func setCharge(commitmentId: String, date: String, paid: Bool? = nil,
                                 amount: Double? = nil, paidOn: String?? = nil, note: String?? = nil,
                                 basis: String? = nil, creating: Bool = true,
                                 in raw: [String: Any], now: Date) throws -> [String: Any] {
        guard LB.parseDate(date) != nil else { throw WriteError.invalid("That day isn’t a real calendar day.") }
        if let amount { try checkAmount(amount) }
        var all = chargeRows(raw)
        var row: [String: Any]
        if let at = all.firstIndex(where: { sameCharge($0, commitmentId, date) }) {
            row = all.remove(at: at)
        } else {
            guard creating else { throw WriteError.notFound("\(commitmentId)@\(date)") }
            guard let sub = (raw["commitments"] as? [[String: Any]])?.first(where: { $0["id"] as? String == commitmentId }) else {
                throw WriteError.notFound(commitmentId)
            }
            guard let price = amount ?? (sub["amount"] as? Double) else {
                throw WriteError.invalid("A charge needs an amount.")
            }
            row = ["commitment_id": commitmentId, "date": date, "amount": price, "paid": false,
                   "written_at": iso8601(now)]
        }
        if let paid { row["paid"] = paid }
        if let amount { row["amount"] = amount }
        if let paidOn { setOrClear(&row, "paid_on", paidOn) }
        if let note {
            if let text = note, !text.isEmpty { try refuseSecrets(text); row["note"] = text }
            else { row.removeValue(forKey: "note") }
        }
        // What backs the row: the caller's word, else the app's own tap when marking, else
        // the owner's hand when a number changed. A plan that was only marked stays honest.
        if let basis { row["basis"] = basis }
        else if amount != nil { row["basis"] = "user" }
        else if paid == true, (row["basis"] as? String) == "plan" || row["basis"] == nil { row["basis"] = "mark_paid" }
        else if paid == false, (row["basis"] as? String) == "mark_paid" { row["basis"] = "plan" }
        all.append(row)
        var vault = setChargeRows(all, in: raw)
        signCharges(&vault, of: commitmentId, dates: [date], at: iso8601(now))
        return vault
    }

    /// One more stretch of plan for an existing recurring commitment, asked for, never automatic:
    /// from the step after its last written charge, or from the first cycle day from today on
    /// when that step is behind it. Nothing lands before today; each row is signed as the
    /// app's charge.
    public static func plan(commitmentId: String, months: Int, in raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let subRow = (raw["commitments"] as? [[String: Any]])?.first(where: { $0["id"] as? String == commitmentId }) else {
            throw WriteError.notFound(commitmentId)
        }
        let sub = try decodeSub(subRow)
        guard sub.billingCycle != .once else { throw WriteError.invalid("A one-time commitment has its one charge; there is nothing to plan.") }
        let existing = chargeRows(raw).filter { $0["commitment_id"] as? String == commitmentId }
        let dates = existing.compactMap { $0["date"] as? String }
        let today = LB.dayOf(now)
        // The rhythm runs from the last charge, or from today when there is none.
        let last = dates.compactMap(LB.parseDate).max()
        let anchor = last ?? today
        var step = 1
        while step < 100_000, stepFrom(sub, anchor, step) < today { step += 1 }
        let first = stepFrom(sub, anchor, step)
        guard first >= today else { return raw }
        // "Twelve more months" is coverage beyond the last charge, that day inclusive, while
        // the plan runs ahead; a lapsed plan counts its months from the first charge it writes.
        let horizonFrom = step == 1 ? (last.map { LB.addDays($0, 1) } ?? first) : first
        let rows = planCharges(for: sub, from: first, months: max(1, months), amount: sub.amount,
                               skipping: Set(dates), writtenAt: iso8601(now), horizonFrom: horizonFrom)
        var vault = upsertCharges(rows, in: raw)
        signCharges(&vault, of: commitmentId, dates: rows.map(\.date), at: iso8601(now))
        return vault
    }

    /// The charges from today on, set to exactly `count` as `plannedAhead` counts them: more
    /// are written a cycle apart after the last row, and unpaid planned rows past the count
    /// are unwritten, each signed as the app's charge. Paid rows, hand-set rows and the
    /// past stay.
    public static func setPlannedCount(commitmentId: String, count: Int, in raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let subRow = (raw["commitments"] as? [[String: Any]])?.first(where: { $0["id"] as? String == commitmentId }) else {
            throw WriteError.notFound(commitmentId)
        }
        let sub = try decodeSub(subRow)
        guard sub.billingCycle != .once else { return raw }
        let today = LB.dayOf(now)
        let wanted = min(max(count, 1), PlannedCount.ceiling)
        let all = chargeRows(raw)
        let isPlan = { (row: [String: Any]) -> Bool in
            row["paid"] as? Bool != true && (row["basis"] as? String ?? "plan") == "plan"
        }
        let ahead = all.enumerated().filter { _, row in
            guard row["commitment_id"] as? String == commitmentId, let day = LB.parseDate(row["date"] as? String) else { return false }
            return day >= today
        }.sorted { (LB.parseDate($0.element["date"] as? String) ?? today) < (LB.parseDate($1.element["date"] as? String) ?? today) }
        if ahead.count > wanted {
            var drop = Set<Int>()
            for (offset, row) in ahead.reversed() where ahead.count - drop.count > wanted && isPlan(row) {
                drop.insert(offset)
            }
            var vault = setChargeRows(all.enumerated().filter { !drop.contains($0.offset) }.map(\.element), in: raw)
            signCharges(&vault, of: commitmentId, dates: drop.compactMap { all[$0]["date"] as? String }, at: iso8601(now))
            return vault
        }
        guard ahead.count < wanted else { return raw }
        let dates = all.filter { $0["commitment_id"] as? String == commitmentId }.compactMap { $0["date"] as? String }
        let last = dates.compactMap(LB.parseDate).max() ?? today
        let end = cancelInfo(sub, today).date
        let stamp = iso8601(now)
        var rows: [ChargeRow] = []
        var k = 1
        while rows.count < wanted - ahead.count && k < 4000 {
            let day = stepFrom(sub, last, k)
            k += 1
            if let end, day > end { break }
            // A plan that stopped months ago resumes from today on, never back-filled.
            if day < today { continue }
            let iso = LB.toISO(day)
            if dates.contains(iso) { continue }
            rows.append(ChargeRow(commitmentId: sub.id, date: iso, amount: sub.amount, paid: false, basis: "plan", writtenAt: stamp))
        }
        var vault = upsertCharges(rows, in: raw)
        signCharges(&vault, of: commitmentId, dates: rows.map(\.date), at: stamp)
        return vault
    }

    /// A price that changed from one charge on: that row takes it by the owner's hand, every
    /// unpaid planned row after it follows, and the commitment's own price is the new one, so
    /// more plan is written at it. Paid rows and rows set by hand keep what they have.
    public static func reprice(commitmentId: String, from date: String, to amount: Double,
                               in raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let day = LB.parseDate(date) else { throw WriteError.invalid("That day isn’t a real calendar day.") }
        var vault = try setCharge(commitmentId: commitmentId, date: date, amount: amount, in: raw, now: now)
        vault = repriceUnpaidPlanned(of: commitmentId, from: LB.addDays(day, 1), to: amount, in: vault, includingPast: false)
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        guard let index = subs.firstIndex(where: { $0["id"] as? String == commitmentId }) else { throw WriteError.notFound(commitmentId) }
        let stamp = iso8601(now)
        subs[index]["amount"] = amount
        subs[index]["updated_at"] = stamp
        vault["commitments"] = subs
        vault["_provenance"] = stamped(vault["_provenance"], id: commitmentId, at: stamp)
        return vault
    }

    /// Several one-time commitments that turn out to be one thing become one recurring
    /// commitment: their charges move under it as they are — dates, amounts, paid, basis —
    /// the one-time rows go, and the plan continues as `plan` writes it, never before today.
    public static func promote(onceIds: [String], to edit: SubEdit, planMonths: Int?,
                               in raw: [String: Any], now: Date, schema: [String: Any]? = nil) throws -> (vault: [String: Any], id: String) {
        var vault = raw
        let subs = vault["commitments"] as? [[String: Any]] ?? []
        let ids = Set(onceIds)
        let moving = chargeRows(vault).filter { ids.contains($0["commitment_id"] as? String ?? "") }
        guard !moving.isEmpty else { throw WriteError.invalid("None of those commitments has a charge to carry over.") }
        for id in onceIds where !subs.contains(where: { $0["id"] as? String == id }) {
            throw WriteError.notFound(id)
        }

        var attributes = edit
        attributes.id = nil
        // The rows say which way it goes: an edit never moves them into or out of a sum.
        attributes.direction = try sharedDirection(of: onceIds, in: raw)
        attributes.firstCharge = moving.compactMap { $0["date"] as? String }.min()
        attributes.planMonths = 1
        let seed = UUID().uuidString.lowercased()
        var seededSubs = subs
        seededSubs.append(["id": seed, "created_at": iso8601(now)])
        vault["commitments"] = seededSubs
        attributes.id = seed
        vault = try apply(attributes, to: vault, now: now, schema: schema)
        // apply() planned one stretch from the first moved charge; the moved rows replace it.
        let carried = moving.map { row -> [String: Any] in
            var out = row
            out["commitment_id"] = seed
            return out
        }
        vault = setChargeRows(chargeRows(vault).filter {
            let owner = $0["commitment_id"] as? String ?? ""
            return owner != seed && !ids.contains(owner)
        } + carried, in: vault)
        var remaining = vault["commitments"] as? [[String: Any]] ?? []
        remaining.removeAll { ids.contains($0["id"] as? String ?? "") }
        vault["commitments"] = remaining
        // The merged rows leave a tombstone each, as a delete does, so the other device adopts the merge.
        for id in onceIds {
            vault["_provenance"] = stamped(vault["_provenance"], id: id, at: iso8601(now))
        }
        vault = try plan(commitmentId: seed, months: max(1, planMonths ?? DEFAULT_PLAN_MONTHS), in: vault, now: now)
        return (vault, seed)
    }

    private static func repriceUnpaidPlanned(of commitmentId: String, from: Date, to amount: Double,
                                             in raw: [String: Any], includingPast: Bool) -> [String: Any] {
        var all = chargeRows(raw)
        for i in all.indices where all[i]["commitment_id"] as? String == commitmentId {
            guard all[i]["paid"] as? Bool != true, (all[i]["basis"] as? String ?? "plan") == "plan" else { continue }
            guard let date = LB.parseDate(all[i]["date"] as? String) else { continue }
            if date >= from || includingPast { all[i]["amount"] = amount }
        }
        return setChargeRows(all, in: raw)
    }

    private static func removeUnpaidPlanned(of commitmentId: String, after day: Date, in raw: [String: Any]) -> [String: Any] {
        let kept = chargeRows(raw).filter { row in
            guard row["commitment_id"] as? String == commitmentId,
                  row["paid"] as? Bool != true, (row["basis"] as? String ?? "plan") == "plan",
                  let date = LB.parseDate(row["date"] as? String) else { return true }
            return date <= day
        }
        return setChargeRows(kept, in: raw)
    }

    /// A one-time commitment's charge follows its date. The row keeps everything else. Only a
    /// single charge moves; a row among several is never re-dated or dropped.
    private static func moveSingleCharge(of commitmentId: String, to date: String, in raw: [String: Any]) -> [String: Any] {
        var all = chargeRows(raw)
        let mine = all.indices.filter { all[$0]["commitment_id"] as? String == commitmentId }
        guard mine.count == 1, let at = mine.first, all[at]["date"] as? String != date else { return raw }
        all[at]["date"] = date
        return setChargeRows(all, in: raw)
    }

    /// Moves one charge to another day. Alone, the row keeps its amount as the owner's fact.
    /// With the later ones, every unpaid planned row after it follows a cycle apart, keeping
    /// its amount; paid and hand-priced rows stay. Each day left or landed on signs as the
    /// app's charge.
    public static func reschedule(commitmentId: String, from: String, to: String, andLater: Bool,
                                  in raw: [String: Any], now: Date) throws -> [String: Any] {
        guard let fromDay = LB.parseDate(from), let toDay = LB.parseDate(to) else { throw WriteError.badDate }
        var all = chargeRows(raw)
        guard let at = all.firstIndex(where: { sameCharge($0, commitmentId, from) }) else {
            throw WriteError.notFound("\(commitmentId)@\(from)")
        }
        if from == to { return raw }
        let stamp = iso8601(now)
        if !andLater {
            if all.contains(where: { sameCharge($0, commitmentId, to) }) { throw WriteError.dayTaken(to) }
            var moved = all.remove(at: at)
            moved["date"] = to
            if (moved["basis"] as? String ?? "plan") == "plan" { moved["basis"] = "user" }
            moved["written_at"] = stamp
            all.append(moved)
            var vault = setChargeRows(all, in: raw)
            signCharges(&vault, of: commitmentId, dates: [from, to], at: stamp)
            return vault
        }
        guard let subRow = (raw["commitments"] as? [[String: Any]])?.first(where: { $0["id"] as? String == commitmentId })
        else { throw WriteError.notFound(commitmentId) }
        let sub = try decodeSub(subRow)
        // The run that moves: the row named and every unpaid planned row after it, in order.
        let isPlan = { (row: [String: Any]) -> Bool in
            row["paid"] as? Bool != true && (row["basis"] as? String ?? "plan") == "plan"
        }
        let moving = all.enumerated().filter { _, row in
            guard row["commitment_id"] as? String == commitmentId, let day = LB.parseDate(row["date"] as? String) else { return false }
            return day == fromDay || (day > fromDay && isPlan(row))
        }
        guard moving.first?.element["date"] as? String == from else { throw WriteError.notFound("\(commitmentId)@\(from)") }
        let kept = Set(all.indices).subtracting(moving.map(\.offset))
        var out = kept.sorted().map { all[$0] }
        let taken = Set(out.filter { $0["commitment_id"] as? String == commitmentId }.compactMap { $0["date"] as? String })
        let end = cancelInfo(sub, now).date
        var landed: [String] = []
        for (k, item) in moving.enumerated() {
            let day = stepFrom(sub, toDay, k)
            if let end, day > end {
                // The named row IS the move. Dropping it would delete the charge the caller
                // asked to move, and every row of the run behind it, and report success.
                guard k > 0 else {
                    throw WriteError.invalid(
                        "That day is past the cancelling date, \(LB.longDate(end)). Move the cancelling date first, or move this charge on its own."
                    )
                }
                break
            }
            let iso = LB.toISO(day)
            if taken.contains(iso) { throw WriteError.dayTaken(iso) }
            var row = item.element
            row["date"] = iso
            row["written_at"] = stamp
            out.append(row)
            landed.append(iso)
        }
        var vault = setChargeRows(out, in: raw)
        signCharges(&vault, of: commitmentId, dates: moving.compactMap { $0.element["date"] as? String } + landed, at: stamp)
        return vault
    }

    /// A one-time commitment's new price, taken from the charge it is: written on its row,
    /// which is then checked as every edit is checked.
    private static func setPrice(_ id: String, to price: Double, in raw: [String: Any], now: Date,
                                 schema: [String: Any]?) throws -> [String: Any] {
        var vault = raw
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        guard let index = subs.firstIndex(where: { $0["id"] as? String == id }) else { throw WriteError.notFound(id) }
        let stamp = iso8601(now)
        var row = subs[index]
        row["amount"] = price
        row["updated_at"] = stamp

        try SubValidator.validate(row, schema: schema, daysChanged: false)
        try refuseSecrets(in: row)

        subs[index] = row
        vault["commitments"] = subs
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
        return vault
    }

    /// One charge's changes as one write: a one-time commitment's price, when the charge counts
    /// in the commitment's currency, since the commitment is its charge; then the row's fields
    /// where it still sits; then the reprice and the move a reach carries. Any refusal throws.
    public static func editCharge(commitmentId: String, from: String, to: String? = nil,
                                  paid: Bool? = nil, amount: Double? = nil, note: String?? = nil,
                                  andLater: Bool = false, in raw: [String: Any], now: Date,
                                  schema: [String: Any]? = nil) throws -> [String: Any] {
        // Checked before either half, in the validator's words: a non-finite number cannot be
        // written at all, and one past the limit is refused.
        if let amount { try checkAmount(amount) }
        let subRow = (raw["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == commitmentId }
        let rowCurrency = chargeRows(raw).first { sameCharge($0, commitmentId, from) }?["currency"] as? String
        var vault = raw
        if let amount, subRow?["billing_cycle"] as? String == BillingCycle.once.rawValue,
           subRow?["amount"] as? Double != amount,
           rowCurrency == nil || rowCurrency == (subRow?["currency"] as? String) {
            vault = try setPrice(commitmentId, to: amount, in: vault, now: now, schema: schema)
        }
        // Never `creating`: this edits a row the caller already holds, and a fresh row here
        // would invent an amount and a basis for a charge that was moved away.
        vault = try setCharge(commitmentId: commitmentId, date: from, paid: paid,
                              amount: amount, note: note, creating: false, in: vault, now: now)
        // A reprice reaches the rows after it in the plan, not ones a backward move lands behind.
        if andLater, let amount {
            vault = try reprice(commitmentId: commitmentId, from: from, to: amount, in: vault, now: now)
        }
        if let to, to != from {
            vault = try reschedule(commitmentId: commitmentId, from: from, to: to,
                                   andLater: andLater, in: vault, now: now)
        }
        return vault
    }

    /// What the commitment form changes on the one charge it is on, as `editCharge` takes it:
    /// nil leaves a field as it is, and `andLater` answers how far a new amount or day reaches.
    public struct ChargeChange: Equatable {
        /// The day the row sits on in the file.
        public var from: String
        public var to: String?
        public var paid: Bool?
        public var amount: Double?
        public var note: String??
        public var andLater: Bool

        public init(from: String, to: String? = nil, paid: Bool? = nil, amount: Double? = nil,
                    note: String?? = nil, andLater: Bool = false) {
            self.from = from
            self.to = to
            self.paid = paid
            self.amount = amount
            self.note = note
            self.andLater = andLater
        }

        /// A day other than the one the row sits on.
        public var moves: Bool { to.map { $0 != from } ?? false }

        public var isEmpty: Bool { !moves && paid == nil && amount == nil && note == nil }
    }

    /// The commitment form's Save as one write: the row, the tag it wears joined to the
    /// registry, an existing commitment's new count of planned charges, then the one charge's
    /// changes as `editCharge` writes them. Any refusal throws, so none of it lands.
    public static func saveCommitment(_ edit: SubEdit, plannedCount: Int? = nil,
                                      charge: ChargeChange? = nil,
                                      in raw: [String: Any], now: Date,
                                      schema: [String: Any]? = nil) throws -> [String: Any] {
        var vault = raw
        // Marking one charge paid is no edit of its commitment: a Save that changes none of the
        // row's own fields leaves the row, its stamp and its signature as the file holds them.
        if !changesNothing(edit, in: raw) {
            vault = try apply(edit, to: raw, now: now, schema: schema)
            // The library's icon comes along for a seeded tag, so the file alone explains every
            // tag it uses.
            if let tag = edit.tag {
                vault = ensureTag(kind: "commitment", named: tag, in: vault, now: now)
            }
        }
        // A new commitment is the one row this write added.
        guard let id = edit.id ?? addedCommitment(from: raw, to: vault) else { return vault }
        // Only an active commitment is planned: a Save that pauses or cancels plans nothing.
        if edit.id != nil, let plannedCount, edit.status == .active {
            vault = try setPlannedCount(commitmentId: id, count: plannedCount, in: vault, now: now)
        }
        if let charge, !charge.isEmpty {
            // The same Save can take the charge off the plan before it is changed.
            guard chargeRows(vault).contains(where: { sameCharge($0, id, charge.from) }) else {
                let held = chargeRows(raw).contains { sameCharge($0, id, charge.from) }
                let was = ((raw["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == id }?["status"] as? String)
                    .flatMap(SubStatus.init(rawValue:))
                throw WriteError.invalid(unmovable(charge.from, by: edit, was: was, held: held, moving: charge.moves))
            }
            vault = try editCharge(commitmentId: id, from: charge.from, to: charge.to, paid: charge.paid,
                                   amount: charge.amount, note: charge.note, andLater: charge.andLater,
                                   in: vault, now: now, schema: schema)
        }
        return vault
    }

    /// Whether an edit leaves an existing row's own fields meaning what the file holds: the
    /// name as `apply` trims it, money out however it is stored. A new row, new details or a
    /// first charge is always a change.
    static func changesNothing(_ edit: SubEdit, in raw: [String: Any]) -> Bool {
        guard let id = edit.id, edit.details == nil, edit.firstCharge == nil,
              let row = (raw["commitments"] as? [[String: Any]])?.first(where: { $0["id"] as? String == id }),
              let sub = try? decodeSub(row)
        else { return false }
        return edit.name.trimmingCharacters(in: .whitespacesAndNewlines) == sub.name
            && edit.amount == sub.amount && edit.currency == sub.currency
            && edit.billingCycle == sub.billingCycle && edit.status == sub.status
            && (edit.billingCycle == .custom ? edit.customCycleDays : nil) == sub.customCycleDays
            && edit.tag == sub.tag && edit.notes == sub.notes
            && edit.familyMemberId == sub.familyMemberId && edit.paymentMethodId == sub.paymentMethodId
            && edit.scheduledCancelDate == sub.scheduledCancelDate
            && storedDirection(edit.direction) == storedDirection(sub.direction)
            && edit.freeTrial == (sub.freeTrial == true)
    }

    /// The id a write added to the commitments, or nil when it added none.
    private static func addedCommitment(from raw: [String: Any], to vault: [String: Any]) -> String? {
        let ids = { (file: [String: Any]) in (file["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } }
        let before = Set(ids(raw))
        return ids(vault).first { !before.contains($0) }
    }

    /// Why the charge a Save moves or changes is not there, named by its day: gone before the
    /// Save, or taken by its own change — a cancelling date before it, a pause or a cancel of a
    /// commitment that `was` active, or a shorter plan.
    static func unmovable(_ from: String, by edit: SubEdit, was: SubStatus?, held: Bool, moving: Bool = true) -> String {
        let day = LB.parseDate(from).map { LB.longDate($0) } ?? from
        guard held else {
            return "The charge on \(day) is no longer in your file. It was removed or moved while this was open."
        }
        let (done, first) = moving ? ("moved", "Move") : ("changed", "Change")
        if let end = LB.parseDate(edit.scheduledCancelDate), let moved = LB.parseDate(from), moved > end {
            return "\(day) is past the cancelling date, so it can't be \(done). \(first) it first, then set the cancelling date."
        }
        // Pausing and cancelling take the plan only as they stop an active commitment, as apply() does.
        if was == .active || was == nil {
            switch edit.status {
            case .paused: return "Pausing removes the charge on \(day), so it can't be \(done). \(first) it first, then pause."
            case .cancelled: return "Cancelling removes the charge on \(day), so it can't be \(done). \(first) it first, then cancel."
            case .active: break
            }
        }
        return "The shorter plan removes the charge on \(day), so it can't be \(done). \(first) it first, then shorten the plan."
    }

    private static func decodeSub(_ row: [String: Any]) throws -> Subscription {
        let data = try JSONSerialization.data(withJSONObject: row)
        return try JSONDecoder().decode(Subscription.self, from: data)
    }

    /// Cancelling — the contract's preferred alternative to deleting, and a real financial event in
    /// its own right: the commitment existed, and its history stays.
    public static func cancel(id: String, in raw: [String: Any], now: Date, schema: [String: Any]? = nil) throws -> [String: Any] {
        var vault = raw
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        guard let index = subs.firstIndex(where: { $0["id"] as? String == id }) else { throw WriteError.notFound(id) }
        let stamp = iso8601(now)
        var row = subs[index]
        row["status"] = SubStatus.cancelled.rawValue
        row["updated_at"] = stamp
        try SubValidator.validate(row, schema: schema, priceChanged: false, daysChanged: false)
        subs[index] = row
        vault["commitments"] = subs
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
        // What was only planned past this day is unwritten; what happened stays.
        return removeUnpaidPlanned(of: id, after: LB.dayOf(now), in: vault)
    }

    /// Removing the row outright. Kept behind a confirmation — the one operation that
    /// destroys something. Its provenance entries outlive it as tombstones, the commitment's
    /// and each removed charge's, signed as the app's, so the owner's other device adopts
    /// the removal instead of asking. `pruneTombstones` sweeps them a month on.
    public static func delete(id: String, from raw: [String: Any], now: Date) throws -> [String: Any] {
        var vault = raw
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        guard subs.contains(where: { $0["id"] as? String == id }) else { throw WriteError.notFound(id) }
        subs.removeAll { $0["id"] as? String == id }
        vault["commitments"] = subs
        let stamp = iso8601(now)
        let removed = chargeRows(vault).filter { $0["commitment_id"] as? String == id }.compactMap { $0["date"] as? String }
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
        signCharges(&vault, of: id, dates: removed, at: stamp)
        return setChargeRows(chargeRows(vault).filter { $0["commitment_id"] as? String != id }, in: vault)
    }

    // MARK: two devices agreeing

    /// The owner kept these rows in Changes: each entry gains `reviewed_by` and `reviewed_at`
    /// and keeps who wrote it, so the other device adopts the kept change. The ids are the
    /// review diff's, rows and `id@date` charge keys. A later writer replaces the whole
    /// entry, which clears the mark.
    public static func markReviewed(ids: [String], in raw: [String: Any], now: Date) -> [String: Any] {
        guard !ids.isEmpty else { return raw }
        var vault = raw
        var prov = vault["_provenance"] as? [String: Any] ?? [:]
        let stamp = iso8601(now)
        for id in ids {
            var entry = prov[id] as? [String: Any] ?? [:]
            entry["reviewed_by"] = LB_PROVENANCE
            entry["reviewed_at"] = stamp
            prov[id] = entry
        }
        vault["_provenance"] = prov
        return vault
    }

    /// Signs what writing `restored` over `current` changes, so the other device adopts an
    /// undo or a restore: every row it adds or changes as the app's own, every row or charge
    /// it removes as a tombstone. Tag rows are never signed. The rows are the restored vault's.
    public static func signRestore(from current: [String: Any], to restored: [String: Any], now: Date) -> [String: Any] {
        var vault = restored
        let stamp = iso8601(now)
        for diff in vaultDiff(from: current, to: restored) where diff.kind != "tags" {
            for id in diff.added.map(\.id) + diff.changed.map(\.id) + diff.removed.map(\.id) {
                vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
            }
        }
        return vault
    }

    /// Drops provenance entries of rows that are gone once older than the window: a key naming
    /// no commitment, account, member or tag, or an `@` key naming no charge row. An entry with
    /// only a Keep's mark ages by `reviewed_at`; an unreadable date is kept. Runs on form saves only.
    public static func pruneTombstones(in raw: [String: Any], now: Date, olderThanDays: Int = 30) -> [String: Any] {
        guard let prov = raw["_provenance"] as? [String: Any], !prov.isEmpty else { return raw }
        var live = Set<String>()
        for kind in ["commitments", "accounts", "members", "tags"] {
            for row in raw[kind] as? [[String: Any]] ?? [] {
                if let id = row["id"] as? String { live.insert(id) }
            }
        }
        for row in chargeRows(raw) {
            if let id = row["commitment_id"] as? String, let date = row["date"] as? String {
                live.insert(chargeKey(id, date))
            }
        }
        for row in raw["tags"] as? [[String: Any]] ?? [] {
            if let key = row["name_key"] as? String ?? (row["name"] as? String).map(nameKey) { live.insert("tag:" + key) }
        }
        live.insert("hints")
        live.insert("to_fill_in")
        let formatter = ISO8601DateFormatter()
        let cutoff = now.addingTimeInterval(-Double(olderThanDays) * 86_400)
        var vault = raw
        vault["_provenance"] = prov.filter { key, value in
            if live.contains(key) { return true }
            let entry = value as? [String: Any]
            let stamp = (entry?["edited_at"] as? String) ?? (entry?["reviewed_at"] as? String)
            guard let at = stamp.flatMap(formatter.date(from:)) else { return true }
            return at >= cutoff
        }
        return vault
    }

    /// The entity kinds a name can name.
    public enum EntityKind: String {
        case paymentMethod = "accounts"
        case familyMember = "members"
    }

    /// Find an entity by the NAME KEY, or create it. Matching is normalised, so
    /// "HDFC  Current" and "hdfc current" are one account, never two — case and
    /// spacing must not split a person or a bank in half. Returns the id either way.
    public static func ensureEntity(
        _ kind: EntityKind, named name: String, in raw: [String: Any], now: Date
    ) throws -> (vault: [String: Any], id: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw WriteError.invalid("Give it a name. That's what you'll recognise it by.") }

        var vault = raw
        var rows = vault[kind.rawValue] as? [[String: Any]] ?? []
        let key = nameKey(clean)
        if let existing = rows.first(where: { nameKey($0["name_key"] as? String ?? $0["name"] as? String) == key }),
           let id = existing["id"] as? String {
            return (vault, id)
        }
        // A new row writes the name into the file, so it meets the scan every note meets. A
        // name already held is matched above and writes nothing.
        try refuseSecrets(clean)

        let id = UUID().uuidString.lowercased()
        // `is_incomplete` is the contract's word for "named, not yet described" — the
        // desktop shows these for filling in rather than treating them as finished.
        rows.append([
            "id": id, "name": clean, "name_key": key,
            "is_incomplete": true, "created_at": iso8601(now),
        ])
        vault[kind.rawValue] = rows
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: iso8601(now))
        return (vault, id)
    }

    /// An account by name and owner. Two accounts at one bank that print no digits are told
    /// apart by their owner, so their `name_key` is "<name>|<owner name key>"; an account with
    /// digits, or with no owner, matches on its name alone. A new account takes the owner.
    public static func ensureAccount(
        named name: String, ownerName owner: String?, in raw: [String: Any], now: Date
    ) throws -> (vault: [String: Any], id: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = owner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !who.isEmpty, !clean.contains(where: \.isNumber) else {
            return try ensureEntity(.paymentMethod, named: clean, in: raw, now: now)
        }
        guard !clean.isEmpty else { throw WriteError.invalid("Give it a name. That's what you'll recognise it by.") }
        var (vault, ownerId) = (raw, "")
        (vault, ownerId) = try ensureEntity(.familyMember, named: who, in: vault, now: now)
        let key = nameKey(clean) + "|" + nameKey(who)
        var rows = vault[EntityKind.paymentMethod.rawValue] as? [[String: Any]] ?? []
        if let existing = rows.first(where: { nameKey($0["name_key"] as? String) == key }), let id = existing["id"] as? String {
            return (vault, id)
        }
        try refuseSecrets(clean)
        let id = UUID().uuidString.lowercased()
        rows.append(["id": id, "name": clean, "name_key": key, "member_id": ownerId,
                     "is_incomplete": true, "created_at": iso8601(now)])
        vault[EntityKind.paymentMethod.rawValue] = rows
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: iso8601(now))
        return (vault, id)
    }

    /// The account on the other side of a one-time row, or none: writes `details.counterpart_account_id`
    /// and `details.counterpart_account`, clears both on nil, applies the Transfers rule and
    /// signs the row. An account id the vault does not hold is refused.
    public static func setCounterpartAccount(
        commitmentId: String, accountId: String?, in raw: [String: Any], now: Date
    ) throws -> [String: Any] {
        var vault = raw
        var rows = vault["commitments"] as? [[String: Any]] ?? []
        guard let index = rows.firstIndex(where: { $0["id"] as? String == commitmentId }) else { throw WriteError.notFound(commitmentId) }
        var details = rows[index]["details"] as? [String: Any] ?? [:]
        if let accountId {
            let accounts = vault[EntityKind.paymentMethod.rawValue] as? [[String: Any]] ?? []
            guard let account = accounts.first(where: { $0["id"] as? String == accountId }) else {
                throw WriteError.invalid("That account isn't in the vault.")
            }
            details[StatementImport.counterpartAccountIdKey] = accountId
            details[StatementImport.counterpartAccountKey] = account["name"] as? String ?? ""
        } else {
            details.removeValue(forKey: StatementImport.counterpartAccountIdKey)
            details.removeValue(forKey: StatementImport.counterpartAccountKey)
        }
        if details.isEmpty { rows[index].removeValue(forKey: "details") } else { rows[index]["details"] = details }
        rows[index]["updated_at"] = iso8601(now)
        vault["commitments"] = rows
        return StatementTransfers.apply(sign(ids: [commitmentId], in: vault, now: now), now: now)
    }

    /// Signs the named rows as the app's own, so the owner's other device adopts the write.
    static func sign(ids: [String], in raw: [String: Any], now: Date) -> [String: Any] {
        var vault = raw
        let stamp = iso8601(now)
        for id in ids { vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp) }
        return vault
    }

    /// A tag's key in `_provenance`: tags have no signed row of their own.
    static func tagKey(_ name: String) -> String { "tag:" + nameKey(name) }

    /// Which subscription field points at this kind of entity.
    private static func foreignKey(_ kind: EntityKind) -> String {
        kind == .paymentMethod ? "account_id" : "member_id"
    }

    /// How many commitments name this entity — what a delete would leave behind. Counted
    /// across every row, not just the active ones: a cancelled commitment still happened.
    public static func referenceCount(_ kind: EntityKind, id: String, in raw: [String: Any]) -> Int {
        let key = foreignKey(kind)
        return (raw["commitments"] as? [[String: Any]] ?? []).filter { $0[key] as? String == id }.count
    }

    /// Rename in place. The id is load-bearing and never changes, so every commitment that
    /// named this account or person keeps naming it.
    public static func renameEntity(
        _ kind: EntityKind, id: String, to name: String, in raw: [String: Any], now: Date
    ) throws -> [String: Any] {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw WriteError.invalid("Give it a name. That's what you'll recognise it by.") }
        // The new name is written, so it meets the scan every note meets — before the twin
        // check, whose refusal repeats the name.
        try refuseSecrets(clean)

        var vault = raw
        var rows = vault[kind.rawValue] as? [[String: Any]] ?? []
        guard let index = rows.firstIndex(where: { $0["id"] as? String == id }) else {
            throw WriteError.notFound(id)
        }
        let key = nameKey(clean)
        // Merging two entities is a different, bigger decision than renaming one; refusing
        // is honest, and nothing is lost either way.
        if rows.contains(where: {
            $0["id"] as? String != id && nameKey($0["name_key"] as? String ?? $0["name"] as? String) == key
        }) {
            let word = kind == .paymentMethod ? "account" : "person"
            throw WriteError.invalid("There's already \(word == "account" ? "an" : "a") \(word) called \(clean).")
        }
        rows[index]["name"] = clean
        rows[index]["name_key"] = key
        // A named thing is no longer only a name.
        rows[index]["is_incomplete"] = false
        vault[kind.rawValue] = rows
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: iso8601(now))
        return vault
    }

    /// What the file keeps of a direction. Nothing, "" and "out" are a charge, written as
    /// absence; any other word is kept as written, so one a newer contract names survives
    /// an edit here. Read, an unknown word is still spending.
    public static func storedDirection(_ direction: String?) -> String? {
        guard let direction, !direction.isEmpty, direction != "out" else { return nil }
        return direction
    }

    /// The one stored direction the named commitments share. A promotion keeps its rows
    /// where they are counted, so ids that mix spending, money in and transfers are refused.
    public static func sharedDirection(of ids: [String], in raw: [String: Any]) throws -> String? {
        let wanted = Set(ids)
        let rows = (raw["commitments"] as? [[String: Any]] ?? []).filter { wanted.contains($0["id"] as? String ?? "") }
        let directions = Set(rows.map { storedDirection($0["direction"] as? String) ?? "" })
        guard directions.count <= 1 else {
            throw WriteError.invalid("These rows do not share a direction: promote spending, money in and transfers separately.")
        }
        return directions.first.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Set or clear what describes an entity rather than names it. Each argument is doubly
    /// optional: nil leaves a field alone, .some(nil) clears it; the other kind's fields are
    /// ignored, unknown keys kept. `parentAccountId` is the linked account, `ownerMemberId`
    /// whose account it is; `removingCardName` takes only card_name out of details.
    public static func setEntityDetails(
        _ kind: EntityKind, id: String, in raw: [String: Any], now: Date,
        accountTag: String?? = nil, parentAccountId: String?? = nil, email: String?? = nil,
        balance: Double?? = nil, balanceDate: String?? = nil,
        memberTag: String?? = nil, ownerMemberId: String?? = nil,
        accountNotes: String?? = nil, removingCardName: Bool = false, photo: String?? = nil,
        starred: Bool? = nil
    ) throws -> [String: Any] {
        var vault = raw
        var rows = vault[kind.rawValue] as? [[String: Any]] ?? []
        guard let index = rows.firstIndex(where: { $0["id"] as? String == id }) else {
            throw WriteError.notFound(id)
        }
        // A star is written only while set; taking it off leaves no key.
        if let starred {
            if starred { rows[index]["starred"] = true } else { rows[index].removeValue(forKey: "starred") }
        }
        if let photo {
            try checkPhotoName(photo)
            setOrClear(&rows[index], "photo", photo)
        }

        // A tag and an email are written into the file, so each meets the scan every note meets.
        if kind == .paymentMethod, let accountTag {
            if let tag = accountTag { try refuseSecrets(tag) }
            setOrClear(&rows[index], "tag", accountTag)
        }
        if kind == .paymentMethod, let parentAccountId {
            if let parent = parentAccountId {
                guard parent != id else {
                    throw WriteError.invalid("An account can't be linked to itself.")
                }
                guard let parentRow = rows.first(where: { $0["id"] as? String == parent }) else {
                    throw WriteError.invalid("That linked account isn't in the vault.")
                }
                // One level, per the contract — checked in both directions.
                if parentRow["parent_account_id"] is String {
                    throw WriteError.invalid("That account is already linked to another — one level only.")
                }
                if rows.contains(where: { $0["parent_account_id"] as? String == id }) {
                    throw WriteError.invalid("Other accounts are linked to this one, so it can't be linked to another.")
                }
            }
            setOrClear(&rows[index], "parent_account_id", parentAccountId)
        }
        if kind == .paymentMethod, let ownerMemberId {
            if let owner = ownerMemberId {
                let people = vault[EntityKind.familyMember.rawValue] as? [[String: Any]] ?? []
                guard people.contains(where: { $0["id"] as? String == owner }) else {
                    throw WriteError.invalid("That person isn't in the vault.")
                }
            }
            setOrClear(&rows[index], "member_id", ownerMemberId)
        }
        if kind == .paymentMethod, removingCardName, var details = rows[index]["details"] as? [String: Any],
           details.removeValue(forKey: PaymentMethod.cardNameKey) != nil {
            if details.isEmpty { rows[index].removeValue(forKey: "details") } else { rows[index]["details"] = details }
        }
        if kind == .paymentMethod, let accountNotes {
            let blank = accountNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            if let text = accountNotes, !blank { try refuseSecrets(text) }
            setOrClear(&rows[index], "notes", blank ? nil : accountNotes)
        }
        if kind == .familyMember, let memberTag {
            let clean = memberTag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !clean.isEmpty { try refuseSecrets(clean) }
            setOrClear(&rows[index], "tag", clean.isEmpty ? nil : clean)
        }
        if kind == .paymentMethod, let balance {
            if let amount = balance, !amount.isFinite {
                throw WriteError.invalid("A balance has to be a number.")
            }
            setOrClear(&rows[index], "balance", balance)
        }
        if kind == .paymentMethod, let balanceDate {
            if let day = balanceDate, LB.parseDate(day) == nil {
                throw WriteError.invalid("The balance's date has to be a day, YYYY-MM-DD.")
            }
            setOrClear(&rows[index], "balance_date", balanceDate)
        }
        if kind == .familyMember, let email {
            if let address = email {
                // Loose on purpose — the server that sends the report is the real judge.
                // Stored exactly as typed; trimming would second-guess the owner.
                let at = address.firstIndex(of: "@")
                guard let at, at != address.startIndex, address.index(after: at) != address.endIndex else {
                    throw WriteError.invalid("An email needs an @ with something either side.")
                }
                try refuseSecrets(address)
            }
            setOrClear(&rows[index], "email", email)
        }

        vault[kind.rawValue] = rows
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: iso8601(now))
        // A person set to Self, or an account's owner, decides which charges are transfers.
        if memberTag != nil || ownerMemberId != nil { vault = StatementTransfers.apply(vault, now: now) }
        return vault
    }

    /// What setup named and nobody filled in, written whole; an empty list leaves no key.
    /// Signed under "to_fill_in", so the owner's other device adopts it.
    public static func setToFillIn(_ list: [CommitmentPlaceholder], in raw: [String: Any], now: Date = Date()) -> [String: Any] {
        var vault = sign(ids: ["to_fill_in"], in: raw, now: now)
        if list.isEmpty {
            vault.removeValue(forKey: "to_fill_in")
        } else {
            vault["to_fill_in"] = list.map { ["id": $0.id, "name": $0.name, "group": $0.group, "tag": $0.tag] }
        }
        return vault
    }

    /// The people and accounts setup kept as hints, written whole; an empty list leaves no key.
    public static func setHints(_ list: [SetupHint], in raw: [String: Any], now: Date = Date()) -> [String: Any] {
        var vault = sign(ids: ["hints"], in: raw, now: now)
        if list.isEmpty {
            vault.removeValue(forKey: "hints")
        } else {
            vault["hints"] = list.map(\.raw)
        }
        return vault
    }

    /// Delete, and unhook every commitment that pointed here. The commitments stay: the money
    /// was still spent, it simply no longer says from where or for whom.
    public static func deleteEntity(
        _ kind: EntityKind, id: String, in raw: [String: Any], now: Date
    ) throws -> [String: Any] {
        var vault = raw
        var rows = vault[kind.rawValue] as? [[String: Any]] ?? []
        guard rows.contains(where: { $0["id"] as? String == id }) else { throw WriteError.notFound(id) }
        rows.removeAll { $0["id"] as? String == id }

        let stamp = iso8601(now)
        // Its children stop hanging under it — an account that's gone can't be pointed at.
        for index in rows.indices where rows[index]["parent_account_id"] as? String == id {
            rows[index]["parent_account_id"] = NSNull()
            if let childId = rows[index]["id"] as? String {
                vault["_provenance"] = stamped(vault["_provenance"], id: childId, at: stamp)
            }
        }
        vault[kind.rawValue] = rows

        // A person's accounts stay, belonging to nobody: no member_id is left dangling.
        if kind == .familyMember {
            var accounts = vault[EntityKind.paymentMethod.rawValue] as? [[String: Any]] ?? []
            for index in accounts.indices where accounts[index]["member_id"] as? String == id {
                accounts[index]["member_id"] = NSNull()
                if let accountId = accounts[index]["id"] as? String {
                    vault["_provenance"] = stamped(vault["_provenance"], id: accountId, at: stamp)
                }
            }
            if vault[EntityKind.paymentMethod.rawValue] != nil { vault[EntityKind.paymentMethod.rawValue] = accounts }
        }

        let key = foreignKey(kind)
        var subs = vault["commitments"] as? [[String: Any]] ?? []
        for index in subs.indices where subs[index][key] as? String == id {
            subs[index][key] = NSNull()
            subs[index]["updated_at"] = stamp
            if let subId = subs[index]["id"] as? String {
                vault["_provenance"] = stamped(vault["_provenance"], id: subId, at: stamp)
            }
        }
        vault["commitments"] = subs
        // The entity's own entry stays as a tombstone, so the other device adopts the delete.
        vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
        return vault
    }

    /// A picture is a file name inside the longbook folder, never a path out of it.
    static func checkPhotoName(_ photo: String?) throws {
        if let name = photo, name.contains("..") || name.hasPrefix("/") {
            throw WriteError.invalid("A photo is a file inside the longbook folder.")
        }
    }

    /// A commitment's picture, or nil to take it away.
    public static func setCommitmentPhoto(id: String, photo: String?, in raw: [String: Any], now: Date) throws -> [String: Any] {
        var vault = raw
        var rows = vault["commitments"] as? [[String: Any]] ?? []
        guard let index = rows.firstIndex(where: { $0["id"] as? String == id }) else { throw WriteError.notFound(id) }
        try checkPhotoName(photo)
        setOrClear(&rows[index], "photo", photo)
        rows[index]["updated_at"] = iso8601(now)
        vault["commitments"] = rows
        return sign(ids: [id], in: vault, now: now)
    }

    /// A tag's picture, on its registry row; a tag not yet registered is registered first.
    public static func setTagPhoto(kind: String, named name: String, photo: String?, in raw: [String: Any], now: Date) throws -> [String: Any] {
        try checkPhotoName(photo)
        var vault = ensureTag(kind: kind, named: name, in: raw, now: now)
        var tags = vault["tags"] as? [[String: Any]] ?? []
        let key = nameKey(name)
        guard let index = tags.firstIndex(where: {
            ($0["kind"] as? String) == kind && nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key
        }) else { return vault }
        setOrClear(&tags[index], "photo", photo)
        vault["tags"] = tags
        return sign(ids: [tagKey(name)], in: vault, now: now)
    }

    /// Make sure a worn tag exists in the registry — copied from the library with its icon when
    /// it's a seeded one; bare when the owner invented it. No tag carries a template. A tag
    /// already present (by kind + name_key) leaves the vault untouched.
    public static func ensureTag(
        kind: String, named name: String, in raw: [String: Any], now: Date
    ) -> [String: Any] {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return raw }
        var vault = raw
        var tags = vault["tags"] as? [[String: Any]] ?? []
        let key = nameKey(clean)
        guard !tags.contains(where: {
            ($0["kind"] as? String) == kind
                && nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key
        }) else { return raw }

        let library = TagLibrary.entry(kind: kind, name: clean)
        var entry: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "kind": kind,
            "name": library?.name ?? clean,
            "name_key": key,
            "is_default": library != nil,
            "sort": tags.count,
            "created_at": iso8601(now),
        ]
        if let icon = library?.icon { entry["icon"] = icon }
        tags.append(entry)
        vault["tags"] = tags
        return sign(ids: [tagKey(clean)], in: vault, now: now)
    }

    /// Deletes one tag from the registry and lifts it off every row wearing it. Returns
    /// the next vault and how many rows wore it; an unknown name changes nothing.
    public static func removeTag(
        kind: String, named name: String, in raw: [String: Any], now: Date
    ) -> (vault: [String: Any], cleared: Int) {
        let key = nameKey(name.trimmingCharacters(in: .whitespaces))
        guard !key.isEmpty else { return (raw, 0) }
        var vault = raw
        var tags = vault["tags"] as? [[String: Any]] ?? []
        let before = tags.count
        tags.removeAll {
            ($0["kind"] as? String) == kind
                && nameKey($0["name_key"] as? String ?? $0["name"] as? String ?? "") == key
        }
        // No registry entry is not a refusal: an AI-written vault may wear a tag it
        // never registered, and the rows below still need carrying either way.
        if tags.count < before { vault["tags"] = tags }
        vault = sign(ids: [tagKey(name)], in: vault, now: now)

        let collection = ["commitment": "commitments", "member": "members", "account": "accounts"][kind]
        guard let collection else { return (vault, 0) }
        let stamp = iso8601(now)
        var rows = vault[collection] as? [[String: Any]] ?? []
        var cleared = 0
        for index in rows.indices where nameKey(rows[index]["tag"] as? String ?? "") == key {
            rows[index]["tag"] = NSNull()
            rows[index]["updated_at"] = stamp
            if let id = rows[index]["id"] as? String {
                vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
            }
            cleared += 1
        }
        vault[collection] = rows
        if kind == "member" { vault = StatementTransfers.apply(vault, now: now) }
        return (vault, cleared)
    }

    /// Renames one tag in the registry and carries every row wearing it. Rows store the
    /// tag's NAME, not its id, so a rename that stopped at the registry would strand them
    /// against a tag that no longer exists. Returns the next vault and how many rows moved.
    public static func renameTag(
        kind: String, from oldName: String, to newName: String, in raw: [String: Any], now: Date
    ) throws -> (vault: [String: Any], moved: Int) {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else {
            throw WriteError.invalid("Give it a name. That's what you'll recognise it by.")
        }
        // The new name is written onto every row wearing the tag, so it meets the scan a tag set
        // on one row meets — before the twin check, whose refusal repeats the name.
        try refuseSecrets(clean)
        let oldKey = nameKey(oldName.trimmingCharacters(in: .whitespaces))
        let newKey = nameKey(clean)
        guard !oldKey.isEmpty else { return (raw, 0) }

        func matches(_ tag: [String: Any], _ key: String) -> Bool {
            (tag["kind"] as? String) == kind
                && nameKey(tag["name_key"] as? String ?? tag["name"] as? String ?? "") == key
        }

        var vault = raw
        var tags = vault["tags"] as? [[String: Any]] ?? []
        // Two tags of one kind sharing a name would be one tag the owner can't tell apart.
        if newKey != oldKey, tags.contains(where: { matches($0, newKey) }) {
            throw WriteError.invalid("There's already one called \"\(clean)\".")
        }
        // The registry entry is optional: a tag exists because rows wear it, and a vault
        // an AI wrote may carry the word without ever registering it. Rows are renamed
        // either way — stopping here would have been a rename that silently did nothing.
        if let index = tags.firstIndex(where: { matches($0, oldKey) }) {
            tags[index]["name"] = clean
            tags[index]["name_key"] = newKey
            // Renamed is the owner's own word now, whatever the library seeded.
            tags[index]["is_default"] = false
            vault["tags"] = tags
        }
        vault = sign(ids: [tagKey(oldName), tagKey(clean)], in: vault, now: now)

        let collection = ["commitment": "commitments", "member": "members", "account": "accounts"][kind]
        guard let collection else { return (vault, 0) }
        let stamp = iso8601(now)
        var rows = vault[collection] as? [[String: Any]] ?? []
        var moved = 0
        for index in rows.indices where nameKey(rows[index]["tag"] as? String ?? "") == oldKey {
            rows[index]["tag"] = clean
            rows[index]["updated_at"] = stamp
            if let id = rows[index]["id"] as? String {
                vault["_provenance"] = stamped(vault["_provenance"], id: id, at: stamp)
            }
            moved += 1
        }
        vault[collection] = rows
        if kind == "member" { vault = StatementTransfers.apply(vault, now: now) }

        // A tag group holds normalised names, so it is carried in the same pass —
        // otherwise the owner's own grouping quietly drops the category it was built on.
        if var groups = vault["groups"] as? [[String: Any]] {
            var touched = false
            for index in groups.indices where (groups[index]["kind"] as? String) == "tag" {
                guard let keys = groups[index]["tag_keys"] as? [String], keys.contains(oldKey) else { continue }
                groups[index]["tag_keys"] = keys.map { $0 == oldKey ? newKey : $0 }
                touched = true
            }
            if touched { vault["groups"] = groups }
        }
        return (vault, moved)
    }

    // MARK: helpers

    /// nil means "the owner cleared this field", which is a real edit and must reach the file —
    /// so it writes JSON null rather than dropping the key, which would read as "never set".
    private static func setOrClear(_ row: inout [String: Any], _ key: String, _ value: Any?) {
        row[key] = value ?? NSNull()
    }

    /// The contract's shape: an OBJECT per record — `{edited_by, edited_at}` — not a bare string.
    /// Existing entries from other tools are left untouched whatever shape they're in.
    private static func stamped(_ existing: Any?, id: String, at stamp: String) -> [String: Any] {
        var prov = existing as? [String: Any] ?? [:]
        prov[id] = ["edited_by": LB_PROVENANCE, "edited_at": stamp]
        return prov
    }

    /// A charge's key in `_provenance`: "<commitment>@<day>", as a charge diffs.
    static func chargeKey(_ commitmentId: String, _ date: String) -> String {
        "\(commitmentId)@\(date)"
    }

    /// Signs each named day as the app's own charge, under its charge key, leaving the
    /// commitment's entry as it is. No days named leaves the file as it was.
    private static func signCharges(_ vault: inout [String: Any], of commitmentId: String,
                                    dates: some Collection<String>, at stamp: String) {
        guard !dates.isEmpty else { return }
        var prov = vault["_provenance"] as? [String: Any] ?? [:]
        for date in dates {
            prov[chargeKey(commitmentId, date)] = ["edited_by": LB_PROVENANCE, "edited_at": stamp]
        }
        vault["_provenance"] = prov
    }

    /// Details as the JSON the raw row carries.
    private static func rawDetails(_ details: Details) -> [String: Any] {
        func raw(_ value: DetailValue) -> Any {
            switch value {
            case .string(let s): return s
            case .number(let n): return n
            case .bool(let b): return b
            case .null: return NSNull()
            case .list(let l): return l.map(raw)
            }
        }
        return details.mapValues(raw)
    }

    /// The data-minimization scan at the write choke point: every value on the row — name,
    /// notes, tag, and each details value whatever its type — is refused if it matches a
    /// card number, expiry, CVV, IBAN or credential. A number-hinted field holds a number,
    /// which a string-only scan never saw.
    private static func refuseSecrets(in row: [String: Any]) throws {
        var texts: [(field: String, text: String)] = []
        for key in ["name", "notes", "tag"] {
            if let value = row[key] as? String { texts.append((key, value)) }
        }
        if let details = row["details"] as? [String: Any] {
            for (label, value) in details { texts += scannableWords(value).map { ("details: \(label)", $0) } }
        }
        for (field, text) in texts {
            if let hit = scanText(text) { throw WriteError.invalid(policyRefusal(hit, field: field)) }
        }
    }

    /// One details value as the words a scan should see.
    private static func scannableWords(_ value: Any) -> [String] {
        switch value {
        case let text as String: return [text]
        case let list as [Any]: return list.flatMap(scannableWords)
        case let number as Double: return [numberWord(number)]
        case let number as Int: return [String(number)]
        case let flag as Bool: return [flag ? "yes" : "no"]
        default: return []
        }
    }

    /// A whole number as its digits. `String` on a Double appends ".0" and, past about
    /// eighteen digits, switches to exponent notation — "4.111111111111111e+18" — where a
    /// digit-run scan finds nothing to look at. Int64 keeps the run intact.
    private static func numberWord(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return value == value.rounded() && abs(value) < 9e18 ? String(Int64(value)) : String(value)
    }

    private static func refuseSecrets(_ text: String) throws {
        if let hit = scanText(text) { throw WriteError.invalid(policyRefusal(hit)) }
    }

    public static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

// MARK: - disk

/// The last-moment check that makes two devices editing one file safe: re-read, compare
/// against the bytes the edit started from, refuse if anything moved, then write
/// atomically under coordination. One choke point for every writer in the process.
public enum VaultDisk {
    public static func write(_ next: [String: Any], to folder: URL, expecting bytesAtRead: Data?) throws {
        // Serialising a value JSON cannot hold, an infinite or NaN number above all, raises an
        // Objective-C exception that no Swift catch stops. Checked first, and refused as an error.
        guard JSONSerialization.isValidJSONObject(next) else {
            throw WriteError.invalid("Your change holds a number the file can’t store, so it wasn’t saved.")
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let file = folder.appendingPathComponent(VaultReader.dataFile)
        if let bytesAtRead, let current = try? VaultReader.coordinatedRead(file), current != bytesAtRead {
            throw WriteError.conflict
        }

        // .sortedKeys buys determinism: the same vault always serialises identically, so
        // a diff between two saves shows only what actually changed.
        let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys])
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
    }
}
