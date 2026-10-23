// The dashboard's expense chart, as data: one bar a day, with the words a bar needs to
// name itself. Pure calendar and currency arithmetic, so the app draws what a test read.
import Foundation

/// One bar of the expense chart: a calendar day and what was charged on it. The scoped
/// sum is the bar's height; another currency is never added to it, only kept beside it.
public struct ExpenseBar: Equatable {
    public let day: Date
    /// The scope currency's total on the day.
    public let scoped: Double
    /// Every other currency's total on the day, biggest first.
    public let others: [CurrencyAmount]
    /// True when the day's charges are all in another currency: a marker, never a height.
    public let foreignOnly: Bool
    public let isPast: Bool
    /// True on the first bar of each calendar month, where an axis names the month.
    public let startsMonth: Bool
    public let chargeIds: [String]

    public init(day: Date, scoped: Double, others: [CurrencyAmount], foreignOnly: Bool,
                isPast: Bool, startsMonth: Bool, chargeIds: [String]) {
        self.day = day
        self.scoped = scoped
        self.others = others
        self.foreignOnly = foreignOnly
        self.isPast = isPast
        self.startsMonth = startsMonth
        self.chargeIds = chargeIds
    }
}

/// The bars for the chosen months: one month gives every calendar day, empty ones
/// included; several give only the days holding a charge, earliest first. A charge outside
/// the months is dropped, and a zero charge, a trial's sign-up day, earns no bar or
/// count. Basis is not consulted.
public func expenseBars(
    _ charges: [Charge], selection: MonthSelection, anchor: Date, scope: String, today: Date
) -> [ExpenseBar] {
    let windows = selection.windows(anchor: anchor)
    let span = selection.span(anchor: anchor)
    var perDay: [Date: [Charge]] = [:]
    for charge in charges where charge.amount != 0
        && windows.contains(where: { charge.date >= $0.first && charge.date <= $0.last }) {
        perDay[LB.dayOf(charge.date), default: []].append(charge)
    }
    let days: [Date] = windows.count == 1
        ? (0...max(LB.daysBetween(span.first, span.last), 0)).map { LB.addDays(span.first, $0) }
        : perDay.keys.sorted()
    var previousMonth: Date?
    return days.map { day in
        let held = perDay[day] ?? []
        let scoped = held.filter { $0.currency == scope }.reduce(0) { $0 + $1.amount }
        let others = sumByCurrency(held.filter { $0.currency != scope })
        let month = LB.firstOfMonth(day)
        defer { previousMonth = month }
        return ExpenseBar(
            day: day,
            scoped: scoped,
            others: others,
            foreignOnly: scoped == 0 && !others.isEmpty,
            isPast: day < today,
            startsMonth: previousMonth != month,
            chargeIds: held.map(\.id)
        )
    }
}
