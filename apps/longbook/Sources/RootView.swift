import DesignSystem
import LongbookCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// How a door narrows the list. `scope` names the side it opens on; nil lets the window
/// decide, so this month opens on what is still coming and a month gone opens on what
/// landed. A month is named by any day inside it, first days in order.
struct ListFilter: Hashable {
    enum Scope: Hashable {
        case upcoming, past
    }

    var scope: Scope? = nil
    var day: String? = nil
    var months: [String] = []
    var methodId: String? = nil
    var memberId: String? = nil
    var category: String? = nil
    var bookmarked = false
    /// The Date chip's window as ISO days, either end open. No door passes one yet.
    var from: String? = nil
    var to: String? = nil
}

#if DEBUG
extension ListFilter {
    /// The harness's Date window: the id as "from,to" in ISO days, else the thirty days
    /// behind today through yesterday, which opens Past.
    static func snapshotRange(_ id: String) -> ListFilter {
        let parts = id.split(separator: ",").map(String.init)
        if parts.count == 2 { return ListFilter(from: parts[0], to: parts[1]) }
        let today = LB.todayMid()
        return ListFilter(from: LB.toISO(LB.addDays(today, -30)), to: LB.toISO(LB.addDays(today, -1)))
    }
}
#endif

/// Screens beyond the dashboard, pushed onto one navigation path that the Mac sidebar
/// also drives — one mechanism, two platforms.
enum Destination: Hashable {
    /// The list, narrowed as the filter says.
    case commitments(ListFilter)
    case calendar
    case accounts
    case members
    case reports
    case report(id: String)
    case commitment(id: String)
    case insights
    case changes
    case mcpServer
    case accountDetails
    case billing
    case display
    case privacy
    /// More as a pushed page: the phone tabs to it, the Mac hosts it in the Settings window.
    case more
    case tips
    case helpAbout
    /// What Sign out opens: this device or every session, and where the account is signed in.
    case signOut
    /// Check for updates: this version, what changed, and the way to a newer build.
    case updates
    /// Trips: start one from today, or add one that is over; each is a report.
    case trips

    /// The case name alone, for usage counts: never an id, a day, a month or a category.
    var screenName: String {
        switch self {
        case .commitments: "commitments"
        case .calendar: "calendar"
        case .accounts: "accounts"
        case .members: "members"
        case .reports: "reports"
        case .report: "report"
        case .commitment: "commitment"
        case .insights: "insights"
        case .changes: "changes"
        case .mcpServer: "mcpServer"
        case .accountDetails: "accountDetails"
        case .billing: "billing"
        case .display: "display"
        case .privacy: "privacy"
        case .more: "more"
        case .tips: "tips"
        case .helpAbout: "helpAbout"
        case .signOut: "signOut"
        case .updates: "updates"
        case .trips: "trips"
        }
    }

    /// A place the sidebar itself opens, so it needs no door back. A filtered list, a single
    /// commitment, a report, or a settings pane is reached from somewhere and needs one.
    var isSidebarRoot: Bool {
        switch self {
        case .reports, .calendar, .insights, .changes, .accounts, .members:
            true
        case .commitments(let filter):
            // An account's or a person's list is the sidebar's own row, so neither is a door.
            filter.scope == nil && filter.day == nil && filter.months.isEmpty && filter.category == nil && !filter.bookmarked
                && filter.from == nil && filter.to == nil
        default:
            false
        }
    }
}

/// One vault load feeds every pane. iPhone gets tabs; the Mac wraps the same stack in
/// the sidebar shell.
struct RootView: View {
    enum Tab {
        case dashboard, calendar, reports, more

        var screenName: String {
            switch self {
            case .dashboard: "dashboard"
            case .calendar: "calendar"
            case .reports: "reports"
            case .more: "more"
            }
        }
    }

