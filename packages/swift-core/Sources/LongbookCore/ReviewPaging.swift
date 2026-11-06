// Pages for a long list: the review shows a hundred rows at a time, then a hundred more
// on request, or every one.
import Foundation

public enum ReviewPaging {
    public static let pageSize = 100

    /// How many rows a kind shows: the page limit held for it, or the first page. `nil`
    /// as a limit means every row.
    public static func shownCount(total: Int, limit: Int?) -> Int {
        guard let limit else { return total }
        return min(max(limit, 0), total)
    }

    /// The rows left after the shown ones.
    public static func hiddenCount(total: Int, limit: Int?) -> Int {
        total - shownCount(total: total, limit: limit)
    }

    /// The limit after "Show 100 more": one page further, never past the end.
    public static func next(limit: Int?, total: Int) -> Int? {
        guard let limit else { return nil }
        let grown = limit + pageSize
        return grown >= total ? nil : grown
    }

    /// The row at the foot of a page, in words: "Show 100 more" or, for the last few,
    /// "Show 12 more". Nil when every row is already shown.
    public static func moreWords(total: Int, limit: Int?) -> String? {
        let hidden = hiddenCount(total: total, limit: limit)
        guard hidden > 0 else { return nil }
        return "Show \(min(pageSize, hidden)) more"
    }
}
