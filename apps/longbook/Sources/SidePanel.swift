import DesignSystem
import SwiftUI

/// The face of a panel's round bar button: the symbol on the chrome colour, in a hairline.
struct PanelCircleFace: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(LBColor.textSecondary.color)
            .frame(width: 36, height: 36)
            .background(LBColor.chrome.color, in: Circle())
            .overlay(Circle().strokeBorder(LBColor.hairline.color, lineWidth: 1))
            .contentShape(Circle())
    }
}

extension View {
    /// Keeps `inside` true while keyboard focus is within this view. A phone has no panel.
    @ViewBuilder
    func lbFocusWithin(_ inside: Binding<Bool>) -> some View {
        #if os(macOS)
        background(FocusWithin(inside: inside))
        #else
        self
        #endif
    }

    /// Stops a row short of the side panel while one is open, so it spans the list's column
    /// only. A phone has no panel.
    @ViewBuilder
    func lbBesidePanel(_ open: Bool) -> some View {
        #if os(macOS)
        modifier(BesidePanel(open: open))
        #else
        self
        #endif
    }

    /// An Edit form standing in a side panel says what it holds, so the window can ask before
    /// something replaces it. A sheet or a phone has no panel.
    @ViewBuilder
    func lbPanelForm(active: Bool, dirty: Bool, close: @escaping () -> Void) -> some View {
        #if os(macOS)
        if active {
            modifier(PanelFormReport(dirty: dirty, close: close))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if os(macOS)
/// The Mac's one side panel, for every Preview and Proposals' detail, in the manner
/// of Apple's inspector: under the screen's title and search rows, one width whatever it
/// holds, sliding in from the right. Drawn by hand because the system inspector stays folded
/// inside this app's own sidebar split.
enum SidePanel {
    static let width: CGFloat = 360
    /// How far down a screen's content a panel starts: a list screen's title, definition and
    /// search rows are this tall.
    static let line: CGFloat = 150
}

/// A row above the panel's column that ends where the panel begins.
private struct BesidePanel: ViewModifier {
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.trailing, open ? SidePanel.width + 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: open)
    }
}

/// A panel's column: the hairline beside it, then what it holds, to the window's foot.
private struct SidePanelColumn<Pane: View>: View {
    @ViewBuilder let pane: () -> Pane

    var body: some View {
        HStack(spacing: 0) {
            Divider()
            pane()
                .frame(width: SidePanel.width)
                .frame(maxHeight: .infinity)
                .background(LBColor.canvas.color)
        }
    }
}

/// A screen's panel, holding what the screen chose.
private struct SidePanelHost<Pane: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let pane: () -> Pane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var token = UUID()

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isPresented {
                SidePanelColumn(pane: pane)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isPresented)
        .onChange(of: isPresented, initial: true) { _, open in PanelForm.shared.report(token, open: open) }
        .onDisappear { PanelForm.shared.report(token, open: false) }
    }
}

extension View {
    func lbSidePanel<Pane: View>(isPresented: Binding<Bool>, @ViewBuilder pane: @escaping () -> Pane) -> some View {
        modifier(SidePanelHost(isPresented: isPresented, pane: pane))
    }
}

/// Close, at a panel's top left.
struct PanelCloseButton: View {
    var help = "Close (Esc)"
    /// The button's fixed name in usage counts.
    let measure: StaticString
    let action: () -> Void

    var body: some View {
        Button { Measure.used(measure); action() } label: {
            PanelCircleFace(symbol: "xmark")
        }
        .lbButtonStyle(.capsule)
        .help(help)
        .accessibilityLabel("Close")
        .lbShortcut(.closePanel)
    }
}

/// A panel as the window needs to know of it: that one is open, and whether a form in it holds
/// changes. A menu or a sidebar row that would replace such a form asks through `ask`, and the
/// shell puts the question.
@MainActor
final class PanelForm: ObservableObject {
    static let shared = PanelForm()
    /// The screen whose panel is open. A push brings the next screen's panel before the last
    /// one's goes, so only the one that opened it can say it has closed.
    @Published fileprivate var opener: UUID?
    /// The question is up. Its own flag, for a dismissal may clear this before a button runs.
    @Published fileprivate var asking = false
    /// What to do once the form's changes may be lost.
    private var waiting: (() -> Void)?
    fileprivate var dirty = false
    /// Puts back what the question was asked about, when the form stays.
    var onKeep: (() -> Void)?
    /// Takes the open form away, typed words and all.
    fileprivate var close: (() -> Void)?

    private init() {}

    fileprivate func report(_ screen: UUID, open: Bool) {
        if open { opener = screen } else if opener == screen { opener = nil }
    }

    /// Runs `then` now, or once the question has been answered: Discard loses what the form holds.
    func ask(then: @escaping () -> Void) {
        if dirty {
            waiting = then
            asking = true
        } else {
            then()
        }
    }

    /// The form goes first, so nothing behind a pushed screen comes back holding what was typed;
    /// what replaces it follows on the next turn, so even the same card opens fresh.
    func discard() {
        let then = waiting
        waiting = nil
        onKeep = nil
        asking = false
        dirty = false
        close?()
        DispatchQueue.main.async { then?() }
    }

    fileprivate func keep() {
        waiting = nil
        asking = false
        onKeep?()
        onKeep = nil
    }
}

/// What the window owes a panel: what would replace a form holding changes asks here first.
struct PanelFormCorner: ViewModifier {
    @ObservedObject private var form = PanelForm.shared

    func body(content: Content) -> some View {
        content
            .measured("root_panel_form_discard", .alert, when: form.asking)
            .alert("Discard your changes?", isPresented: Binding(get: { form.asking }, set: { if !$0 { form.asking = false } })) {
                Button("Discard", role: .destructive) { Measure.used("discard"); form.discard() }
                Button("Keep Editing", role: .cancel) { Measure.used("keep_editing"); form.keep() }
            }
    }
}

private struct PanelFormReport: ViewModifier {
    let dirty: Bool
    let close: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: dirty, initial: true) { _, now in
                PanelForm.shared.dirty = now
                PanelForm.shared.close = close
            }
            .onDisappear {
                PanelForm.shared.dirty = false
                PanelForm.shared.close = nil
            }
    }
}

/// Whether keyboard focus is inside a view: a panel's form saves on Return only then, so Return
/// in the list's search field beside it never reaches the form.
struct FocusWithin: NSViewRepresentable {
    @Binding var inside: Bool

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.report = { inside = $0 }
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.report = { inside = $0 }
    }

    final class Probe: NSView {
        var report: (Bool) -> Void = { _ in }
        private var watching: NSKeyValueObservation?
        private var reported: Bool?

        // It only watches: a click goes to whatever is under it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            watching = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.read() }
            }
        }

        private func read() {
            let now = holdsFocus
            guard now != reported else { return }
            reported = now
            report(now)
        }

        /// The window's own view answers when nothing is focused, and is wider than any form.
        private var holdsFocus: Bool {
            guard let focused = window?.firstResponder as? NSView else { return false }
            let area = convert(bounds, to: nil), frame = focused.convert(focused.bounds, to: nil)
            return !(frame.width > area.width) && area.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }
}
#endif
