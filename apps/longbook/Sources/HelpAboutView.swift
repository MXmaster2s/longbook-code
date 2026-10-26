import DesignSystem
import LongbookCore
import SwiftUI

/// Help & about: the version, the ways to reach us, and each kind of data that leaves the
/// device, with the switch for usage and crash data beside the fact it governs.
struct HelpAboutView: View {
    let model: DashboardModel
    @AppStorage(Telemetry.shareUsageKey) private var shareUsage = true
    @Environment(\.openURL) private var openURL

    private struct LinkRow: Identifiable {
        let symbol: String
        let ink: Int
        let title: String
        let subtitle: String
        let url: URL?
        var id: String { title }
    }

    private static let ideasURL = URL(string: "https://insigh.to/b/longbook")
    private static let faqURL = URL(string: "https://longbook.app/faq/")
    private static let contactURL = URL(string: "https://longbook.app/contact/")
    private static let privacyURL = URL(string: "https://longbook.app/privacy-policy/")
    private static let termsURL = URL(string: "https://longbook.app/terms/")
    private static let sourceURL = URL(string: "https://longbook.app/source/")

    private static var problemURL: URL? { FeedbackMail.url(subject: "longbook problem report") }

    var body: some View {
        SettingsScreen(title: "Help & about", note: "") {
            header
            LBSectionHeader("Feedback")
            links([
                LinkRow(symbol: "lightbulb", ink: 3, title: "Suggest a feature", subtitle: "", url: Self.ideasURL),
                LinkRow(symbol: "exclamationmark.bubble", ink: 3, title: "Report a problem", subtitle: "", url: Self.problemURL),
            ])
            LBSectionHeader("Help")
            supportRow
            links([
                LinkRow(symbol: "questionmark.circle", ink: 8, title: "Questions and guides", subtitle: "", url: Self.faqURL),
                LinkRow(symbol: "envelope", ink: 8, title: "Contact", subtitle: "contact@longbook.app", url: Self.contactURL),
            ])
            LBSectionHeader("What leaves this device")
            leaving
            Text("longbook never sells your data, and never uses your financial data for analytics or advertising.")
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
                .fixedSize(horizontal: false, vertical: true)
            LBSectionHeader("Legal")
            links([
                LinkRow(symbol: "hand.raised", ink: 11, title: "Privacy policy", subtitle: "", url: Self.privacyURL),
                LinkRow(symbol: "doc.text", ink: 11, title: "Terms of service", subtitle: "", url: Self.termsURL),
                LinkRow(symbol: "chevron.left.forwardslash.chevron.right", ink: 11, title: "Source code", subtitle: "GPL-3.0", url: Self.sourceURL),
            ])
        }
    }

    // MARK: header

    private var header: some View {
        LBCard {
            HStack(spacing: LBSpacing.s3) {
                Image("SidebarMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("longbook")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                    Text("Version \(AppVersion.marketing) (\(AppVersion.build))")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Support

    /// Support opens in the app, so its row wears the inward chevron, not the outward arrow.
    private var supportRow: some View {
        LBCard(padding: 0) {
            Button {
                Measure.used("help_support")
                SupportCenter.shared.open()
            } label: {
                SettingsRowLabel(symbol: "bubble.left", ink: 8, title: "Support", subtitle: "", trailing: "chevron.right")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: links

    /// A card of rows that leave the app, each wearing the outward arrow.
    private func links(_ rows: [LinkRow]) -> some View {
        LBCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        Measure.used("arrow_up_right")
                        if let url = row.url { openURL(url) }
                    } label: {
                        SettingsRowLabel(
                            symbol: row.symbol, ink: row.ink, title: row.title, subtitle: row.subtitle,
                            trailing: "arrow.up.right", separated: index < rows.count - 1
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: what leaves this device

    @AppStorage(AIConsent.statements.key) private var statementsConsent = false

    private var leaving: some View {
        LBCard {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                fact("Account", "Your email and account ID, to sign you in. With Google, also your name and the address of your picture.")
                rule
                fact("Purchase", "Apple’s transaction ID, to unlock the licence.")
                rule
                fact(
                    "Hosted copy",
                    "A copy of your memory file for your AI to read, only while AI access is on. Deleted when you turn it off or after 90 days without the app.",
                    state: model.hostedPush ? "On" : "Off"
                )
                rule
                fact("Statements", "Sent through longbook’s server to Anthropic, whose Claude model first checks it is a statement and then reads it with your category, person and account names. longbook keeps none of it.")
                // Withdrawing is turning this off: the next statement or Reorganise asks again.
                Toggle(isOn: $statementsConsent.measured("let_an_ai_read_statements_and_reorganise")) {
                    Text("Let an AI read statements and Reorganise")
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textPrimary.color)
                }
                .tint(LBColor.brand.color)
                rule
                SupportPrivacyRows()
                rule
                fact("Shared reports", "Kept with your account until the link expires or you revoke it.")
                rule
                fact("Tags", "Each tag’s kind, name and icon, so your devices share them. Never a commitment’s name, amount, date or note.")
                rule
                fact("Usage and crash data", "Counts of what you do, how long the app is open, errors it handles and who changed your file, plus crash reports. Sent under a random ID that stays on this device and is never tied to your account; turning this off deletes the ID. Never a name, amount, date or note.")
                Toggle(isOn: Binding(
                    get: { shareUsage },
                    set: { on in
                        shareUsage = on
                        Telemetry.shared.setEnabled(on)
                    }
                ).measured("share_usage_and_crash_data")) {
                    Text("Share usage and crash data")
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textPrimary.color)
                }
                .tint(LBColor.brand.color)
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(LBColor.hairline.color).frame(height: 1)
    }

    /// A kind of data: what it is, then why it leaves. `state` is a live on or off.
    private func fact(_ label: String, _ detail: String, state: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s3) {
                Text(label)
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Spacer(minLength: LBSpacing.s2)
                if let state {
                    Text(state)
                        .lbText(.bodySM)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
            Text(detail)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
