import SwiftUI

/// A screen's short tutorial: shown the first time the screen opens on this device, replayed
/// from Settings > Tutorials. Each device keeps its own, so one seen on the iPhone still shows
/// the first time the same screen opens on the Mac.
enum ScreenTutorial: String, CaseIterable, Identifiable {
    case dashboard, commitments, calendar, reports, accounts, people, insights, changes, settings

    var id: String { rawValue }

    /// The screen's name, as its title and the tab or sidebar row say it.
    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .commitments: "Commitments"
        case .calendar: "Calendar"
        case .reports: "Reports"
        case .accounts: "Accounts"
        case .people: "People"
        case .insights: "Insights"
        // The Proposals screen; its code name is `changes`.
        case .changes: "Proposals"
        case .settings: "Settings"
        }
    }

    /// The ones this device has a screen for: the Mac's settings are a window of their own.
    static var listed: [ScreenTutorial] {
        #if os(macOS)
        allCases.filter { $0 != .settings }
        #else
        allCases
        #endif
    }

    /// Where the screen opens, for a replay; nil is the dashboard, or Settings on the phone.
    var destination: Destination? {
        switch self {
        case .dashboard, .settings: nil
        case .commitments: .commitments(ListFilter())
        case .calendar: .calendar
        case .reports: .reports
        case .accounts: .accounts
        case .people: .members
        case .insights: .insights
        case .changes: .changes
        }
    }

    /// The card counted as a popover while it shows, over the screen it explains.
    var popupName: StaticString {
        switch self {
        case .dashboard: "dashboard_tutorial"
        case .commitments: "commitments_tutorial"
        case .calendar: "calendar_tutorial"
        case .reports: "reports_tutorial"
        case .accounts: "accounts_tutorial"
        case .people: "people_tutorial"
        case .insights: "insights_tutorial"
        case .changes: "changes_tutorial"
        case .settings: "settings_tutorial"
        }
    }

    /// Replay on its row in Settings > Tutorials.
    var replayControl: StaticString {
        switch self {
        case .dashboard: "replay_dashboard_tutorial"
        case .commitments: "replay_commitments_tutorial"
        case .calendar: "replay_calendar_tutorial"
        case .reports: "replay_reports_tutorial"
        case .accounts: "replay_accounts_tutorial"
        case .people: "replay_people_tutorial"
        case .insights: "replay_insights_tutorial"
        case .changes: "replay_changes_tutorial"
        case .settings: "replay_settings_tutorial"
        }
    }

    /// Every step the screen can show. A step whose part of the screen is not there when the
    /// tutorial starts — an empty list, a pane not open — is left out; one with no part is
    /// a card on its own.
    var steps: [TutorialStep] {
        switch self {
        case .dashboard:
            [
                TutorialStep(.dashboardNextPayment, "Your next payment",
                             "Here you see your next payment: what it is, how much, and when it is due. \(Self.tap.capitalizedFirst) it to open it."),
                TutorialStep(.dashboardComingUp, "Your next 30 days",
                             "Here you see every payment coming up in the next 30 days, in the order you pay them."),
                TutorialStep(.dashboardSpending, "Your spending",
                             "Here you see what you spent this month, day by day. \(Self.tap.capitalizedFirst) the month to look at another."),
                // The Mac's + sits in the window's toolbar, which the overlay cannot light.
                TutorialStep(Self.mac ? nil : .addCommitment, "Add anything", Self.mac
                             ? "Click + in the toolbar, or press ⌘N, to put in a commitment or an expense from any screen."
                             : "Tap Add to put in a commitment or an expense, from any screen."),
                TutorialStep(nil, "Every screen has its own tutorial",
                             "When you open a screen for the first time, a short tutorial like this one shows you around. You can replay any of them in Settings > Tutorials."),
            ]
        case .commitments:
            [
                // The phone's search bar is the system's and moves with the screen, so its
                // step is a card on its own there.
                TutorialStep(Self.mac ? .commitmentsSearch : nil, "Find anything", Self.mac
                             ? "Search your commitments by name, category, person or account."
                             : "Use the search bar to find a commitment by name, category, person or account."),
                TutorialStep(.commitmentsScope, "Upcoming and past",
                             "Upcoming shows what you pay next. Past shows what you have already paid."),
                TutorialStep(.commitmentsFirst, "Your commitment", Self.mac
                             ? "Here you see when it is due, how much, and its category, person and account. Click it to open it; right-click it to mark it paid."
                             : "Here you see when it is due, how much, and its category, person and account. Tap it to open it; swipe it to mark it paid."),
                TutorialStep(.commitmentsAdd, "Add a commitment", Self.mac
                             ? "Click Add to put in a commitment by hand, or import a statement to add many at once."
                             : "Tap Add to put in a commitment by hand, or import a statement to add many at once."),
            ]
        case .calendar:
            [
                TutorialStep(.calendarMonth, "Your month",
                             "Here you see every day of this month. Days with a payment due are marked."),
                TutorialStep(.calendarDay, "Your day", Self.mac
                             ? "Click a day to see what is due on it. Mark Paid settles a payment once it is done."
                             : "Tap a day to see what is due on it, and mark each payment paid once it is done."),
            ]
        case .reports:
            [
                TutorialStep(.reportsList, "Your months",
                             "Every month with a confirmed payment gets its own report. \(Self.tap.capitalizedFirst) one to open it."),
                TutorialStep(.reportsEarlier, "Earlier years", "Months from earlier years sit under their own year."),
                TutorialStep(.reportsTotal, "Your total",
                             "Here you see what you spent that month, then by account and by category below."),
                TutorialStep(.reportsShare, "Share", "Share the report as a PDF with anyone who needs it."),
            ]
        case .accounts:
            [
                TutorialStep(.entityList, "Your accounts", Self.mac
                             ? "Every bank account and card you pay from, with its balance. Select one to see it on the right."
                             : "Every bank account and card you pay from, with its balance. Tap one to see what is paid from it."),
                TutorialStep(.entityAdd, "Add an account", Self.mac
                             ? "Click Add Account to put in another account or card."
                             : "Tap Add to put in another account or card."),
            ]
        case .people:
            [
                TutorialStep(.entityList, "Your people", Self.mac
                             ? "Everyone you pay for: family, staff, anyone else. Select a name to see it on the right."
                             : "Everyone you pay for: family, staff, anyone else. Tap a name to see what is theirs."),
                TutorialStep(.entityAdd, "Add a person", Self.mac
                             ? "Click Add Person to put in someone new."
                             : "Tap Add to put in someone new."),
            ]
        case .insights:
            [
                TutorialStep(.insightsFirst, "Notes from your AI",
                             "Your AI leaves short notes about your money here, under the screen each one is about."),
                TutorialStep(.insightsEntities, "By account and person",
                             "Notes about one account or person sit under its name."),
            ]
        case .changes:
            [
                TutorialStep(.changesKinds, "What your AI proposed",
                             "Here you see everything your AI proposed, sorted into charges, commitments, accounts and people."),
                TutorialStep(.changesFirst, "Each proposal", "\(Self.tap.capitalizedFirst) a proposal to see it in full."),
                TutorialStep(.changesAll, "All at once", "Keep All or Undo All settles every proposal in one \(Self.tap)."),
                TutorialStep(.changesDetail, "The proposal in full",
                             "Here you see the proposal in full. Edit it or delete it if it isn’t right."),
            ]
        case .settings:
            [
                TutorialStep(.settingsLongbook, "Your longbook", "Proposals, Insights, Bookmarks, Accounts and People are here."),
                TutorialStep(.settingsImport, "Import a statement", "Add a statement any time to bring your longbook up to date."),
            ]
        }
    }

    /// The last card says where the tutorial comes back from; the dashboard's already does.
    var replayNote: String? {
        self == .dashboard ? nil : "You can replay this tutorial in Settings > Tutorials."
    }

    private static var mac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// The verb a hand uses on this device.
    private static var tap: String { mac ? "click" : "tap" }
}

