#if os(macOS)
import DesignSystem
import LongbookCore
import SwiftUI

/// The Mac sidebar: the vault's own shape — sections, starred accounts and people —
/// in the dashboard's identity inks. Flat surface, not the system material: depth in
/// this design is a tone step. Only the dashboard is a destination yet; the rest are
/// visibly on their way rather than silently dead.
struct SidebarView: View {
    let model: DashboardModel
    @Binding var path: [Destination]
    let addCommitment: () -> Void
    /// The two entity sections fold like a chat app's channel groups; folded, only the
    /// "All" row remains. Remembered per machine, like the sidebar's own visibility.
    @AppStorage("longbook.sidebar.paymentsFolded") private var paymentsFolded = false
    @AppStorage("longbook.sidebar.membersFolded") private var membersFolded = false
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

    /// The screen on show. The harness paints its screen as the stack root with an empty
    /// path, so the row it names stays lit there too.
    private var shown: Destination? {
        #if DEBUG
        path.last ?? RootView.snapshotDestination()
        #else
        path.last
        #endif
    }

    /// The bookmarks door is its own row's light, not this one's.
    private var isCommitments: Bool {
        if case .commitments(let filter) = shown { return !filter.bookmarked }
        return false
    }

    private static let bookmarks = Destination.commitments(ListFilter(bookmarked: true))

    /// The settings live in their own window; the row stays lit on the help and update
    /// screens its menu and the Help menu open here.
    private var isSettings: Bool {
        switch shown {
        case .helpAbout, .updates, .tips, .trips: return true
        default: return false
        }
    }

    /// The reports row stays lit while reading ONE report — the detail is still reports.
    private var isReports: Bool {
        switch shown {
        case .reports, .report: return true
        default: return false
        }
    }

