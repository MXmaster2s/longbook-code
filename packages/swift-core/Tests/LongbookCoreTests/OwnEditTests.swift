// The rule that lets a write from the owner's other device pass without review: every
// touched row freshly signed by the app itself, by exact name. Every fixture is SYNTHETIC.
import XCTest
@testable import LongbookCore

final class OwnEditTests: XCTestCase {
    private let earlier = "2026-09-01T08:00:00Z"
    private let fresh = "2026-09-30T10:00:00Z"
    private let later = "2026-10-02T10:00:00Z"

    private func stamp(_ by: String, at: String) -> [String: Any] {
        ["edited_by": by, "edited_at": at]
    }

    private func vault(
        subs: [[String: Any]], charges: [[String: Any]] = [], tags: [[String: Any]] = [],
        signed: [String: Any] = [:]
    ) -> [String: Any] {
        var out: [String: Any] = ["app": "longbook", "version": 3, "commitments": subs]
        if !charges.isEmpty { out["charges"] = charges }
        if !tags.isEmpty { out["tags"] = tags }
        if !signed.isEmpty { out["_provenance"] = signed }
        return out
    }

    private func netflix(amount: Double = 649) -> [String: Any] { Fx.rawSub(id: "a", name: "Netflix", amount: amount) }
    private func water() -> [String: Any] { Fx.rawSub(id: "b", name: "Water can", amount: 400) }
    private let waterTag: [String: Any] = ["id": "t1", "kind": "commitment", "name": "Household", "name_key": "household"]

    /// Where every case starts: one commitment the app signed a month ago, with two planned charges.
    private func base() -> [String: Any] {
        vault(subs: [netflix()],
              charges: [Fx.rawRow("a", "2026-10-01", amount: 649), Fx.rawRow("a", "2026-11-01", amount: 649)],
              signed: ["a": stamp("longbook-phone", at: earlier)])
    }

    private func added(by name: String, tags: [[String: Any]] = []) -> [String: Any] {
        vault(subs: [netflix(), water()],
              charges: [Fx.rawRow("a", "2026-10-01", amount: 649), Fx.rawRow("a", "2026-11-01", amount: 649)],
              tags: tags,
              signed: ["a": stamp("longbook-phone", at: earlier), "b": stamp(name, at: fresh)])
    }

    // MARK: - the owner's own

    func testARowAddedWithAFreshAppSignatureIsTheOwners() {
        for name in ["longbook-phone", "longbook-mac", "longbook-ios"] {
            XCTAssertTrue(OwnEdit.isOwn(from: base(), to: added(by: name)), name)
        }
    }

