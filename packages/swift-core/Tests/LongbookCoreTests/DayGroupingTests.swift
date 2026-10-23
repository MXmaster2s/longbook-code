import XCTest
@testable import LongbookCore

/// A handful of zones skip midnight when daylight saving starts, so a calendar day's
/// first moment is 01:00 and two dates meaning the same day can differ as instants.
/// Grouping "what is owed on the next day" by instant dropped one of them.
final class DayGroupingTests: XCTestCase {
    private var original: Calendar!

    override func setUp() {
        super.setUp()
        original = LB.calendar
    }

    override func tearDown() {
        LB.calendar = original
        super.tearDown()
    }

    private func use(timeZone identifier: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        LB.calendar = calendar
    }

    /// Santiago has no 00:00 on 2026-09-06. Two rows are owed on 6 August; both must show.
    func testChargesOnOneDayGroupTogetherAcrossADaylightSavingBoundary() {
        use(timeZone: "America/Santiago")
        let today = LB.parseDate("2026-08-06")!
        let vault = Fx.vault([Fx.sub(id: "a"), Fx.sub(id: "b")],
                             [Fx.row("a", "2026-08-06", amount: 10), Fx.row("b", "2026-08-06", amount: 10)])
        let day = nextPaymentDay(vault, today)
        XCTAssertEqual(day?.charges.count, 2, "a charge owed on the hero day was hidden")
        XCTAssertEqual(sumByCurrency(day?.charges ?? []).first?.amount, 20)
    }

    /// The same vault must read the same in any zone.
    func testTheSameVaultAgreesAcrossZones() {
        for zone in ["America/Santiago", "Asia/Kolkata", "America/New_York", "Australia/Lord_Howe"] {
            use(timeZone: zone)
            let vault = Fx.vault([Fx.sub(id: "a"), Fx.sub(id: "b")],
                                 [Fx.row("a", "2026-08-06", amount: 10), Fx.row("b", "2026-08-06", amount: 10)])
            let day = nextPaymentDay(vault, LB.parseDate("2026-08-06")!)
            XCTAssertEqual(day?.charges.count, 2, "disagreed in \(zone)")
        }
    }

    /// Amounts ending in a zero cent kept their last digit.
    func testMoneyKeepsBothDecimalPlaces() {
        XCTAssertEqual(fmtMoney(12.50, "USD"), "$12.50")
        XCTAssertEqual(fmtMoney(12.55, "USD"), "$12.55")
        XCTAssertEqual(fmtMoney(12, "USD"), "$12")
    }

    func testAnInstantParsesWithOrWithoutFractionalSecondsAndADayDoesNot() {
        XCTAssertEqual(LB.parseDateTime("2026-09-07T10:15:00Z"), Date(timeIntervalSince1970: 1_788_776_100))
        XCTAssertEqual(LB.parseDateTime("2026-09-07T10:15:00.250Z"), Date(timeIntervalSince1970: 1_788_776_100.25))
        XCTAssertEqual(LB.parseDateTime("2026-09-07T15:45:00+05:30"), Date(timeIntervalSince1970: 1_788_776_100))
        XCTAssertNil(LB.parseDateTime("2026-09-07"))
        XCTAssertNil(LB.parseDateTime(nil))
    }
}
