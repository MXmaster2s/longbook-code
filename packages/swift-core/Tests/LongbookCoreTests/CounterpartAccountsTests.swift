// The account a transfer moves money to, found by its id or by a name that reads the same.
import XCTest
@testable import LongbookCore

final class CounterpartAccountsTests: XCTestCase {
    private func account(_ id: String, _ name: String) -> PaymentMethod {
        PaymentMethod(id: id, name: name, nameKey: name.lowercased())
    }

    private func transfer(_ id: String, details: Details?) -> Subscription {
        Subscription(id: id, name: "To savings", amount: 5000, currency: "INR", billingCycle: .once,
                     status: .active, details: details, direction: "transfer")
    }

    func testAnIdNamesTheAccountOutright() {
        let hdfc = account("a-hdfc", "HDFC 4417")
        let sub = transfer("t1", details: ["counterpart_account_id": .string("a-hdfc"), "counterpart_account": .string("Somewhere else")])
        XCTAssertTrue(CounterpartAccounts.moves(sub, to: hdfc))
        XCTAssertFalse(CounterpartAccounts.moves(sub, to: account("a-axis", "Axis")))
    }

    func testANameAloneMatchesTheWayTheStatementReaderMatchesAccounts() {
        let hdfc = account("a-hdfc", "HDFC savings ••4417")
        let sub = transfer("t2", details: ["counterpart_account": .string("HDFC 4417")])
        XCTAssertTrue(CounterpartAccounts.moves(sub, to: hdfc))
        XCTAssertFalse(CounterpartAccounts.moves(sub, to: account("a-icici", "ICICI 4417")))
    }

    func testTheBookIsGroupedByAccountWithUnknownIdsLeftOut() {
        let hdfc = account("a-hdfc", "HDFC 4417")
        let axis = account("a-axis", "Axis Bank")
        let vault = Vault(app: "longbook", subscriptions: [
            transfer("t1", details: ["counterpart_account_id": .string("a-hdfc")]),
            transfer("t2", details: ["counterpart_account": .string("axis bank")]),
            transfer("t3", details: ["counterpart_account_id": .string("a-gone"), "counterpart_account": .string("Axis Bank")]),
            transfer("t4", details: nil),
            Fx.sub(id: "s1"),
        ], paymentMethods: [hdfc, axis])
        let grouped = CounterpartAccounts.transfers(in: vault)
        XCTAssertEqual(grouped["a-hdfc"]?.map(\.id), ["t1"])
        XCTAssertEqual(grouped["a-axis"]?.map(\.id), ["t2"], "an id the book no longer holds is not matched by name")
        XCTAssertNil(grouped["a-gone"])
    }

    func testBlankDetailsNameNothing() {
        let sub = transfer("t5", details: ["counterpart_account_id": .string("  "), "counterpart_account": .null])
        let named = CounterpartAccounts.counterpart(of: sub)
        XCTAssertNil(named.id)
        XCTAssertNil(named.name)
    }
}
