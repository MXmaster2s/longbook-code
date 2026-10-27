#if os(macOS)
import DesignSystem
import LongbookCore
import SwiftUI

/// The Mac sidebar: the system's list in the sidebar style, on the design's flat tone. Its
/// rows, selection, symbol column and size setting are the system's; only the material is
/// off. Starred accounts and people sit indented under Accounts and People.
struct SidebarView: View {
    let model: DashboardModel
    @Binding var path: [Destination]

    /// One row: a screen, or one starred account or person.
    enum Row: Hashable {
        case dashboard, reports, calendar, commitments, insights, changes, accounts, members
        case account(String), member(String)

        /// Where the row goes. The sidebar replaces the path: its screens are roots.
        var destination: [Destination] {
            switch self {
            case .dashboard: []
            case .reports: [.reports]
            case .calendar: [.calendar]
            case .commitments: [.commitments(ListFilter())]
            case .insights: [.insights]
            case .changes: [.changes]
            case .accounts: [.accounts]
            case .members: [.members]
            case .account(let id): [.commitments(ListFilter(methodId: id))]
            case .member(let id): [.commitments(ListFilter(memberId: id))]
            }
        }
    }

    /// The screen on show. The harness paints its screen as the stack root with an empty
    /// path, so the row it names stays lit there too.
    private var shown: Destination? {
        #if DEBUG
        path.last ?? RootView.snapshotDestination()
        #else
        path.last
        #endif
    }

    /// The row lit for the screen on show: a report lights Reports, one commitment or any
    /// narrowed list lights Commitments, a starred account's own list lights its row.
    private var lit: Row? {
        switch shown {
        case nil: .dashboard
        case .reports, .report: .reports
        case .calendar: .calendar
        case .insights: .insights
        case .changes: .changes
        case .accounts: .accounts
        case .members: .members
        case .commitment: .commitments
        case .commitments(let filter):
            if let id = filter.methodId, filter == ListFilter(methodId: id) { .account(id) }
            else if let id = filter.memberId, filter == ListFilter(memberId: id) { .member(id) }
            else { .commitments }
        default: nil
        }
    }

    /// The list's selection is the path: a click replaces it, a change elsewhere lights the row.
    private var selection: Binding<Row?> {
        Binding(get: { lit }, set: { row in
            guard let row, row != lit else { return }
            Measure.used("sidebar_row")
            path = row.destination
        })
    }

    var body: some View {
        List(selection: selection) {
            row(.dashboard, "Dashboard", "square.grid.2x2.fill")
            row(.reports, "Reports", "chart.bar")
            row(.calendar, "Calendar", LBGlyph.date)
            row(.commitments, "Commitments", LBGlyph.commitment)
            row(.insights, "Insights", "lightbulb")
            row(.changes, "Proposals", LBGlyph.change, attention: model.outsideChangeFrom != nil)
            if case .loaded(let data) = model.state {
                row(.accounts, "Accounts", LBGlyph.account)
                    .padding(.top, LBSpacing.s3)
                starredRows(data.sidebarMethods) { .account($0.id) }
                row(.members, "People", "person.2")
                    .padding(.top, LBSpacing.s3)
                starredRows(data.sidebarMembers) { .member($0.id) }
            }
        }
        .listStyle(.sidebar)
        // The material off: the sidebar is a tone step below the canvas, under the toolbar too.
        .scrollContentBackground(.hidden)
        .background(LBColor.sunken.color)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
    }

    /// A screen's row: the symbol on the system's column, the name at the body size.
    private func row(_ id: Row, _ title: String, _ symbol: String, attention: Bool = false) -> some View {
        HStack {
            Label { Text(title).lbText(.body) } icon: { Image(systemName: symbol) }
            if attention {
                Spacer(minLength: 0)
                Circle()
                    .fill(LBColor.urgent.color)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("waiting for review")
            }
        }
        .tag(id)
    }

    /// The starred rows of a group, indented under the group's own row as a channel list is.
    private func starredRows(
        _ rows: [DashboardData.SidebarEntity], id: @escaping (DashboardData.SidebarEntity) -> Row
    ) -> some View {
        ForEach(rows.filter(\.starred)) { entity in
            Label {
                Text(entity.name).lbText(.body).lineLimit(1)
            } icon: {
                Circle()
                    .fill(LBColor.dataInk(rank: entity.ink).color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 20)
            .badge(entity.count)
            .tag(id(entity))
            .accessibilityLabel("\(entity.name), \(entity.count) commitments")
        }
    }
}
#endif
