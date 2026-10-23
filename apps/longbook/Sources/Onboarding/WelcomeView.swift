import DesignSystem
import SwiftUI

/// Two pages before sign-in: a welcome, then what longbook is and that it works best beside
/// the owner's own AI. Sign-in is the third step and the purchase the fourth; the dots count
/// all four, and Back steps through them.
struct WelcomeView: View {
    var startPage = 0
    let onDone: () -> Void

    @State private var page = 0

    var body: some View {
        Group {
            #if os(macOS)
            OnboardingPanel {
                VStack(spacing: LBSpacing.s3) {
                    pageView
                        .padding(.vertical, LBSpacing.s6)
                    OnboardingDots(current: page)
                }
            } actions: {
                HStack(spacing: LBSpacing.s3) {
                    if page == 1 { OnboardingTextButton(title: "Back") { show(0) } }
                    OnboardingPrimaryButton(title: buttonTitle, action: advance)
                        .frame(width: 240)
                }
            }
            #else
            OnboardingScaffold(dot: page, secondary: page == 1 ? "Back" : nil, onSecondary: { show(0) }) {
                OnboardingPrimaryButton(title: buttonTitle, action: advance)
            } content: {
                pageView
            }
            #endif
        }
        .onAppear { page = startPage }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                if drag.translation.width < 0 { advance() } else if page == 1 { show(0) }
            }
        )
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.downArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) { if page == 1 { show(0) }; return .handled }
        .onKeyPress(.upArrow) { if page == 1 { show(0) }; return .handled }
    }

    private var buttonTitle: String { "Continue" }

    private var pageView: some View {
        Group {
            if page == 0 { first } else { second }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private var first: some View {
        VStack(spacing: LBSpacing.s6) {
            #if os(macOS)
            Image("SidebarMark")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            #endif
            OnboardingTitle(title: "Welcome", line: "Let’s set up your account.\nIt only takes a few minutes.")
        }
    }

    private var second: some View {
        VStack(spacing: LBSpacing.s6) {
            OnboardingTitle(title: "What is longbook?",
                            line: "It is a private memory of your money.\nIt remembers your expenses & upcoming commitments.")
            VStack(spacing: LBSpacing.s3) {
                HStack(spacing: LBSpacing.s6) {
                    PartnerMark(partner: .claude, size: 32)
                    PartnerMark(partner: .chatGPT, size: 32)
                }
                Text("Your longbook is compatible with your AI.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func advance() {
        if page == 0 { show(1) } else { onDone() }
    }

    private func show(_ next: Int) {
        withAnimation(.easeOut(duration: 0.35)) { page = next }
    }
}
