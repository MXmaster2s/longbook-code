#if os(macOS)
import AppKit
import DesignSystem
import LongbookCore
import ServiceManagement
import StoreKit
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
        case .privacy: "Data & Privacy"
        case .tutorials: "Tutorials"
        }
    }

    /// The name a subpage's back button carries.
    var backTitle: String { self == .account ? "Account" : title }

    var line: String {
        switch self {
        case .account: "longbook Account"
        case .general: "Version, currency and how longbook opens."
        case .appearance: "Light, dark, or as the Mac is set."
        case .ai: "Let your AI read your longbook and propose changes."
        case .statements: "How longbook reads your statements."
        case .privacy: "Where your longbook lives and what leaves this Mac."
        case .tutorials: "Replay a screen’s tutorial on this Mac."
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
        case .general: ["About", "Software Update", "Check for updates", "What’s New", "Home currency", "Login Items", "Open at login",
                        "Menu Bar", "Dock", "Help", "Support", "Feedback", "Tips", "Demo", "Suggest a feature", "Report a problem", "Contact",
                        "Terms", "Privacy policy", "Source code", "Version"]
        case .appearance: ["Automatic", "Light", "Dark", "Theme"]
        case .ai: ["Claude", "ChatGPT", "MCP", "Access", "Keys", "Proposals", "Reorganise", "Prompts", "Shortcuts", "Siri", "Spotlight"]
        case .statements: ["Add accounts and people found", "Optimize your data", "Import a statement", "PDF", "CSV", "Bank", "Card"]
        case .privacy: ["iCloud", "Folder", "Finder", "Backups", "Move", "Usage", "Crash", "What longbook keeps", "What leaves this device",
                        "Card details", "Open Another Folder", "Delete longbook"]
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
    case plan, backups, keeps
    case aiClaudeDesktop, aiAccess, aiPrompts, aiShortcuts
    case screen(Destination)

    var title: String {
        switch self {
        case .about: "About"
        case .softwareUpdate: "Software Update"
        case .loginItems: "Login Items and Menu Bar"
        case .help: "Help and Feedback"
        case .plan: "Plan and longbook Cloud"
        case .backups: "Backups"
        case .keeps: "What longbook keeps"
        case .aiClaudeDesktop: "Claude Desktop"
        case .aiAccess: "Access Keys"
        case .aiPrompts: "Prompts for Your AI"
        case .aiShortcuts: "Shortcuts and Siri"
        case .screen(.updates): "What’s New"
        case .screen(.tips): "Tips"
        case .screen: ""
        }
    }
}

/// The Settings window's one spacing scale, in points.
enum SettingsMetrics {
    static let inset: CGFloat = 24
    static let rowHeight: CGFloat = 40
    static let rowPadding: CGFloat = 12
    static let tile: CGFloat = 22
    static let gap: CGFloat = 10
    static let section: CGFloat = 20
    static let heading: CGFloat = 6
    static let radius: CGFloat = 10
    /// Where a divider starts in a row with a tile: the label's leading edge.
    static let labelEdge: CGFloat = rowPadding + tile + gap
    static let sidebarPadding: CGFloat = 12
    static let sidebarRow: CGFloat = 32
    static let sidebarWidth: CGFloat = 220
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
            SettingsSidebar(auth: auth, picked: $picked, query: $query)
                .navigationSplitViewColumnWidth(SettingsMetrics.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            pane(picked)
                .id(picked)
                .environment(\.lbPageTitleHidden, true)
        }
        .settingsTitleRemoved()
        .environmentObject(entitlement)
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .account:
            stack(pane) { nav in AccountSettingsPane(auth: auth, entitlement: entitlement, open: nav.open) }
        case .general:
            stack(pane) { nav in GeneralSettingsPane(model: model, open: nav.open) }
        case .appearance:
            stack(pane) { _ in AppearanceSettingsPane() }
        case .ai:
            stack(pane) { nav in AISettingsPane(model: model, auth: auth, open: nav.open) }
        case .statements:
            stack(pane) { _ in StatementsSettingsPane(toMainWindow: toMainWindow) }
        case .privacy:
            stack(pane, header: header(.privacy)) { nav in DataPrivacyView(model: model, openPage: nav.open) }
        case .tutorials:
            stack(pane) { _ in TutorialsSettingsPane() }
        }
    }

    private func stack<Root: View>(
        _ pane: SettingsPane, header: AnyView? = nil, @ViewBuilder root: @escaping (SettingsNavigator) -> Root
    ) -> some View {
        SettingsStack(
            model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow,
            back: pane.backTitle, header: header, root: root
        )
    }

    /// The header card a shared screen draws in place of its title.
    private func header(_ pane: SettingsPane) -> AnyView {
        AnyView(SettingsPaneHeader(pane: pane))
    }
}

