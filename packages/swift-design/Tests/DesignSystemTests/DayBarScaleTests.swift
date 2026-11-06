import XCTest
@testable import DesignSystem

/// The day chart's arithmetic: a bar's share of the height on the log scale, and which
/// bar a point across the chart belongs to.
final class DayBarScaleTests: XCTestCase {
    private typealias Bars = LBDayBars

    // MARK: height

    func testNothingIsNoHeightAndThePeakIsAllOfIt() {
        XCTAssertEqual(Bars.share(0, peak: 100), 0)
        XCTAssertEqual(Bars.share(100, peak: 100), 1)
        XCTAssertEqual(Bars.share(50, peak: 0), 0, "no peak, no height")
        XCTAssertEqual(Bars.share(-5, peak: 100), 0)
    }

    func testAHigherDayIsATallerBar() {
        let shares = [1.0, 10, 100, 1000, 10_000].map { Bars.share($0, peak: 10_000) }
        XCTAssertEqual(shares, shares.sorted())
        XCTAssertEqual(Set(shares).count, shares.count, "distinct values draw distinct heights")
    }

    /// The point of the scale: a day a tenth of the peak is not a tenth of the height.
    func testATenthOfThePeakDrawsWellAboveATenthOfTheHeight() {
        XCTAssertGreaterThan(Bars.share(10, peak: 100), 0.4)
        XCTAssertGreaterThan(Bars.share(4200, peak: 42000), 0.7)
        XCTAssertLessThan(Bars.share(10, peak: 100), 1)
    }

    func testAValueOverThePeakIsHeldAtTheTop() {
        XCTAssertEqual(Bars.share(200, peak: 100), 1)
    }

    // MARK: layout

    func testSharedBarsSplitTheWidthWithTwoPointsBetween() {
        let layout = Bars.layout(width: 300, count: 30, widest: nil)
        XCTAssertEqual(layout.gap, 2)
        XCTAssertEqual(layout.slot * 30 + layout.gap * 29, 300, accuracy: 0.001)
    }

    func testCappedBarsSitAtBothEdges() {
        let layout = Bars.layout(width: 300, count: 4, widest: 18)
        XCTAssertEqual(layout.slot, 18)
        XCTAssertEqual(layout.gap, 76)
        XCTAssertEqual(layout.step * 3 + layout.slot, 300, accuracy: 0.001)
    }

    func testCappedBarsShrinkWhenTheCapIsWiderThanTheirShare() {
        let layout = Bars.layout(width: 100, count: 12, widest: 18)
        XCTAssertEqual(layout.gap, 2)
        XCTAssertEqual(layout.slot, 6.5, accuracy: 0.001)
    }

    func testOneCappedBarKeepsItsCap() {
        XCTAssertEqual(Bars.layout(width: 300, count: 1, widest: 18).slot, 18)
        XCTAssertEqual(Bars.layout(width: 300, count: 0, widest: 18).slot, 0)
    }

    // MARK: hit

    func testTheEdgesAreTheFirstAndLastBar() {
        XCTAssertEqual(Bars.index(atX: 0, width: 300, count: 30, widest: nil), 0)
        XCTAssertEqual(Bars.index(atX: 300, width: 300, count: 30, widest: nil), 29)
        XCTAssertEqual(Bars.index(atX: 0, width: 300, count: 4, widest: 18), 0)
        XCTAssertEqual(Bars.index(atX: 300, width: 300, count: 4, widest: 18), 3)
        XCTAssertEqual(Bars.index(atX: -20, width: 300, count: 30, widest: nil), 0, "held inside")
        XCTAssertEqual(Bars.index(atX: 900, width: 300, count: 30, widest: nil), 29, "held inside")
    }

    func testTheMiddleOfABarIsThatBar() {
        let layout = Bars.layout(width: 300, count: 30, widest: nil)
        for i in 0..<30 {
            let middle = CGFloat(i) * layout.step + layout.slot / 2
            XCTAssertEqual(Bars.index(atX: middle, width: 300, count: 30, widest: nil), i)
        }
        let capped = Bars.layout(width: 300, count: 4, widest: 18)
        XCTAssertEqual(Bars.index(atX: 2 * capped.step + 9, width: 300, count: 4, widest: 18), 2)
    }

    func testAPointInAGapGoesToTheNearerBar() {
        let layout = Bars.layout(width: 300, count: 4, widest: 18)
        let gapStart = layout.slot
        XCTAssertEqual(Bars.index(atX: gapStart + layout.gap / 2 - 1, width: 300, count: 4, widest: 18), 0)
        XCTAssertEqual(Bars.index(atX: gapStart + layout.gap / 2 + 1, width: 300, count: 4, widest: 18), 1)
    }

    func testNoBarsIsNoHit() {
        XCTAssertNil(Bars.index(atX: 10, width: 300, count: 0, widest: nil))
    }

    // MARK: axis

    private func day(_ label: String?) -> LBDayBarValue {
        LBDayBarValue(scoped: 1, foreignOnly: false, isPast: false, axisLabel: label)
    }

    /// Twenty bars over 200 points step about ten points each: a label two bars on is
    /// inside the room the first one needs; one at the far end has none to its right.
    func testALabelSitsAtItsBarAndTooCloseANeighbourIsLeftOut() {
        var days = Array(repeating: day(nil), count: 20)
        days[0] = day("Jul")
        days[2] = day("Aug")
        days[19] = day("Sep")
        let layout = Bars.layout(width: 200, count: days.count, widest: nil)
        let marks = Bars.axisMarks(days, layout: layout, width: 200)
        XCTAssertEqual(marks.map(\.label), ["Jul", "Sep"], "Aug sits within the room Jul needs")
        XCTAssertEqual(marks[0].x, 0)
        XCTAssertEqual(marks[1].x, 19 * layout.step, accuracy: 0.001)
        XCTAssertFalse(marks[0].endsAtBar)
        XCTAssertTrue(marks[1].endsAtBar, "the last bar's label ends at its bar")
    }

    func testLabelsWithRoomBetweenThemAreAllDrawn() {
        var days = Array(repeating: day(nil), count: 6)
        days[0] = day("Jul")
        days[3] = day("Aug")
        let layout = Bars.layout(width: 300, count: days.count, widest: 18)
        XCTAssertEqual(Bars.axisMarks(days, layout: layout, width: 300).map(\.label), ["Jul", "Aug"])
    }
}
