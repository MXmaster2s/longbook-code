import SwiftUI

/// What a card is. The band's colour and the icon's symbol both name it, so one card view
/// carries a charge, a person or an account without a variant for each.
public enum LBCardKind: String, CaseIterable, Sendable {
    case charge, people, account, commitment, transfer, earning
    /// A report is none of the six money and people kinds; it wears the same card.
    case report

    /// The Kind band's colour, in the palette's own tokens so Light resolves its sibling.
    public var ink: LBColorValue { ink(in: .dark) }

    /// The band in one palette, for the floors to measure: the colour this device gave the kind.
    public func ink(in palette: LBPalette) -> LBColorValue {
        LBCardColours.shared.swatch(for: self).value(in: palette)
    }

    public var symbol: String {
        switch self {
        case .charge: LBGlyph.charge
        case .earning: LBGlyph.income
        case .transfer: LBGlyph.transfer
        case .commitment: LBGlyph.commitment
        case .people: LBGlyph.people
        case .account: LBGlyph.account
        case .report: LBGlyph.report
        }
    }
}

/// A card's mark in its corner: kept or removed, for a list where one can be taken out, or
/// paid, for a charge marked ahead of its day.
public enum LBCardState: Sendable {
    case plain, kept, removed, paid

    var word: String? {
        switch self {
        case .plain: nil
        case .kept: "Kept"
        case .removed: "Removed"
        case .paid: "Paid"
        }
    }
}

/// The fixed circle at a card's left: a symbol in one colour, or the picture someone chose,
/// filling the same circle.
public struct LBCardIcon: View {
    public static let size: CGFloat = 40

    @Environment(\.displayScale) private var displayScale
    private let symbol: String
    private let image: URL?

    public init(symbol: String, image: URL? = nil) {
        self.symbol = symbol
        self.image = image
    }

