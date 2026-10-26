#if os(macOS)
import AppKit
import DesignSystem
import LongbookCore
import ServiceManagement
import SwiftUI

/// The Settings window's panes, in sidebar order, each with its name, symbol and tile colour.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, account, ai, statements, privacy, tutorials, about

    var id: String { rawValue }

    /// The sidebar's three groups: the app, what longbook reads and keeps, then help.
    static let groups: [[SettingsPane]] = [
        [.general, .appearance, .account],
        [.ai, .statements, .privacy],
        [.tutorials, .about],
    ]

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .account: "Account"
        case .ai: "AI"
        case .statements: "Statements"
        case .privacy: "Data & privacy"
        case .tutorials: "Tutorials"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .account: "person.crop.circle.fill"
        case .ai: "sparkles"
        case .statements: "doc.text.magnifyingglass"
        case .privacy: "lock.fill"
        case .tutorials: "hand.point.up.left.fill"
        case .about: "info.circle.fill"
        }
    }

    var tile: Color {
        switch self {
        case .general, .about: Color(white: 0.55)
        case .appearance: Color(white: 0.22)
        case .account: .blue
        case .ai: .purple
        case .statements: .teal
        case .privacy: .green
        case .tutorials: .orange
        }
    }
}

/// The Settings window (⌘,), as Mac apps lay theirs out: panes in a sidebar of coloured tiles,
/// the picked pane's name as the window's title. The app menu and the main window's sidebar
/// both open it.
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

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(Array(SettingsPane.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { pane in
                            SettingsSidebarRow(pane: pane).tag(pane)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(LBColor.brand.color)
            .navigationSplitViewColumnWidth(210)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            pane(picked)
                .id(picked)
                .navigationTitle(picked.title)
                .environment(\.lbPageTitleHidden, true)
        }
        .environmentObject(entitlement)
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
        case .general:
            GeneralSettingsPane(model: model)
        case .appearance:
            AppearanceSettingsPane()
        case .account:
            SettingsTab(root: .accountDetails, model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow)
        case .ai:
            SettingsTab(root: .mcpServer, model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow)
        case .statements:
            StatementsSettingsPane(toMainWindow: toMainWindow)
        case .privacy:
            SettingsTab(root: .privacy, model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow)
        case .tutorials:
            SettingsTab(root: .tutorials, model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow)
        case .about:
            SettingsTab(model: model, auth: auth, entitlement: entitlement, toMainWindow: toMainWindow) { path in
                AboutSettingsPane(path: path, toMainWindow: toMainWindow)
            }
        }
    }
}

/// One sidebar row: the pane's symbol on its coloured tile, then its name.
private struct SettingsSidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(pane.tile.gradient)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

