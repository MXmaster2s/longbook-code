// "Planned till" on the commitment form: the count of charges planned ahead beside the count
// the file held, so a Save writes one only when the owner moved it, and the day that count
// reaches, so the pills and the date are one value.
import Foundation

public struct PlannedCount: Equatable {
    /// The counts offered as pills; any other is the custom chip's.
    public static let usual = [6, 12, 24]
    /// The most charges one plan is set to, as `VaultPatch.setPlannedCount` caps it.
    public static let ceiling = 240

    /// What the pills show: the file's count until the owner moves it, none included.
    public var chosen: Int
    /// The file's count of charges ahead.
    public private(set) var held: Int

    public init(ahead: Int) {
        chosen = max(0, ahead)
        held = chosen
    }

    /// Charges were planned outside the Save and the file now holds `ahead`. A count nobody
    /// moved follows it; a count the owner chose stays theirs, and Save still writes it.
    public mutating func rebase(ahead: Int) {
        if chosen == held { chosen = max(0, ahead) }
        held = max(0, ahead)
    }
}

/// The days a recurring plan holds for each count: an existing one as its Save leaves it —
/// `VaultPatch.apply`, then `VaultPatch.setPlannedCount` — counted from today, or a new one from
/// its first charge. A count reaches a day, and a day stands for the charges up to it.
public struct PlanHorizon: Equatable {
    /// Every day the plan can reach, in order: rows already written from today on, then the
    /// days a longer plan adds, up to the cancelling date and the ceiling.
    public let days: [Date]
    /// For each written row: whether a shorter plan may take it away — unpaid and only planned.
    private let droppable: [Bool]

    /// An existing commitment's rows, read with the cycle the form holds now. `end` is the
    /// cancelling date the Save writes and `heldEnd` the file's, as the file words them: planned
    /// rows past `end` are unwritten only when the two differ, as the writer does.
    public init(rows: [ChargeRow], cycle: BillingCycle, customDays: Int?, end: String?, heldEnd: String?,
                today: Date) {
        let today = LB.dayOf(today)
        let stop = LB.parseDate(end)
        let cut = end != heldEnd ? stop : nil
        let kept = rows.compactMap { row -> (day: Date, plan: Bool)? in
            guard let day = LB.parseDate(row.date) else { return nil }
            let plan = !row.paid && (row.basis ?? "plan") == "plan"
            if plan, let cut, day > cut { return nil }
            return (day, plan)
        }
        let ahead = kept.filter { $0.day >= today }.sorted { $0.day < $1.day }
        var days = ahead.map(\.day)
        // More plan steps from the last row, never before today, as the writer adds it.
        if cycle != .once {
            let shape = Self.shape(cycle, customDays)
            let last = kept.map(\.day).max() ?? today
            let taken = Set(kept.map { LB.toISO($0.day) })
            var k = 1
            while days.count < PlannedCount.ceiling && k < 4000 {
                let day = stepFrom(shape, last, k)
                k += 1
                if let stop, day > stop { break }
                if day < today || taken.contains(LB.toISO(day)) { continue }
                days.append(day)
            }
        }
        self.days = days
        droppable = ahead.map(\.plan)
    }

    /// A new commitment, planned from its first charge, past or not.
    public init(first: Date, cycle: BillingCycle, customDays: Int?) {
        let first = LB.dayOf(first)
        let shape = Self.shape(cycle, customDays)
        days = cycle == .once ? [first] : (0..<PlannedCount.ceiling).map { stepFrom(shape, first, $0) }
        droppable = []
    }

    private static func shape(_ cycle: BillingCycle, _ customDays: Int?) -> Subscription {
        Subscription(id: "", name: "", amount: 0, currency: "", billingCycle: cycle,
                     customCycleDays: customDays, status: .active)
    }

    /// The first day counted; "Planned till" goes no earlier.
    public var next: Date? { days.first }

    /// How many written rows from today on stand once the Save's cancelling date is applied.
    public var written: Int { droppable.count }

    /// How many charges the plan can hold.
    public var most: Int { days.count }

    /// The days `count` charges fall on, none for none. A longer plan adds days after the
    /// last row; a shorter one takes planned rows away from the end, keeping the rest. The
    /// count already written is those rows, whatever the ceiling: a Save never sends it.
    public func days(count: Int) -> [Date] {
        guard count > 0 else { return [] }
        let written = droppable.count
        let wanted = count == written ? count : min(count, PlannedCount.ceiling)
        guard wanted < written else { return Array(days.prefix(wanted)) }
        var dropped = Set<Int>()
        for index in (0..<written).reversed() where written - dropped.count > wanted && droppable[index] {
            dropped.insert(index)
        }
        return (0..<written).filter { !dropped.contains($0) }.map { days[$0] }
    }

    /// The day the last of `count` charges falls on.
    public func till(count: Int) -> Date? { days(count: count).last }

    /// How many charges a plan through `day` holds: every one from the first day to it, and
    /// each row after it that a shorter plan cannot take, so the day picked is a day the Save
    /// keeps.
    public func count(through day: Date) -> Int {
        let day = LB.dayOf(day)
        let kept = droppable.indices.filter { !droppable[$0] && days[$0] > day }.count
        return days.filter { $0 <= day }.count + kept
    }
}
