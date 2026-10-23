// The expense chart's bars: every day of one month, only the charged days of several.
// Every fixture is SYNTHETIC; this repo is public.
import XCTest
@testable import LongbookCore

final class ExpenseBarsTests: XCTestCase {
    /// 5 Sep 2026: offset 0 is September, -1 August, -2 July.
    private let today = LB.day(2026, 9, 5)

    private func months(_ offsets: Int...) -> MonthSelection {
        MonthSelection(offsets: offsets)!
    }

    private func bars(_ rows: [ChargeRow], _ selection: MonthSelection, subs: [Subscription]? = nil) -> [ExpenseBar] {
        let vault = Fx.vault(subs ?? [Fx.sub(id: "a", name: "A"), Fx.sub(id: "u", name: "U", currency: "USD")], rows)
        return expenseBars(allCharges(vault, today), selection: selection, anchor: today, scope: "INR", today: today)
    }

    // MARK: one month

    func testOneMonthGivesEveryCalendarDayEmptyOnesIncluded() {
        let out = bars([Fx.row("a", "2026-09-03", amount: 500), Fx.row("a", "2026-09-20", amount: 700)], months(0))
        XCTAssertEqual(out.count, 30)
        XCTAssertEqual(out.first?.day, LB.day(2026, 9, 1))
        XCTAssertEqual(out.last?.day, LB.day(2026, 9, 30))
        XCTAssertEqual(out.map(\.scoped).reduce(0, +), 1200)
        XCTAssertEqual(out[2].scoped, 500)
        XCTAssertEqual(out[2].chargeIds, ["a-2026-09-03"])
        XCTAssertEqual(out[19].scoped, 700)
        XCTAssertEqual(out[0].scoped, 0)
        XCTAssertTrue(out[0].chargeIds.isEmpty)
        XCTAssertFalse(out[0].foreignOnly)
    }

    func testOneMonthStartsItsMonthOnTheFirstBarOnly() {
        let out = bars([], months(-2))
        XCTAssertEqual(out.count, 31)
        XCTAssertEqual(out.filter(\.startsMonth).map(\.day), [LB.day(2026, 7, 1)])
    }

    func testADayIsPastOnceItIsBehindToday() {
        let out = bars([], months(0))
        XCTAssertTrue(out[3].isPast, "4 Sep")
        XCTAssertFalse(out[4].isPast, "today is not past")
        XCTAssertFalse(out[5].isPast)
    }

    func testTwoChargesOnOneDayMakeOneBar() {
        let out = bars([Fx.row("a", "2026-09-10", amount: 100), Fx.row("u", "2026-09-10", amount: 20, currency: "INR")], months(0))
        XCTAssertEqual(out[9].scoped, 120)
        XCTAssertEqual(out[9].chargeIds, ["a-2026-09-10", "u-2026-09-10"])
    }

    // MARK: several months

    func testSeveralMonthsGiveOnlyTheDaysThatHoldACharge() {
        let rows = [
            Fx.row("a", "2026-07-20", amount: 300),
            Fx.row("a", "2026-07-03", amount: 100),
            Fx.row("a", "2026-08-15", amount: 999),
            Fx.row("a", "2026-09-01", amount: 200),
        ]
        let out = bars(rows, months(-2, 0))
        XCTAssertEqual(out.map(\.day), [LB.day(2026, 7, 3), LB.day(2026, 7, 20), LB.day(2026, 9, 1)])
        XCTAssertEqual(out.map(\.scoped), [100, 300, 200])
        XCTAssertEqual(out.map(\.startsMonth), [true, false, true])
        XCTAssertEqual(out.map(\.isPast), [true, true, true])
    }

    func testAChosenMonthWithNothingContributesNoBar() {
        let rows = [Fx.row("a", "2026-07-03"), Fx.row("a", "2026-09-01")]
        let out = bars(rows, months(-3, -2, 0))
        XCTAssertEqual(out.map(\.day), [LB.day(2026, 7, 3), LB.day(2026, 9, 1)])
    }

    func testNothingAtAllInSeveralMonthsIsNoBars() {
        XCTAssertTrue(bars([], months(-1, 0)).isEmpty)
    }

