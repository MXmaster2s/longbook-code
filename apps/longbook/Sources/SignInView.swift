import DesignSystem
import LongbookCore
import SwiftUI

/// The first screen anyone sees, and the only way in: the welcome and the sign-in in one
/// step, since longbook needs an account. The account holds identity and licence; the vault
/// itself stays in the owner's own folder.
struct SignInView: View {
    @ObservedObject var auth: AuthViewModel
    /// Shared with the licence step, so the mark keeps its place between the two.
    var namespace: Namespace.ID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage {
        case welcome, email, code
    }

    @State private var stage: Stage = .welcome
    @State private var typedEmail = ""
    @State private var typedCode = ""
    @State private var busy = false
    @State private var error: String?
    /// Set beside `error` when the hourly cap on codes is what stopped the sign-in.
    @State private var feedback: URL?
    @State private var resendCooldown = 0
    @State private var opening: AuthViewModel.Provider?
    /// The step a failure is counted under.
    @State private var attempt: Telemetry.Place = .signInEmailSend
    /// The account the longbook already on this machine was last opened with. Read once,
    /// before anyone signs in — the folder is local, so this needs no account to find.
    @State private var folderAccount: String?
    @State private var confirmingFolderAccount = false

    private static let folderAccountTitle = "There’s already a longbook on this device."

    /// "Last opened by", not "belongs to": nothing stops another address opening it, and
    /// the sidecar only ever knew who came last.
    private static func folderAccountDetail(_ address: String) -> String {
        "It was last opened by \(address). Sign in with that address to keep everything on one account."
    }

