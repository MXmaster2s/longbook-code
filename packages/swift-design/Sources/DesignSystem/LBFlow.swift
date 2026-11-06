import SwiftUI

/// Chips that wrap onto as many lines as they need. A horizontal scroller hides its
/// own contents; a set of choices has to be seen whole to be chosen from.
public struct LBFlow: Layout {
    private let spacing: CGFloat
    private let lineSpacing: CGFloat

    public init(spacing: CGFloat = LBSpacing.s2, lineSpacing: CGFloat = LBSpacing.s2) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = lay(subviews, in: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in lay(subviews, in: bounds.width) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [(index: Int, x: CGFloat, size: CGSize)]
    }

    private func lay(_ subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0

        for index in subviews.indices {
            // Measured against the row's own width, never the item's ideal: a name
            // longer than the screen must shorten to fit rather than run off it.
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + lineSpacing, height: 0, items: [])
                x = 0
            }
            current.items.append((index, x, size))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// One choice. Outlined when it isn't taken, filled when it is; the `accent` variant is
/// the way to make a new one, which is an action rather than a choice; `pending` is one
/// not yet taken up, drawn with the dashed "to fill in" edge and no fill.
public struct LBChip: View {
    public enum Style {
        case choice(selected: Bool)
        case accent
        case pending
    }

    private let title: String
    private let symbol: String?
    private let style: Style
    private let action: () -> Void

    public init(_ title: String, symbol: String? = nil, style: Style, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.action = action
    }

    private var selected: Bool {
        if case .choice(let selected) = style { return selected }
        return false
    }

    private var isAccent: Bool {
        if case .accent = style { return true }
        return false
    }

    private var isPending: Bool {
        if case .pending = style { return true }
        return false
    }

    private var ink: LBColorValue {
        return selected ? LBColor.onBrand : LBColor.textSecondary
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .lbText(.bodySM)
                    .lineLimit(1)
            }
            .foregroundStyle(ink.color)
            .padding(.horizontal, LBSpacing.s3)
            .padding(.vertical, LBSpacing.s2)
            .background(fill, in: RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous))
            .overlay {
                if isPending {
                    LBDashedOutline(cornerRadius: LBRadius.xs)
                } else {
                    RoundedRectangle(cornerRadius: LBRadius.xs, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .lbButtonStyle(.rounded(LBRadius.xs))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if isPending { return .clear }
        return selected ? LBColor.brand.color : LBColor.card.color
    }

    private var border: Color {
        return selected ? .clear : LBColor.hairline.color
    }
}
