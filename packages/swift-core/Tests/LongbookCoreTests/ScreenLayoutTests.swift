// What a Mac list screen keeps between visits: the row it last opened and its two sets of
// column widths.
import XCTest
@testable import LongbookCore

final class ScreenLayoutTests: XCTestCase {
    func testAScreenLandsOnTheRowItRemembers() {
        var rows = RememberedRows()
        rows.remember("chase", on: "accounts")
        XCTAssertEqual(rows.arrival(on: "accounts") { $0 == "chase" }, "chase")
    }

    func testARowThatIsGoneOpensNothing() {
        var rows = RememberedRows()
        rows.remember("chase", on: "accounts")
        XCTAssertNil(rows.arrival(on: "accounts") { _ in false })
    }

    func testAScreenWithNothingRememberedOpensNothing() {
        XCTAssertNil(RememberedRows().arrival(on: "accounts") { _ in true })
    }

    func testForgettingOneScreenLeavesTheOthers() {
        var rows = RememberedRows()
        rows.remember("chase", on: "accounts")
        rows.remember("sam", on: "members")
        rows.forget(on: "accounts")
        XCTAssertNil(rows.row(on: "accounts"))
        XCTAssertEqual(rows.row(on: "members"), "sam")
    }

    func testTheLastRowOpenedIsTheOneKept() {
        var rows = RememberedRows()
        rows.remember("chase", on: "accounts")
        rows.remember("hdfc", on: "accounts")
        XCTAssertEqual(rows.row(on: "accounts"), "hdfc")
    }

    func testRowsSurviveAnEncodingRoundTrip() throws {
        var rows = RememberedRows()
        rows.remember("c:netflix-2026-10-01", on: "charges")
        let back = try JSONDecoder().decode(RememberedRows.self, from: JSONEncoder().encode(rows))
        XCTAssertEqual(back, rows)
    }

    func testThePanelsStatePicksTheSet() {
        let sets = ColumnSets(open: ["Name": 120], closed: ["Name": 300])
        XCTAssertEqual(sets.inForce(panelOpen: true), ["Name": 120])
        XCTAssertEqual(sets.inForce(panelOpen: false), ["Name": 300])
    }

    func testADragChangesOnlyTheSetInForce() {
        var sets = ColumnSets(open: ["Name": 120], closed: ["Name": 300])
        sets.record(["Name": 90], panelOpen: true)
        XCTAssertEqual(sets.open, ["Name": 90])
        XCTAssertEqual(sets.closed, ["Name": 300])
        sets.record(["Name": 250], panelOpen: false)
        XCTAssertEqual(sets.open, ["Name": 90])
        XCTAssertEqual(sets.closed, ["Name": 250])
    }

    func testASetNeverDraggedStaysUnset() {
        var sets = ColumnSets()
        XCTAssertTrue(sets.isEmpty)
        sets.record(["Name": 200], panelOpen: true)
        XCTAssertFalse(sets.isEmpty)
        XCTAssertNil(sets.inForce(panelOpen: false))
    }

    func testAWidthNeverGoesBelowTheNarrowest() {
        var sets = ColumnSets()
        sets.record(["Name": 12], panelOpen: false)
        XCTAssertEqual(sets.closed?["Name"], ColumnSets.narrowest)
    }

    func testSetsSurviveAnEncodingRoundTrip() throws {
        var sets = ColumnSets()
        sets.record(["Name": 200, "Type": 80], panelOpen: true)
        let back = try JSONDecoder().decode(ColumnSets.self, from: JSONEncoder().encode(sets))
        XCTAssertEqual(back, sets)
    }
}
