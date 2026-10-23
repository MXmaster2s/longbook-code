import SwiftUI

/// The "to fill in" edge: a dashed brand hairline on a rounded corner, drawn once here for
/// every card and chip that waits on the reader — a placeholder, an empty rail card, an
/// occurrence not yet chosen.
public struct LBDashedOutline: View {
    /// The edge is a control boundary — a pending chip's only one — so it wears the brand
    /// token whole. Dimmed, the dash falls under the 3:1 floor on either canvas; the
    /// contrast tests hold this value.
    public static let opacity: Double = 1

    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(LBColor.brand.color.opacity(Self.opacity), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
}

extension View {
    /// Lay the dashed brand edge over this view.
    public func lbDashedOutline(cornerRadius: CGFloat) -> some View {
        overlay(LBDashedOutline(cornerRadius: cornerRadius))
    }
}
