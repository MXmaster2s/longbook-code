// Git-style history for the vault, without git: content-addressed snapshots under
// .longbook/history plus an append-only log, pure Foundation and CryptoKit. What lets
// the review answer "what changed while I was away" without ever touching the vault.
import CryptoKit
import Foundation

/// Who wrote the bytes being remembered — this app, or some outside tool. Stored in
/// the log, not inferred later, because only the writer knows at the time.
public enum HistorySource: String {
    case ours, outside
}

public struct HistoryEntry {
    public let hash: String
    public let source: HistorySource
    public let at: Date
    public let byteCount: Int
}

/// Why a record was refused.
public enum HistoryError: Error {
    /// The shared log is here in name only: iCloud still holds its bytes elsewhere.
    case notDownloaded
}

public enum VaultHistory {
    static let logName = "log.jsonl"

    /// Whether a file is here in name only. A snapshot is named by its content's hash, so an
    /// older copy that is here holds the right bytes; only a placeholder is waited for.
    /// Swappable so a test can make an ordinary file read as one still arriving.
    nonisolated(unsafe) static var awaitingDownload: (URL) -> Bool = VaultReader.isPlaceholder

    /// SHA-256 as lowercase hex — the snapshot's identity and its filename.
    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Remember one version of the vault's bytes. Returns nil and writes nothing shared when
    /// the newest logged hash already matches — consecutive duplicates are noise, though
    /// the same bytes may legitimately return later (an edit undone by hand). Throws
    /// `notDownloaded` rather than append to a log iCloud still holds elsewhere.
    @discardableResult
    public static func record(_ bytes: Data, source: HistorySource, in folder: URL) throws -> HistoryEntry? {
        let hash = Self.hash(bytes)
        // This device's copy first, whatever the shared log says: a version seen here is
        // here from now on, so the base of the next review never waits on iCloud.
        mirror(bytes, hash: hash, for: folder)
        let dir = directory(folder)
        // An older copy of the log is read, never appended to: the newer lines iCloud still
        // holds would be lost under this device's, so the append waits for them.
        let log = dir.appendingPathComponent(logName)
        if awaiting(log) || VaultReader.awaitingDownload(log) { throw HistoryError.notDownloaded }
        if entries(in: folder).first?.hash == hash { return nil }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appendingPathComponent("\(hash).json"), options: .atomic)

