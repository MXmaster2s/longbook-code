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

extension VaultContainer {
    /// Asks for the container once, off the main thread, so iCloud starts preparing it at
    /// launch rather than when the first vault step needs it, as Apple's documentation advises.
    public static func prewarm() {
        Task.detached(priority: .utility) { _ = vaultURL() }
    }

    /// The iCloud account the container belongs to now; nil when iCloud is off.
    static func account() -> AnyHashable? {
        (FileManager.default.ubiquityIdentityToken as? NSObject).map(AnyHashable.init)
    }
}

/// `probeBeforeCreating()` asked early, during sign-in and purchase, so its answer is usually
/// in hand when the vault step comes. The vault step never waits for it: an answer not ready
/// then is left running, and a longbook is made at once.
public final class VaultPrecheck: @unchecked Sendable {
    public static let shared = VaultPrecheck()

    /// An early answer, the iCloud account it was given under, and when it was given.
    struct Held: Equatable {
        let availability: VaultContainer.Availability
        let account: AnyHashable?
        let at: Date
    }

    /// What the vault step does: the answer to act on, and whether iCloud confirmed it.
    /// Unconfirmed is an empty container that may still be bringing another device's vault down.
    public struct Step: Equatable {
        public let availability: VaultContainer.Availability
        public let confirmed: Bool
    }

    /// How long an early answer stands.
    static let maxAge: TimeInterval = 10 * 60

    private let lock = NSLock()
    private var running: Task<Void, Never>?
    private var startedAt: Date?
    private var held: Held?

    /// Starts the confirmation in the background. Does nothing while one runs or still stands.
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        if let startedAt, Date().timeIntervalSince(startedAt) < Self.maxAge { return }
        startedAt = Date()
        held = nil
        running = Task.detached(priority: .utility) { [self] in
            let account = VaultContainer.account()
            let answer = VaultContainer.probeBeforeCreating()
            let made = Held(availability: answer, account: account, at: Date())
            lock.withLock { held = made }
        }
    }

    /// The vault step's answer, at once: the early one when it is ready and still stands, the
    /// container as it lists now otherwise. Touches the disk, so never on the main thread.
    public func stepNow() -> Step {
        lock.lock()
        let early = held
        if early != nil { held = nil; startedAt = nil; running = nil }
        lock.unlock()
        return Self.step(early: early, now: Date(), account: VaultContainer.account(), current: VaultContainer.probe())
    }

    /// Waits for a check still under way, so what follows it gives iCloud that long first.
    public func settle() async {
        let task = lock.withLock { running }
        await task?.value
    }

    /// The step from an early answer, if any, and the container now. A found vault or iCloud
    /// off is an answer whatever came before; an empty container is confirmed only by an early
    /// answer that still stands.
    static func step(early: Held?, now: Date, account: AnyHashable?, current: VaultContainer.Availability) -> Step {
        if let early, let reused = reusable(early, now: now, account: account, current: current) {
            return Step(availability: reused, confirmed: true)
        }
        if case .empty = current { return Step(availability: current, confirmed: false) }
        return Step(availability: current, confirmed: true)
    }

    /// Whether an early answer still stands, checked against the container as it lists now.
    /// Too old, another iCloud account, or iCloud off before: no. A vault found before must
    /// still list there; empty before must still list empty, or list the vault that arrived.
    static func reusable(
        _ held: Held,
        now: Date,
        account: AnyHashable?,
        current: VaultContainer.Availability
    ) -> VaultContainer.Availability? {
        guard now.timeIntervalSince(held.at) <= maxAge, now >= held.at, held.account == account else { return nil }
        switch (held.availability, current) {
        case (.hasVault(let before), .hasVault(let after)) where before == after:
            return current
        case (.empty(let before), .empty(let after)) where before == after,
             (.empty(let before), .hasVault(let after)) where before == after:
            return current
        default:
            return nil
        }
    }
}

/// A second vault beside the one this device made without iCloud's confirmation: the copy
/// iCloud renames "financial_memory 2.json", or a version of the same file kept in conflict.
/// Found, never acted on: which one is the owner's real book is theirs to say.
public enum VaultDuplicates {
    public enum Kind: String, Sendable {
        case renamedCopy = "renamed_copy"
        case conflict
    }

    /// When the folder is looked at again after an unconfirmed vault was made, from that moment.
    static let checks: [TimeInterval] = [10, 60, 300, 900]

    /// What the folder holds beside the vault, from its listing and the file's conflict versions.
    static func kind(listing: [String], conflicts: Int) -> Kind? {
        let stem = (VaultReader.dataFile as NSString).deletingPathExtension
        let ext = (VaultReader.dataFile as NSString).pathExtension
        let pattern = "^\\.?\\Q\(stem)\\E \\d+\\.\\Q\(ext)\\E(\\.icloud)?$"
        if listing.contains(where: { $0.range(of: pattern, options: .regularExpression) != nil }) { return .renamedCopy }
        return conflicts > 0 ? .conflict : nil
    }

    /// The folder as it is now. Touches the disk.
    static func find(in dir: URL) -> Kind? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let file = dir.appendingPathComponent(VaultReader.dataFile)
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: file)?.count ?? 0
        return kind(listing: names, conflicts: conflicts)
    }

    /// Looks again after the early check has had its time, then at each of `checks`, and
    /// answers once with the first duplicate found. Changes nothing in the folder.
    public static func watch(_ dir: URL, found: @escaping @Sendable (Kind) -> Void) {
        let made = Date()
        Task.detached(priority: .utility) {
            await VaultPrecheck.shared.settle()
            if let kind = find(in: dir) { found(kind); return }
            for at in checks {
                let wait = made.addingTimeInterval(at).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                if let kind = find(in: dir) { found(kind); return }
            }
        }
    }
}
