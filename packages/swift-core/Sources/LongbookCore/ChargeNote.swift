// A charge's note as a screen labels it. A statement import writes "Statement line: …" into
// every charge it makes, and that prefix is the label, not part of the value. The note holds
// two things in one stored field: the statement line first, the owner's notes on the lines after.
import Foundation

public enum ChargeNote {
    public static let statementPrefix = "Statement line: "

    private static let bareLabel = statementPrefix.trimmingCharacters(in: .whitespaces)

    /// The note taken apart: the statement line's words, and whatever else it holds. A first
    /// line without the label is the owner's own, as are all the lines after it.
    public static func parts(_ note: String?) -> (statementLine: String?, notes: String) {
        guard let note else { return (nil, "") }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(bareLabel) else { return (nil, trimmed) }
        let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let words = lines[0].dropFirst(bareLabel.count).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (words.isEmpty ? nil : words, rest)
    }

    /// The note the file keeps for the two fields. The statement line stands on one line
    /// whatever was typed into it; empty on both sides, the note is empty.
    public static func joined(statementLine: String?, notes: String?) -> String {
        let flat = (statementLine ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
        let line = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return rest }
        return rest.isEmpty ? statementPrefix + line : statementPrefix + line + "\n" + rest
    }

    /// One labelled row per part the note holds: "Statement line" with its words, then "Note"
    /// with the rest.
    public static func rows(_ note: String?) -> [(label: String, value: String)] {
        let held = parts(note)
        return (held.statementLine.map { [(label: "Statement line", value: $0)] } ?? [])
            + (held.notes.isEmpty ? [] : [(label: "Note", value: held.notes)])
    }

    /// The row one line can show: the statement line where there is one, else the note. Nil for
    /// an empty note.
    public static func labelled(_ note: String?) -> (label: String, value: String)? {
        rows(note).first
    }

    /// The words a one-line surface shows: the value alone, since the line has no label slot.
    public static func value(_ note: String?) -> String? {
        labelled(note)?.value
    }

    /// Whether the note came from a statement, read by its prefix.
    public static func isStatementLine(_ note: String?) -> Bool {
        parts(note).statementLine != nil
    }

    /// The note the file keeps for a value typed under the "Statement line" label.
    public static func stored(_ value: String, statementLine: Bool) -> String {
        statementLine ? joined(statementLine: value, notes: nil) : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
