import CryptoKit
import Foundation
import LongbookCore
import MetricKit
import StoreKit
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
import WidgetKit
#endif

/// The running build and the system under it, as Info.plist and the OS report them.
enum AppVersion {
    static let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    /// The commit the build scripts stamped; empty for a build Xcode made by hand.
    static let commit = Bundle.main.object(forInfoDictionaryKey: "LongbookCommit") as? String ?? ""
    #if os(macOS)
    static let systemName = "macOS"
    static let platform = "macos"
    #else
    static let systemName = "iOS"
    static let platform = "ios"
    #endif
    static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion > 0 ? "\(base).\(version.patchVersion)" : base
    }()

    /// "longbook 1.3.3 (17), iOS 17.4": the line a problem report ends with.
    static var line: String { "longbook \(marketing) (\(build)), \(systemName) \(osVersion)" }
}

/// Usage counts and crash reports, posted to PostHog under a random install id kept on this
/// device only. Turning the switch off deletes the id and stops sending; turning it on makes a
/// new one. Never joined to the account. DEBUG builds never post.
@MainActor
final class Telemetry {
    static let shared = Telemetry()
    /// The owner's switch. Absent means on.
    static let shareUsageKey = "longbook.shareUsage"
    /// The random install id. Never the device's own identifiers, never sent anywhere but here.
    static let installIdKey = "longbook.installId"
    /// Set once this install has counted the start of a trial.
    static let trialCountedKey = "longbook.trialCounted"

    private static let endpoint = URL(string: "https://us.i.posthog.com/batch/")!
    /// A project token: it can add events to the project, never read them back.
    private static let token = "phc_pTXUJ2Qh4fYGu6EmDiwZcAYj6i9htiEQETbYZxApGDaM"
    private static let userAgent = "longbook/\(AppVersion.marketing) (\(AppVersion.systemName) \(AppVersion.osVersion))"

