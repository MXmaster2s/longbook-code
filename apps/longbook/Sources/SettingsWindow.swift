#if os(macOS)
import AppKit
import DesignSystem
import LongbookCore
import ServiceManagement
import SwiftUI

/// The Settings window's panes, each with its name, symbol, tile colour and one line saying what it holds.
enum SettingsPane: String, CaseIterable, Identifiable {
    case account, general, appearance, ai, statements, privacy, tutorials

    var id: String { rawValue }

    /// The sidebar's groups under the account row: the app, what longbook reads and keeps, then help.
    static let groups: [[SettingsPane]] = [
        [.general, .appearance],
        [.ai, .statements, .privacy],
        [.tutorials],
    ]

    var title: String {
        switch self {
        case .account: "longbook Account"
        case .general: "General"
        case .appearance: "Appearance"
        case .ai: "AI"
        case .statements: "Statements"
        case .privacy: "Data & privacy"
        case .tutorials: "Tutorials"
        }
    }

    var line: String {
        switch self {
        case .account: "Your purchase, longbook Cloud, and the ways out."
        case .general: "Your longbook’s version, updates, currency, and how it opens on this Mac."
        case .appearance: "Light, dark, or following the Mac."
        case .ai: "Let Claude or ChatGPT read your longbook and propose changes you review."
        case .statements: "How longbook reads your bank and card statements."
        case .privacy: "Where your longbook lives, its backups, and what leaves this Mac."
        case .tutorials: "Each screen shows a short tutorial the first time you open it on this Mac."
        }
    }

    var symbol: String {
        switch self {
        case .account: "person.crop.circle.fill"
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .ai: "sparkles"
        case .statements: "doc.text.magnifyingglass"
        case .privacy: "hand.raised.fill"
        case .tutorials: "play.circle"
        }
    }

    var tile: Color {
        switch self {
        case .general: Color(white: 0.55)
        case .appearance: Color(white: 0.16)
        case .account, .ai: .purple
        case .statements: .teal
        case .privacy: .blue
        case .tutorials: .orange
        }
    }

