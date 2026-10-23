// longbook.workspace.json — one vault's display preferences, beside the data file and never
// inside it. An outside AI rewriting financial_memory.json would drop flags it doesn't know,
// and the review would then announce preferences the owner never touched. Ported from the
// desktop's fileStoreBackend, filename included.
import Foundation

/// Raw-backed for the same reason the vault is: the Mac writes keys this build has no field
/// for, and a save must never be the thing that deletes them.
public struct Workspace {
    public private(set) var raw: [String: Any]

    public init(raw: [String: Any] = [:]) {
        self.raw = raw
    }

    /// The currency the app leads with. Nil derives it from the data instead. Never a rate —
    /// figures stay per-currency, never blended.
    public var homeCurrency: String? {
        get { (raw["homeCurrency"] as? String)?.trimmingCharacters(in: .whitespaces) }
        set {
            if let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                raw["homeCurrency"] = newValue.trimmingCharacters(in: .whitespaces)
            } else {
                raw["homeCurrency"] = NSNull()
            }
        }
    }

    /// Codes typed into the renewal form, so they come back as chips. A convenience, not a
    /// fact about the money, which is why it lives here and not in the vault.
    public var customCurrencies: [String] {
        get { (raw["customCurrencies"] as? [String]) ?? [] }
        set { raw["customCurrencies"] = dedup(newValue) }
    }

    /// Codes taken off the quick selector. The picker offers four of its own accord; this
    /// is how one of those is put away. A code a commitment counts is listed from the vault
    /// regardless, so this can never hide money.
    public var hiddenCurrencies: [String] {
        get { (raw["hiddenCurrencies"] as? [String]) ?? [] }
        set { raw["hiddenCurrencies"] = dedup(newValue) }
    }

    /// Commitments named at setup and not yet filled in: a name and a group each, no amount
    /// and no day. Not a fact about the money, so not in the vault; the timeline shows them
    /// until the form makes each one real.
    public var placeholders: [CommitmentPlaceholder] {
        get { ((raw["placeholders"] as? [[String: String]]) ?? []).compactMap(CommitmentPlaceholder.init(raw:)) }
        set { raw["placeholders"] = newValue.map(\.raw) }
    }

    /// Whether setup has asked "what commitments do you have?" for this vault.
    public var commitmentsAsked: Bool {
        get { (raw["commitmentsAsked"] as? Bool) ?? false }
        set { raw["commitmentsAsked"] = newValue }
    }

    /// Bookmarked commitment ids. In the vault an outside edit could drop them and the review
    /// would read as "bookmarks removed"; here that can't happen.
    public var bookmarks: [String] {
        get { (raw["bookmarks"] as? [String]) ?? [] }
        set { raw["bookmarks"] = Array(NSOrderedSet(array: newValue)) as? [String] ?? newValue }
    }

    /// Reports the owner deleted, by id: the app never draws them again.
    public var deletedReports: [String] {
        get { (raw["deletedReports"] as? [String]) ?? [] }
        set { raw["deletedReports"] = newValue.isEmpty ? nil : (Array(NSOrderedSet(array: newValue)) as? [String] ?? newValue) }
    }

    /// Live share ids by report id, so any device opening this vault can pull comments or
    /// revoke. The sidecar travels with the vault folder, which is exactly the right reach.
    public var reportShares: [String: String] {
        get { (raw["reportShares"] as? [String: String]) ?? [:] }
        set { raw["reportShares"] = newValue }
    }

    /// What is known about each live share, by report id: `url`, `expires_at`, `shared_on`,
    /// and `with` — the owner's own note of who has the link. Beside `reportShares`, never
    /// inside it: that map's shape is what every device reads.
    public var reportShareDetails: [String: [String: String]] {
        get { (raw["reportShareDetails"] as? [String: [String: String]]) ?? [:] }
        set { raw["reportShareDetails"] = newValue }
    }

    /// The account that last opened this folder, so a device can name it before anyone
    /// signs in and steer them to the same account instead of a second one. A record of
    /// who came last, never a lock: any address opens the folder. An address, never a
    /// credential.
    public var accountEmail: String? {
        get { (raw["accountEmail"] as? String)?.trimmingCharacters(in: .whitespaces) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespaces)
            if let trimmed, !trimmed.isEmpty {
                raw["accountEmail"] = trimmed
            } else {
                raw["accountEmail"] = NSNull()
            }
        }
    }

    /// The trip still running, by its report id: the one fact a trip's own file cannot say.
    /// Its report's last day follows today until the trip is ended.
    public var openTrip: String? {
        get { (raw["openTrip"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        set { raw["openTrip"] = newValue.flatMap { $0.isEmpty ? nil : $0 } ?? NSNull() }
    }

    /// Whether this vault keeps a hosted copy for the owner's AI. Off by default, and
    /// turning it off deletes the copy — the flag never outlives the row.
    public var hostedPush: Bool {
        get { (raw["hostedPush"] as? Bool) ?? false }
        set { raw["hostedPush"] = newValue }
    }

    /// Where the first run stands for this vault — `OnboardingStage.raw` — and the device
    /// that last wrote it, so a second device can offer to resume. Nil before it started.
    public var onboardingStage: String? {
        get { (raw["onboardingStage"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        set { raw["onboardingStage"] = newValue.flatMap { $0.isEmpty ? nil : $0 } ?? NSNull() }
    }

    public var onboardingDevice: String? {
        get { (raw["onboardingDevice"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        set { raw["onboardingDevice"] = newValue.flatMap { $0.isEmpty ? nil : $0 } ?? NSNull() }
    }

    /// Case-insensitive, order-preserving: "inr" typed after "INR" is the same code twice.
    private func dedup(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for code in codes.map({ $0.trimmingCharacters(in: .whitespaces) }) where !code.isEmpty {
            if seen.insert(code.lowercased()).inserted { out.append(code) }
        }
        return out
    }
}

public enum WorkspaceStore {
    public static let fileName = "longbook.workspace.json"

    /// A missing or unreadable sidecar is not an error: it means no preference has been
    /// saved yet, and every reader treats an absent field as "use the default".
    public static func read(in folder: URL) -> Workspace {
        let url = folder.appendingPathComponent(fileName)
        // A sidecar iCloud still holds elsewhere would be waited for by whichever thread
        // asked. Ask for it instead, and answer the defaults until it lands.
        if VaultReader.awaitingDownload(url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return Workspace()
        }
        guard let bytes = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else { return Workspace() }
        return Workspace(raw: object)
    }

    /// Read, change, write — so a field this build has no name for survives the save. Its own
    /// path on purpose: a preference still saves while data writes are refused.
    @discardableResult
    public static func update(in folder: URL, _ change: (inout Workspace) -> Void) throws -> Workspace {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        // The defaults read while the sidecar arrives must never be written over it.
        if VaultReader.awaitingDownload(folder.appendingPathComponent(fileName)) {
            throw VaultReader.ReadError.notDownloaded
        }
        var workspace = read(in: folder)
        change(&workspace)
        let data = try JSONSerialization.data(withJSONObject: workspace.raw, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
        return workspace
    }
}
