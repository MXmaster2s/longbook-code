import DesignSystem
import LongbookCore
import SwiftUI

/// What an account without a licence sees instead of the app: longbook is bought before it is
/// used, so the screen leads with the 7-day refund, then what the licence includes. A refunded
/// or revoked licence lands here too. The demo stays a tap away for a look before paying.
struct PurchaseView: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    @ObservedObject private var store = StoreClient.shared
    @State private var demo = false
    /// The first three promises show; “and more” opens the rest.
    @State private var showingAll = false

    private static let termsURL = URL(string: "https://longbook.app/terms/")!
    private static let privacyURL = URL(string: "https://longbook.app/privacy-policy/")!

    /// The licence's promises, from the website's pricing card, short enough for one screen.
    private static let included = [
        "7-day Refund Policy",
        "Includes your iPhone and Mac",
        "Includes Family Sharing",
        "Built-in AI features",
        "Compatibility with your AI",
        "Ownership of your data in your iCloud",
        "Future updates and enhancements",
        "12 months of longbook Cloud",
    ]

    var body: some View {
        OnboardingScaffold(dot: 3, secondary: "Sign Out", onSecondary: { Task { await auth.signOut() } }) {
            BuyButton(auth: auth, entitlement: entitlement, fullWidth: true)
        } content: {
            VStack(spacing: LBSpacing.s6) {
                OnboardingTitle(title: "Activate your longbook", line: "A one-time purchase for your iPhone & Mac")
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    ForEach(Self.included.prefix(3), id: \.self) { tick($0) }
                    if showingAll {
                        ForEach(Self.included.dropFirst(3), id: \.self) { tick($0) }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        Button {
                            Measure.used("and_more")
                            withAnimation(.easeOut(duration: 0.3)) { showingAll = true }
                        } label: {
                            HStack(spacing: LBSpacing.s2) {
                                Text("and more").lbText(.body)
                                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(LBColor.brandText.color)
                            .padding(.leading, 30)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: LBSpacing.s2) {
                    plain(store.busy ? "Checking…" : "Restore Purchase") {
                        Task { await store.restore(auth: auth, entitlement: entitlement) }
                    }
                    .disabled(store.busy)
                    plain("See Demo") { demo = true }
                }
                HStack(spacing: LBSpacing.s4) {
                    Link("Terms of Use", destination: Self.termsURL)
                    Link("Privacy Policy", destination: Self.privacyURL)
                }
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
            }
        }
        .task { await store.load() }
        .modifier(RootView.DemoCover(showing: $demo, auth: auth))
    }

    private func tick(_ words: String) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LBColor.brandText.color)
                .accessibilityHidden(true)
            Text(words)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func plain(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("purchase_plain"); action() }) {
            Text(title)
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
