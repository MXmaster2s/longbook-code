// Renaming a tag: the registry entry takes the new word, every row wearing it follows,
// the owner's groups follow, and a name already in use is refused.
import XCTest
@testable import LongbookCore

final class TagRenameTests: XCTestCase {
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
                ["id": "t1", "kind": "commitment", "name": "Househelps", "name_key": "househelps", "is_default": true],
                ["id": "t2", "kind": "commitment", "name": "streaming", "name_key": "streaming"],
                ["id": "t3", "kind": "member", "name": "Househelps", "name_key": "househelps"],
            ],
            "groups": [
                ["id": "g1", "kind": "tag", "name": "Home", "name_key": "home", "tag_keys": ["househelps", "streaming"]],
            ],
        ]
    }

    private func rows(_ vault: [String: Any], _ key: String) -> [[String: Any]] {
        vault[key] as? [[String: Any]] ?? []
    }

    func testRenamesDefAndCarriesWearers() throws {
        let result = try VaultPatch.renameTag(
            kind: "commitment", from: "Househelps", to: "Household help", in: vault(), now: now
        )
        XCTAssertEqual(result.moved, 1)

        let tags = rows(result.vault, "tags")
        let renamed = tags.first { $0["id"] as? String == "t1" }
        XCTAssertEqual(renamed?["name"] as? String, "Household help")
        XCTAssertEqual(renamed?["name_key"] as? String, "household help")
        // The owner's own word, not the library's seed, once they have changed it.
        XCTAssertEqual(renamed?["is_default"] as? Bool, false)

        let commitments = rows(result.vault, "commitments")
        XCTAssertEqual(commitments.first { $0["id"] as? String == "s1" }?["tag"] as? String, "Household help")
        // A row of another kind sharing the name is a different tag and never moves.
        XCTAssertEqual(tags.first { $0["id"] as? String == "t3" }?["name"] as? String, "Househelps")
        // Untouched rows stay untouched, unknown fields included.
        let netflix = commitments.first { $0["id"] as? String == "s2" }
        XCTAssertEqual(netflix?["tag"] as? String, "streaming")
        XCTAssertEqual(commitments.first { $0["id"] as? String == "s1" }?["future_field"] as? String, "must survive")
    }

    func testCarriesTheOwnersGroups() throws {
        let result = try VaultPatch.renameTag(
            kind: "commitment", from: "Househelps", to: "Household help", in: vault(), now: now
        )
        let keys = rows(result.vault, "groups").first?["tag_keys"] as? [String]
        XCTAssertEqual(keys, ["household help", "streaming"])
    }

    func testRefusesANameAlreadyInUse() {
        XCTAssertThrowsError(
            try VaultPatch.renameTag(kind: "commitment", from: "Househelps", to: "Streaming", in: vault(), now: now)
        )
    }

    /// The new name is written onto every row wearing the tag, so it meets the scan a note meets,
    /// on every kind — before the twin check, whose refusal would repeat it. Nothing moves.
    func testANewNameMeetsTheSecretScan() throws {
        var raw = vault()
        var tags = rows(raw, "tags")
        tags.append(["id": "t4", "kind": "commitment", "name": "pin: 4821", "name_key": "pin: 4821"])
        raw["tags"] = tags
        let refused: [(kind: String, from: String, to: String)] = [
            ("commitment", "Househelps", "pin: 4821"),
            ("commitment", "streaming", "Visa 4111 1111 1111 1111"),
            ("member", "Househelps", "cook 4111111111111111"),
        ]
        for (kind, from, to) in refused {
            XCTAssertThrowsError(try VaultPatch.renameTag(kind: kind, from: from, to: to, in: raw, now: now), to) { error in
                XCTAssertTrue(error.friendlyDescription.hasPrefix(dataPolicyRefusal), to)
            }
        }
        let renamed = try VaultPatch.renameTag(kind: "member", from: "Househelps", to: "household help", in: raw, now: now)
        XCTAssertEqual(rows(renamed.vault, "tags").first { $0["id"] as? String == "t3" }?["name"] as? String,
                       "household help", "a clean name still renames")
    }

    func testRefusesAnEmptyName() {
        XCTAssertThrowsError(
            try VaultPatch.renameTag(kind: "commitment", from: "Househelps", to: "   ", in: vault(), now: now)
        )
    }

    func testCaseOnlyRenameIsAllowed() throws {
        let result = try VaultPatch.renameTag(
            kind: "commitment", from: "Househelps", to: "HOUSEHELPS", in: vault(), now: now
        )
        XCTAssertEqual(result.moved, 1)
        XCTAssertEqual(rows(result.vault, "commitments").first { $0["id"] as? String == "s1" }?["tag"] as? String, "HOUSEHELPS")
    }

    /// A category can exist only as the word rows wear — an AI writing the vault need
    /// never register it. Those rows are carried too.
    func testRenamesRowsWhenTheRegistryHasNoEntry() throws {
        var raw = vault()
        raw["tags"] = [[String: Any]]()
        let result = try VaultPatch.renameTag(
            kind: "commitment", from: "Househelps", to: "Household help", in: raw, now: now
        )
        XCTAssertEqual(result.moved, 1)
        let commitments = rows(result.vault, "commitments")
        XCTAssertEqual(commitments.first { $0["id"] as? String == "s1" }?["tag"] as? String, "Household help")
    }

    func testUnknownTagChangesNothing() throws {
        let result = try VaultPatch.renameTag(
            kind: "commitment", from: "Nope", to: "Something", in: vault(), now: now
        )
        XCTAssertEqual(result.moved, 0)
        XCTAssertEqual(rows(result.vault, "tags").count, 3)
    }

    func testRemovingATagTheRegistryNeverKnewStillUntagsTheRows() throws {
        var base = vault()
        base["tags"] = []
        let result = VaultPatch.removeTag(kind: "commitment", named: "Househelps", in: base, now: now)
        XCTAssertEqual(result.cleared, 1)
        let commitments = rows(result.vault, "commitments")
        XCTAssertTrue(commitments.first { $0["id"] as? String == "s1" }?["tag"] is NSNull)
        XCTAssertEqual(commitments.first { $0["id"] as? String == "s2" }?["tag"] as? String, "streaming")
    }
}
