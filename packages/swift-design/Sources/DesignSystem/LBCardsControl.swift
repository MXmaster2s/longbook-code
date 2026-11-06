import SwiftUI

/// One stop on a Cards Control: what it is called to a screen reader, its symbol, and how
/// many cards it holds, when that is told.
public struct LBCardsControlItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let symbol: String
    public let count: Int?

    public init(id: ID, title: String, symbol: String, count: Int? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.count = count
    }
}

/// A control group of the kinds of card a place holds, each a symbol with its count: the
/// current one lit on a card, a tap jumps to any other. A kind counted at zero has no cards
/// and takes no stop.
public struct LBCardsControl<ID: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [LBCardsControlItem<ID>]
    private let current: ID?
    private let onSelect: (ID) -> Void

    public init(items: [LBCardsControlItem<ID>], current: ID?, onSelect: @escaping (ID) -> Void) {
        self.items = items.filter { $0.count != 0 }
        self.current = current
        self.onSelect = onSelect
    }

    #if os(macOS)
    private static var stopHeight: CGFloat { 28 }
    #else
    private static var stopHeight: CGFloat { 36 }
    #endif

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let lit = item.id == current
                Button {
                    if !lit { onSelect(item.id) }
                } label: {
                    HStack(spacing: LBSpacing.s1) {
                        Image(systemName: item.symbol)
                            .lbText(.body)
                            .accessibilityHidden(true)
                        if let count = item.count {
                            Text("\(count)")
                                .lbText(.cardDetail)
                                .monospacedDigit()
                                .lineLimit(1)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(lit ? LBColor.textPrimary.color : LBColor.textSecondary.color)
                    .frame(maxWidth: .infinity, minHeight: Self.stopHeight)
                    .background(lit ? LBColor.card.color : .clear, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
                    .contentShape(Rectangle())
                }
                .lbButtonStyle(.rounded(LBRadius.xs), hovers: !lit)
                .accessibilityLabel(item.count.map { "\($0) \(item.title)" } ?? item.title)
                .help(item.title)
                .accessibilityAddTraits(lit ? .isSelected : [])
            }
        }
        .padding(2)
        .background(LBColor.hairline.color, in: RoundedRectangle(cornerRadius: LBRadius.sm, style: .continuous))
        .animation(LBMotion.resolve(reduceMotion: reduceMotion), value: current)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Cards Control") {
    VStack {
        LBCardsControl(items: LBCardKind.allCases.map { LBCardsControlItem(id: $0, title: $0.rawValue, symbol: $0.symbol) }, current: .people) { _ in }
        LBCardsControl(items: LBCardKind.allCases.map { LBCardsControlItem(id: $0, title: $0.rawValue, symbol: $0.symbol, count: $0 == .earning ? 0 : 12) }, current: .charge) { _ in }
    }
    .padding()
    .background(LBColor.canvas.color)
}
