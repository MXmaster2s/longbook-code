import DesignSystem
import LongbookCore
import SwiftUI

/// Deleting the account, with room to stop: what goes and what stays, a copy of the longbook
/// to keep first, and the word DELETE typed before the button wakes. The copy leaves through
/// the system share sheet (Mail, Files, AirDrop), so it never passes through longbook's server.
struct DeleteAccountSheet: View {
    @ObservedObject var auth: AuthViewModel
    let onClose: () -> Void

    @State private var typed = ""
    @State private var busy = false
    @State private var error: String?

    private static let word = "DELETE"
    private var memoryFile: URL? {
        VaultSource.resolve().map { $0.appendingPathComponent(VaultReader.dataFile) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s6) {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    Text("Delete your account?")
                        .lbText(.displayLG)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text("This can’t be undone.")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
                facts("Removed for good", [
                    "Your sign-in and email address",
                    auth.signedInWithApple ? "Your Sign in with Apple link to longbook" : nil,
                    "The licence on this account",
                    "Your longbook Cloud copy and shared reports",
                ].compactMap { $0 })
                facts("Kept", [
                    "Your longbook folder in iCloud or on this device",
                    "A longbook Cloud subscription: cancel it in your Apple Account settings",
                ])
                if let memoryFile {
                    VStack(alignment: .leading, spacing: LBSpacing.s2) {
                        ShareLink(item: memoryFile) {
                            Label("Save a Copy of My longbook", systemImage: "square.and.arrow.up")
                                .lbText(.label)
                                .foregroundStyle(LBColor.brandText.color)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(LBColor.chrome.color, in: Capsule())
                        }
                        .lbButtonStyle()
                        Text("Send it to your own email, Files or AirDrop before you go.")
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textTertiary.color)
                    }
                }
                if auth.signedInWithApple {
                    Text("Apple asks you to confirm with Face ID first. Its sheet says Sign in with Apple; it only checks it’s you.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    Text("Type \(Self.word) to confirm")
                        .lbText(.label)
                        .foregroundStyle(LBColor.textSecondary.color)
                    TextField("", text: $typed, prompt: Text(Self.word).foregroundStyle(LBColor.textTertiary.color))
                        .textFieldStyle(.plain)
                        .lbText(.body)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .padding(LBSpacing.s3)
                        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
                }
                Button {
                    Measure.used("deleting")
                    busy = true
                    let leaving = auth.email
                    Task {
                        // An Apple account confirms with Apple first, so the server can end that
                        // link. A closed sheet keeps the account.
                        var confirmation: String?
                        if auth.signedInWithApple {
                            do {
                                confirmation = try await auth.appleDeletionCode()
                            } catch {
                                self.error = "Apple couldn’t confirm on this device. Try again."
                                busy = false
                                return
                            }
                            guard confirmation != nil else { busy = false; return }
                        }
                        // Forgotten before the sign-out: sign-in reads the folder as it appears.
                        error = await auth.deleteAccount(appleCode: confirmation, beforeSignOut: { forgetAccount(leaving) })
                        busy = false
                        guard error == nil else { return }
                        onClose()
                    }
                } label: {
                    Text(busy ? "Deleting…" : "Delete Account")
                        .lbText(.label)
                        .foregroundStyle(LBColor.onBrand.color)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LBColor.dangerFill.color, in: Capsule())
                        .opacity(confirmed && !busy ? 1 : 0.4)
                }
                .lbButtonStyle()
                .disabled(!confirmed || busy)
                if let error {
                    Text(error)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.danger.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Keep My Account", action: { Measure.used("keep_my_account"); onClose() })
                    .lbButtonStyle()
                    .lbText(.label)
                    .foregroundStyle(LBColor.brandText.color)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(LBSpacing.s6)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(LBColor.canvas.color)
    }

    /// The folder names the account that last opened it, for the next sign-in to see. A deleted
    /// account is no one to point to, so its address leaves the folder with it.
    private func forgetAccount(_ email: String?) {
        guard let email, let folder = VaultSource.resolve(),
              WorkspaceStore.read(in: folder).accountEmail?.lowercased() == email.lowercased() else { return }
        try? WorkspaceStore.update(in: folder) { $0.accountEmail = nil }
    }

    private var confirmed: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == Self.word
    }

    private func facts(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            Text(title)
                .lbText(.label)
                .foregroundStyle(LBColor.textSecondary.color)
            ForEach(lines, id: \.self) { line in
                Text("• \(line)")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
