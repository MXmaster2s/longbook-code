import Foundation

/// What's New after an update: this version's changes, each said once, and whether this
/// device has shown them yet. The device keeps the last version it showed, never the vault.
public enum WhatsNew {
    /// The device's last version shown, in UserDefaults.
    public static let seenKey = "longbook.whatsNew.seenVersion"

    /// The badge a change wears: Fixed when its line says it fixed something, New otherwise.
    public enum Kind: Equatable, Sendable {
        case new, fixed

        public var label: String { self == .fixed ? "Fixed" : "New" }
    }

    public struct Change: Equatable, Sendable, Identifiable {
        public let kind: Kind
        /// The first sentence, which says what changed; shown in bold.
        public let lead: String
        /// The rest, which says how; empty when the line is one sentence.
        public let rest: String
        public var id: String { lead + rest }
    }

    public static func kind(of line: String) -> Kind {
        line.lowercased().hasPrefix("fix") ? .fixed : .new
    }

    /// One version's changes across every build it shipped as, newest build first, each line
    /// once. A line that says nothing changes for the reader is left out.
    public static func changes(for version: String, in releases: [Release]) -> [Change] {
        var lines: [String] = []
        for release in releases.sorted(by: { $0.build > $1.build }) where release.version == version {
            for line in release.changes where !lines.contains(line) && !line.hasPrefix("Nothing you will see") {
                lines.append(line)
            }
        }
        return lines.map { line in
            let lead = firstSentence(line)
            let rest = String(line.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            return Change(kind: kind(of: line), lead: lead, rest: rest)
        }
    }

    /// Whether this version is one the device has not shown. No version kept means a copy
    /// from before What's New, so it shows; a new install records its version first.
    public static func isDue(current: String, seen: String?) -> Bool {
        guard let seen, !seen.isEmpty else { return true }
        return isNewer(current, than: seen)
    }

    /// Dotted numbers compared part by part, so 1.10.0 is newer than 1.9.2.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The text up to its first full stop that ends a sentence: one before a space and a
    /// capital, so "1.3.6" and "Settings > Tutorials." hold together.
    public static func firstSentence(_ text: String) -> String {
        var index = text.startIndex
        while let stop = text[index...].firstIndex(of: ".") {
            let next = text.index(after: stop)
            if next < text.endIndex, text[next] == " ",
               let after = text[next...].dropFirst().first, after.isUppercase {
                return String(text[..<next])
            }
            index = next
        }
        return text
    }
}
