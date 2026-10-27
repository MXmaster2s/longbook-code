#if os(macOS)
import SwiftUI

/// The menu bar's voice into the running window. Commands live on the App scene and
/// the window owns the state, so the two meet on notifications — one poster, one
/// listener, no shared object.
/// The window's identifier, so the tray and the menu can put a closed one back.
enum LongbookWindow {
    static let main = "longbook.main"
}

/// A toolbar action with a menu command: the screen on show answers it. Every toolbar
/// item has one, so the keyboard reaches what the pointer can.
enum MacCommand: Hashable {
    case markPaid, bookmark, edit
    case newEntity
    case today, previousMonth, nextMonth
    case refresh, history, howItWorks
    case toggleInspector
}

/// Whether a window is on screen with the ledger in it, which screen, and what is chosen.
/// The menu bar asks before offering a command: an item that is present, enabled and silent
/// is worse than one that is dimmed.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var shellReady = false
    /// The screen on show; nil is the dashboard.
    @Published var screen: Destination?
    /// What Commitments has chosen: rows, whether any charge ahead is among them and all
    /// are paid, whether every chosen commitment is bookmarked.
    @Published var chosenRows = 0
    @Published var chosenCharges = false
    @Published var chosenAllPaid = false
    @Published var chosenAllBookmarked = false
    /// Whether Commitments shows its inspector.
    @Published var inspectorShown = false
    private init() {}

    /// The screen's case, ignoring what it carries.
    var screenName: String? { screen?.screenName }

    func send(_ command: MacCommand) {
        NotificationCenter.default.post(name: .longbookCommand, object: command)
    }
}

extension Notification.Name {
    static let longbookGo = Notification.Name("longbook.go")
    /// One destination onto the current path, rather than a path that replaces it.
    static let longbookPush = Notification.Name("longbook.push")
    static let longbookAdd = Notification.Name("longbook.add")
    static let longbookBack = Notification.Name("longbook.back")
    /// The statement importer, over the main window.
    static let longbookImport = Notification.Name("longbook.import")
    /// Optimize Your Data, asked of the main window from the Help menu or Settings.
    static let longbookSetUpAgain = Notification.Name("longbook.setUpAgain")
    /// Support, asked of the main window from the Help menu or the Settings window.
    static let longbookSupport = Notification.Name("longbook.support")
    /// The demo longbook over the main window, asked from the Settings window.
    static let longbookShowDemo = Notification.Name("longbook.showDemo")
    /// A `MacCommand` for the screen on show.
    static let longbookCommand = Notification.Name("longbook.command")
}

extension View {
    /// Runs `action` for the named command while this screen is on show.
    func onMacCommand(_ command: MacCommand, perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .longbookCommand)) { note in
            if note.object as? MacCommand == command { action() }
        }
    }
}

struct LongbookCommands: Commands {
    @ObservedObject private var menu = MenuState.shared
    /// The same stored switch Help & about shows, so the menu and the screen agree.
    @AppStorage(Telemetry.shareUsageKey) private var shareUsage = true

    private func go(_ path: [Destination]) {
        NotificationCenter.default.post(name: .longbookGo, object: path)
    }

    private func on(_ screens: String...) -> Bool {
        menu.shellReady && screens.contains(menu.screenName ?? "dashboard")
    }

    private var onCommitments: Bool { on("commitments", "commitment") }

