import DesignSystem
import LongbookCore
import SwiftUI

/// The moment after sign-in when a reader has no longbook on this device yet: it is found
/// in iCloud or made there, with nothing to decide and nothing to wait for. Shown before
/// onboarding, so every later step has somewhere to save.
struct VaultChoiceView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @State private var pickingFolder = false

    var body: some View {
        layout
        // No longbook found: make one rather than ask. Creating adopts a longbook iCloud
        // already holds, so a returning reader's book is opened, never replaced.
        .task(id: checkedState != nil) {
            if checkedState != nil { model.createICloudVault() }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result {
                VaultBookmark.save(folder)
                model.load()
            }
        }
    }

    /// Without iCloud the screen takes the shared onboarding frame: keeping the longbook here is
    /// the main button, trying iCloud again the quiet one. Every other state keeps the column.
    @ViewBuilder
    private var layout: some View {
        if case .unavailable(let message) = model.state {
            OnboardingScaffold(secondary: "Try iCloud Again", onSecondary: { model.load() }) {
                OnboardingPrimaryButton(title: Self.keepHere) { model.createLocalVault() }
            } content: {
                VStack(spacing: LBSpacing.s6) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(LBColor.brandText.color)
                        .accessibilityHidden(true)
                    OnboardingTitle(title: "iCloud isn’t available?", line: message)
                    Text("You can move your data anytime in the future")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .multilineTextAlignment(.center)
                    signOutButton
                }
            }
        } else if isWaiting {
            waiting
        } else {
            column
        }
    }

    /// The first-run state reads as the same wait: it starts making the longbook the moment it shows.
    private var isWaiting: Bool {
        switch model.state {
        case .provisioning, .firstRun: true
        default: false
        }
    }

    private var waitingLine: String {
        if case .provisioning(let message) = model.state { return message }
        return DashboardModel.settingUp
    }

    /// Making a longbook in iCloud waits on nothing, so it looks like the app opening: the mark
    /// and the name. A found longbook still coming down, or one made here, says so.
    @ViewBuilder
    private var waiting: some View {
        if waitingLine == DashboardModel.settingUp {
            VStack(spacing: LBSpacing.s2) {
                Image("SidebarMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                Text("longbook")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textTertiary.color)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LBColor.canvas.color)
        } else {
            telling
        }
    }

    /// The mark, what is happening, and where the files will live. Nothing to press.
    private var telling: some View {
        VStack(spacing: LBSpacing.s3) {
            Image("SidebarMark")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text(waitingLine)
                .lbText(.title)
                .foregroundStyle(LBColor.textPrimary.color)
            if waitingLine != DashboardModel.settingUpHere {
                Text("Its files stay in a folder of your own iCloud Drive.")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
            ProgressView()
                .controlSize(.small)
                .padding(.top, LBSpacing.s2)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 360)
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }

    private var column: some View {
        ScrollView {
            VStack(spacing: LBSpacing.s4) {
                Spacer(minLength: LBSpacing.s12)
                content
                signOutButton
                Spacer(minLength: LBSpacing.s8)
            }
            .padding(LBSpacing.s4)
            #if os(macOS)
            .frame(maxWidth: 640)
            #else
            .frame(maxWidth: 460)
            #endif
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }

    /// The first-run flag as the model reports it, nil in every other state.
    private var checkedState: Bool? {
        if case .firstRun(let checkedICloud) = model.state { return checkedICloud }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .provisioning, .firstRun, .unavailable:
            EmptyView()
        case .failed(let message):
            header("folder", badge: "questionmark.circle.fill", "That didn’t open", message)
            secondaryButton("Check iCloud Again") { model.checkICloud() }
            pickButton
        case .loading, .loaded:
            EmptyView()
        }
    }

    private func tile(_ symbol: String, size: CGFloat, radius: CGFloat, symbolSize: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LBColor.brand.color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .medium))
                    .foregroundStyle(LBColor.brandText.color)
            )
            .accessibilityHidden(true)
    }

    /// The glyph tile with an optional badge at its corner, the title, and the note.
    private func header(_ symbol: String, badge: String?, _ title: String, _ note: String) -> some View {
        VStack(spacing: LBSpacing.s3) {
            tile(symbol, size: 72, radius: LBRadius.md, symbolSize: 32)
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(LBColor.brandText.color)
                            .padding(2)
                            .background(LBColor.canvas.color, in: Circle())
                            .offset(x: 8, y: 8)
                            .accessibilityHidden(true)
                    }
                }
            // One line where it fits: a title that wraps reads as two headings.
            Text(title)
                .lbText(.displayLG)
                .foregroundStyle(LBColor.textPrimary.color)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note)
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, LBSpacing.s2)
    }

    @State private var signingOut = false

    private var busy: Bool {
        if signingOut { return true }
        if case .provisioning = model.state { return true }
        return false
    }

    /// The one way back — sign-in is the only screen before this one — named for what it does.
    private var signOutButton: some View {
        Button {
            Measure.used("sign_out")
            guard !signingOut else { return }
            signingOut = true
            model.abandonProvisioning()
            Task {
                await auth.signOut()
                signingOut = false
            }
        } label: {
            Text("Sign Out")
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .padding(.vertical, LBSpacing.s2)
                .padding(.horizontal, LBSpacing.s3)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(busy)
        .accessibilityLabel("Sign out and return to sign in")
        .padding(.top, LBSpacing.s2)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("vault_secondary"); action() }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LBSpacing.s3)
                .overlay(
                    RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous)
                        .strokeBorder(LBColor.hairline.color, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(busy)
    }

    /// Without iCloud the longbook lives beside the app, in its own Documents folder.
    #if os(macOS)
    private static let keepHere = "Keep It on this Mac"
    #else
    private static let keepHere = "Keep It on this iPhone"
    #endif

    private var pickButton: some View {
        Button { Measure.used("choose_a_folder_instead"); pickingFolder = true } label: {
            Text("Choose a Folder Instead")
                .lbText(.footnote)
                .foregroundStyle(LBColor.brandText.color)
                .padding(.vertical, LBSpacing.s2)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .disabled(busy)
    }
}
