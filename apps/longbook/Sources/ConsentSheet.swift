import DesignSystem
import SwiftUI

/// A feature that hands the reader's data to a third-party AI, asked once on this device
/// before it first does (App Review 5.1.2(i)). Withdrawn in Help & about.
enum AIConsent: String {
    /// Statements and Reorganise, both read by Anthropic's Claude.
    case statements
    /// Support questions, answered by Anthropic's Claude from the help articles.
    case support

    /// The UserDefaults key, for `@AppStorage`. True once accepted.
    var key: String { "longbook.aiConsent." + rawValue }

    var given: Bool { UserDefaults.standard.bool(forKey: key) }

    /// The one sentence the sheet says: who receives what, and that nothing is kept.
    var sentence: String {
        switch self {
        case .statements:
            "longbook does not store or use your personal financial data.\nlongbook uses Anthropic’s AI services."
        case .support:
            "Your questions, and a screenshot when you attach one, go to longbook's server and to Anthropic's Claude, which answers from our help articles. Our server doesn't keep them. The details are in the privacy policy."
        }
    }
}

/// "Accept the privacy policy": one sentence naming the AI, the policy itself in a scrolling
/// panel, Accept and Not Now. Apple's own consent sheets are the model.
struct ConsentSheet: View {
    let consent: AIConsent
    let onAccept: () -> Void
    let onDecline: () -> Void
    @Environment(\.openURL) private var openURL

    private static let title = "Accept the privacy policy"
    private static let policyURL = URL(string: "https://longbook.app/privacy-policy/")!

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s4) {
            HStack(spacing: LBSpacing.s3) {
                Image(systemName: "sparkles")
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
            Text(consent.sentence)
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            PolicyPanel()
            buttons
        }
        .padding(LBSpacing.s6)
        #if os(macOS)
        .frame(width: 480)
        .background(LBColor.card.color)
        #else
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationBackground(LBColor.card.color)
        // Sized to its words, as the design's bottom sheet; a raised text size drags it taller.
        .presentationDetents([.height(640), .large])
        #endif
        .tint(LBColor.brandText.color)
    }

    @ViewBuilder
    private var buttons: some View {
        #if os(macOS)
        HStack(spacing: LBSpacing.s2) {
            Button("Read on web") { Measure.used("read_on_web"); openURL(Self.policyURL) }
                .buttonStyle(.link)
                .lbLinkPointer()
            Spacer(minLength: LBSpacing.s3)
            Button("Not Now", action: { Measure.used("not_now"); onDecline() })
                .keyboardShortcut(.cancelAction)
            Button("Accept", action: { Measure.used("accept"); onAccept() })
                .keyboardShortcut(.defaultAction)
                .tint(LBColor.brand.color)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        #else
        VStack(spacing: LBSpacing.s2) {
            filled("Accept", primary: true, action: onAccept)
            filled("Not Now", primary: false, action: onDecline)
            Button("Read on web") { Measure.used("read_on_web"); openURL(Self.policyURL) }
                .lbText(.label)
                .foregroundStyle(LBColor.brandText.color)
                .padding(.top, LBSpacing.s1)
        }
        #endif
    }

    private func filled(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Measure.used("consent_choice"); action() }) {
            Text(title)
                .lbText(.body)
                .foregroundStyle(primary ? LBColor.onBrand.color : LBColor.textPrimary.color)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(primary ? LBColor.brand.color : LBColor.chrome.color,
                            in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPressStyle())
    }
}

/// The privacy policy, whole, from the copy bundled at build (site:pages writes it), in a
/// panel short enough that the buttons stay in view.
private struct PolicyPanel: View {
    private static let blocks: [String] = {
        guard let url = Bundle.main.url(forResource: "privacy-policy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("- Page:") }
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                ForEach(Array(Self.blocks.enumerated()), id: \.offset) { _, block in
                    paragraph(block)
                }
            }
            .padding(LBSpacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if os(macOS)
        .frame(height: 170)
        #else
        .frame(height: 240)
        #endif
        .background(LBColor.sunken.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .accessibilityLabel("Privacy policy")
    }

    @ViewBuilder
    private func paragraph(_ block: String) -> some View {
        if block.hasPrefix("#") {
            Text(block.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                .lbText(.label)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
        } else {
            let plain = block.hasPrefix("> ") ? String(block.dropFirst(2)) : block
            Text((try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(plain))
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
