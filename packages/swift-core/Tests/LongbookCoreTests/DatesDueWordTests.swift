// A commitment's next charge on its card: how soon while near, its date once far.
import XCTest
@testable import LongbookCore

final class DatesDueWordTests: XCTestCase {
    private let far = LB.parseDate("2027-12-12")!

    func testThirtyDaysOrFewerKeepTheRelativeWord() {
        XCTAssertEqual(LB.dueWord(0, on: far), "Today")
        XCTAssertEqual(LB.dueWord(1, on: far), "Tomorrow")
        XCTAssertEqual(LB.dueWord(30, on: far), "In 30 days")
    }

    func testPastThirtyDaysItIsTheDateWithItsYear() {
        XCTAssertEqual(LB.dueWord(31, on: far), "On \(LB.longDate(far))")
        XCTAssertTrue(LB.dueWord(400, on: far).contains("2027"))
    }
}
