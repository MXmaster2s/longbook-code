import Foundation

/// A folder the owner picked once, remembered as a security-scoped bookmark so the app can
/// reach it again after a relaunch. App-local, never vault data: which folder this device
/// opens is a fact about the device.
enum VaultBookmark {
    private static let key = "longbook.vaultBookmark"

    static func save(_ folder: URL) {
        // The picker hands back a scoped URL; the bookmark must be minted while that access
        // is held, or it resolves to nothing next launch.
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? folder.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Nil when nothing was picked, or when the folder has since moved or been deleted —
    /// a stale bookmark is forgotten rather than reported as a vault that won't open.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        if stale { save(url) }
        return url
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
