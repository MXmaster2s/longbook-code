import Foundation
import LongbookCore
import StoreKit
#if os(macOS)
import AppKit
#endif

/// Where this copy's next version comes from, and the words that say so. The App Store looks
/// after an App Store install; TestFlight after a beta or a build from Xcode. The app only opens
/// that page — it never fetches or installs anything itself.
enum AppUpdates {
    /// The App Store Connect record's Apple ID, the number in the store's URL.
    static let appStoreID = "6795070908"
    static let testFlightLink = URL(string: "https://testflight.apple.com/join/g66Nd3Na")!

    enum Place {
        case appStore, testFlight
    }

    /// "Version 1.3.3 (18)", as this copy's bundle states it.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    /// Only a signed App Store install reads as the App Store's; anything else, or no answer,
    /// is TestFlight's.
    static func place() async -> Place {
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result else { return .testFlight }
        return transaction.environment == .production ? .appStore : .testFlight
    }

    static func url(for place: Place) -> URL {
        switch place {
        case .appStore:
            #if os(macOS)
            return URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)")!
            #else
            return URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)")!
            #endif
        case .testFlight:
            return testFlightLink
        }
    }

    static let title = "Check for Updates"

    /// The phone's App Store does the updating, so its screen is named for what it shows.
    static var screenTitle: String {
        #if os(iOS)
        "What’s new"
        #else
        title
        #endif
    }

    /// Every version's changes, from the changelog.json the app ships, newest first.
    static let releases: [Release] = {
        guard let url = Bundle.main.url(forResource: "changelog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return ReleaseNotes.decode(data) ?? []
    }()

    /// This copy's entry, by the version its bundle states.
    static var currentRelease: Release? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return ReleaseNotes.current(in: releases, version: version)
    }

    static func message(for place: Place) -> String {
        switch place {
        case .appStore: "Opens the App Store, which installs the latest version of longbook."
        case .testFlight: "Opens TestFlight, which installs the latest build of longbook."
        }
    }

    static func button(for place: Place) -> String {
        place == .appStore ? "Open App Store" : "Open TestFlight"
    }

    #if os(macOS)
    /// General's Check for updates automatically switch, on unless turned off.
    static let automaticKey = "longbook.updates.automatic"
    private static let lastCheckKey = "longbook.updates.lastCheck"

    /// While the switch is on, at most once a day: an App Store copy asks the store for its
    /// version and, when a newer one is out, says so in the menu item's alert. TestFlight has
    /// no such answer, so a TestFlight copy is never asked.
    @MainActor
    static func checkIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: automaticKey) as? Bool ?? true else { return }
        if let last = defaults.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        defaults.set(Date(), forKey: lastCheckKey)
        Task { @MainActor in
            guard await place() == .appStore, let latest = await storeVersion() else { return }
            let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            if isNewer(latest, than: installed) { askFromMenu(headline: "A newer version of longbook is out") }
        }
    }

    /// The store's current version for this app, from Apple's public lookup; nil on any failure.
    private static func storeVersion() async -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreID)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (object["results"] as? [[String: Any]])?.first else { return nil }
        return first["version"] as? String
    }

    /// Dotted numbers compared part by part, so 1.10.0 is newer than 1.9.2.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        WhatsNew.isNewer(candidate, than: installed)
    }

    /// The menu item's route: the same question as the Settings row, asked in an alert, since a
    /// command has no view of its own to present one from.
    @MainActor
    static func askFromMenu(headline: String = title) {
        Task { @MainActor in
            let place = await place()
            let alert = NSAlert()
            alert.messageText = headline
            let changes = currentRelease.map { "\n\nWhat’s new in \($0.version):\n" + UpdatesView.shown($0.changes).map { "• " + $0 }.joined(separator: "\n") } ?? ""
            alert.informativeText = versionLine + " is on this Mac." + changes + "\n\n" + message(for: place)
            alert.addButton(withTitle: button(for: place))
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url(for: place))
            }
        }
    }
    #endif
}
