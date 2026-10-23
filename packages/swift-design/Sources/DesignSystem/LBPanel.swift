import SwiftUI

/// A dashboard panel: card surface, hairline edge, and an optional header row pairing a
/// sentence-case section name with a quiet trailing note. A mark may sit beside the eyebrow — a
/// small control that belongs to the panel's name, such as the door to its insight.
public struct LBPanel<Content: View, Accessory: View, Mark: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let eyebrow: String?
    private let note: String?
    private let padding: CGFloat
    private let mark: Mark
    private let accessory: Accessory
    private let content: Content

    public init(
        eyebrow: String? = nil,
        note: String? = nil,
        padding: CGFloat = LBSpacing.s4,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView, Mark == EmptyView {
        self.eyebrow = eyebrow
        self.note = note
        self.padding = padding
        self.mark = EmptyView()
        self.accessory = EmptyView()
        self.content = content()
    }

    /// The note slot as a control instead of a word — a panel whose scope the reader can
    /// change says so where it already says what it is showing.
    public init(
        eyebrow: String? = nil,
        padding: CGFloat = LBSpacing.s4,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) where Mark == EmptyView {
        self.eyebrow = eyebrow
        self.note = nil
        self.padding = padding
        self.mark = EmptyView()
        self.accessory = accessory()
        self.content = content()
    }

    public init(
        eyebrow: String? = nil,
        note: String? = nil,
        padding: CGFloat = LBSpacing.s4,
        @ViewBuilder mark: () -> Mark,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.eyebrow = eyebrow
        self.note = note
        self.padding = padding
        self.mark = mark()
        self.accessory = EmptyView()
        self.content = content()
    }

    public init(
        eyebrow: String? = nil,
        padding: CGFloat = LBSpacing.s4,
        @ViewBuilder mark: () -> Mark,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.note = nil
        self.padding = padding
        self.mark = mark()
        self.accessory = accessory()
        self.content = content()
    }

    @ViewBuilder private var eyebrowText: some View {
        if let eyebrow {
            Text(eyebrow)
                .lbText(.eyebrow)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    @ViewBuilder private var noteText: some View {
        if let note {
            Text(note)
                .lbText(.footnote)
                .foregroundStyle(LBColor.textTertiary.color)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LBSpacing.s3) {
            if eyebrow != nil || note != nil || Accessory.self != EmptyView.self || Mark.self != EmptyView.self {
                if typeSize.isAccessibilitySize {
                    // The note under the name: side by side, both broke mid-word.
                    VStack(alignment: .leading, spacing: LBSpacing.s1) {
                        HStack(alignment: .firstTextBaseline) { eyebrowText; mark }
                        noteText
                        accessory
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        eyebrowText
                        mark
                        Spacer(minLength: LBSpacing.s2)
                        noteText
                        accessory
                    }
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LBColor.card.color,
            in: RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.lg, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
    }
}
