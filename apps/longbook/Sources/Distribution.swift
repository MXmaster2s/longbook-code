import Foundation

/// How this copy reached the Mac it runs on, fixed when it is compiled: the App Store build,
/// or the Developer ID build from longbook.app (the longbook-direct target, which sets DIRECT).
/// Purchases, refunds and updates each follow it.
enum Distribution: String {
    case appStore = "app_store"
    case direct

    #if DIRECT
    static let current = Distribution.direct
    #else
    static let current = Distribution.appStore
    #endif

    /// Sent with app.launched as `channel`.
    var channel: String { rawValue }
}
