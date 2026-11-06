import XCTest
@testable import LongbookCore

/// The reading screen's bar: it rises every moment, slows as it goes, and only the end fills it.
final class ReadingBarTests: XCTestCase {
    func testTheBarRisesEveryMomentAndNeverFillsByItself() {
        var bar = ReadingBar()
        var last = bar.share
        for tenth in 1...6_000 {
            bar.advance(to: Double(tenth) / 10, expected: 23, done: 0)
            XCTAssertGreaterThan(bar.share, last, "still at \(tenth)")
            XCTAssertLessThan(bar.share, 1)
            last = bar.share
        }
    }

    func testTheBarSlowsNearTheEnd() {
        var bar = ReadingBar()
        var rises: [Double] = []
        var last = 0.0
        for second in 1...61 {
            bar.advance(to: Double(second), expected: 23, done: 0)
            rises.append(bar.share - last)
            last = bar.share
        }
        XCTAssertLessThan(rises[60], rises[5])
        XCTAssertLessThan(rises[30], rises[5])
        XCTAssertGreaterThan(rises[60], 0)
    }

    func testAnswersCarryTheBarAndAFallingShareNeverLowersIt() {
        var bar = ReadingBar()
        bar.advance(to: 2, expected: 23, done: 0)
        let clockOnly = bar.share
        var helped = ReadingBar()
        helped.advance(to: 2, expected: 23, done: 0.5)
        XCTAssertGreaterThan(helped.share, clockOnly)
        let high = helped.share
        helped.advance(to: 2.1, expected: 23, done: 0.1)
        XCTAssertGreaterThanOrEqual(helped.share, high, "a file changing path grows the units; the bar holds")
        for second in 3...40 {
            helped.advance(to: Double(second), expected: 23, done: 1)
            XCTAssertLessThan(helped.share, 1, "every answer back is not yet the save")
        }
        helped.finish()
        XCTAssertTrue(helped.isFull)
        XCTAssertEqual(helped.share, 1)
    }

    func testTheLinesComeInOrderAsItFills() {
        var bar = ReadingBar()
        XCTAssertEqual(ReadingBar.lines[bar.line].words, "Importing Past Expenses")
        var seen = [bar.line]
        for second in 1...120 {
            bar.advance(to: Double(second), expected: 23, done: Double(second) / 30)
            if seen.last != bar.line { seen.append(bar.line) }
        }
        XCTAssertEqual(seen, Array(0...5))
        XCTAssertEqual(ReadingBar.lines.map(\.words), [
            "Importing Past Expenses", "Identifying People", "Looking for Accounts",
            "Thinking on your Commitments", "Finding Internal Transfers", "Searching your Earnings",
        ])
    }

    func testTheWaitIsTheSlowestFile() {
        XCTAssertEqual(ReadingBar.expected(lineFiles: 2, pieces: []), ReadingBar.linesSeconds)
        XCTAssertEqual(ReadingBar.expected(lineFiles: 1, pieces: [6]), 80)
        XCTAssertEqual(ReadingBar.expected(lineFiles: 0, pieces: [1]), 50)
    }
}
