// Whether the first statement a new longbook is given is recent enough to open its Dashboard
// on: the newest file must end lately and the files together must cover about a month of
// recent days. Pure, and tested; the reader is never shown its numbers.
import Foundation

public enum FirstStatementCheck {
    /// The days a statement covers, first and last, both counted, as ISO days.
    public struct Period: Equatable, Sendable {
        public let start: String
        public let end: String

        /// The two days in order, whichever way they came.
        public init(start: String, end: String) {
            self.start = min(start, end)
            self.end = max(start, end)
        }
    }

    public enum Outcome: Equatable, Sendable {
        case pass
        /// The newest file ends before the cutoff.
        case notRecent
        /// Recent, but its recent days add up to less than a month.
        case tooShort
    }

    /// A monthly statement lands a few days after its month closes, and people download the
    /// one before last; two months covers both without letting an old file through.
    public static let recentDays = 60
    /// About a month, at least: February's 28 days pass, half a month does not.
    public static let fewestDays = 28
    /// Six months plus the recent window: days older than this say nothing about now, so an
    /// old statement beside a recent one earns nothing for its old days.
    public static let windowDays = 210

    /// The files' periods judged together against `today` (an ISO day). No period at all
    /// reads as not recent.
    public static func judge(_ periods: [Period], today: String) -> Outcome {
        guard let now = ordinal(today) else { return .pass }
        let spans = periods.compactMap { period -> (Int, Int)? in
            guard let start = ordinal(period.start), let end = ordinal(period.end) else { return nil }
            return (start, end)
        }
        guard let newest = spans.map(\.1).max(), newest >= now - recentDays else { return .notRecent }
        // Each period cut to the window, then merged, so a day two files share counts once.
        let floor = now - windowDays + 1
        let clipped = spans.map { (max($0.0, floor), min($0.1, now)) }.filter { $0.0 <= $0.1 }.sorted { $0.0 < $1.0 }
        var covered = 0
        var open: (Int, Int)?
        for span in clipped {
            if let current = open, span.0 <= current.1 + 1 {
                open = (current.0, max(current.1, span.1))
            } else {
                if let current = open { covered += current.1 - current.0 + 1 }
                open = span
            }
        }
        if let current = open { covered += current.1 - current.0 + 1 }
        return covered >= fewestDays ? .pass : .tooShort
    }

    /// A file's period: the one it prints when it prints one, otherwise its earliest and
    /// latest dated line. Nil with neither.
    public static func period(printed: Period?, dates: [String]) -> Period? {
        if let printed { return printed }
        let days = dates.filter { LB.parseDate($0) != nil }
        guard let first = days.min(), let last = days.max() else { return nil }
        return Period(start: first, end: last)
    }

    /// The period a statement's top prints of itself, "From 01/05/2026 To 31/10/2026" or
    /// "01 May 2026 to 31 Oct 2026", as two days; nil when it prints none.
    public static func printedPeriod(in text: String) -> Period? {
        let day = #"(\d{1,2}[/.\- ](?:\d{1,2}|[A-Za-z]{3,9})[/.\- ,]{1,2}\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: day + #"\s*(?:to|-|–|till)\s*:?\s*"# + day, options: .caseInsensitive) else { return nil }
        for line in text.split(separator: "\n").map(String.init) {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let fromRange = Range(match.range(at: 1), in: line), let toRange = Range(match.range(at: 2), in: line),
                      let from = StatementLines.parseDate(String(line[fromRange])),
                      let to = StatementLines.parseDate(String(line[toRange])), from <= to
                else { continue }
                return Period(start: from, end: to)
            }
        }
        return nil
    }

    /// Days since 1970 for an ISO day, counted in UTC so no clock change moves a boundary.
    static func ordinal(_ iso: String) -> Int? {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == parts[0], check.month == parts[1], check.day == parts[2] else { return nil }
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }
}
