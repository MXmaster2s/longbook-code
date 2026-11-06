// Setup's people and accounts kept as hints beside the commitments waiting in to_fill_in,
// and the star on a person or an account: read, written by the app, and set by a proposal.
import XCTest
@testable import LongbookCore

final class HintsAndStarsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    private func json(_ object: [String: Any]) -> [String: Any] {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func decode(_ raw: [String: Any]) throws -> Vault {
        try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func seeded() -> [String: Any] {
        json([
            "app": "longbook", "version": 3, "commitments": [],
            "members": [["id": "m-self", "name": "Self", "name_key": "self"]],
            "accounts": [["id": "a-hdfc", "name": "HDFC savings", "name_key": "hdfc savings"]],
        ])
    }

    func testHintsReadLossilyAndNeverBecomeMembersOrAccounts() throws {
        var raw = seeded()
        raw["hints"] = [
            ["id": "h1", "name": "Cook", "kind": "member", "tag": "Cook"],
            ["id": "h2", "name": "Credit card", "kind": "account", "tag": "credit card"],
            ["id": "h3", "name": "Nobody", "kind": "pet"],
            ["id": "h4", "name": " ", "kind": "member"],
            ["name": "No id", "kind": "account"],
        ]
        let vault = try decode(json(raw))
        XCTAssertEqual(vault.hints, [
            SetupHint(id: "h1", name: "Cook", kind: .member, tag: "Cook"),
            SetupHint(id: "h2", name: "Credit card", kind: .account, tag: "credit card"),
        ])
        XCTAssertEqual(vault.familyMembers.map(\.name), ["Self"])
        XCTAssertEqual(vault.paymentMethods.map(\.name), ["HDFC savings"])
    }

    func testSetHintsWritesTheListWholeAndAnEmptyListLeavesNoKey() throws {
        let hints = [SetupHint(id: "h1", name: "Driver", kind: .member, tag: "Driver"),
                     SetupHint(id: "h2", name: "Savings account", kind: .account, tag: "bank account")]
        let written = VaultPatch.setHints(hints, in: seeded())
        XCTAssertEqual(try decode(json(written)).hints, hints)
        XCTAssertEqual((written["members"] as? [[String: Any]])?.count, 1, "a hint adds no person")
        XCTAssertEqual((written["accounts"] as? [[String: Any]])?.count, 1, "a hint adds no account")
        XCTAssertNil(VaultPatch.setHints([], in: written)["hints"])
    }

    func testAStarIsWrittenOnlyWhileSet() throws {
        let starred = try VaultPatch.setEntityDetails(.paymentMethod, id: "a-hdfc", in: seeded(), now: now, starred: true)
        XCTAssertEqual(try decode(json(starred)).paymentMethods.first?.isStarred, true)
        XCTAssertEqual((starred["accounts"] as? [[String: Any]])?.first?["starred"] as? Bool, true)
        let person = try VaultPatch.setEntityDetails(.familyMember, id: "m-self", in: starred, now: now, starred: true)
        XCTAssertEqual(try decode(json(person)).familyMembers.first?.isStarred, true)
        let off = try VaultPatch.setEntityDetails(.paymentMethod, id: "a-hdfc", in: person, now: now, starred: false)
        XCTAssertNil((off["accounts"] as? [[String: Any]])?.first?["starred"], "off leaves no key")
        XCTAssertEqual(try decode(json(off)).paymentMethods.first?.isStarred, false)
    }

    func testAProposalStarsAndUnstarsAndRefusesAnythingButOnOrOff() throws {
        func write(_ kind: String, _ payload: [String: Any]) -> PendingWrite {
            PendingWrite(id: UUID(), kind: kind, payload: json(payload), sourceRef: nil, keyName: "claude")
        }
        guard case .vault(let starred) = try PendingApply.apply(
            write("update_account", ["id": "a-hdfc", "set": ["starred": true]]), to: seeded(), now: now
        ) else { return XCTFail("a vault outcome") }
        XCTAssertEqual((starred["accounts"] as? [[String: Any]])?.first?["starred"] as? Bool, true)
        guard case .vault(let person) = try PendingApply.apply(
            write("update_person", ["name": "self", "set": ["starred": true]]), to: starred, now: now
        ) else { return XCTFail("a vault outcome") }
        XCTAssertEqual((person["members"] as? [[String: Any]])?.first?["starred"] as? Bool, true)
        guard case .vault(let off) = try PendingApply.apply(
            write("update_person", ["id": "m-self", "set": ["starred": false]]), to: person, now: now
        ) else { return XCTFail("a vault outcome") }
        XCTAssertNil((off["members"] as? [[String: Any]])?.first?["starred"])
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-hdfc", "set": ["starred": 1]]), to: seeded(), now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-hdfc", "set": ["starred": "yes"]]), to: seeded(), now: now))
    }
}
