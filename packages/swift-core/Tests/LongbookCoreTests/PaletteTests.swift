// Identity ranks must agree with core, or a category is one colour on the Mac and another on
// the phone. Mirrors packages/core/src/domain/avatar.ts. Rank-to-colour (Theme.dataInk) is
// tested where Theme lives, not here — this file owns only the ordering half of the seam.
import XCTest
@testable import LongbookCore

final class PaletteTests: XCTestCase {
    private func sub(tag: String?) throws -> Subscription {
        var d: [String: Any] = [
            "id": "x", "name": "X", "amount": 1, "currency": "INR",
            "billing_cycle": "monthly", "next_due_date": "2026-08-01", "status": "active", "has_trial": false,
        ]
        if let tag { d["tag"] = tag }
        return try JSONDecoder().decode(Subscription.self, from: JSONSerialization.data(withJSONObject: d))
    }

    // MARK: - categories: alphabetical, deduped, blank folds out

    func testCategoriesRankAlphabeticallyOverNormalisedName() throws {
        let subs = [
            try sub(tag: "Software"),
            try sub(tag: "AI subscription"),
            try sub(tag: "Fitness"),
            try sub(tag: "software"),        // same as "Software" once normalised
        ]
        let p = VaultPalette.categories(subs)
        XCTAssertEqual(p.rank("AI subscription"), 0, "ai < fitness < software")
        XCTAssertEqual(p.rank("Fitness"), 1)
        XCTAssertEqual(p.rank("Software"), 2)
        XCTAssertEqual(p.rank("software"), 2, "case/space-insensitive: one rank, not two")
    }

    func testABlankCategoryIsNotACategory() throws {
        let p = VaultPalette.categories([try sub(tag: "  "), try sub(tag: nil), try sub(tag: "Bills")])
        XCTAssertNil(p.rank("   "), "whitespace-only is an absence, ranks nil")
        XCTAssertNil(p.rank(nil))
        XCTAssertEqual(p.rank("Bills"), 0, "the one real category ranks first")
    }

    // MARK: - members/methods: by when added, keyed by id

    func testEntitiesRankByCreationTimeThenId() {
        let rows: [(id: String, createdAt: String?)] = [
            ("c", "2026-07-03T10:00:00Z"),
            ("a", "2026-07-01T10:00:00Z"),
            ("b", "2026-07-02T10:00:00Z"),
        ]
        let p = VaultPalette.entities(rows)
        XCTAssertEqual(p.rank("a"), 0, "added first")
        XCTAssertEqual(p.rank("b"), 1)
        XCTAssertEqual(p.rank("c"), 2)
    }

    func testEntitiesKeyByIdSoRenamingDoesNotReshuffleColours() {
        // Same rows, ranks follow the id, not any name — there is no name here, which is the point.
        let p = VaultPalette.entities([("m1", "2026-07-01T10:00:00Z"), ("m2", "2026-07-02T10:00:00Z")])
        XCTAssertEqual(p.rank("m1"), 0)
        XCTAssertEqual(p.rank("m2"), 1)
        XCTAssertNil(p.rank("m3"), "an id not in the vault has no rank")
    }

    func testAMissingTimestampSortsAsEpochZero() {
        // Matches core's NaN → 0: the undated row ranks before a real 2026 date.
        let p = VaultPalette.entities([("dated", "2026-07-01T10:00:00Z"), ("undated", nil)])
        XCTAssertEqual(p.rank("undated"), 0)
        XCTAssertEqual(p.rank("dated"), 1)
    }

    func testRowsInUseRankAheadOfUnusedOnes() {
        let rows: [(id: String, createdAt: String?)] = [
            ("old-unused", "2026-07-01T10:00:00Z"),
            ("used-late", "2026-07-03T10:00:00Z"),
            ("used-early", "2026-07-02T10:00:00Z"),
        ]
        let p = VaultPalette.entities(rows, inUse: ["used-late", "used-early"])
        XCTAssertEqual(p.rank("used-early"), 0, "used, added first")
        XCTAssertEqual(p.rank("used-late"), 1)
        XCTAssertEqual(p.rank("old-unused"), 2, "unused rows come after every used one")
    }
}
