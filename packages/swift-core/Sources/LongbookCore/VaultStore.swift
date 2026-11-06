// The app's view of the vault. Reading lives in Shared/VaultReader, since the widget is
// a separate process; this is the app-only half — state, and the write path.
//
// Holds THREE things: the decoded `Vault`, the RAW JSON, and the exact BYTES read.
import Foundation
import WidgetKit

@MainActor
final class VaultStore: ObservableObject {
    enum State {
        case needsFolder
        /// Carries a note, because "waiting for iCloud to send the file" is a different wait from
        /// "reading a local file", and on a phone the first one can take real seconds.
        case loading(String?)
        case loaded(Vault)
        case failed(String)
    }

    @Published private(set) var state: State = .needsFolder

    /// Surfaced to the UI so a failed save can be shown without tearing down the screen the owner is
    /// still standing on — losing a half-typed form to an error banner would be its own bug.
    @Published var saveError: String?

    /// Set once at launch (see LongbookApp) — the one thing `commit()` asks before writing.
    /// Weak: this store must never be the reason the entitlement object outlives its owner.
    weak var entitlement: EntitlementStore?

    static let dataFile = VaultReader.dataFile

    private var raw: [String: Any] = [:]
    private var bytesAtRead: Data?
    private var schema: [String: Any]?

    /// What we found in iCloud, deciding what the first-run screen offers.
    ///
    /// Published so the chooser can ASK rather than guess. An earlier version adopted a vault
    /// silently, so the reader never learned one had been found. Now it is a labelled button.
    enum ICloudState: Equatable {
        case probing
        case hasVault
        case empty
        case unavailable
    }

    @Published private(set) var iCloudState: ICloudState = .probing

    /// Called at launch: if a folder is remembered, go straight to reading it.
    ///
    /// Otherwise, before showing choices, LOOK — a vault may already be in our iCloud
    /// container from another device. The chooser then offers the existing one, not a second.
    func start() {
        if VaultLocation.isSet {
            reload()
        } else {
            state = .needsFolder
            probeICloud()
        }
    }

    /// Ask iCloud what's there, off the main actor — resolving a ubiquity container touches the disk
    /// and can block on a first run.
    func probeICloud() {
        iCloudState = .probing
        Task {
            let availability = await Task.detached(priority: .userInitiated) {
                VaultContainer.probe()
            }.value
            switch availability {
            case .hasVault: iCloudState = .hasVault
            case .empty: iCloudState = .empty
            case .unavailable: iCloudState = .unavailable
            }
        }
    }

    /// Where the open vault lives — what the mac-app screen's step 1 reports.
    ///
    /// The app already knows this, so the screen never has to ask: it says "not migrated yet" or "now
    /// syncing with your iCloud" from the same fact the migration itself acts on.
    var vaultIsInICloud: Bool {
        guard let folder = VaultLocation.resolve() else { return false }
        // Compared by path prefix against the container, which is the only iCloud location this app
        // can write to. `standardizedFileURL` because a bookmark can resolve through /private symlinks.
        guard let container = VaultContainer.vaultURL() else { return false }
        return folder.standardizedFileURL.path.hasPrefix(container.standardizedFileURL.path)
    }

    /// How big the open vault is, in bytes. Shown before migrating, because the fear is that moving a
    /// vault is a big operation and the truth is that it is a few tens of kilobytes of text.
    var vaultBytes: Int {
        guard let folder = VaultLocation.resolve() else { return 0 }
        return VaultMigration.totalBytes(in: folder)
    }

    /// Take on a vault that lives in our own container.
    ///
    /// No security scope here, unlike the picker path: the container is ours, so there is nothing to
    /// ask permission for. That difference is the entire benefit of this route.
    private func performContainerAdopt(_ folder: URL) async {
        do {
            state = .loading("Fetching your vault from iCloud…")
            try await VaultReader.materialize(folder.appendingPathComponent(Self.dataFile))
            let vault = try read(from: folder)
            try VaultLocation.remember(folder)
            state = .loaded(vault)
        } catch {
            // Falling back to the chooser rather than showing a failure: a vault we found on our own
            // initiative failing to open is not something the reader did, and the chooser is a screen
            // they can act on.
            VaultLocation.forget()
            state = .needsFolder
        }
    }

