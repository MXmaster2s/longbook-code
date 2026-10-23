import SwiftUI

/// Chips packed into a fixed number of rows and scrolled sideways. A grid aligns its
/// columns, so one long name widens the column above and below it and leaves a hole beside
/// every short one. This measures nothing but the row it is filling.
public struct LBRail: Layout {
    private let rows: Int
    private let fits: CGFloat?
    private let spacing: CGFloat
    private let lineSpacing: CGFloat

    /// `rows` is a ceiling, not a quota. `fits` is the width the rail is read through —
    /// inside a horizontal scroller nothing proposes that width, so the caller measures it.
    /// Given it, a set that fits on one line stays on one line however many items it has.
    public init(rows: Int, fitting fits: CGFloat? = nil,
                spacing: CGFloat = LBSpacing.s2, lineSpacing: CGFloat = LBSpacing.s2) {
        self.rows = max(1, rows)
        self.fits = fits
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        lay(subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for placed in lay(subviews).items {
            subviews[placed.index].place(
                at: CGPoint(x: bounds.minX + placed.x, y: bounds.minY + placed.y),
                proposal: ProposedViewSize(placed.size)
            )
        }
    }

    private struct Placed {
        let index: Int
        let row: Int
        let x: CGFloat
        let size: CGSize
    }

    /// Each chip goes into whichever row is shortest so far, so the two ends stay level
    /// and nothing is centred into a space its neighbour needed.
    private func lay(_ subviews: Subviews) -> (items: [(index: Int, x: CGFloat, y: CGFloat, size: CGSize)], size: CGSize) {
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(.unspecified) }
        let single = max(sizes.reduce(0) { $0 + $1.width + spacing } - spacing, 0)
        let deep = fits.map { single > $0 } ?? true
        let rows = deep ? self.rows : 1
        var ends = Array(repeating: CGFloat(0), count: rows)
        var tallest: CGFloat = 0
        var packed: [Placed] = []
        for index in subviews.indices {
            let size = sizes[index]
            let row = ends.indices.min { ends[$0] < ends[$1] } ?? 0
            packed.append(Placed(index: index, row: row, x: ends[row], size: size))
            ends[row] += size.width + spacing
            tallest = max(tallest, size.height)
        }
        let step = tallest + lineSpacing
        let items = packed.map {
            (index: $0.index, x: $0.x, y: CGFloat($0.row) * step, size: $0.size)
        }
        let width = max((ends.max() ?? spacing) - spacing, 0)
        let height = CGFloat(rows) * tallest + CGFloat(rows - 1) * lineSpacing
        return (items, CGSize(width: width, height: max(height, 0)))
    }
}