/// What a pane's root uses to open a page, and the app screens' share of the stack.
struct SettingsNavigator {
    let open: (SettingsPage) -> Void
    let screens: Binding<[Destination]>
}

/// One pane's own stack, titled as System Settings is: the pane's root leaves the title bar empty
/// and is named by its header card; a pushed page puts "‹ Pane" and its name in the title bar.
/// ⌘[ and ⌘] go back and forward.
struct SettingsStack<Root: View>: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    let toMainWindow: (Notification.Name) -> Void
    /// The pane's name, on every subpage's back button.
    let back: String
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
                        .navigationTitle("")
                        .navigationBarBackButtonHidden(true)
                        .environment(\.lbPageHeader, nil)
                        // Where the title bar names the page, the page draws no second title.
                        .environment(\.lbPageTitleHidden, !page.title.isEmpty)
                        .toolbar { SettingsBackItem(back: back, title: page.title, action: goBack) }
                }
        }
        // Forward has no button, as in System Settings; its shortcut lives here, out of sight.
        .background {
            Button {
                Measure.used("settings_forward")
                guard let next = ahead.popLast() else { return }
                path.append(next)
            } label: {
                EmptyView()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(ahead.isEmpty)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private func goBack() {
        guard let last = path.popLast() else { return }
        ahead.append(last)
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
        case .plan:
            AccountScreenView(auth: auth, entitlement: entitlement, planOnly: true)
        case .backups:
            BackupsSettingsPage(model: model)
        case .keeps:
            PrivacyKeepsPage(model: model)
        case .aiClaudeDesktop:
            MCPServerView(model: model, auth: auth, part: .claudeDesktop)
        case .aiAccess:
            MCPServerView(model: model, auth: auth, part: .access)
        case .aiPrompts:
            AutomationsView(model: model, auth: auth, part: .prompts)
        case .aiShortcuts:
            AutomationsView(model: model, auth: auth, part: .shortcuts)
        case .screen(let destination):
            DestinationScreen(
                destination: destination, model: model, auth: auth, entitlement: entitlement, path: screens,
                importStatement: { toMainWindow(.longbookImport) },
                setUpAgain: { toMainWindow(.longbookSetUpAgain) }
            )
        }
    }
}

/// A subpage's title bar: "‹ Pane" in the brand's ink, then the page's own name.
private struct SettingsBackItem: ToolbarContent {
    let back: String
    let title: String
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { label }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { label }
        }
    }

    private var label: some View {
        HStack(spacing: 16) {
            Button {
                Measure.used("settings_back")
                action()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(back)
                        .lbText(.body)
                }
                .foregroundStyle(LBColor.brandText.color)
                .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .help("Back to \(back)")
            .accessibilityLabel("Back to \(back)")
            .keyboardShortcut("[", modifiers: .command)
            if !title.isEmpty {
                Text(title)
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.leading, SettingsMetrics.inset - 8)
    }
}

private extension View {
    /// The title bar holds no window title: a pane's root leaves it empty, a subpage names itself.
    @ViewBuilder
    func settingsTitleRemoved() -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

// MARK: sidebar

/// The sidebar: the search field, the account row, then the panes in their groups.
private struct SettingsSidebar: View {
    @ObservedObject var auth: AuthViewModel
    @Binding var picked: SettingsPane
    @Binding var query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sidebarPadding) {
                SettingsSearchField(query: $query)
                if SettingsPane.account.matches(query) || (auth.email ?? "").localizedCaseInsensitiveContains(query) {
                    SettingsSidebarButton(pane: .account, picked: $picked) { on in
                        SettingsAccountRow(auth: auth, picked: on)
                    }
                }
                ForEach(Array(shownGroups.enumerated()), id: \.offset) { _, group in
                    VStack(spacing: 0) {
                        ForEach(group) { pane in
                            SettingsSidebarButton(pane: pane, picked: $picked) { on in
                                SettingsSidebarRow(pane: pane, picked: on)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SettingsMetrics.sidebarPadding)
            .padding(.bottom, SettingsMetrics.sidebarPadding)
        }
        .scrollIndicators(.never)
    }

    /// The groups with only the panes the search finds; a group left empty is dropped.
    private var shownGroups: [[SettingsPane]] {
        SettingsPane.groups.map { $0.filter { $0.matches(query) } }.filter { !$0.isEmpty }
    }
}

/// The sidebar's search field, 28 pt tall.
private struct SettingsSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LBColor.textTertiary.color)
                .accessibilityHidden(true)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .lbText(.body)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A sidebar row as a button that picks its pane, drawn filled in the brand's colour when picked.
private struct SettingsSidebarButton<Label: View>: View {
    let pane: SettingsPane
    @Binding var picked: SettingsPane
    @ViewBuilder let label: (Bool) -> Label

