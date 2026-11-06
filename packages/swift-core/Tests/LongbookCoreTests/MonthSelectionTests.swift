// A selection of months: never empty, stepped as one shape, and named in one set of words.
// The anchor stands for "this month"; the locale is pinned so the words are the same anywhere.
import XCTest
@testable import LongbookCore

final class MonthSelectionTests: XCTestCase {
    /// A day in September 2026: offset 0 is September, -2 July, 4 January 2027.
    private let anchor = LB.day(2026, 9, 23)
    private let posix = Locale(identifier: "en_US_POSIX")
    /// Twenty years either way, as far as the dashboard browses.
    private let browsable = -240...240

    private func months(_ offsets: Int...) -> MonthSelection {
        MonthSelection(offsets: offsets)!
    }

    private func words(_ selection: MonthSelection) -> String {
        selection.label(anchor: anchor, locale: posix)
    }

    // MARK: membership

    func testTheDefaultIsThisMonthAlone() {
        let selection = MonthSelection()
        XCTAssertEqual(selection.count, 1)
        XCTAssertTrue(selection.contains(0))
        XCTAssertFalse(selection.contains(-1))
        XCTAssertEqual(MonthSelection(-3).months, [-3])
    }

    func testMembershipAnswersForEveryMonthNamedAndNoOther() {
        let selection = months(-2, 0, 5)
        XCTAssertTrue(selection.contains(-2))
        XCTAssertTrue(selection.contains(0))
        XCTAssertTrue(selection.contains(5))
        XCTAssertFalse(selection.contains(-1))
        XCTAssertFalse(selection.contains(1))
    }

    func testNoMonthsIsNoSelection() {
        XCTAssertNil(MonthSelection(offsets: [Int]()))
        XCTAssertNil(MonthSelection(days: [], anchor: anchor))
    }

    func testDaysNameTheirMonthsAsOffsetsFromTheAnchorMonth() {
        let selection = MonthSelection(
            days: [LB.day(2026, 7, 31), LB.day(2026, 7, 1), LB.day(2026, 9, 1), LB.day(2025, 12, 15)],
            anchor: anchor
        )
        XCTAssertEqual(selection?.months, [-9, -2, 0], "two days in July name it once")
    }

    // MARK: toggling

    func testAToggleAddsAMonthThenTakesItAway() {
        var selection = MonthSelection()
        XCTAssertTrue(selection.toggle(-1))
        XCTAssertEqual(selection.months, [-1, 0])
        XCTAssertTrue(selection.toggle(0))
        XCTAssertEqual(selection.months, [-1])
    }

    func testTakingAwayTheOnlyMonthIsRefused() {
        var selection = MonthSelection(4)
        XCTAssertFalse(selection.toggle(4))
        XCTAssertEqual(selection, MonthSelection(4), "a refused toggle changes nothing")
    }

    // MARK: shifting

    func testAShiftMovesEveryMonthAndKeepsTheShape() {
        let selection = months(-3, -1, 0)
        XCTAssertEqual(selection.shifted(by: 1, within: -12...12)?.months, [-2, 0, 1])
        XCTAssertEqual(selection.shifted(by: -1, within: -12...12)?.months, [-4, -2, -1])
    }

    func testAShiftThatWouldLeaveTheRangeIsRefused() {
        XCTAssertNil(months(10, 12).shifted(by: 1, within: -12...12), "12 would step to 13")
        XCTAssertNil(months(-12, -11).shifted(by: -1, within: -12...12))
        XCTAssertEqual(months(10, 12).shifted(by: -1, within: -12...12)?.months, [9, 11])
    }

    // MARK: a new month

    /// On 1 October, Jul – Sep chosen in September is still Jul – Sep, not Aug – Oct.
    func testANewMonthKeepsTheSameCalendarMonths() {
        let october = LB.day(2026, 10, 1)
        let carried = months(-2, -1, 0).carried(from: anchor, to: october, within: browsable)
        XCTAssertEqual(carried.months, [-3, -2, -1])
        XCTAssertEqual(carried.label(anchor: october, locale: posix), "Jul – Sep 2026")
    }

    func testThisMonthAloneFollowsTheCalendar() {
        let october = LB.day(2026, 10, 1)
        let carried = MonthSelection().carried(from: anchor, to: october, within: browsable)
        XCTAssertEqual(carried, MonthSelection())
        XCTAssertEqual(carried.label(anchor: october, locale: posix), "October 2026")
    }

