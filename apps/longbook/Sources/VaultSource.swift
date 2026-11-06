import Foundation
import LongbookCore

/// Finds a vault folder to read.
///
/// The shipping answer is a folder the reader picks once, kept as a security-scoped
/// bookmark, with iCloud resolved through the ubiquity container. That arrives with
/// onboarding. Until then this resolves the locations a vault can already sit in.
enum VaultSource {
    static func resolve() -> URL? {
        for candidate in localCandidates() where isVault(candidate) {
            return candidate
        }
        // The app's own iCloud container — where the shipped iPhone app keeps the vault.
        // Resolving it touches disk, so it's consulted only after the local spots are empty.
        if let cloud = VaultContainer.vaultURL(), isVault(cloud) {
            return cloud
        }
        #if DEBUG && os(macOS)
        // Development only: the desktop path of the same container, for unsigned dev builds
        // that can't resolve it through the ubiquity API.
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~app~longbook/Documents")
        if isVault(desktop) { return desktop }
        #endif
        return nil
    }

    private static func localCandidates() -> [URL] {
        var found: [URL] = []

        // A folder the owner picked themselves wins: they said where it is, and no guess
        // of ours should override that.
        if let picked = VaultBookmark.resolve() {
            found.append(picked)
        }

        // A vault kept beside the app itself — the "on this device" placement.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            found.append(documents.appendingPathComponent("longbook"))
            found.append(documents)
        }

        #if DEBUG
        // Development only: an explicit folder wins over everything.
        if let path = ProcessInfo.processInfo.environment["LONGBOOK_VAULT_PATH"], !path.isEmpty {
            found.insert(URL(fileURLWithPath: path), at: 0)
        }
        #endif

        return found
    }

    /// A folder is a vault when it holds the data file. Checked by reading the directory
    /// rather than by `fileExists`, which answers yes for a name the process may not open.
    /// An iCloud file not yet on this device lists as ".name.icloud" — still the vault.
    private static func isVault(_ folder: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return names.contains(VaultReader.dataFile) || names.contains(".\(VaultReader.dataFile).icloud")
    }
}
