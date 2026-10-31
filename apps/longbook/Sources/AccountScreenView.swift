import DesignSystem
import LongbookCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The owner's picture in a circle: the photo a Google sign-in carries, or the email's
/// initial on a tinted circle when there is none or it does not load. Decorative, since
/// the email beside it is the name.
struct AccountAvatar: View {
    let url: URL?
    let email: String?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        // Still loading, or it failed: the initial stands in either way.
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Circle()
            .fill(LBColor.brand.color.opacity(0.18))
            .overlay {
                if let letter = email?.first {
                    Text(String(letter).uppercased())
                        .lbText(.screenTitle)
                        .foregroundStyle(LBColor.brandText.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                }
            }
    }
}

/// The one account screen: who is signed in, the plan and its purchase, longbook Cloud,
/// then the ways out, with deleting last. Account details and Billing both open here. The
/// direct Mac build manages and refunds its purchase through longbook.app and Support.
struct AccountScreenView: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    /// The plan, purchase and Cloud alone, for the Mac's Settings window, whose pane holds the rest.
    var planOnly = false
    @ObservedObject private var store = StoreClient.shared
    @ObservedObject private var direct = DirectStore.shared
    @State private var deleting = false
    @State private var paywall = false
    @State private var enteringKey = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var signingOut = false
    @State private var refund: (id: UInt64, closes: Date)?
    @State private var refunding = false

    /// The price, the buy button and what follows a purchase all wait on the same flag.
    private var canBuy: Bool {
        TrialRibbon.purchasable && !entitlement.state.hasLicence
    }

    /// Subscribed as the server holds it: active or in grace with time left. The trial
    /// covers Cloud without being a subscription, so the door to one stays open.
    private var subscribed: Bool {
        EntitlementState.cloud(status: entitlement.state.cloudStatus, expiresAt: entitlement.state.cloudExpiresAt, trialEndsAt: nil)
    }

    /// Cloud granted by hand: served, with neither a subscription nor a trial behind it.
    /// There is nothing to buy or manage, so the card says so instead of offering a door.
    private var granted: Bool {
        let state = entitlement.state
        let inTrial = state.trialEndsAt.map { $0 > Date() } ?? false
        return state.signedIn && state.hasCloud && !subscribed && !inTrial
    }

    var body: some View {
        SettingsScreen(title: "Account", note: "") {
            if !planOnly { identity }
            plan
            if canBuy { purchase }
            cloud
            if !planOnly { actions }
        }
        .task { if Distribution.current == .appStore { await store.load() } }
        .task(id: entitlement.state.hasLicence) {
            guard Distribution.current == .appStore else { return }
            refund = entitlement.state.hasLicence ? await store.refundable() : nil
        }
        .cloudPaywall(isPresented: $paywall, auth: auth)
        .measured("licence_key", .sheet, when: enteringKey)
        .sheet(isPresented: $enteringKey) {
            LicenceKeySheet(auth: auth, entitlement: entitlement) { enteringKey = false }
        }
    }

    // MARK: identity

    @ViewBuilder
    private var identity: some View {
        LBCard {
            HStack(spacing: LBSpacing.s3) {
                AccountAvatar(url: auth.avatarURL, email: auth.email, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    // Signed in with no address on file reads as that, not as a blank.
                    Text(auth.email ?? "Signed in")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if auth.email != nil {
                        Text("Signed in on this device")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
        Text("Your account holds your purchase and Cloud subscription. Your longbook stays in your folder, and a copy is uploaded only while AI access is on.")
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: plan

    /// The plan row waits for a value: a row that says "Not known yet" says nothing.
    @ViewBuilder
    private var plan: some View {
        if let words = planWords(entitlement.state) {
            LBSectionHeader("Plan")
            LBCard {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    FactRow(label: "Plan", value: words.0, tone: words.1)
                    if let ends = entitlement.state.trialEndsAt, !entitlement.state.hasLicence {
                        FactRow(label: "Trial ends", value: LB.longDate(ends))
                    }
                }
            }
        }
        if Distribution.current == .direct, entitlement.state.hasLicence { directPurchase }
        if let refund {
            // The 7-day refund, the terms' promise: Apple's own refund sheet, two taps away.
            Button { Measure.used("request_a_refund"); refunding = true } label: {
                Text("Request a Refund")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .refundRequestSheet(for: refund.id, isPresented: $refunding) { _ in
                Task { await entitlement.refresh() }
            }
            Text("Within \(StoreClient.refundDays) days of buying, until \(LB.longDate(refund.closes)). Apple makes the refund, and the licence ends when it does.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The direct build's purchase: Polar's portal holds the order and receipts; a refund is
    /// asked of Support, since no App Store sheet exists for it.
    @ViewBuilder
    private var directPurchase: some View {
        Button {
            Measure.used("manage_purchase")
            Task { await direct.managePurchase(auth: auth) }
        } label: {
            Text(direct.busy ? "Opening…" : "Manage purchase")
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(direct.busy)
        if let failure = direct.failure {
            Text(failure)
                .lbText(.footnote)
                .foregroundStyle(LBColor.urgent.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button { Measure.used("request_a_refund"); askSupport() } label: {
            Text("Request a Refund")
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        Text("Within \(StoreClient.refundDays) days of buying. Support arranges the refund, and the licence ends when it does.")
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Support opens over the main window, which this screen may sit beside in Settings.
    private func askSupport() {
        #if os(macOS)
        openWindow(id: LongbookWindow.main)
        NSApp.activate(ignoringOtherApps: true)
        #endif
        SupportCenter.shared.open()
    }

    @ViewBuilder
    private var purchase: some View {
        BuyButton(auth: auth, entitlement: entitlement, fullWidth: true)
        if Distribution.current == .direct {
            Button { Measure.used("licence_key"); enteringKey = true } label: {
                Text("I have a licence key")
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            Text("One purchase, not a subscription, for every platform. The receipt comes by email.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            appStorePurchase
        }
    }

    @ViewBuilder
    private var appStorePurchase: some View {
        // The App Store's own way back: a purchase made on another device or before
        // a reinstall is told to the server again.
        Button {
            Measure.used("checking")
            Task { await store.restore(auth: auth, entitlement: entitlement) }
        } label: {
            Text(store.busy ? "Checking…" : "Restore Purchase")
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(store.busy)
        Text(StoreClient.restoreWords)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
        Text("One purchase, not a subscription, for every platform. Receipts are in your App Store purchase history.")
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Cloud

    /// Cloud's standing, its date, and the door: subscribe, or manage what is already paid.
    /// The paywall sheet carries the full terms; this card states the facts.
    @ViewBuilder
    private var cloud: some View {
        LBSectionHeader("longbook Cloud")
        if let words = cloudWords(entitlement.state) {
            LBCard {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    FactRow(label: "Cloud", value: words.0, tone: words.1)
                    if let line = cloudDateLine(entitlement.state) {
                        FactRow(label: line.0, value: line.1)
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if Distribution.current == .direct {
                bullet(CloudPaywallView.directWords)
            } else {
                bullet("\(store.cloudDisplayPrice ?? "USD 4") \(store.cloudPeriodWords), through the App Store. Buying the licence includes the first 12 months.")
            }
            bullet("Covers the hosted copy for your AI, more statement reading and shared reports. The app and your folder need no Cloud.")
        }
        if granted {
            Text(entitlement.state.hasLicence
                 ? "Cloud comes with your licence for its first 12 months, so there is nothing to subscribe to yet."
                 : "Cloud is granted to this account, so there is nothing to subscribe to.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
        } else if Distribution.current == .appStore {
            cloudButton
        }
    }

    private var cloudButton: some View {
        Button {
            Measure.used("manage_longbook_cloud")
            paywall = true
        } label: {
            Text(subscribed ? "Manage longbook Cloud" : "Subscribe to longbook Cloud")
                .lbText(.label)
                .foregroundStyle(subscribed ? LBColor.brandText.color : LBColor.onBrand.color)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, LBSpacing.s3)
                .padding(.vertical, LBSpacing.s3)
                .background(
                    subscribed ? LBColor.chrome.color : LBColor.brand.color,
                    in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }

    // MARK: actions

    @ViewBuilder
    private var actions: some View {
        signOutButton
        // The account is deletable from inside the app because signing in is the only way
        // in: an account someone cannot leave is one they were never free to make. It sits
        // apart from Sign out so the two are not one tap's distance from each other.
        Button { Measure.used("delete_account"); deleting = true } label: {
            Text("Delete Account…")
                .lbText(.label)
                .foregroundStyle(LBColor.danger.color)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(LBColor.chrome.color, in: Capsule())
                .contentShape(Capsule())
        }
        .lbButtonStyle()
        .padding(.top, LBSpacing.s6)
        .measured("account_screen_deleting", .sheet, when: deleting)
        .sheet(isPresented: $deleting) {
            DeleteAccountSheet(auth: auth) { deleting = false }
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
                #endif
        }
    }

    /// A plain way to the sign-out screen, which asks which sessions to end. The Mac opens it
    /// over the Settings window, which has no stack to push it on.
    @ViewBuilder
    private var signOutButton: some View {
        #if os(macOS)
        Button { Measure.used("sign_out"); signingOut = true } label: { plainLabel("Sign Out…") }
            .lbButtonStyle()
            .measured("account_screen_signing_out", .sheet, when: signingOut)
            .sheet(isPresented: $signingOut) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Done") { Measure.used("done"); signingOut = false }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(LBSpacing.s3)
                    SignOutScreenView(auth: auth)
                }
                .frame(minWidth: 520, minHeight: 520)
                .background(LBColor.canvas.color)
            }
        #else
        NavigationLink(value: Destination.signOut) { plainLabel("Sign out") }
            .lbButtonStyle()
        #endif
    }

    private func plainLabel(_ title: String) -> some View {
        Text(title)
            .lbText(.label)
            .foregroundStyle(LBColor.textPrimary.color)
            .padding(.horizontal, LBSpacing.s4)
            .frame(minHeight: 34)
            .background(LBColor.chrome.color, in: Capsule())
            .contentShape(Capsule())
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
}