    var body: some View {
        let on = picked == pane
        Button {
            guard pane != picked else { return }
            Measure.used("settings_pane")
            picked = pane
        } label: {
            label(on)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(LBColor.brand.color)
                    }
                }
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The account row at the sidebar's top: the sign-in photo, the address, and what it is. 44 pt tall.
private struct SettingsAccountRow: View {
    @ObservedObject var auth: AuthViewModel
    let picked: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.gap) {
            AccountAvatar(url: auth.avatarURL, email: auth.email, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(auth.email ?? "Account")
                    .lbText(.body)
                    .foregroundStyle(picked ? Color.white : LBColor.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("longbook Account")
                    .lbText(.footnote)
                    .foregroundStyle(picked ? Color.white.opacity(0.8) : LBColor.textSecondary.color)
            }
        }
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }
}

/// One sidebar row, 32 pt: the pane's symbol on its coloured tile, then its name.
private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let picked: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.gap) {
            SettingsTile(pane: pane, size: SettingsMetrics.tile)
            Text(pane.title)
                .lbText(.body)
                .foregroundStyle(picked ? Color.white : LBColor.textPrimary.color)
                .lineLimit(1)
        }
        .frame(height: SettingsMetrics.sidebarRow)
    }
}

// MARK: form parts

/// A white symbol on a rounded tile of colour, the mark of every pane and row.
struct SettingsTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = SettingsMetrics.tile

    init(symbol: String, color: Color, size: CGFloat = SettingsMetrics.tile) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    init(pane: SettingsPane, size: CGFloat = SettingsMetrics.tile) {
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

/// A pane's first card: a 44 pt mark, its name, one short line, and an optional control at the end.
struct SettingsHeaderCard<Icon: View, Accessory: View>: View {
    let title: String
    let line: String
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lbText(.title)
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(line)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .lineLimit(1)
            }
            Spacer(minLength: SettingsMetrics.gap)
            accessory()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: SettingsMetrics.radius, style: .continuous))
    }
}

extension SettingsHeaderCard where Accessory == EmptyView {
    init(title: String, line: String, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title: title, line: line, icon: icon, accessory: { EmptyView() })
    }
}

/// A pane's header card from the pane itself: its tile, name and line.
struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        SettingsHeaderCard(title: pane.title, line: pane.line) { SettingsTile(pane: pane, size: 44) }
    }
}

/// A pane or subpage's scrolling canvas: inset 24 pt from both edges, sections 20 pt apart.
struct SettingsCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.section) {
                content()
            }
            .padding(.horizontal, SettingsMetrics.inset)
            .padding(.bottom, SettingsMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .toggleStyle(.switch)
        .tint(LBColor.brand.color)
    }
}

/// A card of rows, radius 10, with an optional heading 6 pt above it.
struct SettingsGroup<Content: View>: View {
    var heading: String?
    @ViewBuilder let content: () -> Content

    init(heading: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.heading = heading
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.heading) {
            if let heading {
                Text(heading)
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity)
                .background(LBColor.card.color, in: RoundedRectangle(cornerRadius: SettingsMetrics.radius, style: .continuous))
        }
    }
}

/// The rule between two rows, starting at the label: 46 pt in a row with a tile, 12 pt without.
struct SettingsDivider: View {
    var tiled = true

    var body: some View {
        Rectangle()
            .fill(LBColor.hairline.color)
            .frame(height: 1)
            .padding(.leading, tiled ? SettingsMetrics.labelEdge : SettingsMetrics.rowPadding)
    }
}

/// A row's detail, behind an ⓘ that opens it in a popover.
struct SettingsInfoButton: View {
    let text: String
    let control: StaticString
    @State private var shown = false

    init(_ text: String, control: StaticString) {
        self.text = text
        self.control = control
    }

