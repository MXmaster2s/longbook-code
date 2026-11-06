// The cash-flow series behind the chart: the charges written over a window of calendar
// months. DENSE — every month gets a bucket, an empty one a zero row, so the axis never
// lies by omission. The scope currency is totalled; foreign stays foreign.
import Foundation

/// One calendar month of charges.
public struct MonthBucket {
    /// The first of the month, local midnight.
    public let month: Date
    /// The total in the scope currency — never a converted one.
    public let scoped: Double
    /// Foreign totals, one per currency — carried alongside, never blended in.
    public let others: [CurrencyAmount]
    /// Charge count across all currencies.
    public let count: Int
}

/// Every month from `monthsBack` before today's month to `monthsForward` after it —
/// exactly monthsBack + 1 + monthsForward buckets, oldest first. Read straight from the
/// rows: a month nobody wrote a charge for is an empty month, not a projected one.
public func monthlySeries(
    _ vault: Vault, scope: String, around today: Date,
    monthsBack: Int = 12, monthsForward: Int = 12
) -> [MonthBucket] {
    let first = LB.addMonths(LB.firstOfMonth(today), -monthsBack)
    let total = monthsBack + 1 + monthsForward
    let months = (0..<total).map { LB.addMonths(first, $0) }
    // The window ends on the final month's last day, not its first.
    let to = LB.addDays(LB.addMonths(first, total), -1)

    var byMonth: [String: [Charge]] = [:]
    for charge in chargesInRange(vault, from: first, to: to, today) {
        byMonth[LB.toISO(LB.firstOfMonth(charge.date)), default: []].append(charge)
    }

    return months.map { month in
        let charges = byMonth[LB.toISO(month)] ?? []
        let scoped = charges.filter { $0.currency == scope }.reduce(0) { $0 + $1.amount }
        let others = sumByCurrency(charges.filter { $0.currency != scope })
        return MonthBucket(month: month, scoped: scoped, others: others, count: charges.count)
    }
}