    /// Create a vault in the app's iCloud container — the one-tap route, no picker.
    func createInICloud() {
        state = .loading("Setting up your longbook in iCloud…")
        Task {
            let availability = await Task.detached(priority: .userInitiated) {
                VaultContainer.probeBeforeCreating()
            }.value

            switch availability {
            case .hasVault(let folder):
                // Someone else got there first (another device, mid-tap). Adopt rather than overwrite.
                await performContainerAdopt(folder)
            case .empty(let folder):
                do {
                    try VaultScaffold.create(at: folder, contractFiles: Self.bundledContractFiles())
                    let vault = try read(from: folder)
                    try VaultLocation.remember(folder)
                    state = .loaded(vault)
                } catch {
                    state = .failed(error.friendlyDescription)
                }
            case .unavailable:
                // Said plainly, because the alternative is a button that appears to work and doesn't.
                // An entitlement that fails to survive signing produces exactly this, silently.
                state = .failed("iCloud isn’t available on this iPhone. Check that you’re signed in to iCloud and that iCloud Drive is on, or keep your longbook on this iPhone instead.")
            }
        }
    }

    /// Adopt a folder the user just picked. `createIfEmpty` is the "create a new vault" branch of the
    /// first-run chooser; without it, a folder holding no vault is an error rather than a surprise
    /// new file appearing somewhere the owner only meant to look.
    func adopt(_ folder: URL, createIfEmpty: Bool) {
        state = .loading(nil)
        Task { await performAdopt(folder, createIfEmpty: createIfEmpty) }
    }

    private func performAdopt(_ picked: URL, createIfEmpty: Bool) async {
        // Security scope is taken FIRST and held across the whole operation, including the
        // bookmark creation. The scope is the PICKED folder's, while the vault may be a child
        // of it: creating and bookmarking `picked/longbook` happens inside the parent's grant.
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        do {
            // The picked folder is the vault's PARENT, not the vault — see VaultPlacement for why,
            // and for why an existing vault is adopted rather than sidestepped.
            let outcome = VaultPlacement.resolve(picked: picked)
            let folder = outcome.url

            switch outcome {
            case .adopt:
                state = .loading("Fetching your vault from iCloud…")
                try await VaultReader.materialize(folder.appendingPathComponent(Self.dataFile))
            case .create:
                guard createIfEmpty else {
                    state = .failed("No vault in that folder. Pick the folder that holds your longbook, or go back and create one instead.")
                    return
                }
                try createVault(at: folder)
            }

            let vault = try read(from: folder)
            // The bookmark is saved only once the folder has actually READ. Saving it first meant a
            // folder that failed was still remembered, so the next launch went straight back into
            // the same failure instead of offering the picker again.
            try VaultLocation.remember(folder)
            state = .loaded(vault)
        } catch {
            VaultLocation.forget()
            state = .failed(error.friendlyDescription)
        }
    }

    func reload() {
        guard let folder = VaultLocation.resolve() else {
            state = .needsFolder
            return
        }
        state = .loading(nil)
        Task { await performReload(folder) }
    }