    /// Ephemeral: no cookies, no cache, no credential store. One try, then it is dropped.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    private let subscriber = DiagnosticSubscriber()
    private var subscribed = false
    private var launchCounted = false
    /// Digests of diagnostics already sent by this process, so a report MetricKit hands over
    /// twice in one run is sent once. Memory only.
    private var sentDiagnostics: Set<String> = []

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.shareUsageKey) as? Bool ?? true
    }

    /// At launch: diagnostics are subscribed to only while sharing is on.
    func start() {
        if isEnabled { subscribe() }
        #if os(macOS)
        // Quitting ends the session as going to the background does on iPhone.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            // The process ends right after, so the last batch is given up to a second to leave.
            MainActor.assumeIsolated { Telemetry.shared.wentAway(waitingUpTo: 1) }
        }
        #endif
    }

    /// The switch in Help & about. Off stops MetricKit delivery at once and deletes the id.
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.shareUsageKey)
        if on {
            subscribe()
        } else {
            unsubscribe()
            UserDefaults.standard.removeObject(forKey: Self.installIdKey)
            flushTask?.cancel()
            flushTask = nil
            held.removeAll()
        }
    }

    /// The install id as it stands, for the owner to quote when writing to us; nil while
    /// sharing is off, since then there is none.
    var installIdIfSharing: String? {
        isEnabled ? UserDefaults.standard.string(forKey: Self.installIdKey) : nil
    }

    /// Made on the first event sent with sharing on, and kept until the switch is turned off.
    private var installId: String {
        if let id = UserDefaults.standard.string(forKey: Self.installIdKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: Self.installIdKey)
        return id
    }

    /// A trial that began in the last ten minutes was begun by this sign-in, so it is counted
    /// once; an older one was started on another device or before a reinstall.
    func trialSeen(endsAt: Date?) {
        guard let endsAt, !UserDefaults.standard.bool(forKey: Self.trialCountedKey) else { return }
        let started = endsAt.addingTimeInterval(-Double(TRIAL_DAYS) * 86_400)
        guard abs(Date().timeIntervalSince(started)) < 600 else { return }
        UserDefaults.standard.set(true, forKey: Self.trialCountedKey)
        send("app.trial_started")
    }

    /// Once per process, however many times the window is rebuilt, with the channel the copy came
    /// through. On iPhone and iPad it says how many longbook widgets are placed; WidgetKit answers.
    func launched(signedIn: Bool) {
        guard !launchCounted else { return }
        launchCounted = true
        Task {
            var props: [String: Any] = [
                "is_signed_in": signedIn, "device_class": Self.deviceClass, "channel": Distribution.current.channel,
            ]
            #if os(iOS)
            props["widgets_installed"] = await withCheckedContinuation { done in
                WidgetCenter.shared.getCurrentConfigurations { result in
                    done.resume(returning: (try? result.get().count) ?? 0)
                }
            }
            #endif
            send("app.launched", props)
        }
    }

    static var deviceClass: String {
        #if os(macOS)
        "mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }

    // MARK: sessions

    private var foregroundSince: Date?
    private var screensThisSession = 0
    /// The tab or page in front and the popups over it, newest last: where a control is used.
    private var page = ""
    private var popups: [String] = []

    /// How a screen appeared: a tab, a pushed page, or something presented over them.
    enum ScreenKind: String {
        case tab, page, sheet, popover, alert, dialog
    }

    /// A screen opened, sent on its own. Tabs and pages also count toward the session's screens.
    func screen(_ name: String, kind: ScreenKind = .page) {
        if kind == .tab || kind == .page {
            screensThisSession += 1
            page = name
        } else {
            popups.append(name)
        }
        send("app.screen_viewed", ["screen": name, "kind": kind.rawValue])
    }

    /// A step back to a page already counted: nothing is sent, but controls are on it again.
    func cameBack(to name: String) {
        page = name
    }

    /// A popup went away, so controls are on what lies under it again.
    func dismissed(_ name: String) {
        if let at = popups.lastIndex(of: name) { popups.remove(at: at) }
    }

    /// What kind of control was used.
    enum ControlKind: String {
        case button, toggle, link, swipe, shortcut
        case menuItem = "menu_item"
        case contextMenu = "context_menu"
    }

    /// A control used, by the fixed name the code gives it, on the screen in front.
    func control(_ name: String, kind: ControlKind, on: Bool? = nil) {
        // Before any page is counted (sign-in, setup), the screen is "unnamed".
        let screen = popups.last ?? (page.isEmpty ? "unnamed" : page)
        var props: [String: Any] = ["control": name, "screen": screen, "kind": kind.rawValue]
        if let on { props["on"] = on }
        send("app.control_used", props)
    }

    /// The app came to the front. A session already running keeps its start.
    func cameForward() {
        guard foregroundSince == nil else { return }
        foregroundSince = Date()
        screensThisSession = 0
    }

    /// The app went to the background or is quitting: how long it was in front, to the
    /// nearest 5 seconds, and how many screens were opened.
    func wentAway(waitingUpTo wait: TimeInterval? = nil) {
        // Whatever is held goes now, with or without a session to end.
        defer { flush(waitingUpTo: wait) }
        guard let since = foregroundSince else { return }
        foregroundSince = nil
        let seconds = Int((Date().timeIntervalSince(since) / 5).rounded()) * 5
        send("app.session_ended", ["seconds": seconds, "screens": screensThisSession])
        screensThisSession = 0
    }

    // MARK: errors

    /// Where a handled error happened. A fixed list, so nothing the error says is ever sent.
    enum Place: String {
        case statementImport = "statement_import"
        case hostedCopy = "hosted_copy"
        case reportShare = "report_share"
        case purchase
        case signInApple = "sign_in_apple"
        case signInGoogle = "sign_in_google"
        case signInEmailSend = "sign_in_email_send"
        case signInEmailCode = "sign_in_email_code"
        case fileOpen = "file_open"
        case fileSave = "file_save"
    }

    /// What kind of error it was. Also a fixed list.
    enum Kind: String {
        case network
        case fileAccess = "file_access"
        case parse
        case store
        case auth
        case unknown
    }

    /// An error the app handled: its place and kind only, never its message or a path.
    func failed(_ place: Place, _ error: Error) {
        failed(place, kind: Self.kind(of: error))
    }

    func failed(_ place: Place, kind: Kind, _ auth: AuthFailure? = nil) {
        var props = ["place": place.rawValue, "kind": kind.rawValue]
        if let auth {
            props["source"] = auth.source
            props["code"] = auth.code
        }
        send("app.error", props)
    }

    static func kind(of error: Error) -> Kind {
        if error is URLError { return .network }
        if error is DecodingError { return .parse }
        if error is StoreKitError || error is Product.PurchaseError { return .store }
        let ns = error as NSError
        switch ns.domain {
        case NSURLErrorDomain: return .network
        case NSPOSIXErrorDomain: return .fileAccess
        case NSCocoaErrorDomain:
            // 3840 and the property-list range are a file that could not be read as JSON.
            if ns.code == 3840 || (3840...3851).contains(ns.code) || (2048...2559).contains(ns.code) { return .parse }
            return (0...1023).contains(ns.code) ? .fileAccess : .unknown
        default: return .unknown
        }
    }

    // MARK: who changed the file

    /// Rows that changed in the memory file, by who signed them and the way they came in.
    /// `source` comes from a row's `_provenance` signature by name: the app's own, a known
    /// AI's, any other, or `direct` for a row nobody signed.
    func changeApplied(source: String, door: String, rows: Int) {
        guard rows > 0 else { return }
        send("app.change_applied", ["source": source, "door": door, "rows": rows])
    }

    static func source(signedBy editedBy: String?) -> String {
        let by = (editedBy ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if by.isEmpty { return "direct" }
        if by.hasPrefix("longbook-") { return "app" }
        if by.contains("claude") || by.contains("anthropic") { return "claude" }
        if by.contains("chatgpt") || by.contains("openai") { return "chatgpt" }
        if by.contains("gemini") { return "gemini" }
        if by.contains("cursor") { return "cursor" }
        return "other"
    }

    /// Events wait in memory, at most fifty and at most ten seconds, then go together. Nothing
    /// is written to disk: an app killed in between loses what it held.
    private var held: [[String: Any]] = []
    private var flushTask: Task<Void, Never>?
    private static let batchLimit = 50

    /// One event. Properties are counts and fixed words only, never the owner's data.
    func send(_ event: String, _ props: [String: Any] = [:]) {
        guard isEnabled else { return }
        held.append(Self.event(event, props, id: installId))
        if held.count >= Self.batchLimit {
            flush()
        } else if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }
    }

    /// Sends what is held: on a full batch, ten seconds after the first, and as the app goes away.
    /// With `waitingUpTo`, blocks until the post answers or that time passes.
    func flush(waitingUpTo wait: TimeInterval? = nil) {
        flushTask?.cancel()
        flushTask = nil
        guard !held.isEmpty else { return }
        let events = held
        held = []
        guard let wait else { return post(events) }
        let answered = DispatchSemaphore(value: 0)
        post(events) { answered.signal() }
        _ = answered.wait(timeout: .now() + wait)
    }

    /// Crash, hang and exception reports. Version, build and system are the ones that
    /// failed, from MetricKit, not the build running now.
    func report(_ diagnostics: [Diagnostic]) {
        guard isEnabled else { return }
        let fresh = diagnostics.filter { sentDiagnostics.insert($0.digest).inserted }
        guard !fresh.isEmpty else { return }
        let id = installId
        post(fresh.map { found in
            Self.event("app.diagnostic", [
                "kind": found.kind,
                "exception_type": Self.orNull(found.exceptionType),
                "exception_code": Self.orNull(found.exceptionCode),
                "signal": Self.orNull(found.signal),
                "termination_reason": Self.orNull(found.terminationReason),
                "device_type": found.deviceType,
                "payload": found.payload,
                "app_version": found.appVersion,
                "app_build": found.appBuild,
                "os_version_full": found.osVersion,
            ], id: id)
        })
    }

    private func subscribe() {
        guard !subscribed else { return }
        subscribed = true
        // Only what MetricKit delivers from now on: re-reading its history would send reports
        // made while sharing was off.
        MXMetricManager.shared.add(subscriber)
    }

    private func unsubscribe() {
        guard subscribed else { return }
        subscribed = false
        MXMetricManager.shared.remove(subscriber)
    }

    private static func orNull(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private static func event(_ name: String, _ props: [String: Any], id: String) -> [String: Any] {
        var properties: [String: Any] = [
            "$process_person_profile": false,
            // PostHog reads the country and city off the IP at the door, then drops the IP.
            "$raw_user_agent": userAgent,
            "$host": "app.longbook.app",
            "$lib": "longbook-app",
            "platform": AppVersion.platform,
            "app_version": AppVersion.marketing,
            "app_build": AppVersion.build,
            "os_version": AppVersion.osVersion,
        ]
        properties.merge(props) { _, given in given }
        return [
            "event": name,
            "distinct_id": id,
            "properties": properties,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    /// Fire and forget: no retry, nothing kept. DEBUG prints instead, and only when asked to.
    private func post(_ events: [[String: Any]], answered: (@Sendable () -> Void)? = nil) {
        #if DEBUG
        defer { answered?() }
        guard ProcessInfo.processInfo.environment["LONGBOOK_TELEMETRY_LOG"] == "1",
              let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
        else { return }
        print("telemetry (not sent):", String(decoding: data, as: UTF8.self))
        #else
        let body: [String: Any] = ["api_key": Self.token, "batch": events]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            answered?()
            return
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = data
        // The session answers on its own queue, so a wait on the main thread can end.
        session.dataTask(with: request) { _, _, _ in answered?() }.resume()
        #endif
    }
}

/// One MetricKit diagnostic, read into plain values on MetricKit's own queue.
struct Diagnostic: Sendable {
    let kind: String
    let exceptionType: Int?
    let exceptionCode: Int?
    let signal: Int?
    let terminationReason: String?
    let deviceType: String
    let appVersion: String
    let appBuild: String
    let osVersion: String
    /// The diagnostic's own JSON, scrubbed and cut to `payloadLimit` characters.
    let payload: String
    /// SHA-256 of the unscrubbed JSON, for de-duplication in memory. Never sent.
    let digest: String

    static let payloadLimit = 100_000
    /// Dropped at any depth: the region, the process id, memory-region text that can name
    /// file paths, and an Objective-C exception's message and arguments. The format string stays.
    private static let scrubbedKeys: Set<String> = [
        "regionFormat", "pid", "virtualMemoryRegionInfo", "composedMessage", "arguments",
    ]

    static func all(in payload: MXDiagnosticPayload) -> [Diagnostic] {
        var found: [Diagnostic] = []
        found += (payload.crashDiagnostics ?? []).map { make("crash", $0, crash: $0) }
        found += (payload.hangDiagnostics ?? []).map { make("hang", $0) }
        found += (payload.cpuExceptionDiagnostics ?? []).map { make("cpu_exception", $0) }
        found += (payload.diskWriteExceptionDiagnostics ?? []).map { make("disk_write_exception", $0) }
        #if os(iOS)
        // Launch diagnostics exist on iOS only.
        found += (payload.appLaunchDiagnostics ?? []).map { make("launch", $0) }
        #endif
        return found
    }

    private static func make(_ kind: String, _ diagnostic: MXDiagnostic, crash: MXCrashDiagnostic? = nil) -> Diagnostic {
        let raw = diagnostic.jsonRepresentation()
        var json = ""
        if let object = try? JSONSerialization.jsonObject(with: raw),
           let clean = try? JSONSerialization.data(withJSONObject: scrub(object), options: [.sortedKeys]) {
            json = String(String(decoding: clean, as: UTF8.self).prefix(payloadLimit))
        }
        return Diagnostic(
            kind: kind,
            exceptionType: crash?.exceptionType?.intValue,
            exceptionCode: crash?.exceptionCode?.intValue,
            signal: crash?.signal?.intValue,
            terminationReason: crash?.terminationReason,
            deviceType: diagnostic.metaData.deviceType,
            appVersion: diagnostic.applicationVersion,
            appBuild: diagnostic.metaData.applicationBuildVersion,
            osVersion: diagnostic.metaData.osVersion,
            payload: json,
            digest: SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func scrub(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            var kept: [String: Any] = [:]
            for (key, inner) in object where !scrubbedKeys.contains(key) {
                kept[key] = key == "callStackRootFrames" ? flatFrames(inner as? [Any] ?? []) : scrub(inner)
            }
            return kept
        }
        if let list = value as? [Any] { return list.map(scrub) }
        return value
    }

    /// MetricKit nests a call stack one level per frame. Written back out that deep, it
    /// overflowed MetricKit's thread and crashed the app, so frames become one list with depths.
    static func flatFrames(_ roots: [Any]) -> [[String: Any]] {
        var flat: [[String: Any]] = []
        var pending: [(frame: Any, depth: Int)] = roots.reversed().map { ($0, 0) }
        while let (frame, depth) = pending.popLast() {
            guard let object = frame as? [String: Any] else { continue }
            var kept = object.filter { $0.key != "subFrames" && !scrubbedKeys.contains($0.key) }
            kept["depth"] = depth
            flat.append(kept)
            let children = object["subFrames"] as? [Any] ?? []
            pending += children.reversed().map { ($0, depth + 1) }
        }
        return flat
    }
}

/// MetricKit's subscriber. Delivery arrives off the main thread; each payload is read here
/// and handed to Telemetry on the main actor.
final class DiagnosticSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let found = payloads.flatMap(Diagnostic.all(in:))
        guard !found.isEmpty else { return }
        Task { @MainActor in Telemetry.shared.report(found) }
    }
}
