// The words the commitment form says, proved without a screen. Every day here is SYNTHETIC.
import XCTest
@testable import LongbookCore

final class FormWordsTests: XCTestCase {
    private func row(_ iso: String) -> (iso: String, day: Date) { (iso, LB.parseDate(iso) ?? Date.distantPast) }

    /// Days in one year that never collide read short; the chip still speaks the year.
    func testOneYearOfDistinctDaysReadsShort() {
        let words = FormWords.occurrenceWords([row("2026-10-06"), row("2026-11-06"), row("2026-12-06")])
        XCTAssertEqual(words["2026-10-06"]?.label, LB.shortDate(LB.day(2026, 10, 6)))
        XCTAssertEqual(words["2026-10-06"]?.spoken, LB.longDate(LB.day(2026, 10, 6)))
        XCTAssertEqual(words.count, 3)
    }

    /// Two chips that would read alike — a yearly plan's — take the year.
    func testAlikeDaysTakeTheYear() {
        let words = FormWords.occurrenceWords([row("2026-02-14"), row("2027-02-14")])
        XCTAssertEqual(words["2026-02-14"]?.label, LB.longDate(LB.day(2026, 2, 14)))
        XCTAssertEqual(words["2027-02-14"]?.label, LB.longDate(LB.day(2027, 2, 14)))
    }

    /// A strip that runs into another year takes the year even when no two days collide, so
    /// "8 Oct · 8 Apr · 7 Oct" never reads as one year's run.
    func testAStripAcrossYearsTakesTheYear() {
        let words = FormWords.occurrenceWords([row("2026-10-08"), row("2027-04-08"), row("2027-10-07")])
        XCTAssertEqual(words["2027-04-08"]?.label, LB.longDate(LB.day(2027, 4, 8)))
        XCTAssertEqual(words["2026-10-08"]?.label, LB.longDate(LB.day(2026, 10, 8)))
    }

    /// A file holding two rows for one commitment on one day — a hand edit, or an AI writing
    /// the JSON itself — must not trap the form. The first row's words stand.
    func testTwoRowsOnOneDayDoNotTrap() {
        let words = FormWords.occurrenceWords([row("2026-10-06"), row("2026-10-06"), row("2026-11-06")])
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words["2026-10-06"]?.label, LB.shortDate(LB.day(2026, 10, 6)), "the duplicate never forces the year on")
    }

    func testNoDaysNoWords() {
        XCTAssertTrue(FormWords.occurrenceWords([]).isEmpty)
    }

    /// A stop from an active commitment names the count it unwrites; from a stopped one, or
    /// with nothing planned, the footnote says so instead of counting zero.
    func testAStopCountsOnlyWhatItUnwrites() {
        XCTAssertEqual(FormWords.statusNote(from: .active, to: .paused, planned: 3, plansAhead: true),
                       "Pausing unwrites the 3 planned charges after today. What happened stays.")
        XCTAssertEqual(FormWords.statusNote(from: .active, to: .cancelled, planned: 1, plansAhead: true),
                       "Cancelling unwrites the 1 planned charge after today. What happened stays.")
        XCTAssertEqual(FormWords.statusNote(from: .active, to: .paused, planned: 0, plansAhead: true),
                       "Nothing is planned after today. What happened stays.")
        XCTAssertEqual(FormWords.statusNote(from: .paused, to: .cancelled, planned: 4, plansAhead: true),
                       "Nothing is planned after today. What happened stays.")
        XCTAssertEqual(FormWords.statusNote(from: .cancelled, to: .paused, planned: 0, plansAhead: false),
                       "Nothing is planned after today. What happened stays.")
    }

    func testBackToActiveNamesTheCountOrTheCancellingDate() {
        XCTAssertEqual(FormWords.statusNote(from: .paused, to: .active, planned: 0, plansAhead: true),
                       "Back to active plans it ahead again; pick the count beside the date.")
        XCTAssertEqual(FormWords.statusNote(from: .cancelled, to: .active, planned: 0, plansAhead: false),
                       "Back to active plans nothing past the cancelling date.")
        XCTAssertNil(FormWords.statusNote(from: .active, to: .active, planned: 5, plansAhead: true))
    }
}