    private func performReload(_ folder: URL) async {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            // iCloud can evict a file that hasn't been opened for a while, so this waits on every
            // read, not just the first — otherwise the app works until the day it's left alone.
            try await VaultReader.materialize(folder.appendingPathComponent(Self.dataFile))
            state = .loaded(try read(from: folder))
        } catch {
            state = .failed(error.friendlyDescription)
        }
    }

    // MARK: - staying current

    /// How often the app looks for an edit made somewhere else, while it's in front of you.
    ///
    /// Long enough to be free, short enough that a Mac change shows up before you'd reach for it.
    private static let watchInterval: Duration = .seconds(20)

    private var watcher: Task<Void, Never>?

    private func performQuietRefresh(_ folder: URL) async {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(Self.dataFile)
        // A short timeout, unlike the 30s an explicit read gets: this runs on a repeat, and a tick
        // that outlives its own interval would stack up behind itself. If the download needs longer,
        // the next tick asks again.
        try? await VaultReader.materialize(file, timeout: 5)
        // Compare bytes before doing anything visible. Most ticks find nothing, and re-publishing an
        // identical vault would redraw every screen and re-nudge the widget for no reason.
        guard let current = try? VaultReader.coordinatedRead(file), current != bytesAtRead else { return }
        if let vault = try? read(from: folder) { state = .loaded(vault) }
    }

    // MARK: - writing

    /// Add or update a commitment. Returns true when it reached the file.
    @discardableResult
    func save(_ edit: SubEdit) -> Bool {
        commit { try VaultPatch.apply(edit, to: $0, now: Date(), schema: self.schema) }
    }

    /// The contract's preferred way to end a commitment (llms.txt rule 6): the row stays, so the
    /// history it carries stays with it.
    @discardableResult
    func cancel(id: String) -> Bool {
        commit { try VaultPatch.cancel(id: id, in: $0, now: Date(), schema: self.schema) }
    }

    @discardableResult
    func delete(id: String) -> Bool {
        commit { try VaultPatch.delete(id: id, from: $0, now: Date()) }
    }

    /// Mark or unmark one upcoming occurrence paid — the swipe action on the glance's 30-day list.
    @discardableResult
    func setPaid(subscriptionId: String, date: String, paid: Bool) -> Bool {
        commit { try VaultPatch.setCharge(commitmentId: subscriptionId, date: date, paid: paid, in: $0, now: Date()) }
    }

    /// One write path for all three, so the discipline can't be forgotten in one of them: patch the
    /// raw JSON → re-check the file is unchanged → atomic coordinated write → re-read. The trial/
    /// read-only gate lives HERE too, for the same reason — one choke point, never per-view.
    private func commit(_ patch: ([String: Any]) throws -> [String: Any]) -> Bool {
        saveError = nil
        if entitlement?.state.readOnly == true {
            saveError = "Your trial has ended. Buy longbook to keep editing."
            return false
        }
        guard let folder = VaultLocation.resolve() else {
            state = .needsFolder
            return false
        }
        do {
            let next = try patch(raw)
            try write(next, to: folder)
            state = .loaded(try read(from: folder))
            // The Home Screen widget reads the same file but on its own schedule, so an edit made
            // here would otherwise sit invisible behind a stale glance until the system got around
            // to refreshing it.
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            saveError = error.friendlyDescription
            return false
        }
    }

    // MARK: - file work

    private func read(from folder: URL) throws -> Vault {
        let loaded = try VaultReader.load(from: folder)
        // A widget only refreshes at timeline expiry, so a Mac edit sits invisible until
        // midnight. The app IS the thing the owner opens, so noticing here and nudging is the
        // closest we get. Gated on the bytes actually differing.
        let changed = bytesAtRead != nil && bytesAtRead != loaded.bytes
        raw = loaded.raw
        bytesAtRead = loaded.bytes
        schema = VaultReader.schema(in: folder)
        // Every successful read funnels through here — first open, quiet refresh, and the re-read at
        // the end of every save — which makes this the one place the widget's copy can be kept level
        // with the vault without anyone having to remember to update it. See VaultMirror.
        let mirrorChanged = VaultMirror.write(loaded.bytes)
        // Nudged when EITHER changed; the second half is not redundant. `changed` is this
        // process's memory of the last read, so it is false on first launch after an update —
        // without the second clause, "open longbook" stays until the system next refreshes.
        if changed || mirrorChanged { WidgetCenter.shared.reloadAllTimelines() }
        return loaded.vault
    }

    /// Between the read and this save, the Mac may have written the file. VaultDisk holds
    /// the guard — one choke point shared with the multiplatform app.
    private func write(_ next: [String: Any], to folder: URL) throws {
        try VaultDisk.write(next, to: folder, expecting: bytesAtRead)
    }

    /// Create a complete vault: the folder, the memory, and the two contract files.
    ///
    /// `read(from:)` loads the schema **out of the vault** to validate writes, so a vault
    /// without it had nothing to validate against. `llms.txt` makes the folder legible.
    private func createVault(at folder: URL) throws {
        try VaultScaffold.create(at: folder, contractFiles: Self.bundledContractFiles())
    }

    /// The two contract files the app carries, read from its own bundle.
    ///
    /// The package bundle carries them, not the app's — `Bundle.main` has never held these,
    /// so this asked for files that were never there and scaffolded contract-less vaults.
    private static func bundledContractFiles() -> [String: Data] {
        VaultContract.bundledFiles()
    }
}