/// One card of a tutorial, and the part of the screen it lights.
struct TutorialStep {
    let target: TutorialTarget?
    let title: String
    let body: String

    init(_ target: TutorialTarget?, _ title: String, _ body: String) {
        self.target = target
        self.title = title
        self.body = body
    }
}

/// A part of a screen a tutorial can light. A screen marks its parts; whichever is on show
/// when the tutorial starts is the one used, and parts marked more than once are lit together.
enum TutorialTarget: Hashable {
    case dashboardNextPayment, dashboardComingUp, dashboardSpending, addCommitment
    case commitmentsSearch, commitmentsScope, commitmentsFirst, commitmentsAdd
    case calendarMonth, calendarDay
    case reportsList, reportsEarlier, reportsTotal, reportsShare
    case entityList, entityAdd
    case insightsFirst, insightsEntities
    case changesKinds, changesFirst, changesAll, changesDetail
    case settingsLongbook, settingsImport
}

extension Notification.Name {
    /// Settings > Tutorials asks the main window to open a screen for its tutorial.
    static let longbookOpenTutorial = Notification.Name("longbook.openTutorial")
}

/// Which tutorials this device has shown, and the one showing now. What has been seen is
/// kept in this device's defaults, never in the vault, so every device keeps its own.
@MainActor
@Observable
final class TutorialCenter {
    static let shared = TutorialCenter()

    /// The tutorial on screen, its steps as they were found, and the one showing.
    private(set) var active: ScreenTutorial?
    private(set) var steps: [TutorialStep] = []
    private(set) var step = 0
    /// Bumped when what has been seen changes, so Settings > Tutorials redraws.
    private(set) var seenRevision = 0
    /// Where the lit parts sit, in window points; several marks for one part are joined.
    @ObservationIgnored private var frames: [TutorialTarget: [UUID: CGRect]] = [:]
    /// The same frames for the card's ring, read while a tutorial shows.
    private(set) var liveFrames: [TutorialTarget: CGRect] = [:]
    /// The window area the overlay covers, so a part scrolled out of sight is not lit.
    @ObservationIgnored var canvas: CGRect = .zero
    /// Screens on show, newest last: a pushed screen stands over the one it came from.
    @ObservationIgnored private var onScreen: [ScreenTutorial] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// True while something stands over the book, the demo longbook above all.
    @ObservationIgnored private var holds = 0

