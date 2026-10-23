// Two devices agreeing: a Keep leaves a review mark, a delete leaves tombstones, an undo
// signs what it puts back; `OwnEdit` adopts each on the other device. The rehearsal plays
// over the demo vault when LONGBOOK_DEMO_VAULT names its folder, else the shared import
// fixture. Every fixture is SYNTHETIC.
import XCTest
@testable import LongbookCore

final class TwoDeviceSyncTests: XCTestCase {
    private let phoneNow = LB.day(2026, 10, 1)
    private var macNow: Date { phoneNow.addingTimeInterval(90) }

    private func provenance(_ vault: [String: Any]) -> [String: [String: Any]] {
        (vault["_provenance"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
    }

    private func ids(_ diff: [EntityDiff]) -> [String] {
        diff.filter { $0.kind != "tags" }.flatMap { $0.added.map(\.id) + $0.changed.map(\.id) + $0.removed.map(\.id) }
    }

    /// The file as a device would read it back: serialised the way VaultDisk writes, parsed again.
    private func roundTrip(_ vault: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: vault, options: [.prettyPrinted, .sortedKeys])
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - the mark

    func testMarkingReviewedKeepsTheWriterAndAddsTheMark() {
        let start: [String: Any] = ["app": "longbook", "version": 3, "commitments": [Fx.rawSub(id: "a")],
                                    "_provenance": ["a": ["edited_by": "claude", "edited_at": "2026-09-30T10:00:00Z", "source": "a chat"]]]
        let marked = VaultPatch.markReviewed(ids: ["a", "a@2026-10-01"], in: start, now: phoneNow)
        let entries = provenance(marked)
        XCTAssertEqual(entries["a"]?["edited_by"] as? String, "claude", "kept is not written")
        XCTAssertEqual(entries["a"]?["edited_at"] as? String, "2026-09-30T10:00:00Z")
        XCTAssertEqual(entries["a"]?["source"] as? String, "a chat")
        XCTAssertEqual(entries["a"]?["reviewed_by"] as? String, "longbook-phone")
        XCTAssertEqual(entries["a"]?["reviewed_at"] as? String, VaultPatch.iso8601(phoneNow))
        XCTAssertEqual(entries["a@2026-10-01"]?["reviewed_by"] as? String, "longbook-phone", "a charge key with no entry gets one")
        XCTAssertNil(entries["a@2026-10-01"]?["edited_by"])
        XCTAssertEqual((VaultPatch.markReviewed(ids: [], in: start, now: phoneNow)["_provenance"] as? [String: Any])?.count, 1,
                       "nothing listed leaves the file as it was")
    }

    // MARK: - the undo

    func testSigningARestoreStampsWhatItPutsBackAndTombstonesWhatItTakes() {
        let current: [String: Any] = ["app": "longbook", "version": 3,
                                      "commitments": [Fx.rawSub(id: "a", amount: 699), Fx.rawSub(id: "b")],
                                      "charges": [Fx.rawRow("b", "2026-10-01")],
                                      "tags": [["id": "t1", "kind": "commitment", "name": "New", "name_key": "new"]],
                                      "_provenance": ["a": ["edited_by": "claude", "edited_at": "2026-09-30T10:00:00Z"],
                                                      "b": ["edited_by": "claude", "edited_at": "2026-09-30T10:00:00Z"]]]
        let restored: [String: Any] = ["app": "longbook", "version": 3,
                                       "commitments": [Fx.rawSub(id: "a", amount: 649), Fx.rawSub(id: "c")],
                                       "_provenance": ["a": ["edited_by": "longbook-phone", "edited_at": "2026-09-01T10:00:00Z"]]]
        let signed = VaultPatch.signRestore(from: current, to: restored, now: macNow)
        let entries = provenance(signed)
        let stamp = VaultPatch.iso8601(macNow)
        for key in ["a", "b", "b@2026-10-01", "c"] {
            XCTAssertEqual(entries[key]?["edited_by"] as? String, "longbook-phone", key)
            XCTAssertEqual(entries[key]?["edited_at"] as? String, stamp, key)
        }
        XCTAssertNil(entries["t1"], "tags are never signed")
        XCTAssertEqual((signed["commitments"] as? [[String: Any]])?.map { $0["id"] as? String }, ["a", "c"], "the rows are the restored vault's")
        XCTAssertNil(signed["tags"])
        XCTAssertTrue(OwnEdit.isOwn(from: current, to: signed), "the other device adopts the undo")
    }

    // MARK: - the rehearsal, both devices over one file

    /// The folder the rehearsal plays in: a copy of the demo vault, or the shared fixture.
    private func openingVault() throws -> [String: Any] {
        let env = ProcessInfo.processInfo.environment["LONGBOOK_DEMO_VAULT"]
        let file = env.map { URL(fileURLWithPath: $0).appendingPathComponent(VaultReader.dataFile) }
            ?? sharedFixturesDirectory(from: #filePath).appendingPathComponent("import-golden-vault.json")
        let data = try Data(contentsOf: file)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Claude's proposal, applied on the phone the way the app applies one: signed with the key's name.
    private func proposed(on vault: [String: Any]) throws -> [String: Any] {
        let write = PendingWrite(id: UUID(), kind: "add_commitments",
                                 payload: ["rows": [["name": "Piano lessons", "amount": 2500, "currency": "INR",
                                                     "billing_cycle": "monthly", "first_charge": "2026-10-10", "plan_months": 3]]],
                                 keyName: "claude")
        guard case .vault(let next) = try PendingApply.apply(write, to: vault, now: phoneNow) else {
            throw XCTSkip("the proposal did not produce a vault")
        }
        return try roundTrip(next)
    }

    func testThePhoneKeepsAndTheMacAdoptsWithoutAsking() throws {
        let h0 = try openingVault()
        let h1 = try proposed(on: h0)
        let proposal = vaultDiff(from: h0, to: h1)
        let added = try XCTUnwrap(proposal.first { $0.kind == "commitments" }?.added.first?.id)
        XCTAssertEqual(provenance(h1)[added]?["edited_by"] as? String, "claude")
        // Both devices open from H0; the proposal stands for review on each.
        XCTAssertFalse(OwnEdit.isOwn(from: h0, to: h1), "the Mac opens a review on the proposal")

        // The phone keeps: the review diff's ids take the mark, and the file is written.
        let h2 = try roundTrip(VaultPatch.markReviewed(ids: ids(proposal), in: h1, now: phoneNow))
        XCTAssertEqual(provenance(h2)[added]?["edited_by"] as? String, "claude", "authorship survives the Keep")
        XCTAssertEqual(provenance(h2)[added]?["reviewed_by"] as? String, "longbook-phone")
        XCTAssertTrue(vaultDiff(from: h1, to: h2).isEmpty, "a Keep moves no row")

        // The Mac notices H2 against its base H0: every touched row carries a fresh mark.
        XCTAssertTrue(OwnEdit.isOwn(from: h0, to: h2), "the Mac adopts the kept change and closes its review")

        // Both kept before iCloud merged: the loser's file differs only in the mark's time.
        let h2b = try roundTrip(VaultPatch.markReviewed(ids: ids(proposal), in: h1, now: macNow))
        XCTAssertTrue(vaultDiff(from: h2, to: h2b).isEmpty, "an empty row diff adopts like an own write")

        // The same mark vouches for nothing newer: Claude edits the row again, the phone reviews again.
        var h3 = h2
        var subs = h3["commitments"] as? [[String: Any]] ?? []
        if let i = subs.firstIndex(where: { $0["id"] as? String == added }) { subs[i]["amount"] = 2800 }
        h3["commitments"] = subs
        XCTAssertFalse(OwnEdit.isOwn(from: h2, to: h3), "a new edit under an old mark is a new outside change")
    }

    func testThePhoneDeletesAndTheMacAdoptsWithoutAsking() throws {
        let h0 = try openingVault()
        let h1 = try proposed(on: h0)
        let proposal = vaultDiff(from: h0, to: h1)
        let added = try XCTUnwrap(proposal.first { $0.kind == "commitments" }?.added.first?.id)
        let h2 = try roundTrip(VaultPatch.markReviewed(ids: ids(proposal), in: h1, now: phoneNow))

        // The phone deletes the commitment outright, charges and all.
        let h3 = try roundTrip(try VaultPatch.delete(id: added, from: h2, now: phoneNow))
        let removed = vaultDiff(from: h2, to: h3)
        XCTAssertEqual(removed.first { $0.kind == "commitments" }?.removed.map(\.id), [added])
        XCTAssertEqual(removed.first { $0.kind == "charges" }?.removed.count, 3, "its three planned charges go with it")
        XCTAssertTrue(OwnEdit.isOwn(from: h2, to: h3), "the Mac adopts the delete through the tombstones")

        // A delete of one the Mac never adopted, against the Mac's older base, is still the owner's.
        XCTAssertTrue(vaultDiff(from: h0, to: h3).isEmpty, "the row came and went; nothing moved against H0")

        // An account deleted on the phone arrives the same way.
        if let account = (h3["accounts"] as? [[String: Any]])?.first?["id"] as? String {
            let h4 = try roundTrip(try VaultPatch.deleteEntity(.paymentMethod, id: account, in: h3, now: phoneNow))
            XCTAssertTrue(OwnEdit.isOwn(from: h3, to: h4))
        }

        // A hand edit with no signature still waits: the rule adopts nothing it cannot vouch for.
        var h5 = h3
        var subs = h5["commitments"] as? [[String: Any]] ?? []
        subs[0]["amount"] = (subs[0]["amount"] as? Double ?? 0) + 1
        h5["commitments"] = subs
        XCTAssertFalse(OwnEdit.isOwn(from: h3, to: h5))
    }

    func testTheMacUndoesAndThePhoneAdoptsWhetherOrNotItKept() throws {
        let h0 = try openingVault()
        let h1 = try proposed(on: h0)
        let proposal = vaultDiff(from: h0, to: h1)
        // The Mac undoes from its review: H0's rows come back, signed as the app's.
        let undone = try roundTrip(VaultPatch.signRestore(from: h1, to: h0, now: macNow))
        // The phone still reviewing from H0 sees no row moved against its base: the review closes.
        XCTAssertTrue(vaultDiff(from: h0, to: undone).isEmpty)
        // The phone that had kept sees the kept rows removed under fresh tombstones.
        let h2 = try roundTrip(VaultPatch.markReviewed(ids: ids(proposal), in: h1, now: phoneNow))
        XCTAssertTrue(OwnEdit.isOwn(from: h2, to: undone), "the undo arrives as the owner's")
    }
}
