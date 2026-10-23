import SwiftUI

/// A sheet that stops three quarters of the way up, so the screen it came from stays
/// visible behind it. What opens from a chip is a detour, not another place.
private struct LBThreeQuarterSheet: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .presentationDetents([.fraction(0.75), .large])
            .presentationDragIndicator(.visible)
        #else
        content
        #endif
    }
}

/// The screen behind such a sheet, softened while it is up.
private struct LBSoftened: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active && !reduceTransparency ? 6 : 0)
            .animation(.easeOut(duration: 0.2), value: active)
    }
}

/// A sheet only as tall as the card it holds — it sits over the screen it came from
/// rather than replacing it.
private struct LBMonthSheet: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        #else
        content
        #endif
    }
}

/// A sheet the height of a month of days.
private struct LBDaySheet: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .presentationDetents([.height(430), .large])
            .presentationDragIndicator(.visible)
        #else
        content
        #endif
    }
}

extension View {
    /// Present this sheet at the height of a day grid.
    public func lbDaySheet() -> some View {
        modifier(LBDaySheet())
    }

    /// Present this sheet at the height of a month grid.
    public func lbMonthSheet() -> some View {
        modifier(LBMonthSheet())
    }

    /// Present this sheet over three quarters of the screen.
    public func lbThreeQuarterSheet() -> some View {
        modifier(LBThreeQuarterSheet())
    }

    /// Soften this view while something is presented over it.
    public func lbSoftenedWhile(_ active: Bool) -> some View {
        modifier(LBSoftened(active: active))
    }
}
