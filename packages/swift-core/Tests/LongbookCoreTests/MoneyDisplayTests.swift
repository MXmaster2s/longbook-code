// What the Show decimals setting reaches: the words on a screen, and nothing a file holds.
import XCTest
@testable import LongbookCore

final class MoneyDisplayTests: XCTestCase {
    private let now = LB.parseDateTime("2026-09-07T10:15:00Z")!

    func testOffShowsWholeAmountsRoundedTheUsualWayInEveryCurrency() {
        XCTAssertEqual(fmtMoney(59.99, "USD", showsDecimals: false), "$60")
        XCTAssertEqual(fmtMoney(12.5, "USD", showsDecimals: false), "$13")
        XCTAssertEqual(fmtMoney(12.49, "USD", showsDecimals: false), "$12")
        XCTAssertEqual(fmtMoney(1299.5, "INR", showsDecimals: false), "₹1,300")
    }

    func testOnShowsTwoDecimalsOnEveryAmount() {
        XCTAssertEqual(fmtMoney(59.99, "USD", showsDecimals: true), "$59.99")
        XCTAssertEqual(fmtMoney(60, "USD", showsDecimals: true), "$60.00")
        XCTAssertEqual(fmtMoney(1299.5, "INR", showsDecimals: true), "₹1,299.50")
    }

    func testACurrencyWithNoSmallerUnitStaysWhole() {
        XCTAssertFalse(fmtMoney(1500.4, "JPY", showsDecimals: true).contains("."))
    }

    func testTheSettingIsOffUntilSet() {
        XCTAssertFalse(MoneyDisplay.showsDecimals)
        XCTAssertEqual(fmtMoney(59.99, "USD"), "$60")
    }

    func testCentsForComparingNeverRound() {
        XCTAssertEqual(fmtMoneyCents(59.99, "USD"), "$59.99")
        XCTAssertNotEqual(fmtMoneyCents(59.99, "USD"), fmtMoneyCents(60, "USD"), "a Proposal's before and after stay apart")
    }

    func testAFormRoundTripOfCentsSavesCentsWithTheSettingOff() throws {
        XCTAssertEqual(fmtMoney(59.99, "USD"), "$60", "the screen shows it whole")
        var edit = SubEdit()
        edit.name = "Gym"
        edit.currency = "USD"
        edit.billingCycle = .once
        edit.firstCharge = "2026-10-10"
        // What a form's amount field holds, typed back as a number.
        let typed = try XCTUnwrap(Double(plainAmount(59.99)))
        edit.amount = typed
        let vault = try VaultPatch.apply(edit, to: Fx.raw([]), now: now)
        let row = try XCTUnwrap((vault["commitments"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["amount"] as? Double, 59.99)
        let id = try XCTUnwrap(row["id"] as? String)
        XCTAssertEqual(Fx.rows(vault, of: id).first?["amount"] as? Double, 59.99)

        // Loaded from the row and saved untouched, it stays exactly what it was.
        var again = SubEdit(from: try JSONDecoder().decode(Subscription.self, from: JSONSerialization.data(withJSONObject: row)))
        again.amount = try XCTUnwrap(Double(plainAmount(again.amount)))
        let after = try VaultPatch.apply(again, to: vault, now: now)
        XCTAssertEqual((after["commitments"] as? [[String: Any]])?.first?["amount"] as? Double, 59.99)
    }

    func testTotalsAddExactFiguresAndOnlyTheirWordsRound() {
        let sums = [CurrencyAmount(currency: "USD", amount: 59.99 + 59.99)]
        XCTAssertEqual(sums[0].amount, 119.98, accuracy: 0.0001)
        XCTAssertEqual(fmtMoneyTotals(sums), "$120")
    }
}
