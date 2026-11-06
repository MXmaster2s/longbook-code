// The changes to one charge are one write: a one-time commitment's price where the charge is
// it, then the row's fields, then the reprice and the move. Proved on the raw dictionary.
// Every fixture is SYNTHETIC; this repo is public.
import XCTest
@testable import LongbookCore

final class ChargeFormWriteTests: XCTestCase {
    private let now = LB.day(2026, 7, 23)
    private var nowStamp: String { VaultPatch.iso8601(now) }

    /// A recurring plan that stops at a cancelling date, beside a one-time purchase, with
    /// keys this build does not model on the vault and on a row.
    private func vault() -> [String: Any] {
        [
            "app": "longbook",
            "version": 3,
            "commitments": [
                [
                    "id": "plan", "name": "Term cover", "amount": 500.0, "currency": "INR",
                    "billing_cycle": "monthly", "status": "active", "ends_on": "2026-12-31",
                    "some_future_field": "must survive",
                ],
                [
                    "id": "once", "name": "Sofa", "amount": 500.0, "currency": "INR",
                    "billing_cycle": "once", "status": "active", "notes": "Three seats",
                ],
            ],
            "charges": [
                Fx.rawRow("plan", "2026-08-05", amount: 500, paid: true, basis: "statement"),
                Fx.rawRow("plan", "2026-09-05", amount: 500),
                Fx.rawRow("plan", "2026-10-05", amount: 500),
                Fx.rawRow("plan", "2026-11-05", amount: 500),
                Fx.rawRow("once", "2026-09-10", amount: 500),
            ],
            "accounts": [["id": "hdfc", "name": "HDFC", "name_key": "hdfc"]],
            "members": [["id": "m1", "name": "Aditi", "name_key": "aditi"]],
            "groups": [["id": "g1", "kind": "payment", "name": "cards", "name_key": "cards"]],
        ]
    }

    private func sub(_ raw: [String: Any], _ id: String) -> [String: Any] {
        (raw["commitments"] as? [[String: Any]] ?? []).first { $0["id"] as? String == id } ?? [:]
    }

    // MARK: - only what changed

    /// Marking a charge of a recurring commitment is no edit of the commitment: its row, its
    /// stamp and its signature stay exactly as the file holds them.
    func testAChargeOnlyEditLeavesTheCommitmentsRowAsItWas() throws {
        let before = sub(vault(), "plan")
        let chargeOnly = try VaultPatch.editCharge(commitmentId: "plan", from: "2026-09-05", paid: true,
                                                   in: vault(), now: now)
        XCTAssertEqual(NSDictionary(dictionary: sub(chargeOnly, "plan")), NSDictionary(dictionary: before))
        XCTAssertNil((chargeOnly["_provenance"] as? [String: Any])?["plan"])
        XCTAssertNotNil(chargeOnly["groups"], "nothing unmodelled is dropped")
    }

    // MARK: - a one-time commitment is its charge

    func testAOneTimeCommitmentsPriceFollowsItsCharge() throws {
        let out = try VaultPatch.editCharge(commitmentId: "once", from: "2026-09-10", amount: 650,
                                            in: vault(), now: now)
        XCTAssertEqual(sub(out, "once")["amount"] as? Double, 650)
        XCTAssertEqual(sub(out, "once")["updated_at"] as? String, nowStamp)
        XCTAssertEqual(Fx.rows(out, of: "once").first?["amount"] as? Double, 650)
        XCTAssertEqual(Fx.rows(out, of: "once").first?["basis"] as? String, "user")

        let unchanged = try VaultPatch.editCharge(commitmentId: "once", from: "2026-09-10", paid: true,
                                                  in: vault(), now: now)
        XCTAssertNil(sub(unchanged, "once")["updated_at"], "no new amount, no price written")
    }

    /// The price is checked as any price is: a one-time commitment cannot be made to cost
    /// less than nothing through its charge.
    func testAOneTimePriceIsCheckedAsTheCommitmentFormChecksIt() {
        XCTAssertThrowsError(try VaultPatch.editCharge(commitmentId: "once", from: "2026-09-10", amount: -5,
                                                       in: vault(), now: now))
    }

