import Foundation
import LongbookCore
import StoreKit

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

extension Distribution {
    /// A verified answer, kept for the app's life: how a copy was installed never changes.
    @MainActor private static var testAnswer: Bool?

    /// Whether this copy unlocks with a test licence: an App Store build that StoreKit says runs
    /// in Apple's test environment. Unverified or unknown, it does not, and is asked again later.
    @MainActor static func acceptsTestLicences() async -> Bool {
        if let testAnswer { return testAnswer }
        guard current == .appStore else { return false }
        guard let result = try? await AppTransaction.shared, case .verified(let transaction) = result else { return false }
        let answer = EntitlementState.acceptsTestLicences(appStoreBuild: true, environment: transaction.environment.rawValue)
        testAnswer = answer
        return answer
    }
}