    var body: some View {
        ZStack {
            if stage == .welcome {
                welcome
                    .transition(OnboardingMotion.push(reduceMotion: reduceMotion))
            } else {
                ScrollView {
                    VStack(spacing: LBSpacing.s4) {
                        if stage == .email { emailStep } else { codeStep }
                    }
                    .padding(LBSpacing.s4)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
                }
                .transition(OnboardingMotion.push(reduceMotion: reduceMotion))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : OnboardingMotion.step, value: stage)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        // Raised from the email door, where the typed address can be compared with the
        // folder's. Apple and Google name the address only after their own sheet, so those
        // two still carry the note rather than a question.
        .measured("sign_in_confirming_folder_account", .dialog, when: confirmingFolderAccount)
        .confirmationDialog(Self.folderAccountTitle, isPresented: $confirmingFolderAccount, titleVisibility: .visible) {
            Button("Continue") { Measure.used("continue"); Task { await send(confirmed: true) } }
            Button("Cancel", role: .cancel) { Measure.used("cancel") }
        } message: {
            if let folderAccount {
                Text(Self.folderAccountDetail(folderAccount))
            }
        }
        // A sign-in that failed, counted by its step and the provider's fixed code: what it
        // said is never sent.
        .onChange(of: error) { _, said in
            if said != nil { Telemetry.shared.failed(attempt, kind: .auth, auth.lastFailure) }
        }
        .task {
            guard folderAccount == nil else { return }
            folderAccount = await Task.detached(priority: .userInitiated) {
                VaultSource.resolve().flatMap { WorkspaceStore.read(in: $0).accountEmail }
            }.value
        }
    }

    // MARK: welcome

    private var welcome: some View {
        OnboardingStep(dot: 0, namespace: namespace) {
            OnboardingWords(title: "longbook", line: "Thank you for installing longbook",
                            note: "Keep your bank statement ready", noteInk: LBColor.danger, noteStrong: true)
            folderAccountNote
        } actions: {
            // Apple's door on both: the Mac build carries the applesignin entitlement too.
            appleButton
            providerRow(.google, Image("GoogleMark").resizable(), "Continue with Google")
            providerRow(nil, Image(systemName: "envelope"), "Continue with Email")
            errorNote
            // The folder opens under any address — it is a folder on this Mac, not an
            // account's property. What a second address costs is a second ACCOUNT, and
            // that is what the reader has to be steered away from.
            note(folderAccount == nil
                 ? "Signing in creates your account if you don’t have one yet."
                 : "Another address signs you into a second account. The commitments in this folder open either way.")
        }
    }

    /// Apple's door first and filled, in Apple's own black (white in dark mode).
    private var appleButton: some View {
        Button {
            Measure.used("apple_logo")
            Task { await continueWith(.apple) }
        } label: {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: "apple.logo").font(.system(size: 16, weight: .medium))
                Text(opening == .apple ? "Opening…" : "Continue with Apple").lbText(.body).fontWeight(.medium)
            }
            .foregroundStyle(LBColor.canvas.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LBSpacing.s3)
            .background(LBColor.textPrimary.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .contentShape(Rectangle())
            .opacity(opening == nil || opening == .apple ? 1 : 0.5)
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(opening != nil)
        .accessibilityLabel(opening == .apple ? "Opening…" : "Continue with Apple")
    }

    /// The same two providers, each on its own native flow: Apple's system sheet, and
    /// Google's SDK. No browser session, so no third-party domain in the consent ask.
    /// A nil provider is the email door, which opens the address step instead of a sheet.
    private func providerRow(_ provider: AuthViewModel.Provider?, _ mark: Image, _ title: String) -> some View {
        Button {
            Measure.used("sign_in_provider")
            if let provider {
                Task { await continueWith(provider) }
            } else {
                clearError()
                stage = .email
            }
        } label: {
            HStack(spacing: LBSpacing.s2) {
                mark
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(LBColor.textSecondary.color)
                Text(provider != nil && opening == provider ? "Opening…" : title)
                    .lbText(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LBSpacing.s4)
            .padding(.vertical, LBSpacing.s3)
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                    .strokeBorder(LBColor.hairline.color, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(opening == nil || opening == provider ? 1 : 0.5)
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(opening != nil)
        .accessibilityLabel(provider != nil && opening == provider ? "Opening…" : title)
    }

    private func continueWith(_ provider: AuthViewModel.Provider) async {
        opening = provider
        attempt = provider == .apple ? .signInApple : .signInGoogle
        clearError()
        // Nothing to do on success: the auth watcher publishes the session and the gate above
        // this view swaps the screen.
        switch provider {
        case .apple: error = await auth.signInWithApple()
        case .google: error = await GoogleNative.signIn(auth: auth)
        }
        opening = nil
    }

    // MARK: email and code

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            backButton { stage = .welcome }
            heading("envelope", "Continue with email", "We’ll send a code to your inbox.")
            field(placeholder: "you@example.com", text: $typedEmail, code: false)
            errorNote
            primaryButton(busy ? "Sending…" : "Send me a code", enabled: looksLikeEmail && !busy) {
                Task { await send() }
            }
            note("Signing in creates your account if you don’t have one yet.")
            Spacer(minLength: LBSpacing.s8)
        }
        .frame(maxWidth: .infinity)
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            backButton { stage = .email; typedCode = ""; clearError() }
            // App Review's account is sent nothing: its code is the one App Store Connect gives.
            isReviewAccount(typedEmail)
                ? heading("number", "Enter your code", "Type the code given for \(typedEmail).")
                : heading("number", "Check your email", "We sent a code to \(typedEmail). It expires shortly.")
            field(placeholder: "Enter code", text: $typedCode, code: true)
            errorNote
            primaryButton(busy ? "Checking…" : "Verify and continue", enabled: codeLooksComplete && !busy) {
                Task { await verify() }
            }
            HStack(spacing: LBSpacing.s4) {
                Button { Measure.used("resend_in_s"); Task { await send(resending: true) } } label: {
                    Text(resendCooldown > 0 ? "Resend in \(resendCooldown)s" : "Send Another Code")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.brandText.color)
                        .padding(.vertical, LBSpacing.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OnboardingPressStyle())
                .disabled(busy || resendCooldown > 0)
                Button { Measure.used("use_a_different_email"); stage = .email; typedCode = ""; clearError() } label: {
                    Text("Use a Different Email")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.brandText.color)
                        .padding(.vertical, LBSpacing.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OnboardingPressStyle())
            }
            Spacer(minLength: LBSpacing.s8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: pieces

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("arrow_left"); action() }) {
            Image(systemName: "arrow.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LBColor.textSecondary.color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPressStyle())
        .accessibilityLabel("Go back")
    }

    private func heading(_ symbol: String, _ title: String, _ note: String) -> some View {
        VStack(spacing: LBSpacing.s2) {
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .fill(LBColor.brand.color.opacity(0.18))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LBColor.brandText.color)
                )
                .accessibilityHidden(true)
            Text(title)
                .lbText(.title)
                .foregroundStyle(LBColor.textPrimary.color)
            Text(note)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textTertiary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, LBSpacing.s2)
    }

    @ViewBuilder
    private func field(placeholder: String, text: Binding<String>, code: Bool) -> some View {
        let entry = TextField("", text: text, prompt: Text(placeholder).foregroundStyle(LBColor.textTertiary.color))
            .textFieldStyle(.plain)
            .lbText(.body)
            .foregroundStyle(LBColor.textPrimary.color)
            .accessibilityLabel(code ? "Verification code" : "Email address")
        Group {
            #if os(iOS)
            entry
                .keyboardType(code ? .numberPad : .emailAddress)
                .textContentType(code ? .oneTimeCode : .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            #else
            entry
                .textContentType(code ? .oneTimeCode : nil)
            #endif
        }
        .padding(.horizontal, LBSpacing.s3)
        .padding(.vertical, LBSpacing.s3)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("sign_in_primary"); action() }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(enabled ? LBColor.onBrand.color : LBColor.textTertiary.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LBSpacing.s3)
                .background(
                    enabled ? LBColor.brand.color : LBColor.chrome.color,
                    in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                )
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(!enabled)
    }

    @ViewBuilder
    private var errorNote: some View {
        if let error {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text(error)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.urgent.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let feedback {
                    Link("Give feedback", destination: feedback).lbLinkPointer()
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.brandText.color)
                }
            }
        }
    }

    private func clearError() {
        error = nil
        feedback = nil
    }

    /// What this machine already holds, said before anyone types an address.
    @ViewBuilder
    private var folderAccountNote: some View {
        if let folderAccount {
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                Text(Self.folderAccountTitle)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text(Self.folderAccountDetail(folderAccount))
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LBSpacing.s3)
            .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: actions

    /// Deliberately loose: the server is the real judge of an address, and a strict pattern
    /// here would only lock someone out of their own account.
    private var looksLikeEmail: Bool {
        let trimmed = typedEmail.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        return trimmed[at...].contains(".") && !trimmed.hasSuffix(".")
    }

    /// Trimmed, unlike the field's raw text: macOS has no numberpad mask, so a pasted
    /// code with stray whitespace must still count correctly against the floor.
    private var codeLooksComplete: Bool {
        typedCode.trimmingCharacters(in: .whitespaces).count >= 6
    }

    private func send(resending: Bool = false, confirmed: Bool = false) async {
        let address = typedEmail.trimmingCharacters(in: .whitespaces)
        // The folder on this device was last opened by someone; signing in as anyone else
        // adopts it into their account. Asked here, where the address is finally known, so
        // the question is only put to the person it is actually about.
        if !confirmed, !resending, let existing = folderAccount,
           existing.localizedCaseInsensitiveCompare(address) != .orderedSame {
            confirmingFolderAccount = true
            return
        }
        busy = true
        attempt = .signInEmailSend
        clearError()
        let failure = await auth.signInWithEmail(address)
        busy = false
        if let failure {
            error = failure.message
            feedback = failure.hourlyLimit ? FeedbackMail.signInLimit : nil
            return
        }
        typedEmail = address
        stage = .code
        if resending {
            // A stale code must not survive its own replacement — the old digits would
            // otherwise sit in the field looking exactly as valid as the new ones.
            typedCode = ""
            startResendCooldown()
        } else {
            resendCooldown = 0
        }
    }

    /// A running countdown is stronger proof a tap landed than a label that silently
    /// reverts, and it keeps repeat taps from ever reaching the server's own rate limit.
    private func startResendCooldown() {
        resendCooldown = 30
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendCooldown -= 1
            }
        }
    }

    private func verify() async {
        busy = true
        attempt = .signInEmailCode
        clearError()
        let code = typedCode.trimmingCharacters(in: .whitespaces)
        // Success needs no navigation: the auth watcher publishes the session and the gate
        // above this view swaps the screen.
        error = await auth.verifyEmailOTP(typedEmail, token: code)
        busy = false
    }
}
