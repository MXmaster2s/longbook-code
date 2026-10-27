import SwiftUI
#if os(macOS)
import AppKit
#endif

// The Mac's control states, after Apple's guidelines: hover on what answers a click, a
// pressed shade, the focus ring for the keyboard only, 40% when disabled, grey selection
// behind the window. The phone keeps its plain buttons.

/// Where a state wash is drawn.
public enum LBWashShape: Sendable, Equatable {
    /// Over whatever the label paints: a card's own fill, a chip's own capsule.
    case label
    /// A rounded rectangle over the label's frame, for rows and icons with no fill at rest.
    case rounded(CGFloat)
    /// A capsule over the label's frame.
    case capsule
}

#if os(macOS)
/// Whether the last thing the person did was keyboard navigation or a pointer click. Focus
/// rings follow it, so a click never leaves a ring behind and Tab always shows one.
@MainActor
@Observable
public final class LBInputModality {
    public static let shared = LBInputModality()

    public private(set) var keyboard = false
    @ObservationIgnored private var monitor: Any?

    /// Tab and the arrow keys move focus; typing into a field does not change what shows.
    private static let navigationKeys: Set<UInt16> = [48, 123, 124, 125, 126]

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            let isKey = event.type == .keyDown
            if isKey && !Self.navigationKeys.contains(event.keyCode) { return event }
            MainActor.assumeIsolated {
                let shared = LBInputModality.shared
                if shared.keyboard != isKey { shared.keyboard = isKey }
            }
            return event
        }
    }
}

/// The hover and pressed layers over a control. Hover fades in 0.12 s, or at once under
/// Reduce Motion; the press lands at once.
private struct LBStateWashLayer: ViewModifier {
    let shape: LBWashShape
    let hovered: Bool
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        switch shape {
        case .label:
            content
                .overlay { layers.blendMode(.sourceAtop).allowsHitTesting(false) }
                .compositingGroup()
        case .rounded(let radius):
            content.overlay { layers.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)).allowsHitTesting(false) }
        case .capsule:
            content.overlay { layers.clipShape(Capsule()).allowsHitTesting(false) }
        }
    }

    private var layers: some View {
        ZStack {
            LBColor.stateHover.color
                .opacity(hovered && !pressed ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered && !pressed)
            LBColor.statePressed.color
                .opacity(pressed ? 1 : 0)
                .animation(nil, value: pressed)
        }
    }
}

/// The one button style the Mac's own controls share: the hover wash, the pressed shade
/// read from `isPressed`, and 40% when disabled. Focus is the system's ring.
public struct LBStateButtonStyle: ButtonStyle {
    let shape: LBWashShape
    let hovers: Bool
    let presses: Bool

    public init(_ shape: LBWashShape = .label, hovers: Bool = true, presses: Bool = true) {
        self.shape = shape
        self.hovers = hovers
        self.presses = presses
    }

    public func makeBody(configuration: Configuration) -> some View {
        LBStateButtonFace(configuration: configuration, shape: shape, hovers: hovers, presses: presses)
    }
}

private struct LBStateButtonFace: View {
    let configuration: ButtonStyleConfiguration
    let shape: LBWashShape
    let hovers: Bool
    let presses: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .modifier(LBStateWashLayer(
                shape: shape,
                hovered: hovers && hovering && isEnabled,
                pressed: presses && configuration.isPressed && isEnabled
            ))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}

/// A hover wash for something clickable that is not a Button: a card chosen by a click.
private struct LBHoverWash: ViewModifier {
    let shape: LBWashShape
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .modifier(LBStateWashLayer(shape: shape, hovered: hovering && isEnabled, pressed: false))
            .onHover { hovering = $0 }
    }
}

