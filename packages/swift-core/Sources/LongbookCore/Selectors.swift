// The domain the app re-expresses in Swift, ported in BEHAVIOUR from packages/core — if
// these answers drift, the two engines disagree about one file.
//
// Every charge is a stored row. Nothing here computes an occurrence; the one generator,
// `planCharges`, writes rows on request.
import Foundation

// MARK: - status (domain/renewal.ts)

public struct CancelInfo {
    public let date: Date?
    public let lapsed: Bool
}

public func cancelInfo(_ sub: Subscription, _ today: Date = LB.todayMid()) -> CancelInfo {
    guard let date = LB.parseDate(sub.scheduledCancelDate) else { return CancelInfo(date: nil, lapsed: false) }
    return CancelInfo(date: date, lapsed: LB.daysBetween(today, date) < 0)
}

/// A stored `active` row whose cancelling date has passed reads as cancelled — checked on
/// open, so nobody has to write to the file on the day.
public func displayStatus(_ sub: Subscription, _ today: Date = LB.todayMid()) -> SubStatus {
    if sub.status == .active, cancelInfo(sub, today).lapsed { return .cancelled }
    return sub.status
}

public func isEffectivelyActive(_ sub: Subscription, _ today: Date = LB.todayMid()) -> Bool {
    displayStatus(sub, today) == .active
}

/// The Free trial pill: the row's own `free_trial` flag, read as a pill and nothing more —
/// the rows say nothing about it. Only spending is ever on trial.
public func isFreeTrial(_ sub: Subscription) -> Bool {
    sub.freeTrial == true && isSpending(sub)
}

/// What a spending total may hold: neither money in nor a transfer between the owner's
/// own accounts. Every sum reads through this.
public func isSpending(_ sub: Subscription) -> Bool { !sub.isIncome && !sub.isTransfer }

/// What comes due: spending, and a transfer the owner keeps in view. Money in is
/// remembered, never owed — nothing about it is due, live or planned short.
public func isOwed(_ sub: Subscription) -> Bool { !sub.isIncome }

// MARK: - charges

/// One charge as a screen reads it: the stored row joined to the commitment it belongs to.
/// A charge behind today reads as paid whatever its row says — the money was due and the day
/// has passed; the row keeps its own mark.
public struct Charge: Identifiable {
    public let sub: Subscription
    public let row: ChargeRow
    public let date: Date
    /// The row's mark, or the calendar: a charge dated before today is paid.
    public let paid: Bool

    public init(sub: Subscription, row: ChargeRow, date: Date, today: Date = LB.todayMid()) {
        self.sub = sub
        self.row = row
        self.date = date
        self.paid = row.paid || date < today
    }

    public var id: String { "\(sub.id)-\(row.date)" }
    public var amount: Double { row.amount }
    /// The row's own currency when it states one, else the commitment's.
    public var currency: String { row.currency ?? sub.currency }
}

