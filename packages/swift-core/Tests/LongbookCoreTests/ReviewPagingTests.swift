// The review's pages: a hundred rows, then a hundred more, or every one.
import XCTest
@testable import LongbookCore

final class ReviewPagingTests: XCTestCase {
    func testTheFirstPageHoldsAHundredRows() {
        XCTAssertEqual(ReviewPaging.shownCount(total: 391, limit: ReviewPaging.pageSize), 100)
        XCTAssertEqual(ReviewPaging.hiddenCount(total: 391, limit: ReviewPaging.pageSize), 291)
        XCTAssertEqual(ReviewPaging.moreWords(total: 391, limit: ReviewPaging.pageSize), "Show 100 more")
    }

    func testAShortListShowsWhole() {
        XCTAssertEqual(ReviewPaging.shownCount(total: 7, limit: ReviewPaging.pageSize), 7)
        XCTAssertNil(ReviewPaging.moreWords(total: 7, limit: ReviewPaging.pageSize))
        XCTAssertNil(ReviewPaging.moreWords(total: 100, limit: 100))
    }

    func testTheNextPageGrowsByAHundredAndTheLastOpensAll() {
        XCTAssertEqual(ReviewPaging.next(limit: 100, total: 391), 200)
        XCTAssertEqual(ReviewPaging.next(limit: 300, total: 391), nil, "the last page shows every row")
        XCTAssertEqual(ReviewPaging.moreWords(total: 391, limit: 300), "Show 91 more")
        XCTAssertNil(ReviewPaging.next(limit: nil, total: 391))
    }

    func testNilShowsEveryRow() {
        XCTAssertEqual(ReviewPaging.shownCount(total: 1500, limit: nil), 1500)
        XCTAssertEqual(ReviewPaging.hiddenCount(total: 1500, limit: nil), 0)
        XCTAssertEqual(ReviewPaging.shownCount(total: 10, limit: -5), 0)
    }
}
