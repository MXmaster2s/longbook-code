import Foundation

/// One place the account is signed in: a device running longbook, a browser, or an AI holding
/// the connector. The server describes it in words; this only carries them to the sign-out
/// screen. The IP address and the raw user agent never leave the server.
public struct ActiveSession: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case app, connector, browser, other
    }

    public let id: String
    public let kind: Kind
    /// "iPhone", "Mac", "Claude", "Chrome on Mac".
    public let label: String
    /// "longbook 18 · iOS 27.0", "AI connector", or empty.
    public let detail: String
    public let signedInAt: Date?
    public let lastActiveAt: Date?
    /// The session this very request belongs to.
    public let isThisDevice: Bool

    public init(id: String, kind: Kind, label: String, detail: String, signedInAt: Date?, lastActiveAt: Date?,
                isThisDevice: Bool) {
        self.id = id
        self.kind = kind
        self.label = label
        self.detail = detail
        self.signedInAt = signedInAt
        self.lastActiveAt = lastActiveAt
        self.isThisDevice = isThisDevice
    }

    /// The function's answer, `{"sessions": [...]}`. Nil when the body is not that shape; a row
    /// missing an id or a label is dropped rather than shown as a blank line.
    public static func decode(_ data: Data) -> [ActiveSession]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = root["sessions"] as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty,
                  let label = row["label"] as? String, !label.isEmpty else { return nil }
            return ActiveSession(
                id: id,
                kind: Kind(rawValue: row["kind"] as? String ?? "") ?? .other,
                label: label,
                detail: row["detail"] as? String ?? "",
                signedInAt: date(row["signed_in_at"]),
                lastActiveAt: date(row["last_active_at"]),
                isThisDevice: row["this_device"] as? Bool ?? false
            )
        }
    }

    /// Postgres writes microseconds and a numeric offset ("2026-09-29T07:32:55.123456+00:00");
    /// a row that was never refreshed may carry none.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let found = withFraction.date(from: text) { return found }
        return ISO8601DateFormatter().date(from: text)
    }

    /// "just now", "3 hours ago", "2 days ago", in the reader's language.
    public func lastUsedWords(now: Date = Date()) -> String? {
        guard let lastActiveAt else { return nil }
        if now.timeIntervalSince(lastActiveAt) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastActiveAt, relativeTo: now)
    }
}

/// The function's whole answer: the sessions it carries, and how many the account has, which
/// can be more than it carries.
public struct ActiveSessionList: Equatable, Sendable {
    public let sessions: [ActiveSession]
    public let total: Int

    public init(sessions: [ActiveSession], total: Int) {
        self.sessions = sessions
        self.total = max(total, sessions.count)
    }

    public static func decode(_ data: Data) -> ActiveSessionList? {
        guard let sessions = ActiveSession.decode(data) else { return nil }
        let total = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["total"] as? Int
        return ActiveSessionList(sessions: sessions, total: total ?? sessions.count)
    }
}

