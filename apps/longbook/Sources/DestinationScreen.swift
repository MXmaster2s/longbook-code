import DesignSystem
import LongbookCore
import SwiftUI

/// The screen a destination names, for any stack that pushes one: the main window's and
/// the Mac's Settings window. The two doors that reach outside the screen are passed in.
struct DestinationScreen: View {
    let destination: Destination
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    @Binding var path: [Destination]
    let importStatement: () -> Void
    let setUpAgain: () -> Void
    /// The demo longbook, where the window can show one over the book.
    var showDemo: (() -> Void)? = nil

    var body: some View {
        switch destination {
        case .commitments(let filter):
            // Re-identified per value: swapping one filter for another must not keep
            // the old screen's state alive.
            CommitmentsView(model: model, filter: filter)
                .id(destination)
        case .calendar:
            CalendarView(model: model)
        case .accounts:
            AccountsView(model: model)
        case .members:
            MembersView(model: model)
        case .reports:
            ReportsView(model: model, auth: auth)
        case .report(let id):
            ReportDetailView(model: model, id: id, auth: auth)
        case .commitment(let id):
            #if os(macOS)
            // The Mac reads a commitment in the list's inspector; a page of its own would
            // say the same thing twice.
            CommitmentsView(model: model, filter: ListFilter(), focus: id)
                .id(destination)
            #else
            CommitmentDetailView(model: model, id: id)
            #endif
        case .card(let card):
            #if os(macOS)
            // The Mac reads a card in the inspector of the list that holds it.
            macCard(card).id(destination)
            #else
            PushedCardPreview(model: model, card: card)
            #endif
        case .insights:
            InsightsView(model: model, path: $path)
        case .changes:
            ChangesView(model: model)
        case .mcpServer:
            AutomationsView(model: model, auth: auth)
        case .tips:
            TipsView(importStatement: importStatement)
        // One account screen: both old doors open it, so the sidebar, deep links and the
        // picture harness keep working.
        case .accountDetails, .billing:
            AccountScreenView(auth: auth, entitlement: entitlement)
        case .display:
            DisplayCurrencyView(model: model)
        case .privacy:
            DataPrivacyView(model: model)
        case .helpAbout:
            HelpAboutView(model: model)
        case .signOut:
            SignOutScreenView(auth: auth)
        case .updates:
            UpdatesView()
        case .trips:
            TripsView(model: model, path: $path)
        case .more:
            MoreView(model: model, auth: auth, onTutorial: setUpAgain, onDemo: showDemo)
        case .tutorials:
            TutorialsView()
        case .support:
            SupportScreen(auth: auth)
        case .bookmarks:
            BookmarksView(model: model)
        case .search:
            #if os(iOS)
            SearchScreen(model: model, path: $path)
            #else
            // The Mac searches from its sidebar field and ⌘K; nothing pushes this there.
            EmptyView()
            #endif
        }
    }
}

#if os(macOS)
extension DestinationScreen {
    @ViewBuilder
    fileprivate func macCard(_ card: CardRef) -> some View {
        switch card {
        case .charge(let subId, let id):
            CommitmentsView(model: model, filter: Self.list(holding: model.chargeItem(id: id)), focus: subId, focusCharge: id)
        case .commitment(let id):
            CommitmentsView(model: model, filter: ListFilter(), focus: id)
        case .entity(let kind, let id):
            EntityListView(model: model, kind: kind, focus: id)
        }
    }

    /// The list a charge stands in: its kind's behind today, or its own day ahead, where the
    /// list shows charges rather than commitments.
    private static func list(holding charge: DashboardModel.ChargeItem?) -> ListFilter {
        guard let charge else { return ListFilter() }
        guard charge.isPast else { return ListFilter(scope: .upcoming, day: charge.dateISO) }
        return ListFilter(scope: .past, kind: charge.isIncome ? .earnings : (charge.isTransfer ? .transfers : .charges))
    }
}

/// The Mac's one session: the main window and the Settings window read the same model,
/// account and licence, so a change made in either is the other's at once.
@MainActor
final class AppSession {
    static let shared = AppSession()
    let model = DashboardModel()
    let auth = AuthViewModel()
    let entitlement = EntitlementStore()
    private init() {}
}
#endif
