import DesignSystem
import LongbookCore
import SwiftUI

/// Where a paused first run rests: on this device after Skip, or on another device
/// that opens the same account mid-setup. The way on is back to where the owner stopped;
/// the quieter door opens a demo longbook, to see what a filled one feels like meanwhile.
struct OnboardingWaitingView: View {
    let commitments: Int
    let accounts: Int
    let onResume: () -> Void
    let onDemo: () -> Void
    /// Setup reopened from More: the way out.
    var onClose: (() -> Void)? = nil

    var body: some View {
        Group {
            #if os(macOS)
            OnboardingPanel {
                words
            } actions: {
                OnboardingCancelButton(action: onClose)
                OnboardingSecondaryButton(title: "Try the Demo", action: onDemo)
                    .frame(width: 220)
                OnboardingPrimaryButton(title: "Continue Setup", action: onResume)
                    .frame(width: 180)
            }
            #else
            VStack(spacing: 0) {
                if let onClose {
                    HStack {
                        Spacer()
                        OnboardingCloseButton(action: onClose)
                    }
                    .padding(.horizontal, LBSpacing.s4)
                    .padding(.top, LBSpacing.s3)
                }
                Spacer()
                words
                    .padding(.horizontal, LBSpacing.s8)
                Spacer()
                VStack(spacing: LBSpacing.s3) {
                    OnboardingPrimaryButton(title: "Continue Setup", action: onResume)
                    OnboardingSecondaryButton(title: "Try the Demo", action: onDemo)
                }
                .padding(.horizontal, LBSpacing.s4)
                .padding(.bottom, LBSpacing.s4)
            }
            .onboardingColumn()
            #endif
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { onResume(); return .handled }
        .onKeyPress(.return) { onResume(); return .handled }
    }

    private var words: some View {
        VStack(spacing: LBSpacing.s4) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(LBColor.brandText.color)
            Text("Your longbook is waiting")
                .lbText(.displayLG)
                .foregroundStyle(LBColor.textPrimary.color)
                .multilineTextAlignment(.center)
            Text("Your choices are saved. Finish whenever you’re ready.")
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let saved {
                Text(saved)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .padding(.horizontal, LBSpacing.s3)
                    .padding(.vertical, LBSpacing.s2)
                    .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
            }
        }
    }

    /// What is saved, naming only what there is: "2 commitments saved". Nil when nothing is.
    private var saved: String? {
        var parts: [String] = []
        if commitments > 0 { parts.append("\(commitments) \(commitments == 1 ? "commitment" : "commitments")") }
        if accounts > 0 { parts.append("\(accounts) \(accounts == 1 ? "account" : "accounts")") }
        return parts.isEmpty ? nil : parts.joined(separator: " and ") + " saved"
    }
}

/// The Mac's frame for a screen with no cards: a centred panel about 640 wide, its words in
/// the middle and its buttons along the bottom-right, sized to their words.
struct OnboardingPanel<Content: View, Actions: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: LBSpacing.s8) {
            content()
                .frame(maxWidth: .infinity)
            HStack(spacing: LBSpacing.s3) {
                Spacer()
                actions()
                Spacer()
            }
        }
        .padding(LBSpacing.s8)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
        .frame(maxWidth: 640)
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }
}
