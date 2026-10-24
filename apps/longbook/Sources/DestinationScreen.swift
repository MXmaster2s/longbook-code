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
        }
    }
}

#if os(macOS)
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

/// The Settings window (⌘,): a toolbar of tabs, as a Mac app's settings are. What is not a
/// setting lives in the menus: Import in File, Optimize Your Data and Tips in Help, Check for
/// Updates in the app menu, Trips in Go.
struct SettingsWindowView: View {
    @ObservedObject private var auth = AppSession.shared.auth
    @ObservedObject private var entitlement = AppSession.shared.entitlement
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue
    @Environment(\.openWindow) private var openWindow

    private var model: DashboardModel { AppSession.shared.model }

    var body: some View {
        SettingsTabs(model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow)
            .frame(minWidth: 600, idealWidth: 720, minHeight: 520, idealHeight: 720)
            .background(LBColor.canvas.color)
            .background(CentersSheets())
            .preferredColorScheme((LBAppearance(rawValue: appearance) ?? .dark).colorScheme)
            .onAppear { model.loadIfNeeded() }
    }

    private func toMainWindow(_ name: Notification.Name) {
        openWindow(id: LongbookWindow.main)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: name, object: nil)
    }
}

/// The settings themselves, one tab each: General, Account, AI and Data.
struct SettingsTabs: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    let toMainWindow: (Notification.Name) -> Void
    @State private var picked: Destination

    init(
        model: DashboardModel, auth: AuthViewModel, entitlement: EntitlementStore,
        start: Destination = .display, toMainWindow: @escaping (Notification.Name) -> Void
    ) {
        self.model = model
        self.auth = auth
        self.entitlement = entitlement
        self.toMainWindow = toMainWindow
        _picked = State(initialValue: start)
    }

    /// Each tab's screen, name and symbol, in toolbar order.
    static let tabs: [(root: Destination, title: String, symbol: String)] = [
        (.display, "General", "gearshape"),
        (.accountDetails, "Account", "person.crop.circle"),
        (.mcpServer, "AI", "sparkles"),
        (.privacy, "Data", "lock"),
    ]

    var body: some View {
        TabView(selection: $picked) {
            ForEach(Self.tabs, id: \.title) { item in
                tab(item.root)
                    .tabItem { Label(item.title, systemImage: item.symbol) }
                    .tag(item.root)
            }
        }
        .environmentObject(entitlement)
    }

    func tab(_ root: Destination) -> some View {
        SettingsTab(root: root, model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow)
    }
}

/// One tab's own stack, so a screen it opens comes back to the tab it was opened from.
struct SettingsTab: View {
    let root: Destination
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    let toMainWindow: (Notification.Name) -> Void
    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            screen(root)
                .navigationDestination(for: Destination.self) { screen($0) }
        }
    }

    private func screen(_ destination: Destination) -> some View {
        DestinationScreen(
            destination: destination, model: model, auth: auth, entitlement: entitlement, path: $path,
            importStatement: { toMainWindow(.longbookImport) },
            setUpAgain: { toMainWindow(.longbookSetUpAgain) }
        )
    }
}
#endif
