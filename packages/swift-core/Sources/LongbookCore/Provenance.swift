// Who last touched a record, read from the vault's `_provenance` map. This is the honesty
// rule made visible: a figure can say where it came from, and a row nobody signed says that
// too rather than implying longbook verified it.
import Foundation

public struct Provenance {
    /// Who wrote the row; empty when nobody signed it and only a review mark names it.
    public let editedBy: String
    public let editedAt: Date?
    public let source: String?
    /// The app's name, written when the owner kept this row in Changes, and when — raw ISO
    /// text compared as text, so the other device's mark matches itself exactly. Only
    /// `OwnEdit` reads the mark; the pill's word stays with `editedBy`.
    public let reviewedBy: String?
    public let reviewedAt: String?

    /// "longbook-phone" and "longbook-mac" are ours; anything else is an outside tool, and
    /// the difference is what the pill is for.
    public var isOurs: Bool {
        editedBy.lowercased().hasPrefix("longbook")
    }

    /// Two or three words for a pill: who, and what they read if they said.
    public var word: String {
        isOurs ? "You" : [editedBy, source].compactMap { $0 }.joined(separator: " · ")
    }
}

public enum ProvenanceReader {
    /// Every signed or reviewed record, keyed by id. A record with neither is simply absent —
    /// never invented, and never guessed from a timestamp.
    public static func map(in raw: [String: Any]) -> [String: Provenance] {
        guard let object = raw["_provenance"] as? [String: Any] else { return [:] }
        let formatter = ISO8601DateFormatter()
        var out: [String: Provenance] = [:]
        for (id, value) in object {
            guard let entry = value as? [String: Any] else { continue }
            let by = (entry["edited_by"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let mark = (entry["reviewed_by"] as? String)?.trimmingCharacters(in: .whitespaces)
            guard !by.isEmpty || !(mark ?? "").isEmpty else { continue }
            out[id] = Provenance(
                editedBy: by,
                editedAt: (entry["edited_at"] as? String).flatMap { formatter.date(from: $0) },
                source: (entry["source"] as? String)?.trimmingCharacters(in: .whitespaces),
                reviewedBy: mark.flatMap { $0.isEmpty ? nil : $0 },
                reviewedAt: entry["reviewed_at"] as? String
            )
        }
        return out
    }
}

/// Whether a version that arrived from outside this process was written by the app on the
/// owner's other device. Decided by exact signing names, never the "longbook" prefix the
/// pill accepts, so a key or client named to look like the app still stands for review.
public enum OwnEdit {
    /// The names the app has ever signed with. "longbook-ios" is retired and kept.
    static let appNames: Set<String> = ["longbook-phone", "longbook-mac", "longbook-ios"]

    /// True when every row added, changed or removed carries a fresh app signature, or a
    /// fresh review mark from the other device's Keep: a charge under its own key first,
    /// else its commitment's. Tag rows are never signed: ignored beside others,
    /// disqualifying alone. An empty diff answers false.
    public static func isOwn(from old: [String: Any], to new: [String: Any]) -> Bool {
        let touched = vaultDiff(from: old, to: new).filter { $0.kind != "tags" }
        guard !touched.isEmpty else { return false }
        let before = ProvenanceReader.map(in: old)
        let after = ProvenanceReader.map(in: new)
        // Fresh means signed or marked by the app and not the entry the base already carried.
        // An entry that outlives its row vouches for the row's removal the same way.
        func fresh(_ id: String) -> Bool {
            guard let now = after[id] else { return false }
            let was = before[id]
            if appNames.contains(now.editedBy),
               was == nil || was?.editedBy != now.editedBy || was?.editedAt != now.editedAt {
                return true
            }
            guard let mark = now.reviewedBy, appNames.contains(mark) else { return false }
            return was == nil || was?.reviewedBy != mark || was?.reviewedAt != now.reviewedAt
        }
        for diff in touched {
            let ids = diff.added.map(\.id) + diff.changed.map(\.id) + diff.removed.map(\.id)
            for id in ids {
                let vouched = diff.kind == "charges" ? fresh(id) || fresh(commitmentKey(id)) : fresh(id)
                if !vouched { return false }
            }
        }
        return true
    }

    /// A charge diffs as "<commitment>@<date>"; with no entry of its own, its signature is
    /// the commitment's.
    static func commitmentKey(_ id: String) -> String {
        guard let at = id.lastIndex(of: "@") else { return id }
        return String(id[..<at])
    }
}
