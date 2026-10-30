#if os(macOS)
import SwiftUI

/// The menu bar's voice into the running window. Commands live on the App scene and
/// the window owns the state, so the two meet on notifications — one poster, one
/// listener, no shared object.
/// The window's identifier, so the tray and the menu can put a closed one back.
enum LongbookWindow {
    static let main = "longbook.main"
}

/// Whether a window is on screen with the ledger in it. The menu bar asks before
/// offering a command: an item that is present, enabled and silent is worse than one
/// that is dimmed.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var shellReady = false
    private init() {}
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
}

struct LongbookCommands: Commands {
    @ObservedObject private var menu = MenuState.shared
    /// The same stored flag the shell reads, so the menu and the button cannot disagree.
    /// The same stored switch Help & about shows, so the menu and the screen agree.
    @AppStorage(Telemetry.shareUsageKey) private var shareUsage = true

    private func go(_ path: [Destination]) {
        NotificationCenter.default.post(name: .longbookGo, object: path)
    }

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
        }
        // Settings… (⌘,) is the Settings scene's own item; nothing replaces it. The sidebar's
        // Settings menu opens the same window.
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Statement…") {
                Measure.used("import_statement", .menuItem)
                NotificationCenter.default.post(name: .longbookImport, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!menu.shellReady)
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
            Button("Charges") { Measure.used("charges", .menuItem); go([.commitments(ListFilter(scope: .past, kind: .charges))]) }
                .disabled(!menu.shellReady)
            Button("Earnings") { Measure.used("earnings", .menuItem); go([.commitments(ListFilter(scope: .past, kind: .earnings))]) }
                .disabled(!menu.shellReady)
            Button("Transfers") { Measure.used("transfers", .menuItem); go([.commitments(ListFilter(scope: .past, kind: .transfers))]) }
                .disabled(!menu.shellReady)
            Button("Insights") { Measure.used("insights", .menuItem); go([.insights]) }.keyboardShortcut("5", modifiers: .command).disabled(!menu.shellReady)
            Button("Proposals") { Measure.used("changes", .menuItem); go([.changes]) }.keyboardShortcut("6", modifiers: .command).disabled(!menu.shellReady)
            Button("Trips") { Measure.used("trips", .menuItem); go([.trips]) }.keyboardShortcut("7", modifiers: .command).disabled(!menu.shellReady)
            Divider()
            Button("Back") {
                Measure.used("back", .menuItem)
                NotificationCenter.default.post(name: .longbookBack, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!menu.shellReady)
        }
    }
}
#endif