    /// The names of the settings a pane holds, so the sidebar's search finds a pane by any of them.
    private var words: [String] {
        switch self {
        case .account: ["Account", "Email", "Plan", "Purchase", "longbook Cloud", "Subscription", "Sign Out", "Refund", "Delete Account"]
        case .general: ["About", "Software Update", "Check for updates", "What’s New", "Home currency", "Login Items", "Launch at login",
                        "Menu Bar", "Dock", "Help", "Feedback", "Tips", "Demo", "Suggest a feature", "Report a problem", "Contact",
                        "Terms", "Privacy policy", "Source code", "Version"]
        case .appearance: ["Automatic", "Light", "Dark", "Theme"]
        case .ai: ["Claude", "ChatGPT", "MCP", "Access", "Keys", "Proposals", "Reorganise", "Prompts", "Shortcuts", "Siri", "Spotlight"]
        case .statements: ["Add accounts and people found", "Optimize your data", "Import a statement", "PDF", "CSV", "Bank", "Card"]
        case .privacy: ["iCloud", "Folder", "Finder", "Backups", "Move", "Usage", "Crash", "What leaves this device", "Card details",
                        "Delete longbook"]
        case .tutorials: ["Replay", "Dashboard", "Commitments", "Calendar", "Reports", "Accounts", "People", "Insights", "Proposals"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + words).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// A page a pane opens: one of the window's own subpages, or one of the app's screens.
enum SettingsPage: Hashable {
    case about, softwareUpdate, loginItems, help
    case screen(Destination)

    var title: String {
        switch self {
        case .about: "About"
        case .softwareUpdate: "Software Update"
        case .loginItems: "Login Items and Menu Bar"
        case .help: "Help and Feedback"
        case .screen(.updates): "What’s New"
        case .screen(.tips): "Tips"
        case .screen: ""
        }
    }
}

/// The Settings window (⌘,), laid out as the Mac's System Settings: a searchable sidebar under the
/// account row, and each pane a header card over grouped cards. The app menu and the main
/// window's sidebar both open it.
struct SettingsWindowView: View {
    @ObservedObject private var auth = AppSession.shared.auth
    @ObservedObject private var entitlement = AppSession.shared.entitlement
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue
    @AppStorage("longbook.settings.pane") private var picked = SettingsPane.general
    @Environment(\.openWindow) private var openWindow

    private var model: DashboardModel { AppSession.shared.model }

    var body: some View {
        SettingsWindowContent(model: model, auth: auth, entitlement: entitlement, picked: $picked, toMainWindow: toMainWindow)
            .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 640)
            .background(CentersSheets())
            .preferredColorScheme((LBAppearance(rawValue: appearance) ?? .dark).colorScheme)
            .overlay(alignment: .bottomTrailing) {
                SupportButton { toMainWindow(.longbookSupport) }
                    .padding(LBSpacing.s6)
            }
            .onAppear { model.loadIfNeeded() }
    }

    private func toMainWindow(_ name: Notification.Name) {
        openWindow(id: LongbookWindow.main)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: name, object: nil)
    }
}

/// The sidebar and the picked pane. The picture harness hosts it with a model of its own.
struct SettingsWindowContent: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    @Binding var picked: SettingsPane
    let toMainWindow: (Notification.Name) -> Void
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                if SettingsPane.account.matches(query) || (auth.email ?? "").localizedCaseInsensitiveContains(query) {
                    Section {
                        SettingsAccountRow(auth: auth).tag(SettingsPane.account)
                    }
                }
                ForEach(Array(shownGroups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { pane in
                            SettingsSidebarRow(pane: pane).tag(pane)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $query, placement: .sidebar, prompt: "Search")
            .tint(LBColor.brand.color)
            .navigationSplitViewColumnWidth(230)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            pane(picked)
                .id(picked)
                .environment(\.lbPageTitleHidden, true)
        }
        .environmentObject(entitlement)
    }

    /// The groups with only the panes the search finds; a group left empty is dropped.
    private var shownGroups: [[SettingsPane]] {
        SettingsPane.groups.map { $0.filter { $0.matches(query) } }.filter { !$0.isEmpty }
    }

    /// The sidebar's pick, counted when the owner changes it.
    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { picked },
            set: { pane in
                guard let pane, pane != picked else { return }
                Measure.used("settings_pane")
                picked = pane
            }
        )
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .account:
            stack(header: accountHeader) { nav in screen(.accountDetails, nav) }
        case .general:
            stack { nav in GeneralSettingsPane(model: model, open: nav.open) }
        case .appearance:
            stack { _ in AppearanceSettingsPane() }
        case .ai:
            stack(header: header(.ai)) { nav in screen(.mcpServer, nav) }
        case .statements:
            stack { _ in StatementsSettingsPane(toMainWindow: toMainWindow) }
        case .privacy:
            stack(header: header(.privacy)) { nav in screen(.privacy, nav) }
        case .tutorials:
            stack(header: header(.tutorials)) { nav in screen(.tutorials, nav) }
        }
    }

    private func stack<Root: View>(header: AnyView? = nil, @ViewBuilder root: @escaping (SettingsNavigator) -> Root) -> some View {
        SettingsStack(model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow, header: header, root: root)
    }

    private func screen(_ destination: Destination, _ nav: SettingsNavigator) -> DestinationScreen {
        DestinationScreen(
            destination: destination, model: model, auth: auth, entitlement: entitlement, path: nav.screens,
            importStatement: { toMainWindow(.longbookImport) },
            setUpAgain: { toMainWindow(.longbookSetUpAgain) }
        )
    }

    /// The header card an app screen draws in place of its title, framed as a card of its own.
    private func header(_ pane: SettingsPane) -> AnyView {
        AnyView(SettingsHeaderCard(title: pane.title, line: pane.line, framed: true) { SettingsTile(pane: pane, size: 56) })
    }

    private var accountHeader: AnyView {
        AnyView(
            SettingsHeaderCard(
                title: auth.email ?? SettingsPane.account.title,
                line: auth.email == nil ? SettingsPane.account.line : "longbook Account · signed in on this Mac",
                framed: true
            ) {
                AccountAvatar(url: auth.avatarURL, email: auth.email, size: 56)
            }
        )
    }
}

