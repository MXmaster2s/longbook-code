// Many rows in one write, and two or more people or accounts made one. Every name is made up.
import XCTest
@testable import LongbookCore

final class VaultBulkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func commitments(_ raw: [String: Any]) -> [[String: Any]] { raw["commitments"] as? [[String: Any]] ?? [] }
    private func row(_ id: String, in raw: [String: Any], _ key: String = "commitments") -> [String: Any]? {
        (raw[key] as? [[String: Any]] ?? []).first { $0["id"] as? String == id }
    }
    private func chargeDates(_ id: String, in raw: [String: Any]) -> [String] {
        (raw["charges"] as? [[String: Any]] ?? []).filter { $0["commitment_id"] as? String == id }.compactMap { $0["date"] as? String }.sorted()
    }

    /// A gym with three charges, a one-time lunch, a salary coming in and a transfer between
    /// Asha's own two accounts. Asha is Self; Bina and Beena are one friend, spelled twice.
    private func vault() -> [String: Any] {
        [
            "app": "longbook", "version": VAULT_FORMAT_VERSION,
            "members": [
                ["id": "asha", "name": "Asha Rao", "name_key": "asha rao", "tag": "Self"],
                ["id": "bina", "name": "Bina Shah", "name_key": "bina shah", "email": "bina@example.com", "photo": "people/bina.jpg"],
                ["id": "beena", "name": "Beena S", "name_key": "beena s", "tag": "Friend", "photo": "people/beena.jpg",
                 "is_incomplete": true, "starred": true, "details": ["met_at": "school"]],
            ] as [[String: Any]],
            "accounts": [
                ["id": "a1", "name": "HDFC savings ••4417", "name_key": "hdfc savings ••4417", "member_id": "asha", "balance": 100.0, "balance_date": "2026-09-01"],
                ["id": "a2", "name": "HDFC ••4417", "name_key": "hdfc ••4417", "last4": "4417", "balance": 200.0, "balance_date": "2026-10-01", "notes": "Old spelling"],
                ["id": "a3", "name": "ICICI ••0063", "name_key": "icici ••0063", "member_id": "asha"],
                ["id": "card", "name": "Card ••9090", "name_key": "card ••9090", "member_id": "asha", "parent_account_id": "a2"],
                ["id": "bank", "name": "Axis", "name_key": "axis|bina shah", "member_id": "bina"],
            ] as [[String: Any]],
            "commitments": [
                ["id": "gym", "name": "Gym", "amount": 50.0, "currency": "USD", "billing_cycle": "monthly", "status": "active", "tag": "Health", "member_id": "bina", "account_id": "a1"],
                ["id": "lunch", "name": "Lunch", "amount": 10.0, "currency": "USD", "billing_cycle": "once", "status": "active", "member_id": "beena", "account_id": "a2"],
                ["id": "pay", "name": "Pay", "amount": 900.0, "currency": "USD", "billing_cycle": "once", "status": "active", "direction": "in", "member_id": "beena", "account_id": "a2"],
                ["id": "move", "name": "Move", "amount": 70.0, "currency": "USD", "billing_cycle": "once", "status": "active", "direction": "transfer", "account_id": "a1",
                 "details": ["counterpart_account_id": "a3", "counterpart_account": "ICICI ••0063", "line_direction": "out"]],
                ["id": "tobeena", "name": "To Beena", "amount": 5.0, "currency": "USD", "billing_cycle": "once", "status": "active", "account_id": "a3",
                 "details": ["counterpart_account_id": "bank", "counterpart_account": "Axis", "line_direction": "out"]],
                ["id": "printed", "name": "Printed", "amount": 5.0, "currency": "USD", "billing_cycle": "once", "status": "active", "account_id": "a3",
                 "details": ["counterpart_account": "HDFC ••4417", "line_direction": "out"]],
            ] as [[String: Any]],
            "charges": [
                ["commitment_id": "gym", "date": "2026-07-05", "amount": 50.0, "paid": true, "basis": "statement"],
                ["commitment_id": "gym", "date": "2026-08-05", "amount": 50.0, "paid": true, "basis": "statement"],
                ["commitment_id": "gym", "date": "2026-09-05", "amount": 50.0, "paid": true, "basis": "statement"],
                ["commitment_id": "lunch", "date": "2026-09-09", "amount": 10.0, "paid": true, "basis": "statement"],
                ["commitment_id": "pay", "date": "2026-09-30", "amount": 900.0, "paid": true, "basis": "statement"],
                ["commitment_id": "move", "date": "2026-09-12", "amount": 70.0, "paid": true, "basis": "statement"],
            ] as [[String: Any]],
            "groups": [
                ["id": "g1", "kind": "member", "name": "Friends", "member_ids": ["bina", "beena"]],
                ["id": "g2", "kind": "account", "name": "Banks", "account_ids": ["a2", "a3"]],
            ] as [[String: Any]],
            "tags": [] as [[String: Any]],
        ]
    }

    // MARK: bulk Category and Person

    func testCategoryAcrossRowsOfOneCommitmentChangesItOnce() throws {
        // Two charges of the gym and the lunch: three cards, two commitments.
        let cards = ["gym", "gym", "lunch"]
        let reach = VaultPatch.bulkReach(cardsOf: cards, in: vault())
        XCTAssertEqual(reach.cards, 3)
        XCTAssertEqual(reach.commitments, 2)
        XCTAssertEqual(reach.charges, 4, "the gym's third charge is reached too")
        let next = try VaultPatch.setCategory("Fitness", onCommitments: cards, in: vault(), now: now)
        XCTAssertEqual(row("gym", in: next)?["tag"] as? String, "Fitness")
        XCTAssertEqual(row("lunch", in: next)?["tag"] as? String, "Fitness")
        XCTAssertNil(row("pay", in: next)?["tag"] as? String, "a row not chosen stays")
        XCTAssertEqual(chargeDates("gym", in: next).count, 3, "a category writes no charge")
        XCTAssertTrue((next["tags"] as? [[String: Any]] ?? []).contains { $0["name"] as? String == "Fitness" }, "a new name joins the registry")
        let prov = next["_provenance"] as? [String: Any] ?? [:]
        XCTAssertNotNil(prov["gym"])
        XCTAssertNil(prov["pay"])
    }

    func testCategoryNilTakesItOff() throws {
        let next = try VaultPatch.setCategory(nil, onCommitments: ["gym"], in: vault(), now: now)
        XCTAssertTrue(row("gym", in: next)?["tag"] is NSNull)
    }

    func testPersonSetsMemberOnMoneyOutAndMoneyInAndNeverOnATransfer() throws {
        let next = try VaultPatch.setPerson("bina", onCommitments: ["lunch", "pay", "move"], in: vault(), now: now)
        XCTAssertEqual(row("lunch", in: next)?["member_id"] as? String, "bina")
        XCTAssertEqual(row("pay", in: next)?["member_id"] as? String, "bina", "From Person on an earning")
        XCTAssertNil(row("move", in: next)?["member_id"] as? String, "a transfer's people are its accounts' owners")
        XCTAssertEqual(VaultPatch.bulkReach(cardsOf: ["lunch", "move"], in: vault()).transfers, 1)
    }

    func testPersonNilTakesThemOff() throws {
        let next = try VaultPatch.setPerson(nil, onCommitments: ["gym"], in: vault(), now: now)
        XCTAssertTrue(row("gym", in: next)?["member_id"] is NSNull)
    }

    func testChangingNothingLeavesTheFileAsItWas() throws {
        let next = try VaultPatch.setPerson("bina", onCommitments: ["gym"], in: vault(), now: now)
        XCTAssertTrue(vaultDiff(from: vault(), to: next).isEmpty)
        XCTAssertNil(next["_provenance"])
    }

    // MARK: refusals change nothing

    func testARefusedBulkChangeWritesNothing() {
        let before = vault()
        XCTAssertThrowsError(try VaultPatch.setCategory("X", onCommitments: ["gym", "nope"], in: before, now: now))
        XCTAssertThrowsError(try VaultPatch.setPerson("nobody", onCommitments: ["gym"], in: before, now: now))
        XCTAssertThrowsError(try VaultPatch.delete(ids: ["gym", "nope"], from: before, now: now))
        XCTAssertThrowsError(try VaultPatch.deleteEntities(.familyMember, ids: ["bina", "nope"], in: before, now: now))
        XCTAssertThrowsError(try VaultPatch.setCategory("4111 1111 1111 1111", onCommitments: ["gym"], in: before, now: now), "the secret scan stands")
        XCTAssertTrue(vaultDiff(from: vault(), to: before).isEmpty)
    }

    func testARefusedMergeWritesNothing() {
        let before = vault()
        XCTAssertThrowsError(try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["bina"], in: before, now: now), "one is not a merge")
        XCTAssertThrowsError(try VaultPatch.mergeEntities(.familyMember, keeping: "nobody", merging: ["bina"], in: before, now: now))
        XCTAssertThrowsError(try VaultPatch.mergeEntities(.paymentMethod, keeping: "a1", merging: ["nope"], in: before, now: now))
        XCTAssertTrue(vaultDiff(from: vault(), to: before).isEmpty)
    }

    // MARK: deleting many

    func testDeletingManyCommitmentsMatchesDeletingEachInTurn() throws {
        let many = try VaultPatch.delete(ids: ["gym", "lunch"], from: vault(), now: now)
        var each = vault()
        for id in ["gym", "lunch"] { each = try VaultPatch.delete(id: id, from: each, now: now) }
        XCTAssertTrue(vaultDiff(from: many, to: each).isEmpty)
        XCTAssertEqual(Set((many["_provenance"] as? [String: Any] ?? [:]).keys), Set((each["_provenance"] as? [String: Any] ?? [:]).keys))
        XCTAssertNil(row("gym", in: many))
        XCTAssertEqual(chargeDates("gym", in: many), [])
        XCTAssertEqual(chargeDates("pay", in: many).count, 1)
    }

    func testDeletingManyChargesTakesOnlyThoseAndKeepsTheirCommitments() {
        let next = VaultPatch.removeCharges([("gym", "2026-07-05"), ("gym", "2026-08-05"), ("lunch", "2026-09-09"), ("gym", "1999-01-01")], in: vault(), now: now)
        XCTAssertEqual(chargeDates("gym", in: next), ["2026-09-05"])
        XCTAssertEqual(chargeDates("lunch", in: next), [])
        XCTAssertNotNil(row("lunch", in: next), "the same as deleting one charge: the commitment stays")
        let prov = next["_provenance"] as? [String: Any] ?? [:]
        XCTAssertNotNil(prov["gym@2026-07-05"])
        XCTAssertNil(prov["gym@1999-01-01"])
    }

    func testDeletingChargeCardsTakesAnEmptiedOneTimeCommitmentAndKeepsARecurringOne() throws {
        var raw = vault()
        raw["charges"] = (raw["charges"] as? [[String: Any]] ?? []).filter { $0["date"] as? String != "2026-08-05" && $0["date"] as? String != "2026-09-05" }
        let next = try VaultPatch.deleteChargeCards([("gym", "2026-07-05"), ("lunch", "2026-09-09")], in: raw, now: now)
        XCTAssertNil(row("lunch", in: next), "a one-time commitment is its one charge")
        XCTAssertNotNil(row("gym", in: next), "a plan with no rows left is still a plan")
        XCTAssertEqual(chargeDates("gym", in: next), [])
        XCTAssertNotNil((next["_provenance"] as? [String: Any])?["lunch"])
        XCTAssertNotNil(row("pay", in: next), "a row not named stays")
    }

    func testDeletingManyEntitiesUnhooksEveryLink() throws {
        let next = try VaultPatch.deleteEntities(.familyMember, ids: ["bina", "beena"], in: vault(), now: now)
        XCTAssertTrue(row("gym", in: next)?["member_id"] is NSNull)
        XCTAssertTrue(row("lunch", in: next)?["member_id"] is NSNull)
        XCTAssertTrue(row("bank", in: next, "accounts")?["member_id"] is NSNull)
        XCTAssertEqual((next["members"] as? [[String: Any]])?.count, 1)
        let accounts = try VaultPatch.deleteEntities(.paymentMethod, ids: ["a2", "a3"], in: vault(), now: now)
        XCTAssertTrue(row("card", in: accounts, "accounts")?["parent_account_id"] is NSNull)
    }

    func testDeletingSelfAmongManyCountsFlips() throws {
        let before = vault()
        let next = try VaultPatch.deleteEntities(.familyMember, ids: ["asha", "bina"], in: before, now: now)
        let flips = StatementTransfers.flips(from: before, to: next)
        XCTAssertEqual(flips.intoCharges, 1, "the move between Asha's accounts")
        XCTAssertEqual(flips.intoTransfers, 0)
        XCTAssertNil(VaultPatch.storedDirection(row("move", in: next)?["direction"] as? String))
    }

    // MARK: merging people

    func testMergingPeopleMovesEveryLink() throws {
        let next = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["beena"], in: vault(), now: now)
        XCTAssertNil(row("beena", in: next, "members"))
        XCTAssertEqual(row("lunch", in: next)?["member_id"] as? String, "bina")
        XCTAssertEqual(row("pay", in: next)?["member_id"] as? String, "bina")
        XCTAssertEqual(row("gym", in: next)?["member_id"] as? String, "bina")
        let group = (next["groups"] as? [[String: Any]])?.first { $0["id"] as? String == "g1" }
        XCTAssertEqual(group?["member_ids"] as? [String], ["bina"], "a group holds the kept one once")
        let prov = next["_provenance"] as? [String: Any] ?? [:]
        for id in ["bina", "beena", "lunch", "pay"] { XCTAssertNotNil(prov[id], "\(id) is signed, the merged one as a tombstone") }
        XCTAssertNil(prov["gym"], "a row that named the kept one all along is not touched")
    }

    func testMergingPeopleMovesTheirAccountsWithTheOwnerInTheKey() throws {
        let next = try VaultPatch.mergeEntities(.familyMember, keeping: "beena", merging: ["bina"], in: vault(), now: now)
        let bank = row("bank", in: next, "accounts")
        XCTAssertEqual(bank?["member_id"] as? String, "beena")
        XCTAssertEqual(bank?["name_key"] as? String, "axis|beena s", "a digit-less account's key names its owner")
    }

    func testTheKeptPersonKeepsItsFieldsAndFillsOnlyTheEmptyOnes() throws {
        let next = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["beena"], in: vault(), now: now)
        let kept = try XCTUnwrap(row("bina", in: next, "members"))
        XCTAssertEqual(kept["name"] as? String, "Bina Shah")
        XCTAssertEqual(kept["email"] as? String, "bina@example.com")
        XCTAssertEqual(kept["photo"] as? String, "people/bina.jpg", "a merged photo is dropped when the kept one has its own")
        XCTAssertEqual(kept["tag"] as? String, "Friend", "empty, so it takes the merged one's")
        XCTAssertEqual(kept["starred"] as? Bool, true)
        XCTAssertNil(kept["is_incomplete"] as? Bool, "the kept row was already described")
        let details = try XCTUnwrap(kept["details"] as? [String: Any])
        XCTAssertEqual(details["met_at"] as? String, "school")
        XCTAssertEqual(details[VaultPatch.mergedNamesKey] as? [String], ["Beena S"])
    }

    func testAKeptPersonWithNoPhotoTakesAMergedOne() throws {
        var raw = vault()
        var members = raw["members"] as? [[String: Any]] ?? []
        members[1].removeValue(forKey: "photo")
        raw["members"] = members
        let next = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["beena"], in: raw, now: now)
        XCTAssertEqual(row("bina", in: next, "members")?["photo"] as? String, "people/beena.jpg")
    }

    func testMergingASelfPersonKeepsTheRuleAndCountsTheFlips() throws {
        // Into Self: Bina's account becomes Asha's, so the row out to it becomes a transfer.
        let before = vault()
        let into = try VaultPatch.mergeEntities(.familyMember, keeping: "asha", merging: ["bina"], in: before, now: now)
        XCTAssertEqual(row("tobeena", in: into)?["direction"] as? String, "transfer")
        XCTAssertEqual(StatementTransfers.flips(from: before, to: into).intoTransfers, 1)
        // Self into a friend: the kept relationship stays, so Asha's accounts stop being Self's.
        var raw = vault()
        var members = raw["members"] as? [[String: Any]] ?? []
        members[1]["tag"] = "Friend"
        raw["members"] = members
        let out = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["asha"], in: raw, now: now)
        XCTAssertEqual(row("bina", in: out, "members")?["tag"] as? String, "Friend")
        XCTAssertNil(VaultPatch.storedDirection(row("move", in: out)?["direction"] as? String))
        XCTAssertEqual(StatementTransfers.flips(from: raw, to: out).intoCharges, 1)
        // A kept person with no relationship takes Self, and nothing flips back.
        let filled = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["asha"], in: vault(), now: now)
        XCTAssertEqual(row("bina", in: filled, "members")?["tag"] as? String, "Self")
        XCTAssertEqual(StatementTransfers.flips(from: vault(), to: filled).intoCharges, 0)
    }

    // MARK: merging accounts

    func testMergingAccountsMovesEveryLink() throws {
        let next = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a1", merging: ["a2"], in: vault(), now: now)
        XCTAssertNil(row("a2", in: next, "accounts"))
        XCTAssertEqual(row("lunch", in: next)?["account_id"] as? String, "a1")
        XCTAssertEqual(row("pay", in: next)?["account_id"] as? String, "a1")
        XCTAssertEqual(row("card", in: next, "accounts")?["parent_account_id"] as? String, "a1", "a card under a merged account")
        let group = (next["groups"] as? [[String: Any]])?.first { $0["id"] as? String == "g2" }
        XCTAssertEqual(group?["account_ids"] as? [String], ["a1", "a3"])
        // "HDFC ••4417" and "HDFC savings ••4417" read as one account, so a name-only row stays
        // readable through the survivor rather than being rewritten.
        XCTAssertNil((row("printed", in: next)?["details"] as? [String: Any])?["counterpart_account_id"] as? String)
    }

    /// Asha is Self with two accounts and a move between them, a one-time row with no line.
    private func twoAccounts(_ extra: [[String: Any]] = []) -> [String: Any] {
        ["app": "longbook", "version": 3,
         "members": [["id": "asha", "name": "Asha Rao", "name_key": "asha rao", "tag": "Self"]],
         "accounts": [["id": "one", "name": "HDFC 1111", "name_key": "hdfc 1111", "member_id": "asha"],
                      ["id": "two", "name": "Axis 2222", "name_key": "axis 2222", "member_id": "asha"]],
         "commitments": [["id": "move", "name": "Move", "amount": 100.0, "currency": "INR", "billing_cycle": "once", "status": "active",
                          "account_id": "one", "direction": "transfer",
                          "details": ["counterpart_account_id": "two", "counterpart_account": "Axis 2222"]]] + extra]
    }

    func testDeletingAnAccountClearsTheCounterpartsNamingIt() throws {
        let named: [String: Any] = ["id": "named", "name": "By name", "amount": 100.0, "currency": "INR", "billing_cycle": "once", "status": "active",
                                    "account_id": "one", "details": ["counterpart_account": "Axis 2222", "statement_line": "A LINE"]]
        let next = try VaultPatch.deleteEntities(.paymentMethod, ids: ["two"], in: twoAccounts([named]), now: now)
        XCTAssertNil(row("move", in: next)?["details"], "nothing else was on it")
        XCTAssertNil(row("move", in: next)?["direction"] as? String, "and the rule ran")
        XCTAssertEqual(row("named", in: next)?["details"] as? [String: String], ["statement_line": "A LINE"], "by name too, and the line stays")
    }

    func testDeletingAnAccountLeavesACounterpartASurvivorAnswersTo() throws {
        let named: [String: Any] = ["id": "named", "name": "By name", "amount": 100.0, "currency": "INR", "billing_cycle": "once", "status": "active",
                                    "details": ["counterpart_account": "HDFC 1111"]]
        let next = try VaultPatch.deleteEntities(.paymentMethod, ids: ["two"], in: twoAccounts([named]), now: now)
        XCTAssertEqual((row("named", in: next)?["details"] as? [String: Any])?["counterpart_account"] as? String, "HDFC 1111")
    }

    func testMergingTwoAccountsWithATransferBetweenThemClearsItAndRunsTheRule() throws {
        let next = try VaultPatch.mergeEntities(.paymentMethod, keeping: "one", merging: ["two"], in: twoAccounts(), now: now)
        XCTAssertEqual(row("move", in: next)?["account_id"] as? String, "one")
        XCTAssertNil(row("move", in: next)?["details"], "an account has no other side of itself")
        XCTAssertNil(row("move", in: next)?["direction"] as? String)
        XCTAssertEqual(StatementTransfers.flips(from: twoAccounts(), to: next).intoCharges, 1)
    }

    func testAnAccountIsNeverTheOtherSideOfItsOwnRow() throws {
        var edit = SubEdit(id: "move")
        edit.name = "Move"
        edit.amount = 100
        edit.currency = "INR"
        edit.billingCycle = .once
        edit.direction = "transfer"
        edit.paymentMethodId = "two"
        let saved = try VaultPatch.saveCommitment(edit, in: twoAccounts(), now: now)
        XCTAssertNil(row("move", in: saved)?["details"], "From Account set to To Account clears To Account")
        XCTAssertNil(row("move", in: saved)?["direction"] as? String)
        let picked = try VaultPatch.setCounterpartAccount(commitmentId: "move", accountId: "one", in: twoAccounts(), now: now)
        XCTAssertNil(row("move", in: picked)?["details"])
    }

    func testMergingAccountsMovesTheCounterpartByIdAndName() throws {
        let next = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a2", merging: ["a3"], in: vault(), now: now)
        let moved = try XCTUnwrap(row("move", in: next)?["details"] as? [String: Any])
        XCTAssertEqual(moved["counterpart_account_id"] as? String, "a2")
        XCTAssertEqual(moved["counterpart_account"] as? String, "HDFC ••4417")
        // A name only the merged account answered to moves too.
        var raw = vault()
        var subs = raw["commitments"] as? [[String: Any]] ?? []
        subs[5]["account_id"] = "a1"
        subs[5]["details"] = ["counterpart_account": "ICICI ••0063", "line_direction": "out"]
        raw["commitments"] = subs
        let named = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a2", merging: ["a3"], in: raw, now: now)
        let printed = try XCTUnwrap(row("printed", in: named)?["details"] as? [String: Any])
        XCTAssertEqual(printed["counterpart_account_id"] as? String, "a2")
    }

    func testMergeKeepsBothRowsNotes() throws {
        var raw = vault()
        var accounts = raw["accounts"] as! [[String: Any]]
        accounts[0]["notes"] = "Joint with mother"
        accounts[1]["notes"] = "Old spelling"
        accounts[2]["notes"] = "Old spelling"
        raw["accounts"] = accounts
        let next = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a1", merging: ["a2", "a3"], in: raw, now: now)
        XCTAssertEqual(row("a1", in: next, "accounts")?["notes"] as? String, "Joint with mother\nOld spelling", "each on its line, a repeat once")
        var people = raw["members"] as! [[String: Any]]
        people[1]["notes"] = "Met at school"
        people[2]["notes"] = "Plays tennis"
        raw["members"] = people
        let person = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["beena"], in: raw, now: now)
        XCTAssertEqual(row("bina", in: person, "members")?["notes"] as? String, "Met at school\nPlays tennis")
    }

    func testTheKeptAccountKeepsItsBalanceAndFillsTheRest() throws {
        let next = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a1", merging: ["a2"], in: vault(), now: now)
        let kept = try XCTUnwrap(row("a1", in: next, "accounts"))
        XCTAssertEqual(kept["balance"] as? Double, 100)
        XCTAssertEqual(kept["balance_date"] as? String, "2026-09-01")
        XCTAssertEqual(kept["last4"] as? String, "4417")
        XCTAssertEqual(kept["notes"] as? String, "Old spelling")
        XCTAssertEqual(kept["member_id"] as? String, "asha")
        // With none of its own it takes the merged balance and that balance's date together.
        let other = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a3", merging: ["a2"], in: vault(), now: now)
        XCTAssertEqual(row("a3", in: other, "accounts")?["balance"] as? Double, 200)
        XCTAssertEqual(row("a3", in: other, "accounts")?["balance_date"] as? String, "2026-10-01")
    }

    func testLinksStayOneLevelDeep() throws {
        // The kept card has a link of its own, so what hung under the merged bank goes to that link.
        var raw = vault()
        var accounts = raw["accounts"] as? [[String: Any]] ?? []
        accounts[2]["parent_account_id"] = "a1"
        raw["accounts"] = accounts
        let up = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a3", merging: ["a2"], in: raw, now: now)
        XCTAssertEqual(row("card", in: up, "accounts")?["parent_account_id"] as? String, "a1")
        XCTAssertEqual(row("a3", in: up, "accounts")?["parent_account_id"] as? String, "a1")
        // Merged into what it was linked to: the kept account hangs under nothing.
        let own = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a2", merging: ["card"], in: vault(), now: now)
        XCTAssertNil(row("a2", in: own, "accounts")?["parent_account_id"] as? String)
        // The bank merged into its own card: the card cannot point at itself.
        let card = try VaultPatch.mergeEntities(.paymentMethod, keeping: "card", merging: ["a2"], in: vault(), now: now)
        XCTAssertNil(row("card", in: card, "accounts")?["parent_account_id"] as? String)
        // A kept account with something under it takes no link from a merged one.
        var linked = vault()
        var rows = linked["accounts"] as? [[String: Any]] ?? []
        rows[2]["parent_account_id"] = "a1"
        linked["accounts"] = rows
        let held = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a2", merging: ["a3"], in: linked, now: now)
        XCTAssertNil(row("a2", in: held, "accounts")?["parent_account_id"] as? String)
    }

    func testMergingThreeRemembersEveryName() throws {
        let first = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["beena"], in: vault(), now: now)
        let second = try VaultPatch.mergeEntities(.familyMember, keeping: "asha", merging: ["bina"], in: first, now: now)
        XCTAssertEqual(VaultPatch.mergedNames(of: try XCTUnwrap(row("asha", in: second, "members"))), ["Bina Shah", "Beena S"])
    }

    func testAMergedRowsDetailsStayOutOfANote() {
        XCTAssertEqual(detailLines(["merged_names": .list([.string("Beena S")])]), [])
    }

    // MARK: the next import

    func testALaterNamePrintedAsMergedAddsNobody() throws {
        let merged = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["beena"], in: vault(), now: now)
        let made = try VaultPatch.ensureEntity(.familyMember, named: "BEENA  S", in: merged, now: now)
        XCTAssertEqual(made.id, "bina")
        XCTAssertEqual((made.vault["members"] as? [[String: Any]])?.count, (merged["members"] as? [[String: Any]])?.count)
        XCTAssertEqual(StatementImport.memberId(named: "beena s", in: merged), "bina")
    }

    func testALaterAccountPrintedAsMergedAddsNobody() throws {
        let merged = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a1", merging: ["a3"], in: vault(), now: now)
        XCTAssertEqual(try VaultPatch.ensureEntity(.paymentMethod, named: "ICICI ••0063", in: merged, now: now).id, "a1")
        XCTAssertEqual(StatementImport.accountId(named: "ICICI savings ••0063", in: merged), "a1")
        // Digit-less accounts stay told apart by their owner.
        var raw = vault()
        var accounts = raw["accounts"] as? [[String: Any]] ?? []
        accounts.append(["id": "b2", "name": "Axis Bank", "name_key": "axis bank|bina shah", "member_id": "bina"])
        raw["accounts"] = accounts
        let axis = try VaultPatch.mergeEntities(.paymentMethod, keeping: "bank", merging: ["b2"], in: raw, now: now)
        XCTAssertEqual(try VaultPatch.ensureAccount(named: "Axis Bank", ownerName: "Bina Shah", in: axis, now: now).id, "bank")
        XCTAssertNotEqual(try VaultPatch.ensureAccount(named: "Axis Bank", ownerName: "Asha Rao", in: axis, now: now).id, "bank")
    }

    func testAnOwnerPrintedAsMergedFindsTheirAccount() throws {
        let merged = try VaultPatch.mergeEntities(.familyMember, keeping: "beena", merging: ["bina"], in: vault(), now: now)
        let made = try VaultPatch.ensureAccount(named: "Axis", ownerName: "Bina Shah", in: merged, now: now)
        XCTAssertEqual(made.id, "bank")
        XCTAssertEqual((made.vault["members"] as? [[String: Any]])?.count, 2)
    }

    func testTheBookReadsAMergedNameAsTheRow() throws {
        let merged = try VaultPatch.mergeEntities(.familyMember, keeping: "asha", merging: ["bina"], in: vault(), now: now)
        let book = StatementBook(raw: merged)
        XCTAssertTrue(book.isSelf("Bina Shah", holder: nil))
        let accounts = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a1", merging: ["a3"], in: vault(), now: now)
        let found = StatementCounterparts.found(
            in: [StatementCloud.Charge(date: "2026-10-01", amount: 5, name: "To ICICI", narration: "x", account: "HDFC", category: nil, kind: "transfer",
                                       member: nil, counterpart: "ICICI ••0063", counterpartKind: "account")],
            knownAccounts: StatementBook(raw: accounts).accounts, knownPeople: [])
        XCTAssertTrue(found.accounts.isEmpty, "the merged account is not offered as new")
    }

    func testAStatementPrintingMergedNamesWritesNoTwins() throws {
        var merged = try VaultPatch.mergeEntities(.familyMember, keeping: "bina", merging: ["beena"], in: vault(), now: now)
        merged = try VaultPatch.mergeEntities(.paymentMethod, keeping: "a1", merging: ["a3"], in: merged, now: now)
        var candidate = StatementCandidate(line: StatementLine(date: "2026-10-20", payee: "UPI-BEENA S", amount: 42, direction: .debit),
                                           name: "Payment to Beena S", tag: nil, keep: true, skipReason: nil, file: "synthetic.pdf", member: "Beena S")
        candidate.counterpartAccount = "ICICI ••0063"
        let file = StatementImport.ReviewFile(rows: [candidate], account: "ICICI ••0063", addsAccount: true, source: "documents/synthetic.pdf",
                                              balance: nil, balanceDate: nil, owner: nil)
        let review = StatementImport.Review(members: ["Beena S"], accounts: [StatementCounterparts.Account(name: "ICICI ••0063")], files: [file],
                                            currency: "USD", repeats: [], waiting: [])
        let written = try StatementImport.write(review, to: merged, now: now, schema: nil).vault
        XCTAssertEqual((written["members"] as? [[String: Any]])?.count, (merged["members"] as? [[String: Any]])?.count)
        XCTAssertEqual((written["accounts"] as? [[String: Any]])?.count, (merged["accounts"] as? [[String: Any]])?.count)
        let line = try XCTUnwrap(commitments(written).first { $0["name"] as? String == "Payment to Beena S" })
        XCTAssertEqual(line["member_id"] as? String, "bina")
        XCTAssertEqual(line["account_id"] as? String, "a1")
        XCTAssertEqual((line["details"] as? [String: Any])?["counterpart_account_id"] as? String, "a1")
    }

    // MARK: one write, at any size

    func testOneChangeAtTheScaleOfThousandsIsQuick() throws {
        var raw = vault()
        var subs = raw["commitments"] as? [[String: Any]] ?? []
        var rows = raw["charges"] as? [[String: Any]] ?? []
        var people = raw["members"] as? [[String: Any]] ?? []
        for index in 0 ..< 5000 {
            let member = "p\(index % 500)"
            subs.append(["id": "c\(index)", "name": "Row \(index)", "amount": 1.0, "currency": "USD", "billing_cycle": "once", "status": "active", "member_id": member])
            rows.append(["commitment_id": "c\(index)", "date": "2026-09-09", "amount": 1.0, "paid": true, "basis": "statement"])
        }
        for index in 0 ..< 500 { people.append(["id": "p\(index)", "name": "Person \(index)", "name_key": "person \(index)"]) }
        raw["commitments"] = subs
        raw["charges"] = rows
        raw["members"] = people
        let everyone = (0 ..< 500).map { "p\($0)" }
        let start = Date()
        let deleted = try VaultPatch.deleteEntities(.familyMember, ids: everyone, in: raw, now: now)
        let merged = try VaultPatch.mergeEntities(.familyMember, keeping: "p0", merging: everyone, in: raw, now: now)
        let category = try VaultPatch.setCategory("Bulk", onCommitments: (0 ..< 5000).map { "c\($0)" }, in: raw, now: now)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "debug build, on any machine")
        XCTAssertEqual((deleted["members"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual(commitments(merged).filter { $0["member_id"] as? String == "p0" }.count, 5000)
        XCTAssertEqual(commitments(category).filter { $0["tag"] as? String == "Bulk" }.count, 5000)
    }

    // MARK: report scopes

    func testAScopeNamingAMergedRowCallsItByTheKeptName() {
        let scope = ReportScope(accounts: ["HDFC"], members: ["Beena S", "Bina Shah", "Asha Rao"])
        let moved = scope.merging(.familyMember, names: ["Beena S"], into: "Bina Shah")
        XCTAssertEqual(moved.members, ["Bina Shah", "Asha Rao"])
        XCTAssertEqual(moved.accounts, ["HDFC"])
        XCTAssertEqual(scope.merging(.paymentMethod, names: ["HDFC"], into: "ICICI").accounts, ["ICICI"])
    }

    // MARK: the deleted-import event

    func testDeletingAnImportedCommitmentReportsItsSortAndNoName() throws {
        let before = vault()
        let after = try VaultPatch.delete(ids: ["gym", "lunch"], from: before, now: now)
        let props = try XCTUnwrap(StatementTour.deletedProperties(before: before, after: after, bulk: true))
        XCTAssertEqual(props["commitments"] as? Int, 2)
        XCTAssertEqual(props["bulk"] as? Bool, true)
        let sorts = try XCTUnwrap(props["removed_commitments"] as? [[String: Any]])
        XCTAssertEqual(sorts.count, 2)
        XCTAssertEqual(sorts.first { $0["cycle"] as? String == "monthly" }?["sightings"] as? String, "3+")
        XCTAssertEqual(sorts.first { $0["cycle"] as? String == "once" }?["sightings"] as? String, "1")
        let text = String(decoding: try JSONSerialization.data(withJSONObject: props, options: .sortedKeys), as: UTF8.self)
        for word in ["Gym", "Lunch", "Asha", "Bina", "Beena", "HDFC", "4417", "50", "bina@example.com", "gym", "lunch"] {
            XCTAssertFalse(text.contains(word), "\(word) left in the payload: \(text)")
        }
        XCTAssertEqual(Set(sorts.flatMap(\.keys)), ["cycle", "sightings", "guessed", "category", "count"])
    }

    func testAnOwnersCategoryNeverLeavesInTheDeletedEvent() throws {
        var raw = vault()
        var subs = raw["commitments"] as? [[String: Any]] ?? []
        subs[0]["tag"] = "Treatment for my knee"
        raw["commitments"] = subs
        let after = try VaultPatch.delete(id: "gym", from: raw, now: now)
        let props = try XCTUnwrap(StatementTour.deletedProperties(before: raw, after: after, bulk: false))
        let sorts = try XCTUnwrap(props["removed_commitments"] as? [[String: Any]])
        XCTAssertEqual(sorts.first?["category"] as? String, "other")
    }

    func testTakingTheLastChargeOfAnImportedCommitmentCountsAndAnEarlierOneDoesNot() throws {
        let before = vault()
        let last = VaultPatch.removeCharges([("lunch", "2026-09-09")], in: before, now: now)
        XCTAssertEqual(StatementTour.deletedProperties(before: before, after: last, bulk: false)?["commitments"] as? Int, 1)
        let one = VaultPatch.removeCharges([("gym", "2026-09-05")], in: before, now: now)
        XCTAssertNil(StatementTour.deletedProperties(before: before, after: one, bulk: false))
    }

    func testACommitmentNoStatementBackedSendsNothing() throws {
        var raw = vault()
        raw["charges"] = [["commitment_id": "gym", "date": "2026-07-05", "amount": 50.0, "paid": true, "basis": "user"]]
        let after = try VaultPatch.delete(id: "gym", from: raw, now: now)
        XCTAssertNil(StatementTour.deletedProperties(before: raw, after: after, bulk: false))
    }
}