    var body: some Commands {
        // Beside About, where a Mac app keeps it. It opens the App Store or TestFlight page,
        // asking first; the store does the updating.
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Measure.used("check_for_updates", .menuItem); AppUpdates.askFromMenu() }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Commitment") {
                Measure.used("new_commitment", .menuItem)
                NotificationCenter.default.post(name: .longbookAdd, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!menu.shellReady)
            // The Accounts and People screens' own Add, named for the screen on show.
            Button(menu.screenName == "members" ? "New Person" : "New Account") {
                Measure.used("new_entity", .menuItem)
                menu.send(.newEntity)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!on("accounts", "members"))
        }
        // Settings… (⌘,) is the Settings scene's own item; nothing replaces it.
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Statement…") {
                Measure.used("import_statement", .menuItem)
                NotificationCenter.default.post(name: .longbookImport, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!menu.shellReady)
        }
        // View › Show/Hide Sidebar (⌃⌘S), the system's command for the system's sidebar,
        // then the Commitments inspector and the Proposals screen's tools.
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            Button(menu.inspectorShown ? "Hide Inspector" : "Show Inspector") {
                Measure.used("toggle_inspector", .menuItem)
                menu.send(.toggleInspector)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!onCommitments)
            Divider()
            Button("Refresh Proposals") { Measure.used("refresh_proposals", .menuItem); menu.send(.refresh) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!on("changes"))
            Button("History…") { Measure.used("proposals_history", .menuItem); menu.send(.history) }
                .disabled(!on("changes"))
            Button("How Proposals Work") { Measure.used("how_proposals_work", .menuItem); menu.send(.howItWorks) }
                .disabled(!on("changes"))
        }
        // The chosen commitments' actions, as the Commitments toolbar offers them.
        CommandMenu("Commitment") {
            Button(menu.chosenAllPaid ? "Mark Unpaid" : "Mark Paid") { Measure.used("mark_paid", .menuItem); menu.send(.markPaid) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!onCommitments || !menu.chosenCharges)
            Button(menu.chosenAllBookmarked ? "Remove Bookmark" : "Bookmark") { Measure.used("bookmark", .menuItem); menu.send(.bookmark) }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!onCommitments || menu.chosenRows == 0)
            Button("Edit…") { Measure.used("edit_commitment", .menuItem); menu.send(.edit) }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!onCommitments || menu.chosenRows != 1)
        }
        // Without this group macOS answers "Help is not available for longbook": the app has no
        // Help Book. The usage switch sits here too, so it can be found without opening Settings.
        CommandGroup(replacing: .help) {
            Button("longbook Help") {
                Measure.used("longbook_help", .menuItem)
                NotificationCenter.default.post(name: .longbookPush, object: Destination.helpAbout)
            }
            .keyboardShortcut("?", modifiers: .command)
            .disabled(!menu.shellReady)
            Button("Ask Support…") {
                Measure.used("ask_support", .menuItem)
                NotificationCenter.default.post(name: .longbookSupport, object: nil)
            }
            .disabled(!menu.shellReady)
            // Not settings, so not in the Settings window: what longbook can do, and setup again.
            Button("Tips") {
                Measure.used("tips", .menuItem)
                NotificationCenter.default.post(name: .longbookPush, object: Destination.tips)
            }
            .disabled(!menu.shellReady)
            Button("Optimize Your Data…") {
                Measure.used("optimize_your_data", .menuItem)
                NotificationCenter.default.post(name: .longbookSetUpAgain, object: nil)
            }
            .disabled(!menu.shellReady)
            Divider()
            Toggle("Share Usage and Crash Data", isOn: Binding(
                get: { shareUsage },
                set: { on in
                    shareUsage = on
                    Telemetry.shared.setEnabled(on)
                }
            ).measured("share_usage_and_crash_data"))
        }
        CommandMenu("Go") {
            Button("Dashboard") { Measure.used("dashboard", .menuItem); go([]) }.keyboardShortcut("1", modifiers: .command).disabled(!menu.shellReady)
            Button("Reports") { Measure.used("reports", .menuItem); go([.reports]) }.keyboardShortcut("2", modifiers: .command).disabled(!menu.shellReady)
            Button("Calendar") { Measure.used("calendar", .menuItem); go([.calendar]) }.keyboardShortcut("3", modifiers: .command).disabled(!menu.shellReady)
            Button("Commitments") { Measure.used("commitments", .menuItem); go([.commitments(ListFilter())]) }
                .keyboardShortcut("4", modifiers: .command).disabled(!menu.shellReady)
            Button("Insights") { Measure.used("insights", .menuItem); go([.insights]) }.keyboardShortcut("5", modifiers: .command).disabled(!menu.shellReady)
            Button("Proposals") { Measure.used("changes", .menuItem); go([.changes]) }.keyboardShortcut("6", modifiers: .command).disabled(!menu.shellReady)
            Button("Trips") { Measure.used("trips", .menuItem); go([.trips]) }.keyboardShortcut("7", modifiers: .command).disabled(!menu.shellReady)
            Button("Bookmarks") { Measure.used("bookmarks", .menuItem); go([.commitments(ListFilter(bookmarked: true))]) }
                .keyboardShortcut("8", modifiers: .command).disabled(!menu.shellReady)
            Divider()
            Button("Back") {
                Measure.used("back", .menuItem)
                NotificationCenter.default.post(name: .longbookBack, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!menu.shellReady)
            Divider()
            // The Calendar's toolbar, as Calendar's own Go menu has them.
            Button("Today") { Measure.used("today", .menuItem); menu.send(.today) }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!on("calendar"))
            Button("Previous Month") { Measure.used("previous_month", .menuItem); menu.send(.previousMonth) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!on("calendar"))
            Button("Next Month") { Measure.used("next_month", .menuItem); menu.send(.nextMonth) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!on("calendar"))
        }
    }
}
#endif
