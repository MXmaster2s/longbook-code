import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A pointer's hold on a horizontal scroll view. AppKit scrolls under a wheel or trackpad,
/// never under a pressed pointer; this hands the pointer the clip view's offset, frame by
/// frame, and lets go with the drag's momentum. A finger does all this, so on iOS the
/// type is inert.
@MainActor
@Observable
public final class LBPointerScroll {
    /// How far along its overflow the strip sits: 0 at the start, 1 at the end, and 0
    /// while everything fits. Rounded to a half-percent so a scroll does not invalidate
    /// its readers on every frame.
    public private(set) var fraction: Double = 0
    public private(set) var atStart = true
    public private(set) var atEnd = true
    /// Whether a scroll view is bound and has more than fits.
    public private(set) var overflows = false
    public private(set) var dragging = false

    public init() {}

    #if os(macOS)
    @ObservationIgnored private weak var scrollView: NSScrollView?
    @ObservationIgnored private var anchor: CGFloat?
    @ObservationIgnored private var observer: NSObjectProtocol?

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    fileprivate func bind(_ view: NSScrollView) {
        guard scrollView !== view else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        scrollView = view
        let clip = view.contentView
        clip.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        read()
    }

    private var overflow: CGFloat {
        guard let scrollView else { return 0 }
        return max(0, (scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width)
    }

    private func read() {
        guard let scrollView else { return }
        let room = overflow
        let x = scrollView.contentView.bounds.origin.x
        let next = room > 0 ? ((min(max(x / room, 0), 1) * 200).rounded() / 200) : 0
        if next != fraction { fraction = next }
        if (room > 0) != overflows { overflows = room > 0 }
        let start = x <= 0.5
        let end = x >= room - 0.5
        if start != atStart { atStart = start }
        if end != atEnd { atEnd = end }
    }

    private func scroll(to x: CGFloat, animated: Bool) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        let target = NSPoint(x: min(max(x, 0), overflow), y: clip.bounds.origin.y)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clip.animator().setBoundsOrigin(target)
                scrollView.reflectScrolledClipView(clip)
            }
        } else {
            clip.scroll(to: target)
            scrollView.reflectScrolledClipView(clip)
        }
    }
    #endif

    /// The pointer has moved `translation` points since it pressed: the strip follows,
    /// pinned at its ends rather than stretched past them. The hold is taken where the
    /// pointer is when the first frame arrives, so the strip never jumps to meet it.
    public func drag(_ translation: CGFloat) {
        #if os(macOS)
        guard let scrollView else { return }
        if anchor == nil {
            anchor = scrollView.contentView.bounds.origin.x + translation
            dragging = true
            NSCursor.closedHand.set()
        }
        guard let anchor else { return }
        scroll(to: anchor - translation, animated: false)
        #endif
    }

    /// The pointer let go. `predicted` is where the drag was heading; the distance beyond
    /// where it stopped is the momentum, spent over a short ease-out.
    public func end(translation: CGFloat, predicted: CGFloat) {
        #if os(macOS)
        guard let anchor else { return }
        self.anchor = nil
        dragging = false
        NSCursor.openHand.set()
        let extra = predicted - translation
        if abs(extra) > 2 { scroll(to: anchor - translation - extra, animated: true) }
        #endif
    }

    /// The cursor says the strip can be held — an open hand over it, closed while it is —
    /// and says nothing over a strip with nowhere to go.
    public func hover(_ inside: Bool) {
        #if os(macOS)
        guard scrollView != nil, overflow > 0 else { return }
        if inside { (dragging ? NSCursor.closedHand : NSCursor.openHand).set() }
        else if !dragging { NSCursor.arrow.set() }
        #endif
    }
}

#if os(macOS)
/// Sits inside the scroll view's content and walks up to the scroll view that holds it.
/// Zero-sized and untouchable, so it takes no room and no clicks.
private struct LBPointerScrollAnchor: NSViewRepresentable {
    let handle: LBPointerScroll

    func makeNSView(context: Context) -> AnchorView { AnchorView(handle: handle) }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.handle = handle
        view.bind()
    }

    final class AnchorView: NSView {
        var handle: LBPointerScroll

        init(handle: LBPointerScroll) {
            self.handle = handle
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            bind()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func bind() {
            var view = superview
            while let current = view {
                if let scrollView = current as? NSScrollView {
                    handle.bind(scrollView)
                    return
                }
                view = current.superview
            }
        }
    }
}
#endif

public extension View {
    /// On a horizontal scroll view's content: binds the handle to the scroll view around it.
    func lbPointerScrollTarget(_ handle: LBPointerScroll) -> some View {
        #if os(macOS)
        background(LBPointerScrollAnchor(handle: handle).frame(width: 0, height: 0))
        #else
        self
        #endif
    }

    /// On the scroll view itself: the pointer drags it, with a hand for a cursor. The hold
    /// outranks the buttons on the strip, so a drag that ends over one is never a click.
    func lbPointerDrag(_ handle: LBPointerScroll) -> some View {
        #if os(macOS)
        highPriorityGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { handle.drag($0.translation.width) }
                .onEnded { handle.end(translation: $0.translation.width, predicted: $0.predictedEndTranslation.width) }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active: handle.hover(true)
            case .ended: handle.hover(false)
            }
        }
        #else
        self
        #endif
    }
}
