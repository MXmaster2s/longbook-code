// Where the vault folder is, remembered across launches and processes. iOS sandboxes
// file access, so the folder is remembered as a SECURITY-SCOPED BOOKMARK, surviving
// relaunches and moves unlike a stored path. Lives in an APP GROUP, not private
// defaults, since the widget is a separate process resolving the same folder.
import Foundation

public enum VaultLocation {
    /// Must match the `com.apple.security.application-groups` entitlement on BOTH targets.
    public static let appGroup = "group.app.longbook"

    private static let key = "vaultBookmark"

    /// The shared store, falling back to the app's own defaults if the group isn't available (a
    /// misconfigured entitlement). Falling back keeps the APP working — only the widget would go
    /// blank — which is the right way round for a failure nobody has noticed yet.
    private static var store: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var isSet: Bool { store.data(forKey: key) != nil || UserDefaults.standard.data(forKey: key) != nil }

    static func remember(_ url: URL) throws {
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        store.set(data, forKey: key)
    }

    /// Forgetting the folder also drops the widget's copy of it. They are one fact — where this
    /// phone's longbook is — and a copy that outlived the bookmark would leave the Home Screen
    /// quoting a vault the app no longer has.
    static func forget() {
        store.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        VaultMirror.clear()
    }

    /// The remembered folder, re-resolved. A bookmark the system reports as stale is rewritten
    /// rather than dropped — the folder moved, it didn't disappear, and silently forgetting it would
    /// send the owner back through the picker for no reason.
    static func resolve() -> URL? {
        migrateIfNeeded()
        guard let data = store.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale { try? remember(url) }
        return url
    }

    /// Before the widget existed, the bookmark lived in the app's private defaults. Anyone who picked
    /// a folder on an older build still has it there, and without this they'd be sent back through
    /// the picker by an update whose whole purpose was to ADD a widget.
    private static func migrateIfNeeded() {
        guard store.data(forKey: key) == nil,
              let old = UserDefaults.standard.data(forKey: key)
        else { return }
        store.set(old, forKey: key)
    }
}
