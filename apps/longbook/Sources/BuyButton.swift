import DesignSystem
import LongbookCore
import SwiftUI

/// The one door to a purchase: the ribbon's capsule or Billing's full-width button. Both name
/// the App Store's price, or Try Again if it fails; with In-App Purchases off, it explains
/// instead. The direct Mac build opens longbook.app's checkout in the browser.
struct BuyButton: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    var fullWidth = false
    @ObservedObject private var store = StoreClient.shared
    @ObservedObject private var direct = DirectStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s1) {
            if Distribution.current == .direct {
                directButton
            } else if store.canMakePayments {
                button
                lines
            } else {
                PurchasesOffNote(compact: !fullWidth)
            }
        }
        .task { if Distribution.current == .appStore { await store.load() } }
    }

    @ViewBuilder
    private var directButton: some View {
        Button(action: { Measure.used("buy"); guard !direct.busy else { return }; Task { await direct.buy(auth: auth) } }) {
            capsule(direct.busy ? "Opening…" : "Buy longbook")
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(direct.busy)
        if let failure = direct.failure {
            Text(failure)
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func capsule(_ title: String) -> some View {
        Text(title)
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

    private var button: some View {
        Button(action: { Measure.used("buy"); tapped() }) {
            capsule(label)
                .opacity(store.loadState == .loading ? 0.6 : 1)
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(store.busy || store.loadState == .loading)
    }

    @ViewBuilder
    private var lines: some View {
        if let failure = store.failure {
            Text(failure)
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
                .fixedSize(horizontal: false, vertical: true)
        } else if store.loadState == .failed, fullWidth {
            Text(StoreClient.pricesFailedWords)
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

    /// Every purchase button names its price; there is none of longbook's own to show first.
    private var label: String {
        if store.busy { return "Opening…" }
        switch store.loadState {
        case .loading: return "Loading Price…"
        case .failed: return "Try Again"
        case .loaded:
            guard let price = store.displayPrice else { return "Try Again" }
            return fullWidth ? "Buy longbook — \(price)" : "Buy for \(price)"
        }
    }

    private func tapped() {
        guard !store.busy else { return }
        if store.loadState == .failed || store.displayPrice == nil {
            Task { await store.load() }
        } else {
            Task { await store.buy(auth: auth, entitlement: entitlement) }
        }
    }
}

/// What stands where a Buy or Subscribe button would, while Screen Time or a restriction
/// turns In-App Purchases off: why, and the two ways forward. Compact, one line for a ribbon.
struct PurchasesOffNote: View {
    var compact = false

    var body: some View {
        if compact {
            Text("Purchases are off")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .help(StoreClient.purchasesOffWords)
                .accessibilityHint(StoreClient.purchasesOffWords)
        } else {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text(StoreClient.purchasesOffTitle)
                    .lbText(.label)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(StoreClient.purchasesOffWords)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