// MARK: form parts

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
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct GeneralSettingsPane: View {
    let model: DashboardModel
    @AppStorage(AppUpdates.automaticKey) private var checksUpdates = true
    @AppStorage(DockIcon.menuBarKey) private var showsMenuBar = true
    @AppStorage(DockIcon.hiddenKey) private var hidesDock = false
    @State private var launchesAtLogin = LaunchAtLogin.isOn
    @State private var loginNote: String?
    @State private var saved: String?

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Launch at login", isOn: launchBinding.measured("launch_at_login"))
                Toggle("Check for updates automatically", isOn: $checksUpdates.measured("check_for_updates_automatically"))
            } footer: {
                if let loginNote {
                    SettingsNote(loginNote, tone: LBColor.urgent)
                } else {
                    SettingsNote("Once a day, longbook asks the App Store for a newer version and tells you when one is out.")
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
                Toggle("Show the next payment in the menu bar", isOn: menuBarBinding.measured("show_next_payment_in_menu_bar"))
                    .disabled(hidesDock)
                Toggle("Hide the Dock icon", isOn: dockBinding.measured("hide_the_dock_icon"))
            } header: {
                Text("Menu bar and Dock")
            } footer: {
                SettingsNote(hidesDock
                    ? "With the Dock icon hidden, the menu bar item opens longbook and its Settings, so it stays on."
                    : "The menu bar shows your next payment, and opens longbook and its Settings.")
            }
        }
        .onAppear {
            model.clearSaveError()
            saved = model.homeCurrency
            launchesAtLogin = LaunchAtLogin.isOn
        }
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
        Binding(get: { showsMenuBar || hidesDock }, set: { showsMenuBar = $0 })
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

    @ViewBuilder
    private var currency: some View {
        if choices.count > 1 {
            Picker("Home currency", selection: currencyChoice) {
                ForEach(choices, id: \.self) { code in
                    Text(Self.currencyWords(code)).tag(String?.some(code))
                }
                Text("Automatic").tag(String?.none)
            }
            .pickerStyle(.menu)
        } else {
            // A picker of one option would be dead UI, and picking would change nothing.
            LabeledContent("Home currency", value: choices.first.map(Self.currencyWords) ?? "Automatic")
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

// MARK: Appearance

struct AppearanceSettingsPane: View {
    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue

    var body: some View {
        SettingsForm {
            Section {
                Picker("Appearance", selection: choice) {
                    Text("System").tag(LBAppearance.system.rawValue)
                    Text(LBAppearance.light.label).tag(LBAppearance.light.rawValue)
                    Text(LBAppearance.dark.label).tag(LBAppearance.dark.rawValue)
                }
                .pickerStyle(.segmented)
            } footer: {
                SettingsNote("longbook follows the Mac’s appearance, or keeps the one you pick.")
            }
        }
    }

    private var choice: Binding<String> {
        Binding(
            get: { appearance },
            set: { value in
                Measure.used("appearance")
                appearance = value
            }
        )
    }
}

// MARK: Statements

struct StatementsSettingsPane: View {
    let toMainWindow: (Notification.Name) -> Void
    @AppStorage("longbook.statements.addFound") private var addsFound = true

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Add accounts and people found in statements", isOn: $addsFound.measured("add_accounts_and_people_found"))
            } footer: {
                SettingsNote(addsFound
                    ? "When you import a statement, every account and person it names is added to Accounts and People, the other side of a transfer too."
                    : "Off: statements still name them for your AI, but Accounts and People list only what you add.")
            }
            Section {
                LabeledContent("Optimize your data") {
                    Button("Optimize…") {
                        Measure.used("optimize_your_data")
                        toMainWindow(.longbookSetUpAgain)
                    }
                }
            } footer: {
                SettingsNote("Your commitments, accounts and people, kept in your longbook as hints for reading statements, by longbook’s AI or yours.")
            }
            Section {
                LabeledContent("Import a statement") {
                    Button("Import…") {
                        Measure.used("import_statement")
                        toMainWindow(.longbookImport)
                    }
                }
            } footer: {
                SettingsNote("A PDF, CSV, text or Excel file from your bank or card. You check what it read before anything is added.")
            }
        }
    }
}

// MARK: About

struct AboutSettingsPane: View {
    @Binding var path: [Destination]
    let toMainWindow: (Notification.Name) -> Void
    @Environment(\.openURL) private var openURL

    private static let helpURL = URL(string: "https://longbook.app/help/")

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent("longbook \(AppVersion.marketing) (\(AppVersion.build))") {
                    Button("Check for Updates…") {
                        Measure.used("about_check_for_updates")
                        AppUpdates.askFromMenu()
                    }
                }
                LabeledContent("What’s New") {
                    Button("Open…") {
                        Measure.used("about_whats_new")
                        path.append(.updates)
                    }
                }
            } footer: {
                SettingsNote("The App Store or TestFlight installs new versions. longbook only opens its page.")
            }
            Section {
                link("Help", "longbook.app/help", Self.helpURL)
                link("Questions and guides", "longbook.app/faq", HelpAboutView.faqURL)
                LabeledContent("Tips") {
                    Button("Open…") {
                        Measure.used("about_tips")
                        path.append(.tips)
                    }
                }
                LabeledContent("Demo longbook") {
                    Button("Try the Demo…") {
                        Measure.used("about_try_the_demo")
                        toMainWindow(.longbookShowDemo)
                    }
                }
                LabeledContent("Send feedback") {
                    Button("Write…") {
                        Measure.used("about_send_feedback")
                        toMainWindow(.longbookSupport)
                    }
                }
                link("Suggest a feature", "insigh.to", HelpAboutView.ideasURL)
                LabeledContent("Report a problem") {
                    Button("Write…") {
                        Measure.used("about_report_a_problem")
                        if let url = HelpAboutView.problemURL { openURL(url) }
                    }
                }
                link("Contact", "contact@longbook.app", HelpAboutView.contactURL)
            } footer: {
                SettingsNote("Support answers from the help articles, or passes your message to a person.")
            }
            Section {
                link("Terms of service", "Open", HelpAboutView.termsURL)
                link("Privacy policy", "Open", HelpAboutView.privacyURL)
                link("Source code", "GPL-3.0", HelpAboutView.sourceURL)
            } footer: {
                SettingsNote("longbook never sells your data, and never uses your financial data for analytics or advertising.")
            }
        }
    }

    /// A row whose value is a link out of the app, in the brand's ink.
    private func link(_ title: String, _ words: String, _ url: URL?) -> some View {
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
