// The months a screen answers for, and the words that name them. Pure calendar logic: the
// dashboard's cards total whichever months are chosen, and every surface names them alike.
import Foundation

/// A set of calendar months, held as offsets from this month and never empty. A card counts
/// a charge whose day falls in any of them: whole months, joined into one window.
public struct MonthSelection: Hashable, Sendable {
    /// Offsets from this month: 0 is this month, -1 the one before it.
    public private(set) var offsets: Set<Int>

    /// One month alone — this month unless another is named.
    public init(_ offset: Int = 0) {
        offsets = [offset]
    }

    /// The months named, or nil when none are: a selection is never empty.
    public init?<S: Sequence>(offsets: S) where S.Element == Int {
        let set = Set(offsets)
        guard !set.isEmpty else { return nil }
        self.offsets = set
    }

    /// The months these days fall in, as offsets from `anchor`'s month. Two days in one
    /// month name it once; no days at all is no selection.
    public init?(days: [Date], anchor: Date) {
        let base = LB.firstOfMonth(anchor)
        self.init(offsets: days.compactMap {
            LB.calendar.dateComponents([.month], from: base, to: LB.firstOfMonth($0)).month
        })
    }

    public var count: Int { offsets.count }

    public func contains(_ offset: Int) -> Bool {
        offsets.contains(offset)
    }

    /// The offsets, earliest first.
    public var months: [Int] { offsets.sorted() }

    /// Whether the months follow one another with no gap — across a year end as well.
    public var isContiguous: Bool {
        let sorted = months
        guard let first = sorted.first, let last = sorted.last else { return true }
        return last - first == sorted.count - 1
    }

    /// Adds a month, or takes one away. Taking away the only month is refused and answers
    /// false: a selection is never empty.
    @discardableResult
    public mutating func toggle(_ offset: Int) -> Bool {
        if offsets.contains(offset) {
            guard offsets.count > 1 else { return false }
            offsets.remove(offset)
        } else {
            offsets.insert(offset)
        }
        return true
    }

    /// Every month moved by `delta`, the shape kept. Nil when any of them would leave
    /// `range`: stepping stops at the edge rather than dropping a month.
    public func shifted(by delta: Int, within range: ClosedRange<Int>) -> MonthSelection? {
        let moved = offsets.map { $0 + delta }
        guard moved.allSatisfy(range.contains) else { return nil }
        return MonthSelection(offsets: moved)
    }

    /// The same calendar months, counted from `anchor`'s month instead of `previous`'s: each
    /// offset moves back by the months passed. This month alone follows the calendar into the
    /// new one; months that would leave `range` give way to this month alone.
    public func carried(from previous: Date, to anchor: Date, within range: ClosedRange<Int>) -> MonthSelection {
        guard self != MonthSelection(),
              let passed = LB.calendar.dateComponents(
                  [.month], from: LB.firstOfMonth(previous), to: LB.firstOfMonth(anchor)
              ).month
        else { return self }
        return shifted(by: -passed, within: range) ?? MonthSelection()
    }

    /// The first day of each month, earliest first.
    public func firstDays(anchor: Date) -> [Date] {
        let base = LB.firstOfMonth(anchor)
        return months.map { LB.addMonths(base, $0) }
    }

    /// Each month's first and last day, earliest first — the windows a card totals.
    public func windows(anchor: Date) -> [(first: Date, last: Date)] {
        firstDays(anchor: anchor).map { ($0, Self.lastDay($0)) }
    }

    /// The same for every month from the earliest to the latest, chosen or not: a chart's
    /// places, so a month left out stands empty where it falls. Months with no gap between
    /// them give exactly `windows`.
    public func spanWindows(anchor: Date) -> [(first: Date, last: Date)] {
        let base = LB.firstOfMonth(anchor)
        guard let first = offsets.min(), let last = offsets.max() else { return [] }
        return (first...last).map { offset in
            let day = LB.addMonths(base, offset)
            return (day, Self.lastDay(day))
        }
    }

    /// From the first day of the earliest month to the last day of the latest. Months left
    /// out between them are inside the span; `windows` says which days count.
    public func span(anchor: Date) -> (first: Date, last: Date) {
        let base = LB.firstOfMonth(anchor)
        let sorted = months
        return (LB.addMonths(base, sorted.first ?? 0), Self.lastDay(LB.addMonths(base, sorted.last ?? 0)))
    }

    /// The words for the months: "September 2026" alone; a run as "Jul – Sep 2026" or
    /// "Nov 2025 – Jan 2026"; up to three apart as "Jan, Mar, Jun 2026" or "Dec 2025, Feb
    /// 2026"; more than three apart as "5 chosen months", never a length of time.
    public func label(anchor: Date, locale: Locale = .current) -> String {
        let days = firstDays(anchor: anchor)
        guard let first = days.first, let last = days.last else { return "" }
        let names = MonthNames(locale: locale)
        if days.count == 1 { return names.long(first) + " " + names.year(first) }
        if isContiguous {
            return names.year(first) == names.year(last)
                ? "\(names.short(first)) – \(names.short(last)) \(names.year(last))"
                : "\(names.short(first)) \(names.year(first)) – \(names.short(last)) \(names.year(last))"
        }
        guard days.count <= 3 else { return "\(days.count) chosen months" }
        // Each year is said once, after the last of its months.
        return days.indices.map { i in
            let closesYear = i == days.count - 1 || names.year(days[i + 1]) != names.year(days[i])
            return closesYear ? names.short(days[i]) + " " + names.year(days[i]) : names.short(days[i])
        }
        .joined(separator: ", ")
    }

    /// The words under a chart that gives each month one bar: the first month and the last,
    /// each with its year when the two years differ.
    public func edgeLabels(anchor: Date, locale: Locale = .current) -> (first: String, last: String) {
        let days = firstDays(anchor: anchor)
        guard let first = days.first, let last = days.last else { return ("", "") }
        let names = MonthNames(locale: locale)
        guard names.year(first) != names.year(last) else { return (names.short(first), names.short(last)) }
        return (names.short(first) + " " + names.year(first), names.short(last) + " " + names.year(last))
    }

    private static func lastDay(_ first: Date) -> Date {
        LB.addDays(LB.addMonths(first, 1), -1)
    }
}

/// A month's name in the reader's language, full or short; its year as the calendar numbers it.
private struct MonthNames {
    private let full: DateFormatter
    private let brief: DateFormatter

    init(locale: Locale) {
        full = Self.formatter("MMMM", locale)
        brief = Self.formatter("MMM", locale)
    }

    func long(_ date: Date) -> String { full.string(from: date) }
    func short(_ date: Date) -> String { brief.string(from: date) }
    func year(_ date: Date) -> String { String(LB.calendar.component(.year, from: date)) }

    private static func formatter(_ template: String, _ locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = LB.calendar
        formatter.timeZone = LB.calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
