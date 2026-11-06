// No tag of any kind carries a template — in the shipped library, in a vault that still holds
// one whatever its shape, and as the writer registers a worn tag.
import XCTest
@testable import LongbookCore

final class TagTemplateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    func testTheShippedLibraryHoldsNoTemplateOfAnyKind() throws {
        let data = try XCTUnwrap(VaultContract.bundledFiles()[VaultReader.libraryFile])
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(root["tags"] as? [[String: Any]])
        XCTAssertEqual(Set(rows.compactMap { $0["kind"] as? String }), ["commitment", "member", "account"])
        XCTAssertEqual(rows.filter { $0["template"] != nil }.compactMap { $0["name"] as? String }, [])
        XCTAssertEqual(TagLibrary.entry(kind: "account", name: "Credit Card")?.icon, "creditcard.fill", "a tag keeps its icon")
        XCTAssertEqual(TagLibrary.entry(kind: "member", name: "family")?.icon, "person.2")
    }

    func testATemplateAVaultHoldsReadsAsNoneOnEveryKindWhateverItsShape() throws {
        let json = """
        {"app":"longbook","version":3,"commitments":[],
         "tags":[
          {"id":"t1","kind":"commitment","name":"insurance","name_key":"insurance","icon":"shield.checkered",
           "template":[{"key":"insurer","label":"Insurer","hint":"text"}]},
          {"id":"t2","kind":"account","name":"credit card","name_key":"credit card","icon":"creditcard.fill",
           "template":"not a list of fields"},
          {"id":"t3","kind":"member","name":"family","name_key":"family",
           "template":[{"key":"relationship"}]}]}
        """
        let tags = try XCTUnwrap(try JSONDecoder().decode(Vault.self, from: Data(json.utf8)).tags)
        XCTAssertEqual(tags.map(\.kind), ["commitment", "account", "member"], "every entry reads")
        XCTAssertEqual(tags.first { $0.kind == "account" }?.icon, "creditcard.fill", "the rest of the entry reads as before")
        // Written back out, an entry is its name and its icon: the read model holds no template.
        let encoded = String(decoding: try JSONEncoder().encode(tags), as: UTF8.self)
        XCTAssertFalse(encoded.contains("template"), encoded)
    }

    func testAWornTagOfAnyKindRegistersWithNoTemplate() throws {
        let raw: [String: Any] = ["app": "longbook", "version": 3, "commitments": [[String: Any]]()]
        var vault = VaultPatch.ensureTag(kind: "commitment", named: "Insurance", in: raw, now: now)
        vault = VaultPatch.ensureTag(kind: "account", named: "credit card", in: vault, now: now)
        vault = VaultPatch.ensureTag(kind: "member", named: "Family", in: vault, now: now)
        let tags = try XCTUnwrap(vault["tags"] as? [[String: Any]])
        XCTAssertEqual(tags.compactMap { $0["kind"] as? String }, ["commitment", "account", "member"])
        for tag in tags {
            let name = tag["name"] as? String ?? ""
            XCTAssertNil(tag["template"], "\(name) registers with no template")
            XCTAssertEqual(tag["is_default"] as? Bool, true, name)
            XCTAssertNotNil(tag["icon"] as? String, "\(name) registers with its icon")
        }
    }
}
