import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The Mac's control states, after Apple's Human Interface Guidelines: a hover wash only on
/// what answers a click, a pressed look at once, the accent ring for the keyboard only,
/// disabled at 40%, and a selection that greys when its window is not in front. Each theme
/// draws its own values; the iPhone keeps the system's plain press.
public enum LBState {
    /// Under the pointer: white 7% on dark, black 5% on light. Fades in over 0.12 s.
    public static let hover = LBStateWash(dark: (white: 1, alpha: 0.07), light: (white: 0, alpha: 0.05))
    /// Held down: black 25% on dark, black 12% on light. Shown at once, never faded.
    public static let pressed = LBStateWash(dark: (white: 0, alpha: 0.25), light: (white: 0, alpha: 0.12))
    /// A selection whose list or window is not focused: white 12% on dark, black 8% on light.
    public static let selectionInactive = LBStateWash(dark: (white: 1, alpha: 0.12), light: (white: 0, alpha: 0.08))
    /// A selection in the window in front: the brand at the tint the sidebar already uses.
    public static let selectionActive = LBColor.brand.color.opacity(0.16)
    public static let disabledOpacity: Double = 0.4
    public static let focusRingWidth: CGFloat = 3
}

/// A translucent state colour with its own value per appearance.
public struct LBStateWash: Sendable {
    public let dark: (white: Double, alpha: Double)
    public let light: (white: Double, alpha: Double)

    public func value(in scheme: ColorScheme) -> (white: Double, alpha: Double) {
        scheme == .dark ? dark : light
    }

    public func color(in scheme: ColorScheme) -> Color {
        let v = value(in: scheme)
        return Color(white: v.white, opacity: v.alpha)
    }
}

/// How a control shows its hover and pressed washes.
public enum LBControlSurface {
    /// The label paints its own surface (a card, a pill, a filled button): the washes are
    /// laid over exactly the pixels it draws, so they hug whatever shape it has.
    case own
    /// The label is transparent at rest (a sidebar row, a header cell): the washes are a
    /// fill in this shape behind it.
    case fill
}

/// The design system's button look on the Mac. Use it through `lbButtonStyle`, which keeps
/// the iPhone on the plain style it has always had.
public struct LBControlStyle: ButtonStyle {
    let surface: LBControlSurface
    let shape: AnyShape
    let hovers: Bool

    public init(surface: LBControlSurface = .own, shape: some Shape = LBControlStyle.rounded, hovers: Bool = true) {
        self.surface = surface
        self.shape = AnyShape(shape)
        self.hovers = hovers
    }

    public static let rounded = RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)

    public func makeBody(configuration: Configuration) -> some View {
        LBControlBody(configuration: configuration, surface: surface, shape: shape, hovers: hovers)
    }
}

private struct LBControlBody: View {
    let configuration: ButtonStyleConfiguration
    let surface: LBControlSurface
    let shape: AnyShape
    let hovers: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    // Hover stays lit under a press so only the hover fades; the press lands at once.
    private var hovered: Bool { hovers && hovering && isEnabled }
    private var pressed: Bool { configuration.isPressed && isEnabled }

    var body: some View {
        washed
            .overlay { focusRing }
            .opacity(isEnabled ? 1 : LBState.disabledOpacity)
            .onHover { hovering = $0 }
            .animation(LBMotion.resolve(reduceMotion: reduceMotion), value: hovered)
    }

    @ViewBuilder
    private var washed: some View {
        switch surface {
        case .own:
            // Multiplying by (1 - alpha) is exactly a black wash at that alpha; on the dark
            // surfaces a white wash is close to a lift of the alpha. Both only touch drawn pixels.
            let hover = LBState.hover.value(in: scheme)
            let press = LBState.pressed.value(in: scheme)
            configuration.label
                .brightness(hovered && hover.white == 1 ? hover.alpha : 0)
                .colorMultiply(Color(white: pressed ? 1 - press.alpha
                                     : hovered && hover.white == 0 ? 1 - hover.alpha : 1))
        case .fill:
            configuration.label
                .background {
                    shape.fill(pressed ? LBState.pressed.color(in: scheme)
                               : hovered ? LBState.hover.color(in: scheme) : .clear)
                }
        }
    }

    /// The accent ring, 3 pt and hugging the shape, only while keyboard navigation is on:
    /// with it off, clicking never draws one.
    @ViewBuilder
    private var focusRing: some View {
        if isFocused && LBKeyboard.navigates {
            shape
                .stroke(LBColor.brand.color, lineWidth: LBState.focusRingWidth)
                .padding(-LBState.focusRingWidth / 2)
                .allowsHitTesting(false)
        }
    }
}

enum LBKeyboard {
    /// Whether keyboard navigation is on. Without it buttons take no focus, and a focused
    /// list or scroller above them would otherwise light every ring inside it.
    @MainActor static var navigates: Bool {
        #if os(macOS)
        NSApplication.shared.isFullKeyboardAccessEnabled
        #else
        false
        #endif
    }
}

public extension View {
    /// The button look every plain control takes: on the Mac, hover, pressed, focus and
    /// disabled states from `LBControlStyle`; on the iPhone, the system's plain style.
    @ViewBuilder
    func lbButtonStyle(
        _ surface: LBControlSurface = .own,
        shape: some Shape = LBControlStyle.rounded,
        hovers: Bool = true
    ) -> some View {
        #if os(macOS)
        buttonStyle(LBControlStyle(surface: surface, shape: shape, hovers: hovers))
            // The system ring is drawn by the style instead, in the brand and the control's shape.
            .focusEffectDisabled()
        #else
        buttonStyle(.plain)
        #endif
    }

    /// A selected row's fill: the brand tint while its window is in front, grey when not.
    func lbSelectionFill(_ selected: Bool, in shape: some Shape = LBControlStyle.rounded) -> some View {
        modifier(LBSelectionFill(selected: selected, shape: AnyShape(shape)))
    }
}

private struct LBSelectionFill: ViewModifier {
    let selected: Bool
    let shape: AnyShape
    @Environment(\.colorScheme) private var scheme
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    private var inFront: Bool { activeState != .inactive }
    #else
    private var inFront: Bool { true }
    #endif

    func body(content: Content) -> some View {
        content.background {
            if selected {
                shape.fill(inFront ? LBState.selectionActive : LBState.selectionInactive.color(in: scheme))
            }
        }
    }
}
