// Every charge joined to its commitment, read once and kept by commitment id, so a
// screen walking a thousand commitments never scans the charges a thousand times.
import Foundation

public struct ChargeIndex {
    public let today: Date
    private let bySub: [String: [Charge]]

    public init(_ vault: Vault, today: Date = LB.todayMid()) {
        self.today = today
        let subs = Dictionary(vault.subscriptions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var grouped: [String: [Charge]] = [:]
        for row in vault.charges {
            guard let sub = subs[row.commitmentId], let date = LB.parseDate(row.date) else { continue }
            grouped[sub.id, default: []].append(Charge(sub: sub, row: row, date: date, today: today))
        }
        for id in grouped.keys { grouped[id]?.sort { $0.date < $1.date } }
        bySub = grouped
    }

    /// The rows of one commitment, date order — what `charges(of:in:)` reads from the vault.
    public func charges(of id: String) -> [Charge] {
        bySub[id] ?? []
    }

    public func charges(of sub: Subscription) -> [Charge] {
        bySub[sub.id] ?? []
    }

    /// The soonest charge on or after today — paid or not.
    public func nextChargeOnOrAfter(_ sub: Subscription) -> Charge? {
        charges(of: sub).first { $0.date >= today }
    }

    /// The soonest charge on or after today that still needs the owner's attention.
    public func nextUnpaidChargeOnOrAfter(_ sub: Subscription) -> Charge? {
        charges(of: sub).first { $0.date >= today && !$0.paid }
    }

    /// `isLiveCommitment`, read from the index.
    public func isLiveCommitment(_ sub: Subscription) -> Bool {
        guard isOwed(sub), isEffectivelyActive(sub, today) else { return false }
        if sub.billingCycle != .once { return true }
        let own = charges(of: sub)
        return own.isEmpty || own.contains { $0.date >= today && !$0.paid }
    }

    /// The last day a commitment has a charge written for.
    public func plannedThrough(_ sub: Subscription) -> Date? {
        charges(of: sub).last?.date
    }

    /// `nextCharges`, read from the index: each live commitment's next charge, soonest first.
    public func nextCharges(_ vault: Vault) -> [DueMeta] {
        vault.subscriptions
            .filter { isOwed($0) && isEffectivelyActive($0, today) }
            .compactMap { sub -> DueMeta? in
                guard let next = nextChargeOnOrAfter(sub) else { return nil }
                return DueMeta(sub: sub, charge: next, date: next.date, days: LB.daysBetween(today, next.date))
            }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.sub.name < $1.sub.name }
    }

    /// `activeUpcoming(of:)`, read from the index: each live commitment's next unpaid charge.
    public func activeUpcoming(of subs: [Subscription]) -> [DueMeta] {
        subs
            .filter { isOwed($0) && isEffectivelyActive($0, today) }
            .compactMap { sub -> DueMeta? in
                guard let next = nextUnpaidChargeOnOrAfter(sub) else { return nil }
                return DueMeta(sub: sub, charge: next, date: next.date, days: LB.daysBetween(today, next.date))
            }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.sub.name < $1.sub.name }
    }

    /// `chargesInRange(of:)`, read from the index: the spending rows of some commitments
    /// between two days, inclusive, date order.
    public func chargesInRange(of subs: [Subscription], from: Date, to: Date) -> [Charge] {
        subs.filter(isSpending)
            .flatMap { charges(of: $0) }
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
    }

    /// `nextDueDay`, read from the index: the nearest day anything is still owed.
    public func nextDueDay(_ vault: Vault) -> PaymentDay? {
        let nexts = vault.subscriptions
            .filter { isOwed($0) && isEffectivelyActive($0, today) }
            .compactMap { nextUnpaidChargeOnOrAfter($0) }
        guard let soonest = nexts.map(\.date).min() else { return nil }
        let onDay = nexts.filter { LB.isSameDay($0.date, soonest) }.sorted { $0.amount > $1.amount }
        return PaymentDay(date: soonest, days: LB.daysBetween(today, soonest),
                          charges: onDay.filter { isSpending($0.sub) }, transfers: onDay.filter { $0.sub.isTransfer })
    }
}
