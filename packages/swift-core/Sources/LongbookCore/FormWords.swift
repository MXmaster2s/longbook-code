// Words the commitment form says that can be proved without a screen: the occurrence strip's
// chip labels, and the footnote under a status the owner has changed.
import Foundation

public enum FormWords {
    /// One chip's words: what it shows, and what it speaks — the full date, year included.
    public struct Occurrence: Equatable {
        public let label: String
        public let spoken: String
    }

    /// "6 Oct" — or "14 Feb 2027" once two chips would read alike, as a yearly plan's do, or
    /// the strip runs into another year. Each day is formatted once per word. A second row
    /// on one day keeps the first's words rather than trapping: outside edits leave such files.
    public static func occurrenceWords(_ days: [(iso: String, day: Date)]) -> [String: Occurrence] {
        var seen = Set<String>()
        let rows = days.filter { seen.insert($0.iso).inserted }
        let spansYears = Set(rows.map { $0.iso.prefix(4) }).count > 1
        let short = spansYears ? [] : rows.map { LB.shortDate($0.day) }
        let long = spansYears || Set(short).count < short.count
        return Dictionary(rows.enumerated().map { i, row in
            let spoken = LB.longDate(row.day)
            return (row.iso, Occurrence(label: long ? spoken : short[i], spoken: spoken))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// What a changed status does on Save, said while it differs from the file's. A stop
    /// unwrites the plan after today only from an active commitment with something planned;
    /// otherwise nothing is planned after today, and what happened stays either way.
    public static func statusNote(from was: SubStatus, to status: SubStatus, planned: Int, plansAhead: Bool) -> String? {
        guard was != status else { return nil }
        switch status {
        case .paused, .cancelled:
            guard was == .active, planned > 0 else { return "Nothing is planned after today. What happened stays." }
            let count = planned == 1 ? "the 1 planned charge" : "the \(planned) planned charges"
            return "\(status == .paused ? "Pausing" : "Cancelling") unwrites \(count) after today. What happened stays."
        case .active:
            // With a cancelling date in the way there is no count to pick: nothing plans past it.
            return plansAhead ? "Back to active plans it ahead again; pick the count beside the date."
                : "Back to active plans nothing past the cancelling date."
        }
    }
}
