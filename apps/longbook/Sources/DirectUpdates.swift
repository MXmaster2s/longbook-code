import Foundation
#if DIRECT
import Sparkle
#endif

/// Sparkle, for the direct Mac build: it reads longbook.app/appcast.xml, checks each download's
/// EdDSA signature against SUPublicEDKey, and installs through its XPC installer. The App Store
/// build compiles none of it; every entry point does nothing there.
@MainActor
enum DirectUpdates {
    /// The value project.yml leaves until the release script writes the real key.
    static let placeholderKey = "LONGBOOK_SPARKLE_PUBLIC_KEY"

    /// A copy built without the key would refuse every update, so its updater never starts.
    static var keyed: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && key != placeholderKey
    }

    #if DIRECT
    private static var controller: SPUStandardUpdaterController?
    #endif

    /// At launch: starts the updater with General's switch as its automatic-check setting.
    static func start() {
        #if DIRECT
        guard controller == nil, keyed else { return }
        let made = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        made.updater.automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: AppUpdates.automaticKey) as? Bool ?? true
        controller = made
        #endif
    }

    /// Check for Updates…: Sparkle's own window says what it found and offers the install.
    static func check() {
        #if DIRECT
        start()
        controller?.checkForUpdates(nil)
        #endif
    }

    /// General's Check automatically switch, handed to Sparkle's daily schedule.
    static func setAutomatic(_ on: Bool) {
        #if DIRECT
        controller?.updater.automaticallyChecksForUpdates = on
        #endif
    }
}
