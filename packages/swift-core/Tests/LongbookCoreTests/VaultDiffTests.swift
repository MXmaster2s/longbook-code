// The review's diff: id-keyed, field-level, told in display strings. Timestamp churn
// and provenance are machine noise and must never read as the owner's story.
import XCTest
@testable import LongbookCore

final class VaultDiffTests: XCTestCase {
    private func vault(
        subs: [[String: Any]] = [], methods: [[String: Any]] = [], members: [[String: Any]] = [],
        tags: [[String: Any]] = [], charges: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "app": "longbook", "version": 3,
            "commitments": subs, "accounts": methods, "members": members,
            "tags": tags, "charges": charges,
        ]
    }

    func testAVaultDiffedAgainstItselfIsEmpty() {
        let v = vault(
            subs: [["id": "a", "name": "Claude", "amount": 100, "has_trial": false]],
            members: [["id": "m1", "name": "Aditi"]]
        )
        XCTAssertTrue(vaultDiff(from: v, to: v).isEmpty)
    }

    func testAnAddedRowIsReportedByName() {
        let diff = vaultDiff(from: vault(), to: vault(subs: [["id": "a", "name": "Claude"]]))
        XCTAssertEqual(diff.count, 1, "only touched kinds come back")
        XCTAssertEqual(diff.first?.kind, "commitments")
        XCTAssertEqual(diff.first?.added.map(\.name), ["Claude"])
        XCTAssertEqual(diff.first?.removed.map(\.name), [])
        XCTAssertTrue(diff.first?.changed.isEmpty ?? false)
    }

    func testARemovedRowIsReportedByName() {
        let diff = vaultDiff(from: vault(members: [["id": "m1", "name": "Aditi"]]), to: vault())
        XCTAssertEqual(diff.first?.kind, "members")
        XCTAssertEqual(diff.first?.removed.map(\.name), ["Aditi"])
    }

    func testAChangedFieldCarriesBeforeAndAfterStrings() {
        let old = vault(subs: [["id": "a", "name": "Claude", "amount": 100]])
        let new = vault(subs: [["id": "a", "name": "Claude", "amount": 149.5]])
        let change = vaultDiff(from: old, to: new).first?.changed.first
        XCTAssertEqual(change?.id, "a")
        XCTAssertEqual(change?.name, "Claude")
        XCTAssertEqual(change?.fields.map(\.key), ["amount"])
        XCTAssertEqual(change?.fields.first?.before, "100", "no trailing .0 on a whole number")
        XCTAssertEqual(change?.fields.first?.after, "149.5")
    }

    func testABooleanRendersAsTrueOrFalseNotOneOrZero() {
        let old = vault(subs: [["id": "a", "name": "Claude", "has_trial": false]])
        let new = vault(subs: [["id": "a", "name": "Claude", "has_trial": true]])
        let field = vaultDiff(from: old, to: new).first?.changed.first?.fields.first
        XCTAssertEqual(field?.before, "false")
        XCTAssertEqual(field?.after, "true")
    }

    func testTimestampChurnIsNotAChange() {
        let old = vault(subs: [["id": "a", "name": "Claude", "updated_at": "2026-01-01T00:00:00Z"]])
        let new = vault(subs: [["id": "a", "name": "Claude", "updated_at": "2026-08-07T09:00:00Z",
                                "created_at": "2026-08-07T09:00:00Z"]])
        XCTAssertTrue(vaultDiff(from: old, to: new).isEmpty, "updated_at and created_at churn on every save")
    }

    func testNullAndAbsentBothRenderAsADash() {
        let noted = vault(subs: [["id": "a", "name": "Claude", "notes": "shared with the family"]])
        let nulled = vault(subs: [["id": "a", "name": "Claude", "notes": NSNull()]])
        let field = vaultDiff(from: noted, to: nulled).first?.changed.first?.fields.first
        XCTAssertEqual(field?.key, "notes")
        XCTAssertEqual(field?.before, "shared with the family")
        XCTAssertEqual(field?.after, "—")

        let absent = vault(subs: [["id": "a", "name": "Claude"]])
        XCTAssertTrue(vaultDiff(from: nulled, to: absent).isEmpty, "null and absent are the same non-value")
    }

    func testKindsComeBackInVaultOrderAndOnlyWhenTouched() {
        let old = vault(
            subs: [["id": "a", "name": "Claude"]],
            methods: [["id": "p1", "name": "HDFC Current"]],
            members: [["id": "m1", "name": "Aditi"]]
        )
        let new = vault(
            subs: [["id": "a", "name": "Claude Pro"]],
            methods: [["id": "p1", "name": "HDFC Current"]],
            members: [["id": "m1", "name": "Aditi"], ["id": "m2", "name": "Rohit"]]
        )
        XCTAssertEqual(vaultDiff(from: old, to: new).map(\.kind), ["commitments", "members"],
                       "untouched payment_methods stays out")
    }

    func testARowWithNoNameFallsBackToItsId() {
        let diff = vaultDiff(from: vault(), to: vault(methods: [["id": "p9"]]))
        XCTAssertEqual(diff.first?.added.map(\.name), ["p9"])
    }

    func testAnArrayValueRendersAsCanonicalJson() {
        let old = vault(subs: [["id": "a", "name": "Claude", "tags": ["ai"]]])
        let new = vault(subs: [["id": "a", "name": "Claude", "tags": ["ai", "work"]]])
        let field = vaultDiff(from: old, to: new).first?.changed.first?.fields.first
        XCTAssertEqual(field?.before, #"["ai"]"#)
        XCTAssertEqual(field?.after, #"["ai","work"]"#)
    }

    func testAnAddedTagIsReportedByName() {
        let tag: [String: Any] = [
            "id": "t1", "kind": "commitment", "name": "Insurance", "name_key": "insurance",
            "icon": "shield",
            "template": [["key": "policy_no", "label": "Policy number", "hint": "text"]],
        ]
        let diff = vaultDiff(from: vault(), to: vault(tags: [tag]))
        XCTAssertEqual(diff.map(\.kind), ["tags"])
        XCTAssertEqual(diff.first?.added.map(\.name), ["Insurance"])
        XCTAssertEqual(diff.first?.removed.map(\.name), [])
        XCTAssertTrue(diff.first?.changed.isEmpty ?? false)
    }

    func testARemovedTagIsReportedByName() {
        let tag: [String: Any] = ["id": "t1", "kind": "member", "name": "Kids", "name_key": "kids"]
        let diff = vaultDiff(from: vault(tags: [tag]), to: vault())
        XCTAssertEqual(diff.first?.kind, "tags")
        XCTAssertEqual(diff.first?.removed.map(\.name), ["Kids"])
    }

    func testAChangedTagReportsItsFieldsNotARemoveAndAdd() {
        let old = vault(tags: [["id": "t1", "kind": "commitment", "name": "Insurance",
                                "name_key": "insurance", "icon": "shield"]])
        let new = vault(tags: [["id": "t1", "kind": "commitment", "name": "Insurance",
                                "name_key": "insurance", "icon": "umbrella"]])
        let entity = vaultDiff(from: old, to: new).first
        XCTAssertEqual(entity?.kind, "tags")
        XCTAssertTrue(entity?.added.isEmpty ?? false)
        XCTAssertTrue(entity?.removed.isEmpty ?? false)
        XCTAssertEqual(entity?.changed.first?.name, "Insurance")
        XCTAssertEqual(entity?.changed.first?.fields.map(\.key), ["icon"])
    }

    func testATagWithNoIdStillMatchesItselfByKindAndNameKey() {
        let tag: [String: Any] = ["kind": "account", "name": "Cards", "name_key": "cards"]
        XCTAssertTrue(vaultDiff(from: vault(tags: [tag]), to: vault(tags: [tag])).isEmpty)
    }

    func testAVaultDifferingOnlyInTagsIsNotBookkeeping() {
        let old = vault(subs: [["id": "a", "name": "Claude"]])
        let new = vault(subs: [["id": "a", "name": "Claude"]],
                        tags: [["id": "t1", "kind": "commitment", "name": "Insurance", "name_key": "insurance"]])
        XCTAssertFalse(vaultDiff(from: old, to: new).isEmpty,
                       "a tag registered by an import must never read as bookkeeping-only")
    }

    func testAChargeIsNamedByCommitmentAndDate() {
        let subs: [[String: Any]] = [["id": "a", "name": "Claude"]]
        let row: [String: Any] = ["commitment_id": "a", "date": "2026-08-01", "amount": 20, "paid": false,
                                  "written_at": "2026-08-01T10:00:00Z"]
        let diff = vaultDiff(from: vault(subs: subs), to: vault(subs: subs, charges: [row]))
        XCTAssertEqual(diff.map(\.kind), ["charges"])
        XCTAssertEqual(diff.first?.added.map(\.name), ["Claude — 2026-08-01"])
        XCTAssertTrue(diff.first?.changed.isEmpty ?? false)
    }

    func testARemovedChargeIsStillNamed() {
        let row: [String: Any] = ["commitment_id": "a", "date": "2026-08-01", "amount": 20, "paid": false]
        let old = vault(subs: [["id": "a", "name": "Claude"]], charges: [row])
        let diff = vaultDiff(from: old, to: vault())
        XCTAssertEqual(diff.map(\.kind), ["commitments", "charges"],
                       "the older vault still names a commitment the newer one dropped")
        XCTAssertEqual(diff.last?.removed.map(\.name), ["Claude — 2026-08-01"])
    }

    func testAChargeOnAnUnknownCommitmentFallsBackToItsId() {
        let row: [String: Any] = ["commitment_id": "ghost", "date": "2026-08-01", "amount": 1, "paid": false]
        let diff = vaultDiff(from: vault(), to: vault(charges: [row]))
        XCTAssertEqual(diff.first?.added.map(\.name), ["ghost — 2026-08-01"])
    }

    /// A charge carries fields that change — paid, the amount, the day the money moved —
    /// and those are changes worth a line; the row's timestamp alone is not.
    func testAChargeMarkedPaidIsAChangeButItsTimestampIsNot() {
        let subs: [[String: Any]] = [["id": "a", "name": "Claude"]]
        let old = vault(subs: subs, charges: [["commitment_id": "a", "date": "2026-08-01", "amount": 20, "paid": false,
                                               "written_at": "2026-08-01T10:00:00Z"]])
        let same = vault(subs: subs, charges: [["commitment_id": "a", "date": "2026-08-01", "amount": 20, "paid": false,
                                                "written_at": "2026-08-02T08:00:00Z"]])
        XCTAssertTrue(vaultDiff(from: old, to: same).isEmpty)
        let paid = vault(subs: subs, charges: [["commitment_id": "a", "date": "2026-08-01", "amount": 18, "paid": true,
                                                "paid_on": "2026-08-02", "written_at": "2026-08-01T10:00:00Z"]])
        let diff = vaultDiff(from: old, to: paid)
        XCTAssertEqual(diff.map(\.kind), ["charges"])
        XCTAssertEqual(diff.first?.changed.first?.name, "Claude — 2026-08-01")
        let fields = Set(diff.first?.changed.first?.fields.map(\.key) ?? [])
        XCTAssertEqual(fields, ["amount", "paid", "paid_on"])
    }

    func testAnAddedCommitmentCarriesItsMoneyCycleAndTag() {
        let row: [String: Any] = ["id": "a", "name": "Netflix", "amount": 649, "currency": "INR",
                                  "billing_cycle": "monthly", "tag": "streaming"]
        let added = vaultDiff(from: vault(), to: vault(subs: [row])).first?.added.first
        XCTAssertEqual(added?.amount, 649)
        XCTAssertEqual(added?.currency, "INR")
        XCTAssertEqual(added?.note, "Monthly · streaming")
    }

    func testAnAddedTransferOrMoneyInSaysWhichWayItMoves() {
        let bill: [String: Any] = ["id": "t", "name": "Coral card bill", "amount": 31250, "currency": "INR",
                                   "billing_cycle": "monthly", "tag": "cards", "direction": "transfer"]
        let pay: [String: Any] = ["id": "p", "name": "Vertex salary", "amount": 214000, "currency": "INR",
                                  "billing_cycle": "monthly", "direction": "in"]
        let rent: [String: Any] = ["id": "r", "name": "Rent", "amount": 42000, "currency": "INR",
                                   "billing_cycle": "monthly", "direction": "out"]
        let added = vaultDiff(from: vault(), to: vault(subs: [bill, pay, rent])).first?.added ?? []
        XCTAssertEqual(added.map(\.direction), ["transfer", "in", nil], "out is absence, as the file keeps it")
        XCTAssertEqual(added.map(\.directionWord), ["Transfer", "Money in", nil])
        XCTAssertEqual(added.map(\.note), ["Transfer · Monthly · cards", "Money in · Monthly", "Monthly"],
                       "a one-line surface leads with it, so a proposal is never read as spending")
    }

    func testAChargeBorrowsItsCommitmentsDirectionAndItIsNeverAChange() {
        let bill: [String: Any] = ["id": "t", "name": "Coral card bill", "currency": "INR", "direction": "transfer"]
        let row: [String: Any] = ["commitment_id": "t", "date": "2026-10-05", "amount": 31250, "paid": false]
        let added = vaultDiff(from: vault(subs: [bill]), to: vault(subs: [bill], charges: [row])).first?.added.first
        XCTAssertEqual(added?.direction, "transfer")
        XCTAssertEqual(added?.note, "Transfer · Planned")
        XCTAssertEqual(added?.paid, "Planned", "the paid words stay their own fact")

        // The commitment turning into a transfer is one change, on the commitment alone.
        var spend = bill
        spend["direction"] = NSNull()
        let turned = vaultDiff(from: vault(subs: [spend], charges: [row]), to: vault(subs: [bill], charges: [row]))
        XCTAssertEqual(turned.map(\.kind), ["commitments"])
        XCTAssertEqual(turned.first?.changed.first?.fields.map(\.key), ["direction"])
    }

    func testAChangedDetailsObjectOpensIntoItsKeysInWords() throws {
        let before: [String: Any] = ["id": "c", "name": "Coral card", "details": ["card_name": "Coral", "autopay": false]]
        let after: [String: Any] = ["id": "c", "name": "Coral card",
                                    "details": ["card_name": "Coral Platinum", "autopay": true, "perks": ["lounge", "fuel"], "due_day": 5]]
        let field = try XCTUnwrap(vaultDiff(from: vault(methods: [before]), to: vault(methods: [after])).first?.changed.first?.fields.first)
        XCTAssertEqual(field.key, "details")
        let parts = try XCTUnwrap(detailChanges(field))
        XCTAssertEqual(parts.map(\.key), ["details.autopay", "details.card_name", "details.due_day", "details.perks"])
        XCTAssertEqual(parts.map(\.before), ["no", "Coral", "—", "—"])
        XCTAssertEqual(parts.map(\.after), ["yes", "Coral Platinum", "5", "lounge, fuel"], "a flag reads yes or no, a list joins")

        let set = try XCTUnwrap(vaultDiff(from: vault(methods: [["id": "c", "name": "Coral card"]]), to: vault(methods: [before])).first?.changed.first?.fields.first)
        XCTAssertEqual(detailChanges(set)?.map(\.after), ["no", "Coral"], "details set for the first time open the same way")

        let nested = FieldChange(key: "details", before: "—", after: #"{"plan":{"tier":"gold"}}"#)
        XCTAssertNil(detailChanges(nested), "an object the contract forbids stays one raw line")
        XCTAssertNil(detailChanges(FieldChange(key: "notes", before: "—", after: "{}")), "only details open")
    }

    func testAnAddedChargeBorrowsItsCommitmentsCurrencyAndSaysPaid() {
        let subs: [[String: Any]] = [["id": "a", "name": "Netflix", "currency": "INR"]]
        let row: [String: Any] = ["commitment_id": "a", "date": "2026-09-01", "amount": 649, "paid": true,
                                  "paid_on": "2026-09-02"]
        let added = vaultDiff(from: vault(subs: subs), to: vault(subs: subs, charges: [row])).first?.added.first
        XCTAssertEqual(added?.amount, 649)
        XCTAssertEqual(added?.currency, "INR")
        // The day reads in the reader's locale ("2 Sep 2026" or "Sep 2, 2026"); the words around it are fixed.
        XCTAssertEqual(added?.note, "Paid on \(LB.longDate(LB.day(2026, 9, 2)))")
    }

    func testAPlannedChargeSaysSoAndAMemberSaysNothing() {
        let subs: [[String: Any]] = [["id": "a", "name": "Netflix", "currency": "INR"]]
        let row: [String: Any] = ["commitment_id": "a", "date": "2026-10-01", "amount": 649, "paid": false]
        let diff = vaultDiff(from: vault(subs: subs), to: vault(subs: subs, members: [["id": "m1", "name": "Aditi"]], charges: [row]))
        XCTAssertEqual(diff.first { $0.kind == "charges" }?.added.first?.note, "Planned")
        let member = diff.first { $0.kind == "members" }?.added.first
        XCTAssertNil(member?.amount)
        XCTAssertNil(member?.note)
    }

    func testAChargesBorrowedCurrencyIsNeverAChange() {
        let subs: [[String: Any]] = [["id": "a", "name": "Netflix", "currency": "INR"]]
        let row: [String: Any] = ["commitment_id": "a", "date": "2026-09-01", "amount": 649, "paid": false]
        XCTAssertTrue(vaultDiff(from: vault(subs: subs, charges: [row]), to: vault(subs: subs, charges: [row])).isEmpty)
    }

    func testProvenanceAndMergeUndoNeverReachTheStory() {
        var old = vault(subs: [["id": "a", "name": "Claude"]])
        var new = old
        old["_provenance"] = ["a": ["edited_by": "longbook-desktop"]]
        new["_provenance"] = ["a": ["edited_by": "longbook-phone"]]
        new["merge_undo"] = ["snapshot": "anything"]
        XCTAssertTrue(vaultDiff(from: old, to: new).isEmpty)
    }
}
