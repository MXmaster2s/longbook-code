import DesignSystem
import LongbookCore
import StoreKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The door to longbook Cloud, opened wherever a server feature is asked for without it:
/// what it costs, how long it runs, what it covers, and the ways to subscribe, manage or
/// restore. The App Store sells it, at the store's own price. The direct Mac build sells no
/// subscription.
struct CloudPaywallView: View {
    @ObservedObject var auth: AuthViewModel
    @EnvironmentObject private var entitlement: EntitlementStore
    @ObservedObject private var store = StoreClient.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private static let termsURL = URL(string: "https://longbook.app/terms/")!
    private static let privacyURL = URL(string: "https://longbook.app/privacy-policy/")!
    /// Apple's own subscriptions page; the Mac has no in-app sheet for it.
    private static let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    /// What the direct build says in place of the subscribe button.
    static let directWords = "longbook Cloud is included for 12 months with your licence. Monthly Cloud on the Mac comes later."

    private var state: EntitlementState { entitlement.state }

    /// Subscribed, as the server holds it: active or in grace with time left. The trial
    /// covers Cloud but is not a subscription, so it still shows the way to one.
    private var subscribed: Bool {
        EntitlementState.cloud(status: state.cloudStatus, expiresAt: state.cloudExpiresAt, trialEndsAt: nil)
    }

    private var priceWords: String {
        "\(store.cloudDisplayPrice ?? "USD 4") \(store.cloudPeriodWords)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                VStack(alignment: .leading, spacing: LBSpacing.s1) {
                    Text("longbook Cloud")
                        .lbText(.screenTitle)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text("Everything in longbook that uses longbook’s server.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                facts
                covers
                actions
                legal
            }
            .padding(LBSpacing.s4)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LBColor.canvas.color)
        .task { if Distribution.current == .appStore { await store.load() } }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 480, minHeight: 600)
        #endif
        .lbClosesOnOutsideClick { dismiss() }
    }

    // MARK: what it is

    private var facts: some View {
        LBCard {
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                if Distribution.current == .appStore {
                    FactRow(label: "Price", value: priceWords)
                    FactRow(label: "Term", value: "Renews \(store.cloudEveryWords) until cancelled")
                }
                if let words = cloudWords(state) {
                    FactRow(label: "Status", value: words.0, tone: words.1)
                }
                if let line = cloudDateLine(state) {
                    FactRow(label: line.0, value: line.1)
                }
            }
        }
    }

    private var covers: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            LBSectionHeader("What it covers")
            bullet("A hosted copy of your longbook, so your AI can read and write it through the longbook MCP server.")
            bullet("More statement reading: bank statements read into charges on longbook’s server, several at a time, more of them each month.")
            bullet("Shared reports: a link and a password that open one report for a few days.")
            bullet("Your folder, the app and everything in it stay yours without Cloud. Your licence includes its first 12 months.")
        }
    }

    // MARK: the doors

    @ViewBuilder
    private var actions: some View {
        if Distribution.current == .direct {
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                Text(Self.directWords)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                quietButton("Done") { dismiss() }
            }
        } else {
            appStoreActions
        }
    }

    @ViewBuilder
    private var appStoreActions: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if subscribed {
                brandButton("Manage Subscription", action: manage)
            } else {
                brandButton(store.busy ? "Opening…" : "Subscribe for \(priceWords)") {
                    guard !store.busy else { return }
                    Task {
                        if await store.subscribe(auth: auth, entitlement: entitlement) { dismiss() }
                    }
                }
            }
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
            HStack(spacing: LBSpacing.s3) {
                quietButton(store.busy ? "Checking…" : "Restore Purchases") {
                    guard !store.busy else { return }
                    Task { await store.restore(auth: auth, entitlement: entitlement) }
                }
                quietButton("Not Now") { dismiss() }
            }
            Text(StoreClient.restoreWords)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if Distribution.current == .appStore {
                appleTerms
            }
            HStack(spacing: LBSpacing.s4) {
                link("Terms of service", Self.termsURL)
                link("Privacy policy", Self.privacyURL)
            }
        }
    }

    private var appleTerms: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text("Payment is charged to your Apple Account when the purchase is confirmed. The subscription renews automatically unless it is cancelled at least 24 hours before the end of the current period. Cancel at any time in your Apple ID subscription settings. Apple keeps the invoice.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: pieces

    /// The same manner as BuyButton's full-width door, for the subscription.
    private func brandButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("cloud_primary"); action() }) {
            Text(title)
                .lbText(.label)
                .foregroundStyle(LBColor.onBrand.color)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, LBSpacing.s3)
                .padding(.vertical, LBSpacing.s3)
                .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(store.busy)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("cloud_quiet"); action() }) {
            Text(title)
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }

    private func link(_ title: String, _ url: URL) -> some View {
        Button { Measure.used("arrow_up_right"); openURL(url) } label: {
            HStack(spacing: LBSpacing.s1) {
                Text(title)
                    .lbText(.footnote)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(LBColor.brandText.color)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s2) {
            Circle()
                .fill(LBColor.textQuaternary.color)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Apple's own management sheet on the phone; the Mac opens the account page instead.
    private func manage() {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
        #else
        openURL(Self.subscriptionsURL)
        #endif
    }
}

extension View {
    /// Presents the Cloud door as a sheet. The EntitlementStore comes through the
    /// environment, so a gate anywhere can open it with the account it already holds.
    func cloudPaywall(isPresented: Binding<Bool>, auth: AuthViewModel) -> some View {
        sheet(isPresented: isPresented) {
            CloudPaywallView(auth: auth)
        }
    }
}
