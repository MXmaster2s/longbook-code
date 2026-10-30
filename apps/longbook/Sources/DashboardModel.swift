import DesignSystem
import Foundation
import LongbookCore
import Observation
import os

/// Everything the dashboard draws, derived once per load for one scope currency.
/// Two rules govern every panel: summed values are one currency at a time, never
/// converted; the 30-day rail crosses currencies deliberately — a timeline, not a total.
struct DashboardData {
    struct Rail {
        /// Spending and transfers together, date order: a timeline, never a total.
        let charges: [Charge]
        /// The spending cards among them; `transferCount` is the rest.
        let upcomingCount: Int
        let transferCount: Int
        let dots: [(fraction: Double, heavy: Bool)]
        /// True when the rail is showing the last 30 charges instead of the next 30.
        /// The reader asks for this deliberately; nothing flips it on its own.
        let looksBack: Bool
        /// The days the charges span, first and last; today at either end when empty.
        let from: Date
        let to: Date
    }

    /// The months the cards answer for, read as one window: one month, or several joined.
    struct Month {
        /// The selection's words — "September 2026", "Jul – Sep 2026", "5 chosen months".
        let name: String
        let total: Double
        let otherTotals: [CurrencyAmount]
        let chargeCount: Int
        /// Scope-currency money dated today or later inside the months. Only months that
        /// reach this one or later hold any.
        let remaining: Double
        let remainingDate: Date?
        /// One bar a day for a single month; for several, one bar for each day that holds a
        /// charge, the empty days between them left out.
        let bars: [ExpenseBar]
        /// The words under the bars' two ends: the first and last day, or month.
        let edges: (first: String, last: String)
        /// Each month's first day, in order — what the cards' doors narrow the list to.
        let firstDays: [Date]
        /// Every charge the months hold, soonest first — what the card shows when turned.
        let expenses: [Charge]
        /// Whether the months include this one, so the turned card leads with what is ahead.
        let holdsThisMonth: Bool
        /// Money in over the months, in the scope currency — said beside the total, never in it.
        let income: Double
    }

    struct Slice: Identifiable {
        /// One commitment inside a slice, for the breakdown a tap opens. Amounts stay
        /// per-currency here too — a line never blends what the slice above it kept apart.
        struct Line: Identifiable {
            let id: String
            let name: String
            let scoped: Double
            let others: [CurrencyAmount]
        }

        let id: String
        let name: String
        let scoped: Double
        let share: Double?
        let others: [CurrencyAmount]
        let ink: Int?
        /// What the slice is made of, largest first — the same window the slice totals.
        let breakdown: [Line]
        /// Every charge the slice's own window holds, soonest first — the same charges
        /// that made `scoped`, so a card's rows and its total answer for one window.
        let charges: [Charge]
    }

    struct SidebarEntity: Identifiable {
        let id: String
        let name: String
        let count: Int
        let ink: Int?
        /// Starred on People or Accounts: the only rows the Mac sidebar keeps.
        var starred = false
    }

    struct CommitmentItem: Identifiable {
        /// Priority is trial > cancelling > paused > cancelled; nil for the ordinary
        /// case — a badge marks an exception, and most rows aren't one.
        enum Badge {
            case trial, cancelling, paused, cancelled
        }

        let id: String
        let name: String
        let amountText: String
        let facts: [LBMetaFact]
        let searchText: String
        let category: String?
        let ink: Int?
        let badge: Badge?
        /// The month heading this row files under. Nil = not scheduled: settled
        /// one-times, paused and cancelled rows, dates that wouldn't parse.
        let monthLabel: String?
        /// The upcoming charge's day, so the row can carry the paid toggle. Nil for
        /// anything not scheduled — there is no occurrence to mark.
        let dueISO: String?
        let isPaid: Bool
        let methodId: String?
        let memberId: String?
        /// How far the plan is written, as words — nil when nothing is written at all.
        let plannedThrough: String?
        let isRecurring: Bool
        /// The facts the list's filters ask for, as the row carries them.
        let cycle: BillingCycle
        let status: SubStatus
        let currency: String
    }

    /// The next day anything is owed. `charges` is all a total may hold; a transfer due
    /// that day rides in `transfers`, and either list may be the empty one.
    let nextDay: PaymentDay?
    let activeCount: Int
    let rail: Rail
    let month: Month
    let methods: [Slice]
    /// The words for the months the accounts and categories panels total — the same
    /// months the expenses panel shows.
    let accountsMonthName: String
    /// How many currencies the active commitments actually span. The stat card says the
    /// real number instead of claiming "all".
    let currencyCount: Int
    let categories: [Slice]
    let scope: String
    let scopeChoices: [String]
    let sidebarMethods: [SidebarEntity]
    let sidebarMembers: [SidebarEntity]
    let vaultLocation: String
    let commitments: [CommitmentItem]
    let commitmentCategories: [String]
}

extension DashboardData {
    /// The real number of currencies, not a claim of "all". One currency says which.
    /// The dashboard's stat card and the reports summary read the same words here, so
    /// the two screens never disagree about one number.
    var currencyWords: String {
        let words = [2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine"]
        guard currencyCount > 1 else { return "All in \(scope)" }
        return "Across \(words[currencyCount] ?? String(currencyCount)) currencies"
    }
}

@Observable
@MainActor
final class DashboardModel {
    enum State {
        case loading
        /// A vault operation in flight, wearing its own words — "looking in your iCloud"
        /// is a different wait from "creating your longbook", and the reader should know
        /// which one they are in.
        case provisioning(String)
        /// No vault anywhere. The reader chooses — check iCloud for one made elsewhere,
        /// or create a new one. Nothing is written just from reaching this state, so a
        /// background reload landing here is as safe as the first launch. `checkedICloud`
        /// flips the copy to "couldn't find one — check again, or create?"
        case firstRun(checkedICloud: Bool)
        /// iCloud was tried and genuinely can't be used right now — the message is why.
        case unavailable(String)
        case failed(String)
        case loaded(DashboardData)
    }

    private(set) var state: State = .loading
    /// Kept for on-demand derivations (the calendar's browsable months) so browsing
    /// twelve months doesn't precompute twenty-five grids nobody asked for.
    private var vault: Vault?
    /// Where the vault lives — the reports folder sits beside the data file.
    private var vaultFolder: URL?
    /// Where the vault lives, for surfaces that point other apps at it. Read-only.
    var vaultFolderURL: URL? { vaultFolder }
    /// Hears a write made elsewhere — the phone through iCloud, an agent — and asks for a
    /// re-read. Made on the first load, re-pointed only when the folder changes.
    @ObservationIgnored private var watcher: VaultWatcher?
    /// What the data file looked like when it was last read, so a tick can tell a new write
    /// from the one on screen without opening the file.
    @ObservationIgnored private(set) var loadedStamp: VaultReader.Stamp?
    /// Whether the app is anywhere on screen. The watcher sleeps while it is not: nothing is
    /// looking, and a locked phone should not spend its battery hearing a write.
    @ObservationIgnored var inForeground = true {
        didSet { inForeground ? watcher?.resume() : watcher?.suspend() }
    }
    private static let log = Logger(subsystem: "app.longbook", category: "vault")
    /// The raw file as read — every write patches THIS and compares THESE bytes on disk.
    private var loadedFile: VaultReader.Loaded?
    /// This build's schema, not the folder's: the folder's copy is something we wrote, and
    /// anything with the vault open can edit it or leave it a release behind.
    private let schema: [String: Any]? = VaultContract.bundledSchema()
    /// The last write's refusal, in the product's voice; nil after a clean save. Every
    /// screen that shows it drops it on the way in, so a refusal raised in one place
    /// cannot follow the reader to a screen that never wrote anything.
    var saveError: String?
    /// Set from the account's entitlement — the trial ran out and no licence covers this
    /// version. Never true while signed out, and never guessed from a failed refresh.
    var readOnly = false
    /// Set from the same entitlement: longbook Cloud, by subscription or trial. The hosted
    /// copy, statement reading and shared reports ask this before they ask the server.
    var hasCloud = false
    /// A folder this model is held to — the demo's, written just before it opened. Nil means
    /// the owner's own, found by its bookmark. A held model is a visit, not the book: it
    /// mirrors nothing to the widget, the hosted copy or the account.
    private let pinnedFolder: URL?
    var isDemo: Bool { pinnedFolder != nil }

    init(pinnedFolder: URL? = nil) {
        self.pinnedFolder = pinnedFolder
    }
    /// True when the account existed before this sign-in. Set from the account, never
    /// inferred from the file: an empty iCloud says nothing about who is holding it.
    var returningAccount = false
    /// Set when this device just made a new, empty longbook, so setup opens at its first
    /// card whatever older signals (another device's progress, a sidecar flag) say.
    var madeFreshVault = false
    /// The address signed in right now, mirrored from the account so a load can stamp the
    /// folder with it. Nil while signed out.
    var signedInEmail: String?
    /// Set when the last provisioning adopted a vault instead of making one — the reader
    /// pressed a button that says set up and got the rows they already had.
    var adoptedExistingVault = false
    /// The derived ledger, every row either side of today, dropped whenever the vault reloads.
    private var chargeCache: (day: Date, rows: [ChargeItem])?
    private var reportsCache: (reports: [Report], unreadable: Int)?
    private var insightsCache: [String: Insight]?
    /// Session-only override of the scope; the saved home currency is the default it
    /// overrides.
    var pickedScope: String? {
        didSet { load() }
    }
    /// Which months the expenses, accounts and categories panels answer for, as offsets
    /// from this one — this month alone until others are picked. Session-only, like the
    /// scope: browsing is a look, not a saved preference.
    var selectedMonths = MonthSelection() {
        didSet {
            monthsCountFrom = LB.firstOfMonth(LB.todayMid())
            load()
        }
    }
    /// The month `selectedMonths` counts from: this month as it was when they were set. A
    /// load in another month carries them to the same calendar months.
    private var monthsCountFrom = LB.firstOfMonth(LB.todayMid())
    /// How far the panels browse: twenty years either way, the far edge of any plan.
    static let monthRange: ClosedRange<Int> = -240...240
    /// Whether the 30-day rail is looking behind today. Set only by the reader's own
    /// deliberate pull on the rail.
    var railLooksBack = false {
        didSet { load() }
    }
    /// Bookmarked commitment ids, from the workspace sidecar — a preference of this
    /// machine, never vault data an outside edit could drop.
    private(set) var bookmarks: Set<String> = []
    /// Whether the owner keeps a hosted copy for their AI, from the same sidecar.
    private(set) var hostedPush = false
    /// An outside edit awaiting review: what the file said before, for the diff. The file
    /// is already the truth — review is for undoing, never for approving.
    private(set) var outsideChangeFrom: String?
    /// True between our commit and the reload that records it, so our own write is never
    /// presented back to the owner as an outside change.
    private var expectingOwnChange = false
    /// The newest file hash the owner has seen, app-local — vault data stays facts only.
    /// Keyed by folder, so opening a different vault isn't read as an outside edit.
    private func lastSeenHash(_ folder: URL) -> String? {
        UserDefaults.standard.string(forKey: seenKey(folder))
    }

    private func setLastSeenHash(_ hash: String?, _ folder: URL) {
        UserDefaults.standard.set(hash, forKey: seenKey(folder))
    }

    private func seenKey(_ folder: URL) -> String {
        "longbook.lastSeenHash." + VaultHistory.hash(Data(folder.path.utf8))
    }

    /// Toggled through the sidecar's own write path, so it works even when the trial
    /// has ended and data writes refuse.
    func toggleBookmark(_ id: String) {
        guard let vaultFolder else { return }
        do {
            let workspace = try WorkspaceStore.update(in: vaultFolder) { workspace in
                var list = workspace.bookmarks
                if let at = list.firstIndex(of: id) { list.remove(at: at) } else { list.append(id) }
                workspace.bookmarks = list
            }
            bookmarks = Set(workspace.bookmarks)
        } catch {
            Telemetry.shared.failed(.fileSave, error)
            saveError = error.friendlyDescription
        }
    }

    /// This read is synchronous and coordinated, so running it as a pop begins stalls the
    /// frames the finger is driving. An answered screen refreshes after the transition
    /// instead of during it. Nothing is skipped.
    func loadIfNeeded() {
        guard case .loaded = state else { load(); return }
        guard !refreshQueued else { return }
        refreshQueued = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            refreshQueued = false
            load()
        }
    }

    private var refreshQueued = false

