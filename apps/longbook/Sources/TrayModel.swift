#if os(macOS)
import AppKit
import Combine
import Foundation
import LongbookCore

/// The menu-bar fact: the nearest day anything is owed, read from the vault directly so
/// the tray stands without a window. Ported from the desktop's updateTray — per-currency
/// totals joined, never blended, and trayDetail=false quiets the text.
@MainActor
final class TrayModel: ObservableObject {
    /// The menu bar's word: "₹3,200 · in 3 days", or "longbook" when the detail is
    /// switched off, nothing is due, or no vault resolves.
    @Published private(set) var title = "longbook"
    /// The menu's own line — "in 3 days: ₹3,200 — Netflix" — shown even with the title
    /// quieted, exactly as the desktop's context menu was. Nil = nothing due.
    @Published private(set) var paymentLine: String?
    /// Why there is no payment line, when the reason is not "nothing is owed". A vault
    /// that cannot be read says so: silence here would read as an empty ledger.
    @Published private(set) var unreachable: String?

    /// What the menu shows under the title, whatever the reason.
    var menuLine: String { paymentLine ?? unreachable ?? "Nothing due" }

    private var watchers = Set<AnyCancellable>()
    /// The folder's own word that something wrote to it — the phone through iCloud, an
    /// agent — so the figure follows an edit with the window closed. Held for the app's life.
    private var folderWatcher: VaultWatcher?

    init() {
        refresh()
        // A date rollover or a wake from sleep makes every "today"-based figure stale
        // until recomputed — the same two triggers the desktop wired.
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .sink { _ in Task { @MainActor [weak self] in self?.refresh() } }
            .store(in: &watchers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { _ in Task { @MainActor [weak self] in self?.refresh() } }
            .store(in: &watchers)
        // An edit in the window is the third way the figure goes stale, and the only one
        // the reader watches happen.
        NotificationCenter.default.publisher(for: .longbookVaultDidChange)
            .sink { _ in Task { @MainActor [weak self] in self?.refresh() } }
            .store(in: &watchers)
    }

    /// One-shot read, no watcher held open: the menu calls this on open, so the line is
    /// current exactly when someone looks at it.
    func refresh() {
        title = "longbook"
        paymentLine = nil
        unreachable = nil

        guard let folder = VaultSource.resolve() else {
            unreachable = "No longbook folder on this Mac yet."
            return
        }
        watch(folder)
        let vault: Vault
        var fromCopy = false
        do {
            vault = try VaultReader.load(from: folder).vault
        } catch {
            // The copy the app keeps, exactly as the widget does. A figure from the last
            // time it opened beats no answer, as long as it says which it is — and as long
            // as it was taken from the folder now open, not one the owner has since left.
            let sameFolder = WidgetBridge.mirrorSource == folder.standardizedFileURL.path
            if sameFolder, let bytes = VaultMirror.read(),
               let copy = try? JSONDecoder().decode(Vault.self, from: bytes) {
                vault = copy
                fromCopy = true
            } else {
                // The reader already writes these sentences, including the one about iCloud
                // still carrying the file over. Discarding them is how "nothing due" gets
                // said about a vault nobody could open.
                unreachable = (error as? VaultReader.ReadError)?.errorDescription
                    ?? "Couldn’t read your longbook."
                return
            }
        }
        // The nearest day anything is owed, so a card bill due tomorrow is never skipped.
        guard let day = nextDueDay(vault, LB.todayMid())
        else {
            if fromCopy { unreachable = "Nothing due, from the last copy — your longbook isn’t readable right now." }
            return
        }
        // Raw key on purpose: absent or true shows the text, only an explicit false
        // hides it — the sidecar contract the desktop wrote.
        let detail = (WorkspaceStore.read(in: folder).raw["trayDetail"] as? Bool) != false
        // The total is spending only. Transfers due that day are named as transfers beside
        // it, and a day holding nothing else leads with them rather than a zero.
        let total = fmtMoneyTotals(sumByCurrency(day.charges))
        let count = "\(day.transfers.count) transfer\(day.transfers.count == 1 ? "" : "s")"
        var parts: [String] = []
        if !day.charges.isEmpty {
            parts.append("\(total) — " + day.charges.map(\.sub.name).joined(separator: ", "))
        }
        if !day.transfers.isEmpty {
            let moved = fmtMoneyTotals(sumByCurrency(day.transfers))
            parts.append("\(count), \(moved) — " + day.transfers.map(\.sub.name).joined(separator: ", "))
        }
        let when = LB.dayWord(day.days)
        title = detail ? "\(day.charges.isEmpty ? count : total) · \(when)" : "longbook"
        let line = "\(when): " + parts.joined(separator: " · ")
        paymentLine = fromCopy ? "\(line) (from the last copy)" : line
    }

    /// One watcher on the folder in use, re-pointed when the owner opens another. Passive:
    /// a kqueue costs nothing between writes, so it never sleeps.
    private func watch(_ folder: URL) {
        if let folderWatcher, folderWatcher.folder.standardizedFileURL.path == folder.standardizedFileURL.path { return }
        folderWatcher?.stop()
        let fresh = VaultWatcher(folder: folder, insideContainer: VaultWatcher.insideContainer(folder)) { [weak self] in
            self?.refresh()
        }
        folderWatcher = fresh
        fresh.resume()
    }
}
#endif
