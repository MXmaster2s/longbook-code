#if os(macOS)
import DesignSystem
import LongbookCore
import SwiftUI

/// The Mac sidebar: one list of the screens, with starred accounts and people a little inside
/// Accounts and People. A flat surface: depth in this design is a tone step. Rows touch, each
/// answering across its whole height and the sidebar's width, so the pointer always has one.
struct SidebarView: View {
    let model: DashboardModel
    @Binding var path: [Destination]
    /// Statements picked or dropped on the row at the foot go here, as a drop on the window
    /// does. Without it the row is not shown: the demo passes none.
    var importStatements: (([URL]) -> Void)?
    /// A file is being dragged over the window, so the row lights.
    var droppingStatement = false
    @State private var pickingStatements = false
    @State private var statementOverRow = false
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

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
        if case .commitments(let filter) = shown { return !filter.bookmarked && filter.kind == nil }
        return false
    }

    /// Charges, Earnings and Transfers: the landed rows by kind, each its own screen.
    private static let charges = Destination.commitments(ListFilter(scope: .past, kind: .charges))
    private static let earnings = Destination.commitments(ListFilter(scope: .past, kind: .earnings))
    private static let transfers = Destination.commitments(ListFilter(scope: .past, kind: .transfers))

    /// The reports row stays lit while reading ONE report — the detail is still reports.
    private var isReports: Bool {
        switch shown {
        case .reports, .report: return true
        default: return false
        }
    }

    private static let pillHeight: CGFloat = 26
    /// A starred row's indent under its parent.
    private static let childIndent: CGFloat = 16

    /// The hit area around a row's pill. The sidebar's margin and the gap between pills are
    /// both inside it, so nothing between two rows is out of reach of the pointer.
    private static func rowInsets(indent: CGFloat = 0, top: CGFloat = 4, bottom: CGFloat = 4) -> EdgeInsets {
        EdgeInsets(top: top, leading: LBSpacing.s3 + indent, bottom: bottom, trailing: LBSpacing.s3)
    }

    /// The screen on show, when it is one whose rows star: its door by name counts too.
    private func isOnScreen(_ kind: VaultPatch.EntityKind) -> Bool {
        switch shown {
        case .accounts: return kind == .paymentMethod
        case .members: return kind == .familyMember
        case .card(.entity(let shownKind, _)): return shownKind == kind
        default: return false
        }
    }

    /// The row a starred child would light: the screen's open row, when the screen is showing.
    private func openRow(_ kind: VaultPatch.EntityKind) -> String? {
        isOnScreen(kind) ? ScreenMemory.shared.openRows[kind.memoryKey] : nil
    }

    var body: some View {
        // Header and the footer are pinned; only the lists between them scroll, so the footer
        // survives any window height.
        VStack(alignment: .leading, spacing: 0) {
            header
                // Room for the window controls: the sidebar runs under the hidden
                // title bar, and the mark must not.
                .padding(.top, 36)
                .padding(.horizontal, LBSpacing.s3)
                .padding(.bottom, LBSpacing.s2)
            SidebarSearchField()
                .padding(.horizontal, LBSpacing.s3)
                .padding(.bottom, LBSpacing.s2)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow("square.grid.2x2.fill", "Dashboard", active: shown == nil) { path = [] }
                    navRow("chart.bar", "Reports", active: isReports) { path = [.reports] }
                    navRow(LBGlyph.date, "Calendar", active: shown == .calendar) { path = [.calendar] }
                    navRow(LBGlyph.commitment, "Commitments", active: isCommitments) { path = [.commitments(ListFilter())] }
                    navRow(LBGlyph.charge, "Charges", active: shown == Self.charges) { path = [Self.charges] }
                    navRow(LBGlyph.income, "Earnings", active: shown == Self.earnings) { path = [Self.earnings] }
                    navRow(LBGlyph.transfer, "Transfers", active: shown == Self.transfers) { path = [Self.transfers] }
                    navRow("lightbulb", "Insights", active: shown == .insights) { path = [.insights] }
                    navRow(
                        LBGlyph.change, "Proposals", active: shown == .changes,
                        attention: model.outsideChangeFrom != nil
                    ) { path = [.changes] }

                    if case .loaded(let data) = model.state {
                        parentRow(LBGlyph.account, "Accounts", .paymentMethod, .accounts, data.sidebarMethods)
                        parentRow("person.2", "People", .familyMember, .members, data.sidebarMembers)
                    }
                }
            }

            statementRow
            Rectangle().fill(LBColor.hairline.color).frame(height: 1)
            // The two quick doors side by side. Settings, What's New, Ask Support, Check for
            // Updates and Quit are in the menu bar.
            HStack(spacing: 0) {
                iconButton(
                    colorScheme == .dark ? "sun.max" : "moon",
                    colorScheme == .dark ? "Switch to the light appearance" : "Switch to the dark appearance",
                    active: false,
                    insets: EdgeInsets(top: LBSpacing.s2, leading: LBSpacing.s3, bottom: LBSpacing.s3, trailing: LBSpacing.s1)
                ) {
                    appearance = (colorScheme == .dark ? LBAppearance.light : LBAppearance.dark).rawValue
                }
                iconButton(
                    shown == .bookmarks ? "bookmark.fill" : "bookmark", "Bookmarks", active: shown == .bookmarks,
                    insets: EdgeInsets(top: LBSpacing.s2, leading: 0, bottom: LBSpacing.s3, trailing: LBSpacing.s3)
                ) {
                    path = [.bookmarks]
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(LBColor.sunken.color)
        .overlay(alignment: .trailing) {
            Rectangle().fill(LBColor.hairline.color).frame(width: 1)
        }
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

    /// A quiet door at the foot, so it is found that statements can be dropped: a click picks
    /// them, a drop on it or anywhere in the window imports them, and a drag lights it.
    @ViewBuilder
    private var statementRow: some View {
        if let importStatements {
            let lit = droppingStatement || statementOverRow
            let insets = Self.rowInsets(top: LBSpacing.s1, bottom: LBSpacing.s2)
            Button {
                Measure.used("sidebar_import_statements")
                pickingStatements = true
            } label: {
                HStack(spacing: LBSpacing.s2) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 11, weight: .medium))
                    Text("Drop statements here").lbText(.footnote)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(lit ? LBColor.brandText.color : LBColor.textSecondary.color)
                .padding(.horizontal, LBSpacing.s2)
                .frame(height: Self.pillHeight)
                // The brand tint whether or not the window is in front: a drag comes from Finder.
                .background(lit ? LBColor.brand.color.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                .rowArea(insets)
            }
            .lbButtonStyle(.inset(LBRadius.xs, insets))
            .help("Import statements")
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                Measure.used("sidebar_statement_drop")
                importStatements(urls)
                return true
            } isTargeted: { statementOverRow = $0 }
            .fileImporter(isPresented: $pickingStatements, allowedContentTypes: StatementImportView.pickable,
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, !urls.isEmpty else { return }
                importStatements(Array(urls.prefix(StatementImportView.filesAtOnce)))
            }
            .animation(.easeOut(duration: 0.12), value: lit)
        }
    }

    /// A square control in the footer, lit the way a row is when its screen is open.
    private func iconButton(
        _ symbol: String, _ label: String, active: Bool, insets: EdgeInsets, action: @escaping () -> Void
    ) -> some View {
        Button(action: { Measure.used("sidebar_item"); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? LBColor.onBrandTint.color : LBColor.textSecondary.color)
                .frame(width: 30, height: 30)
                .lbSelectionFill(active, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                .padding(insets)
                .contentShape(Rectangle())
        }
        .lbButtonStyle(.inset(LBRadius.xs, insets))
        .help(label)
        .accessibilityLabel(label)
    }

    private func navRow(
        _ symbol: String, _ title: String, active: Bool, attention: Bool = false, insets: EdgeInsets = SidebarView.rowInsets(),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { Measure.used("sidebar_row"); action() }) {
            rowLabel(symbol, title, active: active, attention: attention)
                .rowArea(insets)
        }
        .lbButtonStyle(.inset(LBRadius.xs, insets))
        .accessibilityElement(children: .combine)
    }

    /// Accounts or People, with its starred rows a little inside it. The parent stays
    /// unlit while one of those rows is the one open.
    @ViewBuilder
    private func parentRow(
        _ symbol: String, _ title: String, _ kind: VaultPatch.EntityKind, _ screen: Destination,
        _ rows: [DashboardData.SidebarEntity]
    ) -> some View {
        let starred = rows.filter(\.starred)
        let open = openRow(kind)
        navRow(symbol, title, active: isOnScreen(kind) && !starred.contains { $0.id == open }) { path = [screen] }
        ForEach(starred) { row in
            childRow(row, kind: kind, screen: screen, active: row.id == open)
        }
    }

    /// A row's face.
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
        .frame(height: Self.pillHeight)
        .lbSelectionFill(active, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
    }

    /// One starred account or person: opens it selected on its screen, with its panel open.
    /// A form holding changes asks first, as any other door does.
    private func childRow(
        _ row: DashboardData.SidebarEntity, kind: VaultPatch.EntityKind, screen: Destination, active: Bool
    ) -> some View {
        let insets = Self.rowInsets(indent: Self.childIndent)
        return Button {
            Measure.used("sidebar_starred_row")
            PanelForm.shared.ask {
                ScreenMemory.shared.open(row.id, on: kind.memoryKey)
                path = [screen]
            }
        } label: {
            HStack(spacing: LBSpacing.s2) {
                EntityAvatar(name: row.name, ink: row.ink, size: 16, photo: row.photo)
                Text(row.name)
                    .lbText(.bodySM)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? LBColor.onBrandTint.color : LBColor.textSecondary.color)
            .padding(.horizontal, LBSpacing.s2)
            .frame(height: Self.pillHeight)
            .lbSelectionFill(active, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .rowArea(insets)
        }
        .lbButtonStyle(.inset(LBRadius.xs, insets))
        .help(row.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
    }
}

private extension View {
    /// A row's whole answering area around its pill.
    func rowArea(_ insets: EdgeInsets) -> some View {
        padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
#endif
