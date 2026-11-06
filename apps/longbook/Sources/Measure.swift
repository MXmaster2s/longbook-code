import SwiftUI

/// Usage counts for controls and popups, by names written here in the code. StaticString keeps
/// them literal: a label read at run time could carry the owner's own words. Every name matches
/// `^[a-z][a-z0-9_]{1,40}$`; `npm run telemetry:names` checks.
@MainActor
enum Measure {
    /// A button, menu item, swipe action or shortcut was used.
    static func used(_ control: StaticString, _ kind: Telemetry.ControlKind = .button) {
        Telemetry.shared.control(control.description, kind: kind)
    }

    /// A switch was turned on or off by the owner.
    static func toggled(_ control: StaticString, on: Bool) {
        Telemetry.shared.control(control.description, kind: .toggle, on: on)
    }
}

extension Binding where Value == Bool {
    /// The same switch, counted when the owner turns it; changes the code makes elsewhere are not.
    func measured(_ control: StaticString) -> Binding<Bool> {
        Binding(
            get: { wrappedValue },
            set: { new, transaction in
                if new != wrappedValue {
                    MainActor.assumeIsolated { Measure.toggled(control, on: new) }
                }
                self.transaction(transaction).wrappedValue = new
            }
        )
    }
}

extension View {
    /// A popup's appearing and going, counted from the view that presents it: `shown` is the
    /// condition its `.sheet`, `.alert` or the like is presented on.
    func measured(_ name: StaticString, _ kind: Telemetry.ScreenKind, when shown: Bool) -> some View {
        modifier(MeasuredPresentation(name: name.description, kind: kind, shown: shown))
    }
}

private struct MeasuredPresentation: ViewModifier {
    let name: String
    let kind: Telemetry.ScreenKind
    let shown: Bool

    func body(content: Content) -> some View {
        content.onChange(of: shown, initial: true) { _, now in
            if now {
                Telemetry.shared.screen(name, kind: kind)
            } else {
                Telemetry.shared.dismissed(name)
            }
        }
    }
}
