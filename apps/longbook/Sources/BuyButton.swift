import DesignSystem
import LongbookCore
import SwiftUI

/// The one door to a purchase, wherever it stands: the ribbon's capsule or Billing's
/// full-width button. The App Store sells the licence on both platforms; what went
/// wrong is said beneath the button rather than in an alert.
struct BuyButton: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    var fullWidth = false
    @ObservedObject private var store = StoreClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            Button(action: { Measure.used("buy"); buy() }) {
                Text(store.busy ? "Opening…" : label)
                    .lbText(fullWidth ? .body : .label)
                    .foregroundStyle(LBColor.onBrand.color)
                    .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: fullWidth ? 46 : nil)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, fullWidth ? 0 : 6)
                    .background(
                        LBColor.brand.color,
                        in: RoundedRectangle(cornerRadius: fullWidth ? LBRadius.sm : 999, style: .continuous)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(OnboardingPressStyle())
            .disabled(store.busy)
            if let failure = store.failure {
                Text(failure)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice = store.notice {
                Text(notice)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await store.load() }
    }

    /// The full-width door names the price as the App Store states it here; the ribbon's
    /// capsule has no room for it.
    private var label: String {
        guard fullWidth, let price = store.displayPrice else { return "Buy longbook" }
        return "Buy longbook — \(price)"
    }

    private func buy() {
        guard !store.busy else { return }
        Task { await store.buy(auth: auth, entitlement: entitlement) }
    }
}
