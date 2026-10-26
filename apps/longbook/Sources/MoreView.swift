import DesignSystem
import LongbookCore
import SwiftUI

/// Everything that isn't a ledger screen: who you are and where your folder is, then
/// grouped rows — connections, preferences, support — and sign out last, on its own.
/// Every row leads somewhere that exists.
struct MoreView: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let onTutorial: () -> Void
    /// The demo longbook over the book, from the same group as Optimize your data.
    var onDemo: (() -> Void)? = nil
    @State private var importing = false
    @Environment(\.openURL) private var openURL

    /// The tab, the sidebar row and the menu item all say Settings.
    private static let screenTitle = "Settings"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s4) {
                LBPageTitle(Self.screenTitle)
                identityCard
                #if os(iOS)
                // The phone has no sidebar, so More is its one standing route to these.
                group("longbook", [
                    Row(LBGlyph.change, 5, "Proposals", "", .opens(.changes)),
                    Row("lightbulb", 6, "Insights", "", .opens(.insights)),
                    Row("bookmark", 3, "Bookmarks", "", .opens(.commitments(ListFilter(bookmarked: true)))),
                    Row(LBGlyph.account, 4, "Accounts", "", .opens(.accounts)),
                    Row("person.2", 9, "People", "", .opens(.members)),
                ])
                .tutorialTarget(.settingsLongbook)
                #endif
                group("Import", [
                    Row("doc.text.magnifyingglass", 4, "Import a statement", "", .does { importing = true }),
                ])
                .tutorialTarget(.settingsImport)
                group("Reports", [
                    Row("airplane", 7, "Trips", "", .opens(.trips)),
                ])
                group("Connections", [
                    Row("sparkles", 9, "AI Connections", "", .opens(.mcpServer)),
                ])
                group("Preferences", [
                    Row("paintpalette", 5, "Display & currency", "", .opens(.display)),
                    Row("lock", 11, "Data & privacy", "", .opens(.privacy)),
                ])
                group("Support", [
                    Row("slider.horizontal.3", 10, "Optimize your data", "", .does(onTutorial)),
                ] + (onDemo.map { demo in [Row("sparkles", 12, "Try the demo", "", .does(demo))] } ?? []) + [
                    Row("lightbulb.max", 1, "Tips", "", .opens(.tips)),
                    Row("hand.point.up.left", 6, "Tutorials", "", .opens(.tutorials)),
                    Row("questionmark.circle", 8, "Help & about", "", .opens(.helpAbout)),
                ] + updateRows)
                group(nil, [
                    Row("rectangle.portrait.and.arrow.right", nil, "Sign out", "", .opens(.signOut), destructive: true),
                ], danger: true)
            }
            .lbPageColumn(.reading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        #if os(iOS)
        // The Mac's settings are a window of their own, with no tutorial over them.
        .screenTutorial(.settings)
        #endif
        .measured("more_importing", .sheet, when: importing)
        .sheet(isPresented: $importing) {
            StatementImportView(model: model, auth: auth) { importing = false }
        }
        .lbScreenTitle(Self.screenTitle)
    }

    /// What changed in this version, and the way to a newer one. The App Store or
    /// TestFlight does the updating; the screen only opens that page.
    private var updateRows: [Row] {
        [Row("arrow.down.circle", 2, AppUpdates.screenTitle, "", .opens(.updates))]
    }

    // MARK: identity

    /// The card with the owner's email is the door to the account screen: email, plan,
    /// purchase, sign out and delete all live behind it.
    private var identityCard: some View {
        NavigationLink(value: Destination.accountDetails) {
            identityBody
        }
        .lbButtonStyle()
        .accessibilityHint("Opens your account and plan")
    }

    private var identityBody: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            HStack(spacing: LBSpacing.s3) {
                AccountAvatar(url: auth.avatarURL, email: auth.email)
                VStack(alignment: .leading, spacing: 2) {
                    // Named as Settings names its account row: the email is the only name
                    // longbook has been told, and with none the row still says what it opens.
                    Text(auth.email ?? "Your account")
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Account and plan")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
                Spacer(minLength: LBSpacing.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }

    // MARK: groups

    private enum RowState {
        case opens(Destination)
        case does(() -> Void)
        case soon
        case plain
    }

    private struct Row: Identifiable {
        let symbol: String
        let ink: Int?
        let title: String
        let subtitle: String
        let state: RowState
        /// Destructive rows wear danger — a label at the boundary floor, per the rule
        /// delete buttons already follow.
        let destructive: Bool
        var id: String { title }

        init(_ symbol: String, _ ink: Int?, _ title: String, _ subtitle: String, _ state: RowState, destructive: Bool = false) {
            self.symbol = symbol
            self.ink = ink
            self.title = title
            self.subtitle = subtitle
            self.state = state
            self.destructive = destructive
        }
    }

    /// A titled card of rows, the title a caption above it. `danger` washes the card for the
    /// one destructive group.
    private func group(_ title: String?, _ rows: [Row], danger: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            if let title {
                Text(title)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .padding(.horizontal, LBSpacing.s1)
            }
            VStack(spacing: 0) {
                // The rule belongs BETWEEN rows; one under the last would cut the card.
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    self.row(row, separated: index < rows.count - 1)
                }
            }
            .background(
                (danger ? LBColor.danger.color.opacity(0.08) : LBColor.card.color),
                in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                    .strokeBorder(danger ? LBColor.danger.color.opacity(0.35) : LBColor.hairline.color, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func row(_ row: Row, separated: Bool) -> some View {
        switch row.state {
        case .opens(let destination):
            NavigationLink(value: destination) {
                rowBody(row.symbol, ink: row.ink, row.title, row.subtitle, trailing: "chevron.right", separated: separated, destructive: row.destructive)
            }
            .lbButtonStyle()
        case .does(let action):
            Button(action: { Measure.used("more_row"); action() }) {
                rowBody(row.symbol, ink: row.ink, row.title, row.subtitle, trailing: "chevron.right", separated: separated, destructive: row.destructive)
            }
            .lbButtonStyle()
        case .soon:
            rowBody(row.symbol, ink: row.ink, row.title, row.subtitle, trailing: nil, soon: true, separated: separated)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.title), coming soon")
        case .plain:
            rowBody(row.symbol, ink: row.ink, row.title, row.subtitle, trailing: nil, separated: separated)
        }
    }

    private func rowBody(
        _ symbol: String, ink: Int?, _ title: String, _ subtitle: String,
        trailing: String?, soon: Bool = false, separated: Bool = false, destructive: Bool = false
    ) -> some View {
        SettingsRowLabel(
            symbol: symbol, ink: ink, title: title, subtitle: subtitle,
            trailing: trailing, soon: soon, separated: separated, destructive: destructive
        )
    }
}
