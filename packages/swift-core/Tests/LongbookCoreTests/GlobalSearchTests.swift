// Search across the whole longbook: what matches, in which order, and how the keyboard moves.
import XCTest
@testable import LongbookCore

final class GlobalSearchTests: XCTestCase {
    private func entry(_ kind: SearchKind, _ id: String, _ name: String, _ words: String?...) -> SearchEntry {
        SearchEntry(kind: kind, id: id, name: name, words: words)
    }

    func testGroupsFollowTheSidebarOrder() {
        let entries = [
            entry(.help, "h1", "Netflix and your statement"),
            entry(.charges, "c1", "Netflix"),
            entry(.commitments, "s1", "Netflix"),
            entry(.accounts, "a1", "Amex Gold card", "netflix"),
        ]
        let kinds = GlobalSearch.search("netflix", in: entries).map(\.kind)
        XCTAssertEqual(kinds, [.accounts, .commitments, .charges, .help])
    }

    func testAnExactNameLeadsThenAPrefixThenAWordThenOtherWords() {
        let entries = [
            entry(.charges, "1", "Spotify", "gym"),
            entry(.charges, "2", "City gym membership"),
            entry(.charges, "3", "Gymshark"),
            entry(.charges, "4", "Gym"),
        ]
        let ids = GlobalSearch.search("gym", in: entries).first?.hits.map(\.id)
        XCTAssertEqual(ids, ["4", "3", "2", "1"])
    }

    func testTiesKeepTheOrderTheEntriesCameIn() {
        let entries = (1...3).map { entry(.charges, "\($0)", "Netflix") }
        XCTAssertEqual(GlobalSearch.search("Netflix", in: entries).first?.hits.map(\.id), ["1", "2", "3"])
    }

    func testEveryWordMustMatchSomewhere() {
        let entries = [
            entry(.charges, "1", "Netflix", "Amex Gold card", "entertainment"),
            entry(.charges, "2", "Netflix", "Chase checking"),
        ]
        XCTAssertEqual(GlobalSearch.search("netflix amex", in: entries).first?.hits.map(\.id), ["1"])
        XCTAssertTrue(GlobalSearch.search("netflix visa", in: entries).isEmpty)
    }

    func testCaseAccentsAndSpacesAreIgnored() {
        let entries = [entry(.people, "p1", "Zoë Müller")]
        XCTAssertEqual(GlobalSearch.search("  zoe   MULLER ", in: entries).first?.hits.map(\.id), ["p1"])
    }

    func testNotesStatementLinesAndAmountsFind() {
        let entries = [entry(.charges, "1", "Electricity", "POS 4411 CON EDISON NY", "$86.40", "86.40")]
        XCTAssertEqual(GlobalSearch.search("con edison", in: entries).first?.total, 1)
        XCTAssertEqual(GlobalSearch.search("86.40", in: entries).first?.total, 1)
    }

    func testAKindShowsFiveAndSaysHowManyMore() {
        let entries = (1...12).map { entry(.charges, "\($0)", "Uber trip") }
        let group = GlobalSearch.search("uber", in: entries).first
        XCTAssertEqual(group?.hits.count, 5)
        XCTAssertEqual(group?.total, 12)
        XCTAssertEqual(group?.showAllWords, "Show all 12 charges")
    }

    func testAKindThatFitsHasNoShowAll() {
        let entries = (1...5).map { entry(.people, "\($0)", "Sam \($0)") }
        XCTAssertNil(GlobalSearch.search("sam", in: entries).first?.showAllWords)
    }

    func testAnEmptyQueryFindsNothing() {
        XCTAssertTrue(GlobalSearch.search("   ", in: [entry(.charges, "1", "Netflix")]).isEmpty)
    }

    func testRowsListEachKindsResultsThenItsShowAll() {
        let entries = (1...6).map { entry(.charges, "c\($0)", "Uber") } + [entry(.people, "p1", "Uber driver")]
        let rows = GlobalSearch.rows(GlobalSearch.search("uber", in: entries))
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[5], .showAll(.charges, total: 6))
        if case .hit(let last) = rows[6] { XCTAssertEqual(last.id, "p1") } else { XCTFail("the person comes last") }
    }

    func testTheHighlightStopsAtEitherEnd() {
        XCTAssertEqual(GlobalSearch.moved(0, by: -1, count: 4), 0)
        XCTAssertEqual(GlobalSearch.moved(2, by: 1, count: 4), 3)
        XCTAssertEqual(GlobalSearch.moved(3, by: 1, count: 4), 3)
        XCTAssertEqual(GlobalSearch.moved(3, by: 1, count: 0), 0)
    }

    func testRecentSearchesPutTheNewestFirstOnceAndKeepSix() {
        var recent: [String] = []
        for query in ["netflix", "rent", "Amex", "gym", "uber", "sam", "zoom"] {
            recent = GlobalSearch.remembering(query, in: recent)
        }
        XCTAssertEqual(recent, ["zoom", "sam", "uber", "gym", "Amex", "rent"])
        XCTAssertEqual(GlobalSearch.remembering(" amex ", in: recent), ["amex", "zoom", "sam", "uber", "gym", "rent"])
        XCTAssertEqual(GlobalSearch.remembering("  ", in: recent), recent)
    }
}
