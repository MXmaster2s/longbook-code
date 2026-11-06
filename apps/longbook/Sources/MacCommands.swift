#if os(macOS)
import AppKit
import DesignSystem
import SwiftUI

/// The menu bar's voice into the running window. Commands live on the App scene and
/// the window owns the state, so the two meet on notifications — one poster, one
/// listener, no shared object.
/// The window's identifier, so the tray and the menu can put a closed one back.
enum LongbookWindow {
    static let main = "longbook.main"
    static let keyboardShortcuts = "longbook.keyboardShortcuts"
    static let support = "longbook.support"
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
    /// Support, asked of the main window from the Help menu or the Settings window: the
    /// window takes the screenshot and asks for consent, then Support opens in its own window.
    static let longbookSupport = Notification.Name("longbook.support")
    /// Support's own window, put up or brought forward by the main window, which can open it.
    static let longbookSupportWindow = Notification.Name("longbook.supportWindow")
    /// The demo longbook over the main window, asked from the Settings window.
    static let longbookShowDemo = Notification.Name("longbook.showDemo")
}

/// Every shortcut the app defines, in the one place that defines it: a menu item or a bar
/// button takes its keys from here, and Help › Keyboard Shortcuts lists these, so the list
/// cannot say what the keys do not do.
enum KeyShortcut: CaseIterable, Identifiable {
    case newCommitment, importStatement
    case search
    case dashboard, reports, calendar, commitments, insights, proposals, trips, back, forward
    case markPaid, bookmark, edit, delete, closePanel
    case selectAll
    case sendToSupport
    case settings, help, keyboardShortcuts, quit

    var id: Self { self }

    var keys: KeyboardShortcut {
        switch self {
        case .newCommitment: KeyboardShortcut("n", modifiers: .command)
        case .importStatement: KeyboardShortcut("i", modifiers: .command)
        case .search: KeyboardShortcut("k", modifiers: .command)
        case .dashboard: KeyboardShortcut("1", modifiers: .command)
        case .reports: KeyboardShortcut("2", modifiers: .command)
        case .calendar: KeyboardShortcut("3", modifiers: .command)
        case .commitments: KeyboardShortcut("4", modifiers: .command)
        case .insights: KeyboardShortcut("5", modifiers: .command)
        case .proposals: KeyboardShortcut("6", modifiers: .command)
        case .trips: KeyboardShortcut("7", modifiers: .command)
        case .back: KeyboardShortcut("[", modifiers: .command)
        case .forward: KeyboardShortcut("]", modifiers: .command)
        case .markPaid: KeyboardShortcut("p", modifiers: [.command, .shift])
        case .bookmark: KeyboardShortcut("d", modifiers: .command)
        case .edit: KeyboardShortcut("e", modifiers: .command)
        case .delete: KeyboardShortcut(.delete, modifiers: .command)
        case .closePanel: .cancelAction
        case .selectAll: KeyboardShortcut("a", modifiers: .command)
        case .sendToSupport: KeyboardShortcut(.return, modifiers: .command)
        case .settings: KeyboardShortcut(",", modifiers: .command)
        case .help: KeyboardShortcut("?", modifiers: .command)
        case .keyboardShortcuts: KeyboardShortcut("/", modifiers: .command)
        case .quit: KeyboardShortcut("q", modifiers: .command)
        }
    }

    /// What the shortcuts window calls it.
    var title: String {
        switch self {
        case .newCommitment: "New Commitment"
        case .importStatement: "Import Statement…"
        case .search: "Search longbook"
        case .dashboard: "Dashboard"
        case .reports: "Reports"
        case .calendar: "Calendar"
        case .commitments: "Commitments"
        case .insights: "Insights"
        case .proposals: "Proposals"
        case .trips: "Trips"
        case .back: "Back"
        case .forward: "Forward, in Settings"
        case .markPaid: "Mark Paid / Mark Unpaid"
        case .bookmark: "Bookmark / Remove Bookmark"
        case .edit: "Edit"
        case .delete: "Delete…"
        case .closePanel: "Close Panel"
        case .selectAll: "Select All"
        case .sendToSupport: "Send"
        case .settings: "Settings…"
        case .help: "longbook Help"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .quit: "Quit longbook"
        }
    }