    func load() {
        // Offsets count from this month, so a new one would slide every chosen month along.
        // They are carried to the same calendar months first; setting them reloads, so this
        // pass ends before the flag below is read.
        let thisMonth = LB.firstOfMonth(LB.todayMid())
        if thisMonth != monthsCountFrom {
            let carried = selectedMonths.carried(from: monthsCountFrom, to: thisMonth, within: Self.monthRange)
            monthsCountFrom = thisMonth
            if carried != selectedMonths {
                selectedMonths = carried
                return
            }
        }
        // Cleared here, not in noticeChange: a load that never reaches it — no folder, an
        // unreadable file — would otherwise leave the flag set and adopt the NEXT outside
        // change as ours.
        let wasOurs = expectingOwnChange
        expectingOwnChange = false
        #if DEBUG
        // Development only: the snapshot harness names a first-run state to picture, and no
        // folder is opened for it.
        if !isDemo, let forced = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_VAULT"] {
            switch forced {
            case "returning":
                returningAccount = true
                state = .firstRun(checkedICloud: false)
                return
            case "checked":
                returningAccount = true
                state = .firstRun(checkedICloud: true)
                return
            case "new":
                returningAccount = false
                state = .firstRun(checkedICloud: false)
                return
            case "off":
                state = .unavailable(VaultProvisioner.iCloudOffMessage)
                return
            default:
                break
            }
        }
        #endif
        guard let folder = pinnedFolder ?? VaultSource.resolve() else {
            // Never provisions by itself — only asks. Safe to call from anywhere: a
            // background refresh landing here writes nothing, same as a fresh launch.
            // iCloud's own state decides which question is asked, so a screen already
            // showing that answer waits for the probe rather than blinking back.
            switch state {
            case .unavailable: break
            default: state = .firstRun(checkedICloud: false)
            }
            probeICloudAvailability()
            return
        }
        do {
            // A v1 file upgrades in place, once, behind a history snapshot. The rewrite is
            // longbook's own doing, so it must not stand for review as an outside edit.
            let upgraded = false
            // Taken before the read, not after: a write landing between the two is then seen
            // by the next check instead of hidden behind a newer stamp.
            let stamp = VaultReader.stamp(folder)
            let loaded = try VaultReader.load(from: folder)
            // The version on screen until now, for the usage count of who changed the file.
            let previous = vaultFolder == folder ? loadedFile : nil
            vault = loaded.vault
            vaultFolder = folder
            loadedFile = loaded
            loadedStamp = stamp
            awaitedICloud = false
            // Contract files are longbook's own: an older vault takes the bundle's newer
            // llms.txt, schema and library on open, so no vault keeps a stale curriculum.
            healContract(in: folder)
            chargeCache = nil
            ledgerCache = nil
            reportsCache = nil
            insightsCache = nil
            let home = homeCurrency(in: folder)
            if !isDemo { rememberAccount(in: folder) }
            let workspace = WorkspaceStore.read(in: folder)
            bookmarks = Set(workspace.bookmarks)
            hostedPush = workspace.hostedPush && !isDemo
            adopt(workspace)
            noticeChange(loaded.bytes, raw: loaded.raw, in: folder, ours: wasOurs || upgraded, previous: previous?.raw)
            if let previous, previous.bytes != loaded.bytes {
                countChanges(from: previous.raw, to: loaded.raw, ours: wasOurs || upgraded)
            }
            state = .loaded(derive(loaded.vault, home: home, location: locationWord(folder)))
            if !isDemo {
                WidgetBridge.vaultDidLoad(loaded.bytes, from: folder)
                keepHostedCopyAlive()
            }
            settlePlaceholders(workspace)
            settleHints()
            watchFolder(folder)
        } catch VaultReader.ReadError.notDownloaded where showsVault {
            // A newer version is on its way and a vault is already on screen. Ask for the
            // bytes and keep what is showing, re-drawn from what is in memory so a month or
            // scope picked meanwhile still answers; the watcher re-reads when they land.
            VaultReader.requestDownload(folder.appendingPathComponent(VaultReader.dataFile))
            if let vault {
                state = .loaded(derive(vault, home: homeCurrency(in: folder), location: locationWord(folder)))
            }
        } catch VaultReader.ReadError.notDownloaded where !awaitedICloud {
            // The file is here in name only. Wait for it once rather than telling someone
            // their vault is broken while iCloud is still carrying it over.
            awaitedICloud = true
            waitForICloudThenLoad(folder)
        } catch let error as VaultReader.ReadError {
            if case .notAVault = error { Telemetry.shared.failed(.fileOpen, kind: .parse) } else { Telemetry.shared.failed(.fileOpen, kind: .fileAccess) }
            // The stamp is kept even so: a file that cannot be read is not re-read every tick.
            loadedStamp = VaultReader.stamp(folder)
            state = .failed(error.errorDescription ?? Self.unexplained)
        } catch {
            Telemetry.shared.failed(.fileOpen, error)
            loadedStamp = VaultReader.stamp(folder)
            state = .failed(Self.unexplained)
        }
    }

    private var showsVault: Bool {
        if case .loaded = state { return true }
        return false
    }

    /// A tick's or the watcher's question: is the file on disk the one on screen? Re-read
    /// only when it is not. A copy iCloud has not brought down yet is asked for, not read.
    func reloadIfFileMoved() {
        guard let vaultFolder, fileMoved(in: vaultFolder) else { return }
        Self.log.notice("The vault file changed on disk; re-reading it.")
        load()
    }

    private func fileMoved(in folder: URL) -> Bool {
        let file = folder.appendingPathComponent(VaultReader.dataFile)
        let scoped = folder.startAccessingSecurityScopedResource()
        let waiting = VaultReader.awaitingDownload(file)
        if waiting { VaultReader.requestDownload(file) }
        if scoped { folder.stopAccessingSecurityScopedResource() }
        return !waiting && VaultReader.stamp(folder) != loadedStamp
    }

    /// One watcher per folder, kept across loads: each holds a kqueue and a scoped access
    /// open for its life, so a new one is made only when the folder itself changes.
    private func watchFolder(_ folder: URL) {
        if let watcher, watcher.folder.standardizedFileURL.path == folder.standardizedFileURL.path { return }
        watcher?.stop()
        let fresh = VaultWatcher(folder: folder, insideContainer: VaultWatcher.insideContainer(folder)) { [weak self] in
            self?.reloadIfFileMoved()
        }
        watcher = fresh
        if inForeground { fresh.resume() }
    }

    /// One wait, then whatever the folder says. The flag stops a vault that never arrives
    /// from looping: the second answer is reported, however unwelcome.
    private func waitForICloudThenLoad(_ folder: URL) {
        state = .provisioning("Fetching your longbook from iCloud…")
        Task { [weak self] in
            await Task.detached(priority: .userInitiated) {
                try? await VaultReader.materialize(folder.appendingPathComponent(VaultReader.dataFile))
            }.value
            self?.load()
        }
    }

    /// The reader says a longbook already exists: look again, and WAIT for iCloud this
    /// time — a vault made elsewhere sits here as an undownloaded placeholder, and
    /// reporting "not found" without materializing it would invite a duplicate.
    func checkICloud() {
        state = .provisioning("Looking in your iCloud…")
        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { () async -> URL? in
                guard let folder = VaultSource.resolve() else { return nil }
                try? await VaultReader.materialize(folder.appendingPathComponent(VaultReader.dataFile))
                return folder
            }.value
            guard let self else { return }
            if found != nil {
                self.load()
            } else {
                self.state = .firstRun(checkedICloud: true)
            }
        }
    }

    /// Whose account opened this folder, so another device can say so before anyone signs
    /// in. Added or corrected, never cleared: signed out is when it is needed.
    private func rememberAccount(in folder: URL) {
        guard let email = signedInEmail, !email.isEmpty else { return }
        guard WorkspaceStore.read(in: folder).accountEmail != email else { return }
        try? WorkspaceStore.update(in: folder) { $0.accountEmail = email }
    }

    /// The folder describes itself to any tool that opens it, so its contract has to be the
    /// one this build ships — a vault made by an older release was handing out the old one.
    /// Touches the disk and takes coordination, so it never runs on the main actor.
    private func healContract(in folder: URL) {
        Task.detached(priority: .utility) { VaultContract.heal(in: folder) }
    }

    /// iCloud being off is an answer the reader deserves before they tap anything, not a
    /// failure they have to earn. Probing touches the disk, hence the detached hop; a
    /// result landing after they have moved on is dropped.
    private func probeICloudAvailability() {
        guard !probingICloud else { return }
        probingICloud = true
        Task { [weak self] in
            let off = await Task.detached(priority: .userInitiated) {
                VaultContainer.probe() == .unavailable
            }.value
            guard let self else { return }
            self.probingICloud = false
            switch self.state {
            case .firstRun(checkedICloud: false), .unavailable:
                self.state = off
                    ? .unavailable(VaultProvisioner.iCloudOffMessage)
                    : .firstRun(checkedICloud: false)
            default:
                break
            }
        }
    }

    /// Set once a load has waited for iCloud, so a vault that never lands reports itself
    /// instead of waiting again on every retry.
    private var awaitedICloud = false
    private var probingICloud = false
    private var creatingICloudVault = false

    /// iCloud is off, so the longbook is made beside the app, in its Documents folder,
    /// where `VaultSource` already looks. A vault already there is opened, never replaced.
    func createLocalVault() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("longbook")
        state = .provisioning("Creating your longbook…")
        Task { [weak self] in
            let made = await Task.detached(priority: .userInitiated) { () -> String? in
                if FileManager.default.fileExists(atPath: folder.appendingPathComponent(VaultReader.dataFile).path) { return nil }
                do { try VaultScaffold.create(at: folder, contractFiles: VaultContract.bundledFiles()); return nil }
                catch { return error.localizedDescription }
            }.value
            guard let self else { return }
            if let made { self.state = .failed(made) } else { self.madeFreshVault = true; self.load() }
        }
    }

    /// The reader chose a fresh start. Still adopt-first underneath: another device may
    /// have won the race between their tap and this write.
    func createICloudVault() {
        // The first-run screen asks on its own and the button asks again; one scaffold at a time.
        guard !creatingICloudVault else { return }
        creatingICloudVault = true
        state = .provisioning("Creating your longbook vault…")
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                VaultProvisioner.ensureICloudVault()
            }.value
            guard let self else { return }
            self.creatingICloudVault = false
            switch result {
            case .ready(let folder, let found):
                // The reader asked for a new vault and got the one they already had. Say so
                // while the file comes down, or the old rows arrive with no explanation.
                if found { self.state = .provisioning("Opening the longbook vault we found…") }
                self.adoptedExistingVault = found
                self.madeFreshVault = !found
                try? await VaultReader.materialize(folder.appendingPathComponent(VaultReader.dataFile))
                self.load()
            case .unavailable(let message):
                self.state = .unavailable(message)
            }
        }
    }

    private static let unexplained = "That folder didn’t open. Check it’s still where it was, then try again."

    // MARK: colours

    /// Account colours: the accounts commitments use keep the inks, so a vault with more
    /// accounts than inks never greys out one that is charged.
    static func accountPalette(_ vault: Vault) -> Palette {
        VaultPalette.entities(vault.paymentMethods.map { (id: $0.id, createdAt: $0.createdAt) },
                              inUse: Set(vault.subscriptions.compactMap(\.paymentMethodId)))
    }

    /// Member colours, by the same rule.
    static func memberPalette(_ vault: Vault) -> Palette {
        VaultPalette.entities(vault.familyMembers.map { (id: $0.id, createdAt: $0.createdAt) },
                              inUse: Set(vault.subscriptions.compactMap(\.familyMemberId)))
    }

    // MARK: usage count of who changed the file

    /// Set while a proposal from the hosted server is being read back in, so its rows count
    /// as coming through that door rather than as a change found in the file.
    private var applyingProposal = false

    /// Rows changed between two versions, by who signed each one, sent as counts. This
    /// device's own writes are the app's; the rest are as `_provenance` names them, and a row
    /// nobody signed counts as a direct edit.
    private func countChanges(from old: [String: Any], to new: [String: Any], ours: Bool) {
        guard !isDemo else { return }
        let after = ProvenanceReader.map(in: new)
        let before = ProvenanceReader.map(in: old)
        var rowsBySource: [String: Int] = [:]
        for diff in vaultDiff(from: old, to: new) {
            for id in diff.added.map(\.id) + diff.changed.map(\.id) + diff.removed.map(\.id) {
                let source = ours ? "app" : Telemetry.source(signedBy: (after[id] ?? before[id])?.editedBy)
                rowsBySource[source, default: 0] += 1
            }
        }
        let door = ours ? "app" : applyingProposal ? "hosted" : "file"
        for (source, rows) in rowsBySource {
            Telemetry.shared.changeApplied(source: source, door: door, rows: rows)
        }
    }

    // MARK: history and review

    /// Files every change into history and decides whose it was. Our own writes, the app's
    /// writes from the owner's other device and the very first read pass silently; anything
    /// else stands for review. `previous` is the version on screen before this one.
    private func noticeChange(_ bytes: Data, raw: [String: Any], in folder: URL, ours wasOurs: Bool,
                              previous: [String: Any]? = nil) {
        // The invariant: this device adopts a version, moving `lastSeenHash` to it, when every
        // row touched since its base carries a fresh app signature or review mark, or no row
        // was touched. A review opens, or re-opens, only on a version touching a row with
        // neither: a new outside change.
        let hash = VaultHistory.hash(bytes)
        guard let seen = lastSeenHash(folder) else {
            // A folder this app has never opened is adopted as it stands. The first-run
            // gate adopts the import that opens it the same way, when it opens.
            _ = try? VaultHistory.record(bytes, source: .ours, in: folder)
            setLastSeenHash(hash, folder)
            return
        }
        // Back at the accepted bytes: nothing stands for review any more.
        guard hash != seen else { outsideChangeFrom = nil; return }
        // A version held back while its base came down is still whose it was.
        let ours = wasOurs || awaitedOwnVersion == hash
        // The base is read only when the verdict can use it; one iCloud still holds elsewhere
        // is never waited for here, and only once at all. A verdict still pending counts as
        // an open review, so an own write made meanwhile waits with it.
        var base: [String: Any]?
        var held = VaultHistory.BaseState.missing
        if !ours || outsideChangeFrom != nil || verdictPending {
            let waited = awaitedHistoryBase == seen && historyWaitDone
            if !waited, VaultHistory.awaiting(hash: seen, in: folder) {
                held = .arriving
            } else {
                base = VaultHistory.snapshot(hash: seen, in: folder)
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                held = base == nil ? .missing : .bytes
            }
        }
        let hasOpenReview = outsideChangeFrom != nil || (verdictPending && held != .missing)
        // The app on the other device signed or marked every row it touched — an edit, a
        // delete, a Keep, an Undo — and iCloud delivers that write here with `ours` false.
        // A version that moves no row against the base, bytes or bookkeeping only, is no
        // outside change either.
        let synced = !ours && base.map { OwnEdit.isOwn(from: $0, to: raw) } == true
        let unchanged = base.map { vaultDiff(from: $0, to: raw).isEmpty } == true
        switch VaultHistory.verdict(ours: ours, hasOpenReview: hasOpenReview, base: held, synced: synced, unchanged: unchanged) {
        case .wait:
            // Nothing recorded and nothing moved: the screen shows the file, and the
            // verdict follows once the base lands or the wait gives up.
            awaitedOwnVersion = ours ? hash : nil
            if awaitedHistoryBase != seen {
                awaitedHistoryBase = seen
                historyWaitDone = false
                verdictPending = true
                waitForHistoryBaseThenLoad(seen, folder)
            }
            return
        case .adopt:
            _ = try? VaultHistory.record(bytes, source: .ours, in: folder)
            outsideChangeFrom = nil
            setLastSeenHash(hash, folder)
        case .review:
            // Inside a review the base stays what the owner last accepted, so a row edited
            // or dropped there does not keep the rest of it across a relaunch. The other
            // device's Keep or Undo closes the review here as it did there.
            _ = try? VaultHistory.record(bytes, source: ours ? .ours : .outside, in: folder)
            if outsideChangeFrom == nil {
                outsideChangeFrom = seen
            } else if let previous, ours || OwnEdit.isOwn(from: previous, to: raw) {
                // The owner's own write, here or on the other device, made while the review
                // was open: it applies directly, so it moves the base instead of joining it.
                carryOwnChange(from: previous, to: raw, bytes: bytes, in: folder)
            }
        }
        awaitedOwnVersion = nil
        verdictPending = false
        // Never while a review is open: pruning could delete the very snapshot the owner
        // is about to compare against or restore.
        if outsideChangeFrom == nil { VaultHistory.prune(in: folder) }
    }

    /// Moves the open review's base by what the owner's own write changed, kept on this
    /// device only. A review the write leaves with nothing in it closes. Left as it was
    /// when the base cannot be read or kept.
    private func carryOwnChange(from previous: [String: Any], to raw: [String: Any], bytes: Data, in folder: URL) {
        guard let from = outsideChangeFrom,
              let baseBytes = VaultHistory.snapshot(hash: from, in: folder),
              let base = try? JSONSerialization.jsonObject(with: baseBytes) as? [String: Any]
        else { return }
        let moved = ReviewBase.carry(from: previous, to: raw, onto: base)
        if vaultDiff(from: moved, to: raw).isEmpty {
            outsideChangeFrom = nil
            setLastSeenHash(VaultHistory.hash(bytes), folder)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: moved, options: [.sortedKeys]),
              let hash = VaultHistory.keepUnlogged(data, in: folder)
        else { return }
        outsideChangeFrom = hash
        setLastSeenHash(hash, folder)
    }

    /// The base hash one reload has already waited for, so a version iCloud never delivers
    /// is adopted on the next pass rather than waited for again.
    private var awaitedHistoryBase: String?
    /// Whether that wait has run its course; until then the base still counts as arriving.
    private var historyWaitDone = false
    /// A verdict held back for its base: every reload until it lands waits with it.
    private var verdictPending = false
    /// The file hash whose own write was held back for its base, so the reload that
    /// follows still records it as ours.
    private var awaitedOwnVersion: String?

    /// One wait for a base iCloud still holds elsewhere, off the main actor, then a reload
    /// that reads it — or, if it never lands, adopts without it. Nothing on screen waits.
    private func waitForHistoryBaseThenLoad(_ seen: String, _ folder: URL) {
        Task { [weak self] in
            await Task.detached(priority: .utility) {
                try? await VaultHistory.materialize(hash: seen, in: folder)
            }.value
            self?.historyWaitDone = true
            self?.load()
        }
    }

    /// The refusal when Keep, Undo or Restore needs a version iCloud still holds elsewhere.
    private static let versionArriving =
        "That version is still coming down from iCloud. Give it a moment on Wi-Fi, then try again."

    /// How many commitments the folder holds — what the first-run gate waits on, and all
    /// it needs to know about the vault.
    var commitmentCount: Int { vault?.subscriptions.count ?? 0 }

    /// Every commitment by id, name and rhythm — what a statement's lines are matched against.
    var commitmentIdNames: [(id: String, name: String, cycle: BillingCycle)] {
        (vault?.subscriptions ?? []).map { ($0.id, $0.name, $0.billingCycle) }
    }

    /// How many versions history holds — the Data & privacy screen's honest number.
    func historyCount() -> Int {
        vaultFolder.map { VaultHistory.entries(in: $0).count } ?? 0
    }

    /// The outside edit, row by row — what changed between the last state the owner saw
    /// and the file as it stands.
    func reviewDiff() -> [EntityDiff] {
        guard let vaultFolder, let from = outsideChangeFrom,
              let oldBytes = VaultHistory.snapshot(hash: from, in: vaultFolder),
              let old = try? JSONSerialization.jsonObject(with: oldBytes) as? [String: Any],
              let current = loadedFile?.raw
        else { return [] }
        return vaultDiff(from: old, to: current)
    }

    /// Keeping is adopting: the file was already the truth, the owner has now seen it. The
    /// kept rows take a review mark first, so the other device adopts the change too; a
    /// refused mark (a lapsed trial, a second conflict) still keeps it here. Refused while
    /// the base arrives.
    @discardableResult
    func keepOutsideChange() -> Bool {
        guard let vaultFolder else { return false }
        if let from = outsideChangeFrom, VaultHistory.awaiting(hash: from, in: vaultFolder) {
            saveError = Self.versionArriving
            return false
        }
        if !readOnly, outsideChangeFrom != nil, !markKept() {
            // The other device wrote first: take its write, then try once more.
            load()
            if outsideChangeFrom != nil { _ = markKept() }
        }
        guard let loadedFile else { return false }
        setLastSeenHash(VaultHistory.hash(loadedFile.bytes), vaultFolder)
        outsideChangeFrom = nil
        refreshHostedCopy()
        return true
    }

    /// Writes the review mark on every row under review, while the review is still open so
    /// the reload records it as ours and leaves the base alone. False only on a conflict;
    /// any other refusal, or nothing to mark, reads as done and the local Keep stands.
    private func markKept() -> Bool {
        let ids = reviewDiff().filter { $0.kind != "tags" }
            .flatMap { $0.added.map(\.id) + $0.changed.map(\.id) + $0.removed.map(\.id) }
        guard !ids.isEmpty else { return true }
        if commit({ VaultPatch.markReviewed(ids: ids, in: $0, now: Date()) }) { return true }
        return saveError != WriteError.conflict.friendlyDescription
    }

    /// Revert writes the old snapshot as a NEW change through the same gate as every
    /// write — compare-and-swap, read-only check, then a reload that records it as ours.
    /// Every row it puts back is signed as the app's, so the other device adopts the undo.
    @discardableResult
    func revertOutsideChange() -> Bool {
        guard let vaultFolder, let from = outsideChangeFrom else { return false }
        if VaultHistory.awaiting(hash: from, in: vaultFolder) {
            saveError = Self.versionArriving
            return false
        }
        guard let oldBytes = VaultHistory.snapshot(hash: from, in: vaultFolder),
              let old = try? JSONSerialization.jsonObject(with: oldBytes) as? [String: Any]
        else { return false }
        let done = commit { VaultPatch.signRestore(from: $0, to: old, now: Date()) }
        if done {
            outsideChangeFrom = nil
            // The write above ran inside the review; what it left is now the accepted state.
            if let loadedFile { setLastSeenHash(VaultHistory.hash(loadedFile.bytes), vaultFolder) }
        }
        return done
    }

    /// Every kept version, newest first — the list the Changes screen walks.
    func changeLog() -> [HistoryEntry] {
        vaultFolder.map { VaultHistory.entries(in: $0) } ?? []
    }

    /// What one version changed against the one before it. The oldest entry has no
    /// parent and answers nil: it is the first version, not a change.
    func diff(for entry: HistoryEntry) -> [EntityDiff]? {
        guard let vaultFolder else { return nil }
        let log = VaultHistory.entries(in: vaultFolder)
        guard let index = log.firstIndex(where: { $0.hash == entry.hash }), index + 1 < log.count,
              let newBytes = VaultHistory.snapshot(hash: entry.hash, in: vaultFolder),
              let oldBytes = VaultHistory.snapshot(hash: log[index + 1].hash, in: vaultFolder),
              let new = try? JSONSerialization.jsonObject(with: newBytes) as? [String: Any],
              let old = try? JSONSerialization.jsonObject(with: oldBytes) as? [String: Any]
        else { return nil }
        return vaultDiff(from: old, to: new)
    }

    /// Who signed each row in that version — the _provenance names, for attribution.
    func writers(for entry: HistoryEntry) -> [String: String] {
        guard let vaultFolder,
              let bytes = VaultHistory.snapshot(hash: entry.hash, in: vaultFolder),
              let raw = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let provenance = raw["_provenance"] as? [String: Any]
        else { return [:] }
        return provenance.compactMapValues { ($0 as? [String: Any])?["edited_by"] as? String }
    }

    /// The one outside hand that signed every row under review; nil when none or several
    /// did. A charge is signed through its commitment, so "id@day" falls back to the id.
    func reviewWriter(_ diff: [EntityDiff]) -> String? {
        guard let newest = changeLog().first else { return nil }
        let signed = writers(for: newest)
        let ids = diff.flatMap { $0.added.map(\.id) + $0.removed.map(\.id) + $0.changed.map(\.id) }
        let names = Set(ids.compactMap { id in
            signed[id] ?? signed[String(id.split(separator: "@", maxSplits: 1).first ?? Substring(id))]
        }).filter { !$0.lowercased().hasPrefix("longbook") }
        return names.count == 1 ? names.first : nil
    }

    /// Restoring writes the chosen version back as a NEW change through the same gate
    /// as every write — history only ever moves forward, never rewinds. The rows it
    /// changes are signed as the app's, so the other device adopts the restore.
    @discardableResult
    func restore(hash: String) -> Bool {
        guard let vaultFolder else { return false }
        if VaultHistory.awaiting(hash: hash, in: vaultFolder) {
            saveError = Self.versionArriving
            return false
        }
        guard let bytes = VaultHistory.snapshot(hash: hash, in: vaultFolder),
              let old = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else { return false }
        return commit { VaultPatch.signRestore(from: $0, to: old, now: Date()) }
    }

    /// Whether a version's story is out of reach for now: its snapshot, or the parent's it
    /// is read against, is one iCloud still holds elsewhere. Pruned away reads false.
    func isArriving(_ entry: HistoryEntry) -> Bool {
        guard let vaultFolder else { return false }
        if VaultHistory.awaiting(hash: entry.hash, in: vaultFolder) { return true }
        let log = VaultHistory.entries(in: vaultFolder)
        guard let index = log.firstIndex(where: { $0.hash == entry.hash }), index + 1 < log.count else { return false }
        return VaultHistory.awaiting(hash: log[index + 1].hash, in: vaultFolder)
    }

    /// Which kept versions moved a row against the one before them, by hash. Filled off the
    /// main actor as the History list asks; a version's parent never changes, so a verdict holds.
    private var rowsMovedByHash: [String: Bool] = [:]

    /// The versions already judged bookkeeping-only, without reading anything.
    func knownBookkeepingVersions() -> Set<String> {
        Set(rowsMovedByHash.filter { !$0.value }.keys)
    }

    /// The versions the History list leaves out: each whose rows equal its parent's —
    /// bookkeeping only, a Keep's review marks above all. They stay in the log. Snapshots
    /// are read and compared off the main actor, once each, and only when not yet judged.
    func bookkeepingOnlyVersions() async -> Set<String> {
        guard let vaultFolder else { return [] }
        let known = rowsMovedByHash
        let judged = await Task.detached(priority: .userInitiated) {
            Self.judgeRows(in: vaultFolder, known: known)
        }.value
        rowsMovedByHash.merge(judged) { _, new in new }
        return Set(rowsMovedByHash.filter { !$0.value }.keys)
    }

    /// Walks the log oldest to newest holding one parent at a time: true when a version's
    /// rows differ from its parent's. The first version, and one whose snapshot or parent's
    /// is gone, count as moved so the list still shows them. One still arriving is judged
    /// once it lands.
    private nonisolated static func judgeRows(in folder: URL, known: [String: Bool]) -> [String: Bool] {
        func parse(_ hash: String) -> [String: Any]? {
            VaultHistory.snapshot(hash: hash, in: folder)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        var out: [String: Bool] = [:]
        var parent: (hash: String, raw: [String: Any]?, parsed: Bool)?
        for entry in VaultHistory.entries(in: folder).reversed() {
            var raw: [String: Any]?
            var parsed = false
            if known[entry.hash] == nil {
                if var above = parent {
                    if !above.parsed { above.raw = parse(above.hash); above.parsed = true }
                    raw = parse(entry.hash)
                    parsed = true
                    if let old = above.raw, let new = raw {
                        out[entry.hash] = !vaultDiff(from: old, to: new).isEmpty
                    } else if !VaultHistory.awaiting(hash: entry.hash, in: folder),
                              !VaultHistory.awaiting(hash: above.hash, in: folder) {
                        out[entry.hash] = true
                    }
                } else {
                    out[entry.hash] = true
                }
            }
            parent = (entry.hash, raw, parsed)
        }
        return out
    }

    /// The quick selector's own two lists. Neither is a fact about money — one adds a code
    /// to the picker, the other puts one away — which is why both live beside the vault
    /// rather than in it. Read with the vault: the form asks for these on every keystroke.
    private(set) var customCurrencies: [String] = []
    private(set) var hiddenCurrencies: [String] = []

    /// Puts a code on the quick selector.
    @discardableResult
    func keepCurrency(_ code: String) -> Bool {
        guard let vaultFolder, code.count == 3 else { return false }
        guard let workspace = try? WorkspaceStore.update(in: vaultFolder, {
            $0.customCurrencies = $0.customCurrencies + [code]
            $0.hiddenCurrencies = $0.hiddenCurrencies.filter { $0 != code }
        }) else { return false }
        adopt(workspace)
        return true
    }

    /// Takes a code off the quick selector — and only off it. Refused while a commitment
    /// counts in it, because that code is listed from the vault regardless: putting it
    /// away would be a button that does nothing.
    @discardableResult
    func forgetCurrency(_ code: String) -> Bool {
        guard let vaultFolder, currencyIsRemovable(code) else { return false }
        guard let workspace = try? WorkspaceStore.update(in: vaultFolder, {
            $0.customCurrencies = $0.customCurrencies.filter { $0 != code }
            $0.hiddenCurrencies = $0.hiddenCurrencies + [code]
        }) else { return false }
        adopt(workspace)
        return true
    }

    /// A code no commitment counts. Nothing else can leave the selector, because nothing
    /// else is only a selector entry.
    func currencyIsRemovable(_ code: String) -> Bool {
        commitmentsIn(currency: code).isEmpty
    }

    private func adopt(_ workspace: Workspace) {
        customCurrencies = workspace.customCurrencies
        hiddenCurrencies = workspace.hiddenCurrencies
        openTripId = workspace.openTrip
    }

    /// The commitments a code actually counts.
    func commitmentsIn(currency code: String) -> [Subscription] {
        (vault?.subscriptions ?? []).filter { $0.currency == code }
    }

    /// The workspace sidecar remembers the owner's home currency.
    private func homeCurrency(in folder: URL) -> String? {
        WorkspaceStore.read(in: folder).homeCurrency
    }

    /// What the sidecar holds today, for the screen that edits it.
    var homeCurrency: String? {
        vaultFolder.flatMap { WorkspaceStore.read(in: $0).homeCurrency }
    }

    /// Saved beside the vault, not in it — and on its own write path, so it still saves when
    /// the trial has ended and data writes are refused.
    @discardableResult
    func setHomeCurrency(_ code: String?) -> Bool {
        guard let vaultFolder else { return false }
        do {
            try WorkspaceStore.update(in: vaultFolder) { $0.homeCurrency = code }
            pickedScope = nil
            return true
        } catch {
            Telemetry.shared.failed(.fileSave, error)
            saveError = error.friendlyDescription
            return false
        }
    }

    /// The backup is the file itself, byte for byte as it was read — never a re-serialisation
    /// of the part this build happens to understand.
    func exportBackup() -> URL? {
        guard let loadedFile else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("longbook-backup-\(LB.toISO(Date())).json")
        do {
            try loadedFile.bytes.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Where the vault lives, in the reader's words.
    private func locationWord(_ folder: URL) -> String {
        folder.path.contains("Mobile Documents") ? "in iCloud Drive" : "on this device"
    }

    /// Scope choices: currencies with at least one live recurring commitment, busiest
    /// first — one large foreign charge shouldn't outrank where everything lives.
    private func scopeChoices(_ vault: Vault, _ today: Date) -> [String] {
        var counts: [String: Int] = [:]
        for sub in vault.subscriptions
        where isSpending(sub) && isEffectivelyActive(sub, today) && sub.billingCycle != .once {
            counts[sub.currency, default: 0] += 1
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// With nothing picked or chosen: the busiest recurring currency, which Settings names
    /// when it is the only one, else a live commitment's, else the one most charges are in.
    /// INR only for a folder holding no charge at all.
    private func fallbackCurrency(_ vault: Vault, choices: [String], _ today: Date) -> String {
        if let busiest = choices.first { return busiest }
        if let live = vault.subscriptions.first(where: { isSpending($0) && isEffectivelyActive($0, today) }) {
            return live.currency
        }
        var counts: [String: Int] = [:]
        for charge in allCharges(vault, today) { counts[charge.currency, default: 0] += 1 }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? "INR"
    }

    /// The currency a figure without one of its own is drawn in, a report or an account's
    /// balance: the home currency when one is chosen, else the fallback above.
    private func figureCurrency(_ vault: Vault, _ today: Date = LB.todayMid()) -> String {
        homeCurrency ?? fallbackCurrency(vault, choices: scopeChoices(vault, today), today)
    }

    private func derive(_ vault: Vault, home: String?, location: String) -> DashboardData {
        let today = LB.todayMid()
        let active = vault.subscriptions.filter { isSpending($0) && isEffectivelyActive($0, today) }
        // What is counted as a commitment is what still lies ahead; a one-time line whose
        // charge is behind today is that charge, and its money still counts in the month.
        let live = liveCommitments(vault, today)

        let choices = scopeChoices(vault, today)
        let scope = [pickedScope, home].compactMap { $0 }.first(where: { choices.contains($0) })
            ?? fallbackCurrency(vault, choices: choices, today)

        let methodPalette = Self.accountPalette(vault)
        let memberPalette = Self.memberPalette(vault)
        let windows = selectedMonths.windows(anchor: LB.firstOfMonth(today))
        let summary = month(vault, selection: selectedMonths, scope: scope, today: today)
        // The slices read every spending commitment, whatever its status, as the total does:
        // a cancelled one's charges in the months are in all three cards or in none.
        let spending = vault.subscriptions.filter(isSpending)

        return DashboardData(
            nextDay: nextDueDay(vault, today),
            activeCount: live.count,
            rail: rail(vault, today: today),
            month: summary,
            methods: methodSlices(vault, spending: spending, windows: windows, scope: scope),
            accountsMonthName: summary.name,
            currencyCount: Set(active.map(\.currency)).count,
            categories: categorySlices(spending, windows: windows, scope: scope),
            scope: scope,
            scopeChoices: choices,
            sidebarMethods: vault.paymentMethods.map { method in
                DashboardData.SidebarEntity(
                    id: method.id, name: method.name,
                    count: live.filter { $0.paymentMethodId == method.id }.count,
                    ink: methodPalette.rank(method.id), starred: method.isStarred
                )
            },
            sidebarMembers: vault.familyMembers.map { member in
                DashboardData.SidebarEntity(
                    id: member.id, name: member.name,
                    count: live.filter { $0.familyMemberId == member.id }.count,
                    ink: memberPalette.rank(member.id), starred: member.isStarred
                )
            },
            vaultLocation: location,
            commitments: commitmentItems(vault, today: today),
            // Every commitment's, as the form offers them: a slice or a tile may name a paused or
            // cancelled one's category, and the list's chip must name what it filtered by.
            commitmentCategories: Array(Set(vault.subscriptions.compactMap { trimmedCategory($0) })).sorted()
        )
    }

    /// A one-time line whose charge is behind today or paid is that charge, and belongs on
    /// no commitments screen or count. Paused and cancelled rows are still commitments.
    private func isSettledCharge(_ sub: Subscription, in vault: Vault, _ today: Date) -> Bool {
        isEffectivelyActive(sub, today) && !isLiveCommitment(sub, in: vault, today)
    }

    private func trimmedCategory(_ sub: Subscription) -> String? {
        let name = sub.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// How a row says it moves money between the owner's own accounts: listed where it
    /// falls, as money in is, and never summed.
    static let transferFact = LBMetaFact(symbol: LBGlyph.transfer, text: "Transfer")

    /// What an empty link slot says, under the glyph the filled one wears. The row's own
    /// tap reaches Edit, the one door to filling it.
    static let addCategoryFact = LBMetaFact(symbol: LBGlyph.category, text: "Add category", placeholder: true)
    static let addMemberFact = LBMetaFact(symbol: LBGlyph.member, text: "Add person", placeholder: true)
    static let addAccountFact = LBMetaFact(symbol: LBGlyph.account, text: "Add account", placeholder: true)

    /// Category, member and account as every list and card wears them, a placeholder in
    /// each empty slot. Only a spend row is asked for a category: a transfer or money in
    /// names one when it has one.
    static func linkFacts(category: String?, member: String?, method: String?, spend: Bool) -> [LBMetaFact] {
        [
            category.map { LBMetaFact(symbol: LBGlyph.category, text: categoryWord($0)) } ?? (spend ? addCategoryFact : nil),
            member.map { LBMetaFact(symbol: LBGlyph.member, text: $0) } ?? addMemberFact,
            method.map { LBMetaFact(symbol: LBGlyph.account, text: $0) } ?? addAccountFact,
        ].compactMap { $0 }
    }

    /// The same strip for one loaded row, its names resolved against the vault.
    func linkFacts(_ sub: Subscription) -> [LBMetaFact] {
        let names = entityNames(memberId: sub.familyMemberId, methodId: sub.paymentMethodId)
        return Self.linkFacts(category: trimmedCategory(sub), member: names.member, method: names.method,
                              spend: !sub.isIncome && !sub.isTransfer)
    }

    /// The whole vault, each row exactly once: the scheduled ones soonest-due first
    /// under month headings, then everything not billing — derived by subtraction from
    /// `activeUpcoming`, so the two buckets can never disagree about a row.
    private func commitmentItems(_ vault: Vault, today: Date) -> [DashboardData.CommitmentItem] {
        let palette = VaultPalette.categories(vault.subscriptions)
        let members = Dictionary(vault.familyMembers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let methods = Dictionary(vault.paymentMethods.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        func item(_ sub: Subscription, due: DueMeta?) -> DashboardData.CommitmentItem {
            let category = trimmedCategory(sub)
            let member = sub.familyMemberId.flatMap { members[$0] }
            let method = sub.paymentMethodId.flatMap { methods[$0] }
            let paid = due?.paid ?? false
            // The row's own words answer a mark-paid tap — the pill alone flipping read
            // as the row not reacting. The cycle is a details-screen fact.
            let facts: [LBMetaFact] = [
                due.map { LBMetaFact(symbol: LBGlyph.date, text: LB.dayWord($0.days)) },
                sub.isTransfer ? Self.transferFact : nil,
            ].compactMap { $0 }
                + Self.linkFacts(category: category, member: member, method: method,
                                 spend: !sub.isIncome && !sub.isTransfer)
                + (paid ? [LBMetaFact(symbol: LBGlyph.paid, text: "Paid")] : [])
            let mark = badge(sub, in: vault, today)
            let search = Self.searchWords(sub, category: category, member: member, method: method, badge: mark,
                                          status: displayStatus(sub, today), more: [paid ? "paid" : nil])
            let through = LongbookCore.plannedThrough(sub, in: vault)
            return DashboardData.CommitmentItem(
                id: sub.id,
                name: sub.name,
                amountText: fmtMoney(due?.charge.amount ?? sub.amount, due?.charge.currency ?? sub.currency),
                facts: facts,
                searchText: search,
                category: category,
                ink: category.flatMap { palette.rank($0) },
                badge: mark,
                monthLabel: due.map { LB.monthYear($0.date).lowercased() },
                dueISO: due.map { LB.toISO($0.date) },
                isPaid: paid,
                methodId: sub.paymentMethodId,
                memberId: sub.familyMemberId,
                plannedThrough: through.map { settledWord($0) },
                isRecurring: sub.billingCycle != .once,
                cycle: sub.billingCycle,
                status: displayStatus(sub, today),
                currency: due?.charge.currency ?? sub.currency
            )
        }

        let upcoming = nextCharges(vault, today)
        let scheduled = Set(upcoming.map(\.sub.id))
        // A one-time line whose charge is behind today is that charge — it lives in the
        // past ledger, not down here. Locale collation, as the archived list sorted —
        // codepoint order files "iCloud" after "Zoom".
        let rest = vault.subscriptions
            .filter { !scheduled.contains($0.id) && !isSettledCharge($0, in: vault, today) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return upcoming.map { item($0.sub, due: $0) } + rest.map { item($0, due: nil) }
    }

    /// A trial first: a decision beats a state. Then a scheduled-but-not-lapsed cancel on a
    /// live row reads cancelling.
    private func badge(_ sub: Subscription, in vault: Vault, _ today: Date) -> DashboardData.CommitmentItem.Badge? {
        if LongbookCore.isFreeTrial(sub) { return .trial }
        let status = displayStatus(sub, today)
        if status == .active, cancelInfo(sub, today).date != nil { return .cancelling }
        if status == .paused { return .paused }
        if status == .cancelled { return .cancelled }
        return nil
    }

    /// "12 Jul 2025" — a settled date keeps its year; "12 Jul" two years later would
    /// read as upcoming. One formatter, not one per row — the ledger has hundreds.
    private static let settledFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = LB.calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("d MMM y")
        return formatter
    }()

    private func settledWord(_ date: Date) -> String {
        Self.settledFormatter.string(from: date)
    }

    private func rail(_ vault: Vault, today: Date) -> DashboardData.Rail {
        // Counted, not dated: the next 30 charges ahead of today, or the 30 that landed
        // last. A past charge is a row exactly as a future one is.
        let back = railLooksBack
        // A transfer rides the timeline beside the spending, flagged on its card; on a
        // shared day the spending stands first, each in its stored order.
        let all = (allCharges(vault, today) + transferCharges(vault, today)).enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset }
            .map(\.element)
        let charges = back
            ? Array(all.filter { $0.date < today }.suffix(30))
            : Array(all.filter { $0.date >= today }.prefix(30))
        let from = charges.first?.date ?? today
        let to = charges.last?.date ?? today
        let span = max(LB.daysBetween(from, to), 1)
        var perDay: [Int: Int] = [:]
        for charge in charges {
            perDay[LB.daysBetween(from, charge.date), default: 0] += 1
        }
        let dots = perDay.sorted { $0.key < $1.key }.map { day, count in
            (fraction: Double(day) / Double(span), heavy: count > 1)
        }
        // Chronological either way, so the cards, the strip and the edge labels agree:
        // the left edge is the older end.
        let transfers = charges.filter { $0.sub.isTransfer }.count
        // Ahead, the note names commitments, so a monthly one planned two years out is one, not 24.
        let ahead = Set(charges.filter { !$0.sub.isTransfer }.map(\.sub.id)).count
        return DashboardData.Rail(
            charges: charges, upcomingCount: back ? charges.count - transfers : ahead, transferCount: transfers,
            dots: dots, looksBack: back, from: from, to: to
        )
    }

    /// Whole calendar months, elapsed charges included — a forward-only read would shrink
    /// a month as it passes. Several months read as one window: a charge in any of them
    /// counts. Paid marks don't move money; they never touch this.
    private func month(_ vault: Vault, selection: MonthSelection, scope: String, today: Date) -> DashboardData.Month {
        let anchor = LB.firstOfMonth(today)
        let windows = selection.windows(anchor: anchor)
        let span = selection.span(anchor: anchor)

        var total = 0.0
        var others: [String: Double] = [:]
        var remaining = 0.0
        var remainingDate: Date?

        let monthCharges = chargesInRange(vault, from: span.first, to: span.last)
            .filter { Self.falls($0.date, in: windows) }
        for charge in monthCharges {
            if charge.currency == scope {
                total += charge.amount
                if charge.date >= today {
                    remaining += charge.amount
                    if remainingDate == nil || charge.date < remainingDate! { remainingDate = charge.date }
                }
            } else {
                others[charge.currency, default: 0] += charge.amount
            }
        }

        let income = incomeCharges(vault, today)
            .filter { $0.currency == scope && Self.falls($0.date, in: windows) }
            .reduce(0) { $0 + $1.amount }
        // One month is drawn a bar a day; several, a bar for each day that holds a charge.
        let bars = expenseBars(monthCharges, selection: selection, anchor: anchor, scope: scope, today: today)
        let edges: (first: String, last: String) = windows.count == 1
            ? (first: LB.shortDate(span.first), last: LB.shortDate(span.last))
            : selection.edgeLabels(anchor: anchor)
        return DashboardData.Month(
            name: selection.label(anchor: anchor),
            total: total,
            otherTotals: others.map { CurrencyAmount(currency: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount },
            chargeCount: monthCharges.count,
            remaining: remaining,
            remainingDate: remainingDate,
            bars: bars,
            edges: edges,
            firstDays: windows.map { $0.first },
            expenses: monthCharges,
            holdsThisMonth: selection.contains(0),
            income: income
        )
    }

    /// Whether a day falls inside any of the windows — the months a card joins into one.
    private static func falls(_ date: Date, in windows: [(first: Date, last: Date)]) -> Bool {
        windows.contains { date >= $0.first && date <= $0.last }
    }

    // MARK: commitments named at setup

    /// What setup was told and the form has not yet made real, in the vault itself so
    /// every door sees what is waiting.
    var placeholders: [CommitmentPlaceholder] {
        vault?.toFillIn ?? []
    }

    var commitmentsAsked: Bool {
        vaultFolder.map { WorkspaceStore.read(in: $0).commitmentsAsked } ?? true
    }

    @discardableResult
    func setPlaceholders(_ placeholders: [CommitmentPlaceholder]) -> Bool {
        commit { VaultPatch.setToFillIn(placeholders, in: $0) }
    }

    /// The sidecar's list, from before the vault carried one, moved in once; and any
    /// name the book now holds as a commitment leaves the list.
    private func settlePlaceholders(_ workspace: Workspace) {
        if vault?.toFillIn == nil, !workspace.placeholders.isEmpty, let vaultFolder {
            let carried = workspace.placeholders
            _ = try? WorkspaceStore.update(in: vaultFolder) { $0.placeholders = [] }
            setPlaceholders(carried)
            return
        }
        let waiting = placeholders
        let left = waiting.filter { !hasCommitment(named: $0.name) }
        if left.count != waiting.count { setPlaceholders(left) }
    }

    func markCommitmentsAsked() {
        guard let vaultFolder else { return }
        _ = try? WorkspaceStore.update(in: vaultFolder) { $0.commitmentsAsked = true }
    }

    // MARK: people and accounts kept as hints

    /// The people and accounts setup picked, kept for reading statements and never listed
    /// on People or Accounts.
    var hints: [SetupHint] { vault?.hints ?? [] }

    /// One kind's hints replaced by these names; a name the book already holds as a real
    /// person or account is not a hint, and the other kind's are left alone.
    @discardableResult
    func setHints(_ kind: SetupHint.Kind, _ picked: [(name: String, tag: String?)]) -> Bool {
        let held = Set((kind == .member ? memberNames : accountNames).map { $0.lowercased() })
        let kept = hints.filter { $0.kind == kind }
        var next = hints.filter { $0.kind != kind }
        var seen = Set<String>()
        for pick in picked {
            let key = pick.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, !held.contains(key), seen.insert(key).inserted else { continue }
            // A hint picked again keeps its id.
            next.append(kept.first { $0.name.lowercased() == key }
                ?? SetupHint(name: pick.name.trimmingCharacters(in: .whitespaces), kind: kind, tag: pick.tag))
        }
        guard next != hints else { return true }
        return commit { VaultPatch.setHints(next, in: $0) }
    }

    /// A hint the book now holds by name, as a person or an account, has done its work.
    private func settleHints() {
        let waiting = hints
        guard !waiting.isEmpty, !readOnly else { return }
        let people = Set(memberNames.map { $0.lowercased() })
        let accounts = Set(accountNames.map { $0.lowercased() })
        let left = waiting.filter { !($0.kind == .member ? people : accounts).contains($0.name.lowercased()) }
        if left.count != waiting.count { commit { VaultPatch.setHints(left, in: $0) } }
    }

    // MARK: the first run

    /// Where the first run stands for this vault, from the sidecar; nil before it began.
    var onboardingStage: OnboardingStage? {
        vaultFolder.flatMap { WorkspaceStore.read(in: $0).onboardingStage }.flatMap(OnboardingStage.init(raw:))
    }

    /// Writes the stage to the sidecar, then to the account so another device can resume.
    func setOnboardingStage(_ stage: OnboardingStage) {
        guard let vaultFolder else { return }
        let device = OnboardingDevice.id
        _ = try? WorkspaceStore.update(in: vaultFolder) { $0.onboardingStage = stage.raw; $0.onboardingDevice = device }
        Task { await OnboardingSync.push(stage: stage.raw, device: device) }
    }

    /// Every charge the book holds, past and planned.
    var chargeCount: Int { vault?.charges.count ?? 0 }

    /// Whether the book holds enough to be shown as one. The least it needs is longbook's
    /// rule, never a list the reader is shown.
    var dashboardAllowed: Bool {
        // App Review signs in on a fresh device with no statement to give, so its book opens as it is.
        if let signedInEmail, isReviewAccount(signedInEmail) { return true }
        return OnboardingCards.dashboardAllowed(commitments: commitmentCount + placeholders.count, charges: chargeCount,
                                                accounts: accountNames.count + hints.filter { $0.kind == .account }.count,
                                                members: memberNames.count)
    }

    /// A person by role, once: the role is the name and the tag until the owner renames them.
    func ensureMember(_ name: String, role: String) {
        guard !memberNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
              let id = addEntity(.familyMember, named: name) else { return }
        setEntityDetails(.familyMember, id: id, memberTag: .some(role))
    }

    /// A placeholder the form has made real, or one the reader let go.
    func removePlaceholder(_ id: String) {
        setPlaceholders(placeholders.filter { $0.id != id })
    }

    /// Whether a commitment by this name is in the book — how a placeholder knows it is done.
    /// Whether the book holds a recurring commitment by this name. A one-time row — a
    /// statement's line, say — is not one: a name set up or ticked still waits on it.
    func hasCommitment(named name: String) -> Bool {
        vault?.subscriptions.contains { $0.billingCycle != .once && $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? false
    }

    /// The months that hold at least one charge, as offsets from this month, so a picker
    /// can draw the empty ones fainter.
    var monthsWithCharges: Set<Int> {
        guard let vault else { return [] }
        let anchor = LB.firstOfMonth(LB.todayMid())
        var out = Set<Int>()
        for charge in vault.charges {
            guard let date = LB.parseDate(charge.date),
                  let months = LB.calendar.dateComponents([.month], from: anchor, to: LB.firstOfMonth(date)).month
            else { continue }
            out.insert(months)
        }
        return out
    }

    /// The id the unassigned bucket wears. No payment method carries it, so a filter
    /// reading it means "nothing assigned" rather than "an account by this name".
    static let unassignedMethodId = "no-account"
    /// The same for the person bucket: "No person".
    static let unassignedMemberId = "no-member"

    /// The chosen months' spend per payment account — the months the panels show. One row
    /// per account the vault holds, plus an unassigned bucket; an account whose money is
    /// all in another currency is present, never blended.
    private func methodSlices(
        _ vault: Vault, spending: [Subscription], windows: [(first: Date, last: Date)], scope: String
    ) -> [DashboardData.Slice] {
        let palette = Self.accountPalette(vault)

        var groups: [(id: String, name: String, ink: Int?, subs: [Subscription])] =
            vault.paymentMethods.map { method in
                (method.id, method.name, palette.rank(method.id),
                 spending.filter { $0.paymentMethodId == method.id })
            }
        groups.append((Self.unassignedMethodId, "No account", nil, spending.filter { $0.paymentMethodId == nil }))

        return slices(groups, windows: windows, scope: scope)
    }

    /// The same months by category — the owner's free text, exactly as typed. Colour
    /// ranks normalise the name; grouping never does.
    private func categorySlices(
        _ spending: [Subscription], windows: [(first: Date, last: Date)], scope: String
    ) -> [DashboardData.Slice] {
        let palette = VaultPalette.categories(spending)

        var byName: [String: [Subscription]] = [:]
        var order: [String] = []
        for sub in spending {
            let name = sub.tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = name.isEmpty ? "No category" : name
            if byName[key] == nil { order.append(key) }
            byName[key, default: []].append(sub)
        }
        let groups = order.map { name in
            (id: name, name: name,
             ink: name == "No category" ? nil : palette.rank(name),
             subs: byName[name] ?? [])
        }
        return slices(groups, windows: windows, scope: scope)
    }

    private func slices(
        _ groups: [(id: String, name: String, ink: Int?, subs: [Subscription])],
        windows: [(first: Date, last: Date)],
        scope: String
    ) -> [DashboardData.Slice] {
        var rows: [DashboardData.Slice] = []
        var scopedTotal = 0.0
        // Read once across the whole stretch, then kept to the chosen months: a gap
        // between two of them holds nothing a card counts.
        guard let from = windows.first?.first, let to = windows.last?.last else { return [] }

        var sums: [(id: String, name: String, ink: Int?, scoped: Double,
                    others: [String: Double], lines: [DashboardData.Slice.Line],
                    charges: [Charge])] = []
        for group in groups {
            var scoped = 0.0
            var others: [String: Double] = [:]
            // Per commitment as well as per group, from the same charges — so a
            // breakdown always adds up to the slice the reader tapped.
            var perSubScoped: [String: Double] = [:]
            var perSubOthers: [String: [String: Double]] = [:]
            var subNames: [String: String] = [:]
            let windowCharges = vault.map {
                chargesInRange($0, of: group.subs, from: from, to: to).filter { Self.falls($0.date, in: windows) }
            } ?? []
            for charge in windowCharges {
                subNames[charge.sub.id] = charge.sub.name
                if charge.currency == scope {
                    scoped += charge.amount
                    perSubScoped[charge.sub.id, default: 0] += charge.amount
                } else {
                    others[charge.currency, default: 0] += charge.amount
                    perSubOthers[charge.sub.id, default: [:]][charge.currency, default: 0] += charge.amount
                }
            }
            guard scoped > 0 || !others.isEmpty else { continue }
            scopedTotal += scoped
            let lines = subNames.keys.map { id in
                DashboardData.Slice.Line(
                    id: id,
                    name: subNames[id] ?? "—",
                    scoped: perSubScoped[id] ?? 0,
                    others: (perSubOthers[id] ?? [:])
                        .map { CurrencyAmount(currency: $0.key, amount: $0.value) }
                        .sorted { $0.amount > $1.amount }
                )
            }
            .sorted { a, b in
                a.scoped != b.scoped ? a.scoped > b.scoped : a.name < b.name
            }
            // The window's own charges, not a fresh look ahead: a card that lists the
            // next twelve months under a total for one month names months it never totalled.
            sums.append((group.id, group.name, group.ink, scoped, others, lines, windowCharges))
        }

        for row in sums.sorted(by: { $0.scoped > $1.scoped }) {
            rows.append(DashboardData.Slice(
                id: row.id,
                name: row.name,
                scoped: row.scoped,
                share: row.scoped > 0 && scopedTotal > 0 ? row.scoped / scopedTotal * 100 : nil,
                others: row.others.map { CurrencyAmount(currency: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount },
                ink: row.ink,
                breakdown: row.lines,
                charges: row.charges
            ))
        }
        return rows
    }

    // MARK: the ledger, row by row

    /// One stored charge as the list reads it, either side of today: the row joined to its
    /// commitment, with the words its facts strip and the filters ask for.
    struct ChargeItem: Identifiable {
        let id: String
        let subId: String
        let name: String
        let amountText: String
        let facts: [LBMetaFact]
        let searchText: String
        let category: String?
        let ink: Int?
        let badge: DashboardData.CommitmentItem.Badge?
        let monthLabel: String
        let dateISO: String
        /// Dated before today. Today's own rows are still ahead: they can be marked.
        let isPast: Bool
        let isPaid: Bool
        /// Money that arrived rather than left: listed with the rest, marked, never summed.
        let isIncome: Bool
        /// Money moved between the owner's own accounts: the same — listed, marked, never summed.
        let isTransfer: Bool
        let methodId: String?
        let memberId: String?
        let cycle: BillingCycle
        let status: SubStatus
        let currency: String
    }

    /// Everything a search may match on a row: its names and notes, and the words the screen
    /// shows for it — "Cancelling", "Free trial", "Yearly", "Money in", "Paid" — so a word
    /// read on a card finds the card.
    static func searchWords(_ sub: Subscription, category: String?, member: String?, method: String?,
                            badge: DashboardData.CommitmentItem.Badge?, status: SubStatus, more: [String?]) -> String {
        let badgeWord: String? = switch badge {
        case .trial: "free trial"
        case .cancelling: "cancelling"
        case .paused: "paused"
        case .cancelled: "cancelled"
        case nil: nil
        }
        let cycleWord = sub.billingCycle == .once ? "one-time once" : sub.billingCycle.rawValue
        let words: [String?] = [sub.name, category, member, method, sub.notes, badgeWord, status.rawValue, cycleWord,
                                sub.isTransfer ? "transfer" : nil, sub.isIncome ? "money in income" : nil]
        return (words + more).compactMap { $0 }.joined(separator: " ").lowercased()
    }

    /// Every stored charge, oldest first: behind today for every commitment, because it
    /// happened; ahead only for the ones still active, since a paused or cancelled plan's
    /// written rows will not charge. Money in rides along, marked. Read once per load and day.
    func chargeItems() -> [ChargeItem] {
        let today = LB.todayMid()
        if let chargeCache, chargeCache.day == today { return chargeCache.rows }
        guard let vault else { return [] }
        let palette = VaultPalette.categories(vault.subscriptions)
        let members = Dictionary(vault.familyMembers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let methods = Dictionary(vault.paymentMethods.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        // Each commitment's badge once, not once per row.
        var badges: [String: DashboardData.CommitmentItem.Badge] = [:]
        for sub in vault.subscriptions {
            badges[sub.id] = badge(sub, in: vault, today)
        }

        let rows = (allCharges(vault, today) + incomeCharges(vault, today) + transferCharges(vault, today))
            .filter { $0.date < today || isEffectivelyActive($0.sub, today) }
            .sorted { $0.date < $1.date }
        // One formatter per month and per distinct amount, not one per row: a plan of a
        // thousand rows names three dozen months and a few dozen amounts, and a formatter
        // costs more than the rest of the row put together.
        var monthWords: [Substring: String] = [:]
        var amountTexts: [String: String] = [:]
        func word<Key: Hashable>(_ known: inout [Key: String], _ key: Key, or make: () -> String) -> String {
            if let word = known[key] { return word }
            let word = make()
            known[key] = word
            return word
        }
        let derived: [ChargeItem] = rows.map { charge in
            let sub = charge.sub
            let past = charge.date < today
            let dateISO = LB.toISO(charge.date)
            let monthLabel = word(&monthWords, dateISO.prefix(7)) { LB.monthYear(charge.date).lowercased() }
            let amountText = word(&amountTexts, "\(charge.currency) \(charge.amount)") { fmtMoney(charge.amount, charge.currency) }
            let category = trimmedCategory(sub)
            let member = sub.familyMemberId.flatMap { members[$0] }
            let method = sub.paymentMethodId.flatMap { methods[$0] }
            let income = sub.isIncome
            let transfer = sub.isTransfer
            // The badge is the commitment's, worn by each of its rows.
            let badge = badges[sub.id]
            // The commitment row's strip, so a landed charge and one ahead read alike. A mark
            // set ahead of time is the pill's word, not the strip's.
            let facts: [LBMetaFact] = [
                LBMetaFact(symbol: LBGlyph.date,
                           text: past ? settledWord(charge.date) : LB.dayWord(LB.daysBetween(today, charge.date))),
                income ? LBMetaFact(symbol: LBGlyph.income, text: "Money in") : (transfer ? Self.transferFact : nil),
            ].compactMap { $0 }
                + Self.linkFacts(category: category, member: member, method: method, spend: !income && !transfer)
            return ChargeItem(
                id: charge.id,
                subId: sub.id,
                name: sub.name,
                amountText: (income ? "+" : "") + amountText,
                facts: facts,
                searchText: Self.searchWords(sub, category: category, member: member, method: method, badge: badge,
                                             status: displayStatus(sub, today),
                                             more: [charge.paid ? "paid" : nil, amountText, monthLabel]),
                category: category,
                ink: category.flatMap { palette.rank($0) },
                badge: badge,
                monthLabel: monthLabel,
                dateISO: dateISO,
                isPast: past,
                isPaid: charge.paid,
                isIncome: income,
                isTransfer: transfer,
                methodId: sub.paymentMethodId,
                memberId: sub.familyMemberId,
                cycle: sub.billingCycle,
                status: displayStatus(sub, today),
                currency: charge.currency
            )
        }
        chargeCache = (day: today, rows: derived)
        return derived
    }

    // MARK: accounts

    struct AccountCard: Identifiable {
        let id: String
        let name: String
        /// The owning member's name, or nil — an absence wears no label.
        let owner: String?
        let activeCount: Int
        let totalCount: Int
        let ink: Int?
        /// Real cash leaving over the next twelve months, per currency — never blended.
        let window: [CurrencyAmount]
        let next: (amountText: String, name: String, dateText: String)?
        /// What the account held, and when that was true — as last said, never computed.
        let balance: (amountText: String, dateText: String)?
    }

    /// One card per payment method, plus the unassigned bucket when money would
    /// otherwise vanish. Numbers come from the same engine every other panel trusts.
    func accountCards() -> [AccountCard] {
        guard let vault else { return [] }
        let today = LB.todayMid()
        let balanceCurrency = figureCurrency(vault, today)
        let palette = Self.accountPalette(vault)
        let members = Dictionary(vault.familyMembers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let window = (from: LB.firstOfMonth(today), to: LB.addDays(LB.addMonths(LB.firstOfMonth(today), 12), -1))

        // A real account is a card whatever it holds; only the unassigned bucket needs money in it.
        func card(id: String, name: String, owner: String?, ink: Int?, subs: [Subscription],
                  balance: (Double, String?)? = nil, real: Bool = true) -> AccountCard? {
            guard real || !subs.isEmpty else { return nil }
            let coming = chargesInRange(vault, of: subs, from: window.from, to: window.to)
            // The soonest charge still owed, whenever it is — including years out. A card
            // whose money all lands beyond the window still says what comes next.
            let soonest = activeUpcoming(vault, of: subs, today).first
            return AccountCard(
                id: id,
                name: name,
                owner: owner,
                activeCount: subs.filter { isLiveCommitment($0, in: vault, today) }.count,
                totalCount: subs.filter { !isSettledCharge($0, in: vault, today) }.count,
                ink: ink,
                window: sumByCurrency(coming),
                next: soonest.map {
                    (fmtMoney($0.charge.amount, $0.charge.currency), $0.sub.name, settledWord($0.date))
                },
                balance: balance.map { amount, day in
                    (fmtMoney(amount, balanceCurrency), day.flatMap(LB.parseDate).map(settledWord) ?? "")
                }
            )
        }

        var cards = vault.paymentMethods.compactMap { method in
            card(
                id: method.id,
                name: method.name,
                owner: method.familyMemberId.flatMap { members[$0] },
                ink: palette.rank(method.id),
                subs: vault.subscriptions.filter { $0.paymentMethodId == method.id },
                balance: method.balance.map { ($0, method.balanceDate) }
            )
        }
        if let unassigned = card(
            id: "no-account", name: "No account", owner: nil, ink: nil,
            subs: vault.subscriptions.filter { $0.paymentMethodId == nil }, real: false
        ) {
            cards.append(unassigned)
        }
        return cards
    }

    // MARK: reports

    /// What the reports folder holds, read once per vault load. The unreadable count is
    /// surfaced, not swallowed — a skipped file must never look like a missing report.
    func reports() -> (reports: [Report], unreadable: Int) {
        if let reportsCache { return reportsCache }
        guard let vaultFolder else { return ([], 0) }
        let listed = ReportReader.list(in: vaultFolder)
        reportsCache = listed
        return listed
    }

    func report(id: String) -> Report? {
        reports().reports.first { $0.id == id }
    }

    /// The raw file behind one report — what a share sends, byte for byte.
    func reportFile(id: String) -> (url: URL, bytes: Data)? {
        vaultFolder.flatMap { ReportReader.file(id: id, in: $0) }
    }

    /// The live share for a report, remembered in the sidecar so every device sees it.
    func shareId(forReport id: String) -> String? {
        vaultFolder.flatMap { WorkspaceStore.read(in: $0).reportShares[id] }
    }

    /// What one live share is: its link, when it was made and ends, who was given it.
    struct ShareDetails {
        let id: String
        let url: String
        let sharedOn: Date?
        let expiresAt: Date?
        let with: String
    }

    /// The live share with everything the sidecar recorded about it. A share made before
    /// details were kept still has its link, derived from its id the way the server names it.
    func shareDetails(forReport id: String) -> ShareDetails? {
        guard let vaultFolder else { return nil }
        let workspace = WorkspaceStore.read(in: vaultFolder)
        guard let shareId = workspace.reportShares[id] else { return nil }
        let kept = workspace.reportShareDetails[id] ?? [:]
        return ShareDetails(
            id: shareId,
            url: kept["url"] ?? ShareReportClient.viewerURL(id: shareId),
            sharedOn: kept["shared_on"].flatMap(LB.parseDateTime),
            expiresAt: kept["expires_at"].flatMap(LB.parseDateTime),
            with: kept["with"] ?? ""
        )
    }

    /// A share begins with everything known about it, and ends with all of it gone.
    func rememberShare(_ shareId: String?, forReport id: String, details: [String: String] = [:]) {
        guard let vaultFolder else { return }
        try? WorkspaceStore.update(in: vaultFolder) { workspace in
            var shares = workspace.reportShares
            shares[id] = shareId
            workspace.reportShares = shares
            var kept = workspace.reportShareDetails
            kept[id] = shareId == nil ? nil : details
            workspace.reportShareDetails = kept
        }
    }

    /// One detail of a live share, added or corrected — who has the link, when it ends.
    func noteShare(forReport id: String, _ key: String, _ value: String?) {
        guard let vaultFolder, shareId(forReport: id) != nil else { return }
        try? WorkspaceStore.update(in: vaultFolder) { workspace in
            var kept = workspace.reportShareDetails
            var mine = kept[id] ?? [:]
            mine[key] = value?.isEmpty == false ? value : nil
            kept[id] = mine
            workspace.reportShareDetails = kept
        }
    }

    /// Viewer comments land in the report file itself — one line each under the module
    /// they answered — so they read wherever the vault does. Returns lines added.
    func mergeComments(_ notes: [(module: String, line: String)], intoReport id: String) -> Int? {
        guard let file = reportFile(id: id) else { return nil }
        do {
            let added = try ReportReader.mergeViewerComments(notes, intoReportAt: file.url)
            if added > 0 { reportsCache = nil }
            return added
        } catch {
            Telemetry.shared.failed(.fileSave, error)
            saveError = error.friendlyDescription
            return nil
        }
    }

    // MARK: writes

    /// One write path for every edit: patch the raw file → compare-and-swap to disk →
    /// re-read. A refusal lands in saveError and the vault stays exactly as it was.
    @discardableResult
    private func commit(_ patch: ([String: Any]) throws -> [String: Any]) -> Bool {
        saveError = nil
        // One gate for every write, as on the desktop. Reads and export are untouched: a
        // lapsed trial stops new writing, it never takes anything away.
        guard !readOnly else {
            saveError = "This account has no licence. Buy longbook to keep editing. Everything you have stays visible and exportable."
            return false
        }
        guard let vaultFolder, let loadedFile else {
            saveError = "No folder is open, so there’s nowhere to save."
            return false
        }
        do {
            let next = try patch(loadedFile.raw)
            try VaultDisk.write(next, to: vaultFolder, expecting: loadedFile.bytes)
            expectingOwnChange = true
            load()
            refreshHostedCopy()
            refreshStructures()
            return true
        } catch {
            Telemetry.shared.failed(.fileSave, error)
            saveError = error.friendlyDescription
            return false
        }
    }

    /// The registry's definitions — never a value — mirror into the owner's account row
    /// after every save. Quiet by design; StructureSync.payload is the whole boundary,
    /// held to definitions-only by its own test.
    private func refreshStructures() {
        guard let vault else { return }
        let rows = StructureSync.payload(from: vault)
        guard !rows.isEmpty else { return }
        Task { _ = await StructureSync.push(rows) }
    }

    /// The owner's explicit choice, made in settings. On pushes now; off deletes the
    /// hosted row before the flag changes — a revoke that fails stays visibly on.
    func setHostedPush(_ on: Bool) async -> String? {
        guard let vaultFolder, let loadedFile else { return "No folder is open, so there’s nothing to share." }
        // Off is always allowed: a lapsed account can still delete its copy.
        if on, !hasCloud { return Self.cloudNeeded }
        if on {
            if let message = await HostedMemory.push(memoryData: loadedFile.bytes) {
                Telemetry.shared.failed(.hostedCopy, kind: .unknown)
                return message
            }
        } else {
            if let message = await HostedMemory.revoke() {
                Telemetry.shared.failed(.hostedCopy, kind: .unknown)
                return message
            }
        }
        let workspace = try? WorkspaceStore.update(in: vaultFolder) { $0.hostedPush = on }
        hostedPush = workspace?.hostedPush ?? on
        Telemetry.shared.send("app.hosted_copy_switched", ["on": on])
        return nil
    }

    /// What a server feature says when the account has no Cloud; the screens open the
    /// door to one beside it.
    static let cloudNeeded = "longbook Cloud is needed for this. Subscribe in Account."

    /// The server switch as the folder holds it now: another device may have turned it
    /// on or off since this one last loaded.
    func rereadHostedPush() {
        guard let vaultFolder else { return }
        hostedPush = WorkspaceStore.read(in: vaultFolder).hostedPush
    }

    // MARK: proposals waiting in the cloud

    /// Proposals this app could not apply. Nothing else in the system mentions them
    /// again, so they are held here until the owner has seen them.
    private(set) var failedProposals: [PendingWrite] = []
    /// Set when proposals are waiting but this app may not apply them — a lapsed trial.
    private(set) var proposalsHeldBack = 0

    /// Writes an AI proposed while nobody was here, applied on open. Each goes in through
    /// the OUTSIDE door — VaultDisk, never `commit`: a write marked ours would skip the
    /// review this promises. One write per proposal, so one failure costs only itself.
    private var applyingPendingWrites = false

    func applyPendingWrites() async {
        // NOT gated on the hosted-copy switch: a proposal is filed against the account,
        // not against the copy, and an owner who turned the copy off would otherwise
        // accumulate a queue nothing would ever apply or mention. One run at a time: two
        // overlapping fetches would apply the same proposal twice.
        guard vaultFolder != nil, !applyingPendingWrites else { return }
        #if DEBUG
        // A harness run on this Mac shares the owner's keychain session: his queue is not its to apply.
        let env = ProcessInfo.processInfo.environment
        if env["LONGBOOK_SKIP_AUTH"] != nil || env["LONGBOOK_SNAPSHOT_SCREEN"] != nil || env["LONGBOOK_WINDOW_SNAPSHOT"] != nil { return }
        #endif
        applyingPendingWrites = true
        defer { applyingPendingWrites = false }
        failedProposals = await PendingWrites.unapplied() + localRequests().filter { $0.failure != nil }
        let waiting = await PendingWrites.waiting()
        guard !waiting.isEmpty else { return }
        // A lapsed trial stops writing, so say so rather than discarding the queue.
        guard !readOnly else {
            proposalsHeldBack = waiting.count
            return
        }
        proposalsHeldBack = 0

        var applied = 0
        for write in waiting {
            guard let folder = vaultFolder, let file = loadedFile else { break }
            do {
                switch try PendingApply.apply(write, to: file.raw, now: Date(), schema: schema) {
                case .vault(let next):
                    try VaultDisk.write(next, to: folder, expecting: file.bytes)
                case .drawReport(let request):
                    try drawRequestedReport(request, prefix: MonthlyReport.requestPrefix)
                case .insight(let module, let text):
                    try InsightsWriter.append(module: module, text: text, in: folder)
                }
                applied += 1
                await PendingWrites.markApplied(write.id)
                // Re-read between proposals: the next one applies to what the last wrote,
                // and the CAS check compares against bytes that are actually current.
                applyingProposal = true
                load()
                applyingProposal = false
            } catch {
                // Told, not retried: a proposal that cannot land says why, where the owner
                // can read it, and never blocks the ones behind it.
                await PendingWrites.markFailed(write.id, reason: error.friendlyDescription)
            }
        }
        if applied > 0 {
            load()
            refreshHostedCopy()
        }
        // Re-read after the run: a proposal that failed during it belongs on the list too.
        failedProposals = await PendingWrites.unapplied() + localRequests().filter { $0.failure != nil }
    }

    // MARK: requests the local server left in the folder

    /// The vault's requests/ folder: what the server on this machine asked of the app, one
    /// file each, because the server may not draw a report itself.
    private var requestsFolder: URL? {
        vaultFolder?.appendingPathComponent("requests", isDirectory: true)
    }

    /// Every request file, oldest first, each read as a proposal so one apply path serves
    /// both doors. A file that is not a request is left alone and never listed.
    private func localRequests() -> [PendingWrite] {
        guard let folder = requestsFolder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        // A dot-named file is the server's half-written temp; it becomes a request on rename.
        return names.sorted().filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.compactMap { name in
            let url = folder.appendingPathComponent(name)
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            // A request is a few hundred bytes; anything large, or not a plain file, is not one.
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) <= 64 * 1024,
                  let bytes = try? VaultReader.coordinatedRead(url),
                  let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let id = (object["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let kind = object["kind"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else { return nil }
            let created = object["created_at"] as? String
            return PendingWrite(
                id: id, kind: kind, payload: payload, sourceRef: object["source_ref"] as? String,
                origin: "local", client: object["client"] as? String,
                createdAt: created.flatMap { iso.date(from: $0) ?? plain.date(from: $0) },
                failure: object["failure"] as? String
            )
        }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    private func requestFile(_ id: UUID) -> URL? {
        guard let folder = requestsFolder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        return names.first { $0.hasSuffix(".json") && !$0.hasPrefix(".") && $0.lowercased().contains(id.uuidString.lowercased()) }
            .map { folder.appendingPathComponent($0) }
    }

    /// Requests from the server on this machine, applied like a cloud proposal. A request
    /// that lands is deleted; one that cannot keeps its file with the reason written in, so
    /// Changes can say why. Needs no account: the local door has none.
    func applyLocalRequests() {
        let waiting = localRequests().filter { $0.failure == nil }
        guard !waiting.isEmpty else {
            failedProposals = failedProposals.filter { $0.origin != "local" } + localRequests().filter { $0.failure != nil }
            return
        }
        for write in waiting {
            guard let file = loadedFile, let url = requestFile(write.id) else { continue }
            do {
                switch try PendingApply.apply(write, to: file.raw, now: Date(), schema: schema) {
                case .drawReport(let request):
                    try drawRequestedReport(request, prefix: MonthlyReport.requestPrefix)
                default:
                    // The local server writes the vault itself; only a report is ever asked for here.
                    throw WriteError.invalid("The server on this Mac asked for \"\(write.kind)\", which it writes itself.")
                }
                try? FileManager.default.removeItem(at: url)
            } catch {
                let reason = String(error.friendlyDescription.prefix(400))
                if let bytes = try? Data(contentsOf: url),
                   var object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                    object["failure"] = reason
                    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                        try? VaultScaffold.coordinatedWrite(data, to: url)
                    }
                }
            }
        }
        failedProposals = failedProposals.filter { $0.origin != "local" } + localRequests().filter { $0.failure != nil }
    }

    // MARK: statements read by the server

    /// A statement review written whole, signed "statement import": statements with a kept line
    /// filed in documents, the vault built off the main actor, one write, one re-read, then
    /// the month reports. The rows land kept. A refusal writes nothing and removes the copies.
    func importReview(_ review: StatementImport.Review, statements: [URL]) async throws -> Int {
        guard !readOnly else {
            throw WriteError.invalid("This account has no licence. Buy longbook to keep editing. Everything you have stays visible and exportable.")
        }
        guard let folder = vaultFolder, let file = loadedFile else {
            throw WriteError.invalid("No folder is open, so there’s nowhere to save.")
        }
        var review = review
        var filed: [String] = []
        do {
            for index in review.files.indices where review.files[index].keepsALine && statements.indices.contains(index) {
                let source = try fileStatement(statements[index])
                review.files[index].source = source
                filed.append(source)
            }
            let raw = file.raw
            let schema = schema
            let ready = review
            let written = try await Task.detached(priority: .userInitiated) {
                try StatementImport.write(ready, to: raw, now: Date(), schema: schema)
            }.value
            // The file is compared with the bytes the build started from: a write landing
            // meanwhile refuses this one.
            try VaultDisk.write(written.vault, to: folder, expecting: file.bytes)
            expectingOwnChange = true
            load()
            refreshHostedCopy()
            refreshStructures()
            // Every month the new rows confirm gets its report, drawn from what was written.
            drawMonthlyReports()
            return written.charges
        } catch {
            Telemetry.shared.failed(.fileSave, error)
            let scoped = folder.startAccessingSecurityScopedResource()
            for source in filed { try? FileManager.default.removeItem(at: folder.appendingPathComponent(source)) }
            if scoped { folder.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// The file's own bytes as text, for the server that reorganises it. Nil when none is open.
    var vaultText: String? {
        loadedFile.map { String(decoding: $0.bytes, as: UTF8.self) }
    }

    /// The server's proposals applied together as one change, signed "Reorganise", so Changes
    /// shows one card with one Keep All and one Undo All. A proposal the file refuses is
    /// skipped and counted; the rest still land.
    func reorganise(_ proposals: [ReorganiseCloud.Proposal]) throws -> (applied: Int, skipped: Int) {
        guard !readOnly else {
            throw WriteError.invalid("This account has no licence. Buy longbook to keep editing. Everything you have stays visible and exportable.")
        }
        guard let folder = vaultFolder, let file = loadedFile else {
            throw WriteError.invalid("No folder is open, so there’s nowhere to save.")
        }
        var raw = file.raw
        var applied = 0
        var skipped = 0
        let now = Date()
        for proposal in proposals {
            let write = PendingWrite(id: UUID(), kind: proposal.kind, payload: proposal.payload,
                                     sourceRef: "reorganise", keyName: "Reorganise", origin: "reorganise")
            do {
                guard case .vault(let next) = try PendingApply.apply(write, to: raw, now: now, schema: schema) else { skipped += 1; continue }
                raw = next
                applied += 1
            } catch {
                skipped += 1
            }
        }
        guard applied > 0 else { return (0, skipped) }
        try VaultDisk.write(raw, to: folder, expecting: file.bytes)
        load()
        refreshHostedCopy()
        refreshStructures()
        return (applied, skipped)
    }

    /// The picked file copied into the vault's documents folder, returned as the relative
    /// path the rows cite. A name already taken gets a numbered twin, never overwritten.
    func fileStatement(_ url: URL) throws -> String {
        guard let folder = vaultFolder else { throw WriteError.invalid("No folder is open, so there’s nowhere to keep it.") }
        let folderScoped = folder.startAccessingSecurityScopedResource()
        defer { if folderScoped { folder.stopAccessingSecurityScopedResource() } }
        let documents = folder.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let ext = url.pathExtension.lowercased()
        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "-", options: .regularExpression)
        var name = "\(base).\(ext)"
        var twin = 2
        while FileManager.default.fileExists(atPath: documents.appendingPathComponent(name).path) {
            name = "\(base)-\(twin).\(ext)"
            twin += 1
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: url, to: documents.appendingPathComponent(name))
        return "documents/\(name)"
    }

    /// The charges already in the book as the importer keys them, so a statement read
    /// twice writes nothing twice.
    func importedChargeKeys() -> Set<String> {
        guard let vault else { return [] }
        let subs = Dictionary(vault.subscriptions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out = Set<String>()
        for charge in vault.charges {
            guard let sub = subs[charge.commitmentId] else { continue }
            var narration = sub.name
            if case .string(let line)? = sub.details?["statement_line"] { narration = line }
            out.insert(StatementImport.key(date: charge.date, amount: charge.amount, narration: narration))
        }
        return out
    }

    /// The people and the accounts the book already names, so a reading matches them
    /// rather than inventing twins.
    var memberNames: [String] { vault?.familyMembers.map(\.name) ?? [] }
    var accountNames: [String] { vault?.paymentMethods.map(\.name) ?? [] }

    /// Every commitment category the vault or the library knows, for the on-device namer.
    var commitmentTagNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for name in (vault?.tags ?? []).filter({ $0.kind == "commitment" }).map(\.name)
            + TagLibrary.entries(kind: "commitment").map(\.name)
        where seen.insert(name.lowercased()).inserted {
            names.append(name)
        }
        return names
    }

    /// The owner has read a failure; it stops being news.
    func dismissFailedProposal(_ id: UUID) {
        let local = failedProposals.first { $0.id == id }?.origin == "local"
        failedProposals.removeAll { $0.id == id }
        if local {
            if let url = requestFile(id) { try? FileManager.default.removeItem(at: url) }
        } else {
            Task { await PendingWrites.dismissFailed(id) }
        }
    }

    /// The app's own report for every month holding a confirmed charge: written when absent,
    /// redrawn when it was the app's, never over one an AI wrote. A redraw carries the
    /// comments the stored file holds — they are the words a viewer wrote.
    func drawMonthlyReports() {
        guard let vault, let folder = vaultFolder else { return }
        let scope = figureCurrency(vault)
        let existing = ReportReader.list(in: folder).reports
        let deleted = Set(WorkspaceStore.read(in: folder).deletedReports)
        let spending = MonthlyReport.spendingMonths(in: vault)
        var drawn = 0
        for first in MonthlyReport.months(in: vault) {
            let id = MonthlyReport.id(for: first)
            if deleted.contains(id) { continue }
            let found = existing.first { $0.id == id }
            // A month with nothing spent has nothing to report: none is drawn, and one the
            // app drew earlier goes.
            guard spending.contains(first) else {
                if let found, found.subtitle == MonthlyReport.subtitle, removeReportFile(found.id, in: folder) { drawn += 1 }
                continue
            }
            // The owner's own edits to a drawn report are what it left out; a redraw keeps them out.
            var report = MonthlyReport.build(
                vault: vault, month: first, currency: scope,
                removed: found?.removedIds ?? [], hidden: Set(found?.hiddenIds ?? [])
            )
            if let found {
                if found.subtitle != MonthlyReport.subtitle { continue }
                report = report.carryingComments(from: found)
            }
            if writeReport(report, in: folder) { drawn += 1 }
        }
        // Spans follow the ledger too: a trip or an asked-for report drawn again from its own
        // days and scope, the open trip through today. The open trip is read fresh: another
        // device may have ended it, and a file not yet synced here is no reason to close it.
        let today = LB.todayMid()
        openTripId = WorkspaceStore.read(in: folder).openTrip
        for found in existing where MonthlyReport.redrawsItself(found) && !deleted.contains(found.id) {
            let through: Date? = found.id == openTripId ? today : nil
            guard let report = MonthlyReport.redraw(found, vault: vault, through: through, fallbackCurrency: scope, today: today) else { continue }
            if writeReport(report, in: folder) { drawn += 1 }
        }
        if drawn > 0 { reportsCache = nil }
    }

    // MARK: spans: trips and asked-for reports

    /// The trip still running, by report id, mirrored from the sidecar.
    private(set) var openTripId: String?

    /// Every trip, newest first.
    func trips() -> [Report] {
        reports().reports.filter(\.isTrip)
    }

    /// Draws a span over the days and scope asked and returns its id. The same name, days and
    /// scope asked again redraw the same file; the currency is the one the span was spent in.
    @discardableResult
    func drawRequestedReport(_ request: PendingApply.ReportRequest, prefix: String) throws -> String {
        guard let vault, let folder = vaultFolder else { throw WriteError.invalid("No folder is open, so there’s nowhere to save.") }
        let existing = ReportReader.list(in: folder).reports
        let id = MonthlyReport.spanId(prefix: prefix, title: request.title, start: request.start, end: request.end,
                                      scope: request.scope, existing: existing)
        let currency = MonthlyReport.spanCurrency(vault: vault, from: request.start, to: request.end, scope: request.scope,
                                                  fallback: figureCurrency(vault))
        var report = MonthlyReport.draw(vault: vault, id: id, title: request.title, from: request.start, to: request.end,
                                        scope: request.scope, currency: currency)
        if let found = existing.first(where: { $0.id == id }) {
            report = MonthlyReport.redraw(found, vault: vault, through: request.end, fallbackCurrency: figureCurrency(vault)) ?? report
        }
        try saveReport(report, in: folder)
        reportsCache = nil
        return id
    }

    /// A trip that is over: its days, people and accounts, drawn as a report. Returns its id.
    func addPastTrip(name: String, members: [String], accounts: [String], start: Date, end: Date) -> String? {
        let scope = ReportScope(accounts: accounts, members: members)
        return try? drawRequestedReport(.init(title: name, start: start, end: max(start, end), scope: scope.isEmpty ? nil : scope),
                                        prefix: MonthlyReport.tripPrefix)
    }

    /// A trip from today, open until ended: its report's last day follows today.
    func startTrip(name: String, members: [String], accounts: [String]) -> String? {
        let today = LB.todayMid()
        let scope = ReportScope(accounts: accounts, members: members)
        guard let id = try? drawRequestedReport(.init(title: name, start: today, end: today, scope: scope.isEmpty ? nil : scope),
                                                prefix: MonthlyReport.tripPrefix),
              let folder = vaultFolder
        else { return nil }
        try? WorkspaceStore.update(in: folder) { $0.openTrip = id }
        openTripId = id
        return id
    }

    /// Ends the running trip: drawn one last time through today, then closed on that day.
    func endTrip() {
        guard let folder = vaultFolder else { return }
        if let id = WorkspaceStore.read(in: folder).openTrip ?? openTripId, let vault, let found = report(id: id),
           let last = MonthlyReport.redraw(found, vault: vault, through: LB.todayMid(), fallbackCurrency: figureCurrency(vault)) {
            writeReport(last, in: folder)
            reportsCache = nil
        }
        try? WorkspaceStore.update(in: folder) { $0.openTrip = nil }
        openTripId = nil
    }

    /// The running trip's report; nil when none runs. The redraw pass closes one whose file is gone.
    func openTrip() -> Report? {
        openTripId.flatMap { report(id: $0) }
    }

    /// Deletes a report, as a commitment is deleted: its file goes and the app never draws
    /// it again. A trip still running is ended with it.
    @discardableResult
    func deleteReport(id: String) -> Bool {
        guard let folder = vaultFolder, MonthlyReport.isSafeId(id) else { return false }
        guard removeReportFile(id, in: folder) else {
            saveError = "That report could not be deleted."
            return false
        }
        try? WorkspaceStore.update(in: folder) { workspace in
            workspace.deletedReports.append(id)
            if workspace.openTrip == id { workspace.openTrip = nil }
        }
        if openTripId == id { openTripId = nil }
        reportsCache = nil
        return true
    }

    private func removeReportFile(_ id: String, in folder: URL) -> Bool {
        guard MonthlyReport.isSafeId(id), let file = ReportReader.file(id: id, in: folder) else { return false }
        return (try? FileManager.default.removeItem(at: file.url)) != nil
    }

    /// The file for one report, written only when its bytes changed. True when it was.
    @discardableResult
    private func writeReport(_ report: Report, in folder: URL) -> Bool {
        (try? saveReport(report, in: folder)) ?? false
    }

    /// The same write, saying why it failed. An id that is not one safe file name is refused:
    /// it came out of a file, and must never reach another file in the folder.
    @discardableResult
    private func saveReport(_ report: Report, in folder: URL) throws -> Bool {
        guard MonthlyReport.isSafeId(report.id) else {
            throw WriteError.invalid("The report’s name cannot be used as a file name.")
        }
        let reports = folder.appendingPathComponent(ReportReader.folderName, isDirectory: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(report)
        let file = reports.appendingPathComponent("\(report.id).json")
        if let current = try? Data(contentsOf: file), current == bytes { return false }
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        try VaultScaffold.coordinatedWrite(bytes, to: file)
        return true
    }

    /// How a charge stands in a report: in it, taken out and listed last, or dropped for good.
    enum ReportRowState {
        case kept, removed, hidden
    }

    /// Takes a charge out of a report, puts it back, or drops it for good. The app's own
    /// report is drawn again without it, so every figure follows; any other report keeps its
    /// figures and only marks or drops the row.
    func setReportRow(_ rowId: String, in reportId: String, to state: ReportRowState) {
        guard let vault, let folder = vaultFolder, let found = report(id: reportId) else { return }
        var removed = found.removedIds
        var hidden = Set(found.hiddenIds ?? [])
        removed.remove(rowId)
        hidden.remove(rowId)
        switch state {
        case .removed: removed.insert(rowId)
        case .hidden: hidden.insert(rowId)
        case .kept: break
        }
        var next: Report
        if found.subtitle == MonthlyReport.subtitle, let key = found.period, let first = LB.parseDate(key + "-01") {
            next = MonthlyReport.build(vault: vault, month: first, currency: figureCurrency(vault), removed: removed, hidden: hidden)
                .carryingComments(from: found)
        } else if MonthlyReport.redrawsItself(found) {
            // A span is drawn again over its own days into its own file — never its month's.
            var marked = found
            marked.hiddenIds = hidden.isEmpty ? nil : hidden.sorted()
            marked.modules = found.modules.map { module in
                guard case .transactions(var list) = module, list.title == MonthlyReport.Titles.charges else { return module }
                list.rows = list.rows.map { row in
                    var copy = row
                    if let id = row.id { copy.removed = removed.contains(id) ? true : nil }
                    return copy
                }
                return .transactions(list)
            }
            let through: Date? = found.id == openTripId ? LB.todayMid() : nil
            next = MonthlyReport.redraw(marked, vault: vault, through: through, fallbackCurrency: figureCurrency(vault)) ?? marked
        } else {
            next = found
            next.hiddenIds = hidden.isEmpty ? nil : hidden.sorted()
            next.modules = found.modules.map { module in
                guard case .transactions(var list) = module else { return module }
                let rows = list.rows.filter { $0.id.map { !hidden.contains($0) } ?? true }.map { row -> ReportRow in
                    var marked = row
                    if let id = row.id { marked.removed = removed.contains(id) ? true : nil }
                    return marked
                }
                list.rows = rows.filter { $0.removed != true } + rows.filter { $0.removed == true }
                return .transactions(list)
            }
        }
        writeReport(next, in: folder)
        reportsCache = nil
    }

    /// The server deletes a copy no app has refreshed for ninety days. An app in use says
    /// so once a day, save or no save, so only an abandoned copy ever expires. It touches
    /// a copy that exists and uploads nothing.
    @ObservationIgnored private var keepingAlive = false

    private func keepHostedCopyAlive() {
        guard hostedPush, hasCloud, !keepingAlive else { return }
        keepingAlive = true
        Task {
            await HostedMemory.touchIfDue()
            keepingAlive = false
        }
    }

    /// Every successful save refreshes the hosted copy, quietly — the local save already
    /// stands, and the settings screen shows the copy's age where it matters. Without
    /// Cloud the copy is left as it was; the server would refuse the write anyway.
    private func refreshHostedCopy() {
        guard hostedPush, hasCloud, let bytes = loadedFile?.bytes else { return }
        Task { if await HostedMemory.push(memoryData: bytes) != nil { Telemetry.shared.failed(.hostedCopy, kind: .unknown) } }
    }

    /// A commitment in one write: its fields and the tag it wears, then, when given, a new
    /// count of planned charges and the changes to the one charge the form is on. A refusal
    /// anywhere leaves the file as it was; `VaultPatch.saveCommitment` composes them.
    @discardableResult
    func save(_ edit: SubEdit, plannedCount: Int? = nil,
              charge: VaultPatch.ChargeChange? = nil) -> Bool {
        commit {
            try VaultPatch.saveCommitment(edit, plannedCount: plannedCount, charge: charge,
                                          in: $0, now: Date(), schema: schema)
        }
    }

    @discardableResult
    func cancelCommitment(id: String) -> Bool {
        commit { try VaultPatch.cancel(id: id, in: $0, now: Date(), schema: schema) }
    }

    @discardableResult
    func deleteCommitment(id: String) -> Bool {
        commit { try VaultPatch.delete(id: id, from: $0, now: Date()) }
    }

    @discardableResult
    func setPaid(subscriptionId: String, dateISO: String, paid: Bool) -> Bool {
        commit { try VaultPatch.setCharge(commitmentId: subscriptionId, date: dateISO, paid: paid, in: $0, now: Date()) }
    }

    func removeCharge(subscriptionId: String, dateISO: String) -> Bool {
        commit { VaultPatch.removeCharges(of: subscriptionId, dates: [dateISO], in: $0, now: Date()) }
    }

    /// This charge and every unpaid one after it, with the plan ended the day before.
    func removeChargeAndLater(subscriptionId: String, dateISO: String) -> Bool {
        commit { try VaultPatch.removeChargeAndLater(of: subscriptionId, from: dateISO, in: $0, now: Date(), schema: schema) }
    }

    /// Whether deleting this charge can take the plan after it: a recurring commitment's
    /// unpaid charge dated today or later. A paid one, the past, and a one-time commitment
    /// go one row at a time.
    func offersLaterRemoval(subscriptionId: String, dateISO: String) -> Bool {
        guard let sub = subscription(id: subscriptionId), sub.billingCycle != .once,
              let charge = charges(of: subscriptionId).first(where: { $0.row.date == dateISO }) else { return false }
        return !charge.paid
    }

    /// The words the delete alert adds for "every one after": how many planned charges go
    /// with it and the day the plan then ends.
    func laterRemovalWords(subscriptionId: String, dateISO: String) -> String {
        let rows = charges(of: subscriptionId).filter { $0.row.date > dateISO && !$0.row.paid }
        let end = LB.parseDate(dateISO).map { LB.longDate(LB.addDays($0, -1)) } ?? "the day before"
        let count = rows.count == 0 ? "no later charge" : rows.count == 1 ? "the one planned after it" : "the \(rows.count) planned after it"
        return "Every one after also removes \(count), and the plan ends on \(end). Paid charges stay."
    }

    /// Several charges of one commitment taken out in one write: a plan dropped from a review.
    func removeCharges(subscriptionId: String, datesISO: [String]) -> Bool {
        commit { VaultPatch.removeCharges(of: subscriptionId, dates: datesISO, in: $0, now: Date()) }
    }

    /// How many charges stand from today on, today's included — the count "Planned till" shows
    /// on an existing one, counted as the Save's planned count is set.
    func plannedCount(_ id: String) -> Int {
        guard let vault, let sub = vault.subscriptions.first(where: { $0.id == id }) else { return 0 }
        return LongbookCore.plannedAhead(sub, in: vault).count
    }

    /// The day of an existing commitment's last charge were this Save to land: the Save run on
    /// the file as loaded, nothing written. Nil for none, or for a Save the writer refuses.
    func plannedEnd(of edit: SubEdit, plannedCount: Int?, charge: VaultPatch.ChargeChange?) -> Date? {
        guard let raw = loadedFile?.raw, let id = edit.id,
              let out = try? VaultPatch.saveCommitment(edit, plannedCount: plannedCount, charge: charge,
                                                       in: raw, now: Date(), schema: schema)
        else { return nil }
        let rows = out["charges"] as? [[String: Any]] ?? []
        return rows.filter { $0["commitment_id"] as? String == id }.compactMap { LB.parseDate($0["date"] as? String) }.max()
    }

    /// Every charge of one commitment, date order, as the detail lists them.
    func charges(of id: String) -> [Charge] {
        guard let vault, let sub = vault.subscriptions.first(where: { $0.id == id }) else { return [] }
        return LongbookCore.charges(of: sub, in: vault)
    }

    /// Name an account or a member, and get the id back so a form can select what it just
    /// named. Idempotent: a name already there is matched, never duplicated. Nil when the
    /// write is refused — a new name the secret scan catches among them — with `saveError` set.
    @discardableResult
    func addEntity(_ kind: VaultPatch.EntityKind, named name: String) -> String? {
        var made: String?
        let saved = commit { raw in
            let result = try VaultPatch.ensureEntity(kind, named: name, in: raw, now: Date())
            made = result.id
            return result.vault
        }
        return saved ? made : nil
    }

    /// How many commitments would be left without one — what the delete warning states.
    func referenceCount(_ kind: VaultPatch.EntityKind, id: String) -> Int {
        loadedFile.map { VaultPatch.referenceCount(kind, id: id, in: $0.raw) } ?? 0
    }

    @discardableResult
    func renameEntity(_ kind: VaultPatch.EntityKind, id: String, to name: String) -> Bool {
        commit { try VaultPatch.renameEntity(kind, id: id, to: name, in: $0, now: Date()) }
    }

    /// A picture named in the file, as a URL inside the open longbook folder.
    func photoURL(_ relative: String?) -> URL? {
        guard let relative, !relative.isEmpty, let folder = vaultFolder else { return nil }
        return folder.appendingPathComponent(relative)
    }

    func commitmentPhotoURL(id: String) -> URL? {
        photoURL(vault?.subscriptions.first { $0.id == id }?.photo)
    }

    func tagPhotoURL(kind: String, name: String?) -> URL? {
        guard let name else { return nil }
        let key = nameKey(name)
        return photoURL((vault?.tags ?? []).first { $0.kind == kind && $0.nameKey == key }?.photo)
    }

    @discardableResult
    func setCommitmentPhoto(id: String, photo: String?) -> Bool {
        commit { try VaultPatch.setCommitmentPhoto(id: id, photo: photo, in: $0, now: Date()) }
    }

    @discardableResult
    func setTagPhoto(kind: String, name: String, photo: String?) -> Bool {
        commit { try VaultPatch.setTagPhoto(kind: kind, named: name, photo: photo, in: $0, now: Date()) }
    }

    /// Doubly-optional arguments, as the writer takes them: nil leaves a field alone,
    /// .some(nil) clears it. A new `name` and any `accountOwners` (accounts a person's
    /// editor linked or unlinked) ride in the same write, so one Save is one change.
    @discardableResult
    func setEntityDetails(
        _ kind: VaultPatch.EntityKind, id: String,
        accountTag: String?? = nil, parentAccountId: String?? = nil, email: String?? = nil,
        balance: Double?? = nil, balanceDate: String?? = nil,
        memberTag: String?? = nil, ownerMemberId: String?? = nil,
        accountNotes: String?? = nil, removingCardName: Bool = false,
        name: String? = nil, accountOwners: [(accountId: String, memberId: String?)] = [], photo: String?? = nil
    ) -> Bool {
        commit { raw in
            let now = Date()
            var next = raw
            if let name {
                next = try VaultPatch.renameEntity(kind, id: id, to: name, in: next, now: now)
            }
            next = try VaultPatch.setEntityDetails(
                kind, id: id, in: next, now: now,
                accountTag: accountTag, parentAccountId: parentAccountId, email: email,
                balance: balance, balanceDate: balanceDate,
                memberTag: memberTag, ownerMemberId: ownerMemberId,
                accountNotes: accountNotes, removingCardName: removingCardName, photo: photo
            )
            for change in accountOwners {
                next = try VaultPatch.setEntityDetails(
                    .paymentMethod, id: change.accountId, in: next, now: now,
                    ownerMemberId: .some(change.memberId)
                )
            }
            if case .some(.some(let tag)) = accountTag {
                next = VaultPatch.ensureTag(kind: "account", named: tag, in: next, now: now)
            }
            if case .some(.some(let tag)) = memberTag,
               !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                next = VaultPatch.ensureTag(kind: "member", named: tag, in: next, now: now)
            }
            return next
        }
    }

    /// The tag vocabulary a picker offers for one kind: the vault's own registry first
    /// (the owner's order), then the library's seeded names it hasn't adopted yet.
    func tagChoices(kind: String) -> [(name: String, icon: String?)] {
        var seen = Set<String>()
        var out: [(String, String?)] = []
        for def in vault?.tags ?? [] where def.kind == kind {
            if seen.insert(def.nameKey).inserted {
                out.append((def.name, def.icon ?? TagLibrary.entry(kind: kind, name: def.name)?.icon))
            }
        }
        // A regional tag (UPI) is offered only in its region; a vault already wearing it
        // lists it in its own registry above, so nothing it holds goes missing.
        for entry in TagLibrary.entries(kind: kind) where Regional.offersLibraryTag(kind: kind, name: entry.name) {
            if seen.insert(entry.nameKey).inserted { out.append((entry.name, entry.icon)) }
        }
        return out
    }

    /// The owner's own tags — registry entries the shipped library doesn't know. Only
    /// these can be deleted from the form; the library's vocabulary isn't in the file.
    func customTags(kind: String) -> Set<String> {
        var out = Set<String>()
        for def in vault?.tags ?? [] where def.kind == kind && TagLibrary.entry(kind: kind, name: def.name) == nil {
            out.insert(def.name)
        }
        return out
    }

    /// How many commitments wear the tag — what the delete warning states.
    func tagWearCount(kind: String, name: String) -> Int {
        commitmentsWearing(kind: kind, name: name).count
    }

    /// The commitments wearing the tag, in the order the file keeps them — the list the
    /// tag's own screen shows, so a category can be read as well as renamed.
    func commitmentsWearing(kind: String, name: String) -> [Subscription] {
        guard kind == "commitment" else { return [] }
        let key = nameKey(name)
        guard !key.isEmpty else { return [] }
        return (vault?.subscriptions ?? []).filter { nameKey($0.tag) == key }
    }

    /// Drops a refusal the reader has moved on from.
    func clearSaveError() {
        guard saveError != nil else { return }
        saveError = nil
    }

    /// Every commitment naming this account or person — the list its edit screen shows,
    /// so what a rename or removal touches is visible before it happens.
    func commitmentsNaming(_ kind: VaultPatch.EntityKind, id: String) -> [Subscription] {
        (vault?.subscriptions ?? []).filter {
            kind == .paymentMethod ? $0.paymentMethodId == id : $0.familyMemberId == id
        }
    }

    /// Takes the label off one commitment and leaves the rest of the row exactly as it
    /// was. The money stays; only the label goes — and it goes through the same reviewed
    /// write as any edit, so history explains it.
    @discardableResult
    func untag(commitmentId: String) -> Bool {
        guard let sub = subscription(id: commitmentId) else { return false }
        var edit = SubEdit(from: sub)
        edit.tag = nil
        return save(edit)
    }

    /// Deletes the tag and untags the rows wearing it — one reviewed write, kept in history.
    @discardableResult
    func deleteTag(kind: String, name: String) -> Bool {
        commit { VaultPatch.removeTag(kind: kind, named: name, in: $0, now: Date()).vault }
    }

    /// Renames the tag and carries every row wearing it — one reviewed write, kept in
    /// history like any other. A refusal lands in `saveError`, in the product's voice.
    @discardableResult
    func renameTag(kind: String, from oldName: String, to newName: String) -> Bool {
        commit { try VaultPatch.renameTag(kind: kind, from: oldName, to: newName, in: $0, now: Date()).vault }
    }

    /// The icon a tag wears — the vault's registry first, the library as fallback.
    func tagIcon(kind: String, name: String?) -> String? {
        guard let name else { return nil }
        let key = nameKey(name)
        if let def = (vault?.tags ?? []).first(where: { $0.kind == kind && $0.nameKey == key }) {
            return def.icon ?? TagLibrary.entry(kind: kind, name: name)?.icon
        }
        return TagLibrary.entry(kind: kind, name: name)?.icon
    }

    /// What the entity sheet edits beyond the name, plus the accounts this one could be
    /// linked to — every other account linked to nothing. Current values come from the raw
    /// row the writer patches, so unknown neighbours never round-trip through the slice;
    /// an account's details, read only, come as stored.
    func entityDetails(_ kind: VaultPatch.EntityKind, id: String) -> (
        accountTag: String?, parentAccountId: String?, email: String?,
        parentChoices: [(id: String, name: String)], balance: Double?, balanceDate: String?,
        memberTag: String?, ownerMemberId: String?, accountDetails: Details?, notes: String?,
        createdAt: String?, linkedHere: [(id: String, name: String)]
    ) {
        let row = (loadedFile?.raw[kind.rawValue] as? [[String: Any]] ?? [])
            .first { $0["id"] as? String == id }
        let isAccount = kind == .paymentMethod
        let parents = isAccount
            ? (vault?.paymentMethods ?? [])
                .filter { $0.id != id && $0.parentAccountId == nil }
                .map { (id: $0.id, name: $0.name) }
            : []
        // The accounts linked to this one: while any are, it cannot be linked itself.
        let linkedHere = isAccount
            ? (vault?.paymentMethods ?? [])
                .filter { $0.parentAccountId == id }
                .map { (id: $0.id, name: $0.name) }
            : []
        return (
            row?["tag"] as? String,
            row?["parent_account_id"] as? String,
            row?["email"] as? String,
            parents,
            (row?["balance"] as? NSNumber)?.doubleValue,
            row?["balance_date"] as? String,
            isAccount ? nil : row?["tag"] as? String,
            isAccount ? row?["member_id"] as? String : nil,
            isAccount ? vault?.paymentMethods.first { $0.id == id }?.details : nil,
            isAccount ? row?["notes"] as? String : nil,
            row?["created_at"] as? String,
            linkedHere
        )
    }

    @discardableResult
    func deleteEntity(_ kind: VaultPatch.EntityKind, id: String) -> Bool {
        commit { try VaultPatch.deleteEntity(kind, id: id, in: $0, now: Date()) }
    }

    /// A charge a card names: the next one owed, or one that landed.
    struct EntityMoment: Identifiable {
        let id: String
        let commitmentId: String
        let name: String
        let date: Date
        let amountText: String
        let tag: String?
        let symbol: String
        let ink: Int?
    }

    /// One account or person as a list card reads it. The editor's preview redraws the
    /// same value from the fields being typed, so what can be edited is `var`.
    struct EntityCard: Identifiable {
        let id: String
        let kind: VaultPatch.EntityKind
        var name: String
        var tag: String?
        /// A person's picture inside the longbook folder, when they have one.
        var photo: URL? = nil
        let ink: Int?
        /// False for the bucket of commitments that name no account or person.
        let isReal: Bool
        let isIncomplete: Bool
        /// Starred by the owner: listed first, and kept in the Mac sidebar.
        var starred = false
        let commitments: Int
        let charges: Int
        let addedOn: Date?
        var balance: Double?
        var balanceDate: Date?
        let balanceCurrency: String
        var owner: (id: String, name: String, ink: Int?)?
        var linked: (id: String, name: String)?
        /// For a person: how many accounts belong to them.
        var accountCount: Int
        let next: EntityMoment?
        /// Real cash over the next twelve months, per currency — never blended.
        let window: [CurrencyAmount]
    }

    /// What one account's or person's commitments come to: how many, how many charges
    /// landed, the next one owed, the latest landed, and the next twelve months. A nil id
    /// reads the commitments that name nobody.
    func entitySummary(_ kind: VaultPatch.EntityKind, id: String?, recentLimit: Int = 4) -> (
        commitments: Int, charges: Int, next: EntityMoment?, recent: [EntityMoment], window: [CurrencyAmount], upcoming: [EntityMoment]
    ) {
        guard let vault else { return (0, 0, nil, [], [], []) }
        return summary(kind, id: id, ledger: entityLedger(vault), recentLimit: recentLimit)
    }

    /// A row a picker offers: who or what could be chosen, with no charges read for it.
    struct EntityChoice: Identifiable {
        let id: String
        let name: String
        let tag: String?
        let ink: Int?
        /// For an account: the person it belongs to today.
        let owner: (id: String, name: String)?
    }

    /// The vault read once for the entity screens: every charge joined to its commitment
    /// and grouped by it, the commitments and landed rows grouped by account and person,
    /// and the cards drawn from them so far.
    private struct EntityLedger {
        let day: Date
        let bySub: [String: [Charge]]
        let subsByMethod: [String?: [Subscription]]
        let subsByMember: [String?: [Subscription]]
        let landedByMethod: [String?: [ChargeItem]]
        let landedByMember: [String?: [ChargeItem]]
        let categories: Palette
        var cards: [String: [EntityCard]] = [:]
    }

    /// Held per vault load and per day; `load()` drops it beside `chargeCache`. Not observed:
    /// it fills during a body pass, and a body must not invalidate itself.
    @ObservationIgnored private var ledgerCache: EntityLedger?

    private func entityLedger(_ vault: Vault) -> EntityLedger {
        let today = LB.todayMid()
        if let ledgerCache, ledgerCache.day == today { return ledgerCache }
        let subs = Dictionary(vault.subscriptions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // One pass, one date parse per row, every direction of money.
        var bySub: [String: [Charge]] = [:]
        for row in vault.charges {
            guard let sub = subs[row.commitmentId], let date = LB.parseDate(row.date) else { continue }
            bySub[sub.id, default: []].append(Charge(sub: sub, row: row, date: date, today: today))
        }
        for id in bySub.keys { bySub[id]?.sort { $0.date < $1.date } }
        // Newest first: the rows "Show all" lists under Past, in the order it lists them.
        let landed = Array(chargeItems().filter(\.isPast).reversed())
        let made = EntityLedger(
            day: today, bySub: bySub,
            subsByMethod: Dictionary(grouping: vault.subscriptions, by: \.paymentMethodId),
            subsByMember: Dictionary(grouping: vault.subscriptions, by: \.familyMemberId),
            landedByMethod: Dictionary(grouping: landed, by: \.methodId),
            landedByMember: Dictionary(grouping: landed, by: \.memberId),
            categories: VaultPalette.categories(vault.subscriptions)
        )
        ledgerCache = made
        return made
    }

    /// A one-time row whose charge is behind today or paid is that charge, not a
    /// commitment, whichever way its money moves. One with no charge written still counts.
    private func isSettledOnce(_ sub: Subscription, _ ledger: EntityLedger) -> Bool {
        guard sub.billingCycle == .once, isEffectivelyActive(sub, ledger.day) else { return false }
        let own = ledger.bySub[sub.id] ?? []
        return !own.isEmpty && !own.contains { $0.date >= ledger.day && !$0.paid }
    }

    /// The commitments naming an account or a person, money in and transfers among them,
    /// less the one-time rows already settled. The card, the editor's list and the delete
    /// question all count these, so the three never disagree.
    func entityCommitments(_ kind: VaultPatch.EntityKind, id: String?) -> [Subscription] {
        guard let vault else { return [] }
        let ledger = entityLedger(vault)
        let naming = (kind == .paymentMethod ? ledger.subsByMethod : ledger.subsByMember)[id] ?? []
        return naming.filter { !isSettledOnce($0, ledger) }
    }

    /// What deleting would leave without it: its commitments, the one-time charges already
    /// settled, and for a person the accounts that belong to them.
    func entityUse(_ kind: VaultPatch.EntityKind, id: String) -> (commitments: Int, oneTime: Int, accounts: Int) {
        guard let vault else { return (0, 0, 0) }
        let ledger = entityLedger(vault)
        let naming = (kind == .paymentMethod ? ledger.subsByMethod : ledger.subsByMember)[id] ?? []
        let live = naming.filter { !isSettledOnce($0, ledger) }.count
        let theirs = kind == .familyMember ? vault.paymentMethods.filter { $0.familyMemberId == id }.count : 0
        return (live, naming.count - live, theirs)
    }

    private func summary(_ kind: VaultPatch.EntityKind, id: String?, ledger: EntityLedger, recentLimit: Int) -> (
        commitments: Int, charges: Int, next: EntityMoment?, recent: [EntityMoment], window: [CurrencyAmount], upcoming: [EntityMoment]
    ) {
        let isAccount = kind == .paymentMethod
        let subs = (isAccount ? ledger.subsByMethod : ledger.subsByMember)[id] ?? []
        func symbol(_ tag: String?) -> String {
            tagIcon(kind: "commitment", name: tag) ?? CategoryGlyph.symbol(tag ?? "")
        }
        // The cached backward ledger: the same rows "Show all" lists under Past.
        let landed = (isAccount ? ledger.landedByMethod : ledger.landedByMember)[id] ?? []
        let recent = landed.prefix(recentLimit).compactMap { charge -> EntityMoment? in
            guard let date = LB.parseDate(charge.dateISO) else { return nil }
            return EntityMoment(
                id: charge.id, commitmentId: charge.subId, name: charge.name, date: date,
                amountText: charge.amountText, tag: charge.category,
                symbol: symbol(charge.category), ink: charge.ink
            )
        }
        // The soonest charge still owed, as core's upcoming list orders them.
        let due = subs.compactMap { sub -> Charge? in
            guard isOwed(sub), isEffectivelyActive(sub, ledger.day) else { return nil }
            return ledger.bySub[sub.id]?.first { $0.date >= ledger.day && !$0.paid }
        }
        .min { $0.date != $1.date ? $0.date < $1.date : $0.sub.name < $1.sub.name }
        let next = due.map { charge -> EntityMoment in
            let tag = trimmedCategory(charge.sub)
            return EntityMoment(
                id: charge.id, commitmentId: charge.sub.id, name: charge.sub.name, date: charge.date,
                amountText: fmtMoney(charge.amount, charge.currency), tag: tag,
                symbol: symbol(tag), ink: tag.flatMap { ledger.categories.rank($0) }
            )
        }
        let from = LB.firstOfMonth(ledger.day)
        let to = LB.addDays(LB.addMonths(from, 12), -1)
        let coming = subs.filter(isSpending)
            .flatMap { ledger.bySub[$0.id] ?? [] }
            .filter { $0.date >= from && $0.date <= to }
        // The next few charges still owed, soonest first: the preview's Upcoming commitments.
        var owedAhead: [Charge] = []
        for sub in subs where isOwed(sub) && isEffectivelyActive(sub, ledger.day) {
            for charge in ledger.bySub[sub.id] ?? [] where charge.date >= ledger.day && !charge.paid {
                owedAhead.append(charge)
            }
        }
        owedAhead.sort { $0.date != $1.date ? $0.date < $1.date : $0.sub.name < $1.sub.name }
        var upcoming: [EntityMoment] = []
        for charge in owedAhead.prefix(recentLimit) {
            let tag = trimmedCategory(charge.sub)
            let ink: Int? = tag.flatMap { ledger.categories.rank($0) }
            upcoming.append(EntityMoment(
                id: charge.id, commitmentId: charge.sub.id, name: charge.sub.name, date: charge.date,
                amountText: fmtMoney(charge.amount, charge.currency), tag: tag, symbol: symbol(tag), ink: ink
            ))
        }
        return (
            subs.filter { !isSettledOnce($0, ledger) }.count,
            landed.count, next, Array(recent), sumByCurrency(coming), upcoming
        )
    }

    /// Accounts or people as a picker lists them. No charge is read, so an editor can ask
    /// for the other kind without paying for its cards.
    func entityChoices(_ kind: VaultPatch.EntityKind) -> [EntityChoice] {
        guard let vault else { return [] }
        if kind == .familyMember {
            let inks = Self.memberPalette(vault)
            return vault.familyMembers.map {
                EntityChoice(id: $0.id, name: $0.name, tag: $0.tag, ink: inks.rank($0.id), owner: nil)
            }
        }
        let inks = Self.accountPalette(vault)
        let names = Dictionary(vault.familyMembers.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return vault.paymentMethods.map { method in
            let owner = method.familyMemberId.flatMap { id in names[id].map { (id: id, name: $0) } }
            return EntityChoice(id: method.id, name: method.name, tag: method.tag, ink: inks.rank(method.id), owner: owner)
        }
    }

    /// One card, for the editor's preview: taken from the cards already drawn for this
    /// load when there are any, and otherwise drawn alone.
    func entityCard(_ kind: VaultPatch.EntityKind, id: String) -> EntityCard? {
        guard let vault else { return nil }
        let ledger = entityLedger(vault)
        if let drawn = ledger.cards[kind.rawValue] { return drawn.first { $0.id == id } }
        return drawCards(kind, only: id, vault: vault, ledger: ledger).first
    }

    /// Every account or person as a card, starred ones first, then in the file's order — an
    /// account linked to another follows it. The bucket of commitments naming nobody comes
    /// last, and only when it holds something.
    func entityCards(_ kind: VaultPatch.EntityKind) -> [EntityCard] {
        // Reading the vault first keeps the screen observing it; the cache is not observed.
        guard let vault else { return [] }
        let ledger = entityLedger(vault)
        if let drawn = ledger.cards[kind.rawValue] { return drawn }
        let cards = drawCards(kind, only: nil, vault: vault, ledger: ledger)
        ledgerCache?.cards[kind.rawValue] = cards
        return cards
    }

    /// The cards of one kind, or the one card `only` names, from a ledger already read.
    private func drawCards(
        _ kind: VaultPatch.EntityKind, only: String?, vault: Vault, ledger: EntityLedger
    ) -> [EntityCard] {
        let isAccount = kind == .paymentMethod
        let people = Self.memberPalette(vault)
        let currency = figureCurrency(vault)
        // created_at is an instant: the day it fell on here, not the day it was in UTC.
        func addedDay(_ stamp: String?) -> Date? {
            LB.parseDateTime(stamp).map(LB.dayOf) ?? stamp.flatMap { LB.parseDate(String($0.prefix(10))) }
        }

        var cards: [EntityCard] = []
        if isAccount {
            let palette = Self.accountPalette(vault)
            let ids = Set(vault.paymentMethods.map(\.id))
            let heads = vault.paymentMethods.filter { $0.parentAccountId.map { !ids.contains($0) } ?? true }
            var ordered = heads.flatMap { head in
                [head] + vault.paymentMethods.filter { $0.parentAccountId == head.id && $0.id != head.id }
            }
            // A row the grouping missed (a chain the contract forbids) is still a card.
            let placed = Set(ordered.map(\.id))
            ordered += vault.paymentMethods.filter { !placed.contains($0.id) }
            for method in ordered where only == nil || only == method.id {
                let sums = summary(kind, id: method.id, ledger: ledger, recentLimit: 0)
                let owner = method.familyMemberId.flatMap { id in vault.familyMembers.first { $0.id == id } }
                let linked = method.linkedAccountId.flatMap { id in vault.paymentMethods.first { $0.id == id } }
                cards.append(EntityCard(
                    id: method.id, kind: kind, name: method.name, tag: method.tag,
                    photo: photoURL(method.photo),
                    ink: palette.rank(method.id), isReal: true, isIncomplete: method.isIncomplete ?? false,
                    starred: method.isStarred, commitments: sums.commitments, charges: sums.charges, addedOn: addedDay(method.createdAt),
                    balance: method.balance,
                    balanceDate: LB.parseDate(method.balanceDate),
                    balanceCurrency: currency,
                    owner: owner.map { ($0.id, $0.name, people.rank($0.id)) },
                    linked: linked.map { ($0.id, $0.name) },
                    accountCount: 0, next: sums.next, window: sums.window
                ))
            }
        } else {
            for member in vault.familyMembers where only == nil || only == member.id {
                let sums = summary(kind, id: member.id, ledger: ledger, recentLimit: 0)
                cards.append(EntityCard(
                    id: member.id, kind: kind, name: member.name, tag: member.tag,
                    photo: photoURL(member.photo),
                    ink: people.rank(member.id), isReal: true, isIncomplete: member.isIncomplete ?? false,
                    starred: member.isStarred, commitments: sums.commitments, charges: sums.charges, addedOn: addedDay(member.createdAt),
                    balance: nil, balanceDate: nil, balanceCurrency: currency,
                    owner: nil, linked: nil,
                    accountCount: vault.paymentMethods.filter { $0.familyMemberId == member.id }.count,
                    next: sums.next, window: sums.window
                ))
            }
        }
        let nobody = (isAccount ? ledger.subsByMethod : ledger.subsByMember)[String?.none] ?? []
        if only == nil, !nobody.isEmpty {
            let loose = summary(kind, id: nil, ledger: ledger, recentLimit: 0)
            cards.append(EntityCard(
                id: isAccount ? Self.unassignedMethodId : Self.unassignedMemberId, kind: kind,
                name: isAccount ? "No account" : "No person", tag: nil, ink: nil,
                isReal: false, isIncomplete: false,
                commitments: loose.commitments, charges: loose.charges, addedOn: nil,
                balance: nil, balanceDate: nil, balanceCurrency: currency,
                owner: nil, linked: nil, accountCount: 0, next: loose.next, window: loose.window
            ))
        }
        // Starred first, each side in the order above.
        return cards.filter(\.starred) + cards.filter { !$0.starred }
    }

    /// Stars or unstars a person or an account: starred ones lead their list and stand in
    /// the Mac sidebar.
    @discardableResult
    func setStarred(_ kind: VaultPatch.EntityKind, id: String, _ starred: Bool) -> Bool {
        commit { try VaultPatch.setEntityDetails(kind, id: id, in: $0, now: Date(), starred: starred) }
    }

    /// Nothing to show yet — the state onboarding exists for.
    var isEmptyVault: Bool {
        guard let vault else { return true }
        return vault.subscriptions.isEmpty
    }

    /// What this commitment has cost: its rows before today, as written. Silent under
    /// three charges. The span names the first charge counted.
    func rowMemory(id: String) -> String? {
        guard let vault, let sub = vault.subscriptions.first(where: { $0.id == id }) else { return nil }
        let today = LB.todayMid()
        let charges = LongbookCore.charges(of: sub, in: vault, today).filter { $0.date < today }
        guard charges.count >= 3, let first = charges.first else { return nil }
        let total = charges.filter { $0.currency == sub.currency }.reduce(0) { $0 + $1.amount }
        // One commitment's own rows, said on its own screen: a transfer's are called transfers.
        let rows = sub.isTransfer ? "transfers" : "charges"
        return "\(fmtMoney(total, sub.currency)) across \(charges.count) \(rows) since \(LB.monthYear(first.date))."
    }

    /// Resolved display names for a commitment's links — ids are load-bearing, names
    /// are for reading.
    func entityNames(memberId: String?, methodId: String?) -> (member: String?, method: String?) {
        (
            memberId.flatMap { id in vault?.familyMembers.first { $0.id == id }?.name },
            methodId.flatMap { id in vault?.paymentMethods.first { $0.id == id }?.name }
        )
    }

    /// The decoded row behind a list item — what the edit form loads.
    func subscription(id: String) -> Subscription? {
        vault?.subscriptions.first { $0.id == id }
    }

    /// The choices the form offers, from the vault itself.
    var editChoices: (
        currencies: [String], categories: [String],
        methods: [(id: String, name: String)], members: [(id: String, name: String)],
        names: [String]
    ) {
        let vaultCurrencies = Set(vault?.subscriptions.map(\.currency) ?? [])
        let common = ["INR", "USD", "EUR", "GBP"]
        // The sidecar holds the selector's list — a preference — while the vault holds what
        // the money is. A code a commitment counts is offered whatever the lists say.
        let put = Set(hiddenCurrencies).subtracting(vaultCurrencies)
        let kept = customCurrencies.filter { !vaultCurrencies.contains($0) && !common.contains($0) }
        let currencies = (common.filter(vaultCurrencies.contains) + vaultCurrencies.subtracting(common).sorted()
            + kept + common.filter { !vaultCurrencies.contains($0) }).filter { !put.contains($0) }
        var seen = Set<String>()
        let ordered = currencies.filter { seen.insert($0).inserted }
        let categories = Set((vault?.subscriptions ?? []).compactMap { trimmedCategory($0) }).sorted()
        return (
            ordered,
            categories,
            (vault?.paymentMethods ?? []).map { ($0.id, $0.name) },
            (vault?.familyMembers ?? []).map { ($0.id, $0.name) },
            Array(Set((vault?.subscriptions ?? []).map(\.name))).sorted()
        )
    }

    /// The AI's note for one app module, if it left one — see docs/insights-format.md.
    func insight(_ module: String) -> Insight? {
        if insightsCache == nil {
            insightsCache = vaultFolder.map { InsightsReader.byModule(in: $0) } ?? [:]
        }
        return insightsCache?[module]
    }

    /// The owner dismisses a note: it leaves the file, so the mark leaves the module too.
    func removeInsight(_ module: String) {
        guard let vaultFolder else { return }
        do {
            try InsightsWriter.remove(module: module, in: vaultFolder)
            insightsCache = nil
        } catch {
            Telemetry.shared.failed(.fileSave, error)
            saveError = error.friendlyDescription
        }
    }

    struct InsightPlace: Identifiable {
        let id: String
        let place: String
        let insight: Insight
        let door: Destination?
        let ink: Int?
    }

    struct InsightArea: Identifiable {
        let id: String
        let title: String
        let rows: [InsightPlace]
    }

    /// The dashboard modules a note can annotate, in the dashboard's own order, each named
    /// as its card is on the dashboard.
    static let dashboardModules: [(id: String, place: String, door: Destination)] = [
        ("dashboard.next_payment", "Next payment", .calendar),
        ("dashboard.active_commitments", "Commitments", .commitments(ListFilter())),
        ("dashboard.next_30_days", "Coming up", .commitments(ListFilter())),
        ("dashboard.this_month", "Spending", .commitments(ListFilter())),
        ("dashboard.by_account", "Accounts", .accounts),
        ("dashboard.by_category", "Categories", .commitments(ListFilter())),
    ]

    /// Every note the AI has left, grouped by the area it annotates — the insights
    /// page's whole content. A module id the app doesn't recognise stays silent, as
    /// docs/insights-format.md rules; an account or member id resolves to its name.
    func insightAreas() -> [InsightArea] {
        guard case .loaded(let data) = state else { return [] }
        // A dashboard note opens the screen its card opens; the Mac's Insights opens the
        // dashboard itself, which its sidebar can reach.
        var areas: [InsightArea] = [
            InsightArea(id: "dashboard", title: "Dashboard", rows: Self.dashboardModules.compactMap { module in
                insight(module.id).map {
                    InsightPlace(id: module.id, place: module.place, insight: $0, door: module.door, ink: nil)
                }
            }),
        ]
        let entities: [(String, String, Destination, [DashboardData.SidebarEntity], String)] = [
            ("accounts", "Accounts", .accounts, data.sidebarMethods, "account."),
            ("members", "People", .members, data.sidebarMembers, "member."),
        ]
        for (id, title, door, list, prefix) in entities {
            areas.append(InsightArea(id: id, title: title, rows: list.compactMap { entity in
                insight(prefix + entity.id).map {
                    InsightPlace(id: prefix + entity.id, place: entity.name, insight: $0, door: door, ink: entity.ink)
                }
            }))
        }
        return areas.filter { !$0.rows.isEmpty }
    }

    // MARK: members

    struct MemberCard: Identifiable {
        let id: String
        let name: String
        let ink: Int?
        let accountCount: Int
        let renewalCount: Int
        let addedOn: String?
        /// Real cash on this member's behalf over the next twelve months, per currency.
        let window: [CurrencyAmount]
        /// Categories in the member's biggest currency carry a share bar; a category
        /// whose money is all foreign is listed with its own sums and no bar.
        let breakdown: [(name: String, amountText: String, share: Double?)]
        /// The soonest charge, whenever it is — the card's answer when the window is empty.
        let next: (amountText: String, name: String, dateText: String)?
    }

    /// One card per family member; the unassigned bucket appears only when money
    /// would otherwise vanish.
    func memberCards() -> [MemberCard] {
        guard let vault else { return [] }
        let today = LB.todayMid()
        let palette = Self.memberPalette(vault)
        let window = (from: LB.firstOfMonth(today), to: LB.addDays(LB.addMonths(LB.firstOfMonth(today), 12), -1))

        // A real member is a card whatever they hold; only the unassigned bucket needs money in it.
        func card(id: String, name: String, ink: Int?, addedOn: String?, subs: [Subscription], accounts: Int, real: Bool = true) -> MemberCard? {
            guard real || !subs.isEmpty else { return nil }
            let coming = chargesInRange(vault, of: subs, from: window.from, to: window.to)
            let sums = sumByCurrency(coming)
            let primary = sums.first?.currency

            var byCategory: [String: [Charge]] = [:]
            var order: [String] = []
            for charge in coming {
                let key = trimmedCategory(charge.sub) ?? "No category"
                if byCategory[key] == nil { order.append(key) }
                byCategory[key, default: []].append(charge)
            }
            let primaryTotal = sums.first?.amount ?? 0
            let rows = order.map { key -> (name: String, amountText: String, share: Double?) in
                let charges = byCategory[key] ?? []
                let scoped = charges.filter { $0.currency == primary }.reduce(0) { $0 + $1.amount }
                if scoped > 0, primaryTotal > 0 {
                    return (key, fmtMoney(scoped, primary ?? ""), scoped / primaryTotal)
                }
                return (key, fmtMoneyTotals(sumByCurrency(charges)), nil)
            }
            .sorted { ($0.share ?? -1) > ($1.share ?? -1) }

            return MemberCard(
                id: id,
                name: name,
                ink: ink,
                accountCount: accounts,
                renewalCount: subs.filter { !isSettledCharge($0, in: vault, today) }.count,
                addedOn: addedOn.flatMap { LB.parseDate(String($0.prefix(10))) }.map { settledWord($0) },
                window: sums,
                breakdown: rows,
                next: activeUpcoming(vault, of: subs, today).first.map {
                    (fmtMoney($0.charge.amount, $0.charge.currency), $0.sub.name, settledWord($0.date))
                }
            )
        }

        var cards = vault.familyMembers.compactMap { member in
            card(
                id: member.id,
                name: member.name,
                ink: palette.rank(member.id),
                addedOn: member.createdAt,
                subs: vault.subscriptions.filter { $0.familyMemberId == member.id },
                accounts: vault.paymentMethods.filter { $0.familyMemberId == member.id }.count
            )
        }
        if let unassigned = card(
            id: Self.unassignedMemberId, name: "No person", ink: nil, addedOn: nil,
            subs: vault.subscriptions.filter { $0.familyMemberId == nil }, accounts: 0, real: false
        ) {
            cards.append(unassigned)
        }
        return cards
    }

    // MARK: calendar

    struct CalendarDay: Identifiable {
        let id: String
        let date: Date
        let dayNumber: Int
        let inMonth: Bool
        let isToday: Bool
        let isPast: Bool
        let charges: [(subId: String, name: String, amountText: String, paid: Bool, ink: Int?)]
        /// Transfers due the day, listed under the payments and flagged; never in the day's count.
        let transfers: [(subId: String, name: String, amountText: String, paid: Bool, ink: Int?)]
    }

    struct CalendarMonth {
        let title: String
        let days: [CalendarDay]
        let atStart: Bool
        let atEnd: Bool
    }

    /// One month's grid: real charges in both directions — memory and forecast. Past days
    /// read paid by the calendar and sit dimmed; marks apply from today on. Browsable ±12 months.
    func calendarMonth(offset: Int) -> CalendarMonth? {
        guard let vault else { return nil }
        let today = LB.todayMid()
        let first = LB.addMonths(LB.firstOfMonth(today), offset)
        let nextFirst = LB.addMonths(first, 1)
        let last = LB.addDays(nextFirst, -1)

        let palette = VaultPalette.categories(vault.subscriptions)
        typealias Row = (subId: String, name: String, amountText: String, paid: Bool, ink: Int?)
        func row(_ charge: Charge) -> Row {
            (subId: charge.sub.id,
             name: charge.sub.name,
             amountText: fmtMoney(charge.amount, charge.currency),
             paid: charge.paid,
             ink: trimmedCategory(charge.sub).flatMap { palette.rank($0) })
        }
        var byDay: [String: [Row]] = [:]
        for charge in chargesInRange(vault, from: first, to: last) {
            byDay[LB.toISO(charge.date), default: []].append(row(charge))
        }
        // Kept apart from the spending, so the day's count stays what was spent.
        var transfersByDay: [String: [Row]] = [:]
        for charge in transferCharges(vault, today) where charge.date >= first && charge.date <= last {
            transfersByDay[LB.toISO(charge.date), default: []].append(row(charge))
        }

        // Sunday-aligned, exactly as many weeks as the month needs.
        let weekday = LB.calendar.component(.weekday, from: first)
        let gridStart = LB.addDays(first, -(weekday - 1))
        let dayCount = LB.daysBetween(first, last) + 1
        let cells = Int(ceil(Double(weekday - 1 + dayCount) / 7.0)) * 7

        let days = (0..<cells).map { i in
            let date = LB.addDays(gridStart, i)
            return CalendarDay(
                id: LB.toISO(date),
                date: date,
                dayNumber: LB.calendar.component(.day, from: date),
                inMonth: date >= first && date <= last,
                isToday: LB.isSameDay(date, today),
                isPast: date < today,
                charges: byDay[LB.toISO(date)] ?? [],
                transfers: transfersByDay[LB.toISO(date)] ?? []
            )
        }
        return CalendarMonth(
            title: LB.monthYear(first),
            days: days,
            atStart: offset <= -12,
            atEnd: offset >= 12
        )
    }
}
