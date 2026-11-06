// Deleting a tag: the registry entry goes, every row wearing it is untagged and
// stamped, and nothing else on those rows moves.
import XCTest
@testable import LongbookCore

final class TagRemovalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    private func vault() -> [String: Any] {
        [
            "app": "longbook",
            "version": 2,
            "commitments": [
                [
                    "id": "s1", "name": "Maid", "amount": 9000.0, "currency": "INR",
                    "billing_cycle": "monthly", "next_due_date": "2026-09-01", "status": "active",
                    "tag": "Househelps", "future_field": "must survive",
                ],
                [
                    "id": "s2", "name": "Netflix", "amount": 649.0, "currency": "INR",
                    "billing_cycle": "monthly", "next_due_date": "2026-08-25", "status": "active",
                    "tag": "streaming",
                ],
            ],
            "tags": [
                ["id": "t1", "kind": "commitment", "name": "Househelps", "name_key": "househelps"],
                ["id": "t2", "kind": "member", "name": "Househelps", "name_key": "househelps"],
            ],
        ]
    }

    private func rows(_ vault: [String: Any], _ key: String) -> [[String: Any]] {
        vault[key] as? [[String: Any]] ?? []
    }

    func testRemovesDefAndUntagsWearers() {
        let result = VaultPatch.removeTag(kind: "commitment", named: "Househelps", in: vault(), now: now)
        XCTAssertEqual(result.cleared, 1)
        let tags = rows(result.vault, "tags")
        XCTAssertEqual(tags.map { $0["id"] as? String }, ["t2"], "only the commitment-kind def goes")
        let s1 = rows(result.vault, "commitments")[0]
        XCTAssertTrue(s1["tag"] is NSNull, "the row is untagged, not dropped")
        XCTAssertEqual(s1["future_field"] as? String, "must survive")
        XCTAssertNotNil(s1["updated_at"])
        let prov = result.vault["_provenance"] as? [String: Any]
        XCTAssertNotNil(prov?["s1"], "the untagging is attributed")
        XCTAssertEqual(rows(result.vault, "commitments")[1]["tag"] as? String, "streaming")
    }

    func testMatchesByNameKeyNotSpelling() {
        let result = VaultPatch.removeTag(kind: "commitment", named: "  HOUSEHELPS ", in: vault(), now: now)
        XCTAssertEqual(result.cleared, 1)
    }

    func testAWornNameTheRegistryNeverKnewStillComesOff() {
        // An AI-written vault may tag rows without registering the word. Deleting it
        // must still carry the rows — the registry entry was never the point.
        let result = VaultPatch.removeTag(kind: "commitment", named: "streaming", in: vault(), now: now)
        XCTAssertEqual(result.cleared, 1)
        XCTAssertEqual(rows(result.vault, "tags").count, 2, "no registry def existed to remove")
        XCTAssertTrue(rows(result.vault, "commitments")[1]["tag"] is NSNull)
        let prov = result.vault["_provenance"] as? [String: Any]
        XCTAssertNotNil(prov?["s2"], "the untagging is attributed")
    }
}
