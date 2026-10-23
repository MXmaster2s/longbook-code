import DesignSystem
import LongbookCore
import SwiftUI

/// The front door for a signed-in reader with no vault anywhere: check iCloud for an
/// existing longbook, create a new one, or point at a folder — never a write they
/// didn't choose. Shown before onboarding, so every later step has somewhere to save.
struct VaultChoiceView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @State private var pickingFolder = false
    /// Whether the last first-run state followed a check, so a check in flight keeps the
    /// emphasis where it was instead of jumping back.
    @State private var checked = false

    /// The three ways forward. One is the filled button; the others stay quiet.
    private enum Choice: CaseIterable {
        case check, create, choose
    }

    var body: some View {
        layout
        .onChange(of: checkedState, initial: true) { _, value in
            if let value { checked = value }
        }
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
        } else {
            column
        }
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
        case .provisioning(let message):
            #if os(macOS)
            macDialog("One moment", message, filled: checked || !model.returningAccount ? .create : .check)
            #else
            header("folder", badge: nil, "One moment", message)
            choices(filled: checked || !model.returningAccount ? .create : .check)
            #endif
        case .firstRun(let checkedICloud):
            #if os(macOS)
            macDialog(firstRunTitle, firstRunNote, filled: checkedICloud || !model.returningAccount ? .create : .check)
            #else
            header("folder", badge: model.returningAccount ? "magnifyingglass.circle.fill" : "plus.circle.fill",
                   firstRunTitle, firstRunNote)
            choices(filled: checkedICloud || !model.returningAccount ? .create : .check)
            #endif
        case .unavailable:
            EmptyView()
        case .failed(let message):
            header("folder", badge: "questionmark.circle.fill", "That didn’t open", message)
            secondaryButton("Check iCloud Again") { model.checkICloud() }
            pickButton
        case .loading, .loaded:
            EmptyView()
        }
    }

    private var firstRunTitle: String {
        model.returningAccount ? "Your longbook isn’t in iCloud" : "Your longbook folder"
    }

    private var firstRunNote: String {
        model.returningAccount
            ? "Check again, create a new one, or choose the folder it’s in."
            : "One folder of plain files in your iCloud Drive, synced by Apple and readable by your AI."
    }

    private func title(_ choice: Choice) -> String {
        switch choice {
        case .check: model.returningAccount ? "Check Again" : "Check iCloud"
        case .create: "New longbook"
        case .choose:
            #if os(macOS)
            "Choose Folder…"
            #else
            "Choose Folder"
            #endif
        }
    }

    private func perform(_ choice: Choice) {
        switch choice {
        case .check: model.checkICloud()
        case .create: model.createICloudVault()
        case .choose: pickingFolder = true
        }
    }

    /// What a check found, said where it was tapped.
    #if !os(macOS)
    private var notFound: some View {
        Text("Not found in iCloud Drive.")
            .lbText(.footnote)
            .foregroundStyle(LBColor.textTertiary.color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
    #endif

    /// The phone's three choices: the filled button, then two quiet ones. A finished check
    /// puts its result above Check Again and moves the fill to New longbook.
    #if !os(macOS)
    private func choices(filled: Choice) -> some View {
        VStack(spacing: LBSpacing.s1) {
            if checked { notFound.padding(.bottom, LBSpacing.s1) }
            ForEach(Choice.allCases, id: \.self) { choice in
                choiceButton(choice, filled: choice == filled)
            }
        }
    }
    #endif

    #if !os(macOS)
    private func choiceButton(_ choice: Choice, filled: Bool) -> some View {
        Button { perform(choice) } label: {
            Text(title(choice))
                .lbText(.body)
                .foregroundStyle(filled ? LBColor.onBrand.color : LBColor.brandText.color)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(filled ? LBColor.brand.color : Color.clear,
                            in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lbTapHaptic()
        .disabled(busy)
    }
    #endif

    #if os(macOS)
    /// A dialog: the glyph beside the message, the buttons under it on the right with the
    /// default one last, and a finished check's result on the left of that row.
    private func macDialog(_ title: String, _ note: String, filled: Choice) -> some View {
        HStack(alignment: .top, spacing: LBSpacing.s4) {
            tile("folder", size: 56, radius: LBRadius.sm, symbolSize: 26)
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                Text(title)
                    .lbText(.title)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if checked {
                    Text("Not found in iCloud Drive.")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .padding(.top, LBSpacing.s1)
                }
                HStack(spacing: LBSpacing.s2) {
                    Spacer(minLength: LBSpacing.s2)
                    ForEach([Choice.choose] + Choice.allCases.filter { $0 != .choose && $0 != filled } + [filled], id: \.self) { choice in
                        macButton(choice, isDefault: choice == filled)
                    }
                }
                .padding(.top, LBSpacing.s3)
            }
        }
        .padding(LBSpacing.s6)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    private func macButton(_ choice: Choice, isDefault: Bool) -> some View {
        Button { perform(choice) } label: {
            Text(title(choice))
                .lbText(.body)
                .foregroundStyle(isDefault ? LBColor.onBrand.color : LBColor.textPrimary.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, LBSpacing.s4)
                .frame(minHeight: 32)
                .background(isDefault ? LBColor.brand.color : LBColor.chrome.color,
                            in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(isDefault ? .defaultAction : nil)
        .disabled(busy)
    }
    #endif

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
            guard !signingOut else { return }
            signingOut = true
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
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Sign out and return to sign in")
        .padding(.top, LBSpacing.s2)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
        .disabled(busy)
    }

    /// Without iCloud the longbook lives beside the app, in its own Documents folder.
    #if os(macOS)
    private static let keepHere = "Keep It on this Mac"
    #else
    private static let keepHere = "Keep It on this iPhone"
    #endif

    private var pickButton: some View {
        Button { pickingFolder = true } label: {
            Text("Choose a Folder Instead")
                .lbText(.footnote)
                .foregroundStyle(LBColor.brandText.color)
                .padding(.vertical, LBSpacing.s2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}