    /// The shortcuts window's headings, in its order, each with its rows.
    static let groups: [(title: String, shortcuts: [KeyShortcut])] = [
        ("File", [.newCommitment, .importStatement]),
        ("Search", [.search]),
        ("Go", [.dashboard, .reports, .calendar, .commitments, .insights, .proposals, .trips, .back, .forward]),
        ("Commitment", [.markPaid, .bookmark, .edit, .delete, .closePanel]),
        ("Lists", [.selectAll]),
        ("Support", [.sendToSupport]),
        ("longbook", [.settings, .help, .keyboardShortcuts, .quit]),
    ]

    /// Marked in the shortcuts window for the release that brought it.
    var isNew: Bool {
        switch self {
        case .markPaid, .bookmark, .edit, .delete, .closePanel, .selectAll, .keyboardShortcuts, .search: true
        default: false
        }
    }

    /// The keys as a Mac menu writes them: "⇧⌘P", "Esc".
    var symbols: String {
        var out = ""
        if keys.modifiers.contains(.control) { out += "⌃" }
        if keys.modifiers.contains(.option) { out += "⌥" }
        if keys.modifiers.contains(.shift) { out += "⇧" }
        if keys.modifiers.contains(.command) { out += "⌘" }
        switch keys.key {
        case .escape: return out + "Esc"
        case .delete: return out + "⌫"
        case .return: return out + "↩"
        default: return out + String(keys.key.character).uppercased()
        }
    }

    /// Whether a key press is this shortcut, for a key that must leave a text field its own.
    func matches(_ event: NSEvent) -> Bool {
        var wanted: NSEvent.ModifierFlags = []
        if keys.modifiers.contains(.command) { wanted.insert(.command) }
        if keys.modifiers.contains(.shift) { wanted.insert(.shift) }
        if keys.modifiers.contains(.option) { wanted.insert(.option) }
        if keys.modifiers.contains(.control) { wanted.insert(.control) }
        return event.modifierFlags.intersection([.command, .shift, .option, .control]) == wanted
            && event.charactersIgnoringModifiers == String(keys.key.character)
    }
}

extension View {
    func lbShortcut(_ shortcut: KeyShortcut) -> some View {
        keyboardShortcut(shortcut.keys)
    }
}

/// A shortcut heard only while no text field holds the cursor, so ⌘⌫ in a field stays the
/// field's own: delete to the start of the line.
struct ShortcutKey: NSViewRepresentable {
    let shortcut: KeyShortcut
    let action: () -> Void

    init(_ shortcut: KeyShortcut, action: @escaping () -> Void) {
        self.shortcut = shortcut
        self.action = action
    }

    func makeNSView(context: Context) -> Catcher { Catcher() }

    func updateNSView(_ view: Catcher, context: Context) {
        view.shortcut = shortcut
        view.action = action
    }

    static func dismantleNSView(_ view: Catcher, coordinator: ()) { view.stop() }

    final class Catcher: NSView {
        var shortcut: KeyShortcut?
        var action: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, window.attachedSheet == nil,
                      self.shortcut?.matches(event) == true, !(window.firstResponder is NSText) else { return event }
                self.action()
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Help › Keyboard Shortcuts: a small window of every shortcut, read from `KeyShortcut`.
struct KeyboardShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LBSpacing.s3) {
                ForEach(KeyShortcut.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: LBSpacing.s1) {
                        Text(group.title)
                            .lbText(.footnote)
                            .foregroundStyle(LBColor.textSecondary.color)
                            .padding(.leading, LBSpacing.s3)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(group.shortcuts) { row($0) }
                        }
                        .padding(.vertical, LBSpacing.s1)
                        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
                    }
                }
            }
            .padding(LBSpacing.s4)
        }
        .frame(width: 460)
        .frame(minHeight: 400, idealHeight: 720)
        .background(LBColor.canvas.color)
    }

    private func row(_ shortcut: KeyShortcut) -> some View {
        HStack(spacing: LBSpacing.s2) {
            Text(shortcut.title)
                .lbText(.body)
                .foregroundStyle(LBColor.textPrimary.color)
                .frame(width: 208, alignment: .leading)
            if shortcut.isNew { LBBadge("New", tone: .muted) }
            Spacer(minLength: LBSpacing.s3)
            Text(shortcut.symbols)
                .lbText(.body)
                .monospacedDigit()
                .foregroundStyle(LBColor.textSecondary.color)
        }
        .padding(.horizontal, LBSpacing.s3)
        .frame(minHeight: 24)
        .accessibilityElement(children: .combine)
    }
}

