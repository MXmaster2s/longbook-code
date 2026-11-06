#if os(macOS)
import AppKit
import SwiftUI

/// Every sheet opens in the middle of its window rather than dropping from the top edge.
/// AppKit asks the window's delegate where a sheet goes; this proxy answers that one
/// question and passes every other to SwiftUI's own delegate.
final class SheetCentering: NSObject, NSWindowDelegate, @unchecked Sendable {
    /// Held strongly: the window holds its delegate weakly, and SwiftUI's must outlive the swap.
    private var original: NSWindowDelegate?
    private static var proxies: [ObjectIdentifier: SheetCentering] = [:]

    @MainActor
    static func install(on window: NSWindow) {
        let id = ObjectIdentifier(window)
        if let proxy = proxies[id] {
            proxy.reclaim(window)
            return
        }
        let proxy = SheetCentering()
        proxy.original = window.delegate
        proxies[id] = proxy
        window.delegate = proxy
        // SwiftUI can hand the window a new delegate of its own later, which dropped the
        // centring (Sign in with Apple opened at the top). Each update takes it back.
        NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { proxy.reclaim(window) }
        }
        watchSignInPanels()
    }

    /// Back in front of a delegate SwiftUI set since, keeping that one as the one to answer to.
    @MainActor
    private func reclaim(_ window: NSWindow) {
        guard window.delegate !== self else { return }
        if !(window.delegate is SheetCentering) { original = window.delegate }
        window.delegate = self
    }

    private static var watching = false

    /// Apple's sign-in can come as its own panel rather than a sheet; it is centred over the
    /// window it was asked from. Only Apple's authorisation panels are moved.
    @MainActor
    private static func watchSignInPanels() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let panel = note.object as? NSWindow, panel.sheetParent == nil,
                  String(describing: type(of: panel)).contains("Authoriz") || String(describing: type(of: panel)).hasPrefix("AK")
            else { return }
            MainActor.assumeIsolated {
                guard let host = NSApp.windows.first(where: { proxies[ObjectIdentifier($0)] != nil && $0.isVisible && $0 !== panel }) else { return }
                let frame = host.frame
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
            }
        }
    }

    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        // The sheet's top edge goes where the returned rect starts, in window coordinates.
        let area = window.contentLayoutRect
        let top = area.midY + sheet.frame.height / 2
        return NSRect(x: rect.origin.x, y: min(top, rect.origin.y), width: rect.width, height: rect.height)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original?.responds(to: aSelector) == true ? original : nil
    }
}

/// Puts the centring on the window the view lands in.
struct CentersSheets: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SheetCentering.install(on: window) }
        }
    }
}
#endif
