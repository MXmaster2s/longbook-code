import DesignSystem
import SwiftUI

/// The one-time choice about usage and crash data (App Review 5.1.1): asked when the app first
/// opens, before any event could be sent, and once on an install from before it was asked. Two
/// equal buttons; either one continues, and the switch in Settings changes it later.
struct UsageChoiceSheet: View {
    let onChoose: (Bool) -> Void

    static let title = "Usage and crash data"
    static let sent = "longbook can send counts of what you do in the app, such as screens opened, how long it is open and errors it handles, plus crash reports. They go to PostHog under a random ID that stays on this device and is never tied to your account. PostHog notes the country and city your connection comes from."
    static let neverSent = "Never sent: your commitments, names, amounts, dates, notes, statements or email address."
    static let later = "You can change this at any time in Settings."

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LBColor.onBrand.color)
                    .frame(width: 36, height: 36)
                    .background(LBColor.brand.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                    .accessibilityHidden(true)
                Text(Self.title)
                    .lbText(.screenTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s3) {
                    words(Self.sent, ink: LBColor.textSecondary.color)
                    words(Self.neverSent, ink: LBColor.textPrimary.color)
                    words(Self.later, ink: LBColor.textTertiary.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: LBSpacing.s2) {
                choice("Don’t Share", share: false)
                choice("Share", share: true)
            }
        }
        .padding(LBSpacing.s6)
        // No ring on either answer when the sheet opens, so neither looks chosen. Tab still
        // reaches both, and the ring shows from the first Tab until a click.
        .lbKeyboardFocusEffects()
        // Answered with a button, never swiped away: a sheet closed unanswered would ask again.
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(width: 460)
        .background(LBColor.card.color)
        #else
        .presentationBackground(LBColor.card.color)
        .presentationDetents([.medium, .large])
        #endif
        .onAppear { TutorialCenter.shared.hold(true) }
        .onDisappear { TutorialCenter.shared.hold(false) }
    }

    private func words(_ text: String, ink: Color) -> some View {
        Text(text)
            .lbText(.body)
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Both answers look alike, so neither is the one the screen pushes.
    private func choice(_ title: String, share: Bool) -> some View {
        // Counted after the answer is stored, so a Don't Share is never sent.
        Button(action: { onChoose(share); Measure.used("usage_choice") }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPressStyle())
        .accessibilityLabel(share ? "Share usage and crash data" : "Don’t share usage and crash data")
        #if os(macOS)
        // Neither is the default button, so Return answers with the one Tab reached, as Space does.
        .onKeyPress(.return) { onChoose(share); Measure.used("usage_choice"); return .handled }
        #endif
    }
}

/// Raises the choice over whatever stands in front once the sign-in state is known, until it
/// is answered. Every window reads the same stored answer, so one answer closes it in all.
struct UsageChoicePresenter: ViewModifier {
    let ready: Bool
    @AppStorage(Telemetry.shareUsageKey) private var answer: Bool?

    #if DEBUG
    /// Pictures and simulator runs show screens as they are, with nothing over them.
    private static let disabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        return ["LONGBOOK_SNAPSHOT", "LONGBOOK_SNAPSHOT_SCREEN", "LONGBOOK_WINDOW_SNAPSHOT", "LONGBOOK_SKIP_AUTH",
                "LONGBOOK_NO_USAGE_CHOICE"].contains { env[$0] != nil }
    }()
    #else
    private static let disabled = false
    #endif

    func body(content: Content) -> some View {
        let asking = ready && answer == nil && !Self.disabled
        content
            .measured("usage_choice", .sheet, when: asking)
            .sheet(isPresented: Binding(get: { asking }, set: { _ in })) {
                UsageChoiceSheet { share in Telemetry.shared.setEnabled(share) }
            }
    }
}