    var body: some View {
        // Header and the bottom row are pinned; only the lists between them scroll, so Add
        // commitment survives any window height. Settings opens a menu whose first item
        // opens the Settings window (⌘,).
        VStack(alignment: .leading, spacing: 0) {
            header
                // Room for the window controls: the sidebar runs under the hidden
                // title bar, and the mark must not.
                .padding(.top, 36)
                .padding(.horizontal, LBSpacing.s3)
                .padding(.bottom, LBSpacing.s3)

            ScrollView {
                VStack(alignment: .leading, spacing: LBSpacing.s2) {
                    sectionLabel("Overview")
                    navRow("square.grid.2x2.fill", "Dashboard", active: shown == nil) { path = [] }
                    navRow("chart.bar", "Reports", active: isReports) { path = [.reports] }
                    navRow(LBGlyph.date, "Calendar", active: shown == .calendar) { path = [.calendar] }
                    navRow(LBGlyph.commitment, "Commitments", active: isCommitments) { path = [.commitments(ListFilter())] }
                    navRow("lightbulb", "Insights", active: shown == .insights) { path = [.insights] }
                    navRow(
                        LBGlyph.change, "Proposals", active: shown == .changes,
                        attention: model.outsideChangeFrom != nil
                    ) { path = [.changes] }

                    if case .loaded(let data) = model.state {
                        foldLabel("Payments", folded: $paymentsFolded).padding(.top, LBSpacing.s3)
                        navRow(LBGlyph.account, "Accounts", active: shown == .accounts) { path = [.accounts] }
                        if !paymentsFolded {
                            starredRows(data.sidebarMethods, none: "Star an account on Accounts to keep it here.") { row in
                                entityRow(row, destination: .commitments(ListFilter(methodId: row.id)))
                            }
                        }

                        foldLabel("People", folded: $membersFolded).padding(.top, LBSpacing.s3)
                        navRow("person.2", "People", active: shown == .members) { path = [.members] }
                        if !membersFolded {
                            starredRows(data.sidebarMembers, none: "Star a person on People to keep them here.") { row in
                                entityRow(row, destination: .commitments(ListFilter(memberId: row.id)))
                            }
                        }
                    }
                }
                .padding(.horizontal, LBSpacing.s3)
                .padding(.bottom, LBSpacing.s3)
            }

            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            VStack(alignment: .leading, spacing: LBSpacing.s2) {
                navRow("plus.circle.fill", "Add commitment", active: false) { addCommitment() }
                    .tutorialTarget(.addCommitment)
                // Settings keeps the row; the two quick doors sit at its right edge.
                HStack(spacing: LBSpacing.s1) {
                    settingsMenu
                    iconButton(
                        colorScheme == .dark ? "sun.max" : "moon",
                        colorScheme == .dark ? "Switch to the light appearance" : "Switch to the dark appearance",
                        active: false
                    ) {
                        appearance = (colorScheme == .dark ? LBAppearance.light : LBAppearance.dark).rawValue
                    }
                    iconButton("bookmark", "Bookmarks", active: shown == Self.bookmarks) {
                        path = [Self.bookmarks]
                    }
                }
            }
            .padding(LBSpacing.s3)
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(LBColor.sunken.color)
        .overlay(alignment: .trailing) {
            Rectangle().fill(LBColor.hairline.color).frame(width: 1)
        }
    }

    /// The Settings row's menu: the Settings window first, then the app's own doors.
    private var settingsMenu: some View {
        Menu {
            Button("Settings…") {
                Measure.used("sidebar_settings", .menuItem)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Button("What’s New") {
                Measure.used("sidebar_whats_new", .menuItem)
                WhatsNewCenter.shared.open()
            }
            Button("Send Feedback…") {
                Measure.used("sidebar_send_feedback", .menuItem)
                SupportCenter.shared.open()
            }
            Button("Check for Updates…") {
                Measure.used("sidebar_check_for_updates", .menuItem)
                AppUpdates.askFromMenu()
            }
            Divider()
            Button("Quit longbook") {
                Measure.used("sidebar_quit", .menuItem)
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            rowLabel("gearshape", "Settings", active: isSettings)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Settings")
    }

    private var header: some View {
        HStack(spacing: LBSpacing.s2) {
            Image("SidebarMark")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("longbook")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                if case .loaded(let data) = model.state {
                    Text(data.vaultLocation)
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
        }
        .padding(.horizontal, LBSpacing.s1)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .lbText(.eyebrow)
            .foregroundStyle(LBColor.textTertiary.color)
            .padding(.horizontal, LBSpacing.s2)
    }

    /// A section label that folds its rows: the chevron says which way it stands.
    private func foldLabel(_ text: String, folded: Binding<Bool>) -> some View {
        Button {
            Measure.used("fold_section")
            folded.wrappedValue.toggle()
        } label: {
            HStack(spacing: LBSpacing.s1) {
                Text(text)
                    .lbText(.eyebrow)
                    .foregroundStyle(LBColor.textTertiary.color)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(LBColor.textQuaternary.color)
                    .rotationEffect(.degrees(folded.wrappedValue ? -90 : 0))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LBSpacing.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint(folded.wrappedValue ? "Shows the rows" : "Hides the rows")
    }

    /// A square control beside Add, lit the way a row is when its screen is open.
    private func iconButton(
        _ symbol: String, _ label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: { Measure.used("sidebar_item"); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? LBColor.onBrandTint.color : LBColor.textSecondary.color)
                .frame(width: 30, height: 30)
                .background(
                    active ? LBColor.brand.color.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func navRow(
        _ symbol: String, _ title: String, active: Bool, attention: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { Measure.used("waiting_for_review"); action() }) {
            rowLabel(symbol, title, active: active, attention: attention)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// Only the starred rows of a group; with none starred, one quiet line saying how to keep one here.
    @ViewBuilder
    private func starredRows<Row: View>(
        _ rows: [DashboardData.SidebarEntity], none: String, row: @escaping (DashboardData.SidebarEntity) -> Row
    ) -> some View {
        let starred = rows.filter(\.starred)
        if starred.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: LBSpacing.s2) {
                Image(systemName: "star")
                    .font(.system(size: 9, weight: .medium))
                    .accessibilityHidden(true)
                Text(none)
                    .lbText(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(LBColor.textTertiary.color)
            .padding(.horizontal, LBSpacing.s2)
            .padding(.vertical, 4)
        } else {
            ForEach(starred) { row($0) }
        }
    }

    /// A row's face, shared by the rows and the Settings menu.
    private func rowLabel(_ symbol: String, _ title: String, active: Bool, attention: Bool = false) -> some View {
        HStack(spacing: LBSpacing.s2) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
            Text(title).lbText(.bodySM)
            Spacer(minLength: 0)
            if attention {
                Circle()
                    .fill(LBColor.urgent.color)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("waiting for review")
            }
        }
        .foregroundStyle(active ? LBColor.onBrandTint.color : LBColor.textSecondary.color)
        .padding(.horizontal, LBSpacing.s2)
        .padding(.vertical, 6)
        .background(
            active ? LBColor.brand.color.opacity(0.16) : .clear,
            in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    /// One account or member, straight to its filtered commitments — the same door the
    /// cards on Accounts and Members already open.
    private func entityRow(_ row: DashboardData.SidebarEntity, destination: Destination) -> some View {
        Button { Measure.used("path"); path = [destination] } label: {
            HStack(spacing: LBSpacing.s2) {
                Circle()
                    .fill(LBColor.dataInk(rank: row.ink).color)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(row.name)
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .lineLimit(1)
                Spacer(minLength: LBSpacing.s1)
                if row.count > 0 {
                    Text("\(row.count)")
                        .lbText(.footnote)
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
            .padding(.horizontal, LBSpacing.s2)
            .padding(.vertical, 4)
            .background(
                shown == destination ? LBColor.brand.color.opacity(0.16) : .clear,
                in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(row.count) commitments")
    }
}
#endif
