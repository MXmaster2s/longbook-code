import SwiftUI

/// A row's facts on one wrapping line, each a glyph and its words. Each fact is one
/// subview, so a glyph and its words never part across lines. A placeholder keeps its
/// slot and glyph and reads as an action word, in the brand's text ink.
public struct LBMetaFacts: View {
    private let facts: [LBMetaFact]

    public init(_ facts: [LBMetaFact]) {
        self.facts = facts
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        // One line at the standard sizes: a long account or person is cut with an ellipsis
        // rather than wrapping the card to a fourth line. At the accessibility sizes the
        // facts wrap instead, since one line there cut nearly every one short.
        if typeSize.isAccessibilitySize {
            LBFlow(spacing: LBSpacing.s2, lineSpacing: LBSpacing.s1) { items(wrapping: true) }
        } else {
            HStack(spacing: LBSpacing.s2) { items(wrapping: false) }
        }
    }

    private func items(wrapping: Bool) -> some View {
        ForEach(facts, id: \.self) { fact in
            HStack(spacing: 3) {
                if !fact.symbol.isEmpty {
                    Image(systemName: fact.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityHidden(true)
                }
                Text(fact.text)
                    .lbText(.footnote)
                    .lineLimit(wrapping ? nil : 1)
                    .truncationMode(.tail)
            }
            .layoutPriority(fact == facts.first ? 1 : 0)
            .foregroundStyle(fact.placeholder ? LBColor.brandText.color : LBColor.textTertiary.color)
        }
    }
}
