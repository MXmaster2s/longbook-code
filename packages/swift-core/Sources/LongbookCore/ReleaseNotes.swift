import Foundation

/// One version's list of what changed, as the app's changelog.json states it. The same file
/// gives TestFlight its "what to test", so the two never disagree.
public struct Release: Equatable, Sendable {
    public let version: String
    public let build: Int
    /// "2026-09-30"
    public let date: String
    public let changes: [String]

    public init(version: String, build: Int, date: String, changes: [String]) {
        self.version = version
        self.build = build
        self.date = date
        self.changes = changes
    }
}

public enum ReleaseNotes {
    /// The releases in the file, newest build first. Nil when the bytes are not that list; a
    /// release with no version or no changes is dropped rather than shown empty.
    public static func decode(_ data: Data) -> [Release]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let releases = rows.compactMap { row -> Release? in
            guard let version = row["version"] as? String, !version.isEmpty,
                  let build = row["build"] as? Int,
                  let changes = row["changes"] as? [String], !changes.isEmpty else { return nil }
            return Release(version: version, build: build, date: row["date"] as? String ?? "", changes: changes)
        }
        return releases.sorted { $0.build > $1.build }
    }

    /// The entry for the copy that is running, by its version; the newest when none matches,
    /// so a build cut without its entry still shows the latest words.
    public static func current(in releases: [Release], version: String) -> Release? {
        releases.first { $0.version == version } ?? releases.first
    }
}
