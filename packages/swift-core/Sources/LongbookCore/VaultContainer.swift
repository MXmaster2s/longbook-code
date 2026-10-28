// The app's own iCloud container — the one place on iOS we write to without asking.
// A PUBLISHED container shows in iCloud Drive with the app's icon (what Obsidian does):
// the phone creates a vault with NO picker; the Mac reads it as a plain folder.
import Foundation

public enum VaultContainer {
    /// Must match `com.apple.developer.ubiquity-container-identifiers` in Longbook.entitlements and
    /// the key under NSUbiquitousContainers in project.yml. All three or none — a mismatch yields a
    /// nil container at runtime and no error anywhere, which is the failure mode this app has already
    /// been bitten by twice.
    public static let identifier = "iCloud.app.longbook"

    /// Where the vault sits inside the container, if available. `nil` means iCloud is
    /// unavailable — not signed in, off, or a lost entitlement. Callers must show that
    /// plainly. Touches disk and can block, so never called from a view body — see `probe()`.
    public static func vaultURL() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: identifier)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// What the chooser needs to know before it offers iCloud as a route.
    public enum Availability: Equatable {
        /// Available, and a vault is already there — adopt it without asking anything.
        case hasVault(URL)
        /// Available and empty. Creating one here is a single tap.
        case empty(URL)
        /// iCloud is not usable on this device. The reason is for the reader, not the log.
        case unavailable
    }

    /// Ask the container what state it is in. Blocking — call it off the main actor.
    public static func probe() -> Availability {
        guard let dir = vaultURL() else { return .unavailable }
        // Asking for the container URL does not create the directory, so a first run finds it missing.
        // Creating it here is safe and idempotent: an empty Documents folder in our own container is
        // not a vault and nothing else reads it.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Listed by name, not `fileExists`: a vault made on another device that hasn't downloaded
        // here yet is a ".name.icloud" placeholder, and calling that "empty" invites a second vault.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let present = names.contains(VaultReader.dataFile) || names.contains(".\(VaultReader.dataFile).icloud")
        return present ? .hasVault(dir) : .empty(dir)
    }

    /// `probe()` for a caller about to write a vault. A container new to this device lists
    /// empty while iCloud is still bringing its files down; a vault written into that gap meets
    /// the one arriving, and iCloud keeps both as "name 2". Blocking — never on the main thread.
    public static func probeBeforeCreating(timeout: TimeInterval = 30) -> Availability {
        let first = probe()
        guard case .empty(let dir) = first else { return first }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let answer = confirmEmpty(first, listing: names, timeout: timeout, iCloudListsVault: iCloudListsVault)
        if case .hasVault = answer { awaitListing(in: dir, timeout: timeout) }
        return answer
    }

    /// Known upstream, not yet here: asked for, and given until it lists, so the caller's
    /// read finds a name to wait on rather than an empty folder.
    private static func awaitListing(in dir: URL, timeout: TimeInterval) {
        let file = dir.appendingPathComponent(VaultReader.dataFile)
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .hasVault = probe() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// An empty answer checked against iCloud's own index, which names files not yet here.
    /// A folder holding nothing at all may simply not have arrived, so it waits for news;
    /// one holding anything has synced, and the index's first answer stands.
    static func confirmEmpty(
        _ first: Availability,
        listing: [String],
        timeout: TimeInterval,
        iCloudListsVault: (_ keepListening: Bool, _ timeout: TimeInterval) -> Bool
    ) -> Availability {
        guard case .empty(let dir) = first else { return first }
        if iCloudListsVault(listing.isEmpty, timeout) { return .hasVault(dir) }
        return first
    }

    /// Whether iCloud knows a vault file in the container, downloaded or not. Asked on the main
    /// run loop, which a metadata query needs, and waited for here; from the main thread, no.
    static func iCloudListsVault(keepListening: Bool, timeout: TimeInterval) -> Bool {
        guard !Thread.isMainThread else { return false }
        let search = VaultSearch(keepListening: keepListening)
        DispatchQueue.main.async { search.start(timeout: timeout) }
        search.done.wait()
        return search.found
    }
}

/// One metadata query, ended by the first result, by gathering finding none (unless asked to
/// keep listening), or by the deadline — whichever comes first. Lives on the main thread.
private final class VaultSearch: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private(set) var found = false
    private let keepListening: Bool
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var finished = false

    init(keepListening: Bool) {
        self.keepListening = keepListening
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, VaultReader.dataFile)
    }

    func start(timeout: TimeInterval) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [self] _ in
            if query.resultCount > 0 { finish(true) } else if !keepListening { finish(false) }
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [self] _ in
            if query.resultCount > 0 { finish(true) }
        })
        if !query.start() { finish(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [self] in finish(false) }
    }

    private func finish(_ result: Bool) {
        guard !finished else { return }
        finished = true
        found = result
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        done.signal()
    }
}
