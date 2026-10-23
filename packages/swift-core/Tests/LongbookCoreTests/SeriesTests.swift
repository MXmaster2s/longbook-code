// The chart's engine must stay dense and honest: one bucket per calendar month, empty
// months as zero rows, and a foreign currency carried beside the scope, never inside
// it. Every fixture is SYNTHETIC; this repo is public.
import XCTest
@testable import LongbookCore

final class SeriesTests: XCTestCase {
    /// 21 Jul 2026 — mid-window, so both directions get exercised.
    private let today = LB.day(2026, 7, 21)

    func testExactlyTwentyFiveBucketsOldestFirstEvenWithNoData() {
        let series = monthlySeries(Fx.vault([]), scope: "INR", around: today)
        XCTAssertEqual(series.count, 25)
        XCTAssertEqual(LB.toISO(series.first!.month), "2025-07-01")
        XCTAssertEqual(LB.toISO(series.last!.month), "2027-07-01")
        XCTAssertTrue(series.allSatisfy { $0.scoped == 0 && $0.count == 0 })
    }

    func testAOneTimeChargeFillsOneBucketAndLeavesTheRestAsZeroRows() {
        let vault = Fx.vault([Fx.sub(id: "o", cycle: .once)], [Fx.row("o", "2026-09-15", amount: 500)])
        let series = monthlySeries(vault, scope: "INR", around: today)
        let sept = series.first { LB.toISO($0.month) == "2026-09-01" }!
        XCTAssertEqual(sept.scoped, 500)
        XCTAssertEqual(series.filter { $0.count > 0 }.count, 1)
    }

    func testAMonthlyRunLandsInEveryMonthItWasWrittenFor() {
        let vault = Fx.vault([Fx.sub(id: "a")], Fx.monthly("a", from: "2026-05-10", months: 6))
        let series = monthlySeries(vault, scope: "INR", around: today)
        let filled = series.filter { $0.count == 1 }.map { LB.toISO($0.month) }
        XCTAssertEqual(filled, ["2026-05-01", "2026-06-01", "2026-07-01", "2026-08-01", "2026-09-01", "2026-10-01"])
    }

    func testAMonthWithNoRowIsAnEmptyMonthNotAProjectedOne() {
        let vault = Fx.vault([Fx.sub(id: "a")], [Fx.row("a", "2026-07-21"), Fx.row("a", "2026-09-21")])
        let series = monthlySeries(vault, scope: "INR", around: today)
        XCTAssertEqual(series.first { LB.toISO($0.month) == "2026-08-01" }?.count, 0)
    }

    func testForeignCurrencyIsCarriedBesideTheScopeNeverBlended() {
        let vault = Fx.vault([Fx.sub(id: "r", currency: "INR"), Fx.sub(id: "u", currency: "USD")],
                             [Fx.row("r", "2026-07-21", amount: 100), Fx.row("u", "2026-07-21", amount: 20)])
        let july = monthlySeries(vault, scope: "INR", around: today).first { LB.toISO($0.month) == "2026-07-01" }!
        XCTAssertEqual(july.scoped, 100)
        XCTAssertEqual(july.others.first?.currency, "USD")
        XCTAssertEqual(july.others.first?.amount, 20)
        XCTAssertEqual(july.count, 2)
    }

    func testCustomWindowSizesHoldTheBucketArithmetic() {
        let series = monthlySeries(Fx.vault([]), scope: "INR", around: today, monthsBack: 2, monthsForward: 1)
        XCTAssertEqual(series.map { LB.toISO($0.month) }, ["2026-05-01", "2026-06-01", "2026-07-01", "2026-08-01"])
    }

    /// A paused commitment's past rows are still money that left; its plan ahead was
    /// removed when it was paused, so nothing is invented forward either.
    func testAPausedCommitmentsPastStillCountsAndItsFutureIsWhatWasWritten() {
        let vault = Fx.vault([Fx.sub(id: "p", status: .paused)], [Fx.row("p", "2026-06-21", paid: true, basis: "statement")])
        let series = monthlySeries(vault, scope: "INR", around: today)
        XCTAssertEqual(series.first { LB.toISO($0.month) == "2026-06-01" }?.scoped, 100)
        XCTAssertEqual(series.filter { $0.count > 0 }.count, 1)
    }
}