struct LongbookCommands: Commands {
    @ObservedObject private var menu = MenuState.shared
    @Environment(\.openWindow) private var openWindow
    /// The same stored flag the shell reads, so the menu and the button cannot disagree.
    /// The same stored switch Help & about shows, so the menu and the screen agree.
    @AppStorage(Telemetry.shareUsageKey) private var shareUsage = false

    private func go(_ path: [Destination]) {
        NotificationCenter.default.post(name: .longbookGo, object: path)
    }

    var body: some Commands {
        // Beside About, where a Mac app keeps it. It opens the App Store page, asking first;
        // the store does the updating, or Sparkle on the direct build.
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Measure.used("check_for_updates", .menuItem); AppUpdates.askFromMenu() }
            Button("What’s New") { Measure.used("whats_new", .menuItem); WhatsNewCenter.shared.open() }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Commitment") {
                Measure.used("new_commitment", .menuItem)
                NotificationCenter.default.post(name: .longbookAdd, object: nil)
            }
            .lbShortcut(.newCommitment)
            .disabled(!menu.shellReady)
        }
        // Settings… (⌘,) is the Settings scene's own item; nothing replaces it.
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Statement…") {
                Measure.used("import_statement", .menuItem)
                NotificationCenter.default.post(name: .longbookImport, object: nil)
            }
            .lbShortcut(.importStatement)
            .disabled(!menu.shellReady)
        }
        // The search at the top of the sidebar, from any screen.
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Search longbook") {
                Measure.used("search_longbook", .menuItem)
                openWindow(id: LongbookWindow.main)
                SearchCenter.shared.askFocus()
            }
            .lbShortcut(.search)
            .disabled(!menu.shellReady)
        }
        // Without this group macOS answers "Help is not available for longbook": the app has no
        // Help Book. The usage switch sits here too, so it can be found without opening Settings.
        CommandGroup(replacing: .help) {
            Button("longbook Help") {
                Measure.used("longbook_help", .menuItem)
                NotificationCenter.default.post(name: .longbookPush, object: Destination.helpAbout)
            }
            .lbShortcut(.help)
            .disabled(!menu.shellReady)
            Button("Keyboard Shortcuts") {
                Measure.used("keyboard_shortcuts", .menuItem)
                openWindow(id: LongbookWindow.keyboardShortcuts)
            }
            .lbShortcut(.keyboardShortcuts)
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
            Button("Dashboard") { Measure.used("dashboard", .menuItem); go([]) }.lbShortcut(.dashboard).disabled(!menu.shellReady)
            Button("Reports") { Measure.used("reports", .menuItem); go([.reports]) }.lbShortcut(.reports).disabled(!menu.shellReady)
            Button("Calendar") { Measure.used("calendar", .menuItem); go([.calendar]) }.lbShortcut(.calendar).disabled(!menu.shellReady)
            Button("Commitments") { Measure.used("commitments", .menuItem); go([.commitments(ListFilter())]) }
                .lbShortcut(.commitments).disabled(!menu.shellReady)
            Button("Charges") { Measure.used("charges", .menuItem); go([.commitments(ListFilter(scope: .past, kind: .charges))]) }
                .disabled(!menu.shellReady)
            Button("Earnings") { Measure.used("earnings", .menuItem); go([.commitments(ListFilter(scope: .past, kind: .earnings))]) }
                .disabled(!menu.shellReady)
            Button("Transfers") { Measure.used("transfers", .menuItem); go([.commitments(ListFilter(scope: .past, kind: .transfers))]) }
                .disabled(!menu.shellReady)
            Button("Insights") { Measure.used("insights", .menuItem); go([.insights]) }.lbShortcut(.insights).disabled(!menu.shellReady)
            Button("Proposals") { Measure.used("changes", .menuItem); go([.changes]) }.lbShortcut(.proposals).disabled(!menu.shellReady)
            Button("Trips") { Measure.used("trips", .menuItem); go([.trips]) }.lbShortcut(.trips).disabled(!menu.shellReady)
            Divider()
            Button("Back") {
                Measure.used("back", .menuItem)
                NotificationCenter.default.post(name: .longbookBack, object: nil)
            }
            .lbShortcut(.back)
            .disabled(!menu.shellReady)
        }
    }
}
#endif