/// What a pane's root uses to open a page, and the app screens' share of the stack.
struct SettingsNavigator {
    let open: (SettingsPage) -> Void
    let screens: Binding<[Destination]>
}

/// One pane's own stack, with back and forward in the toolbar as System Settings has them. A
/// pushed page names itself in the toolbar; the pane's root is named by its header card.
struct SettingsStack<Root: View>: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    let toMainWindow: (Notification.Name) -> Void
    let header: AnyView?
    let root: (SettingsNavigator) -> Root
    @State private var path: [SettingsPage] = []
    /// The pages Back left, newest last, for Forward to reopen.
    @State private var ahead: [SettingsPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            root(SettingsNavigator(open: open, screens: screens))
                .environment(\.lbPageHeader, header)
                .navigationTitle("")
                .navigationDestination(for: SettingsPage.self) { page in
                    self.page(page)
                        .navigationTitle(page.title)
                        .navigationBarBackButtonHidden(true)
                        .environment(\.lbPageHeader, nil)
                        .environment(\.lbPageTitleHidden, false)
                }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button {
                        Measure.used("settings_back")
                        guard let last = path.popLast() else { return }
                        ahead.append(last)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(path.isEmpty)
                    .keyboardShortcut("[", modifiers: .command)
                    Button {
                        Measure.used("settings_forward")
                        guard let next = ahead.popLast() else { return }
                        path.append(next)
                    } label: {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(ahead.isEmpty)
                    .keyboardShortcut("]", modifiers: .command)
                }
                .controlGroupStyle(.navigation)
            }
        }
    }

    private func open(_ page: SettingsPage) {
        ahead.removeAll()
        path.append(page)
    }

    /// The app screens on the path, for a screen that pushes one of its own.
    private var screens: Binding<[Destination]> {
        Binding(
            get: { path.compactMap { if case .screen(let destination) = $0 { destination } else { nil } } },
            set: { destinations in
                path = path.filter { if case .screen = $0 { false } else { true } } + destinations.map(SettingsPage.screen)
            }
        )
    }

    @ViewBuilder
    private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .about:
            AboutSettingsPage()
        case .softwareUpdate:
            SoftwareUpdatePage(open: open)
        case .loginItems:
            LoginItemsPage()
        case .help:
            HelpSettingsPage(open: open, toMainWindow: toMainWindow)
        case .screen(let destination):
            DestinationScreen(
                destination: destination, model: model, auth: auth, entitlement: entitlement, path: screens,
                importStatement: { toMainWindow(.longbookImport) },
                setUpAgain: { toMainWindow(.longbookSetUpAgain) }
            )
        }
    }
}

// MARK: sidebar

/// The account row at the sidebar's top: the avatar, the address, and what it is.
private struct SettingsAccountRow: View {
    @ObservedObject var auth: AuthViewModel

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            AccountAvatar(url: auth.avatarURL, email: auth.email, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(auth.email ?? "Account")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("longbook Account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// One sidebar row: the pane's symbol on its coloured tile, then its name.
private struct SettingsSidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            SettingsTile(pane: pane)
        }
    }
}

// MARK: form parts

