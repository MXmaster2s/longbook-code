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
}
