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

/// A card in a section's hue. Its content inherits the section tint, so a caller writes
/// text without restating the colour and cannot accidentally pair a tint with a fill
/// that was never measured against it.
public struct LBSectionCard<Content: View>: View {
    private let section: LBSection
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(
        _ section: LBSection,
        radius: CGFloat = LBRadius.xl,
        padding: CGFloat = LBSpacing.s6,
        @ViewBuilder content: () -> Content
    ) {
        self.section = section
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .foregroundStyle(section.tint.color)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                section.fill.color,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}
