// Calendar-day math for the vault.
//
// Ported in BEHAVIOUR from packages/core/src/domain/dates.ts. The vault stores plain calendar days
// (`YYYY-MM-DD`), never instants — "the 21st" has to mean the 21st wherever the phone is, so every
// date here is a local midnight built from y/m/d components rather than a parsed timestamp.
import Foundation

public enum LB {
    /// Gregorian in the device's own timezone. Held in one place so tests and app agree.
    public static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    /// A local-midnight date from calendar parts — the Swift twin of JS `new Date(y, m-1, d)`.
    public static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? Date(timeIntervalSince1970: 0)
    }

    /// Parse ISO `YYYY-MM-DD` to local midnight. Returns nil on anything malformed — a
    /// deliberate departure from core's lenient parse, since a bogus date would render
    /// as a confident "3 days overdue". Invented days (2026-02-31) rejected too.
    public static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let parts = s.split(separator: "-")
        guard parts.count >= 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2].prefix(2)),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: d))
        else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year == y && c.month == m && c.day == d) ? calendar.startOfDay(for: date) : nil
    }

    /// Parse an ISO 8601 instant (`2026-09-07T10:15:00Z`, with or without fractional
    /// seconds) as the server and sidecar write them. Nil for anything else — an instant is
    /// not a vault date, and never becomes one here.
    public static func parseDateTime(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: s) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: s)
    }

    /// Whether two instants fall on the same calendar day. Where a zone skips midnight
    /// for daylight saving, a day's first moment is not 00:00, so two dates meaning the
    /// same day can differ as instants — compare days, never instants.
    public static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    public static func toISO(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func todayMid() -> Date {
        calendar.startOfDay(for: Date())
    }

    /// The day an instant falls on, at its first moment — what "today" means to a writer
    /// handed an injected clock rather than the machine's.
    public static func dayOf(_ instant: Date) -> Date {
        calendar.startOfDay(for: instant)
    }

    /// Whole days from a to b (b − a). Calendar-based rather than a millisecond division, so a
    /// daylight-saving boundary can't turn 1 day into 0.96 and round wrong.
    public static func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    /// Add months, clamping the day to the target month's length — Jan 31 + 1 month = Feb 28/29,
    /// never overflowing into March. Foundation clamps natively, which is exactly core's
    /// `addMonthsClamped` rule.
    public static func addMonths(_ anchor: Date, _ months: Int) -> Date {
        guard let moved = calendar.date(byAdding: .month, value: months, to: anchor) else { return anchor }
        return calendar.startOfDay(for: moved)
    }

    public static func addDays(_ anchor: Date, _ days: Int) -> Date {
        guard let moved = calendar.date(byAdding: .day, value: days, to: anchor) else { return anchor }
        return calendar.startOfDay(for: moved)
    }

    /// "Today" / "Tomorrow" / "In N days" — the desktop's wording, so the phone and the menu bar
    /// say the same thing about the same day.
    public static func dayWord(_ days: Int) -> String {
        if days < 0 { return "\(abs(days))d overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days) days"
    }

    /// "Today" / "Yesterday" / "N days ago" — a charge behind us already happened, and
    /// "overdue" would accuse the reader of missing a bill they may well have paid.
    public static func agoWord(_ days: Int) -> String {
        switch days {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return "\(abs(days)) days ago"
        }
    }

    /// "6 Aug 2026" — a date that must stand alone, so it keeps its year.
    public static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMM y")
        return f.string(from: date)
    }

    public static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }

    // MARK: - calendar view helpers

    /// The first day of the month that contains `date`, at local midnight.
    public static func firstOfMonth(_ date: Date) -> Date {
        let c = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: c) ?? date
    }

    /// "July 2026" — the calendar's month header.
    public static func monthYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: date)
    }

    /// "July" — the month alone, in the owner's locale.
    public static func monthName(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: date)
    }

    /// Weekday initials, Sunday-first, matching the design's grid. Single letters (S M T W T F S).
    public static let weekdayInitials = ["S", "M", "T", "W", "T", "F", "S"]

    /// "Sep" — a month named under a chart's bar, where three letters fit.
    public static func shortMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: date)
    }

    /// "J" for July — the cash-flow chart's axis, where 25 columns leave room for one letter.
    public static func monthLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMMMM")
        return f.string(from: date)
    }
}
