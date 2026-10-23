import DesignSystem
import LongbookCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct LongbookApp: App {
    #if os(macOS)
    /// The tray's own vault read — the menu bar answers with every window closed.
    @StateObject private var tray = TrayModel()
    @Environment(\.openWindow) private var openWindow
    #endif

    #if os(macOS) && DEBUG
    init() {
        Snapshot.runIfAsked()
    }
    #elseif os(iOS)
    init() {
        // The navigation bar's titles in the design's face: a Large Title over each
        // screen that folds into a Headline as the page scrolls.
        let bar = UINavigationBar.appearance()
        let ink = UIColor(LBColor.textPrimary.color)
        bar.largeTitleTextAttributes = [.font: LBFont.uiFont(.largeTitle), .foregroundColor: ink]
        bar.titleTextAttributes = [.font: LBFont.uiFont(.headline), .foregroundColor: ink]
        bar.tintColor = UIColor(LBColor.brandText.color)
    }
    #endif

    @AppStorage("appearance") private var appearance = LBAppearance.system.rawValue
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some Scene {
        #if os(macOS)
        // One window, by id, not a group: the view owns the model and the commands are an
        // unfiltered broadcast, so a second window would mean two models over one file.
        // The id is also what lets the tray and the Dock put a closed window back.
        Window("longbook", id: LongbookWindow.main) {
            RootView()
                .preferredColorScheme((LBAppearance(rawValue: appearance) ?? .system).colorScheme)
                .background(CentersSheets())
        }
        .defaultSize(width: 1280, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands { LongbookCommands() }

        // The app menu's Settings… (⌘,) opens this window, as on every Mac app.
        Settings {
            SettingsWindowView()
        }
        #else
        WindowGroup {
            RootView()
                // Dark is the authored canvas and the default; light is the second
                // palette the reader can choose. System hands the choice to the OS.
                .preferredColorScheme((LBAppearance(rawValue: appearance) ?? .system).colorScheme)
                // The window itself takes the choice too, the moment it changes and each time
                // the app comes forward, so nothing waits for a relaunch.
                .onChange(of: appearance, initial: true) { _, value in LBAppearance.applyToWindows(value) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { LBAppearance.applyToWindows(appearance) }
                }
        }
        #endif

        #if os(macOS)
        // The desktop's menu-bar indicator, as a scene: the next payment beside the clock.
        MenuBarExtra {
            Group {
                Text(tray.menuLine)
                Divider()
                Button("Open longbook") {
                    // Activation alone raises a process that may have no window left.
                    openWindow(id: LongbookWindow.main)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Refresh") { tray.refresh() }
                Divider()
                Button("Quit longbook") { NSApplication.shared.terminate(nil) }
            }
            // Opening the menu re-reads the vault, so the line is never a stale answer.
            .onAppear { tray.refresh() }
        } label: {
            Text(tray.title)
        }
        #endif
    }
}

#if os(macOS) && DEBUG
import AppKit

/// Development harness: render the root view to a PNG in a window that is never ordered
/// onto the screen, then exit. Lets a build be seen without taking anyone's display.
enum Snapshot {
    /// The real window, as it stands after `LONGBOOK_SNAPSHOT_WAIT` seconds: the key window
    /// (a sheet when one is up) drawn to a PNG at Retina scale, then the app quits.
    static func windowSnapshot(to path: String, env: [String: String]) {
        let wait = env["LONGBOOK_SNAPSHOT_WAIT"].flatMap(Double.init) ?? 5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            let main = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
            let window = main?.attachedSheet ?? main
            if let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
            }
            exit(0)
        }
    }

    static func runIfAsked() {
        let env = ProcessInfo.processInfo.environment
        if let path = env["LONGBOOK_WINDOW_SNAPSHOT"] { return windowSnapshot(to: path, env: env) }
        guard let path = env["LONGBOOK_SNAPSHOT"] else { return }
        // A taller frame shows a whole scrolling screen; a named width makes a store-size
        // picture. The default is a window's worth.
        let height = env["LONGBOOK_SNAPSHOT_HEIGHT"].flatMap { CGFloat(Double($0) ?? 0) }.map { max($0, 900) } ?? 900
        let width = env["LONGBOOK_SNAPSHOT_WIDTH"].flatMap { CGFloat(Double($0) ?? 0) }.map { max($0, 1024) } ?? 1280
        // A named screen is hosted as the plain root: the shell's pushed panes and sheets
        // do not draw in a window nothing shows. No name means the dashboard in its shell.
        let named = env["LONGBOOK_SNAPSHOT_SHEET"] ?? env["LONGBOOK_SNAPSHOT_SCREEN"]
        // A screen the sidebar opens is pictured in the shell, beside the sidebar, as the
        // reader meets it; a sheet or a setup screen stands alone.
        let inShell: Set<String> = ["commitments", "charges", "noaccount", "daterange", "commitment", "calendar", "accounts",
                                    "members", "insights", "reports", "report", "changes", "trips"]
        let root: AnyView
        if let named, !named.isEmpty, !inShell.contains(named) || env["LONGBOOK_SNAPSHOT_SHEET"] != nil {
            root = AnyView(SnapshotScreenHost(screen: named, id: env["LONGBOOK_SNAPSHOT_ID"] ?? ""))
        } else {
            root = AnyView(RootView())
        }
        // The harness follows the app's own appearance setting (-appearance light|dark); dark by default.
        let light = UserDefaults.standard.string(forKey: "appearance") == LBAppearance.light.rawValue
        let view = NSHostingView(
            rootView: root.preferredColorScheme(light ? .light : .dark).frame(width: width, height: height)
        )
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = view
        window.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        // Layout needs a few runloop turns; the window never appears because nothing
        // orders it front. A screen that works first can ask for longer.
        let wait = env["LONGBOOK_SNAPSHOT_WAIT"].flatMap(Double.init) ?? 3
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        // A scale above 1 draws the same layout into a denser bitmap, as a Retina screen would:
        // store pictures need twice the pixels of a window's points.
        let scale = env["LONGBOOK_SNAPSHOT_SCALE"].flatMap(Double.init).map { max(1, min($0, 3)) } ?? 1
        let rep: NSBitmapImageRep
        if scale > 1 {
            guard let dense = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { exit(1) }
            dense.size = view.bounds.size
            rep = dense
        } else {
            guard let plain = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            rep = plain
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? data.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}

/// Hosts one screen as a plain root so the harness can picture it, drawing the content the
/// shell's NavigationStack would push. Its own model, auth and store read the vault the env
/// names; the sidebar and tab bar are the shell's and are absent here.
private struct SnapshotScreenHost: View {
    let screen: String
    let id: String
    /// The onboarding stage a harness screen name stands for.
    static func stage(for screen: String) -> OnboardingStage {
        switch screen {
        case "setupaccounts": return .accounts(card: 0)
        case "setupsummary": return .commitmentsDone
        case "setupstatement": return .finish
        default: return .commitments(card: 0)
        }
    }
    static func settingsTab(_ id: String) -> Destination {
        switch id {
        case "account": .accountDetails
        case "ai": .mcpServer
        case "data": .privacy
        default: .display
        }
    }
    @State private var model = DashboardModel()
    @StateObject private var auth = AuthViewModel()
    @StateObject private var entitlement = EntitlementStore()
    var body: some View {
        // A stack, as the shell gives every screen: a link outside one draws disabled.
        NavigationStack {
            switch screen {
            case "commitments": CommitmentsView(model: model, filter: ListFilter())
            case "commitment": CommitmentDetailView(model: model, id: id)
            case "calendar": CalendarView(model: model)
            case "accounts": AccountsView(model: model)
            case "members": MembersView(model: model)
            case "insights": InsightsView(model: model, path: .constant([]))
            case "reports": ReportsView(model: model, auth: auth)
            case "report": ReportDetailView(model: model, id: id, auth: auth)
            case "changes": ChangesView(model: model)
            case "connectai", "automations": AutomationsView(model: model, auth: auth)
            // The Settings window at its own width; LONGBOOK_SNAPSHOT_ID names the tab.
            case "settings": SnapshotSettingsWindow(model: model, auth: auth, entitlement: entitlement, picked: Self.settingsTab(id))
            case "more": MoreView(model: model, auth: auth) {}
            case "account": AccountDetailsView(auth: auth, entitlement: entitlement)
            case "display": DisplayCurrencyView(model: model)
            case "privacy": DataPrivacyView(model: model)
            case "help", "helpabout": HelpAboutView(model: model)
            case "signout": SignOutScreenView(auth: auth)
            case "updates": UpdatesView()
            case "trips": TripsView(model: model, path: .constant([]))
            case "addtrip": TripFlowView(model: model, mode: .past, onCreated: { _ in }, onClose: {})
            case "starttrip": TripFlowView(model: model, mode: .start, onCreated: { _ in }, onClose: {})
            case "billing": BillingView(entitlement: entitlement, auth: auth)
            case "purchase": PurchaseView(auth: auth, entitlement: entitlement)
            case "addcommitment": RenewalFormView(model: model, editingId: nil, onDone: {})
            case "importstatement": StatementImportView(model: model, auth: auth, onDone: {})
            case "consent": ConsentSheet(consent: .statements, onAccept: {}, onDecline: {})
            case "reorganise": ReorganiseView(model: model, auth: auth, onDone: {})
            case "charges": CommitmentsView(model: model, filter: ListFilter(scope: .past, months: id.isEmpty ? [] : [id]))
            case "noaccount": CommitmentsView(model: model, filter: ListFilter(months: id.isEmpty ? [] : [id], methodId: DashboardModel.unassignedMethodId))
            case "daterange": CommitmentsView(model: model, filter: ListFilter.snapshotRange(id))
            case "editaccount": SnapshotAccountEdit(model: model)
            case "editmember": SnapshotMemberEdit(model: model)
            case "editcommitment": SnapshotCommitmentEdit(model: model)
            case "editcharge": SnapshotChargeEdit(model: model)
            case "tips": TipsView()
            case "welcome": WelcomeView(onDone: {})
            case "waiting": OnboardingWaitingView(commitments: 2, accounts: 0, onResume: {}, onDemo: {})
            case "demo": DemoLongbookView(auth: auth, onLeave: {})
            case "picker", "setupmembers", "setupaccounts", "setupsummary", "setupstatement":
                OnboardingFlowView(model: model, auth: auth,
                                   session: OnboardingSession(start: Self.stage(for: screen), paused: false, model: model,
                                                              replay: ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_REPLAY"] != nil),
                                   replay: ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_REPLAY"] != nil, onDone: {})
            case "vaultchoice": VaultChoiceView(model: model, auth: auth)
            case "signin": SignInView(auth: auth, onBack: {})
            case "deleteaccount": DeleteAccountSheet(auth: auth, onClose: {})
            default: DashboardView(model: model, auth: auth, path: .constant([]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LBColor.canvas.color)
        .environmentObject(entitlement)
        .onAppear { model.load() }
    }
}

/// The Settings window at its own width. An offscreen window draws no toolbar, so the tab
/// bar macOS puts there is drawn here as a stand-in, with the picked tab's content beneath.
private struct SnapshotSettingsWindow: View {
    let model: DashboardModel
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var entitlement: EntitlementStore
    let picked: Destination

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LBSpacing.s2) {
                ForEach(SettingsTabs.tabs, id: \.title) { item in
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol).font(.system(size: 18))
                        Text(item.title).font(.system(size: 11))
                    }
                    .foregroundStyle(item.root == picked ? LBColor.brandText.color : LBColor.textSecondary.color)
                    .frame(width: 64, height: 48)
                    .background(item.root == picked ? LBColor.chrome.color : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LBSpacing.s2)
            .background(LBColor.card.color)
            SettingsTab(root: picked, model: model, auth: auth, entitlement: entitlement, toMainWindow: { _ in })
        }
        .frame(width: 720)
        .border(LBColor.hairline.color)
    }
}

/// The first real account's editor, once the vault has loaded and named one.
/// The member editor as the window's root, since an offscreen window paints no sheet.
private struct SnapshotMemberEdit: View {
    let model: DashboardModel
    var body: some View {
        if let first = model.entityCards(.familyMember).first(where: \.isReal) {
            EntityEditView(model: model, kind: .familyMember, id: first.id, currentName: first.name) {}
        } else {
            Color.clear
        }
    }
}

private struct SnapshotAccountEdit: View {
    let model: DashboardModel
    var body: some View {
        if let first = model.accountCards().first(where: { $0.id != DashboardModel.unassignedMethodId }) {
            EntityEditView(model: model, kind: .paymentMethod, id: first.id, currentName: first.name) {}
        } else {
            Color.clear
        }
    }
}
#endif

#if DEBUG
/// The phone's edit sheet for the harness: the form LONGBOOK_SNAPSHOT_SCREEN names.
struct SnapshotEditForm: View {
    let model: DashboardModel
    var body: some View {
        // Sized as the app opens it: on a charge over three quarters, on a commitment full.
        if ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_SCREEN"] == "editcharge" {
            SnapshotChargeEdit(model: model)
                .lbThreeQuarterSheet()
        } else {
            SnapshotCommitmentEdit(model: model)
        }
    }
}

/// The editing form rather than the adding one, named by LONGBOOK_SNAPSHOT_ID: Status and
/// Cancelling On only appear for a commitment that exists.
struct SnapshotCommitmentEdit: View {
    let model: DashboardModel
    var body: some View {
        let wanted = ProcessInfo.processInfo.environment["LONGBOOK_SNAPSHOT_ID"] ?? ""
        if model.subscription(id: wanted) != nil {
            RenewalFormView(model: model, editingId: wanted, onDone: {})
        } else {
            Color.clear
        }
    }
}

/// The form opened on one charge: the commitment named by LONGBOOK_SNAPSHOT_ID, and the row
/// on the ISO day named by LONGBOOK_SNAPSHOT_CHARGE.
struct SnapshotChargeEdit: View {
    let model: DashboardModel
    var body: some View {
        let env = ProcessInfo.processInfo.environment
        let wanted = env["LONGBOOK_SNAPSHOT_ID"] ?? ""
        let day = env["LONGBOOK_SNAPSHOT_CHARGE"] ?? ""
        if model.charges(of: wanted).contains(where: { $0.row.date == day }) {
            RenewalFormView(model: model, editingId: wanted, chargeISO: day, onDone: {})
        } else {
            Color.clear
        }
    }
}
#endif
