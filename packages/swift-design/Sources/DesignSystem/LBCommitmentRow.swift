import SwiftUI

/// One commitment or charge as a card, the same on every screen: an ink on the leading
/// edge, the name and badge, the day and category, then the person and account, the
/// amount trailing. A missing fact stands as its prompt.
public struct LBCommitmentRow<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    private let name: String
    private let facts: [LBMetaFact]
    private let amount: String
    private let ink: LBColorValue
    private let badge: (text: String, tone: LBBadgeTone)?
    private let selected: Bool
    private let symbol: String?
    private let image: URL?
    private let trailing: Trailing

    public init(
        name: String, facts: [LBMetaFact], amount: String, ink: LBColorValue,
        badge: (text: String, tone: LBBadgeTone)? = nil, selected: Bool = false, symbol: String? = nil, image: URL? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.image = image
        self.name = name
        self.facts = facts
        self.amount = amount
        self.ink = ink
        self.badge = badge
        self.selected = selected
        self.symbol = symbol
        self.trailing = trailing()
    }

    /// The people and the account sit on their own line, under the day and the category.
    private static func isLink(_ fact: LBMetaFact) -> Bool {
        fact.symbol == LBGlyph.member || fact.symbol == LBGlyph.account
    }

    private var primaryFacts: [LBMetaFact] { facts.filter { !Self.isLink($0) } }
    private var linkFacts: [LBMetaFact] { facts.filter(Self.isLink) }

    /// With nothing under the amount, it shares the name's line and the facts below run
    /// the card's whole width: a long account or category is cut far less often.
    private var amountOnNameLine: Bool { Trailing.self == EmptyView.self && !typeSize.isAccessibilitySize }

    public var body: some View {
        HStack(alignment: .top, spacing: LBSpacing.s3) {
            // The ink is a second signal, never the only one — the same category is named
            // in the line below it.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ink.color)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: LBSpacing.s2) {
                    // The owner's own picture of it, else a symbol the caller names (a report's). A
                    // commitment passes none: its category is named on the line below.
                    if let picture {
                        picture.resizable().scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityHidden(true)
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LBColor.textSecondary.color)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                    }
                    Text(name)
                        .lbText(.body)
                        .foregroundStyle(LBColor.textPrimary.color)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                    if let badge, !typeSize.isAccessibilitySize {
                        LBBadge(badge.text, tone: badge.tone)
                    }
                    if amountOnNameLine {
                        Spacer(minLength: LBSpacing.s2)
                        amountView
                    }
                }
                // Beside the name at the largest sizes, a badge broke the name mid-word.
                if let badge, typeSize.isAccessibilitySize {
                    LBBadge(badge.text, tone: badge.tone)
                }
                if !primaryFacts.isEmpty { LBMetaFacts(primaryFacts) }
                if !linkFacts.isEmpty { LBMetaFacts(linkFacts) }
                if typeSize.isAccessibilitySize {
                    // Side by side, a raised text size would truncate the name; stack instead.
                    amountView
                    trailing
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize, !amountOnNameLine {
                VStack(alignment: .trailing, spacing: LBSpacing.s2) {
                    amountView
                    trailing
                }
                .layoutPriority(1)
            }
        }
        .padding(LBSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The card is as tall as its words: offered more, it never stretches to fill.
        .fixedSize(horizontal: false, vertical: true)
        // Chosen reads as a tint, never a ring: the ink and the amount stay as they are.
        .background(selected ? LBColor.brand.color.opacity(0.14) : LBColor.card.color,
                    in: RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LBRadius.md, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .contentShape(Rectangle())
        // One row is one thing to hear, unless it carries a control of its own.
        .accessibilityElement(children: Trailing.self == EmptyView.self ? .ignore : .contain)
        .accessibilityLabel(spokenLabel)
    }

    private var picture: Image? {
        guard let image, let data = try? Data(contentsOf: image) else { return nil }
        #if os(macOS)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }

    @ViewBuilder
    private var amountView: some View {
        if !amount.isEmpty {
            LBAmount(amount, prominence: .inline)
                .foregroundStyle(LBColor.textPrimary.color)
        }
    }

    private var spokenLabel: String {
        ([name, badge?.text ?? ""] + facts.map(\.text) + [amount])
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

public extension LBCommitmentRow where Trailing == EmptyView {
    init(
        name: String, facts: [LBMetaFact], amount: String, ink: LBColorValue,
        badge: (text: String, tone: LBBadgeTone)? = nil, selected: Bool = false, symbol: String? = nil, image: URL? = nil
    ) {
        self.init(name: name, facts: facts, amount: amount, ink: ink, badge: badge, selected: selected, symbol: symbol, image: image) { EmptyView() }
    }
}

public extension View {
    /// A card standing alone in a `List`: no row fill, no separator, a breath between cards.
    func lbCardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: LBSpacing.s1, leading: LBSpacing.s4, bottom: LBSpacing.s1, trailing: LBSpacing.s4))
    }
}