    public var body: some View {
        ZStack {
            Circle().fill(LBColor.hairline.color)
            if let picture = LBPhoto.image(file: image, side: Self.size, scale: displayScale) {
                picture
            } else {
                Image(systemName: symbol)
                    .lbText(.cardTitle)
                    .foregroundStyle(LBColor.textPrimary.color)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

}

/// The mark a card or a table row wears while its list is selecting: a circle on iPhone, a
/// checkbox on the Mac, filled once chosen.
public struct LBSelectionMark: View {
    private let selected: Bool

    public init(selected: Bool) {
        self.selected = selected
    }

    private var symbol: String {
        #if os(macOS)
        selected ? "checkmark.square.fill" : "square"
        #else
        selected ? "checkmark.circle.fill" : "circle"
        #endif
    }

    public var body: some View {
        Image(systemName: symbol)
            .lbText(.cardTitle)
            .foregroundStyle(selected ? LBColor.brand.color : LBColor.textTertiary.color)
            .accessibilityHidden(true)
    }
}

/// The one card: Kind band, icon, title, pill, amount, up to four details and a state. 98 tall
/// on iPhone and Mac; width follows the column. `lead` details share the first line and the
/// rest the second. With no kind it keeps the shape and wears no band.
public struct LBKindCard: View {
    public static let height: CGFloat = 98
    public static let radius = LBRadius.md

    @Environment(\.dynamicTypeSize) private var typeSize

    private let kind: LBCardKind?
    private let symbol: String?
    private let title: String
    private let pill: String?
    private let pillTone: LBBadgeTone
    private let holdsPill: Bool
    private let amount: String?
    private let details: [LBMetaFact]
    private let lead: Int
    private let image: URL?
    private let state: LBCardState
    private let selected: Bool
    private let marked: Bool
    private let accessory: AnyView?

    /// `symbol` stands in for the kind's own. `holdsPill` keeps the pill beside a long name,
    /// where the pill says what the card is, and the name is cut instead.
    public init(kind: LBCardKind?, symbol: String? = nil, title: String, pill: String? = nil, pillTone: LBBadgeTone = .muted,
                holdsPill: Bool = false, amount: String? = nil,
                details: [LBMetaFact] = [], lead: Int = 2, image: URL? = nil, state: LBCardState = .plain,
                selected: Bool = false, marked: Bool = false, accessory: AnyView? = nil) {
        self.kind = kind
        self.symbol = symbol
        self.title = title
        self.pill = pill
        self.pillTone = pillTone
        self.holdsPill = holdsPill
        self.amount = amount
        self.details = Array(details.prefix(4))
        self.lead = lead
        self.image = image
        self.state = state
        self.selected = selected
        self.marked = marked
        self.accessory = accessory
    }

    private func nameRow(pill: String?) -> some View {
        HStack(spacing: LBSpacing.s2) {
            Text(title)
                .lbText(.cardTitle)
                .foregroundStyle(LBColor.textPrimary.color)
                .lineLimit(1)
            if let pill { LBBadge(pill, tone: pillTone).fixedSize() }
            Spacer(minLength: LBSpacing.s2)
            if let amount {
                Text(amount)
                    .lbText(.cardTitle)
                    .monospacedDigit()
                    .foregroundStyle(LBColor.textPrimary.color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    public var body: some View {
        HStack(spacing: LBSpacing.s3) {
            if marked { LBSelectionMark(selected: selected) }
            LBCardIcon(symbol: symbol ?? kind?.symbol ?? LBGlyph.change, image: image)
            VStack(alignment: .leading, spacing: LBSpacing.s1) {
                if holdsPill {
                    nameRow(pill: marked ? nil : pill)
                } else {
                    // A name too long to sit beside its pill keeps the room; the Preview shows the pill.
                    ViewThatFits(in: .horizontal) {
                        nameRow(pill: marked ? nil : pill)
                        nameRow(pill: nil)
                    }
                }
                detailLine(details.prefix(lead), last: details.count <= lead)
                if details.count > lead || accessory != nil {
                    HStack(spacing: LBSpacing.s2) {
                        detailLine(details.dropFirst(lead), last: true)
                        if let accessory {
                            Spacer(minLength: 0)
                            accessory
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, LBSpacing.s4)
        .padding(.vertical, typeSize.isAccessibilitySize ? LBSpacing.s3 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        // At the accessibility text sizes the words set the height, so none is cut.
        .frame(minHeight: Self.height, maxHeight: typeSize.isAccessibilitySize ? nil : Self.height)
        // Chosen reads as a tint, never a ring: the band and the words stay as they are.
        .lbSelectionFill(selected, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous),
                         resting: LBColor.card.color, tint: 0.14)
        .overlay(alignment: .bottomTrailing) { stateMark }
        .overlay(alignment: .leading) {
            if let kind {
                Rectangle()
                    .fill(kind.ink.color)
                    .frame(width: 4)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(LBColor.hairline.color, lineWidth: 1)
        )
        .opacity(state == .removed ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .accessibilityElement(children: accessory == nil ? .ignore : .contain)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private func detailLine(_ facts: ArraySlice<LBMetaFact>, last: Bool) -> some View {
        if !facts.isEmpty {
            HStack(spacing: LBSpacing.s2) {
                ForEach(facts, id: \.self) { fact in
                    Label(fact.text, systemImage: fact.symbol)
                        .labelStyle(LBCardDetailLabel())
                        .lbText(.cardDetail)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(fact.placeholder ? LBColor.brandText.color : LBColor.textTertiary.color)
                }
            }
            // The last line stops short of the corner's mark.
            .padding(.trailing, last && state != .plain ? LBSpacing.s6 : 0)
        }
    }

    @ViewBuilder
    private var stateMark: some View {
        switch state {
        case .plain:
            EmptyView()
        case .kept:
            Image(systemName: "checkmark.circle.fill")
                .lbText(.cardTitle)
                .foregroundStyle(LBColor.onBrand.color, LBColor.brand.color)
                .padding(LBSpacing.s3)
                .accessibilityHidden(true)
        case .removed:
            Image(systemName: "xmark")
                .lbText(.cardTitle)
                .foregroundStyle(LBColor.textSecondary.color)
                .padding(LBSpacing.s3)
                .accessibilityHidden(true)
        case .paid:
            Image(systemName: LBGlyph.paid)
                .lbText(.cardDetail)
                .foregroundStyle(LBColor.card.color, LBColor.textSecondary.color)
                .padding(LBSpacing.s3)
                .accessibilityHidden(true)
        }
    }

    private var spoken: String {
        ([title, pill ?? "", amount ?? ""] + details.map(\.text) + [state.word == pill ? "" : state.word ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// A detail's symbol close beside its words, so a line holds as much as it can.
private struct LBCardDetailLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: LBSpacing.s1) {
            configuration.icon
            configuration.title
        }
    }
}

/// The press on a phone's card: the pressed shade over the whole card. A Mac card hovers and
/// presses as the Mac's own controls do.
private struct LBKindCardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                LBColor.statePressed.color
                    .opacity(configuration.isPressed ? 1 : 0)
                    .clipShape(RoundedRectangle(cornerRadius: LBKindCard.radius, style: .continuous))
                    .allowsHitTesting(false)
            }
    }
}

public extension View {
    /// A card standing alone in a `List`: no row fill, no separator, a breath between cards.
    func lbCardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: LBSpacing.s4, bottom: 6, trailing: LBSpacing.s4))
    }

    /// A list holding cards: plain rows on the canvas, each as low as what it holds, and lazy
    /// however many it lists.
    func lbCardList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LBColor.canvas.color)
            .environment(\.defaultMinListRowHeight, 0)
    }

    /// The states a card shows when it is a door: Hover and Pressed on the Mac, Pressed on iPhone.
    @ViewBuilder
    func lbCardButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(LBStateButtonStyle(.rounded(LBKindCard.radius)))
        #else
        buttonStyle(LBKindCardPress())
        #endif
    }
}

#Preview("Cards") {
    VStack(spacing: LBSpacing.s2) {
        LBKindCard(kind: .charge, title: "Whole Foods", amount: "$86.40", details: [
            LBMetaFact(symbol: LBGlyph.date, text: "27 Sep 2026"), LBMetaFact(symbol: LBGlyph.category, text: "Food & groceries"),
            LBMetaFact(symbol: LBGlyph.member, text: "Jordan Lee"), LBMetaFact(symbol: LBGlyph.account, text: "Chase Bank"),
        ])
        LBKindCard(kind: .people, title: "Jordan Lee", pill: "Self", amount: "$700.00", details: [
            LBMetaFact(symbol: LBGlyph.account, text: "3 Accounts"), LBMetaFact(symbol: LBGlyph.charge, text: "41 Charges"),
            LBMetaFact(symbol: LBGlyph.commitment, text: "2 Commitments"),
        ], state: .kept)
        LBKindCard(kind: .people, title: "Maya Chen", details: [
            LBMetaFact(symbol: LBGlyph.account, text: "1 Account"),
        ], state: .removed)
        LBKindCard(kind: .report, title: "September 2026", amount: "$4,120.00", details: [
            LBMetaFact(symbol: LBGlyph.date, text: "30 days"), LBMetaFact(symbol: LBGlyph.category, text: "12 categories"),
            LBMetaFact(symbol: LBGlyph.account, text: "3 accounts"), LBMetaFact(symbol: LBGlyph.member, text: "2 people"),
        ])
        LBKindCard(kind: nil, symbol: LBGlyph.category, title: "Streaming", pill: "New", pillTone: .positive, holdsPill: true, details: [
            LBMetaFact(symbol: LBGlyph.category, text: "Category"),
        ])
    }
    .padding()
    .background(LBColor.canvas.color)
}
