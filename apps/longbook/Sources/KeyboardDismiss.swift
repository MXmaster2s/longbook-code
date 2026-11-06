import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// A tap anywhere that is not a text field puts the keyboard away, everywhere in the app.
/// The recogniser sits on the window, so a sheet — which shares the window — gets it too;
/// a SwiftUI gesture on the root never reaches a sheet's content.
private final class WindowKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = WindowKeyboardDismisser()
    private let windows = NSHashTable<UIWindow>.weakObjects()

    func install(in window: UIWindow) {
        guard !windows.contains(window) else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        windows.add(window)
    }

    @objc private func tapped() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// A tap inside a field is the field's: it moves the cursor, never the keyboard.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextInput { return false }
            view = current.superview
        }
        return true
    }
}

/// An empty view whose only job is to find the window it lands in and arm it.
private struct KeyboardDismissInstaller: UIViewRepresentable {
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { WindowKeyboardDismisser.shared.install(in: window) }
        }
    }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        return probe
    }

    func updateUIView(_ uiView: Probe, context: Context) {}
}
#endif

extension View {
    /// Arms the window this view lands in, so a tap outside any field closes the keyboard
    /// — in this view, in every sheet it presents, and in everything else on that window.
    func lbDismissesKeyboardOnTap() -> some View {
        #if os(iOS)
        background(KeyboardDismissInstaller().frame(width: 0, height: 0))
        #else
        self
        #endif
    }
}
