// A copy of the vault's bytes the WIDGET is allowed to read: its sandbox can't see a
// vault in the app's Documents folder. The App Group container is the ONE place both
// can open. A FALLBACK — the widget reads the real vault first.
import Foundation

public enum VaultMirror {
    /// Not `financial_memory.json`. The name says what it is, so nobody who goes looking in the group
    /// container mistakes a derived copy for someone's vault, and nothing tries to open it as one.
    public static let fileName = "widget-copy.json"

    /// nil when the App Group is unavailable — a misconfigured or dropped entitlement. Reported by
    /// returning nothing rather than by crashing: the app's job is the vault, and a widget that goes
    /// blank must never take the app down with it.
    public static func directory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VaultLocation.appGroup)
    }

    /// Returns whether the copy CHANGED — false for a failed write or identical bytes.
    /// Used to decide whether to nudge WidgetKit, so "nothing changed" and "nothing to
    /// tell the widget" are the same answer. Skipping avoids touching the file for
    /// nothing on every 20s poll.
    @discardableResult
    public static func write(_ bytes: Data, in dir: URL) -> Bool {
        let file = dir.appendingPathComponent(fileName)
        if let existing = try? Data(contentsOf: file), existing == bytes { return false }
        // .atomic because the widget can wake mid-write: it reads this file on the system's schedule,
        // not ours, and a half-written copy would decode as garbage rather than as "unreachable".
        do {
            try bytes.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public static func write(_ bytes: Data) -> Bool {
        guard let dir = directory() else { return false }
        return write(bytes, in: dir)
    }

    public static func read(in dir: URL) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent(fileName))
    }

    public static func read() -> Data? {
        guard let dir = directory() else { return nil }
        return read(in: dir)
    }

    public static func clear(in dir: URL) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
    }

    public static func clear() {
        guard let dir = directory() else { return }
        clear(in: dir)
    }
}
