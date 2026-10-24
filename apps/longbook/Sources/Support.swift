import DesignSystem
import LongbookCore
import SwiftUI
import WebKit
#if os(iOS)
import UIKit
typealias SupportImage = UIImage
#else
import AppKit
typealias SupportImage = NSImage
#endif

/// Support: chat.sh's messenger in a web view of its own, asked about once (the consent sheet),
/// opened from Settings and Help & about, and from every screen while a conversation is open.
@MainActor
final class SupportCenter: ObservableObject {
    static let shared = SupportCenter()

    /// The longbook workspace's messenger at chat.sh. Public: it is in every page that embeds it.
    nonisolated static let site = "c9a8a115-6b20-4c4f-93d4-e281c327fc99"
    /// The chat's own storage, apart from any other web view, so clearing history clears only it.
    nonisolated static let storeID = UUID(uuidString: "6D1B3C2A-5E4F-4A7B-9C8D-0E1F2A3B4C5D")!
    private static let activeKey = "longbook.support.activeUntil"
    /// chat.sh keeps a conversation open in the browser for a day after its last message.
    private static let openFor: TimeInterval = 24 * 60 * 60

    @Published var presented = false
    @Published var askingConsent = false
    @Published private(set) var activeUntil: Date?
    /// A line under the tip after the screenshot is taken, cleared when Support closes.
    @Published var screenshotNote: String?
    /// The screen behind Support, taken the moment it opened: what the screenshot button hands on.
    private var behind: SupportImage?

    var active: Bool { (activeUntil ?? .distantPast) > Date() }

    private init() {
        activeUntil = UserDefaults.standard.object(forKey: Self.activeKey) as? Date
    }

    func open() {
        guard !presented else { return }
        behind = SupportScreenshot.capture()
        if AIConsent.support.given { presented = true } else { askingConsent = true }
    }

    func accepted() {
        UserDefaults.standard.set(true, forKey: AIConsent.support.key)
        askingConsent = false
        // The chat cannot open while the consent sheet is still leaving.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.presented = true }
    }

    func declined() { askingConsent = false }

    func close() {
        presented = false
        screenshotNote = nil
    }

    /// The page says whether a conversation is open, and when its last message was saved.
    func report(open: Bool, savedAt: Date?) {
        activeUntil = open ? (savedAt ?? Date()).addingTimeInterval(Self.openFor) : nil
        UserDefaults.standard.set(activeUntil, forKey: Self.activeKey)
    }

    /// The screen behind Support onto the clipboard, to paste into a message; on a Mac also a
    /// file the attach button's panel opens on.
    func copyScreenshot() {
        guard let image = behind else {
            screenshotNote = "There was no screen to capture."
            return
        }
        #if os(iOS)
        UIPasteboard.general.image = image
        screenshotNote = "Screenshot copied. After Talk to a person, touch and hold the message box and tap Paste."
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        SupportScreenshot.save(image)
        screenshotNote = "Screenshot copied. After Talk to a person, press Command-V in the message box."
        #endif
    }

    /// Clears the conversations this device keeps; the team's copy stays in the inbox.
    func clearHistory() async {
        let store = WKWebsiteDataStore(forIdentifier: Self.storeID)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        report(open: false, savedAt: nil)
    }
}

// MARK: screenshot

enum SupportScreenshot {
    /// The front window as it is drawn now.
    @MainActor
    static func capture() -> SupportImage? {
        #if os(iOS)
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window else { return nil }
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        #else
        guard let view = (NSApp.mainWindow ?? NSApp.keyWindow)?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
        #endif
    }

    #if os(macOS)
    /// Where the Mac keeps the last screenshot, for the attach button's panel to open on.
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("longbook-support", isDirectory: true) }

    static func save(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? png.write(to: folder.appendingPathComponent("longbook screenshot.png"))
    }
    #endif
}

// MARK: the page

