import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// Listens, from inside a sheet, for a click on the window behind it. AppKit refuses that
/// click with a beep; here it closes the sheet, as a click outside a popover closes the
/// popover. Only the topmost sheet answers, so one with its own sheet or alert up stays.
private struct LBOutsideClickCatcher: NSViewRepresentable {
    let close: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView(close: close) }

    func updateNSView(_ view: CatcherView, context: Context) { view.close = close }

    final class CatcherView: NSView {
        var close: () -> Void
        private var monitor: Any?

        init(close: @escaping () -> Void) {
            self.close = close
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        deinit { stop() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let mine = self.window, mine.attachedSheet == nil,
                      let clicked = event.window, clicked !== mine
                else { return event }
                var parent = mine.sheetParent
                while let candidate = parent {
                    if candidate === clicked {
                        self.close()
                        return nil
                    }
                    parent = candidate.sheetParent
                }
                return event
            }
        }

        private func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif

public extension View {
    /// Inside a sheet: a click on the window behind it closes it. iOS sheets already
    /// answer a touch outside, so this is inert there.
    func lbClosesOnOutsideClick(_ close: @escaping () -> Void) -> some View {
        #if os(macOS)
        background(LBOutsideClickCatcher(close: close).frame(width: 0, height: 0))
        #else
        self
        #endif
    }
}
