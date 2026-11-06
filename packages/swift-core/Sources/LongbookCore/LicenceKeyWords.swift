// Words the licence key sheet says in the website Mac app.
import Foundation

public enum LicenceKeyWords {
    /// The key as sent: surrounding spaces and line breaks from a paste dropped.
    public static func trimmed(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True once something other than spaces is typed, which is when Activate wakes.
    public static func canClaim(_ key: String) -> Bool { !trimmed(key).isEmpty }

    /// The words for a refused claim: the server's own `why`, or a fallback with its status.
    public static func refusal(why: String?, status: Int) -> String {
        guard let why, !why.isEmpty else { return "The licence key could not be activated (\(status))." }
        return why
    }

    /// The words when the server could not be reached at all.
    public static let unreachable = "longbook.app could not be reached. Check the connection, then try again."
}