/// Reaches a card or row by Tab and Full Keyboard Access, rings it in the accent while the
/// keyboard is driving, and lets Return or Space act on it.
private struct LBKeyboardFocus: ViewModifier {
    let radius: CGFloat
    let activate: (() -> Void)?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .overlay {
                if focused && LBInputModality.shared.keyboard {
                    RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
            .onKeyPress(keys: [.return, .space]) { _ in
                guard let activate else { return .ignored }
                activate()
                return .handled
            }
    }
}

/// The system focus effects, on while the keyboard drives and off after a click.
private struct LBKeyboardFocusEffects: ViewModifier {
    func body(content: Content) -> some View {
        content.focusEffectDisabled(!LBInputModality.shared.keyboard)
    }
}

/// The pointing hand over a link, the one place the Mac's pointer changes.
private struct LBLinkPointer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content.onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

/// The selection fill: the brand tint while the window is in front, the inactive grey
/// over the resting surface when it is not.
private struct LBSelectionFill<S: InsettableShape>: ViewModifier {
    let selected: Bool
    let shape: S
    let resting: Color
    let tint: Double
    @Environment(\.controlActiveState) private var activeState

    func body(content: Content) -> some View {
        content.background {
            if selected && activeState == .key {
                shape.fill(LBColor.brand.color.opacity(tint))
            } else {
                ZStack {
                    shape.fill(resting)
                    if selected { shape.fill(LBColor.stateSelectionInactive.color) }
                }
            }
        }
    }
}
#endif

extension View {
    /// The Mac's shared button style (hover, pressed, disabled); the phone keeps `.plain`.
    /// Segmented, checkbox and radio faces pass `hovers: false`; a click that only selects
    /// passes `presses: false`.
    @ViewBuilder
    public func lbButtonStyle(_ shape: LBWashShape = .label, hovers: Bool = true, presses: Bool = true) -> some View {
        #if os(macOS)
        buttonStyle(LBStateButtonStyle(shape, hovers: hovers, presses: presses))
        #else
        buttonStyle(.plain)
        #endif
    }

    /// The same states for a button in a list row, which keeps `.borderless` on the phone so
    /// the row does not take its tap.
    @ViewBuilder
    public func lbBorderlessButtonStyle(_ shape: LBWashShape = .label) -> some View {
        #if os(macOS)
        buttonStyle(LBStateButtonStyle(shape))
        #else
        buttonStyle(.borderless)
        #endif
    }

    /// A dimmed look for a control that waits, on the phone only: on the Mac the shared
    /// button style already takes a disabled control to 40%.
    @ViewBuilder
    public func lbPhoneDimmed(_ dimmed: Bool, to opacity: Double = 0.5) -> some View {
        #if os(macOS)
        self
        #else
        self.opacity(dimmed ? opacity : 1)
        #endif
    }

    /// A hover wash on the Mac for a clickable view that is not a Button.
    @ViewBuilder
    public func lbHoverWash(_ shape: LBWashShape = .label) -> some View {
        #if os(macOS)
        modifier(LBHoverWash(shape: shape))
        #else
        self
        #endif
    }

    /// Makes a card or row that acts reachable from the keyboard on the Mac, with the accent
    /// ring while the keyboard drives. Return and Space run `activate` when one is given.
    @ViewBuilder
    public func lbKeyboardFocusable(radius: CGFloat, activate: (() -> Void)? = nil) -> some View {
        #if os(macOS)
        modifier(LBKeyboardFocus(radius: radius, activate: activate))
        #else
        self
        #endif
    }

    /// System focus rings for keyboard navigation only: shown after Tab, hidden after a click.
    @ViewBuilder
    public func lbKeyboardFocusEffects() -> some View {
        #if os(macOS)
        modifier(LBKeyboardFocusEffects())
        #else
        self
        #endif
    }

    /// The pointing hand over a link on the Mac. Every other control keeps the arrow.
    @ViewBuilder
    public func lbLinkPointer() -> some View {
        #if os(macOS)
        modifier(LBLinkPointer())
        #else
        self
        #endif
    }

    /// A selection behind the view on the Mac: brand while the window is key, the inactive
    /// grey when not. `resting` is the surface it sits on when not selected; `tint` is the
    /// brand's strength.
    @ViewBuilder
    public func lbSelectionFill<S: InsettableShape>(
        _ selected: Bool, in shape: S, resting: Color = .clear, tint: Double = 0.16
    ) -> some View {
        #if os(macOS)
        modifier(LBSelectionFill(selected: selected, shape: shape, resting: resting, tint: tint))
        #else
        background(selected ? LBColor.brand.color.opacity(tint) : resting, in: shape)
        #endif
    }
}
