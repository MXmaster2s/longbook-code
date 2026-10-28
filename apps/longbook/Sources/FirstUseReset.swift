#if DEVICE_BUILD
import Foundation
import GoogleSignIn
import LongbookCore
import os
import Security
#if os(iOS)
import WidgetKit
#endif

/// Device builds only: device:install sets DEVICE_BUILD. `longbook://dev/first-use` puts this
/// install back to its first run, for `npm run clean:slate`. The iCloud vault is the tool's to
/// move; nothing here touches it. Shows nothing, logs one line, quits.
enum FirstUseReset {
    /// Searched for in the binary: the release scripts refuse an archive that carries it.
    static let marker = "longbook device build: first-use reset"

    static func handles(_ url: URL) -> Bool {
        url.scheme == "longbook" && url.host == "dev" && url.path == "/first-use"
    }

    @MainActor
    static func run() -> Never {
        GIDSignIn.sharedInstance.signOut()
        let settings = clearSettings()
        let files = clearFiles()
        let setAside = setDeviceVaultAside()
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // Last, right before the exit, so no token refresh can write the session back.
        let items = clearKeychain()
        Logger(subsystem: "app.longbook.longbook", category: "first-use").notice(
            "\(marker, privacy: .public): \(items) keychain items, \(settings) settings, \(files) files; device vault set aside: \(setAside)"
        )
        // exit, not terminate: quitting runs observers that write settings back.
        exit(0)
    }

    /// Every item the app can reach, in every access group it holds (the app group included):
    /// the session (app.longbook.session), the trial start (app.longbook.trial), Google's.
    private static func clearKeychain() -> Int {
        var removed = 0
        for itemClass in [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassKey, kSecClassCertificate] {
            var query: [String: Any] = [
                kSecClass as String: itemClass,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
            #endif
            var count = query
            count[kSecMatchLimit as String] = kSecMatchLimitAll
            count[kSecReturnAttributes as String] = true
            var found: CFTypeRef?
            if SecItemCopyMatching(count as CFDictionary, &found) == errSecSuccess { removed += (found as? [Any])?.count ?? 0 }
            SecItemDelete(query as CFDictionary)
        }
        #if os(macOS)
        // The access key sits in the login keychain on purpose, one item per key name.
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: KeyKeychain.service]
        var tries = 0
        while tries < 100, SecItemDelete(key as CFDictionary) == errSecSuccess {
            removed += 1
            tries += 1
        }
        #endif
        return removed
    }

    /// The app's own domain (folder bookmark, onboarding, tutorials, consents, telemetry id,
    /// entitlement cache) and the app group's (the bookmark the widget reads).
    private static func clearSettings() -> Int {
        var keys = 0
        if let id = Bundle.main.bundleIdentifier {
            keys += UserDefaults.standard.persistentDomain(forName: id)?.count ?? 0
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        if let group = UserDefaults(suiteName: VaultLocation.appGroup) {
            keys += group.persistentDomain(forName: VaultLocation.appGroup)?.count ?? 0
            group.removePersistentDomain(forName: VaultLocation.appGroup)
            group.synchronize()
        }
        UserDefaults.standard.synchronize()
        return keys
    }

    /// Caches, Application Support (the history mirror), web storage, saved window state and
    /// tmp (Support attachments, the demo longbook), then the widget's copy of the vault.
    private static func clearFiles() -> Int {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        #if os(macOS)
        // Outside the sandbox these folders would be every app's; only the container is ours.
        guard let id = Bundle.main.bundleIdentifier, home.hasSuffix("/Library/Containers/\(id)/Data") else { return 0 }
        #endif
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let folders = [
            fm.urls(for: .cachesDirectory, in: .userDomainMask)[0],
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            library.appendingPathComponent("HTTPStorages"),
            library.appendingPathComponent("Saved Application State"),
            fm.temporaryDirectory,
        ]
        var removed = 0
        for folder in folders where folder.standardizedFileURL.path.hasPrefix(home + "/") {
            for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                if (try? fm.removeItem(at: item)) != nil { removed += 1 }
            }
        }
        VaultMirror.clear()
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        return removed
    }

    /// A vault kept in the app's Documents is moved into Documents › longbook backups, never
    /// deleted, so the next launch does not find it.
    private static func setDeviceVaultAside() -> Bool {
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let isVault = { (folder: URL) in fm.fileExists(atPath: folder.appendingPathComponent(VaultReader.dataFile).path) }
        guard isVault(documents) || isVault(documents.appendingPathComponent("longbook")) else { return false }
        let backups = "longbook backups"
        let into = documents.appendingPathComponent(backups)
            .appendingPathComponent(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: ""))
        guard (try? fm.createDirectory(at: into, withIntermediateDirectories: true)) != nil else { return false }
        for name in (try? fm.contentsOfDirectory(atPath: documents.path)) ?? [] where name != backups {
            try? fm.moveItem(at: documents.appendingPathComponent(name), to: into.appendingPathComponent(name))
        }
        return true
    }
}
#endif