        let at = Date()
        let line: [String: Any] = [
            "hash": hash, "source": source.rawValue,
            "at": VaultPatch.iso8601(at), "bytes": bytes.count,
        ]
        var data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        data.append(0x0A)
        try append(data, to: dir.appendingPathComponent(logName))
        return HistoryEntry(hash: hash, source: source, at: at, byteCount: bytes.count)
    }

    /// The log, newest first. A line that doesn't parse is skipped rather than fatal —
    /// history is a convenience, and it must never make a vault unreadable. A log iCloud
    /// still holds elsewhere reads as empty; `awaitingLog(in:)` says so.
    public static func entries(in folder: URL) -> [HistoryEntry] {
        guard let raw = logText(directory(folder).appendingPathComponent(logName)) else { return [] }
        let f = ISO8601DateFormatter()
        return raw.split(separator: "\n").reversed().compactMap { line in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let hash = object["hash"] as? String,
                  let source = (object["source"] as? String).flatMap(HistorySource.init(rawValue:)),
                  let at = (object["at"] as? String).flatMap(f.date(from:)),
                  let bytes = object["bytes"] as? Int
            else { return nil }
            return HistoryEntry(hash: hash, source: source, at: at, byteCount: bytes)
        }
    }

    /// The bytes behind one entry, or nil once pruned away — or while iCloud still holds it
    /// elsewhere; `awaiting(hash:in:)` tells the two apart. Never waits: a wait here would
    /// stop the main actor. This device's own copy is read first. Nothing but a lowercase
    /// hex hash ever becomes a filename.
    public static func snapshot(hash: String, in folder: URL) -> Data? {
        guard isHex(hash) else { return nil }
        if let own = try? Data(contentsOf: mirrorFile(hash, for: folder)) { return own }
        let shared = directory(folder).appendingPathComponent("\(hash).json")
        guard !awaiting(shared) else { return nil }
        return try? Data(contentsOf: shared)
    }

    /// Whether iCloud still holds this version somewhere other than here — what tells a
    /// nil snapshot apart from one pruned away. Asks for the download on the way. A copy
    /// in this device's mirror answers false: there is nothing to wait for.
    public static func awaiting(hash: String, in folder: URL) -> Bool {
        guard isHex(hash), !mirrored(hash, for: folder) else { return false }
        return awaiting(directory(folder).appendingPathComponent("\(hash).json"))
    }

    /// Waits, off the main actor, for the shared log iCloud holds elsewhere.
    public static func materializeLog(in folder: URL) async throws {
        try await VaultReader.materialize(directory(folder).appendingPathComponent(logName))
    }

    /// The same question of the shared log.
    public static func awaitingLog(in folder: URL) -> Bool {
        awaiting(directory(folder).appendingPathComponent(logName))
    }

    /// Waits, off the main actor, for a version iCloud holds elsewhere — thirty seconds at
    /// most, as the vault file itself is waited for. Returns at once for one already here.
    public static func materialize(hash: String, in folder: URL) async throws {
        guard isHex(hash), !mirrored(hash, for: folder) else { return }
        try await VaultReader.materialize(directory(folder).appendingPathComponent("\(hash).json"))
    }

    /// Drop the oldest log lines beyond `keep`, then delete any snapshot no remaining
    /// line references. A hash can repeat, so only the genuinely unreferenced go.
    /// How many versions the log keeps; Changes states it.
    public static let kept = 50

    public static func prune(in folder: URL, keep: Int = kept) {
        let dir = directory(folder)
        let log = dir.appendingPathComponent(logName)
        guard keep >= 0, let raw = logText(log) else { return }
        let lines = raw.split(separator: "\n").map(String.init)
        guard lines.count > keep else { return }

        let kept = Array(lines.suffix(keep))
        let referenced = Set(kept.compactMap(hashIn))
        let dropped = Set(lines.prefix(lines.count - keep).compactMap(hashIn))
        let gone = dropped.subtracting(referenced)
        for hash in gone where isHex(hash) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(hash).json"))
        }
        pruneMirror(for: folder, dropping: gone)
        let body = kept.isEmpty ? Data() : Data((kept.joined(separator: "\n") + "\n").utf8)
        try? body.write(to: log, options: .atomic)
    }

    /// What the kept versions take on this device: the shared snapshots and log in the
    /// folder, and this device's own copies of them.
    public static func size(in folder: URL) -> Int {
        [directory(folder), mirrorDirectory(for: folder)].reduce(0) { $0 + bytes(under: $1) }
    }

    /// Every kept version gone, in the folder and on this device. Not undoable: Changes
    /// asks twice before calling it.
    public static func clear(in folder: URL) {
        let fm = FileManager.default
        for dir in [directory(folder), mirrorDirectory(for: folder)] {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "json" || item.lastPathComponent == logName {
                try? fm.removeItem(at: item)
            }
        }
    }

    private static func bytes(under dir: URL) -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: this device's mirror

    /// Where this device keeps its own copy of every version it has recorded, outside the
    /// shared folder: Application Support, one directory per vault. Swappable so tests
    /// stay in a temporary folder.
    nonisolated(unsafe) static var mirrorRoot: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("longbook").appendingPathComponent("history")

    /// The mirror for one vault, named by its folder path as the app's own keys are.
    public static func mirrorDirectory(for folder: URL) -> URL {
        mirrorRoot.appendingPathComponent(hash(Data(folder.path.utf8)))
    }

    private static func mirrorFile(_ hash: String, for folder: URL) -> URL {
        mirrorDirectory(for: folder).appendingPathComponent("\(hash).json")
    }

    private static func mirrored(_ hash: String, for folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: mirrorFile(hash, for: folder).path)
    }

    /// Best effort: a copy that cannot be written leaves the shared history as it was. The
    /// directory is a cache of what iCloud already holds, so backups skip it.
    private static func mirror(_ bytes: Data, hash: String, for folder: URL) {
        guard !mirrored(hash, for: folder) else { return }
        var dir = mirrorDirectory(for: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        try? bytes.write(to: mirrorFile(hash, for: folder), options: .atomic)
    }

    /// The mirror loses exactly what the shared folder loses. A version the log never got —
    /// recorded while the log was arriving, or overwritten by the other device's copy of
    /// it — may still be this device's base, so nothing else is swept.
    private static func pruneMirror(for folder: URL, dropping gone: Set<String>) {
        let dir = mirrorDirectory(for: folder)
        for hash in gone where isHex(hash) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(hash).json"))
        }
    }

    // MARK: helpers

    private static func directory(_ folder: URL) -> URL {
        folder.appendingPathComponent(".longbook").appendingPathComponent("history")
    }

    /// Asks iCloud for a file it holds elsewhere and says so; never reads one.
    private static func awaiting(_ url: URL) -> Bool {
        guard awaitingDownload(url) else { return false }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return true
    }

    /// The log's text, or nil while it is absent — or arriving, which must not be read.
    private static func logText(_ log: URL) -> String? {
        guard !awaiting(log) else { return nil }
        return try? String(contentsOf: log, encoding: .utf8)
    }

    private static func hashIn(_ line: String) -> String? {
        ((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any])?["hash"] as? String
    }

    private static func isHex(_ hash: String) -> Bool {
        hash.range(of: "^[a-f0-9]+$", options: .regularExpression) != nil
    }

    private static func append(_ data: Data, to log: URL) throws {
        guard FileManager.default.fileExists(atPath: log.path) else {
            try data.write(to: log, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

// MARK: the verdict

extension VaultHistory {
    /// What this device holds of the version a reload is judged against.
    public enum BaseState: Equatable {
        /// Its bytes are here.
        case bytes
        /// iCloud still holds it elsewhere; it may land in a moment.
        case arriving
        /// Pruned away, or never recorded here.
        case missing
    }

    /// The one decision behind every reload that finds the file changed.
    public enum Verdict: Equatable {
        /// Move on: the version is the owner's own, synced from their other device, or has
        /// no base to be judged against.
        case adopt
        /// A review stands — opened now, or still open on the base the owner last accepted.
        case review
        /// The base is still coming down from iCloud; decide nothing until it lands.
        case wait
    }

    /// Pure, so it is tested without the app: the model gathers the facts, this says what
    /// they mean. An own write with no review open adopts whatever the base says, so it is
    /// never read; otherwise the base decides, and one still arriving decides nothing yet.
    public static func verdict(ours: Bool, hasOpenReview: Bool, base: BaseState, synced: Bool, unchanged: Bool) -> Verdict {
        if base == .arriving, !ours || hasOpenReview { return .wait }
        let hasBase = hasOpenReview || base == .bytes
        if ours || !hasBase || synced || unchanged {
            // Inside a review the base stays what the owner last accepted: an own edit
            // there is recorded, and the review stands unless it moved nothing.
            return !hasOpenReview || synced || unchanged ? .adopt : .review
        }
        return .review
    }
}
