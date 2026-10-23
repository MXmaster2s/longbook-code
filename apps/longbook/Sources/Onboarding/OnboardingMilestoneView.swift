import DesignSystem
import LongbookCore
import SwiftUI

/// The pause after a step: each name added on its own row with what it still needs, or a
/// sentence when there is none. With a secondary, the primary is a detour back and the
/// secondary is the way on, which the forward keys follow.
struct OnboardingMilestoneView: View {
    struct Row: Identifiable {
        let name: String
        /// What the row waits for: "Add amount later", "Add balance later".
        let badge: String
        let tag: String?
        var id: String { name }
    }

    let step: Int
    let clock: OnboardingClock
    let heading: String
    /// Said under the heading when there are no rows to show instead.
    var summary: String? = nil
    let rows: [Row]
    var note: String? = nil
    let buttonTitle: String
    let onContinue: () -> Void
    let onBack: () -> Void
    var secondary: (title: String, action: () -> Void)? = nil
    /// Setup reopened from More: the way out.
    var onClose: (() -> Void)? = nil

    private var onForward: () -> Void { secondary?.action ?? onContinue }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: step, clock: clock, complete: true, onClose: onClose)
            ScrollView {
                VStack(spacing: LBSpacing.s4) {
                    // A seal marks something done; an empty tray says nothing was added.
                    Image(systemName: rows.isEmpty ? "tray" : "checkmark.seal.fill")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(LBColor.brandText.color)
                        .padding(.top, LBSpacing.s8)
                    Text(heading)
                        .lbText(.displayLG)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary {
                        Text(summary)
                            .lbText(.body)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: LBSpacing.s2) {
                        ForEach(rows, content: row)
                    }
                    .padding(.top, LBSpacing.s2)
                }
                .padding(LBSpacing.s4)
            }
            VStack(spacing: LBSpacing.s4) {
                if let note {
                    Text(note)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: LBSpacing.s3) {
                    #if os(macOS)
                    OnboardingCancelButton(action: onClose)
                    #endif
                    OnboardingPrimaryButton(title: buttonTitle, action: onContinue)
                }
                if let secondary {
                    OnboardingSecondaryButton(title: secondary.title, action: secondary.action)
                }
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.bottom, LBSpacing.s4)
        }
        .onboardingColumn()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { onForward(); return .handled }
        .onKeyPress(.rightArrow) { onForward(); return .handled }
        .onKeyPress(.upArrow) { onBack(); return .handled }
        .onKeyPress(.leftArrow) { onBack(); return .handled }
    }

    /// One name as the owner picked it, the role it implies, and what it still needs.
    private func row(_ row: Row) -> some View {
        HStack(spacing: LBSpacing.s3) {
            Text(row.name)
                .lbText(.body)
                .fontWeight(.medium)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
            if let tag = row.tag {
                Text(tag)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .padding(.horizontal, LBSpacing.s2)
                    .padding(.vertical, LBSpacing.s1)
                    .background(LBColor.chrome.color, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            }
            Spacer(minLength: LBSpacing.s2)
            Text(row.badge)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous).strokeBorder(LBColor.hairline.color, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