/// The commitments by id, built once per read rather than once per row.
private func byId(_ subs: [Subscription]) -> [String: Subscription] {
    Dictionary(subs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
}

/// Every spending charge joined to its commitment, date order — the rows every sum is made
/// of. A row whose commitment is gone, or whose date is unreadable, is skipped. Money in and
/// transfers are not charges: `incomeCharges` and `transferCharges` read them.
public func allCharges(_ vault: Vault, _ today: Date = LB.todayMid()) -> [Charge] {
    joined(vault, today).filter { isSpending($0.sub) }
}

/// Every row of money in, joined and in date order — salary, refunds, interest.
public func incomeCharges(_ vault: Vault, _ today: Date = LB.todayMid()) -> [Charge] {
    joined(vault, today).filter { $0.sub.isIncome }
}

/// Every transfer row, joined and in date order — a card bill, a standing move to savings.
/// For the timeline beside `allCharges`; never for a total.
public func transferCharges(_ vault: Vault, _ today: Date = LB.todayMid()) -> [Charge] {
    joined(vault, today).filter { $0.sub.isTransfer }
}

private func joined(_ vault: Vault, _ today: Date) -> [Charge] {
    let subs = byId(vault.subscriptions)
    return vault.charges.compactMap { row in
        guard let sub = subs[row.commitmentId], let date = LB.parseDate(row.date) else { return nil }
        return Charge(sub: sub, row: row, date: date, today: today)
    }
    .sorted { $0.date < $1.date }
}

/// The rows of one commitment, date order.
public func charges(of sub: Subscription, in vault: Vault, _ today: Date = LB.todayMid()) -> [Charge] {
    vault.charges
        .filter { $0.commitmentId == sub.id }
        .compactMap { row in LB.parseDate(row.date).map { Charge(sub: sub, row: row, date: $0, today: today) } }
        .sorted { $0.date < $1.date }
}

/// Every charge across the whole vault between two days, inclusive, date order. Status is
/// not consulted: a cancelled commitment's past charges happened, and its future ones were
/// removed when it was cancelled. What the rows say is what there is.
public func chargesInRange(_ vault: Vault, from: Date, to: Date, _ today: Date = LB.todayMid()) -> [Charge] {
    allCharges(vault, today).filter { $0.date >= from && $0.date <= to }
}

/// The same window, for some of the commitments — a card or a slice reads its own.
public func chargesInRange(_ vault: Vault, of subs: [Subscription], from: Date, to: Date, _ today: Date = LB.todayMid()) -> [Charge] {
    let ids = Set(subs.map(\.id))
    return chargesInRange(vault, from: from, to: to, today).filter { ids.contains($0.sub.id) }
}

/// The soonest charge for one commitment on or after today — paid or not.
public func nextChargeOnOrAfter(_ sub: Subscription, in vault: Vault, _ today: Date = LB.todayMid()) -> Charge? {
    charges(of: sub, in: vault, today).first { $0.date >= today }
}

/// The soonest charge on or after today that still needs the owner's attention.
public func nextUnpaidChargeOnOrAfter(_ sub: Subscription, in vault: Vault, _ today: Date = LB.todayMid()) -> Charge? {
    charges(of: sub, in: vault, today).first { $0.date >= today && !$0.paid }
}

/// A commitment is what still lies ahead. A recurring one is a commitment while active; a
/// one-time one until its charge is behind today or marked paid, after which it is that
/// charge and nothing more. One with no charge written is still owed.
public func isLiveCommitment(_ sub: Subscription, in vault: Vault, _ today: Date = LB.todayMid()) -> Bool {
    guard isOwed(sub), isEffectivelyActive(sub, today) else { return false }
    if sub.billingCycle != .once { return true }
    let own = charges(of: sub, in: vault, today)
    return own.isEmpty || own.contains { $0.date >= today && !$0.paid }
}

/// The commitments still ahead, in the vault's own order.
public func liveCommitments(_ vault: Vault, _ today: Date = LB.todayMid()) -> [Subscription] {
    vault.subscriptions.filter { isLiveCommitment($0, in: vault, today) }
}

/// The last day this commitment has a charge written for — how far its plan reaches.
public func plannedThrough(_ sub: Subscription, in vault: Vault) -> Date? {
    charges(of: sub, in: vault).last?.date
}

/// One commitment's plan: its rows from today on, today's own included. The count the form's
/// Planned till holds, and the one `VaultPatch.setPlannedCount` sets.
public func plannedAhead(_ sub: Subscription, in vault: Vault, _ today: Date = LB.todayMid()) -> [Charge] {
    charges(of: sub, in: vault, today).filter { $0.date >= today }
}

public struct DueMeta: Identifiable {
    public let sub: Subscription
    public let charge: Charge
    public let date: Date
    /// Whole days from today (0 = today, negative = overdue).
    public let days: Int
    public var id: String { sub.id }
    public var paid: Bool { charge.paid }
}

private func upcoming(_ subs: [Subscription], in vault: Vault, unpaidOnly: Bool, _ today: Date) -> [DueMeta] {
    subs
        .filter { isOwed($0) && isEffectivelyActive($0, today) }
        .compactMap { sub -> DueMeta? in
            let next = unpaidOnly ? nextUnpaidChargeOnOrAfter(sub, in: vault, today) : nextChargeOnOrAfter(sub, in: vault, today)
            guard let next else { return nil }
            return DueMeta(sub: sub, charge: next, date: next.date, days: LB.daysBetween(today, next.date))
        }
        .sorted { $0.date != $1.date ? $0.date < $1.date : $0.sub.name < $1.sub.name }
}

/// Effectively-active commitments with an unpaid charge ahead, soonest first — what still
/// owes, transfers among them. Whatever this declines is, by subtraction, "not scheduled".
public func activeUpcoming(_ vault: Vault, _ today: Date = LB.todayMid()) -> [DueMeta] {
    upcoming(vault.subscriptions, in: vault, unpaidOnly: true, today)
}

public func activeUpcoming(_ vault: Vault, of subs: [Subscription], _ today: Date = LB.todayMid()) -> [DueMeta] {
    upcoming(subs, in: vault, unpaidOnly: true, today)
}

/// The same list with each commitment's next charge whether paid or not — the list a mark
/// is answered in, where a charge marked paid in three days still reads "in 3 days · Paid".
public func nextCharges(_ vault: Vault, _ today: Date = LB.todayMid()) -> [DueMeta] {
    upcoming(vault.subscriptions, in: vault, unpaidOnly: false, today)
}

public struct PaymentDay {
    public let date: Date
    /// Whole days from today (0 = today).
    public let days: Int
    /// The spending landing on this day, across currencies, biggest first — all a total may hold.
    public let charges: [Charge]
    /// The transfers due the same day, biggest first: shown beside the charges, never summed.
    public let transfers: [Charge]

    public init(date: Date, days: Int, charges: [Charge], transfers: [Charge] = []) {
        self.date = date
        self.days = days
        self.charges = charges
        self.transfers = transfers
    }
}

/// The day's rows from each commitment's next unpaid charge; `anchor` picks whose day it is.
private func owedDay(_ vault: Vault, _ today: Date, anchor: (Charge) -> Bool) -> PaymentDay? {
    let nexts = vault.subscriptions
        .filter { isOwed($0) && isEffectivelyActive($0, today) }
        .compactMap { nextUnpaidChargeOnOrAfter($0, in: vault, today) }
    guard let soonest = nexts.filter(anchor).map(\.date).min() else { return nil }
    // Grouped by calendar day, not by instant: two charges owed on the same day can hold
    // different instants where a zone skips midnight, and one would hide the other.
    let onDay = nexts.filter { LB.isSameDay($0.date, soonest) }.sorted { $0.amount > $1.amount }
    return PaymentDay(date: soonest, days: LB.daysBetween(today, soonest),
                      charges: onDay.filter { isSpending($0.sub) }, transfers: onDay.filter { $0.sub.isTransfer })
}

/// The nearest day on or after today that spending is still owed. A *day*, not a single
/// row — two things due together both show. A transfer never makes a payment day, so
/// `charges` is never empty; one due that day rides in `transfers`.
public func nextPaymentDay(_ vault: Vault, _ today: Date = LB.todayMid()) -> PaymentDay? {
    owedDay(vault, today) { isSpending($0.sub) }
}

/// The nearest day anything is still owed — spending or a transfer. Either list may be
/// empty, never both: a card bill due first is a day with transfers and no charges.
public func nextDueDay(_ vault: Vault, _ today: Date = LB.todayMid()) -> PaymentDay? {
    owedDay(vault, today) { _ in true }
}

/// A plan that has run short: active recurring commitments whose last written charge
/// falls within `withinDays` of today. The dashboard names them; the app never extends
/// a plan on its own.
public func plansRunningShort(_ vault: Vault, withinDays: Int = 90, _ today: Date = LB.todayMid()) -> [(sub: Subscription, through: Date)] {
    let limit = LB.addDays(today, withinDays)
    return vault.subscriptions
        .filter { isOwed($0) && isEffectivelyActive($0, today) && $0.billingCycle != .once && $0.scheduledCancelDate == nil }
        .compactMap { sub in plannedThrough(sub, in: vault).map { (sub: sub, through: $0) } }
        .filter { $0.through <= limit }
        .sorted { $0.through < $1.through }
}

/// The side of the ledger a door opens on: what is still ahead, or what already landed.
public enum ListScope {
    case upcoming, past
}

/// A day behind today opens Past; today or later opens Upcoming. A range opens Past when its
/// last day is behind today, else Upcoming; an open end runs through today. Months open Past
/// only when every one is wholly behind today. No window opens Upcoming.
public func listScope(
    day: String?, months: [String], from: String? = nil, to: String? = nil, today: Date = LB.todayMid()
) -> ListScope {
    if let day, let date = LB.parseDate(day) { return date < today ? .past : .upcoming }
    if from != nil || to != nil {
        guard let last = LB.parseDate(to) else { return .upcoming }
        return last < today ? .past : .upcoming
    }
    let anchor = LB.firstOfMonth(today)
    guard let chosen = MonthSelection(days: months.compactMap(LB.parseDate), anchor: anchor) else { return .upcoming }
    return chosen.span(anchor: anchor).last < today ? .past : .upcoming
}

/// Whether a day lies inside a window, both ends included; an open end holds everything
/// past it. Days compare as ISO strings, as `underCap` does, so an inverted window holds
/// nothing.
public func inDayRange(_ dateISO: String, from: String?, to: String?) -> Bool {
    (from.map { dateISO >= $0 } ?? true) && (to.map { dateISO <= $0 } ?? true)
}

/// The Date chip's words: "12 Sep – 4 Oct", "28 Dec 2025 – 4 Jan 2026" across a year, "On
/// 12 Sep" for one day, "From 12 Sep" or "Until 4 Oct" with one end open; nil with neither.
/// Its own formatter, so a test can pin the locale.
public func dayRangeLabel(from: Date?, to: Date?, locale: Locale = .current) -> String? {
    func words(_ date: Date, year: Bool) -> String {
        let f = DateFormatter()
        f.calendar = LB.calendar
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(year ? "d MMM y" : "d MMM")
        return f.string(from: date)
    }
    switch (from, to) {
    case (nil, nil): return nil
    case (let from?, nil): return "From \(words(from, year: false))"
    case (nil, let to?): return "Until \(words(to, year: false))"
    case (let from?, let to?):
        if LB.isSameDay(from, to) { return "On \(words(from, year: false))" }
        let years = LB.calendar.component(.year, from: from) != LB.calendar.component(.year, from: to)
        return "\(words(from, year: years)) – \(words(to, year: years))"
    }
}

/// What a capped list ahead shows: the rows before `edge`, or every row when none is —
/// an empty card above "Show later months" would deny what the chip offers.
public func underCap<Row>(_ rows: [Row], before edge: String, capped: Bool, dateISO: (Row) -> String) -> [Row] {
    guard capped else { return rows }
    let near = rows.filter { dateISO($0) < edge }
    return near.isEmpty ? rows : near
}

// MARK: - the one generator

/// One cycle step from an anchor. Months for monthly and yearly, days for custom; a
/// one-time commitment never steps.
public func stepFrom(_ sub: Subscription, _ anchor: Date, _ k: Int) -> Date {
    if k == 0 { return anchor }
    switch sub.billingCycle {
    case .once: return anchor
    case .custom:
        // A step no Int can count lands at the far end of time rather than trapping.
        let (span, overflow) = k.multipliedReportingOverflow(by: cycleDays(sub))
        if overflow { return k > 0 ? .distantFuture : .distantPast }
        return LB.addDays(anchor, span)
    case .monthly: return LB.addMonths(anchor, k)
    case .yearly: return LB.addMonths(anchor, k * 12)
    }
}

/// The days one custom step spans: 30 when unset, and held to 1…`CUSTOM_DAYS_LIMIT`, so a
/// count no write takes, already in a file, steps as the nearest one a write does.
public func cycleDays(_ sub: Subscription) -> Int {
    min(max(1, sub.customCycleDays ?? 30), CUSTOM_DAYS_LIMIT)
}

/// The rows a plan writes, on request and never otherwise: from `first`, one per cycle,
/// for `months` calendar months or up to the cancelling date. A one-time commitment gets
/// its single charge. Dates already holding a row are skipped.
public func planCharges(for sub: Subscription, from first: Date, months: Int, amount: Double,
                        skipping existing: Set<String> = [], writtenAt: String,
                        horizonFrom: Date? = nil) -> [ChargeRow] {
    // The horizon is exclusive — 24 months from September is September through August —
    // and a cancelling date is inclusive. When extending it is measured from the last
    // written charge, so "twelve more months" never reaches a renewal three years out.
    let horizon = LB.addMonths(horizonFrom ?? first, max(1, months))
    let cancel = cancelInfo(sub).date
    var out: [ChargeRow] = []
    var k = 0
    while k < 4000 {
        let date = stepFrom(sub, first, k)
        if sub.billingCycle != .once, date >= horizon { break }
        if let cancel, date > cancel { break }
        let iso = LB.toISO(date)
        if !existing.contains(iso) {
            out.append(ChargeRow(commitmentId: sub.id, date: iso, amount: amount,
                                 paid: false, basis: "plan", writtenAt: writtenAt))
        }
        if sub.billingCycle == .once { break }
        k += 1
    }
    return out
}

// MARK: - money

public struct CurrencyAmount: Equatable {
    public let currency: String
    public let amount: Double

    public init(currency: String, amount: Double) {
        self.currency = currency
        self.amount = amount
    }
}

/// One amount per currency — never blended, biggest first.
public func sumByCurrency(_ charges: [Charge]) -> [CurrencyAmount] {
    var totals: [String: Double] = [:]
    for c in charges { totals[c.currency, default: 0] += c.amount }
    return totals.map { CurrencyAmount(currency: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
}

private let noDecimalCurrencies: Set<String> = ["INR", "JPY"]
private let currencyLocales: [String: String] = [
    "INR": "en_IN", "USD": "en_US", "EUR": "de_DE", "GBP": "en_GB",
    "AED": "ar_AE", "SGD": "en_SG", "AUD": "en_AU", "CAD": "en_CA", "JPY": "ja_JP",
]

public func fmtMoney(_ amount: Double, _ currency: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    if let id = currencyLocales[currency] { f.locale = Locale(identifier: id) }
    let isWhole = amount == amount.rounded()
    // Both bounds move together, or an amount ending in a zero cent loses its last digit.
    let digits = (noDecimalCurrencies.contains(currency) || isWhole) ? 0 : 2
    f.minimumFractionDigits = digits
    f.maximumFractionDigits = digits
    return f.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
}

/// The same to the paisa, for a figure that must be checked rather than read: "₹47.49".
public func fmtMoneyExact(_ amount: Double, _ currency: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    if let id = currencyLocales[currency] { f.locale = Locale(identifier: id) }
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
}

/// An amount as a form's field holds it: a whole number without a point, nothing in exponent
/// form, and no conversion a huge number could trap on.
public func plainAmount(_ amount: Double) -> String {
    if amount == amount.rounded() {
        return abs(amount) < 1e15 ? String(Int64(amount)) : String(format: "%.0f", amount)
    }
    let text = String(amount)
    guard text.contains("e") else { return text }
    let plain = NumberFormatter()
    plain.locale = Locale(identifier: "en_US_POSIX")
    plain.numberStyle = .decimal
    plain.usesGroupingSeparator = false
    plain.maximumFractionDigits = 20
    return plain.string(from: NSNumber(value: amount)) ?? text
}

/// A per-currency total as one string: "₹149 + $20". Never a blend.
public func fmtMoneyTotals(_ sums: [CurrencyAmount]) -> String {
    sums.map { fmtMoney($0.amount, $0.currency) }.joined(separator: " + ")
}