    /// Only this month alone follows: another month alone, or this month among others, stays put.
    func testEveryOtherSelectionKeepsItsMonths() {
        let october = LB.day(2026, 10, 1)
        XCTAssertEqual(
            MonthSelection(-1).carried(from: anchor, to: october, within: browsable).label(anchor: october, locale: posix),
            "August 2026"
        )
        XCTAssertEqual(
            months(0, 1).carried(from: anchor, to: october, within: browsable).label(anchor: october, locale: posix),
            "Sep – Oct 2026"
        )
    }

    func testTheMonthsPassedAreCountedAcrossAYearEndAndSeveralAtOnce() {
        let january = LB.day(2027, 1, 1)
        XCTAssertEqual(
            months(-1, 0).carried(from: LB.day(2026, 12, 31), to: january, within: browsable)
                .label(anchor: january, locale: posix),
            "Nov – Dec 2026"
        )
        let february = LB.day(2027, 2, 14)
        let carried = months(-8, -6, 0).carried(from: anchor, to: february, within: browsable)
        XCTAssertEqual(carried.months, [-13, -11, -5], "five months passed")
        XCTAssertEqual(carried.label(anchor: february, locale: posix), "Jan, Mar, Sep 2026")
    }

    /// A clock set back a month carries the other way.
    func testAnEarlierMonthCarriesForward() {
        let october = LB.day(2026, 10, 1)
        XCTAssertEqual(months(-3, -1).carried(from: october, to: anchor, within: browsable).months, [-2, 0])
    }

    func testTheSameMonthCarriesNothing() {
        XCTAssertEqual(months(-3, 2).carried(from: anchor, to: LB.day(2026, 9, 30), within: browsable), months(-3, 2))
    }

    /// One month pushed past the range takes the whole selection back to this month alone.
    func testMonthsThatWouldLeaveTheRangeGiveWayToThisMonthAlone() {
        let october = LB.day(2026, 10, 1)
        XCTAssertEqual(months(-240, -2).carried(from: anchor, to: october, within: browsable), MonthSelection())
        XCTAssertEqual(months(-239, -2).carried(from: anchor, to: october, within: browsable).months, [-240, -3])
    }

    // MARK: contiguity and order

    func testMonthsWithNoGapAreContiguous() {
        XCTAssertTrue(MonthSelection().isContiguous)
        XCTAssertTrue(months(-2, -1, 0).isContiguous)
        XCTAssertFalse(months(-2, 0).isContiguous)
        XCTAssertFalse(months(-5, -4, 0).isContiguous)
    }

    /// October 2026 to March 2027 crosses a year end with no gap.
    func testARunAcrossAYearEndIsContiguous() {
        let selection = months(1, 2, 3, 4, 5, 6)
        XCTAssertTrue(selection.isContiguous)
        XCTAssertEqual(selection.firstDays(anchor: anchor).first, LB.day(2026, 10, 1))
        XCTAssertEqual(selection.firstDays(anchor: anchor).last, LB.day(2027, 3, 1))
    }

    func testTheMonthsReadEarliestFirstWhateverOrderTheyWereNamedIn() {
        let selection = months(3, -7, 0, -1)
        XCTAssertEqual(selection.months, [-7, -1, 0, 3])
        XCTAssertEqual(
            selection.firstDays(anchor: anchor),
            [LB.day(2026, 2, 1), LB.day(2026, 8, 1), LB.day(2026, 9, 1), LB.day(2026, 12, 1)]
        )
    }

