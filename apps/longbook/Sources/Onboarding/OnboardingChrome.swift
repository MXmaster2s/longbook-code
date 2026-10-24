import DesignSystem
import LongbookCore
import SwiftUI

/// The pieces every onboarding screen shares: the step header, the one primary button,
/// and the column every screen sits in.
enum OnboardingDevice {
    /// A name for this device in the account's progress row, kept on this device only.
    static var id: String {
        let key = "longbook.deviceId"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        #if os(macOS)
        let made = "Mac-\(UUID().uuidString.prefix(8))"
        #else
        let made = "iPhone-\(UUID().uuidString.prefix(8))"
        #endif
        UserDefaults.standard.set(made, forKey: key)
        return made
    }
}

/// When the first run began on this device, for the finish's usage count. Never shown: a
/// visible clock reads as being timed.
@Observable
final class OnboardingClock {
    let startedAt = Date()
}

struct OnboardingHeader: View {
    let step: Int
    let clock: OnboardingClock
    /// True on the pause after a step: the words say the step is done.
    var complete = false
    /// Setup reopened from More: the phone closes from here; the Mac puts Cancel by the
    /// primary button instead.
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: LBSpacing.s3) {
            HStack(spacing: LBSpacing.s1) {
                if complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LBColor.mintTint.color)
                }
                Text(complete ? "Step \(step) done" : "Step \(step) of 3")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize()
            }
            ForEach(1...3, id: \.self) { mark in
                Capsule()
                    .fill(mark <= step ? LBColor.brand.color : LBColor.chrome.color)
                    .frame(height: 3)
            }
            #if os(iOS)
            if let onClose {
                OnboardingCloseButton(action: onClose)
            }
            #endif
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.top, LBSpacing.s3)
        .accessibilityElement(children: .contain)
    }
}

/// A plain close mark, for setup reopened from More on the phone.
struct OnboardingCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: { Measure.used("close"); action() }) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LBColor.textSecondary.color)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close setup")
    }
}

/// The Mac's way out of a reopened setup: Cancel beside the primary button, never a mark
/// in the window's far corner. Draws nothing when there is nowhere to go.
struct OnboardingCancelButton: View {
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: { Measure.used("cancel"); action() }) {
                Text("Cancel")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .padding(.horizontal, LBSpacing.s6)
                    .frame(minHeight: 46)
                    .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel and close setup")
        }
    }
}

/// The brand-filled button every step ends with. Dimmed, not hidden, while it waits.
struct OnboardingPrimaryButton: View {
    let title: String
    var enabled = true
    /// Why the button waits, said as a tooltip on the Mac and a short bubble on a phone tap.
    var hint = "Complete the steps above to continue"
    let action: () -> Void
    @State private var hinting = false

    var body: some View {
        Button(action: { Measure.used("onboarding_primary"); action() }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(enabled ? LBColor.onBrand.color : LBColor.textTertiary.color)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(enabled ? LBColor.brand.color : LBColor.hairline.color,
                            in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.2), value: enabled)
        .help(enabled ? "" : hint)
        .accessibilityHint(enabled ? "" : hint)
        .overlay(alignment: .top) {
            if hinting {
                Text(hint)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, LBSpacing.s2)
                    .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                    .offset(y: -44)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onTapGesture {
            // A disabled button swallows nothing: the tap lands here and earns the reason.
            guard !enabled else { return }
            withAnimation(.easeOut(duration: 0.18)) { hinting = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeOut(duration: 0.25)) { hinting = false }
            }
        }
    }
}

/// The quieter full-width button under a primary one: the other way on, never the main one.
struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: { Measure.used("onboarding_secondary"); action() }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The two AIs longbook sits beside, each with its own mark from the asset catalogue: Claude's
/// in its terracotta, ChatGPT's in the text colour, as their brand pages draw them.
enum AIPartner {
    case claude, chatGPT

    var name: String {
        switch self {
        case .claude: "Claude"
        case .chatGPT: "ChatGPT"
        }
    }

