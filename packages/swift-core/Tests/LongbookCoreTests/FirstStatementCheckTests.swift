import XCTest
@testable import LongbookCore

/// The first statement must be recent and cover about a month; several files are judged together.
final class FirstStatementCheckTests: XCTestCase {
    private typealias Period = FirstStatementCheck.Period
    private let today = "2026-11-04"

    private func ago(_ days: Int, from day: String = "2026-11-04") -> String {
        LB.toISO(LB.addDays(LB.parseDate(day)!, -days))
    }

    private func judge(_ periods: [Period], today: String = "2026-11-04") -> FirstStatementCheck.Outcome {
        FirstStatementCheck.judge(periods, today: today)
    }

    func testAHalfMonthStatementFromTwoYearsAgoIsNotRecent() {
        XCTAssertEqual(judge([Period(start: "2024-10-01", end: "2024-10-15")]), .notRecent)
    }

    func testAFebruaryStatementEndingTenDaysAgoPasses() {
        XCTAssertEqual(judge([Period(start: "2026-02-01", end: "2026-02-28")], today: "2026-03-10"), .pass)
    }

    func testEndingSixtyDaysAgoPassesAndSixtyOneFails() {
        XCTAssertEqual(judge([Period(start: ago(100), end: ago(60))]), .pass)
        XCTAssertEqual(judge([Period(start: ago(100), end: ago(61))]), .notRecent)
    }

    func testARecentHalfMonthIsTooShort() {
        XCTAssertEqual(judge([Period(start: ago(19), end: ago(5))]), .tooShort)
    }

    func testTwoAdjacentRecentHalfMonthsPassTogether() {
        XCTAssertEqual(judge([Period(start: ago(34), end: ago(20)), Period(start: ago(19), end: ago(5))]), .pass)
    }

    func testAnOldSixMonthStatementGivesARecentShortOneNoCredit() {
        let old = Period(start: "2025-01-01", end: "2025-06-30")
        let recent = Period(start: ago(12), end: ago(3))
        XCTAssertEqual(judge([old, recent]), .tooShort)
        // One that reaches into the window counts only its days inside it.
        let edge = Period(start: ago(400), end: ago(FirstStatementCheck.windowDays - 10))
        XCTAssertEqual(judge([edge, recent]), .tooShort)
    }

    func testOverlappingPeriodsCountOnce() {
        let one = Period(start: ago(20), end: ago(1))
        let two = Period(start: ago(15), end: ago(5))
        XCTAssertEqual(judge([one, two]), .tooShort)
        XCTAssertEqual(judge([one, Period(start: ago(30), end: ago(10))]), .pass)
    }

    func testDayBoundariesAndAYearEnd() {
        // Twenty-eight days, both ends counted, passes; twenty-seven does not.
        XCTAssertEqual(judge([Period(start: ago(27), end: ago(0))]), .pass)
        XCTAssertEqual(judge([Period(start: ago(26), end: ago(0))]), .tooShort)
        // December, read on 5 January.
        XCTAssertEqual(judge([Period(start: "2026-12-01", end: "2026-12-31")], today: "2027-01-05"), .pass)
        // Across the turn of the year: 20 December to 16 January is twenty-eight days.
        XCTAssertEqual(judge([Period(start: "2026-12-20", end: "2027-01-16")], today: "2027-01-20"), .pass)
        XCTAssertEqual(judge([Period(start: "2026-12-21", end: "2027-01-16")], today: "2027-01-20"), .tooShort)
        // Sixty days back across the year end: 5 November 2026 from 4 January 2027.
        XCTAssertEqual(judge([Period(start: "2026-10-01", end: "2026-11-05")], today: "2027-01-04"), .pass)
        XCTAssertEqual(judge([Period(start: "2026-10-01", end: "2026-11-04")], today: "2027-01-04"), .notRecent)
    }

    func testASixMonthStatementFromThisWeekPasses() {
        XCTAssertEqual(judge([Period(start: "2026-05-01", end: "2026-11-02")]), .pass)
    }

    func testNoPeriodIsNotRecentAndDaysAfterTodayAreNotCovered() {
        XCTAssertEqual(judge([]), .notRecent)
        XCTAssertEqual(judge([Period(start: ago(5), end: ago(-30))]), .tooShort)
    }

    func testThePrintedPeriodWinsOverTheLines() {
        let printed = Period(start: "2026-05-01", end: "2026-10-31")
        XCTAssertEqual(FirstStatementCheck.period(printed: printed, dates: ["2026-06-03"]), printed)
        XCTAssertEqual(FirstStatementCheck.period(printed: nil, dates: ["2026-06-03", "bad", "2026-04-02", "2026-05-09"]),
                       Period(start: "2026-04-02", end: "2026-06-03"))
        XCTAssertNil(FirstStatementCheck.period(printed: nil, dates: []))
    }

    func testAPrintedPeriodIsReadFromTheTop() {
        XCTAssertEqual(FirstStatementCheck.printedPeriod(in: "Account Statement\nStatement From : 01/05/2026 To : 31/10/2026"),
                       Period(start: "2026-05-01", end: "2026-10-31"))
        XCTAssertEqual(FirstStatementCheck.printedPeriod(in: "Period 01 May 2026 to 31 Oct 2026"),
                       Period(start: "2026-05-01", end: "2026-10-31"))
        XCTAssertNil(FirstStatementCheck.printedPeriod(in: "Statement date 03/11/2026"))
    }
}