    func testANewUnsignedTagBesideAnOwnRowIsStillTheOwners() {
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: added(by: "longbook-phone", tags: [waterTag])))
    }

    func testAnAmountChangedUnderAFreshAppSignatureIsTheOwners() {
        var next = base()
        next["commitments"] = [netflix(amount: 699)]
        next["_provenance"] = ["a": stamp("longbook-phone", at: fresh)]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: next))
    }

    func testPlannedChargesDroppedUnderARestampedCommitmentAreTheOwners() {
        var next = base()
        next["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649)]
        next["_provenance"] = ["a": stamp("longbook-phone", at: fresh)]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: next), "a charge is vouched for through its commitment")
    }

    func testAChargeMarkedPaidUnderARestampedCommitmentIsTheOwners() {
        var next = base()
        next["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649, paid: true), Fx.rawRow("a", "2026-11-01", amount: 649)]
        next["_provenance"] = ["a": stamp("longbook-phone", at: fresh)]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: next))
    }

    // MARK: - a charge signed under its own key, the commitment's entry untouched

    private func chargeSigned(_ date: String, by name: String = "longbook-phone") -> [String: Any] {
        ["a": stamp("longbook-phone", at: earlier), "a@\(date)": stamp(name, at: fresh)]
    }

    func testAChargeMarkedPaidOnTheOtherDeviceArrivesAsOwn() {
        var next = base()
        next["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649, paid: true, basis: "mark_paid"), Fx.rawRow("a", "2026-11-01", amount: 649)]
        next["_provenance"] = chargeSigned("2026-10-01")
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: next), "the charge's own fresh stamp vouches for it")
    }

    func testAPlanExtendedOnTheOtherDeviceArrivesAsOwn() {
        var next = base()
        next["charges"] = (next["charges"] as? [[String: Any]] ?? []) + [Fx.rawRow("a", "2026-12-01", amount: 649)]
        next["_provenance"] = chargeSigned("2026-12-01")
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: next))
    }

    func testATrialTickedOnTheOtherDeviceArrivesAsOwn() {
        var next = base()
        next["charges"] = [Fx.rawRow("a", "2026-09-30", amount: 0, paid: true, basis: "user")] + (next["charges"] as? [[String: Any]] ?? [])
        next["_provenance"] = chargeSigned("2026-09-30")
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: next))
    }

    func testAChargeRemovedOnTheOtherDeviceArrivesAsOwnThroughItsOwnKey() {
        var next = base()
        next["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649)]
        next["_provenance"] = chargeSigned("2026-11-01")
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: next), "the entry outlives the row and vouches for its removal")
    }

    func testAChargeSignedByANameThatOnlyLooksLikeTheAppWaits() {
        for name in ["Longbook-Phone", "longbook-phone-2", "claude-daily-brief"] {
            var next = base()
            next["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649, paid: true), Fx.rawRow("a", "2026-11-01", amount: 649)]
            next["_provenance"] = chargeSigned("2026-10-01", by: name)
            XCTAssertFalse(OwnEdit.isOwn(from: base(), to: next), name)
        }
    }

    /// The AI's proposal is signed by commitment id with the key's name, and the charge it
    /// marked carries no app key: nothing in the file vouches for it as the owner's.
    func testAnAIMarkPaidAppliedThroughAProposalStillWaits() throws {
        let proposal = PendingWrite(id: UUID(), kind: "mark_paid", payload: ["id": "a", "date": "2026-10-01"], keyName: "claude-daily-brief")
        guard case .vault(let next) = try PendingApply.apply(proposal, to: base(), now: Date()) else { return XCTFail("a vault outcome") }
        XCTAssertTrue(vaultDiff(from: base(), to: next).contains { $0.kind == "charges" }, "the mark landed")
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: next))
        let signed = ProvenanceReader.map(in: next)
        XCTAssertEqual(signed["a@2026-10-01"]?.editedBy, "claude-daily-brief", "the charge's entry is the proposal's too")
        XCTAssertEqual(signed["a"]?.editedBy, "claude-daily-brief")
    }

    // MARK: - waits in Changes

    func testARowSignedByAnyoneElseWaits() {
        for name in ["claude-daily-brief", "statement import", "Siri", "bank message", "mcp", "Your AI"] {
            XCTAssertFalse(OwnEdit.isOwn(from: base(), to: added(by: name)), name)
        }
    }

    func testANameThatOnlyLooksLikeTheAppWaits() {
        for name in ["longbook-daily", "Longbook-Phone", "longbook", "longbook-phone-2"] {
            XCTAssertFalse(OwnEdit.isOwn(from: base(), to: added(by: name)), name)
        }
    }

    func testAnAmountChangedUnderAnUntouchedStampWaits() {
        var next = base()
        next["commitments"] = [netflix(amount: 699)]
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: next), "an unsigned hand edit keeps the old signature")
    }

    func testAnUnsignedAddedRowWaits() {
        var next = base()
        next["commitments"] = [netflix(), water()]
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: next))
    }

    func testAnOwnRowBesideAnAIRowWaits() {
        var next = added(by: "longbook-phone")
        next["commitments"] = [netflix(), water(), Fx.rawSub(id: "c", name: "Gym", amount: 1500)]
        next["_provenance"] = ["a": stamp("longbook-phone", at: earlier), "b": stamp("longbook-phone", at: fresh),
                               "c": stamp("claude-daily-brief", at: fresh)]
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: next), "the whole delivery waits; its own rows read You inside it")
    }

    func testARemovedCommitmentWaits() {
        let gone = vault(subs: [])
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: gone), "an unsigned delete leaves nothing to vouch for it")
        var stale = base()
        stale["commitments"] = []
        stale["charges"] = nil
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: stale), "an old entry for a gone row vouches for nothing")
    }

    // MARK: - a delete on the other device leaves tombstones

    func testADeletedCommitmentSignedAsATombstoneArrivesAsOwn() {
        let gone = vault(subs: [], signed: ["a": stamp("longbook-phone", at: fresh),
                                            "a@2026-10-01": stamp("longbook-phone", at: fresh),
                                            "a@2026-11-01": stamp("longbook-phone", at: fresh)])
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: gone), "the entries outlive the rows and vouch for the removal")
    }

    func testADeletedAccountSignedAsATombstoneArrivesAsOwn() {
        var before = base()
        before["accounts"] = [["id": "p1", "name": "HDFC", "name_key": "hdfc"]]
        var after = base()
        after["accounts"] = []
        after["_provenance"] = ["a": stamp("longbook-phone", at: earlier), "p1": stamp("longbook-phone", at: fresh)]
        XCTAssertTrue(OwnEdit.isOwn(from: before, to: after))
    }

    // MARK: - a Keep on the other device leaves a review mark

    private func marked(_ by: String, at: String, reviewedBy: String, reviewedAt: String) -> [String: Any] {
        ["edited_by": by, "edited_at": at, "reviewed_by": reviewedBy, "reviewed_at": reviewedAt]
    }

    func testARowKeptOnTheOtherDeviceArrivesAsOwn() {
        var kept = added(by: "claude-daily-brief")
        kept["_provenance"] = ["a": stamp("longbook-phone", at: earlier),
                               "b": marked("claude-daily-brief", at: fresh, reviewedBy: "longbook-phone", reviewedAt: fresh)]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: kept), "the AI wrote it, the owner kept it, the mark says so")
    }

    func testAChargeKeptOnTheOtherDeviceArrivesAsOwnThroughItsOwnKey() {
        var kept = base()
        kept["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649, paid: true), Fx.rawRow("a", "2026-11-01", amount: 649)]
        kept["_provenance"] = ["a": stamp("longbook-phone", at: earlier),
                               "a@2026-10-01": marked("claude-daily-brief", at: fresh, reviewedBy: "longbook-phone", reviewedAt: fresh)]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: kept))
    }

    func testAnUnsignedRowKeptOnTheOtherDeviceArrivesAsOwnByItsMarkAlone() {
        var kept = base()
        kept["commitments"] = [netflix(amount: 699)]
        kept["_provenance"] = ["a": ["edited_by": "longbook-phone", "edited_at": earlier,
                                     "reviewed_by": "longbook-phone", "reviewed_at": fresh]]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: kept), "the signature is the base's; the mark is new")
        var bare = base()
        bare["commitments"] = [netflix(), water()]
        bare["_provenance"] = ["a": stamp("longbook-phone", at: earlier), "b": ["reviewed_by": "longbook-phone", "reviewed_at": fresh]]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: bare), "a hand-written row nobody signed, kept in the app")
    }

    func testAReviewMarkByANameThatOnlyLooksLikeTheAppWaits() {
        for name in ["Longbook-Phone", "longbook-phone-2", "longbook", "claude-daily-brief"] {
            var kept = added(by: "claude-daily-brief")
            kept["_provenance"] = ["a": stamp("longbook-phone", at: earlier),
                                   "b": marked("claude-daily-brief", at: fresh, reviewedBy: name, reviewedAt: fresh)]
            XCTAssertFalse(OwnEdit.isOwn(from: base(), to: kept), name)
        }
    }

    func testAnOldReviewMarkDoesNotVouchForANewEdit() {
        var before = added(by: "claude-daily-brief")
        before["_provenance"] = ["a": stamp("longbook-phone", at: earlier),
                                 "b": marked("claude-daily-brief", at: earlier, reviewedBy: "longbook-phone", reviewedAt: earlier)]
        var after = before
        after["commitments"] = [netflix(), Fx.rawSub(id: "b", name: "Water can", amount: 450)]
        XCTAssertFalse(OwnEdit.isOwn(from: before, to: after), "the same mark on both sides vouches for nothing new")
    }

    /// The local server re-signs the charge key it edits, so a Keep's mark on that key never
    /// outlives the edit: a device whose base predates the Keep reviews the later edit too.
    func testAKeptChargeKeyReSignedByALaterEditWaitsOnEveryBase() {
        var kept = base()
        kept["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649, paid: true), Fx.rawRow("a", "2026-11-01", amount: 649)]
        kept["_provenance"] = ["a": stamp("longbook-phone", at: earlier),
                               "a@2026-10-01": marked("claude", at: fresh, reviewedBy: "longbook-phone", reviewedAt: fresh)]
        XCTAssertTrue(OwnEdit.isOwn(from: base(), to: kept), "the Keep's mark vouches for the mark-paid")
        var edited = kept
        edited["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 999, paid: true), Fx.rawRow("a", "2026-11-01", amount: 649)]
        edited["_provenance"] = ["a": stamp("claude", at: later), "a@2026-10-01": stamp("claude", at: later)]
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: edited), "a device whose base predates the Keep reviews the 999")
        XCTAssertFalse(OwnEdit.isOwn(from: kept, to: edited), "so does the device that kept")
    }

    func testAChargeChangedUnderAnUntouchedCommitmentWaits() {
        var next = base()
        next["charges"] = [Fx.rawRow("a", "2026-10-01", amount: 649, paid: true), Fx.rawRow("a", "2026-11-01", amount: 649)]
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: next))
    }

    func testATagsOnlyChangeWaits() {
        var next = base()
        next["tags"] = [waterTag]
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: next), "tag rows are never signed, so nothing vouches for them")
    }

    func testAnEmptyDiffIsNotAnOwnEdit() {
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: base()))
        var churn = base()
        churn["_provenance"] = ["a": stamp("longbook-phone", at: fresh)]
        XCTAssertFalse(OwnEdit.isOwn(from: base(), to: churn), "a stamp with no row behind it is not a change to adopt")
    }

    func testAFileWithNoBaseSignaturesStillQualifiesWhenFreshlySigned() {
        var old = base()
        old["_provenance"] = nil
        XCTAssertTrue(OwnEdit.isOwn(from: old, to: added(by: "longbook-phone")))
    }

    func testAChargeIdResolvesToItsCommitmentAtTheLastAt() {
        XCTAssertEqual(OwnEdit.commitmentKey("a@2026-10-01"), "a")
        XCTAssertEqual(OwnEdit.commitmentKey("x@y@2026-10-01"), "x@y")
        XCTAssertEqual(OwnEdit.commitmentKey("plain"), "plain")
    }
}
