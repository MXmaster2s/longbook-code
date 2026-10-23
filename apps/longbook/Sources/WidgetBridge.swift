// After a successful load, wake whichever glance surface this platform has: the widget on
// iOS, the menu-bar strip on macOS. The nudge fires only when the bytes CHANGED —
// "nothing changed" and "nothing to tell the glance" are the same answer.
import Foundation
import LongbookCore
#if os(iOS)
import WidgetKit
#endif

extension Notification.Name {
    /// The vault this process holds has changed. The menu-bar strip is in the same
    /// process as the window, so a notification is all it needs.
    static let longbookVaultDidChange = Notification.Name("longbookVaultDidChange")
}

enum WidgetBridge {
    #if os(macOS)
    /// What the menu bar was last told about. load() runs on far more than edits, and a
    /// re-read costs a file read on the main thread.
    private static var lastSeen: Data?
    #endif

    #if os(macOS)
    /// Which folder the copy was taken from. The tray quotes that copy when the vault
    /// cannot be read, and a figure from a folder the owner has since left is not an
    /// answer about the one they are looking at.
    private static let sourceKey = "longbook.mirrorSource"

    static var mirrorSource: String? {
        UserDefaults.standard.string(forKey: sourceKey)
    }
    #endif

    static func vaultDidLoad(_ bytes: Data, from folder: URL? = nil) {
        #if os(macOS)
        // The strip beside the clock is always on screen, so a figure left over from
        // before an edit is a wrong answer nobody had to ask for.
        if lastSeen != bytes {
            lastSeen = bytes
            // The Mac keeps a copy for the same reason the phone does: it is what the
            // menu bar falls back to when the vault itself cannot be read.
            VaultMirror.write(bytes)
            if let folder {
                UserDefaults.standard.set(folder.standardizedFileURL.path, forKey: sourceKey)
            }
            NotificationCenter.default.post(name: .longbookVaultDidChange, object: nil)
        }
        #endif
        #if os(iOS)
        // write() answers false both for identical bytes and for a nil group container
        // (a dropped entitlement) — either way there is no widget to wake. macOS has no
        // widget process at all, so the whole thing is a no-op there.
        if VaultMirror.write(bytes) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
