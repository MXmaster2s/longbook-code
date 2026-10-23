#if os(macOS)
import AppKit
import SwiftUI

/// Every sheet opens in the middle of its window rather than dropping from the top edge.
/// AppKit asks the window's delegate where a sheet goes; this proxy answers that one
/// question and passes every other to SwiftUI's own delegate.
final class SheetCentering: NSObject, NSWindowDelegate {
    /// Held strongly: the window holds its delegate weakly, and SwiftUI's must outlive the swap.
    private var original: NSWindowDelegate?
    private static var proxies: [ObjectIdentifier: SheetCentering] = [:]

    @MainActor
    static func install(on window: NSWindow) {
        let id = ObjectIdentifier(window)
        if let proxy = proxies[id], window.delegate === proxy { return }
        let proxy = SheetCentering()
        proxy.original = window.delegate
        proxies[id] = proxy
        window.delegate = proxy
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