    var asset: String {
        switch self {
        case .claude: "ClaudeMark"
        case .chatGPT: "ChatGPTMark"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
        case .chatGPT: LBColor.textPrimary.color
        }
    }
}

struct PartnerMark: View {
    let partner: AIPartner
    var size: CGFloat = 16

    var body: some View {
        Image(partner.asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(partner.tint)
            .accessibilityHidden(true)
    }
}

/// A small pill: the card's "Scroll down" and the Step 3 helpers. Grey means locked.
struct OnboardingPill: View {
    let title: String
    var ready = true
    let action: () -> Void

    var body: some View {
        Button(action: { Measure.used("onboarding_pill"); action() }) {
            Text(title)
                .lbText(.bodySM)
                .fontWeight(.medium)
                .foregroundStyle(ready ? LBColor.onBrand.color : LBColor.textTertiary.color)
                .padding(.horizontal, LBSpacing.s4)
                .frame(minHeight: 44)
                .background(ready ? LBColor.brand.color : LBColor.hairline.color, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: ready)
    }
}

/// Dark or light during setup, where Settings is not yet in reach: a sun by night, a moon
/// by day, the same remembered choice as the Appearance setting.
struct OnboardingThemeButton: View {
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            Measure.used("sun_max")
            appearance = (colorScheme == .dark ? LBAppearance.light : LBAppearance.dark).rawValue
        } label: {
            Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LBColor.textSecondary.color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colorScheme == .dark ? "Switch to the light appearance" : "Switch to the dark appearance")
    }
}

/// A quiet text action with a full tap target, for "Skip".
struct OnboardingTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: { Measure.used("onboarding_quiet"); action() }) {
            Text(title)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .padding(.horizontal, LBSpacing.s3)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// The column every onboarding screen keeps to. A phone's column is 560 at most; a Mac
    /// screen that lays its cards side by side asks for more.
    func onboardingColumn(width: CGFloat = 560) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LBColor.canvas.color)
    }
}

/// The width a Mac onboarding screen takes when its cards sit in two columns.
enum OnboardingWidth {
    #if os(macOS)
    static let wide: CGFloat = 920
    #else
    static let wide: CGFloat = 560
    #endif
}

/// Where the reader is on the way in: two welcome pages, sign-in, then the purchase.
struct OnboardingDots: View {
    static let total = 4
    let current: Int

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            ForEach(0..<Self.total, id: \.self) { dot in
                Circle()
                    .fill(dot == current ? LBColor.brand.color : LBColor.hairline.color)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(Self.total)")
    }
}

/// The frame every screen on the way in shares, so only the words change: the
/// mark at one spot at the top, the screen's own content under it, and the dots, main button
/// and quiet button pinned to the same heights at the foot. An empty slot keeps its space.
struct OnboardingScaffold<Content: View, Primary: View>: View {
    var dot: Int?
    var secondary: String?
    var onSecondary: () -> Void = {}
    @ViewBuilder let primary: Primary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Image("SidebarMark")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .padding(.top, LBSpacing.s12)
                .accessibilityHidden(true)
            ScrollView {
                content
                    .padding(.horizontal, LBSpacing.s6)
                    .padding(.top, LBSpacing.s8)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: LBSpacing.s3) {
                Group {
                    if let dot { OnboardingDots(current: dot) } else { Color.clear }
                }
                .frame(height: 7)
                primary
                    .frame(maxWidth: .infinity, minHeight: 50)
                Group {
                    if let secondary { OnboardingTextButton(title: secondary, action: onSecondary) } else { Color.clear }
                }
                .frame(height: 44)
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.bottom, LBSpacing.s2)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }
}

/// A screen title and its line: one size for every step on the way in.
struct OnboardingTitle: View {
    let title: String
    var line: String?

    var body: some View {
        VStack(spacing: LBSpacing.s3) {
            Text(title)
                .lbText(.displayLG)
                .foregroundStyle(LBColor.textPrimary.color)
            if let line {
                Text(line)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textSecondary.color)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}