    var body: some View {
        Button {
            Measure.used(control)
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(LBColor.textTertiary.color)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .help(text)
        .accessibilityLabel("More about this setting")
        .measured("settings_info", .popover, when: shown)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .lbText(.bodySM)
                .foregroundStyle(LBColor.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 280, alignment: .leading)
        }
    }
}

/// One row, 40 pt: a 22 pt tile, the label, then the row's own control at the trailing edge.
struct SettingsRow<Label: View, Trailing: View>: View {
    var symbol: String?
    var tile: Color = Color(white: 0.55)
    @ViewBuilder let label: () -> Label
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: SettingsMetrics.gap) {
            if let symbol {
                SettingsTile(symbol: symbol, color: tile)
            }
            label()
            Spacer(minLength: SettingsMetrics.gap)
            trailing()
        }
        .padding(.horizontal, SettingsMetrics.rowPadding)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

/// A row's label in the body style.
struct SettingsRowTitle: View {
    let title: String
    var tone: Color?

    var body: some View {
        Text(title)
            .lbText(.body)
            .foregroundStyle(tone ?? LBColor.textPrimary.color)
    }
}

extension SettingsRow where Label == SettingsRowTitle {
    init(_ title: String, symbol: String? = nil, tile: Color = Color(white: 0.55), tone: Color? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol
        self.tile = tile
        self.label = { SettingsRowTitle(title: title, tone: tone) }
        self.trailing = trailing
    }
}

extension SettingsRow where Label == SettingsRowTitle, Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil, tile: Color = Color(white: 0.55), tone: Color? = nil) {
        self.init(title, symbol: symbol, tile: tile, tone: tone) { EmptyView() }
    }
}

/// A row that opens a page, or a window elsewhere: its label, an optional value, then a chevron.
struct SettingsLinkRow: View {
    let title: String
    var symbol: String?
    var tile: Color = Color(white: 0.55)
    var value: String?
    var tone: Color?
    var chevron = true
    let control: StaticString
    let action: () -> Void

    var body: some View {
        Button {
            Measure.used(control)
            action()
        } label: {
            SettingsRow(title, symbol: symbol, tile: tile, tone: tone) {
                if let value {
                    Text(value)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                        .lineLimit(1)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LBColor.textTertiary.color)
                }
            }
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
    }
}

/// A line under a group for what went wrong; nothing else sits under a card.
struct SettingsProblem: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .lbText(.footnote)
            .foregroundStyle(LBColor.urgent.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -SettingsMetrics.section + SettingsMetrics.heading)
    }
}

/// The two-line row a subpage uses for a sentence: the text wraps inside the row's padding.
struct SettingsTextRow: View {
    let text: String

