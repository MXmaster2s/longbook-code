import SwiftUI

#if os(iOS)
import UIKit
#endif

/// The dashboard's answer in the hand. One place for it, so the whole screen speaks in the
/// same voice, and one platform check, so no call site has to know that the Mac cannot feel.
enum LBHaptics {
    #if os(iOS)
    private static let engine = UIImpactFeedbackGenerator(style: .medium)
    #endif

    /// A module answering a tap — the lightest thing worth feeling.
    static func tap() {
        #if os(iOS)
        engine.impactOccurred(intensity: 0.45)
        #endif
    }

    /// A pull in progress, where `progress` is how much of the threshold has been spent:
    /// quiet while the effort is small, firm just before it becomes a decision.
    static func pull(_ progress: Double) {
        #if os(iOS)
        engine.impactOccurred(intensity: 0.3 + min(max(progress, 0), 1) * 0.5)
        #endif
    }

    /// A tap that cannot be answered: the month with nothing in it.
    static func warn() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// The moment the pull turns the rail.
    static func commit() {
        #if os(iOS)
        engine.impactOccurred(intensity: 1)
        #endif
    }
}

extension View {
    /// A tap on a dashboard module answers in the hand as well as on the screen. Kept as a
    /// simultaneous gesture so it rides alongside a button or a link instead of taking the
    /// tap from it.
    func lbTapHaptic() -> some View {
        simultaneousGesture(TapGesture().onEnded { LBHaptics.tap() })
    }
}
