// A charge's note as a screen labels it. A statement import writes "Statement line: …"
// into every charge it makes, and that prefix is the label, not part of the value.
import Foundation

public enum ChargeNote {
    public static let statementPrefix = "Statement line: "

    /// One labelled row: "Statement line" with the words after the prefix, or "Note" with
    /// the whole note. Nil for an empty note.
    public static func labelled(_ note: String?) -> (label: String, value: String)? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let bare = statementPrefix.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(bare) {
            let rest = trimmed.dropFirst(bare.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : ("Statement line", rest)
        }
        return ("Note", trimmed)
    }

    /// The words a one-line surface shows: the value alone, since the line has no label slot.
    public static func value(_ note: String?) -> String? {
        labelled(note)?.value
    }

    /// Whether the note came from a statement, read by its prefix.
    public static func isStatementLine(_ note: String?) -> Bool {
        note?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(statementPrefix.trimmingCharacters(in: .whitespaces)) == true
    }

    /// The note the file keeps for a value typed under the "Statement line" label.
    public static func stored(_ value: String, statementLine: Bool) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard statementLine, !trimmed.isEmpty else { return trimmed }
        return statementPrefix + trimmed
    }
}
