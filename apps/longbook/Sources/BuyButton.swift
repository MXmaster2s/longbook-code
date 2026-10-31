import DesignSystem
import LongbookCore
import SwiftUI

/// The one door to a purchase, wherever it stands: the ribbon's capsule or Billing's
/// full-width button. The App Store sells the licence on both platforms; the direct Mac
/// build sends the buyer to longbook.app. What went wrong is said beneath the button.
struct BuyButton: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    var fullWidth = false
    @ObservedObject private var store = StoreClient.shared
    @ObservedObject private var direct = DirectStore.shared

    private var busy: Bool { Distribution.current == .direct ? direct.busy : store.busy }
    private var failure: String? { Distribution.current == .direct ? direct.failure : store.failure }
    private var notice: String? { Distribution.current == .direct ? nil : store.notice }

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            Button(action: { Measure.used("buy"); buy() }) {
                Text(busy ? "Opening…" : label)
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
            .disabled(busy)
            if let failure {
                Text(failure)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice {
                Text(notice)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { if Distribution.current == .appStore { await store.load() } }
    }

    /// The full-width door names the price as the App Store states it here; the ribbon's
    /// capsule has no room for it. The direct build names the website instead.
    private var label: String {
        if Distribution.current == .direct { return "Buy on longbook.app" }
        guard fullWidth, let price = store.displayPrice else { return "Buy longbook" }
        return "Buy longbook — \(price)"
    }

    private func buy() {
        guard !busy else { return }
        switch Distribution.current {
        case .appStore: Task { await store.buy(auth: auth, entitlement: entitlement) }
        case .direct: Task { await direct.buy(auth: auth) }
        }
    }
}
