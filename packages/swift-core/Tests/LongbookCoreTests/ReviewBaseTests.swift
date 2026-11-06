// A commitment the owner adds while an outside edit stands for review applies directly: it
// moves the review's base and never joins the review. Every fixture is SYNTHETIC.
import XCTest
@testable import LongbookCore

final class ReviewBaseTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-28T09:00:00Z")!

    /// The version the owner last accepted: one commitment with two charges.
    private func accepted() -> [String: Any] {
        Fx.raw([Fx.rawSub(id: "flix", name: "Netflix", amount: 649)],
               charges: [Fx.rawRow("flix", "2026-10-05", paid: true, basis: "statement"),
                         Fx.rawRow("flix", "2026-11-05")])
    }

    /// An AI's write on top of it, signed by the AI: a gym membership added.
    private func outside() -> [String: Any] {
        var raw = accepted()
        raw["commitments"] = (raw["commitments"] as! [[String: Any]]) + [Fx.rawSub(id: "gym", name: "Gym", amount: 2000)]
        raw["charges"] = (raw["charges"] as! [[String: Any]]) + [Fx.rawRow("gym", "2026-11-01", amount: 2000)]
        raw["_provenance"] = ["gym": ["edited_by": "Claude", "edited_at": "2026-10-27T10:00:00Z"]]
        return raw
    }

    private func newCommitment() -> SubEdit {
        var edit = SubEdit()
        edit.name = "Water can"
        edit.amount = 400
        edit.currency = "INR"
        edit.billingCycle = .monthly
        edit.firstCharge = "2026-11-10"
        return edit
    }

    private func ids(_ diffs: [EntityDiff]) -> Set<String> {
        Set(diffs.flatMap { $0.added.map(\.id) + $0.changed.map(\.id) + $0.removed.map(\.id) })
    }

    func testOwnAddDuringReviewLeavesOnlyTheOutsideEdit() throws {
        let base = accepted()
        let reviewed = outside()
        let saved = try VaultPatch.saveCommitment(newCommitment(), plannedCount: 3, in: reviewed, now: now)
        let added = try XCTUnwrap((saved["commitments"] as? [[String: Any]])?.first { $0["name"] as? String == "Water can" }?["id"] as? String)

        // Before the fix the review diffed the accepted version against the file: the
        // owner's commitment stood in it beside the AI's.
        XCTAssertTrue(ids(vaultDiff(from: base, to: saved)).contains(added))

        let moved = ReviewBase.carry(from: reviewed, to: saved, onto: base)
        let left = ids(vaultDiff(from: moved, to: saved))
        XCTAssertFalse(left.contains(added))
        XCTAssertFalse(left.contains { $0.hasPrefix(added + "@") })
        XCTAssertEqual(left, ["gym", "gym@2026-11-01"])

        // The base keeps the owner's rows and their signature, so Undo leaves them in place.
        XCTAssertTrue((moved["commitments"] as? [[String: Any]])?.contains { $0["id"] as? String == added } == true)
        XCTAssertFalse(Fx.rows(moved, of: added).isEmpty)
        let signed = (moved["_provenance"] as? [String: Any])?[added] as? [String: Any]
        XCTAssertEqual(signed?["edited_by"] as? String, "longbook-phone")
        XCTAssertNil((moved["_provenance"] as? [String: Any])?["gym"], "the AI's signature stays under review")
    }

    func testOwnEditAndRemovalCarryAndOtherRowsStay() throws {
        let base = accepted()
        let reviewed = outside()
        var edited = reviewed
        var subs = edited["commitments"] as! [[String: Any]]
        subs[0]["amount"] = 699.0
        edited["commitments"] = subs
        edited["charges"] = (edited["charges"] as! [[String: Any]]).filter { $0["date"] as? String != "2026-11-05" }
        edited["home_currency"] = "INR"

        let moved = ReviewBase.carry(from: reviewed, to: edited, onto: base)
        XCTAssertEqual(ids(vaultDiff(from: moved, to: edited)), ["gym", "gym@2026-11-01"])
        XCTAssertEqual((moved["commitments"] as? [[String: Any]])?.first?["amount"] as? Double, 699)
        XCTAssertEqual(Fx.rows(moved, of: "flix").count, 1)
        XCTAssertEqual(moved["home_currency"] as? String, "INR")
    }

    func testNothingTouchedLeavesTheBase() {
        let base = accepted()
        let moved = ReviewBase.carry(from: outside(), to: outside(), onto: base)
        XCTAssertTrue(vaultDiff(from: base, to: moved).isEmpty)
        XCTAssertNil(moved["_provenance"])
    }
}