    /// A moment for the screen to settle before its tutorial starts.
    private static let delay: Duration = .milliseconds(800)

    private init() {}

    #if DEBUG
    /// The picture harness photographs screens as they are; a tutorial over them would hide them.
    private static let disabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        return ["LONGBOOK_SNAPSHOT", "LONGBOOK_SNAPSHOT_SCREEN", "LONGBOOK_WINDOW_SNAPSHOT", "LONGBOOK_NO_TUTORIALS"]
            .contains { env[$0] != nil }
    }()
    #else
    private static let disabled = false
    #endif

    private static func key(_ screen: ScreenTutorial) -> String { "tutorial.seen." + screen.rawValue }

    func isSeen(_ screen: ScreenTutorial) -> Bool {
        UserDefaults.standard.bool(forKey: Self.key(screen))
    }

    // MARK: screens

    func appeared(_ screen: ScreenTutorial) {
        onScreen.append(screen)
        schedule(screen)
    }

    func disappeared(_ screen: ScreenTutorial) {
        if let at = onScreen.lastIndex(of: screen) { onScreen.remove(at: at) }
        // Leaving a screen mid-tutorial ends it unseen: it starts again on the next visit.
        if active == screen { end() }
        // A screen can go after the next one arrives — a tab switch from a pushed page passes
        // its root on the way — so whatever is on top now gets its turn.
        if active == nil, let top = onScreen.last { schedule(top) }
    }

    /// The demo longbook, or anything else that covers the book, holds tutorials back.
    func hold(_ on: Bool) {
        holds = max(0, holds + (on ? 1 : -1))
        if holds > 0 {
            pending?.cancel()
            end()
        } else if let top = onScreen.last {
            schedule(top)
        }
    }

    private func schedule(_ screen: ScreenTutorial) {
        guard !Self.disabled, !isSeen(screen) else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard let self, !Task.isCancelled, onScreen.last == screen, active == nil, holds == 0 else { return }
            start(screen)
        }
    }

    /// The steps whose parts are on show, in order. With none of its parts there yet — an
    /// empty list — the tutorial waits for a visit that has them.
    private func start(_ screen: ScreenTutorial) {
        let found = screen.steps.filter { step in step.target.map { visibleRect($0) != nil } ?? true }
        guard found.contains(where: { $0.target != nil }) else { return }
        steps = found
        step = 0
        refreshLive()
        active = screen
    }

    func next() {
        if step + 1 < steps.count {
            refreshLive()
            step += 1
        } else {
            finish()
        }
    }

    /// Done or Skip: the tutorial is seen on this device.
    func finish() {
        guard let screen = active else { return }
        UserDefaults.standard.set(true, forKey: Self.key(screen))
        seenRevision += 1
        end()
    }

    private func end() {
        active = nil
        steps = []
        step = 0
    }

    // MARK: replay

    func replay(_ screen: ScreenTutorial) {
        UserDefaults.standard.removeObject(forKey: Self.key(screen))
        seenRevision += 1
        // Already on show, as the Mac's dashboard may be: it starts here, with no visit.
        if onScreen.last == screen { schedule(screen) }
    }

    func replayAll() {
        for screen in ScreenTutorial.allCases { UserDefaults.standard.removeObject(forKey: Self.key(screen)) }
        seenRevision += 1
        if let top = onScreen.last { schedule(top) }
    }

    // MARK: parts of the screen

    func setFrame(_ target: TutorialTarget, id: UUID, rect: CGRect) {
        frames[target, default: [:]][id] = rect
        if active != nil { refreshLive() }
    }

    func removeFrame(_ target: TutorialTarget, id: UUID) {
        frames[target]?[id] = nil
        if active != nil { refreshLive() }
    }

    private func union(_ target: TutorialTarget) -> CGRect? {
        guard let rects = frames[target]?.values, let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    /// The part as far as it is on screen; nil when too little of it shows to point at.
    private func visibleRect(_ target: TutorialTarget) -> CGRect? {
        guard let rect = union(target) else { return nil }
        let shown = canvas == .zero ? rect : rect.intersection(canvas)
        return shown.isNull || shown.height < 20 || shown.width < 20 ? nil : shown
    }

    /// Only the steps' own parts are copied, so a scroll elsewhere redraws nothing.
    private func refreshLive() {
        var live: [TutorialTarget: CGRect] = [:]
        for step in steps { if let target = step.target, let rect = visibleRect(target) { live[target] = rect } }
        if live != liveFrames { liveFrames = live }
    }
}