/// The messenger's page: chat.sh's widget without its own button, opened at once, told who is
/// signed in, and reporting back whether a conversation is open. Never a word of the longbook.
private enum SupportPage {
    static func html(userId: String?, email: String?) -> String {
        var user: [String: Any] = [
            "attributes": ["app": "\(AppVersion.marketing) (\(AppVersion.build))", "platform": platform],
        ]
        if let userId { user["userId"] = userId }
        if let email { user["email"] = email }
        let json = (try? JSONSerialization.data(withJSONObject: user)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let site = SupportCenter.site
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;height:100%;background:transparent}</style></head><body>
        <script>
        var user = \(json);
        function post(m) { try { window.webkit.messageHandlers.support.postMessage(m); } catch (e) {} }
        function report() {
          var raw = null, saved = null;
          try { raw = localStorage.getItem('chatsh:thread:\(site)'); } catch (e) {}
          try { saved = raw ? (JSON.parse(raw).savedAt || null) : null; } catch (e) {}
          post({ kind: 'thread', open: !!raw, savedAt: saved });
        }
        function go() {
          if (!window.chatSh) { post({ kind: 'failed' }); return; }
          if (user.userId || user.email) chatSh.identify(user);
          chatSh.on('close', function () { report(); post({ kind: 'close' }); });
          // An open sent before the widget is ready is dropped, so open again once it is.
          chatSh.on('ready', function () { chatSh.open(); });
          chatSh.open();
          report();
          setInterval(report, 5000);
        }
        </script>
        <script src="https://chat.sh/widget.js" data-site="\(site)" data-launcher="none" async onload="go()" onerror="post({kind:'failed'})"></script>
        </body></html>
        """
    }

    private static var platform: String {
        #if os(iOS)
        "iOS \(UIDevice.current.systemVersion)"
        #else
        "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
    }
}

/// Reads the page's messages; weak, so the web view does not keep its own handler alive.
private final class SupportMessages: NSObject, WKScriptMessageHandler, WKUIDelegate {
    var onFailed: () -> Void = {}

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        Task { @MainActor in
            switch kind {
            case "thread":
                SupportCenter.shared.report(open: body["open"] as? Bool ?? false, savedAt: Self.date(body["savedAt"]))
            case "close":
                SupportCenter.shared.close()
            case "failed":
                self.onFailed()
            default:
                break
            }
        }
    }

    /// chat.sh's saved time, as milliseconds, seconds or an ISO date.
    private static func date(_ value: Any?) -> Date? {
        if let n = value as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        if let s = value as? String { return ISO8601DateFormatter().date(from: s) }
        return nil
    }

    #if os(macOS)
    /// The attach button's file panel opens where the last screenshot was saved.
    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        if FileManager.default.fileExists(atPath: SupportScreenshot.folder.path) {
            panel.directoryURL = SupportScreenshot.folder
        }
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }
    #endif
}

#if os(iOS)
private typealias SupportRepresentable = UIViewRepresentable
#else
private typealias SupportRepresentable = NSViewRepresentable
#endif

private struct SupportWebView: SupportRepresentable {
    let html: String
    let onFailed: () -> Void

    func makeCoordinator() -> SupportMessages { SupportMessages() }

    private func make(_ coordinator: SupportMessages) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: SupportCenter.storeID)
        config.userContentController.add(coordinator, name: "support")
        coordinator.onFailed = onFailed
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = coordinator
        #if os(iOS)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        #else
        view.setValue(false, forKey: "drawsBackground")
        #endif
        // The page claims longbook.app, where the website's Support page lives, so the chat
        // reports one place in the inbox.
        view.loadHTMLString(html, baseURL: URL(string: "https://longbook.app/support/"))
        return view
    }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { make(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: SupportMessages) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "support")
    }
    #else
    func makeNSView(context: Context) -> WKWebView { make(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: SupportMessages) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "support")
    }
    #endif
}

// MARK: the sheet, the panel

/// What Support shows: a bar with Done (the phone) or Hide (the Mac), the screenshot tip, and the
/// messenger beneath.
struct SupportScreen: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject private var center = SupportCenter.shared
    @State private var page: String?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            bar
            tip
            if failed {
                Text("Support could not open. Write to contact@longbook.app instead.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .padding(LBSpacing.s6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if let page {
                SupportWebView(html: page) { failed = true }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(LBColor.canvas.color)
        .task {
            let id = await auth.userId()?.uuidString
            page = SupportPage.html(userId: id, email: auth.email)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationBackground(LBColor.chrome.color)
        #endif
    }

    private var bar: some View {
        HStack {
            Text("Support")
                .lbText(.headline)
                .foregroundStyle(LBColor.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LBSpacing.s3)
            #if os(iOS)
            Button("Done") { Measure.used("support_done"); center.close() }
                .lbText(.body)
                .foregroundStyle(LBColor.brandText.color)
            #else
            Button { Measure.used("support_hide"); center.close() } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LBColor.textSecondary.color)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide Support")
            .accessibilityLabel("Hide Support")
            #endif
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, LBSpacing.s3)
        .background(LBColor.chrome.color)
        .overlay(alignment: .bottom) { Rectangle().fill(LBColor.hairline.color).frame(height: 1) }
    }

    private var tip: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s2) {
            HStack(alignment: .top, spacing: LBSpacing.s3) {
                Text("Need to show a problem? Attach a screenshot. Check it first, it may show amounts.")
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { Measure.used("support_screenshot"); center.copyScreenshot() } label: {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                        .lbText(.label)
                        .foregroundStyle(LBColor.brandText.color)
                }
                .buttonStyle(.plain)
                .help("Copy a screenshot of the screen behind Support")
            }
            if let note = center.screenshotNote {
                Text(note)
                    .lbText(.footnote)
                    .foregroundStyle(LBColor.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LBSpacing.s3)
        .background(LBColor.brand.color.opacity(0.12), in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .padding(LBSpacing.s3)
    }
}

// MARK: the button

/// The floating Support button. The dot says a conversation is open.
struct SupportButton: View {
    /// What the press does, when Support opens in another window (the Mac's Settings).
    var action: (() -> Void)? = nil
    @ObservedObject private var center = SupportCenter.shared

    var body: some View {
        Button { Measure.used("support_button"); (action ?? center.open)() } label: {
            HStack(spacing: LBSpacing.s2) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Support")
                    .lbText(.label)
            }
            .foregroundStyle(LBColor.onBrand.color)
            .padding(.horizontal, LBSpacing.s4)
            .padding(.vertical, 11)
            .background(LBColor.brand.color, in: Capsule())
            .overlay(alignment: .topTrailing) {
                if center.active {
                    Circle().fill(LBColor.urgent.color)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(LBColor.chrome.color, lineWidth: 2))
                        .offset(x: 2, y: -2)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(center.active ? "Support, conversation open" : "Support")
    }
}

/// The consent sheet before the first chat, and on the phone the chat sheet itself.
struct SupportPresenter: ViewModifier {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject private var center = SupportCenter.shared

    func body(content: Content) -> some View {
        content
            .measured("support_consent", .sheet, when: center.askingConsent)
            .sheet(isPresented: $center.askingConsent) {
                ConsentSheet(consent: .support, onAccept: center.accepted, onDecline: center.declined)
            }
            #if os(iOS)
            .measured("support_chat", .sheet, when: center.presented)
            .sheet(isPresented: Binding(get: { center.presented }, set: { if !$0 { center.close() } })) {
                SupportScreen(auth: auth)
            }
            #endif
    }
}

// MARK: Help & about

/// Support's rows in What leaves this device: the fact, Allow Support, Clear support history.
struct SupportPrivacyRows: View {
    @AppStorage(AIConsent.support.key) private var allowed = false
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Support")
                    .lbText(.body)
                    .foregroundStyle(LBColor.textPrimary.color)
                Text("Your messages and screenshots go to chat.sh, our support service. An AI answers first from our help articles. Never the contents of your longbook.")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Withdrawing is turning this off: the next time Support opens, it asks again.
            Toggle(isOn: $allowed.measured("allow_support")) {
                Text("Allow Support")
                    .lbText(.bodySM)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
            .tint(LBColor.brand.color)
            Button {
                Measure.used("clear_support_history")
                Task {
                    await SupportCenter.shared.clearHistory()
                    cleared = true
                }
            } label: {
                Text(cleared ? "Support history cleared" : "Clear support history")
                    .lbText(.bodySM)
                    .foregroundStyle(cleared ? LBColor.textTertiary.color : LBColor.brandText.color)
            }
            .buttonStyle(.plain)
            .disabled(cleared)
        }
    }
}