    func testAMonthStartsAtItsFirstChargedDayNotItsFirstDay() {
        let rows = [Fx.row("a", "2026-08-09"), Fx.row("a", "2026-08-28"), Fx.row("a", "2026-09-14"), Fx.row("a", "2026-09-30")]
        let out = bars(rows, months(-1, 0))
        XCTAssertEqual(out.filter(\.startsMonth).map(\.day), [LB.day(2026, 8, 9), LB.day(2026, 9, 14)])
        XCTAssertEqual(out.map(\.isPast), [true, true, false, false])
    }

    // MARK: currencies

    func testAnotherCurrencyIsKeptBesideTheBarNeverAddedToIt() {
        let rows = [Fx.row("a", "2026-09-08", amount: 400), Fx.row("u", "2026-09-08", amount: 20)]
        let day = bars(rows, months(0))[7]
        XCTAssertEqual(day.scoped, 400)
        XCTAssertEqual(day.others, [CurrencyAmount(currency: "USD", amount: 20)])
        XCTAssertFalse(day.foreignOnly)
    }

    func testADayInAnotherCurrencyAloneIsForeignOnly() {
        let rows = [Fx.row("u", "2026-09-08", amount: 20), Fx.row("u", "2026-09-08", amount: 5)]
        let day = bars(rows, months(0))[7]
        XCTAssertEqual(day.scoped, 0)
        XCTAssertTrue(day.foreignOnly)
        XCTAssertEqual(day.others, [CurrencyAmount(currency: "USD", amount: 25)])
        XCTAssertEqual(day.chargeIds.count, 2)
    }

    func testAForeignOnlyDayEarnsABarInSeveralMonths() {
        let out = bars([Fx.row("u", "2026-08-08", amount: 20)], months(-1, 0))
        XCTAssertEqual(out.map(\.day), [LB.day(2026, 8, 8)])
        XCTAssertTrue(out[0].foreignOnly)
    }

    // MARK: what counts

    func testAPlannedRowCountsLikeAnyOther() {
        let rows = [Fx.row("a", "2026-09-20", amount: 700, basis: "plan"), Fx.row("a", "2026-09-02", amount: 300, basis: "statement")]
        let out = bars(rows, months(0))
        XCTAssertEqual(out[19].scoped, 700)
        XCTAssertEqual(out[1].scoped, 300)
    }

    /// A trial's sign-up day holds a zero charge. It is no expense: in several months it earns
    /// no bar, in one month its day stays empty, and beside a real charge it is not counted.
    func testAZeroChargeIsNotAnExpense() {
        let rows = [Fx.row("a", "2026-08-08", amount: 0, paid: true, basis: "user"),
                    Fx.row("a", "2026-09-03", amount: 0, paid: true, basis: "user"),
                    Fx.row("a", "2026-09-10", amount: 0, paid: true, basis: "user"),
                    Fx.row("u", "2026-09-10", amount: 500, currency: "INR")]
        XCTAssertEqual(bars(rows, months(-1, 0)).map(\.day), [LB.day(2026, 9, 10)], "no bar day for a zero charge alone")
        let month = bars(rows, months(0))
        XCTAssertEqual(month.count, 30)
        XCTAssertTrue(month[2].chargeIds.isEmpty, "3 Sep holds only the zero charge")
        XCTAssertEqual(month[9].chargeIds, ["u-2026-09-10"], "beside a real charge, the zero one is not counted")
        XCTAssertEqual(month[9].scoped, 500)
    }

    func testAChargeOutsideTheChosenMonthsIsDropped() {
        let rows = [Fx.row("a", "2026-08-31", amount: 100), Fx.row("a", "2026-10-01", amount: 100), Fx.row("a", "2026-09-15", amount: 50)]
        let out = bars(rows, months(0))
        XCTAssertEqual(out.map(\.scoped).reduce(0, +), 50)
    }

    func testMoneyInAndTransfersAreNotBars() {
        let subs = [
            Fx.sub(id: "a", name: "A"),
            Subscription(id: "pay", name: "Pay", amount: 1000, currency: "INR", billingCycle: .monthly, status: .active, direction: "in"),
        ]
        let rows = [Fx.row("pay", "2026-09-01", amount: 1000), Fx.row("a", "2026-09-01", amount: 10)]
        let out = bars(rows, months(-1, 0), subs: subs)
        XCTAssertEqual(out.map(\.scoped), [10])
        XCTAssertEqual(out[0].chargeIds, ["a-2026-09-01"])
    }
}