/// A white symbol on a rounded tile of colour, the mark of every pane and row.
struct SettingsTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    init(symbol: String, color: Color, size: CGFloat = 20) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    init(pane: SettingsPane, size: CGFloat = 20) {
        self.init(symbol: pane.symbol, color: pane.tile, size: size)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// A pane's first card: its big tile, its name, and one line saying what it holds.
struct SettingsHeaderCard<Icon: View>: View {
    let title: String
    let line: String
    /// Drawn on a card of its own where the page has no grouped cards to sit in.
    var framed = false
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: LBSpacing.s2) {
            icon()
            Text(title)
                .lbText(.largeTitle)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text(line)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textSecondary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LBSpacing.s4)
        .padding(.horizontal, framed ? LBSpacing.s4 : 0)
        .background {
            if framed {
                RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous).fill(LBColor.card.color)
            }
        }
    }
}

/// A row's tile, title and an optional note under the title.
private struct SettingsPaneRowLabel: View {
    let title: String
    var note: String?
    let symbol: String
    let tile: Color

    var body: some View {
        HStack(spacing: LBSpacing.s2) {
            SettingsTile(symbol: symbol, color: tile)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A row that opens a page, or a window elsewhere: its label, an optional value, then a chevron.
private struct SettingsLinkRow: View {
    let label: SettingsPaneRowLabel
    var value: String?
    let control: StaticString
    let action: () -> Void

    var body: some View {
        Button {
            Measure.used(control)
            action()
        } label: {
            HStack(spacing: LBSpacing.s2) {
                label
                Spacer(minLength: LBSpacing.s2)
                if let value {
                    Text(value).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A pane of grouped cards on the window's canvas, switches drawn as switches.
private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .scrollContentBackground(.hidden)
            .background(LBColor.canvas.color)
            .tint(LBColor.brand.color)
    }
}

/// The pane's header card as the first card of its form.
private struct SettingsHeaderSection: View {
    let pane: SettingsPane

    var body: some View {
        Section {
            SettingsHeaderCard(title: pane.title, line: pane.line) { SettingsTile(pane: pane, size: 56) }
        }
    }
}

/// The short note under a card.
private struct SettingsNote: View {
    let text: String
    var tone: LBColorValue = LBColor.textTertiary

    init(_ text: String, tone: LBColorValue = LBColor.textTertiary) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: General

/// Whether longbook opens at login, through the system's own login items.
@MainActor
enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Asks the system for the change; the note it returns says what stops it, nil when nothing does.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            return error.localizedDescription
        }
        return SMAppService.mainApp.status == .requiresApproval
            ? "Allow longbook in System Settings › General › Login Items."
            : nil
    }
}

/// The menu bar item and the Dock icon. Hiding the Dock icon keeps the menu bar item on,
/// so longbook is always one click away.
@MainActor
enum DockIcon {
    static let hiddenKey = "longbook.dock.hidden"
    static let menuBarKey = "longbook.menuBar.shown"

    static func apply(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        // A change of policy sends the app behind other apps; its windows come back in front.
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }

    /// At launch: the Dock icon as the owner left it.
    static func applyStored() {
        if UserDefaults.standard.bool(forKey: hiddenKey) {
            UserDefaults.standard.set(true, forKey: menuBarKey)
            NSApp.setActivationPolicy(.accessory)
        }
    }
}


struct GeneralSettingsPane: View {
    let model: DashboardModel
    let open: (SettingsPage) -> Void
    @State private var saved: String?

    var body: some View {
        SettingsForm {
            SettingsHeaderSection(pane: .general)
            Section {
                SettingsLinkRow(label: SettingsPaneRowLabel(title: "About", symbol: "info", tile: Color(white: 0.55)), control: "general_about") {
                    open(.about)
                }
                SettingsLinkRow(
                    label: SettingsPaneRowLabel(title: "Software Update", symbol: "gear", tile: Color(white: 0.55)),
                    control: "general_software_update"
                ) {
                    open(.softwareUpdate)
                }
            }
            Section {
                currency
            } footer: {
                if let saveError = model.saveError {
                    SettingsNote(saveError, tone: LBColor.urgent)
                } else {
                    SettingsNote(choices.count > 1
                        ? "Totals in other currencies are shown separately, never converted."
                        : "Everything in your folder is in \(choices.first ?? "one currency"). A second currency adds a choice here.")
                }
            }
            Section {
                SettingsLinkRow(
                    label: SettingsPaneRowLabel(title: "Login Items and Menu Bar", symbol: "menubar.rectangle", tile: .blue),
                    control: "general_login_items"
                ) {
                    open(.loginItems)
                }
                SettingsLinkRow(
                    label: SettingsPaneRowLabel(title: "Help and Feedback", symbol: "questionmark", tile: .orange),
                    control: "general_help_and_feedback"
                ) {
                    open(.help)
                }
            }
        }
        .onAppear {
            model.clearSaveError()
            saved = model.homeCurrency
        }
    }

    private var currencyLabel: SettingsPaneRowLabel {
        SettingsPaneRowLabel(title: "Home currency", symbol: "banknote", tile: .green)
    }

    @ViewBuilder
    private var currency: some View {
        if choices.count > 1 {
            Picker(selection: currencyChoice) {
                ForEach(choices, id: \.self) { code in
                    Text(Self.currencyWords(code)).tag(String?.some(code))
                }
                Text("Automatic").tag(String?.none)
            } label: {
                currencyLabel
            }
            .pickerStyle(.menu)
        } else {
            // A picker of one option would be dead UI, and picking would change nothing.
            LabeledContent {
                Text(choices.first.map(Self.currencyWords) ?? "Automatic")
            } label: {
                currencyLabel
            }
        }
    }

    /// "INR · Indian Rupee": the code, then the currency's name in the Mac's language.
    private static func currencyWords(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        return "\(code) · \(name)"
    }

    private var current: String? { saved ?? model.homeCurrency }

    /// The chosen code, or nil for the one that follows the data.
    private var currencyChoice: Binding<String?> {
        Binding(
            get: { current },
            set: { code in
                Measure.used("home_currency", .menuItem)
                model.setHomeCurrency(code)
                saved = code
            }
        )
    }

    private var choices: [String] {
        if case .loaded(let data) = model.state { return data.scopeChoices }
        return []
    }
}

/// General › Software Update: this version with Check Now, the daily check, and what's new.
struct SoftwareUpdatePage: View {
    let open: (SettingsPage) -> Void
    @AppStorage(AppUpdates.automaticKey) private var checksUpdates = true

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent {
                    Button("Check Now") {
                        Measure.used("about_check_for_updates")
                        AppUpdates.askFromMenu()
                    }
                } label: {
                    SettingsPaneRowLabel(
                        title: "longbook \(AppVersion.marketing) (\(AppVersion.build))",
                        note: "The App Store or TestFlight installs new versions. longbook only opens its page.",
                        symbol: "gear", tile: Color(white: 0.55)
                    )
                }
                Toggle(isOn: $checksUpdates.measured("check_for_updates_automatically")) {
                    SettingsPaneRowLabel(title: "Check for updates automatically", symbol: "arrow.clockwise", tile: Color(white: 0.55))
                }
            } footer: {
                SettingsNote("Once a day, longbook asks the App Store for a newer version and tells you when one is out.")
            }
            Section {
                SettingsLinkRow(
                    label: SettingsPaneRowLabel(title: "What’s New in \(AppVersion.marketing)", symbol: "sparkles.rectangle.stack", tile: .orange),
                    control: "about_whats_new"
                ) {
                    open(.screen(.updates))
                }
            }
        }
    }
}

/// General › Login Items and Menu Bar: how longbook opens on this Mac, and where it shows.
struct LoginItemsPage: View {
    @AppStorage(DockIcon.menuBarKey) private var showsMenuBar = true
    @AppStorage(DockIcon.hiddenKey) private var hidesDock = false
    @State private var launchesAtLogin = LaunchAtLogin.isOn
    @State private var loginNote: String?

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: launchBinding.measured("launch_at_login")) {
                    SettingsPaneRowLabel(title: "Launch at login", symbol: "power", tile: Color(white: 0.55))
                }
            } footer: {
                if let loginNote {
                    SettingsNote(loginNote, tone: LBColor.urgent)
                } else {
                    SettingsNote("longbook opens when you log in to this Mac.")
                }
            }
            Section {
                Toggle(isOn: menuBarBinding.measured("show_next_payment_in_menu_bar")) {
                    SettingsPaneRowLabel(title: "Show the next payment in the menu bar", symbol: "menubar.rectangle", tile: .blue)
                }
                .disabled(hidesDock)
                Toggle(isOn: dockBinding.measured("hide_the_dock_icon")) {
                    SettingsPaneRowLabel(title: "Hide the Dock icon", symbol: "dock.rectangle", tile: .blue)
                }
            } header: {
                Text("Menu bar and Dock")
            } footer: {
                SettingsNote(hidesDock
                    ? "With the Dock icon hidden, the menu bar item opens longbook and its Settings, so it stays on."
                    : "The menu bar shows your next payment, and opens longbook and its Settings.")
            }
        }
        .onAppear { launchesAtLogin = LaunchAtLogin.isOn }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchesAtLogin },
            set: { on in
                loginNote = LaunchAtLogin.set(on)
                launchesAtLogin = LaunchAtLogin.isOn
            }
        )
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(get: { showsMenuBar || hidesDock }, set: { if $0 != showsMenuBar { showsMenuBar = $0 } })
    }

    private var dockBinding: Binding<Bool> {
        Binding(
            get: { hidesDock },
            set: { on in
                hidesDock = on
                // A hidden Dock icon leaves the menu bar item as the way in, so it shows.
                if on && !showsMenuBar { showsMenuBar = true }
                DockIcon.apply(hidden: on)
            }
        )
    }
}

