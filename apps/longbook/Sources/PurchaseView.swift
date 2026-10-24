import DesignSystem
import LongbookCore
import SwiftUI

/// What an account without a licence sees instead of the app: longbook is bought before it is
/// used. "What’s included?" opens every promise the licence carries. A refunded or revoked
/// licence lands here too. The demo stays a tap away for a look before paying.
struct PurchaseView: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    /// Shared with sign-in, so the mark keeps its place between the two steps.
    var namespace: Namespace.ID? = nil
    @ObservedObject private var store = StoreClient.shared
    @State private var demo = false
    @State private var showingIncluded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        "Customer Support",
    ]

    var body: some View {
        OnboardingStep(dot: 1, namespace: namespace) {
            VStack(spacing: LBSpacing.s2) {
                Text("Activate your longbook")
                    .lbText(.displayLG)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("A one-time purchase for your iPhone & Mac.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            includedDisclosure
        } actions: {
            BuyButton(auth: auth, entitlement: entitlement, fullWidth: true)
            HStack(spacing: LBSpacing.s2) {
                OnboardingSecondaryButton(title: store.busy ? "Checking…" : "Restore Purchase") {
                    Task { await store.restore(auth: auth, entitlement: entitlement) }
                }
                .disabled(store.busy)
                OnboardingSecondaryButton(title: "See Demo") { demo = true }
            }
            HStack(spacing: LBSpacing.s1) {
                Link("Terms of Use", destination: Self.termsURL)
                Text("·")
                Link("Privacy Policy", destination: Self.privacyURL)
            }
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
        }
        // The account stays changeable before paying: the one way out sits where a sheet's is.
        .overlay(alignment: .topTrailing) {
            OnboardingTextButton(title: "Sign Out") { Task { await auth.signOut() } }
                .padding(.trailing, LBSpacing.s2)
                .padding(.top, LBSpacing.s2)
        }
        .task { await store.load() }
        .modifier(RootView.DemoCover(showing: $demo, auth: auth))
    }

    /// Closed, one line under the price; open, the promises drop in under it.
    private var includedDisclosure: some View {
        VStack(spacing: LBSpacing.s3) {
            Button {
                Measure.used("whats_included")
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : OnboardingMotion.reveal) { showingIncluded.toggle() }
            } label: {
                HStack(spacing: LBSpacing.s1) {
                    Text("What’s included?").lbText(.label)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showingIncluded ? 180 : 0))
                }
                .foregroundStyle(LBColor.brandText.color)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(OnboardingPressStyle())
            .accessibilityValue(showingIncluded ? "Open" : "Closed")
            if showingIncluded {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    ForEach(Self.included, id: \.self) { tick($0) }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func tick(_ words: String) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LBColor.brandText.color)
                .accessibilityHidden(true)
            Text(words)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
