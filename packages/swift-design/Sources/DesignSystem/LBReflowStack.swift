import SwiftUI

/// A row that becomes a column at the accessibility text sizes, as Apple's own screens do.
/// Side by side, the larger words would be cut short or broken mid-word.
public struct LBReflowStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}