// MARK: Appearance

struct AppearanceSettingsPane: View {
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue

    var body: some View {
        SettingsForm {
            SettingsHeaderSection(pane: .appearance)
            Section {
                HStack(spacing: LBSpacing.s4) {
                    Spacer(minLength: 0)
                    thumbnail(.system, "Automatic")
                    thumbnail(.light, LBAppearance.light.label)
                    thumbnail(.dark, LBAppearance.dark.label)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, LBSpacing.s2)
            } footer: {
                SettingsNote("longbook follows the Mac’s appearance, or keeps the one you pick.")
            }
        }
    }

    /// One choice drawn as a small window in its colours, ringed in the brand's colour when picked.
    private func thumbnail(_ choice: LBAppearance, _ name: String) -> some View {
        let picked = appearance == choice.rawValue
        let light = Color(white: 0.95)
        let dark = Color(white: 0.12)
        return Button {
            Measure.used("appearance")
            appearance = choice.rawValue
        } label: {
            VStack(spacing: LBSpacing.s1) {
                Group {
                    switch choice {
                    case .system: HStack(spacing: 0) { light; dark }
                    case .light: light
                    case .dark: dark
                    }
                }
                .frame(width: 96, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(picked ? LBColor.brand.color : Color.primary.opacity(0.12), lineWidth: picked ? 3 : 1)
                )
                Text(name)
                    .font(.caption.weight(picked ? .semibold : .regular))
                    .foregroundStyle(picked ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: Statements

struct StatementsSettingsPane: View {
    let toMainWindow: (Notification.Name) -> Void
    @AppStorage("longbook.statements.addFound") private var addsFound = true

    var body: some View {
        SettingsForm {
            SettingsHeaderSection(pane: .statements)
            Section {
                Toggle(isOn: $addsFound.measured("add_accounts_and_people_found")) {
                    SettingsPaneRowLabel(title: "Add accounts and people found in statements", symbol: "person.2.fill", tile: .teal)
                }
            } footer: {
                SettingsNote(addsFound
                    ? "When you import a statement, its account, the accounts its transfers and card payments go to, and every person it names are added to Accounts and People."
                    : "Off: statements still name them for your AI, but Accounts and People list only what you add.")
            }
            Section {
                SettingsLinkRow(
                    label: SettingsPaneRowLabel(title: "Optimize your data", symbol: "wand.and.stars", tile: .purple),
                    control: "optimize_your_data"
                ) {
                    toMainWindow(.longbookSetUpAgain)
                }
            } footer: {
                SettingsNote("Your answers are kept as hints for reading your statements. They aren’t added to People or Accounts.")
            }
            Section {
                LabeledContent {
                    Button("Import…") {
                        Measure.used("import_statement")
                        toMainWindow(.longbookImport)
                    }
                } label: {
                    SettingsPaneRowLabel(title: "Import a statement", symbol: "doc.fill", tile: .teal)
                }
            } footer: {
                SettingsNote("A PDF, CSV, text or Excel file from your bank or card. You check what it read before anything is added.")
            }
        }
    }
}

// MARK: About, Help and Feedback

/// General › About: this version, and the terms the app is under.
struct AboutSettingsPage: View {
    var body: some View {
        SettingsForm {
            Section {
                SettingsHeaderCard(title: "longbook", line: "Version \(AppVersion.marketing) (\(AppVersion.build))") {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                }
            }
            Section {
                SettingsLinkOut(title: "Terms of service", words: "Open", url: HelpAboutView.termsURL)
                SettingsLinkOut(title: "Privacy policy", words: "Open", url: HelpAboutView.privacyURL)
                SettingsLinkOut(title: "Source code", words: "GPL-3.0", url: HelpAboutView.sourceURL)
            } footer: {
                SettingsNote("longbook never sells your data, and never uses your financial data for analytics or advertising.")
            }
        }
    }
}

/// General › Help and Feedback: the help pages, the demo, and the ways to write to us.
struct HelpSettingsPage: View {
    let open: (SettingsPage) -> Void
    let toMainWindow: (Notification.Name) -> Void
    @Environment(\.openURL) private var openURL

    private static let helpURL = URL(string: "https://longbook.app/help/")

    var body: some View {
        SettingsForm {
            Section {
                SettingsLinkOut(title: "Help", words: "longbook.app/help", url: Self.helpURL)
                SettingsLinkOut(title: "Questions and guides", words: "longbook.app/faq", url: HelpAboutView.faqURL)
                SettingsLinkRow(label: SettingsPaneRowLabel(title: "Tips", symbol: "lightbulb", tile: .orange), control: "about_tips") {
                    open(.screen(.tips))
                }
                LabeledContent("Demo longbook") {
                    Button("Try the Demo…") {
                        Measure.used("about_try_the_demo")
                        toMainWindow(.longbookShowDemo)
                    }
                }
            }
            Section {
                LabeledContent("Send feedback") {
                    Button("Write…") {
                        Measure.used("about_send_feedback")
                        toMainWindow(.longbookSupport)
                    }
                }
                SettingsLinkOut(title: "Suggest a feature", words: "insigh.to", url: HelpAboutView.ideasURL)
                LabeledContent("Report a problem") {
                    Button("Write…") {
                        Measure.used("about_report_a_problem")
                        if let url = HelpAboutView.problemURL { openURL(url) }
                    }
                }
                SettingsLinkOut(title: "Contact", words: "contact@longbook.app", url: HelpAboutView.contactURL)
            } footer: {
                SettingsNote("Support answers from the help articles, or passes your message to a person.")
            }
        }
    }
}

/// A row whose value is a link out of the app, in the brand's ink.
private struct SettingsLinkOut: View {
    let title: String
    let words: String
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        LabeledContent(title) {
            Button(words) {
                Measure.used("about_link")
                if let url { openURL(url) }
            }
            .buttonStyle(.link)
            .foregroundStyle(LBColor.brandText.color)
        }
    }
}
#endif
