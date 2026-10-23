// The decision every reload makes when the file has changed: adopt, review, or wait for
// a base iCloud still holds elsewhere. Pure, so the whole table is pinned here, and the
// owner's hang is rehearsed end to end without the app. Every fixture is SYNTHETIC.
import XCTest
@testable import LongbookCore

final class ReviewVerdictTests: XCTestCase {
    private typealias Base = VaultHistory.BaseState

    private func verdict(ours: Bool, review: Bool = false, base: Base, synced: Bool = false, unchanged: Bool = false) -> VaultHistory.Verdict {
        VaultHistory.verdict(ours: ours, hasOpenReview: review, base: base, synced: synced, unchanged: unchanged)
    }

    // MARK: - the base is still arriving

    func testAnOwnWriteWithNoOpenReviewNeedsNoBase() {
        XCTAssertEqual(verdict(ours: true, base: .arriving), .adopt, "Mark paid never reads history")
    }

    func testAnOutsideChangeWhoseBaseIsArrivingWaits() {
        XCTAssertEqual(verdict(ours: false, base: .arriving), .wait)
    }

    func testInsideAReviewAnArrivingBaseWaitsWhoeverWrote() {
        XCTAssertEqual(verdict(ours: false, review: true, base: .arriving), .wait)
        XCTAssertEqual(verdict(ours: true, review: true, base: .arriving), .wait)
    }

    // MARK: - the base is gone

    func testAMissingBaseAdoptsAsAPrunedOneAlwaysHas() {
        XCTAssertEqual(verdict(ours: false, base: .missing), .adopt)
        XCTAssertEqual(verdict(ours: true, base: .missing), .adopt)
    }

    func testAMissingBaseInsideAReviewLeavesTheReviewStanding() {
        XCTAssertEqual(verdict(ours: false, review: true, base: .missing), .review)
        XCTAssertEqual(verdict(ours: true, review: true, base: .missing), .review)
    }

    // MARK: - the base is here

    func testAnOwnWriteAdopts() {
        XCTAssertEqual(verdict(ours: true, base: .bytes), .adopt)
    }

    func testAnOutsideChangeOpensAReview() {
        XCTAssertEqual(verdict(ours: false, base: .bytes), .review)
        XCTAssertEqual(verdict(ours: false, review: true, base: .bytes), .review, "and stays open")
    }

    func testTheOtherDevicesSignedWriteAdoptsAndClosesAReview() {
        XCTAssertEqual(verdict(ours: false, base: .bytes, synced: true), .adopt)
        XCTAssertEqual(verdict(ours: false, review: true, base: .bytes, synced: true), .adopt)
    }

    func testAVersionThatMovesNoRowAdoptsAndClosesAReview() {
        XCTAssertEqual(verdict(ours: false, base: .bytes, unchanged: true), .adopt)
        XCTAssertEqual(verdict(ours: true, review: true, base: .bytes, unchanged: true), .adopt)
    }

    func testAnOwnEditInsideAReviewKeepsTheReviewOpen() {
        XCTAssertEqual(verdict(ours: true, review: true, base: .bytes), .review)
    }

    // MARK: - the owner's afternoon, rehearsed

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("verdict-rehearsal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        VaultHistory.mirrorRoot = folder.appendingPathComponent("mirror")
    }

    override func tearDownWithError() throws {
        VaultHistory.awaitingDownload = VaultReader.awaitingDownload
        try? FileManager.default.removeItem(at: folder)
    }

    private func vault(subs: [[String: Any]], signed: [String: Any]) -> [String: Any] {
        ["app": "longbook", "version": 3, "commitments": subs, "_provenance": signed]
    }

    private func bytes(_ raw: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
    }

    /// The model's reading of the base, as noticeChange gathers it: never a blocking read.
    private func judge(seen: String, raw: [String: Any], ours: Bool, review: Bool, waitedFor: String?) -> VaultHistory.Verdict {
        var base: [String: Any]?
        var state = Base.missing
        if !ours || review {
            if waitedFor != seen, VaultHistory.awaiting(hash: seen, in: folder) {
                state = .arriving
            } else {
                base = VaultHistory.snapshot(hash: seen, in: folder)
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                state = base == nil ? .missing : .bytes
            }
        }
        let synced = !ours && base.map { OwnEdit.isOwn(from: $0, to: raw) } == true
        let unchanged = base.map { vaultDiff(from: $0, to: raw).isEmpty } == true
        return VaultHistory.verdict(ours: ours, hasOpenReview: review, base: state, synced: synced, unchanged: unchanged)
    }

