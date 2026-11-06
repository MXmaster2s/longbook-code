import SwiftUI

/// A neutral card: the raised surface everything ordinary sits on.
public struct LBCard<Content: View>: View {
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(
        radius: CGFloat = LBRadius.md,
        padding: CGFloat = LBSpacing.s4,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LBColor.card.color,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}