    var body: some View {
        Text(text)
            .lbText(.body)
            .foregroundStyle(LBColor.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowHeight, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.rowPadding)
            .padding(.vertical, 8)
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
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct GeneralSettingsPane: View {
    let model: DashboardModel
    let open: (SettingsPage) -> Void
    @State private var saved: String?

    var body: some View {
        SettingsCanvas {
            SettingsPaneHeader(pane: .general)
            SettingsGroup {
                SettingsLinkRow(title: "About", symbol: "info", value: AppVersion.marketing, control: "general_about") {
                    open(.about)
                }
                SettingsDivider()
                SettingsLinkRow(title: "Software Update", symbol: "gear", control: "general_software_update") {
                    open(.softwareUpdate)
                }
            }
            SettingsGroup {
                SettingsRow("Home currency", symbol: "banknote", tile: .green) {
                    currency
                    SettingsInfoButton(currencyNote, control: "home_currency_info")
                }
            }
            if let saveError = model.saveError {
                SettingsProblem(saveError)
            }
            SettingsGroup {
                SettingsLinkRow(title: "Login Items and Menu Bar", symbol: "menubar.rectangle", tile: .blue, control: "general_login_items") {
                    open(.loginItems)
                }
                SettingsDivider()
                SettingsLinkRow(title: "Help and Feedback", symbol: "questionmark", tile: .orange, control: "general_help_and_feedback") {
                    open(.help)
                }
            }
        }
        .onAppear {
            model.clearSaveError()
            saved = model.homeCurrency
        }
    }

    private var currencyNote: String {
        choices.count > 1
            ? "Totals in other currencies are shown separately, never converted."
            : "Everything in your folder is in \(choices.first ?? "one currency"). A second currency adds a choice here."
    }

    /// The code alone in the row; the menu names each currency in full.
    @ViewBuilder
    private var currency: some View {
        if choices.count > 1 {
            Menu {
                Picker("Home currency", selection: currencyChoice) {
                    ForEach(choices, id: \.self) { code in
                        Text(Self.currencyWords(code)).tag(String?.some(code))
                    }
                    Text("Automatic").tag(String?.none)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(current ?? "Automatic")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            // A picker of one option would be dead UI, and picking would change nothing.
            Text(choices.first ?? "Automatic")
                .lbText(.body)
                .foregroundStyle(LBColor.textSecondary.color)
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
        SettingsCanvas {
            SettingsGroup {
                SettingsRow("longbook \(AppVersion.marketing) (\(AppVersion.build))", symbol: "gear") {
                    Button("Check Now") {
                        Measure.used("about_check_for_updates")
                        AppUpdates.askFromMenu()
                    }
                }
                SettingsDivider()
                SettingsRow("Check automatically", symbol: "arrow.clockwise") {
                    Toggle("Check automatically", isOn: $checksUpdates.measured("check_for_updates_automatically"))
                        .labelsHidden()
                }
            }
            SettingsGroup {
                SettingsLinkRow(
                    title: "What’s New in \(AppVersion.marketing)", symbol: "sparkles.rectangle.stack", tile: .orange,
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
        SettingsCanvas {
            SettingsGroup {
                SettingsRow("Open at login", symbol: "laptopcomputer", tile: .blue) {
                    Toggle("Open at login", isOn: launchBinding.measured("launch_at_login"))
                        .labelsHidden()
                }
            }
            if let loginNote {
                SettingsProblem(loginNote)
            }
            SettingsGroup(heading: "Menu Bar and Dock") {
                SettingsRow("Show in the menu bar", symbol: "menubar.rectangle", tile: .orange) {
                    SettingsInfoButton(
                        "On, the menu bar item shows your next payment. Off, it shows the longbook mark. Either way it opens longbook and its Settings.",
                        control: "menu_bar_info"
                    )
                    Toggle("Show in the menu bar", isOn: menuBarBinding.measured("show_next_payment_in_menu_bar"))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("Hide the Dock icon", symbol: "dock.rectangle") {
                    Toggle("Hide the Dock icon", isOn: dockBinding.measured("hide_the_dock_icon"))
                        .labelsHidden()
                }
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
        Binding(get: { showsMenuBar }, set: { if $0 != showsMenuBar { showsMenuBar = $0 } })
    }

    private var dockBinding: Binding<Bool> {
        Binding(
            get: { hidesDock },
            set: { on in
                hidesDock = on
                DockIcon.apply(hidden: on)
            }
        )
    }
}

// MARK: Appearance

struct AppearanceSettingsPane: View {
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue

    var body: some View {
        SettingsCanvas {
            SettingsPaneHeader(pane: .appearance)
            SettingsGroup {
                HStack(spacing: 0) {
                    thumbnail(.system, "Automatic")
                    thumbnail(.light, LBAppearance.light.label)
                    thumbnail(.dark, LBAppearance.dark.label)
                }
                .padding(.vertical, 16)
            }
        }
    }

    /// One choice drawn as a small window in its colours, ringed in the brand's colour when picked.
    private func thumbnail(_ choice: LBAppearance, _ name: String) -> some View {
        let picked = appearance == choice.rawValue
        let light = Color(white: 0.95)
        let dark = Color(white: 0.16)
        return Button {
            Measure.used("appearance")
            appearance = choice.rawValue
        } label: {
            VStack(spacing: 8) {
                Group {
                    switch choice {
                    case .system: HStack(spacing: 0) { light; dark }
                    case .light: light
                    case .dark: dark
                    }
                }
                .frame(width: 88, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(picked ? LBColor.brand.color : Color.primary.opacity(0.12), lineWidth: picked ? 3 : 1)
                )
                Text(name)
                    .lbText(.footnote)
                    .foregroundStyle(picked ? LBColor.textPrimary.color : LBColor.textSecondary.color)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .lbButtonStyle()
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: Account

/// The account pane: the sign-in photo and email once, in the header; then the plan and Cloud,
/// the ways out, and deleting last.
struct AccountSettingsPane: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    let open: (SettingsPage) -> Void
    @ObservedObject private var store = StoreClient.shared
    @State private var deleting = false
    @State private var signingOut = false
    @State private var refund: (id: UInt64, closes: Date)?
    @State private var refunding = false

    var body: some View {
        SettingsCanvas {
            SettingsHeaderCard(title: auth.email ?? SettingsPane.account.title, line: "longbook Account") {
                AccountAvatar(url: auth.avatarURL, email: auth.email, size: 44)
            }
            SettingsGroup {
                SettingsLinkRow(title: "Plan", symbol: "seal.fill", tile: .purple, value: planValue, control: "account_plan") {
                    open(.plan)
                }
                SettingsDivider()
                SettingsLinkRow(title: "longbook Cloud", symbol: "icloud.fill", tile: .blue, value: cloudValue, control: "account_cloud") {
                    open(.plan)
                }
            }
            if auth.isSignedIn {
                SettingsGroup {
                    SettingsLinkRow(title: "Sign Out", symbol: "rectangle.portrait.and.arrow.right", control: "sign_out") {
                        signingOut = true
                    }
                    if refund != nil {
                        SettingsDivider()
                        SettingsLinkRow(title: "Request a Refund", symbol: "dollarsign.arrow.circlepath", tile: .green,
                                        control: "request_a_refund") {
                            refunding = true
                        }
                    }
                }
                SettingsGroup {
                    SettingsLinkRow(title: "Delete Account…", tone: LBColor.danger.color, chevron: false, control: "delete_account") {
                        deleting = true
                    }
                }
            }
        }
        .task { await store.load() }
        .task(id: entitlement.state.hasLicence) { refund = entitlement.state.hasLicence ? await store.refundable() : nil }
        .refundRequestSheet(for: refund?.id ?? 0, isPresented: $refunding) { _ in
            Task { await entitlement.refresh() }
        }
        .measured("account_screen_signing_out", .sheet, when: signingOut)
        .sheet(isPresented: $signingOut) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { Measure.used("done"); signingOut = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(LBSpacing.s3)
                SignOutScreenView(auth: auth)
            }
            .frame(minWidth: 520, minHeight: 520)
            .background(LBColor.canvas.color)
        }
        .measured("account_screen_deleting", .sheet, when: deleting)
        .sheet(isPresented: $deleting) {
            DeleteAccountSheet(auth: auth) { deleting = false }
                .frame(minWidth: 520, minHeight: 640)
        }
    }

    private var planValue: String? { planWords(entitlement.state)?.0 }

    /// "Renews 2 Oct 2027" while a date stands, otherwise Cloud's standing.
    private var cloudValue: String? {
        if let line = cloudDateLine(entitlement.state) { return "\(line.0) \(line.1)" }
        return cloudWords(entitlement.state)?.0
    }
}

// MARK: AI

/// The AI pane: the two switches, the connections, then what to do with them.
struct AISettingsPane: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    let open: (SettingsPage) -> Void
    @State private var reorganising = false

    var body: some View {
        SettingsCanvas {
            SettingsPaneHeader(pane: .ai)
            MCPServerView(model: model, auth: auth, part: .switches, openPage: open)
            SettingsGroup(heading: "Automations") {
                SettingsLinkRow(title: "Prompts for Your AI", symbol: "text.quote", tile: .orange, control: "ai_prompts") {
                    open(.aiPrompts)
                }
                SettingsDivider()
                SettingsLinkRow(title: "Shortcuts and Siri", symbol: "command", control: "ai_shortcuts_and_siri") {
                    open(.aiShortcuts)
                }
                SettingsDivider()
                SettingsRow("Reorganise My longbook", symbol: "wand.and.stars", tile: .purple) {
                    SettingsInfoButton(
                        "longbook’s AI reads your whole longbook and proposes it the way you’d keep it. It lands in Proposals as one proposal.",
                        control: "reorganise_info"
                    )
                    Button("Reorganise…") { Measure.used("reorganise_my_longbook"); reorganising = true }
                }
            }
        }
        .measured("automations_reorganising", .sheet, when: reorganising)
        .sheet(isPresented: $reorganising) {
            ReorganiseView(model: model, auth: auth) { reorganising = false }
        }
    }
}

// MARK: Statements

struct StatementsSettingsPane: View {
    let toMainWindow: (Notification.Name) -> Void
    @AppStorage("longbook.statements.addFound") private var addsFound = true

    var body: some View {
        SettingsCanvas {
            SettingsPaneHeader(pane: .statements)
            SettingsGroup {
                SettingsRow("Add accounts and people found", symbol: "person.2.fill", tile: .teal) {
                    SettingsInfoButton(
                        "On, importing a statement adds its account, the accounts its transfers and card payments go to, and every person it names to Accounts and People. Off, statements still name them for your AI, but Accounts and People list only what you add.",
                        control: "add_accounts_and_people_found_info"
                    )
                    Toggle("Add accounts and people found", isOn: $addsFound.measured("add_accounts_and_people_found"))
                        .labelsHidden()
                }
            }
            SettingsGroup {
                SettingsLinkRow(title: "Optimize Your Data", symbol: "wand.and.stars", tile: .purple, control: "optimize_your_data") {
                    toMainWindow(.longbookSetUpAgain)
                }
                SettingsDivider()
                SettingsRow("Import a Statement", symbol: "doc.fill", tile: .teal) {
                    Button("Import…") {
                        Measure.used("import_statement")
                        toMainWindow(.longbookImport)
                    }
                }
            }
        }
    }
}

// MARK: Data & Privacy

/// Data & Privacy › Backups: how many versions history keeps, and a copy to save.
struct BackupsSettingsPage: View {
    let model: DashboardModel
    @State private var backup: URL?

    var body: some View {
        SettingsCanvas {
            SettingsGroup {
                SettingsRow("History", symbol: "clock.arrow.circlepath") {
                    Text(historyWords)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textSecondary.color)
                }
                SettingsDivider()
                if let backup {
                    SettingsRow("Backup", symbol: "externaldrive.fill", tile: .blue) {
                        ShareLink(item: backup) { Text("Share Backup") }
                    }
                } else {
                    SettingsRow("Backup", symbol: "externaldrive.fill", tile: .blue) {
                        Button("Back Up Now") { Measure.used("back_up_now"); backup = model.exportBackup() }
                    }
                }
            }
        }
    }

    private var historyWords: String {
        let count = model.historyCount()
        return count == 0 ? "Starts with the first change" : "\(count) version\(count == 1 ? "" : "s") kept"
    }
}

/// Data & Privacy › What longbook keeps: the folder's facts, what is never stored, and what leaves this Mac.
struct PrivacyKeepsPage: View {
    let model: DashboardModel
    @State private var bytes = 0

    var body: some View {
        SettingsCanvas {
            SettingsGroup(heading: "Your longbook") {
                SettingsRow("Stored") { value(location) }
                if bytes > 0 {
                    SettingsDivider(tiled: false)
                    SettingsRow("Size") { value(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) }
                }
            }
            SettingsGroup(heading: "Card details") {
                SettingsTextRow(text: "longbook never stores a full card number, CVV, expiry, PIN or password: a save carrying one is refused.")
            }
            SettingsGroup(heading: "What longbook keeps") {
                SettingsTextRow(text: "Your data stays on your devices, except while AI access is on (turning it off deletes that copy), when you share a report, or when you import a statement.")
                SettingsDivider(tiled: false)
                SettingsTextRow(text: "Your account keeps each tag’s kind, name and icon, never a commitment’s name, amount, date or note.")
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.heading) {
                Text("What leaves this device")
                    .lbText(.headline)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .accessibilityAddTraits(.isHeader)
                DataLeavingCard(model: model)
            }
        }
        .onAppear { bytes = model.vaultFolderURL.map { VaultMigration.totalBytes(in: $0) } ?? 0 }
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .lbText(.body)
            .foregroundStyle(LBColor.textSecondary.color)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var location: String {
        if case .loaded(let data) = model.state { return data.vaultLocation.capitalizedFirst }
        return "No folder is open"
    }
}

// MARK: Tutorials

extension ScreenTutorial {
    /// The screen's own symbol, as the main window's sidebar draws it.
    var settingsSymbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .commitments: LBGlyph.commitment
        case .calendar: LBGlyph.date
        case .reports: "chart.bar.fill"
        case .accounts: LBGlyph.account
        case .people: "person.2.fill"
        case .insights: "lightbulb.fill"
        case .changes: LBGlyph.change
        case .settings: "gearshape.fill"
        }
    }

    var settingsTile: Color {
        switch self {
        case .dashboard: .indigo
        case .commitments: .blue
        case .calendar: .red
        case .reports: .green
        case .accounts: .teal
        case .people: .orange
        case .insights: .yellow
        case .changes: .purple
        case .settings: Color(white: 0.55)
        }
    }
}

/// Tutorials: every screen's tutorial, whether this Mac has shown it, and Replay, in two fixed columns.
struct TutorialsSettingsPane: View {
    private var center: TutorialCenter { TutorialCenter.shared }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Read so the Seen words redraw after a tutorial ends or is replayed.
        let _ = center.seenRevision
        let screens = ScreenTutorial.listed
        SettingsCanvas {
            SettingsHeaderCard(title: SettingsPane.tutorials.title, line: SettingsPane.tutorials.line) {
                SettingsTile(pane: .tutorials, size: 44)
            } accessory: {
                Button("Replay All") {
                    Measure.used("replay_all_tutorials")
                    center.replayAll()
                    open(.dashboard)
                }
            }
            SettingsGroup {
                ForEach(Array(screens.enumerated()), id: \.element) { index, screen in
                    row(screen, control: screen.replayControl)
                    if index < screens.count - 1 { SettingsDivider() }
                }
            }
        }
    }

    private func row(_ screen: ScreenTutorial, control: StaticString) -> some View {
        SettingsRow(screen.title, symbol: screen.settingsSymbol, tile: screen.settingsTile) {
            HStack(spacing: 3) {
                if center.isSeen(screen) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    Text("Seen")
                        .lbText(.footnote)
                }
            }
            .foregroundStyle(LBColor.textTertiary.color)
            .frame(width: 52, alignment: .trailing)
            .accessibilityLabel(center.isSeen(screen) ? "Seen" : "Not seen yet")
            Button {
                Measure.used(control)
                center.replay(screen)
                open(screen)
            } label: {
                Text("Replay")
                    .lbText(.body)
                    .foregroundStyle(LBColor.brandText.color)
                    .contentShape(Rectangle())
            }
            .lbButtonStyle()
            .frame(width: 52, alignment: .trailing)
            .accessibilityLabel("Replay the \(screen.title) tutorial")
        }
    }

    /// The main window opens the screen, brought to the front first, where the tutorial starts.
    private func open(_ screen: ScreenTutorial) {
        openWindow(id: LongbookWindow.main)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .longbookOpenTutorial, object: screen)
    }
}

// MARK: About, Help and Feedback

/// General › About: this version, and the terms the app is under.
struct AboutSettingsPage: View {
    var body: some View {
        SettingsCanvas {
            SettingsHeaderCard(title: "longbook", line: "Version \(AppVersion.marketing) (\(AppVersion.build))") {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .accessibilityHidden(true)
            }
            SettingsGroup {
                SettingsLinkOut(title: "Terms of service", words: "Open", url: HelpAboutView.termsURL)
                SettingsDivider(tiled: false)
                SettingsLinkOut(title: "Privacy policy", words: "Open", url: HelpAboutView.privacyURL)
                SettingsDivider(tiled: false)
                SettingsLinkOut(title: "Source code", words: "GPL-3.0", url: HelpAboutView.sourceURL)
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
        SettingsCanvas {
            SettingsGroup {
                SettingsLinkOut(title: "Help", words: "longbook.app/help", url: Self.helpURL)
                SettingsDivider(tiled: false)
                SettingsLinkOut(title: "Questions and guides", words: "longbook.app/faq", url: HelpAboutView.faqURL)
                SettingsDivider(tiled: false)
                SettingsLinkRow(title: "Tips", control: "about_tips") {
                    open(.screen(.tips))
                }
                SettingsDivider(tiled: false)
                SettingsRow("Demo longbook") {
                    Button("Try the Demo…") {
                        Measure.used("about_try_the_demo")
                        toMainWindow(.longbookShowDemo)
                    }
                }
            }
            SettingsGroup {
                SettingsRow("longbook Support") {
                    Button("Ask Support…") {
                        Measure.used("about_ask_support")
                        toMainWindow(.longbookSupport)
                    }
                }
                SettingsDivider(tiled: false)
                SettingsRow("Send feedback") {
                    Button("Write…") {
                        Measure.used("about_send_feedback")
                        toMainWindow(.longbookSupport)
                    }
                }
                SettingsDivider(tiled: false)
                SettingsLinkOut(title: "Suggest a feature", words: "insigh.to", url: HelpAboutView.ideasURL)
                SettingsDivider(tiled: false)
                SettingsRow("Report a problem") {
                    Button("Write…") {
                        Measure.used("about_report_a_problem")
                        if let url = HelpAboutView.problemURL { openURL(url) }
                    }
                }
                SettingsDivider(tiled: false)
                SettingsLinkOut(title: "Contact", words: "contact@longbook.app", url: HelpAboutView.contactURL)
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
        SettingsRow(title) {
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