    #if os(macOS)
    /// The one session the Settings window shares, so both read one model over one file.
    @State private var model = AppSession.shared.model
    @StateObject private var auth = AppSession.shared.auth
    @StateObject private var entitlement = AppSession.shared.entitlement
    #else
    @State private var model = DashboardModel()
    @StateObject private var auth = AuthViewModel()
    @StateObject private var entitlement = EntitlementStore()
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    /// App-local, not vault data: whether the owner has been through setup on this
    /// device. The vault stays the only place real facts live.
    @State private var path: [Destination] = []
    @State private var tab: Tab = .dashboard
    @State private var addingRenewal = false
    /// The statement importer as a sheet: the File menu's on the Mac, the harness's on the phone.
    @State private var importingStatement = false
    /// A commitment's or a charge's edit form as a sheet, for the harness on the phone.
    @State private var snapshotEditing = false
    /// The first run while it shows: where it begins, and whether the Waiting screen comes
    /// first. Decided once when the vault loads and held until it ends, so what it writes
    /// into the vault cannot dismiss it.
    @State private var onboarding: OnboardingSession?
    @State private var setupDone = false
    /// True when More reopened setup over a book that already holds something.
    @State private var setupReplay = false
    /// The demo longbook, opened from Settings over the book.
    @State private var showingDemo = false
    /// The two welcome pages, once per device, before the first sign-in.
    @AppStorage("longbook.welcomeSeen") private var welcomeSeen = false
    /// Set when sign-in's Back reopens the welcome, so it opens on its second page.
    @State private var welcomeBack = false
    /// Whether the first loaded vault has had the cloud queue applied to it.
    @State private var appliedOnFirstLoad = false
    /// How often the front window looks for an edit made elsewhere: one stat, nothing read.
    private static let filePoll: Duration = .seconds(5)
    /// The same look while the window is open but behind another app.
    private static let idlePoll: Duration = .seconds(30)
    /// How often proposals are fetched — after the file look, never before it.
    private static let proposalsEvery: Duration = .seconds(45)

