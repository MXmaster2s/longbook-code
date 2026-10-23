// A tag groups categories for totals, so the rules that matter are: it matches the way the
// rest of the vault matches names, it never invents a bucket, and it never double-counts.
import XCTest
@testable import LongbookCore

final class CategoryTagTests: XCTestCase {
    private func group(
        _ id: String, _ kind: String, _ name: String, sort: Int? = nil, categories: [String]? = nil
    ) -> VaultGroup {
        VaultGroup(
            id: id, kind: kind, name: name, nameKey: nameKey(name), icon: nil, sort: sort,
            accountIds: nil, memberIds: nil, tagKeys: categories
        )
    }

    func testTagMatchesOnTheNormalisedCategoryName() {
        let tags = CategoryTags([group("1", "tag", "Business", categories: ["software", "domains"])])
        XCTAssertEqual(tags.tag(for: "Software"), "Business")
        XCTAssertEqual(tags.tag(for: "  DOMAINS "), "Business")
    }

    func testAnUntaggedCategoryStaysUntagged() {
        let tags = CategoryTags([group("1", "tag", "Business", categories: ["software"])])
        XCTAssertNil(tags.tag(for: "Groceries"))
        XCTAssertNil(tags.tag(for: nil))
        XCTAssertNil(tags.tag(for: "   "))
    }

    func testOtherKindsOfGroupAreNotTags() {
        let tags = CategoryTags([
            group("1", "payment", "Cards"),
            group("2", "shared_access", "Household"),
            group("3", "something_new", "Whatever", categories: ["software"]),
        ])
        XCTAssertTrue(tags.isEmpty)
        XCTAssertNil(tags.tag(for: "software"))
    }

    func testACategoryClaimedTwiceKeepsTheFirstTag() {
        let tags = CategoryTags([
            group("2", "tag", "Household", sort: 2, categories: ["software"]),
            group("1", "tag", "Business", sort: 1, categories: ["software"]),
        ])
        XCTAssertEqual(tags.tag(for: "software"), "Business")
        XCTAssertEqual(tags.order, ["Business", "Household"])
    }

    func testAnEmptyTagIsNotListed() {
        let tags = CategoryTags([group("1", "tag", "Business", categories: [])])
        XCTAssertTrue(tags.isEmpty)
        XCTAssertTrue(tags.order.isEmpty)
    }

    func testGroupsSurviveTheVaultDecodeTheyAreReadFrom() throws {
        let json = """
        {"app":"longbook","version":3,"commitments":[],"members":[],"accounts":[],
         "groups":[{"id":"1","kind":"tag","name":"Business","name_key":"business",
         "tag_keys":["software"]}]}
        """
        let vault = try JSONDecoder().decode(Vault.self, from: Data(json.utf8))
        XCTAssertEqual(CategoryTags(vault.groups).tag(for: "software"), "Business")
    }
}