    /// Each window is a whole calendar month, February's leap day included.
    func testTheWindowsAreWholeCalendarMonths() {
        let windows = months(-8, 17).windows(anchor: anchor)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].first, LB.day(2026, 1, 1))
        XCTAssertEqual(windows[0].last, LB.day(2026, 1, 31))
        XCTAssertEqual(windows[1].first, LB.day(2028, 2, 1))
        XCTAssertEqual(windows[1].last, LB.day(2028, 2, 29))
    }

    func testTheSpanRunsFromTheEarliestFirstDayToTheLatestLastDay() {
        let span = months(-2, 0, 3).span(anchor: anchor)
        XCTAssertEqual(span.first, LB.day(2026, 7, 1))
        XCTAssertEqual(span.last, LB.day(2026, 12, 31))
    }

    /// Jan, Feb and Jun take six places, so June sits where June falls, not where April would.
    func testEveryMonthAcrossTheSpanHasAPlaceChosenOrNot() {
        let slots = months(-8, -7, -3).spanWindows(anchor: anchor)
        XCTAssertEqual(slots.map { $0.first }, (1...6).map { LB.day(2026, $0, 1) })
        XCTAssertEqual(slots[1].last, LB.day(2026, 2, 28))
        XCTAssertEqual(slots[5].last, LB.day(2026, 6, 30))
        let acrossAYear = months(2, 5).spanWindows(anchor: anchor)
        XCTAssertEqual(
            acrossAYear.map { $0.first },
            [LB.day(2026, 11, 1), LB.day(2026, 12, 1), LB.day(2027, 1, 1), LB.day(2027, 2, 1)]
        )
    }

    func testMonthsWithNoGapTakeExactlyTheirOwnPlaces() {
        for selection in [MonthSelection(), months(-2, -1, 0), months(2, 3, 4)] {
            let slots = selection.spanWindows(anchor: anchor)
            let windows = selection.windows(anchor: anchor)
            XCTAssertEqual(slots.map { $0.first }, windows.map { $0.first })
            XCTAssertEqual(slots.map { $0.last }, windows.map { $0.last })
        }
    }

    // MARK: words

    func testOneMonthIsNamedInFull() {
        XCTAssertEqual(words(MonthSelection()), "September 2026")
        XCTAssertEqual(words(MonthSelection(-9)), "December 2025")
    }

    func testARunInOneYearIsNamedByItsEnds() {
        XCTAssertEqual(words(months(-2, -1, 0)), "Jul – Sep 2026")
        XCTAssertEqual(words(months(-1, 0)), "Aug – Sep 2026")
        XCTAssertEqual(words(months(-8, -7, -6, -5, -4)), "Jan – May 2026", "a run is never counted")
    }

    func testARunAcrossAYearEndNamesBothYears() {
        XCTAssertEqual(words(months(2, 3, 4)), "Nov 2026 – Jan 2027")
        XCTAssertEqual(words(months(-10, -9, -8)), "Nov 2025 – Jan 2026")
    }

    /// Two years, no gap: a run, not a list.
    func testAContiguousSelectionSpanningTwoYearsIsARun() {
        let selection = months(-9, -8)
        XCTAssertTrue(selection.isContiguous)
        XCTAssertEqual(words(selection), "Dec 2025 – Jan 2026")
    }

    func testSeparateMonthsInOneYearAreListedWithTheYearOnce() {
        XCTAssertEqual(words(months(-8, -6, -3)), "Jan, Mar, Jun 2026")
        XCTAssertEqual(words(months(-2, 0)), "Jul, Sep 2026")
    }

    func testSeparateMonthsAcrossYearsSayEachYearAfterItsLastMonth() {
        XCTAssertEqual(words(months(-9, -7)), "Dec 2025, Feb 2026")
        XCTAssertEqual(words(months(-11, -9, -7)), "Oct, Dec 2025, Feb 2026")
        XCTAssertEqual(words(months(-21, -9, 5)), "Dec 2024, Dec 2025, Feb 2027")
    }

    /// Counted as chosen months: "Nothing in 4 months." would read as a length of time.
    func testMoreThanThreeSeparateMonthsAreCounted() {
        XCTAssertEqual(words(months(-8, -6, -4, -2)), "4 chosen months")
        XCTAssertEqual(words(months(-8, -6, -4, -2, 0)), "5 chosen months")
        XCTAssertEqual(words(months(-20, -9, -2, 0, 1)), "5 chosen months")
    }

    func testTheEdgeLabelsNameTheFirstAndLastMonth() {
        let sameYear = months(-2, -1, 0).edgeLabels(anchor: anchor, locale: posix)
        XCTAssertEqual(sameYear.first, "Jul")
        XCTAssertEqual(sameYear.last, "Sep")
        let twoYears = months(-10, -9, -8).edgeLabels(anchor: anchor, locale: posix)
        XCTAssertEqual(twoYears.first, "Nov 2025")
        XCTAssertEqual(twoYears.last, "Jan 2026")
    }
}