    #if DEBUG
    /// Development only: lets the offscreen snapshot harness and simulator runs reach the
    /// app without a real inbox. Absent from release builds, so the gate is unconditional
    /// in the app anyone installs.
    private static let skipsAuth = ProcessInfo.processInfo.environment["LONGBOOK_SKIP_AUTH"] != nil
        || ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT"] != nil
        || ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] != nil
    /// True when the harness forces a first-run vault state (see `DashboardModel.load`).
    private static let forcesVault = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_VAULT"] != nil
    /// A paywall pictured on its own for App Review: the licence's purchase screen or the
    /// Cloud subscription's.
    private static let picturesPaywall = ["purchase", "cloudpaywall"].contains(ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] ?? "")
    /// The screen the harness named, as a destination. An id (a commitment, a report) rides
    /// in a second variable. Nil means the dashboard.
    static func snapshotDestination() -> Destination? {
        let env = ProcessInfo.processInfo.environment
        let id = env["LONGBOOK_SNAPSHOT_ID"] ?? ""
        switch env["LONGBOOK_SNAPSHOT_SCREEN"] {
        case "commitments": return .commitments(ListFilter())
        // Past by name: the month pictured may be this one, which would otherwise open ahead.
        case "charges": return .commitments(ListFilter(scope: .past, months: id.isEmpty ? [] : [id]))
        // The dashboard's No account door for a month: the list decides its side.
        case "noaccount": return .commitments(ListFilter(months: id.isEmpty ? [] : [id], methodId: DashboardModel.unassignedMethodId))
        // The list under a Date window, its chip wearing the words.
        case "daterange": return .commitments(ListFilter.snapshotRange(id))
        case "commitment": return .commitment(id: id)
        case "calendar": return .calendar
        case "accounts": return .accounts
        case "members": return .members
        case "insights": return .insights
        case "reports": return .reports
        case "report": return .report(id: id)
        case "changes": return .changes
        case "connectai", "automations": return .mcpServer
        case "tips": return .tips
        case "settings", "more": return .more
        case "account", "billing": return .accountDetails
        case "display": return .display
        case "privacy": return .privacy
        case "help", "helpabout": return .helpAbout
        case "signout": return .signOut
        case "updates": return .updates
        case "trips", "addtrip", "starttrip": return .trips
        default: return nil
        }
    }
    #else
    private static let skipsAuth = false
    private static let forcesVault = false
    private static let picturesPaywall = false
    #endif

    init() {
        // The phone opens the named screen the way a tap would: a tab as its own tab, the
        // add form as its sheet, anything else pushed. The Mac shows it as the stack root
        // instead, which an offscreen window paints where a push does not.
        #if DEBUG && os(iOS)
        switch ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] {
        case "calendar": _tab = State(initialValue: .calendar)
        case "reports": _tab = State(initialValue: .reports)
        case "settings", "more": _tab = State(initialValue: .more)
        case "addcommitment": _addingRenewal = State(initialValue: true)
        case "importstatement": _importingStatement = State(initialValue: true)
        case "editcommitment", "editcharge": _snapshotEditing = State(initialValue: true)
        case "picker", "setupmembers": _onboarding = State(initialValue: OnboardingSession(start: .commitments(card: 0), paused: false, model: DashboardModel(), replay: ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_REPLAY"] != nil))
        case "setupaccounts": _onboarding = State(initialValue: OnboardingSession(start: .accounts(card: 0), paused: false, model: DashboardModel()))
        case "setupstatement": _onboarding = State(initialValue: OnboardingSession(start: .finish, paused: false, model: DashboardModel()))
        case "setupsummary": _onboarding = State(initialValue: OnboardingSession(start: .commitmentsDone, paused: false, model: DashboardModel()))
        default:
            if let screen = Self.snapshotDestination() { _path = State(initialValue: [screen]) }
        }
        // Setup as More reopens it: the close control, and the seconds all the same.
        if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_REPLAY"] != nil { _setupReplay = State(initialValue: true) }
        #endif
        // The real Mac window, pictured by hand: the named screen opens in the sidebar, the
        // add form or the importer as its sheet. The offscreen harness hosts screens itself.
        #if DEBUG && os(macOS)
        let env = ProcessInfo.processInfo.environment
        if env["LONGBOOK_SNAPSHOT"] == nil {
            switch env["LONGBOOK_SNAPSHOT_SCREEN"] {
            case "addcommitment": _addingRenewal = State(initialValue: true)
            case "importstatement": _importingStatement = State(initialValue: true)
            default:
                if let screen = Self.snapshotDestination() { _path = State(initialValue: [screen]) }
            }
        }
        #endif
    }

    var body: some View {
        gate
            .task { auth.start() }
            // Crash reports are collected only while the owner's switch is on.
            .task { Telemetry.shared.start() }
            // Once per launch, when the sign-in state is first known.
            .onChange(of: auth.checked, initial: true) { _, checked in
                if checked { Telemetry.shared.launched(signedIn: auth.isSignedIn) }
            }
            // What the App Store delivers on its own — a purchase finished elsewhere, a
            // refund — reaches the server for as long as the app is open.
            .task { await StoreClient.shared.listen(auth: auth, entitlement: entitlement) }
            // Google's redirect first — its SDK says whether the URL was its own; every
            // other longbook:// link is the email flow's.
            .onOpenURL { url in
                if GoogleNative.handle(url) { return }
                auth.handle(url)
            }
            // Signing out clears the cache outright; signing in asks the server. Coming back
            // to the app re-asks, so a licence bought elsewhere lands without a relaunch.
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn {
                    Task { await entitlement.refresh() }
                    Task { await model.applyPendingWrites() }
                } else {
                    entitlement.clear()
                    // The next sign-in starts at the dashboard, not on whatever screen signed out.
                    path = []
                    tab = .dashboard
                }
            }
            // Time in front, for the session count: from becoming active to the background.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { Telemetry.shared.cameForward() }
                if phase == .background { Telemetry.shared.wentAway() }
            }
            .onChange(of: scenePhase) { _, phase in
                model.inForeground = phase != .background
                if phase == .active, auth.isSignedIn {
                    Task { await entitlement.refresh() }
                    // Anything an AI proposed while nobody was here lands now — through
                    // the outside door, so it waits in Changes to keep or undo.
                    Task { await model.applyPendingWrites() }
                }
            }
            // The cloud queue is skipped until a folder is open; the first loaded vault
            // asks once more, so a cold start does not wait for the next activation.
            .onChange(of: vaultLoaded, initial: true) { _, loaded in
                guard loaded else { return }
                // A report the server on this machine asked for needs no account.
                model.applyLocalRequests()
                guard !appliedOnFirstLoad, auth.isSignedIn else { return }
                appliedOnFirstLoad = true
                #if DEBUG
                // A harness run shares this Mac's keychain session: the owner's real queue is not its to apply.
                if Self.skipsAuth { return }
                #endif
                Task { await model.applyPendingWrites() }
            }
            // While the window is anywhere on screen: a look at the file every few seconds —
            // another device, an agent, Siri — and proposals every 45, after the look, so a
            // slow network never delays what is already on disk.
            .task(id: scenePhase) {
                guard scenePhase != .background else { return }
                var sinceProposals: Duration = .zero
                while !Task.isCancelled {
                    let wait = scenePhase == .active ? Self.filePoll : Self.idlePoll
                    try? await Task.sleep(for: wait)
                    guard !Task.isCancelled, scenePhase != .background else { return }
                    model.reloadIfFileMoved()
                    model.applyLocalRequests()
                    sinceProposals += wait
                    guard sinceProposals >= Self.proposalsEvery, auth.isSignedIn else { continue }
                    sinceProposals = .zero
                    await model.applyPendingWrites()
                }
            }
            .onChange(of: entitlement.state.readOnly, initial: true) { _, locked in
                model.readOnly = locked && TrialRibbon.enforced
            }
            // Cloud as the account holds it: the hosted copy, statement reading and shared
            // reports ask the model before they ask the server.
            .onChange(of: entitlement.state.hasCloud, initial: true) { _, cloud in
                model.hasCloud = cloud
            }
            .onChange(of: entitlement.state.trialEndsAt, initial: true) { _, ends in
                Telemetry.shared.trialSeen(endsAt: ends)
            }
            // The Cloud door opens from any screen, with the store this view holds.
            .environmentObject(entitlement)
            // The harness names its own first-run state; the live account must not overwrite it.
            .onChange(of: auth.returningAccount, initial: true) { _, returning in
                if !Self.forcesVault { model.returningAccount = returning }
            }
            .onChange(of: auth.email, initial: true) { _, address in
                model.signedInEmail = address
            }
            #if DEBUG && os(iOS)
            .measured("root_snapshot_editing", .sheet, when: snapshotEditing)
            .sheet(isPresented: $snapshotEditing) {
                SnapshotEditForm(model: model)
            }
            #endif
    }

    /// An account comes first: longbook is not usable signed out. The wait state exists so
    /// someone already signed in never sees the sign-in screen flash past.
    @ViewBuilder
    private var gate: some View {
        if Self.picturesPaywall {
            if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] == "purchase" {
                PurchaseView(auth: auth, entitlement: entitlement)
            } else {
                CloudPaywallView(auth: auth).environmentObject(entitlement)
            }
        } else if Self.skipsAuth {
            signedIn
        } else if auth.isSignedIn {
            licensed
        } else if auth.checked {
            if welcomeSeen {
                SignInView(auth: auth) { welcomeBack = true; welcomeSeen = false }
            } else {
                WelcomeView(startPage: welcomeBack ? 1 : 0) { welcomeSeen = true }
            }
        } else {
            waiting
        }
    }

    /// Then a licence: longbook is bought before use. The wait screen stands in until the
    /// server answers once, so a licensed owner never sees the purchase screen flash past;
    /// unanswered (offline on a first run), the app opens rather than locking anyone out.
    @ViewBuilder
    private var licensed: some View {
        if entitlement.state.signedIn {
            if entitlement.state.hasLicence { signedIn } else { PurchaseView(auth: auth, entitlement: entitlement) }
        } else if entitlement.known {
            signedIn
        } else {
            waiting
        }
    }

    private var waiting: some View {
        VStack(spacing: LBSpacing.s2) {
            Image("SidebarMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
            Text("longbook")
                .lbText(.body)
                .foregroundStyle(LBColor.textTertiary.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
    }

    /// A vault comes before setup, not after: onboarding's quick-add writes into the
    /// vault, so a reader who reaches it must already have one. `VaultChoiceView` is the
    /// gate that guarantees that — nothing past it can ever hit "nowhere to save".
    @ViewBuilder
    private var signedIn: some View {
        Group {
            switch model.state {
            case .loading:
                waiting
            case .provisioning, .firstRun, .unavailable, .failed:
                VaultChoiceView(model: model, auth: auth)
            case .loaded:
                if let onboarding {
                    // The first run stands in front of the book until it is one: commitments
                    // and accounts by kind, then the history, with a Waiting screen between.
                    OnboardingFlowView(model: model, auth: auth, session: onboarding, replay: setupReplay) {
                        self.onboarding = nil
                        setupReplay = false
                        setupDone = true
                    }
                } else {
                    replayable
                }
            }
        }
        .onAppear { model.load() }
        .task(id: loadedKey) { await openOnboardingIfDue() }
        .lbDismissesKeyboardOnTap()
        .modifier(DemoCover(showing: $showingDemo, auth: auth))
    }

    /// The demo longbook over the book: the whole screen on the phone, the whole window on the Mac.
    struct DemoCover: ViewModifier {
        @Binding var showing: Bool
        @ObservedObject var auth: AuthViewModel

        func body(content: Content) -> some View {
            #if os(iOS)
            content
                .measured("demo_cover", .sheet, when: showing)
                .fullScreenCover(isPresented: $showing) {
                DemoLongbookView(auth: auth) { showing = false }
            }
            #else
            content.overlay {
                if showing {
                    DemoLongbookView(auth: auth) { withAnimation(.easeOut(duration: 0.25)) { showing = false } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LBColor.canvas.color)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: showing)
            #endif
        }
    }

    /// Changes when the vault arrives or empties, so the first-run decision is made again.
    private var loadedKey: String {
        guard case .loaded = model.state else { return "none" }
        return model.isEmptyVault ? "empty" : "full"
    }

    /// A run begun and not finished resumes on the Waiting screen, wherever it was begun;
    /// an empty book never asked opens the first card. The account is asked too, since a
    /// device may know of a run before the folder does.
    private func openOnboardingIfDue() async {
        guard case .loaded = model.state, onboarding == nil, !setupDone else { return }
        if model.madeFreshVault {
            model.madeFreshVault = false
            onboarding = OnboardingSession(start: .commitments(card: 0), paused: false, model: model)
            return
        }
        if let stage = model.onboardingStage {
            if stage != .done { onboarding = OnboardingSession(start: stage, paused: true, model: model) }
            return
        }
        guard model.isEmptyVault, !model.commitmentsAsked else { return }
        if let progress = await OnboardingSync.pull(), let stage = OnboardingStage(raw: progress.stage),
           stage != .done, progress.device != OnboardingDevice.id {
            if onboarding == nil { onboarding = OnboardingSession(start: stage, paused: true, model: model) }
            return
        }
        if onboarding == nil { onboarding = OnboardingSession(start: .commitments(card: 0), paused: false, model: model) }
    }

    private var vaultLoaded: Bool {
        if case .loaded = model.state { return true }
        return false
    }

    /// Setup stays reachable after it has been through once — More has a row for it.
    private var replayable: some View { ribboned }

    /// The trial ribbon sits outside every screen rather than on one, so it survives
    /// navigation. It rides under the shell on the Mac, where the top strip is the hidden
    /// title bar's.
    private var ribboned: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            TrialRibbon(auth: auth, entitlement: entitlement)
            ReviewCard(model: model, path: $path)
            shell
            #else
            shell
            TrialRibbon(auth: auth, entitlement: entitlement)
            #endif
        }
        .background(LBColor.canvas.color)
        // Coming back to the app re-reads the file, so an edit made elsewhere — another
        // device, the owner's AI — is noticed the moment the app is.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.load() }
        }
        // Every screen change passes here: a push or a sidebar jump counts, a step back does
        // not. On the Mac an emptied path is the sidebar returning to the dashboard.
        .onChange(of: path) { old, new in
            #if os(macOS)
            if new.isEmpty, !old.isEmpty {
                Telemetry.shared.screen(Tab.dashboard.screenName, kind: .tab)
                return
            }
            #endif
            guard let last = new.last, last != old.last, !old.starts(with: new) else {
                // A step back sends nothing, but controls are on the page come back to.
                #if os(iOS)
                Telemetry.shared.cameBack(to: new.last?.screenName ?? tab.screenName)
                #else
                if let last = new.last { Telemetry.shared.cameBack(to: last.screenName) }
                #endif
                return
            }
            Telemetry.shared.screen(last.screenName)
        }
        #if os(iOS)
        .onChange(of: tab) { _, new in
            Telemetry.shared.screen(new.screenName, kind: .tab)
        }
        #endif
    }

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        // A plain split, not NavigationSplitView: this design's sidebar is a flat tone
        // step, and the system chrome would draw its own material over it.
        HStack(spacing: 0) {
            SidebarView(model: model, path: $path) { addingRenewal = true }
            NavigationStack(path: $path) {
                Group {
                    #if DEBUG
                    // The harness shows its screen as the root; a push does not paint offscreen.
                    if let screen = Self.snapshotDestination() { destinationView(screen) }
                    else { DashboardView(model: model, auth: auth, path: $path) }
                    #else
                    DashboardView(model: model, auth: auth, path: $path)
                    #endif
                }
                .navigationDestination(for: Destination.self) {
                    // The system back chevron would float into the hidden title
                    // bar; the in-pane bar and the shortcut are the doors back.
                    destinationView($0).navigationBarBackButtonHidden(true)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { macTopInsets }
        }
        .background(LBColor.canvas.color)
        .ignoresSafeArea()
        // Rings would fight the design's own focus language — selection is a fill here.
        .focusEffectDisabled()
        // Half of a 13-inch Air is 735pt, and macOS clamps a window to its minimum rather
        // than refusing to tile — so a floor above that overlapped the app beside it. With
        // the sidebar put away the panes still have their measure.
        .frame(minWidth: 720, minHeight: 620)
        .measured("root_adding_renewal", .sheet, when: addingRenewal)
        .sheet(isPresented: $addingRenewal) {
            RenewalFormView(model: model, editingId: nil) { addingRenewal = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .longbookGo)) { note in
            path = note.object as? [Destination] ?? []
        }
        .onReceive(NotificationCenter.default.publisher(for: .longbookPush)) { note in
            guard let destination = note.object as? Destination else { return }
            if path.last != destination { path.append(destination) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .longbookAdd)) { _ in
            addingRenewal = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .longbookBack)) { _ in
            if !path.isEmpty { path.removeLast() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .longbookImport)) { _ in
            importingStatement = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .longbookSetUpAgain)) { _ in
            setUpAgain()
        }
        .measured("root_importing_statement", .sheet, when: importingStatement)
        .sheet(isPresented: $importingStatement) {
            StatementImportView(model: model, auth: auth) { importingStatement = false }
        }
        // These listeners live here, so the menu bar can only act while this is on
        // screen. Saying so is what keeps a command from being offered and then ignored.
        .onAppear { MenuState.shared.shellReady = true }
        .onDisappear { MenuState.shared.shellReady = false }
        #else
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .dashboard: DashboardView(model: model, auth: auth, path: $path)
                case .calendar: CalendarView(model: model)
                case .reports: ReportsView(model: model, auth: auth)
                case .more: MoreView(model: model, auth: auth, onTutorial: setUpAgain, onDemo: { showingDemo = true })
                }
            }
            // On every screen, root and pushed alike, so a mis-tap deep in a list stays
            // one tap from anywhere. Seated INSIDE the stack because an inset on the
            // stack itself never reaches its scroll views — the last section of every
            // screen stayed pinned under the bar, unreachable by scrolling.
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .navigationDestination(for: Destination.self) {
                destinationView($0)
                    .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            }
        }
        .measured("root_adding_renewal", .sheet, when: addingRenewal)
        .sheet(isPresented: $addingRenewal) {
            RenewalFormView(model: model, editingId: nil) { addingRenewal = false }
        }
        .measured("root_importing_statement", .sheet, when: importingStatement)
        .sheet(isPresented: $importingStatement) {
            StatementImportView(model: model, auth: auth) { importingStatement = false }
        }
        #endif
    }

    private func destinationView(_ destination: Destination) -> some View {
        DestinationScreen(
            destination: destination, model: model, auth: auth, entitlement: entitlement, path: $path,
            importStatement: { importingStatement = true },
            setUpAgain: setUpAgain,
            showDemo: { showingDemo = true }
        )
    }

    /// More's Set up again, from whichever window holds it: the first card, over the book.
    private func setUpAgain() {
        setupReplay = true
        onboarding = OnboardingSession(start: .commitments(card: 0), paused: false, model: model, replay: true)
    }

    #if os(macOS)
    /// The review notice is the phone's, in the same seat: the full diff and Undo live on
    /// the Changes screen, and the strip hides itself there.
    private var macTopInsets: some View {
        VStack(spacing: 0) {
            ReviewCard(model: model, path: $path, clearsTitleBar: false)
            macBackBar
        }
    }

    /// A slim bar with one door back. The sidebar replaces the path, so its own
    /// destinations need no door; anything pushed on top of them does, Settings included,
    /// and so does a page that arrived by a link — a commitment opened from the dashboard.
    @ViewBuilder
    private var macBackBar: some View {
        if path.count > 1 || path.last.map({ !$0.isSidebarRoot }) == true {
            HStack {
                Button {
                    path.removeLast()
                } label: {
                    HStack(spacing: LBSpacing.s1) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back").lbText(.label)
                    }
                    .foregroundStyle(LBColor.textSecondary.color)
                    .padding(.horizontal, LBSpacing.s2)
                    .padding(.vertical, 4)
                    .background(LBColor.chrome.color, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, LBSpacing.s4)
            .padding(.top, LBSpacing.s4)
            .padding(.bottom, LBSpacing.s1)
        }
    }
    #endif

    #if os(iOS)
    /// The tab a pushed screen belongs to: what More lists lights More, a report lights
    /// Reports. A list of commitments, or one of them, is reached from anywhere and keeps
    /// the tab it was opened from.
    private var litTab: Tab {
        guard let root = path.first else { return tab }
        switch root {
        case .changes, .insights, .accounts, .members, .mcpServer, .accountDetails, .billing, .display, .privacy, .more, .tips,
             .helpAbout, .signOut, .updates, .trips:
            return .more
        case .reports, .report:
            return .reports
        case .calendar:
            return .calendar
        case .commitments(let filter):
            return filter.bookmarked ? .more : tab
        case .commitment:
            return tab
        }
    }

    /// Four tabs around Add, each an icon over its name, as the system's tab bar draws them.
    /// The names match the titles of the screens they open.
    private var tabBar: some View {
        let tab = litTab
        return HStack(alignment: .top, spacing: 0) {
            tabItem("square.grid.2x2.fill", "Dashboard", active: tab == .dashboard) { path = []; self.tab = .dashboard }
            tabItem("calendar", "Calendar", active: tab == .calendar) { path = []; self.tab = .calendar }
            Button {
                addingRenewal = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(height: 26)
                    if !typeSize.isAccessibilitySize {
                        Text("Add")
                            .lbText(.tabLabel)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(LBColor.brandText.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a commitment")
            .accessibilityShowsLargeContentViewer { Label("Add", systemImage: "plus.circle.fill") }
            tabItem("chart.bar.fill", "Reports", active: tab == .reports) { path = []; self.tab = .reports }
            tabItem("gearshape", "Settings", active: tab == .more) { path = []; self.tab = .more }
        }
        .padding(.horizontal, LBSpacing.s2)
        .padding(.top, LBSpacing.s1)
        .background(LBColor.sunken.color)
        .overlay(alignment: .top) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
    }

    /// The name sits on one line and may shrink a little before it would wrap. At the
    /// accessibility sizes the bar shows icons alone, as the system's does, and a long press
    /// shows the name large.
    private func tabItem(
        _ symbol: String, _ label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 26)
                if !typeSize.isAccessibilitySize {
                    Text(label)
                        .lbText(.tabLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(active ? LBColor.brandText.color : LBColor.textTertiary.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }
    #endif
}
