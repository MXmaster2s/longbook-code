// Reading the vault, from either process: the app and widget are separate, so this
// can't live in the app's `@MainActor ObservableObject`. Plain functions both call.
// Every read goes through NSFileCoordinator, or a half-written file decodes garbage.
import Foundation

public enum VaultReader {
    public static let dataFile = "financial_memory.json"
    public static let schemaFile = "longbook.schema.json"
    /// The AI etiquette contract. Never read by this app — written when the phone creates a vault, so
    /// a phone-made folder is as legible to an outside tool as a Mac-made one.
    public static let llmsFile = "llms.txt"
    /// The seeded tag library, and the file whose `contract_revision` is read — which is what
    /// lets a refresh tell a newer contract set from an older one.
    public static let libraryFile = "library.json"
    /// The prompts an owner gives their AI, each with its result and procedure. Never read from
    /// the vault: the app reads its bundled copy through `PromptCatalog`.
    public static let promptsFile = "prompts.json"

    /// The bytes are returned alongside the decoded vault because the writer needs them: comparing
    /// them at save time is what proves nobody changed the file underneath us.
    public struct Loaded {
        public let vault: Vault
        public let raw: [String: Any]
        public let bytes: Data
    }

    public enum ReadError: LocalizedError {
        case unreadable(String)
        case notAVault
        case notDownloaded

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Couldn’t read \(name)."
            // The file is the owner's, and it IS readable — it just isn't a memory this build
            // understands. Say that, rather than a decoding error nobody can act on.
            case .notAVault: return "That file isn’t a financial memory this version can read."
            case .notDownloaded:
                return "Your longbook is still coming down from iCloud. Give it a moment on Wi-Fi, then try again."
            }
        }
    }

    /// What one look at the data file says without opening it: enough to tell a new write
    /// from the one already read. Two writes of the same bytes still differ by date.
    public struct Stamp: Equatable {
        public let modified: Date
        public let size: Int
    }

    /// One stat of the data file, on a fresh URL so the answer is live. Cheap enough to
    /// ask every few seconds; nothing is read or decoded. Nil when the file is not there.
    public static func stamp(_ folder: URL) -> Stamp? {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        var file = folder.appendingPathComponent(dataFile)
        file.removeAllCachedResourceValues()
        guard let v = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = v.contentModificationDate, let size = v.fileSize else { return nil }
        return Stamp(modified: modified, size: size)
    }

    /// Whether iCloud holds this file somewhere other than here. A placeholder answers
    /// `fileExists` yes and reads as nothing, so anyone reading without waiting must ask.
    public static func awaitingDownload(_ file: URL) -> Bool {
        let s = downloadStatus(file)
        return s.ubiquitous && !s.current
    }

    /// Whether iCloud owns the file, and whether this device holds its newest bytes.
    public static func downloadStatus(_ url: URL) -> (ubiquitous: Bool, current: Bool) {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var probe = url
        // URLs cache resource values; without this the status never appears to change and the
        // wait below would spin until it timed out on a file that had already arrived.
        probe.removeAllCachedResourceValues()
        guard let v = try? probe.resourceValues(forKeys: keys) else { return (false, false) }
        return (v.isUbiquitousItem ?? false, v.ubiquitousItemDownloadingStatus == .current)
    }

    /// Whether the file is here in name only: iCloud owns it and no bytes have landed yet.
    /// An older copy that is here reads fine when the name is the content's own hash.
    public static func isPlaceholder(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        var probe = url
        probe.removeAllCachedResourceValues()
        guard let v = try? probe.resourceValues(forKeys: keys), v.isUbiquitousItem == true else { return false }
        return v.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Ask iCloud for the file's newest bytes. A request, never a wait: a local folder has
    /// nothing to fetch, and a refusal is not something anyone could act on.
    public static func requestDownload(_ file: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
    }

    /// Wait for an iCloud file to exist on THIS device before reading. An undownloaded
    /// file is a **placeholder**: `fileExists` says yes but there are no bytes.
    /// `startDownloadingUbiquitousItem` only REQUESTS; this waits for `.current`.
    public static func materialize(_ file: URL, timeout: TimeInterval = 30) async throws {
        let first = downloadStatus(file)
        guard first.ubiquitous else { return }   // an ordinary local folder — nothing to wait for
        if first.current { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if downloadStatus(file).current { return }
        }
        throw ReadError.notDownloaded
    }

    public static func load(from folder: URL) throws -> Loaded {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let file = folder.appendingPathComponent(dataFile)
        // An iCloud file that has never been opened on this device is a placeholder until asked for.
        // Harmless (and throws) on a non-iCloud folder, hence try?.
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        // Requesting is not receiving. Reading a placeholder yields nothing to decode, which
        // would be reported as a broken vault; say what is true and let the caller wait.
        if awaitingDownload(file) { throw ReadError.notDownloaded }

        let bytes = try coordinatedRead(file)
        guard let vault = try? JSONDecoder().decode(Vault.self, from: bytes) else {
            throw ReadError.notAVault
        }
        let raw = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:]
        return Loaded(vault: vault, raw: raw, bytes: bytes)
    }

    /// The schema the VAULT ships. Kept for tools that want to see what a folder is carrying;
    /// writes are checked against `VaultContract.bundledSchema()`, which cannot be edited
    /// underneath us. Absent or unparseable is fine.
    public static func schema(in folder: URL) -> [String: Any]? {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let data = try? coordinatedRead(folder.appendingPathComponent(schemaFile)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func coordinatedRead(_ file: URL) throws -> Data {
        var readError: Error?
        var data: Data?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordError) { url in
            do { data = try Data(contentsOf: url) } catch { readError = error }
        }
        if let coordError { throw coordError }
        if let readError { throw readError }
        guard let data else { throw ReadError.unreadable(file.lastPathComponent) }
        return data
    }
}
