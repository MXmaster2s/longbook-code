// The payload guard: "we only hold your structure" is a CI-enforced property, not a
// sentence. A payload built from a vault full of sensitive values must contain the tag
// definitions and nothing else — fail here and the promise broke.
import XCTest
@testable import LongbookCore

final class StructureSyncTests: XCTestCase {
    /// A vault whose VALUES are all sentinels — if any sentinel appears in the payload,
    /// data leaked into the structure store.
    private func sensitiveVault() -> Vault {
        Vault(
            app: "longbook", version: 3,
            subscriptions: [
                Subscription(
                    id: "SENSITIVE-ID", name: "SENSITIVE-NETFLIX", amount: 98765,
                    currency: "INR", billingCycle: .monthly,
                    tag: "insurance", notes: "SENSITIVE-NOTE", status: .active,
                    details: ["insurer": .string("SENSITIVE-INSURER"), "sum_assured": .number(5_000_000)]
                ),
            ],
            familyMembers: [
                FamilyMember(id: "m1", name: "SENSITIVE-PERSON", nameKey: "sensitive-person",
                             email: "SENSITIVE@EXAMPLE.COM", tag: "family"),
            ],
            paymentMethods: [
                PaymentMethod(id: "p1", name: "SENSITIVE-VISA", nameKey: "sensitive-visa",
                              tag: "credit card", last4: "9292"),
            ],
            tags: [
                TagDef(id: "t1", kind: "commitment", name: "insurance", nameKey: "insurance",
                       icon: "shield.checkered", isDefault: true, sort: 0, createdAt: "2026-08-18"),
                TagDef(id: "t2", kind: "member", name: "family", nameKey: "family",
                       icon: nil, isDefault: false, sort: 1, createdAt: nil),
            ]
        )
    }

    func testPayloadCarriesDefinitionsOnly() throws {
        let rows = StructureSync.payload(from: sensitiveVault())
        XCTAssertEqual(rows.count, 2, "one row per registry entry, nothing per data row")

        let bytes = try JSONEncoder().encode(rows)
        let serialized = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(serialized.contains("SENSITIVE"), "no value from any data row may travel")
        XCTAssertFalse(serialized.contains("98765"), "no amount may travel")
        XCTAssertFalse(serialized.contains("9292"), "no digits of any account may travel")
        XCTAssertFalse(serialized.contains("2026-09-01"), "no date from any data row may travel")
    }

    func testPayloadKeysAreExactlyTheAllowedSet() throws {
        let rows = StructureSync.payload(from: sensitiveVault())
        let bytes = try JSONEncoder().encode(rows)
        let decoded = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]])
        let allowed: Set<String> = ["kind", "name", "name_key", "icon", "source"]
        for row in decoded {
            XCTAssertTrue(Set(row.keys).isSubset(of: allowed), "unexpected keys: \(Set(row.keys).subtracting(allowed))")
        }
    }

    /// No tag syncs a template, whatever its kind and whatever its entry in the file holds.
    func testNoTemplateTravelsFromAnyKindOfTag() throws {
        let json = """
        {"app":"longbook","version":3,"commitments":[],
         "tags":[
          {"id":"t1","kind":"commitment","name":"insurance","name_key":"insurance",
           "template":[{"key":"insurer","label":"Insurer","hint":"text"}]},
          {"id":"t2","kind":"account","name":"credit card","name_key":"credit card","is_default":true,
           "template":[{"key":"card_name","label":"Card name","hint":"text"}]},
          {"id":"t3","kind":"member","name":"family","name_key":"family",
           "template":[{"key":"relationship","label":"Relationship","hint":"text"}]}]}
        """
        let vault = try JSONDecoder().decode(Vault.self, from: Data(json.utf8))
        let rows = StructureSync.payload(from: vault)
        XCTAssertEqual(rows.map(\.name_key), ["insurance", "credit card", "family"])
        let serialized = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
        XCTAssertFalse(serialized.contains("template"), serialized)
    }

    func testLibraryAndOwnerProvenanceAreDistinguished() {
        let rows = StructureSync.payload(from: sensitiveVault())
        XCTAssertEqual(rows.first { $0.name_key == "insurance" }?.source, "library")
        XCTAssertEqual(rows.first { $0.name_key == "family" }?.source, "user")
    }

    func testAnEmptyRegistrySyncsNothing() {
        let vault = Vault(app: "longbook", version: 2, subscriptions: [])
        XCTAssertTrue(StructureSync.payload(from: vault).isEmpty)
    }
}
