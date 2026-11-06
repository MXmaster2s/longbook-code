import Foundation
import StoreKit
import SwiftUI

/// Apple's own rating prompt, asked as Apple recommends: after a statement import is kept and
/// walked through to the Dashboard, from the second one on, never during setup, once a version.
/// Nothing asks how the person feels first; the system decides whether it shows.
@MainActor
enum RatingPrompt {
    private static let keptKey = "longbook.rating.importsKept"
    private static let askedVersionKey = "longbook.rating.askedVersion"
    /// Kept imports before the first ask; the first is often the one made during setup.
    static let importsBeforeAsking = 2

    /// An import was kept and its walk-through ended on the Dashboard. True when this is the
    /// moment to ask: enough imports kept, outside setup, and not yet asked in this version.
    static func importKept(duringSetup: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let kept = defaults.integer(forKey: keptKey) + 1
        defaults.set(kept, forKey: keptKey)
        guard !duringSetup, kept >= importsBeforeAsking,
              defaults.string(forKey: askedVersionKey) != AppVersion.marketing else { return false }
        defaults.set(AppVersion.marketing, forKey: askedVersionKey)
        return true
    }

    /// Asks once the Dashboard is in front, so the prompt never stands over the import's sheet.
    static func ask(_ requestReview: RequestReviewAction) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
    }
}
