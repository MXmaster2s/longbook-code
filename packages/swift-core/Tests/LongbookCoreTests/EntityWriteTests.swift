// Renaming and deleting an account or a person. The rule under all of it: a commitment is a
// thing that happened, so unhooking it from an entity must never remove the commitment.
import XCTest
@testable import LongbookCore

final class EntityWriteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    private func vault() -> [String: Any] {
        [
            "app": "longbook",
            "version": 3,
            "commitments": [
                [
                    "id": "s1", "name": "Grok", "amount": 20.0, "currency": "USD",
                    "billing_cycle": "monthly", "status": "active",
                    "account_id": "p1", "member_id": "m1",
                    "some_future_field": "must survive",
                ],
                [
                    "id": "s2", "name": "Gym", "amount": 1500.0, "currency": "INR",
                    "billing_cycle": "monthly", "next_due_date": "2026-08-10", "status": "cancelled",
                    "account_id": "p1",
                ],
                [
                    "id": "s3", "name": "Domain", "amount": 900.0, "currency": "INR",
                    "billing_cycle": "yearly", "next_due_date": "2027-01-10", "status": "active",
                ],
            ],
            "members": [["id": "m1", "name": "Aditi", "name_key": "aditi"]],
            "accounts": [
                ["id": "p1", "name": "HDFC current", "name_key": "hdfc current", "is_incomplete": true],
                ["id": "p2", "name": "ICICI joint", "name_key": "icici joint"],
            ],
        ]
    }

    private func rows(_ vault: [String: Any], _ key: String) -> [[String: Any]] {
        vault[key] as? [[String: Any]] ?? []
    }

    private func sub(_ vault: [String: Any], _ id: String) -> [String: Any]? {
        rows(vault, "commitments").first { $0["id"] as? String == id }
    }

    private func method(_ vault: [String: Any], _ id: String) -> [String: Any]? {
        rows(vault, "accounts").first { $0["id"] as? String == id }
    }

    private func member(_ vault: [String: Any], _ id: String) -> [String: Any]? {
        rows(vault, "members").first { $0["id"] as? String == id }
    }

    /// The base vault plus a third account, for exercising the one-level rule.
    private func vaultWithThirdMethod() -> [String: Any] {
        var made = vault()
        var methods = rows(made, "accounts")
        methods.append(["id": "p3", "name": "Amazon Pay", "name_key": "amazon pay"])
        made["accounts"] = methods
        return made
    }

    func testCountingWhatADeleteWouldLeaveBehindIncludesCancelledRows() {
        XCTAssertEqual(VaultPatch.referenceCount(.paymentMethod, id: "p1", in: vault()), 2)
        XCTAssertEqual(VaultPatch.referenceCount(.familyMember, id: "m1", in: vault()), 1)
        XCTAssertEqual(VaultPatch.referenceCount(.paymentMethod, id: "p2", in: vault()), 0)
    }

    func testRenamingKeepsTheIdSoEveryCommitmentStillPointsAtIt() throws {
        let made = try VaultPatch.renameEntity(.paymentMethod, id: "p1", to: "  HDFC Salary  ", in: vault(), now: now)
        let row = try XCTUnwrap(rows(made, "accounts").first { $0["id"] as? String == "p1" })
        XCTAssertEqual(row["name"] as? String, "HDFC Salary")
        XCTAssertEqual(row["name_key"] as? String, "hdfc salary")
        XCTAssertEqual(row["is_incomplete"] as? Bool, false)
        XCTAssertEqual(sub(made, "s1")?["account_id"] as? String, "p1")
    }

    func testRenamingOntoAnotherNameIsRefusedRatherThanQuietlyMerging() {
        XCTAssertThrowsError(try VaultPatch.renameEntity(.paymentMethod, id: "p1", to: "icici  JOINT", in: vault(), now: now))
    }

    func testRenamingToNothingIsRefused() {
        XCTAssertThrowsError(try VaultPatch.renameEntity(.familyMember, id: "m1", to: "   ", in: vault(), now: now))
    }

    /// A rename writes the new name into the file, so it meets the scan every note meets:
    /// refused in the writer's words and never repeated, not even by the twin refusal when
    /// another row already holds that name. A clean name is written.
    func testARenameMeetsTheSecretScan() throws {
        var held = vault()
        held["accounts"] = rows(held, "accounts")
            + [["id": "p9", "name": "4111 1111 1111 1111", "name_key": "4111 1111 1111 1111"]]
        for (kind, id) in [(VaultPatch.EntityKind.paymentMethod, "p1"), (.familyMember, "m1")] {
            for secret in ["4111 1111 1111 1111", "password: hunter2"] {
                XCTAssertThrowsError(try VaultPatch.renameEntity(kind, id: id, to: secret, in: held, now: now),
                                     "\(kind) \(secret)") {
                    XCTAssertTrue($0.friendlyDescription.hasPrefix(dataPolicyRefusal), $0.friendlyDescription)
                }
            }
        }
        let account = try VaultPatch.renameEntity(.paymentMethod, id: "p1", to: "HDFC Visa 4821", in: held, now: now)
        XCTAssertEqual(method(account, "p1")?["name"] as? String, "HDFC Visa 4821")
        let person = try VaultPatch.renameEntity(.familyMember, id: "m1", to: "Aditi Rao", in: held, now: now)
        XCTAssertEqual(member(person, "m1")?["name"] as? String, "Aditi Rao")
    }

    func testDeletingUnhooksItsCommitmentsButKeepsEveryOne() throws {
        let made = try VaultPatch.deleteEntity(.paymentMethod, id: "p1", in: vault(), now: now)
        XCTAssertEqual(rows(made, "accounts").count, 1)
        XCTAssertEqual(rows(made, "commitments").count, 3, "commitments survive their account")
        XCTAssertTrue(sub(made, "s1")?["account_id"] is NSNull)
        XCTAssertTrue(sub(made, "s2")?["account_id"] is NSNull)
        // The other foreign key, and fields this build doesn't model, are none of its business.
        XCTAssertEqual(sub(made, "s1")?["member_id"] as? String, "m1")
        XCTAssertEqual(sub(made, "s1")?["some_future_field"] as? String, "must survive")
    }

    func testDeletingSignsTheRowsItTouchedAndLeavesTheEntityATombstone() throws {
        var start = vault()
        start["_provenance"] = ["p1": ["edited_by": "someone"]]
        let made = try VaultPatch.deleteEntity(.paymentMethod, id: "p1", in: start, now: now)
        let provenance = made["_provenance"] as? [String: Any] ?? [:]
        XCTAssertEqual((provenance["p1"] as? [String: Any])?["edited_by"] as? String, "longbook-phone",
                       "the entry outlives the row so the other device adopts the delete")
        XCTAssertNotNil(provenance["s1"])
        XCTAssertNil(provenance["s3"], "a commitment that never named it is untouched")
    }

    func testDeletingAPersonFreesTheAccountsThatWereTheirs() throws {
        var start = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, ownerMemberId: "m1")
        var people = rows(start, "members")
        people.append(["id": "m2", "name": "Ivo", "name_key": "ivo"])
        start["members"] = people
        start = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: start, now: now, ownerMemberId: "m2")
        start["_provenance"] = ["m1": ["edited_by": "someone"]]

        let made = try VaultPatch.deleteEntity(.familyMember, id: "m1", in: start, now: now)
        XCTAssertTrue(method(made, "p1")?["member_id"] is NSNull, "no account is left pointing at someone gone")
        XCTAssertEqual(method(made, "p2")?["member_id"] as? String, "m2", "another person's account is none of its business")
        XCTAssertTrue(sub(made, "s1")?["member_id"] is NSNull)
        XCTAssertEqual(rows(made, "accounts").count, 2, "the accounts themselves stay")
        let provenance = made["_provenance"] as? [String: Any] ?? [:]
        XCTAssertNotNil(provenance["p1"], "the freed account is signed like every row the delete touched")
        XCTAssertNil(provenance["p2"])
        XCTAssertEqual((provenance["m1"] as? [String: Any])?["edited_by"] as? String, "longbook-phone", "the person leaves a tombstone")
        // Every foreign key left in the file resolves.
        let held = Set(rows(made, "members").compactMap { $0["id"] as? String })
        for row in rows(made, "accounts") + rows(made, "commitments") {
            if let owner = row["member_id"] as? String { XCTAssertTrue(held.contains(owner), owner) }
        }
        // Deleting an account never reads member_id as its own key.
        let other = try VaultPatch.deleteEntity(.paymentMethod, id: "p2", in: start, now: now)
        XCTAssertEqual(method(other, "p1")?["member_id"] as? String, "m1")
    }

    func testDeletingSomethingAlreadyGoneSaysSoRatherThanPretending() {
        XCTAssertThrowsError(try VaultPatch.deleteEntity(.familyMember, id: "nobody", in: vault(), now: now))
    }

    // MARK: - details: the kind of account, what it is linked to, where a report reaches a member

    func testSettingWhatKindOfAccountItIs() throws {
        let made = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, accountTag: "credit card")
        XCTAssertEqual(method(made, "p1")?["tag"] as? String, "credit card")
        XCTAssertNotNil((made["_provenance"] as? [String: Any])?["p1"], "the edit is signed")
    }

    func testClearingTheKindOfAccountWritesNullNotAbsence() throws {
        let set = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, accountTag: "wallet")
        let made = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: set, now: now, accountTag: .some(nil))
        XCTAssertTrue(method(made, "p1")?["tag"] is NSNull)
    }

    func testAnyOwnerWordMayNameTheKind() throws {
        // v2 opened the vocabulary: a tag outside the library is the owner's to invent.
        let made = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, accountTag: "chit fund")
        XCTAssertEqual(method(made, "p1")?["tag"] as? String, "chit fund")
    }

    func testHangingAnAccountUnderAnother() throws {
        let made = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: vault(), now: now, parentAccountId: "p1")
        XCTAssertEqual(method(made, "p2")?["parent_account_id"] as? String, "p1")
    }

    func testUnhookingAnAccountFromItsParent() throws {
        let set = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: vault(), now: now, parentAccountId: "p1")
        let made = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: set, now: now, parentAccountId: .some(nil))
        XCTAssertTrue(method(made, "p2")?["parent_account_id"] is NSNull)
    }

    func testAnAccountNeverHangsUnderItself() {
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, parentAccountId: "p1"))
    }

    func testAnAccountNeverHangsUnderOneAlreadyHanging() throws {
        let nested = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: vaultWithThirdMethod(), now: now, parentAccountId: "p1")
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p3", in: nested, now: now, parentAccountId: "p2"))
    }

    func testAnAccountOthersHangUnderStaysAtTheTop() throws {
        let nested = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: vaultWithThirdMethod(), now: now, parentAccountId: "p1")
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: nested, now: now, parentAccountId: "p3"))
    }

    func testHangingUnderAnAccountThatIsNotThereIsRefused() {
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, parentAccountId: "nobody"))
    }

    func testDeletingAParentFreesItsChildren() throws {
        let nested = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: vault(), now: now, parentAccountId: "p1")
        let made = try VaultPatch.deleteEntity(.paymentMethod, id: "p1", in: nested, now: now)
        XCTAssertTrue(method(made, "p2")?["parent_account_id"] is NSNull, "no dangling parent")
    }

    func testSettingAMembersEmail() throws {
        let made = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: vault(), now: now, email: "aditi@example.com")
        XCTAssertEqual(member(made, "m1")?["email"] as? String, "aditi@example.com")
        XCTAssertNotNil((made["_provenance"] as? [String: Any])?["m1"], "the edit is signed")
    }

    func testClearingAMembersEmail() throws {
        let set = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: vault(), now: now, email: "aditi@example.com")
        let made = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: set, now: now, email: .some(nil))
        XCTAssertTrue(member(made, "m1")?["email"] is NSNull)
    }

    func testAnEmailNeedsAnAtSignWithSomethingEitherSide() {
        for bad in ["aditi.example.com", "@example.com", "aditi@", "@"] {
            XCTAssertThrowsError(try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: vault(), now: now, email: bad))
        }
    }

    func testAnEmailIsStoredExactlyAsTypedNeverTrimmedOrRecased() throws {
        let made = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: vault(), now: now, email: " Rohit@X.com ")
        XCTAssertEqual(member(made, "m1")?["email"] as? String, " Rohit@X.com ")
    }

    func testDetailsTouchOnlyTheFieldsTheyName() throws {
        var start = vault()
        var methods = rows(start, "accounts")
        methods[0]["some_future_field"] = "must survive"
        start["accounts"] = methods
        let made = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: start, now: now, accountTag: "debit")
        let row = try XCTUnwrap(method(made, "p1"))
        XCTAssertEqual(row["some_future_field"] as? String, "must survive")
        XCTAssertEqual(row["name"] as? String, "HDFC current")
        XCTAssertNil(row["parent_account_id"], "a field left nil stays absent, not cleared")
    }

    func testRefusalsSpeakOfLinkedAccounts() {
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, parentAccountId: "p1")) { error in
            XCTAssertEqual(error.friendlyDescription, "An account can't be linked to itself.")
        }
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, parentAccountId: "nobody")) { error in
            XCTAssertEqual(error.friendlyDescription, "That linked account isn't in the vault.")
        }
    }

    func testAnAccountTakesANoteAndThePersonItBelongsTo() throws {
        let made = try VaultPatch.setEntityDetails(
            .paymentMethod, id: "p1", in: vault(), now: now,
            ownerMemberId: "m1", accountNotes: "Card name: Platinum Reserve\nLounge access."
        )
        let row = try XCTUnwrap(method(made, "p1"))
        XCTAssertEqual(row["notes"] as? String, "Card name: Platinum Reserve\nLounge access.")
        XCTAssertNil(row["details"], "nothing is written to details")
        XCTAssertEqual(row["member_id"] as? String, "m1")
        XCTAssertNotNil((made["_provenance"] as? [String: Any])?["p1"], "the edit is signed")

        let cleared = try VaultPatch.setEntityDetails(
            .paymentMethod, id: "p1", in: made, now: now, ownerMemberId: .some(nil), accountNotes: .some("  ")
        )
        let bare = try XCTUnwrap(method(cleared, "p1"))
        XCTAssertTrue(bare["notes"] is NSNull)
        XCTAssertTrue(bare["member_id"] is NSNull)
    }

    /// Edit Account's Save, once the notes carry the card's name: card_name leaves details, the
    /// rest of details stays, and nothing else about details is ever touched.
    func testASaveCanTakeTheCardNameOutOfDetailsAndLeavesTheRest() throws {
        var start = vault()
        var methods = rows(start, "accounts")
        methods[0]["details"] = ["card_name": "Platinum Reserve", "due_day": 5]
        methods[1]["details"] = ["card_name": "Coral"]
        start["accounts"] = methods
        let made = try VaultPatch.setEntityDetails(
            .paymentMethod, id: "p1", in: start, now: now,
            accountNotes: "Lounge access.\nCard name: Platinum Reserve", removingCardName: true
        )
        let row = try XCTUnwrap(method(made, "p1"))
        XCTAssertEqual(row["details"] as? [String: Int], ["due_day": 5], "the rest of details rides through")
        XCTAssertEqual(row["notes"] as? String, "Lounge access.\nCard name: Platinum Reserve")
        // A card name alone in details leaves no empty object behind when it goes.
        let gone = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: start, now: now, removingCardName: true)
        XCTAssertNil(method(gone, "p2")?["details"])
        XCTAssertNotNil((gone["_provenance"] as? [String: Any])?["p2"], "the edit is signed")
        // Otherwise details are never touched.
        let kept = try VaultPatch.setEntityDetails(.paymentMethod, id: "p2", in: start, now: now, accountTag: "credit card")
        XCTAssertEqual(method(kept, "p2")?["details"] as? [String: String], ["card_name": "Coral"])
    }

    /// Edit Account opens an account holding a card name in details with it as the last line of
    /// the notes field — unless the notes already hold that same line — so it is seen before Save.
    func testEditAccountOpensWithAHeldCardNameAsALineOfItsNotes() {
        let held: Details = ["card_name": .string(" Platinum Reserve "), "due_day": .number(5)]
        XCTAssertEqual(notesFoldingCardName("Lounge access.", details: held), "Lounge access.\nCard name: Platinum Reserve")
        XCTAssertEqual(notesFoldingCardName("Lounge access.\n\n", details: held), "Lounge access.\nCard name: Platinum Reserve")
        XCTAssertEqual(notesFoldingCardName(nil, details: held), "Card name: Platinum Reserve")
        XCTAssertEqual(notesFoldingCardName(" \n ", details: held), "Card name: Platinum Reserve", "blank notes are none")
        // The same line, in any case or spacing, is the notes' own to say.
        XCTAssertEqual(notesFoldingCardName("Lounge access.\ncard  NAME :platinum  RESERVE", details: held),
                       "Lounge access.\ncard  NAME :platinum  RESERVE")
        // A card-name line saying another name never hides the held one: both are seen, and one Save keeps what the owner leaves.
        XCTAssertEqual(notesFoldingCardName("Lounge access.\ncard  NAME: Coral", details: held),
                       "Lounge access.\ncard  NAME: Coral\nCard name: Platinum Reserve")
        XCTAssertEqual(notesFoldingCardName("Card name: Platinum Reserve Metal", details: held),
                       "Card name: Platinum Reserve Metal\nCard name: Platinum Reserve", "a line is the same only whole")
        XCTAssertEqual(notesFoldingCardName(nil, details: ["card_name": .number(2024)]), "Card name: 2024", "held as a number, read as its digits")
        // Nothing held, or nothing said, leaves the notes as they are.
        XCTAssertEqual(notesFoldingCardName("Lounge access.", details: ["due_day": .number(5)]), "Lounge access.")
        XCTAssertEqual(notesFoldingCardName("Lounge access.", details: ["card_name": .string("  ")]), "Lounge access.")
        XCTAssertNil(notesFoldingCardName(nil, details: nil))
        XCTAssertNil(notesFoldingCardName("  ", details: ["card_name": .null]))
    }

    func testANoteIsNeverASecretAndAnOwnerIsSomeoneHeld() {
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, accountNotes: "pin: 4821"))
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now,
                                                             accountNotes: "Card name: Visa 4111 1111 1111 1111"))
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, ownerMemberId: "nobody"))
    }

    /// A tag and an email are written into the file, so each meets the scan a note meets — as
    /// both MCP doors scan them.
    func testATagAndAnEmailMeetTheSecretScan() throws {
        let refusals: [(String, () throws -> [String: Any])] = [
            ("account tag", { try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: self.vault(), now: self.now, accountTag: "pin: 4821") }),
            ("member tag", { try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: self.vault(), now: self.now, memberTag: "cook 4111 1111 1111 1111") }),
            ("email", { try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: self.vault(), now: self.now, email: "4111111111111111@example.com") }),
        ]
        for (what, write) in refusals {
            XCTAssertThrowsError(try write(), what) { error in
                XCTAssertTrue(error.friendlyDescription.hasPrefix(dataPolicyRefusal), what)
            }
        }
        let tagged = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, accountTag: "credit card")
        XCTAssertEqual(method(tagged, "p1")?["tag"] as? String, "credit card")
        let person = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: vault(), now: now,
                                                     email: "aditi@example.com", memberTag: "household help")
        XCTAssertEqual(member(person, "m1")?["email"] as? String, "aditi@example.com")
        XCTAssertEqual(member(person, "m1")?["tag"] as? String, "household help")
    }

    func testAPersonWearsATagAndLosesItWithNull() throws {
        let made = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: vault(), now: now, memberTag: " landlord ")
        XCTAssertEqual(member(made, "m1")?["tag"] as? String, "landlord")
        let cleared = try VaultPatch.setEntityDetails(.familyMember, id: "m1", in: made, now: now, memberTag: .some(nil))
        XCTAssertTrue(member(cleared, "m1")?["tag"] is NSNull)
        // Each kind takes only its own fields: a member tag never lands on an account.
        let ignored = try VaultPatch.setEntityDetails(.paymentMethod, id: "p1", in: vault(), now: now, memberTag: "landlord")
        XCTAssertNil(method(ignored, "p1")?["tag"])
    }

    func testSettingDetailsOnSomethingGoneSaysSo() {
        XCTAssertThrowsError(try VaultPatch.setEntityDetails(.paymentMethod, id: "nobody", in: vault(), now: now, accountTag: "cash"))
    }
}
