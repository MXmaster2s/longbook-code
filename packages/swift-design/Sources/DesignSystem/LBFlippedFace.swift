import SwiftUI

/// A card showing its back wears the opposite appearance — light where the screen is
/// dark, dark where it is light. The turn is then legible at a glance, without a label
/// saying so, and every token underneath resolves to its own palette rather than being
/// tinted by hand.
private struct LBFlippedFace: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let flipped: Bool

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, flipped ? opposite : scheme)
    }

    private var opposite: ColorScheme {
        scheme == .dark ? .light : .dark
    }
}

extension View {
    /// Wear the opposite appearance while `flipped` — the shared behaviour of every card
    /// in this system that turns over.
    public func lbFlippedFace(_ flipped: Bool) -> some View {
        modifier(LBFlippedFace(flipped: flipped))
    }
}
