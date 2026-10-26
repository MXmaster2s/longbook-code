import DesignSystem
import LongbookCore
import SwiftUI

/// The visible half of the read-only gate: quiet until the last three days, then permanent
/// once the trial has run out. Nothing is ever hidden when it does — everything stays
/// readable and exportable, only new writing stops, and the door to buy stands beside it.
struct TrialRibbon: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    @State private var dismissed = false

    private var state: EntitlementState { entitlement.state }

    private static let warnWithinDays = 3

    /// A lapsed trial stops new writing: the refusals in DashboardModel, ChangesView and
    /// VaultStore, and the permanent sentence here, all read this.
    static let enforced = true

    /// The App Store stands behind the door on both platforms — apple-purchase binds the
    /// purchase to the signed-in account. Billing's price and both buy controls read this.
    static let purchasable = true

    private var locked: Bool { state.readOnly && Self.enforced }

    var body: some View {
        if let words {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: locked ? "lock" : "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(locked ? LBColor.urgent.color : LBColor.brandText.color)
                Text(words)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: LBSpacing.s2)
                if Self.purchasable {
                    BuyButton(auth: auth, entitlement: entitlement)
                }
                if !locked {
                    Button { Measure.used("dismiss_ribbon"); dismissed = true } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LBColor.textQuaternary.color)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .lbButtonStyle()
                    .accessibilityLabel("Dismiss")
                }
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.vertical, LBSpacing.s2)
            .background(LBColor.sunken.color)
            .overlay(alignment: .bottom) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
        }
    }

    private var words: String? {
        if locked {
            return "This account has no licence. Everything stays visible and exportable; nothing new can be added."
        }
        guard !dismissed, !state.readOnly, let days = state.trialDaysLeft(), days <= Self.warnWithinDays else { return nil }
        return days <= 1 ? "Your trial ends today." : "\(days) days left in your trial."
    }
}