    func testAnOutsideChangeWaitsForItsBaseThenOpensAReviewOnceItLands() throws {
        // The phone wrote the base: its snapshot and log line arrived through iCloud, the
        // snapshot as a placeholder. This Mac adopted it without a local copy.
        let phoneVersion = vault(subs: [Fx.rawSub(id: "a", name: "Home Rent", amount: 42000)],
                                 signed: ["a": ["edited_by": "longbook-phone", "edited_at": "2026-10-01T08:11:30Z"]])
        let baseBytes = try bytes(phoneVersion)
        try VaultHistory.record(baseBytes, source: .ours, in: folder)
        try FileManager.default.removeItem(at: VaultHistory.mirrorDirectory(for: folder))
        let seen = VaultHistory.hash(baseBytes)
        VaultHistory.awaitingDownload = { $0.lastPathComponent == "\(seen).json" }

        // An outside hand adds a row, unsigned.
        var outside = phoneVersion
        outside["commitments"] = [Fx.rawSub(id: "a", name: "Home Rent", amount: 42000),
                                  Fx.rawSub(id: "b", name: "Gym", amount: 1500)]
        let outsideBytes = try bytes(outside)

        // First pass: nothing blocks, nothing is recorded, nothing moves.
        let started = Date()
        XCTAssertEqual(judge(seen: seen, raw: outside, ours: false, review: false, waitedFor: nil), .wait)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(VaultHistory.entries(in: folder).count, 1)

        // Meanwhile Mark paid on this Mac: an own write with no review open adopts at once.
        XCTAssertEqual(judge(seen: seen, raw: outside, ours: true, review: false, waitedFor: seen), .adopt)

        // The base lands: the same facts now open the review, recorded as an outside edit.
        VaultHistory.awaitingDownload = VaultReader.awaitingDownload
        XCTAssertEqual(judge(seen: seen, raw: outside, ours: false, review: false, waitedFor: seen), .review)
        let entry = try XCTUnwrap(VaultHistory.record(outsideBytes, source: .outside, in: folder))
        XCTAssertEqual(VaultHistory.entries(in: folder).map(\.source), [.outside, .ours])
        XCTAssertEqual(VaultHistory.snapshot(hash: seen, in: folder), baseBytes, "the review's base reads back")
        XCTAssertEqual(VaultHistory.snapshot(hash: entry.hash, in: folder), outsideBytes)
    }

    func testABaseThatNeverLandsIsAdoptedOnTheSecondPassNotWaitedForAgain() throws {
        let baseBytes = try bytes(vault(subs: [Fx.rawSub(id: "a", name: "Home Rent", amount: 42000)], signed: [:]))
        try VaultHistory.record(baseBytes, source: .ours, in: folder)
        try FileManager.default.removeItem(at: VaultHistory.mirrorDirectory(for: folder))
        let seen = VaultHistory.hash(baseBytes)
        VaultHistory.awaitingDownload = { $0.lastPathComponent == "\(seen).json" }
        let outside = vault(subs: [Fx.rawSub(id: "b", name: "Gym", amount: 1500)], signed: [:])

        XCTAssertEqual(judge(seen: seen, raw: outside, ours: false, review: false, waitedFor: nil), .wait)
        // The thirty seconds passed and the file is still elsewhere: adopted as a pruned
        // base always was, so the app cannot loop on it.
        XCTAssertEqual(judge(seen: seen, raw: outside, ours: false, review: false, waitedFor: seen), .adopt)
    }

    func testTheOtherDevicesSignedWriteStillPassesOnceItsBaseLands() throws {
        let earlier = vault(subs: [Fx.rawSub(id: "a", name: "Home Rent", amount: 42000)],
                            signed: ["a": ["edited_by": "longbook-mac", "edited_at": "2026-09-01T08:00:00Z"]])
        let baseBytes = try bytes(earlier)
        try VaultHistory.record(baseBytes, source: .ours, in: folder)
        let seen = VaultHistory.hash(baseBytes)
        // Recorded here, so the mirror holds it: iCloud's state of the shared copy is moot.
        VaultHistory.awaitingDownload = { $0.lastPathComponent == "\(seen).json" }
        let phone = vault(subs: [Fx.rawSub(id: "a", name: "Home Rent", amount: 42000), Fx.rawSub(id: "b", name: "Gym", amount: 1500)],
                          signed: ["a": ["edited_by": "longbook-mac", "edited_at": "2026-09-01T08:00:00Z"],
                                   "b": ["edited_by": "longbook-phone", "edited_at": "2026-10-01T08:11:30Z"]])
        XCTAssertEqual(judge(seen: seen, raw: phone, ours: false, review: false, waitedFor: nil), .adopt)
    }
}
