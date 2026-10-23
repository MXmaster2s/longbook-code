import SwiftUI

/// The reader's appearance choice. Dark is the authored canvas and stays the default;
/// system defers to the device. Stored per device — an appearance is how this screen
/// reads, not a fact about the money.
enum LBAppearance: String, CaseIterable {
    case dark
    case light
    case system

    /// nil means "follow the device", which is what preferredColorScheme(nil) does.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }
}

#if os(iOS)
import UIKit

extension LBAppearance {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: .unspecified
        }
    }

    /// Sets every window of the app to the choice at once. SwiftUI's own override can keep
    /// the old style until a relaunch, above all when going back to the system's.
    @MainActor
    static func applyToWindows(_ raw: String) {
        let style = (LBAppearance(rawValue: raw) ?? .system).interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
#endif