    /// A charge that states a currency of its own is counted in it, so its new amount is not
    /// the commitment's price. One in the commitment's currency, or in none, still sets it.
    func testAOneTimePriceFollowsOnlyAChargeCountedInItsCurrency() throws {
        var raw = vault()
        var rows = raw["charges"] as? [[String: Any]] ?? []
        let at = try XCTUnwrap(rows.firstIndex { $0["commitment_id"] as? String == "once" })
        rows[at]["currency"] = "USD"
        raw["charges"] = rows
        let other = try VaultPatch.editCharge(commitmentId: "once", from: "2026-09-10", amount: 20,
                                              in: raw, now: now)
        XCTAssertEqual(sub(other, "once")["amount"] as? Double, 500, "a USD charge never prices an INR commitment")
        XCTAssertNil(sub(other, "once")["updated_at"], "the commitment is not written at all")
        XCTAssertEqual(Fx.rows(other, of: "once").first?["amount"] as? Double, 20)
        XCTAssertEqual(Fx.rows(other, of: "once").first?["currency"] as? String, "USD")

        rows[at]["currency"] = "INR"
        raw["charges"] = rows
        let same = try VaultPatch.editCharge(commitmentId: "once", from: "2026-09-10", amount: 650,
                                             in: raw, now: now)
        XCTAssertEqual(sub(same, "once")["amount"] as? Double, 650, "the commitment's own currency, stated, still follows")
    }

    /// A one-time commitment's currency is picked on the form opened on its charge, and lands
    /// on the commitment in the same Save. The charge states none, so it counts in the new code.
    func testAOneTimeCommitmentsCurrencyLandsInTheSameSave() throws {
        var sofa = SubEdit(id: "once")
        sofa.name = "Sofa"
        sofa.amount = 500
        sofa.currency = "USD"
        sofa.billingCycle = .once
        sofa.notes = "Three seats"
        let out = try VaultPatch.saveCommitment(sofa, charge: .init(from: "2026-09-10", amount: 20), in: vault(), now: now)
        XCTAssertEqual(sub(out, "once")["currency"] as? String, "USD")
        XCTAssertEqual(sub(out, "once")["amount"] as? Double, 20, "the price follows a charge that states no currency")
        XCTAssertNil(Fx.rows(out, of: "once").first?["currency"], "the row still states none of its own")
        XCTAssertEqual(sub(out, "plan")["currency"] as? String, "INR", "no other commitment changes")
    }

    // MARK: - an amount that is not a number

    /// "inf", "nan" and "1e400" all parse as numbers, and none can be written: JSON holds no
    /// non-finite number. Each is refused before anything else, as a negative one is.
    func testAnAmountThatIsNotAFiniteNumberIsRefused() {
        let amounts = ["inf", "nan", "1e400", "-5"].compactMap { Double($0) }
        XCTAssertEqual(amounts.count, 4, "each of them parses")
        for amount in amounts {
            for (id, day) in [("plan", "2026-09-05"), ("once", "2026-09-10")] {
                for andLater in [false, true] {
                    XCTAssertThrowsError(try VaultPatch.editCharge(commitmentId: id, from: day, amount: amount,
                                                                   andLater: andLater, in: vault(), now: now)) {
                        XCTAssertEqual($0.friendlyDescription, "The amount has to be a number, and not a negative one.",
                                       "\(amount) on \(id), later charges \(andLater)")
                    }
                }
            }
        }
        // With a move, an infinite price would reach the move's own decoding of the row first.
        XCTAssertThrowsError(try VaultPatch.editCharge(commitmentId: "plan", from: "2026-09-05", to: "2026-09-12",
                                                       amount: .infinity, andLater: true, in: vault(), now: now)) {
            XCTAssertTrue($0 is WriteError, "refused as a WriteError, \($0)")
        }
    }

    /// Past a quadrillion a charge's amount is refused in plain words, on either commitment and
    /// either reach, and through the plain charge write a proposal's mark or row takes.
    func testAnAmountPastTheLimitIsRefused() throws {
        let words = "The amount can't be more than 1,000,000,000,000,000."
        for amount in [1e15 + 1, 9.3e18] {
            for (id, day) in [("plan", "2026-09-05"), ("once", "2026-09-10")] {
                for andLater in [false, true] {
                    XCTAssertThrowsError(try VaultPatch.editCharge(commitmentId: id, from: day, amount: amount,
                                                                   andLater: andLater, in: vault(), now: now)) {
                        XCTAssertEqual($0.friendlyDescription, words, "\(amount) on \(id), later charges \(andLater)")
                    }
                }
            }
            XCTAssertThrowsError(try VaultPatch.setCharge(commitmentId: "plan", date: "2026-09-05", paid: true,
                                                          amount: amount, in: vault(), now: now)) {
                XCTAssertEqual($0.friendlyDescription, words)
            }
        }
        let limit = try VaultPatch.editCharge(commitmentId: "plan", from: "2026-09-05", amount: 1e15, in: vault(), now: now)
        XCTAssertEqual(Fx.rows(limit, of: "plan")[1]["amount"] as? Double, 1e15, "the limit itself is kept")
    }
}
