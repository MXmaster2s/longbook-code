// The write path, proved rather than asserted. Prevents DATA LOSS THAT LOOKS LIKE
// SUCCESS: an unmodeled field quietly vanishes from the vault with nothing in the UI
// showing it. Preservation gets the most tests, asserted on the raw dictionary, not structs.
//
// Every fixture is SYNTHETIC — this repo is public.
import XCTest
@testable import LongbookCore

final class WriterTests: XCTestCase {
    private let now = LB.day(2026, 7, 23)
    /// The stamp the writer should produce for `now`. Derived, not hardcoded: `LB.day` is a LOCAL
    /// midnight and the stamp is UTC, so a literal here would only pass in one timezone.
    private var nowStamp: String { VaultPatch.iso8601(now) }

    /// A vault carrying plenty this build does NOT model: `groups`, `merge_undo`, a `settings` key
    /// invented here to stand for "whatever a future desktop adds", and a row field the same.
    private func richVault() -> [String: Any] {
        [
            "app": "longbook",
            "version": 3,
            "commitments": [
                [
                    "id": "grok", "name": "Grok", "amount": 20.0, "currency": "USD",
                    "billing_cycle": "monthly", "status": "active",
                    "owner_id": "local",
                    "some_future_field": "must survive",
                ],
                [
                    "id": "apple", "name": "Apple fitness+", "amount": 149.0, "currency": "INR",
                    "billing_cycle": "monthly", "status": "active",
                ],
            ],
            "charges": [
                ["commitment_id": "grok", "date": "2026-08-21", "amount": 20.0, "paid": false, "basis": "plan"],
                ["commitment_id": "apple", "date": "2026-07-21", "amount": 149.0, "paid": false, "basis": "plan"],
            ],
            "members": [["id": "m1", "name": "Aditi", "name_key": "aditi"]],
            "accounts": [],
            "categories": ["AI subscription", "Fitness"],
            "groups": [["id": "g1", "kind": "payment", "name": "cards", "name_key": "cards"]],
            "merge_undo": NSNull(),
            "settings": ["home_currency": "INR"],
            "_provenance": ["grok": ["edited_by": "claude", "edited_at": "2026-07-20T10:00:00Z"]],
        ]
    }

    private func subs(_ vault: [String: Any]) -> [[String: Any]] {
        vault["commitments"] as? [[String: Any]] ?? []
    }

    private func row(_ vault: [String: Any], _ id: String) -> [String: Any]? {
        subs(vault).first { $0["id"] as? String == id }
    }

    // MARK: - the rule that matters most

    func testEditingOneRowPreservesEveryFieldThePhoneDoesNotModel() throws {
        var edit = SubEdit(id: "grok")
        edit.name = "Grok"
        edit.amount = 30            // the only real change
        edit.currency = "USD"
        edit.firstCharge = "2026-08-21"

        let out = try VaultPatch.apply(edit, to: richVault(), now: now)

        XCTAssertNotNil(out["groups"], "groups is the owner's arrangement of their vault — never ours to drop")
        XCTAssertNotNil(out["categories"])
        XCTAssertNotNil(out["settings"], "a key a NEWER desktop added must survive an OLDER phone's write")
        XCTAssertTrue(out["merge_undo"] is NSNull, "an explicit null is a value, not an absence")
        XCTAssertEqual(
            row(out, "grok")?["some_future_field"] as? String, "must survive",
            "an unmodelled field on the edited row itself is the easiest one to lose"
        )
        XCTAssertEqual(row(out, "grok")?["amount"] as? Double, 30, "and the actual edit still lands")
        XCTAssertEqual(subs(out).count, 2, "editing one row touches no others")
        XCTAssertEqual(row(out, "apple")?["amount"] as? Double, 149)
    }

    func testAnotherToolsProvenanceEntriesAreLeftAlone() throws {
        var edit = SubEdit(id: "apple")
        edit.name = "Apple fitness+"
        edit.amount = 149
        edit.currency = "INR"
        edit.firstCharge = "2026-07-21"

        let out = try VaultPatch.apply(edit, to: richVault(), now: now)
        let prov = try XCTUnwrap(out["_provenance"] as? [String: Any])

        let grok = try XCTUnwrap(prov["grok"] as? [String: Any])
        XCTAssertEqual(grok["edited_by"] as? String, "claude", "we signed our row, not someone else's")

        let apple = try XCTUnwrap(prov["apple"] as? [String: Any])
        XCTAssertEqual(apple["edited_by"] as? String, "longbook-phone")
        XCTAssertEqual(apple["edited_at"] as? String, nowStamp)
    }

    /// The contract asks for an OBJECT per record. A bare string would still be JSON, and the
    /// desktop would still show *an* edit — but not who made it, which is the whole point.
    func testProvenanceIsWrittenAsTheContractsObjectShapeNotAString() throws {
        var edit = SubEdit()
        edit.name = "New thing"
        edit.amount = 10
        edit.currency = "INR"
        edit.firstCharge = "2026-08-01"

        let out = try VaultPatch.apply(edit, to: richVault(), now: now)
        let id = try XCTUnwrap(subs(out).last?["id"] as? String)
        XCTAssertTrue(out["_provenance"] as? [String: Any] != nil)
        XCTAssertTrue(
            (out["_provenance"] as? [String: Any])?[id] is [String: Any],
            "an entry must be {edited_by, edited_at}, not a bare name"
        )
    }

    // MARK: - adding and editing

    func testAddingMintsAnIdAndStampsBothTimestamps() throws {
        var edit = SubEdit()
        edit.name = "  Netflix  "     // trimmed on the way in
        edit.amount = 649
        edit.currency = "INR"
        edit.firstCharge = "2026-08-15"

        let out = try VaultPatch.apply(edit, to: richVault(), now: now)
        XCTAssertEqual(subs(out).count, 3)
        let added = try XCTUnwrap(subs(out).last)
        XCTAssertEqual(added["name"] as? String, "Netflix")
        XCTAssertEqual(added["created_at"] as? String, nowStamp)
        XCTAssertEqual(added["updated_at"] as? String, nowStamp)
        XCTAssertNil(added["owner_id"], "rows carry no owner_id")
        XCTAssertNil(added["has_trial"], "nothing about an occurrence lives on the row")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(added["id"] as? String)), "a real UUID, not a slug")
    }

    func testEditingKeepsTheIdAndTheCreationDate() throws {
        var edit = SubEdit(id: "grok")
        edit.name = "Grok"
        edit.amount = 20
        edit.currency = "USD"
        edit.firstCharge = "2026-08-21"

        let out = try VaultPatch.apply(edit, to: richVault(), now: now)
        // The id is load-bearing: family_member_id and _provenance both key on it.
        XCTAssertEqual(row(out, "grok")?["id"] as? String, "grok")
        XCTAssertEqual(row(out, "grok")?["updated_at"] as? String, nowStamp)
        XCTAssertNil(row(out, "grok")?["created_at"], "an edit doesn't invent a creation date the row never had")
    }

    func testClearingAFieldWritesNullRatherThanDroppingTheKey() throws {
        var vault = richVault()
        var rows = subs(vault)
        rows[0]["tag"] = "AI subscription"
        vault["commitments"] = rows

        var edit = SubEdit(id: "grok")
        edit.name = "Grok"
        edit.amount = 20
        edit.currency = "USD"
        edit.firstCharge = "2026-08-21"
        edit.tag = nil          // the owner cleared it — a real edit

        let out = try VaultPatch.apply(edit, to: vault, now: now)
        let cleared = try XCTUnwrap(row(out, "grok"))
        XCTAssertTrue(cleared["tag"] is NSNull, "dropping the key would read as ‘never set’, not ‘cleared’")
    }

    func testAFirstChargeInThePastIsWrittenWhereItWasTypedNeverRolledForward() throws {
        // A writer that "helpfully" advances a past first charge invents a different history.
        var edit = SubEdit()
        edit.name = "Old gym"
        edit.amount = 149
        edit.currency = "INR"
        edit.firstCharge = "2026-01-21"   // deliberately in the past
        edit.planMonths = 2

        let out = try VaultPatch.apply(edit, to: richVault(), now: now)
        let id = try XCTUnwrap(subs(out).last?["id"] as? String)
        XCTAssertEqual(Fx.rows(out, of: id).map { $0["date"] as? String }, ["2026-01-21", "2026-02-21"])
    }

    func testEditingARowThatIsNoLongerThereFailsRatherThanAddingItBack() {
        var edit = SubEdit(id: "deleted-elsewhere")
        edit.name = "Ghost"
        edit.amount = 1
        edit.currency = "INR"
        edit.firstCharge = "2026-08-01"
        XCTAssertThrowsError(try VaultPatch.apply(edit, to: richVault(), now: now))
    }

    // MARK: - validation

    private func valid(_ mutate: (inout SubEdit) -> Void) -> SubEdit {
        var e = SubEdit()
        e.name = "Thing"
        e.amount = 100
        e.currency = "INR"
        e.firstCharge = "2026-08-01"
        mutate(&e)
        return e
    }

    func testBadInputIsRefusedBeforeItCanReachTheFile() {
        let cases: [(String, SubEdit)] = [
            ("a blank name", valid { $0.name = "   " }),
            ("a negative amount", valid { $0.amount = -5 }),
            ("no currency", valid { $0.currency = "" }),
            ("an invented calendar day", valid { $0.firstCharge = "2026-02-31" }),
            ("a non-date", valid { $0.firstCharge = "soon" }),
            ("a custom cycle with no length", valid { $0.billingCycle = .custom; $0.customCycleDays = nil }),
            ("a custom cycle of zero days", valid { $0.billingCycle = .custom; $0.customCycleDays = 0 }),
        ]
        for (what, edit) in cases {
            XCTAssertThrowsError(try VaultPatch.apply(edit, to: richVault(), now: now), "should refuse \(what)")
        }
    }

    /// The commitment form reads its amount with `Double(_:)`, which takes "inf", "nan" and
    /// "1e400". The validator refuses each, new or edited, in a negative amount's words.
    func testAnAmountThatIsNotAFiniteNumberIsRefusedLikeANegativeOne() {
        for typed in ["inf", "nan", "1e400"] {
            let amount = Double(typed) ?? -1
            XCTAssertFalse(amount.isFinite, "\(typed) parses to a number that is not finite")
            for edit in [valid { $0.amount = amount }, valid { $0.id = "grok"; $0.amount = amount }] {
                XCTAssertThrowsError(try VaultPatch.apply(edit, to: richVault(), now: now)) {
                    XCTAssertEqual($0.friendlyDescription, "The amount has to be a number, and not a negative one.", typed)
                }
            }
        }
    }

    /// A figure past a quadrillion is a slip of the keyboard, and a form could no longer show
    /// it digit for digit: refused new or edited, in plain words. The limit itself is kept.
    func testAnAmountPastTheLimitIsRefused() throws {
        for amount in [1e15 + 1, 2e15, 9.3e18] {
            for edit in [valid { $0.amount = amount }, valid { $0.id = "grok"; $0.amount = amount }] {
                XCTAssertThrowsError(try VaultPatch.apply(edit, to: richVault(), now: now), "\(amount)") {
                    XCTAssertEqual($0.friendlyDescription, "The amount can't be more than 1,000,000,000,000,000.")
                }
            }
        }
        let limit = try VaultPatch.apply(valid { $0.id = "grok"; $0.amount = 1e15 }, to: richVault(), now: now)
        XCTAssertEqual(row(limit, "grok")?["amount"] as? Double, 1e15)
    }

    /// Days between charges run from 1 to 36,500, a hundred years: new or edited, a count past
    /// either end is refused in plain words, and both ends are kept.
    func testACustomCycleIsHeldToAHundredYears() throws {
        for days in [0, -5, 36_501, 99_999_999_999_999_999] {
            for edit in [valid { $0.billingCycle = .custom; $0.customCycleDays = days },
                         valid { $0.id = "grok"; $0.billingCycle = .custom; $0.customCycleDays = days }] {
                XCTAssertThrowsError(try VaultPatch.apply(edit, to: richVault(), now: now), "\(days)") {
                    XCTAssertEqual($0.friendlyDescription, "A custom cycle is 1 to 36,500 days between charges.")
                }
            }
        }
        for days in [1, 36_500] {
            let kept = try VaultPatch.apply(valid { $0.id = "grok"; $0.billingCycle = .custom; $0.customCycleDays = days },
                                            to: richVault(), now: now)
            XCTAssertEqual(row(kept, "grok")?["custom_cycle_days"] as? Int, days)
        }
    }

    // MARK: - entities

    func testEnsureEntityMatchesOnTheNormalisedNameRatherThanCreatingATwin() throws {
        var vault = richVault()
        vault["accounts"] = [["id": "hdfc", "name": "HDFC Current", "name_key": "hdfc current"]]

        let again = try VaultPatch.ensureEntity(.paymentMethod, named: "  hdfc   CURRENT ", in: vault, now: now)
        XCTAssertEqual(again.id, "hdfc", "case and spacing must not split one account into two")
        XCTAssertEqual((again.vault["accounts"] as? [[String: Any]])?.count, 1)

        let fresh = try VaultPatch.ensureEntity(.paymentMethod, named: "Kotak S&P", in: again.vault, now: now)
        let rows = try XCTUnwrap(fresh.vault["accounts"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        let added = try XCTUnwrap(rows.last)
        XCTAssertEqual(added["name"] as? String, "Kotak S&P", "the owner's own spelling, kept exactly")
        XCTAssertEqual(added["name_key"] as? String, "kotak s&p")
        XCTAssertEqual(added["is_incomplete"] as? Bool, true, "named, not yet described")
        XCTAssertEqual(added["created_at"] as? String, nowStamp)
    }

    func testEnsureEntityRefusesABlankNameAndKeepsMembersSeparateFromMethods() throws {
        XCTAssertThrowsError(try VaultPatch.ensureEntity(.familyMember, named: "   ", in: richVault(), now: now))

        let made = try VaultPatch.ensureEntity(.familyMember, named: "Aditi", in: richVault(), now: now)
        XCTAssertEqual((made.vault["members"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((made.vault["accounts"] as? [[String: Any]])?.count, 0,
                       "a member never lands among the accounts")
    }

    /// A new account or person puts its name in the file, so the name meets the scan every
    /// note meets: refused in the writer's words, never repeated. A clean name is written; a
    /// name the file already holds is matched and nothing is written, as the Mac door does.
    func testANewAccountOrMemberNameMeetsTheSecretScan() throws {
        for (kind, clean) in [(VaultPatch.EntityKind.paymentMethod, "HDFC Visa 4821"), (.familyMember, "Ivo")] {
            for secret in ["4111 1111 1111 1111", "Card 4111-1111-1111-1111", "pin: 4821"] {
                XCTAssertThrowsError(try VaultPatch.ensureEntity(kind, named: secret, in: richVault(), now: now),
                                     "\(kind) \(secret)") {
                    XCTAssertTrue($0.friendlyDescription.hasPrefix(dataPolicyRefusal), $0.friendlyDescription)
                }
            }
            let made = try VaultPatch.ensureEntity(kind, named: clean, in: richVault(), now: now)
            let rows = made.vault[kind.rawValue] as? [[String: Any]] ?? []
            XCTAssertEqual(rows.first { $0["id"] as? String == made.id }?["name"] as? String, clean, "\(kind)")
        }

        var held = richVault()
        held["accounts"] = [["id": "old", "name": "4111 1111 1111 1111", "name_key": "4111 1111 1111 1111"]]
        let matched = try VaultPatch.ensureEntity(.paymentMethod, named: "4111 1111 1111 1111", in: held, now: now)
        XCTAssertEqual(matched.id, "old")
        XCTAssertEqual((matched.vault["accounts"] as? [[String: Any]])?.count, 1)
    }

    func testACancellingDateReachesTheFileAndCanBeTakenBack() throws {
        var edit = valid { $0.scheduledCancelDate = "2026-11-30" }
        var vault = try VaultPatch.apply(edit, to: richVault(), now: now)
        let id = try XCTUnwrap(subs(vault).last?["id"] as? String)
        XCTAssertEqual(try XCTUnwrap(row(vault, id))["ends_on"] as? String, "2026-11-30")

        // Deciding to keep it must clear the date, not leave a stop day nobody meant.
        edit.id = id
        edit.scheduledCancelDate = nil
        vault = try VaultPatch.apply(edit, to: vault, now: now)
        XCTAssertTrue(try XCTUnwrap(row(vault, id))["ends_on"] is NSNull, "cleared, not dropped")
    }

    func testACancellingDateThatIsNotARealDayIsRefused() {
        let bad = valid { $0.scheduledCancelDate = "2026-02-31" }
        XCTAssertThrowsError(try VaultPatch.apply(bad, to: richVault(), now: now))
    }

    func testARefusedWriteLeavesTheVaultUntouched() throws {
        let before = richVault()
        let bad = valid { $0.firstCharge = "2026-02-31" }
        XCTAssertThrowsError(try VaultPatch.apply(bad, to: before, now: now))
        // apply() is pure and returns a new dictionary, so a rejected edit cannot have half-applied.
        XCTAssertEqual(subs(before).count, 2)
    }

    /// The drift guard: validation reads the enum from the schema the VAULT ships, so a contract that
    /// gains a value works without shipping a new app — and one that loses a value stops accepting it.
    func testValidationFollowsTheShippedSchemaRatherThanAHardcodedCopy() {
        let narrowed: [String: Any] = [
            "properties": ["commitments": ["items": [
                "required": SubValidator.requiredKeys,
                "properties": ["status": ["enum": ["active"]]],
            ]]],
        ]
        let paused = valid { $0.status = .paused }
        XCTAssertThrowsError(
            try VaultPatch.apply(paused, to: richVault(), now: now, schema: narrowed),
            "the vault's own schema says only ‘active’ here, so ‘paused’ must be refused"
        )
        XCTAssertNoThrow(try VaultPatch.apply(paused, to: richVault(), now: now),
                         "without a schema the built-in rules still allow it")
    }

    func testAnUnreadableSchemaFallsBackInsteadOfBlockingAllWrites() {
        let junk: [String: Any] = ["properties": "not an object at all"]
        XCTAssertNoThrow(try VaultPatch.apply(valid { _ in }, to: richVault(), now: now, schema: junk))
    }

    // MARK: - ending a commitment

    func testCancellingKeepsTheRowAndItsHistory() throws {
        let out = try VaultPatch.cancel(id: "grok", in: richVault(), now: now)
        XCTAssertEqual(subs(out).count, 2, "the row stays — that's the difference from deleting")
        XCTAssertEqual(row(out, "grok")?["status"] as? String, "cancelled")
        XCTAssertEqual(row(out, "grok")?["some_future_field"] as? String, "must survive")
        XCTAssertEqual(
            (out["_provenance"] as? [String: Any]).flatMap { ($0["grok"] as? [String: Any])?["edited_by"] as? String },
            "longbook-phone"
        )
    }

    func testDeletingLeavesATombstoneSignedByTheApp() throws {
        let out = try VaultPatch.delete(id: "grok", from: richVault(), now: now)
        XCTAssertEqual(subs(out).count, 1)
        XCTAssertNil(row(out, "grok"))
        XCTAssertFalse((out["charges"] as? [[String: Any]] ?? []).contains { $0["commitment_id"] as? String == "grok" })
        let provenance = out["_provenance"] as? [String: Any] ?? [:]
        // The entry outlives the row: the other device reads the removal as the owner's.
        for key in ["grok", "grok@2026-08-21"] {
            let entry = provenance[key] as? [String: Any]
            XCTAssertEqual(entry?["edited_by"] as? String, "longbook-phone", key)
            XCTAssertEqual(entry?["edited_at"] as? String, nowStamp, key)
        }
        XCTAssertNotNil(out["groups"], "deleting a row is still not licence to drop anything else")
    }

    func testDeletingSomethingAlreadyGoneFails() {
        XCTAssertThrowsError(try VaultPatch.delete(id: "nope", from: richVault(), now: now))
    }

    // MARK: - tombstones are swept a month on

    private func tombstone(daysOld: Int) -> [String: Any] {
        ["edited_by": "longbook-phone", "edited_at": VaultPatch.iso8601(now.addingTimeInterval(-Double(daysOld) * 86_400))]
    }

    private func savedProvenance(_ vault: [String: Any]) throws -> [String: Any] {
        var edit = SubEdit(id: "apple")
        edit.name = "Apple fitness+"
        edit.amount = 149
        edit.firstCharge = "2026-07-21"
        return try VaultPatch.apply(edit, to: vault, now: now)["_provenance"] as? [String: Any] ?? [:]
    }

    func testAYoungTombstoneSurvivesAnUnrelatedSave() throws {
        var vault = richVault()
        vault["_provenance"] = ["gone": tombstone(daysOld: 10), "gone@2026-06-01": tombstone(daysOld: 29)]
        let saved = try savedProvenance(vault)
        XCTAssertNotNil(saved["gone"])
        XCTAssertNotNil(saved["gone@2026-06-01"])
    }

    func testAnOldTombstoneGoesOnTheNextSave() throws {
        var vault = richVault()
        vault["_provenance"] = ["gone": tombstone(daysOld: 31), "gone@2026-06-01": tombstone(daysOld: 60),
                                "grok@2026-01-01": tombstone(daysOld: 45)]
        let saved = try savedProvenance(vault)
        XCTAssertNil(saved["gone"])
        XCTAssertNil(saved["gone@2026-06-01"])
        XCTAssertNil(saved["grok@2026-01-01"], "a charge day the file no longer holds is a tombstone too")
        XCTAssertNotNil(saved["apple"], "the row just saved is signed as ever")
    }

    func testAnEntryWithALiveRowIsNeverPruned() throws {
        var vault = richVault()
        vault["_provenance"] = ["grok": ["edited_by": "claude", "edited_at": "2025-01-01T00:00:00Z"],
                                "grok@2026-08-21": tombstone(daysOld: 400),
                                "m1": tombstone(daysOld: 400)]
        let saved = try savedProvenance(vault)
        XCTAssertEqual((saved["grok"] as? [String: Any])?["edited_by"] as? String, "claude")
        XCTAssertNotNil(saved["grok@2026-08-21"], "its charge row is still on file")
        XCTAssertNotNil(saved["m1"], "a member's entry is as live as the member")
    }

    /// A Keep on a hand-deleted row leaves an entry with only its mark; the mark's own day ages it.
    func testAnOrphanMarkLeftByAKeepAgesOutByItsOwnDay() throws {
        let mark = { (daysOld: Int) -> [String: Any] in
            ["reviewed_by": "longbook-phone", "reviewed_at": VaultPatch.iso8601(self.now.addingTimeInterval(-Double(daysOld) * 86_400))]
        }
        var vault = richVault()
        vault["_provenance"] = ["gone@2026-05-01": mark(40), "gone": mark(5), "grok@2026-08-21": mark(400)]
        let saved = try savedProvenance(vault)
        XCTAssertNil(saved["gone@2026-05-01"], "a kept removal's mark is a tombstone like any other")
        XCTAssertNotNil(saved["gone"], "a young one stays")
        XCTAssertNotNil(saved["grok@2026-08-21"], "its charge row is still on file")
    }

    func testAnUnreadableDateIsNeverTakenForOld() {
        var vault = richVault()
        vault["_provenance"] = ["gone": ["edited_by": "someone", "edited_at": "last spring"],
                                "quiet": ["edited_by": "someone"]]
        let pruned = VaultPatch.pruneTombstones(in: vault, now: now)["_provenance"] as? [String: Any] ?? [:]
        XCTAssertNotNil(pruned["gone"])
        XCTAssertNotNil(pruned["quiet"])
    }

    // MARK: - the round trip

    /// The end-to-end shape check: patch → serialise → decode. If this passes, what the phone writes
    /// is something the phone (and by the shared contract, the desktop) can read straight back.
    func testWhatWeWriteDecodesBackAsAVault() throws {
        var edit = SubEdit()
        edit.name = "Claude"
        edit.amount = 100
        edit.currency = "USD"
        edit.firstCharge = "2026-08-14"
        edit.familyMemberId = "m1"

        let out = try VaultPatch.apply(edit, to: richVault(), now: now)
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        let decoded = try JSONDecoder().decode(Vault.self, from: data)

        XCTAssertEqual(decoded.subscriptions.count, 3)
        let claude = try XCTUnwrap(decoded.subscriptions.first { $0.name == "Claude" })
        XCTAssertEqual(claude.familyMemberId, "m1")
        XCTAssertEqual(claude.status, .active)
        XCTAssertNil(claude.tag, "a JSON null decodes to nil, not to a crash")

        // And the new commitment's charges are immediately visible to the glance's own arithmetic.
        XCTAssertNotNil(nextPaymentDay(decoded, LB.day(2026, 8, 1)))
        XCTAssertEqual(charges(of: claude, in: decoded).count, DEFAULT_PLAN_MONTHS)
    }

    // MARK: - paid marks

    func testMarkingPaidFlipsTheRowAndBackAndTouchesNothingElse() throws {
        let on = try VaultPatch.setCharge(commitmentId: "grok", date: "2026-08-21", paid: true, in: richVault(), now: now)
        let grok = Fx.rows(on, of: "grok")
        XCTAssertEqual(grok.count, 1, "the row was already there; a mark is not a second row")
        XCTAssertEqual(grok.first?["paid"] as? Bool, true)
        XCTAssertEqual(grok.first?["basis"] as? String, "mark_paid")

        let off = try VaultPatch.setCharge(commitmentId: "grok", date: "2026-08-21", paid: false, in: on, now: now)
        XCTAssertEqual(Fx.rows(off, of: "grok").first?["paid"] as? Bool, false)
        XCTAssertNotNil(off["groups"], "an unrelated array is untouched by a paid-mark patch")
        XCTAssertEqual((off["charges"] as? [[String: Any]])?.count, 2, "the other commitment's row is untouched")
    }

    // MARK: - moving a charge past the cancelling date

    /// A plan that stops at a cancelling date, its first row carrying a statement's own amount
    /// and basis — the two facts a re-created row would invent.
    private func cancellingVault() -> [String: Any] {
        [
            "app": "longbook",
            "version": 3,
            "commitments": [[
                "id": "plan", "name": "Term cover", "amount": 500.0, "currency": "INR",
                "billing_cycle": "monthly", "status": "active", "ends_on": "2026-12-31",
            ]],
            "charges": [
                ["commitment_id": "plan", "date": "2026-10-05", "amount": 700.0, "paid": false, "basis": "statement"],
                ["commitment_id": "plan", "date": "2026-11-05", "amount": 500.0, "paid": false, "basis": "plan"],
                ["commitment_id": "plan", "date": "2026-12-05", "amount": 500.0, "paid": false, "basis": "plan"],
            ],
        ]
    }

    /// The run's own row may never be the row that gets dropped. Dropping it deleted the charge
    /// the caller asked to move, took the rest of the run with it, and reported success.
    func testMovingARunPastTheCancellingDateIsRefusedRatherThanDroppingTheMovedRow() {
        XCTAssertThrowsError(
            try VaultPatch.reschedule(commitmentId: "plan", from: "2026-10-05", to: "2027-02-01",
                                      andLater: true, in: cancellingVault(), now: now)
        ) { error in
            XCTAssertTrue(error.friendlyDescription.contains("cancelling date"),
                          "the refusal says why: \(error.friendlyDescription)")
        }
    }

    /// Moving one charge alone past that date is still allowed: one row is a fact about one
    /// day, not a plan being re-anchored. Pinned so the refusal above is not widened.
    func testMovingOneChargeAlonePastTheCancellingDateIsStillAllowed() throws {
        let out = try VaultPatch.reschedule(commitmentId: "plan", from: "2026-10-05", to: "2027-02-01",
                                            andLater: false, in: cancellingVault(), now: now)
        let dates = Fx.rows(out, of: "plan").compactMap { $0["date"] as? String }
        XCTAssertEqual(dates, ["2026-11-05", "2026-12-05", "2027-02-01"])
        let moved = Fx.rows(out, of: "plan").first { $0["date"] as? String == "2027-02-01" }
        XCTAssertEqual(moved?["amount"] as? Double, 700.0, "the row keeps its own amount")
        XCTAssertEqual(moved?["basis"] as? String, "statement", "and its own basis")
    }

    /// Rows after the run's first still stop at the cancelling date — unchanged behaviour,
    /// pinned here beside the refusal so the difference between them stays deliberate.
    func testARunMovedInsideTheCancellingDateStillStopsAtIt() throws {
        let out = try VaultPatch.reschedule(commitmentId: "plan", from: "2026-10-05", to: "2026-12-20",
                                            andLater: true, in: cancellingVault(), now: now)
        let dates = Fx.rows(out, of: "plan").compactMap { $0["date"] as? String }
        XCTAssertEqual(dates, ["2026-12-20"], "the moved row lands; the two that would fall past 31 Dec do not")
        XCTAssertEqual(Fx.rows(out, of: "plan").first?["amount"] as? Double, 700.0)
    }

    /// The second half of the same defect: a caller editing a row it already holds must never
    /// write a fresh one instead, inventing the commitment's price and a blank basis.
    func testSetChargeRefusesToCreateWhenTheCallerSaysItIsEditing() {
        XCTAssertThrowsError(
            try VaultPatch.setCharge(commitmentId: "plan", date: "2027-02-01", amount: 900,
                                     creating: false, in: cancellingVault(), now: now)
        )
        XCTAssertNoThrow(
            try VaultPatch.setCharge(commitmentId: "plan", date: "2027-02-01", amount: 900,
                                     in: cancellingVault(), now: now),
            "the default is unchanged: a row not yet there is still written"
        )
    }

    // MARK: - a secret carried by something other than a string

    /// A card number typed into a number-hinted details field is held as a number, and the
    /// scan read only strings. Same digits, same refusal, whatever type carries them.
    func testACardNumberIsRefusedWhateverTypeTheDetailsValueHolds() {
        let carriers: [(String, DetailValue)] = [
            ("a string", .string("4111111111111111")),
            ("a number", .number(4111111111111111)),
            ("a number inside a list", .list([.number(4111111111111111)])),
            ("a string inside a list", .list([.string("4111111111111111")])),
        ]
        for (what, value) in carriers {
            var edit = valid { $0.id = "grok" }
            edit.details = ["sum_assured": value]
            XCTAssertThrowsError(try VaultPatch.apply(edit, to: richVault(), now: now),
                                 "a card number as \(what) must be refused")
        }
    }

    /// And an ordinary number still saves — the scan must not become a wall.
    func testAnOrdinaryNumericDetailStillSaves() throws {
        var edit = valid { $0.id = "grok" }
        edit.details = ["seats": .number(5), "principal": .number(250_000)]
        let out = try VaultPatch.apply(edit, to: richVault(), now: now)
        let details = row(out, "grok")?["details"] as? [String: Any]
        XCTAssertEqual(details?["seats"] as? Double, 5)
        XCTAssertEqual(details?["principal"] as? Double, 250_000)
    }

    // MARK: - the commitment form's Save is one write

    /// A monthly plan: a statement's charge behind today, three planned ones ahead of it.
    private func planVault() -> [String: Any] {
        [
            "app": "longbook",
            "version": 3,
            "commitments": [[
                "id": "flix", "name": "Streaming", "amount": 649.0, "currency": "INR",
                "billing_cycle": "monthly", "status": "active",
            ]],
            "charges": [
                Fx.rawRow("flix", "2026-07-05", amount: 649, paid: true, basis: "statement"),
                Fx.rawRow("flix", "2026-08-05", amount: 649),
                Fx.rawRow("flix", "2026-09-05", amount: 649),
                Fx.rawRow("flix", "2026-10-05", amount: 649),
            ],
        ]
    }

    private func flix(_ mutate: (inout SubEdit) -> Void = { _ in }) -> SubEdit {
        var edit = SubEdit(id: "flix")
        edit.name = "Streaming"
        edit.amount = 649
        edit.currency = "INR"
        mutate(&edit)
        return edit
    }

    /// The row, the tag, the planned count and the move land together, exactly as the same
    /// steps taken one after another leave them.
    func testTheCommitmentFormsSaveLandsTheRowTheCountAndTheMoveTogether() throws {
        let edit = flix { $0.name = "Streaming plus"; $0.tag = "Video" }
        let out = try VaultPatch.saveCommitment(edit, plannedCount: 4,
                                                charge: .init(from: "2026-08-05", to: "2026-08-09", andLater: true),
                                                in: planVault(), now: now)
        XCTAssertEqual(row(out, "flix")?["name"] as? String, "Streaming plus")
        let tags = out["tags"] as? [[String: Any]] ?? []
        XCTAssertTrue(tags.contains { $0["kind"] as? String == "commitment" && $0["name"] as? String == "Video" },
                      "a worn tag joins the registry in the same write")
        XCTAssertEqual(Fx.rows(out, of: "flix").compactMap { $0["date"] as? String },
                       ["2026-07-05", "2026-08-09", "2026-09-09", "2026-10-09", "2026-11-09"],
                       "a fourth charge is planned, then the run moves")

        var steps = try VaultPatch.apply(edit, to: planVault(), now: now)
        steps = try VaultPatch.setPlannedCount(commitmentId: "flix", count: 4, in: steps, now: now)
        steps = try VaultPatch.reschedule(commitmentId: "flix", from: "2026-08-05", to: "2026-08-09",
                                          andLater: true, in: steps, now: now)
        XCTAssertEqual(out["commitments"] as? NSArray, steps["commitments"] as? NSArray)
        XCTAssertEqual(out["charges"] as? NSArray, steps["charges"] as? NSArray)
    }

    /// A rename saved with a move onto a day already taken is refused whole: a refusal
    /// anywhere in the Save leaves the file byte for byte as it was, the name included.
    func testARefusalAnywhereInTheCommitmentFormsSaveLeavesTheFileAsItWas() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("commitment-form-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try VaultDisk.write(planVault(), to: folder, expecting: nil)
        let before = try VaultReader.load(from: folder)

        let renamed = flix { $0.name = "Streaming plus"; $0.tag = "Video" }
        let ending = flix { $0.name = "Streaming plus"; $0.scheduledCancelDate = "2026-12-31" }
        let attempts: [(String, String, () throws -> [String: Any])] = [
            ("a move onto a day already taken", "already sits on", {
                try VaultPatch.saveCommitment(renamed, plannedCount: 5,
                                              charge: .init(from: "2026-08-05", to: "2026-09-05", andLater: false),
                                              in: before.raw, now: self.now)
            }),
            ("a run moved past the cancelling date", "cancelling date", {
                try VaultPatch.saveCommitment(ending, charge: .init(from: "2026-08-05", to: "2027-01-10", andLater: true),
                                              in: before.raw, now: self.now)
            }),
            ("a blank name", "Give it a name", {
                try VaultPatch.saveCommitment(self.flix { $0.name = "  " }, plannedCount: 5,
                                              in: before.raw, now: self.now)
            }),
        ]
        for (what, why, attempt) in attempts {
            XCTAssertThrowsError(try VaultDisk.write(try attempt(), to: folder, expecting: before.bytes),
                                 "\(what) is refused") {
                XCTAssertTrue($0.friendlyDescription.contains(why), "\(what): \($0.friendlyDescription)")
            }
            let after = try VaultReader.load(from: folder)
            XCTAssertEqual(after.bytes, before.bytes, "\(what): the file is byte for byte as it was")
            XCTAssertEqual(after.vault.subscriptions.first?.name, "Streaming", "\(what): the name is unwritten")
            XCTAssertNil(after.raw["tags"], "\(what): the registry is untouched")
            XCTAssertEqual(after.vault.charges.count, 4, "\(what): no charge was planned or moved")
        }
    }

    /// A paused commitment last charged 5 Mar, saved on 23 Jul. A Save that only fixed a note
    /// sends no count and writes no charge; a count the owner chose is written from today on,
    /// never back-filled into the months behind it.
    func testAPlanCountWritesNothingBeforeToday() throws {
        let raw = Fx.raw([Fx.rawSub(id: "gym", name: "Gym", amount: 1500, status: "paused")],
                         charges: [Fx.rawRow("gym", "2026-02-05", amount: 1500, paid: true, basis: "statement"),
                                   Fx.rawRow("gym", "2026-03-05", amount: 1500, paid: true, basis: "statement")])
        var note = SubEdit(id: "gym")
        note.name = "Gym"
        note.amount = 1500
        note.currency = "INR"
        note.status = .paused
        note.notes = "Locker: 12"
        let saved = try VaultPatch.saveCommitment(note, in: raw, now: now)
        XCTAssertEqual(saved["charges"] as? NSArray, raw["charges"] as? NSArray, "a note is all that changed")

        let one = try VaultPatch.setPlannedCount(commitmentId: "gym", count: 1, in: raw, now: now)
        XCTAssertEqual(Fx.rows(one, of: "gym").compactMap { $0["date"] as? String },
                       ["2026-02-05", "2026-03-05", "2026-08-05"], "the charge asked for lands from today on, never on 5 Apr")
        let three = try VaultPatch.setPlannedCount(commitmentId: "gym", count: 3, in: raw, now: now)
        XCTAssertEqual(Fx.rows(three, of: "gym").compactMap { $0["date"] as? String },
                       ["2026-02-05", "2026-03-05", "2026-08-05", "2026-09-05", "2026-10-05"])
    }

    /// Monthly, with a statement's paid charge behind today and three planned ahead: One-time
    /// is refused whole, in words, and the rows stay exactly where they were. One of several
    /// rows is never re-dated or dropped.
    func testACommitmentWithSeveralChargesIsNeverMadeOneTime() throws {
        let once = flix { $0.billingCycle = .once; $0.firstCharge = "2026-08-05" }
        for attempt in [{ try VaultPatch.apply(once, to: self.planVault(), now: self.now) },
                        { try VaultPatch.saveCommitment(once, in: self.planVault(), now: self.now) }] {
            XCTAssertThrowsError(try attempt()) {
                XCTAssertEqual($0.friendlyDescription,
                               "One-time holds a single charge, and this has 4. Cancel it instead to stop its plan.")
            }
        }

        // A one-time commitment holding two rows refuses a date, even one of its own days:
        // which charge moves is the charge's to say. Without a date, the rest of the edit lands.
        let twice = Fx.raw([Fx.rawSub(id: "sofa", name: "Sofa", amount: 500, cycle: "once")],
                           charges: [Fx.rawRow("sofa", "2026-07-01", amount: 500, paid: true, basis: "statement"),
                                     Fx.rawRow("sofa", "2026-08-01", amount: 500)])
        var sofa = SubEdit(id: "sofa")
        sofa.name = "Sofa"
        sofa.amount = 500
        sofa.currency = "INR"
        sofa.billingCycle = .once
        sofa.notes = "Delivered in two parts"
        for day in ["2026-08-10", "2026-08-01"] {
            sofa.firstCharge = day
            for attempt in [{ try VaultPatch.apply(sofa, to: twice, now: self.now) },
                            { try VaultPatch.saveCommitment(sofa, in: twice, now: self.now) }] {
                XCTAssertThrowsError(try attempt(), day) {
                    XCTAssertEqual($0.friendlyDescription,
                                   "This one-time commitment has 2 charges. Move the one you mean from the charge itself.")
                }
            }
        }
        sofa.firstCharge = nil
        let kept = try VaultPatch.apply(sofa, to: twice, now: now)
        XCTAssertEqual(Fx.rows(kept, of: "sofa").compactMap { $0["date"] as? String }, ["2026-07-01", "2026-08-01"])
        XCTAssertEqual(row(kept, "sofa")?["notes"] as? String, "Delivered in two parts")
    }

    /// A recurring commitment holding exactly one charge, made one-time with a new date: the
    /// charge moves there with its amount, its mark and what backs it, as a one-time
    /// commitment's date edit moves it, whatever the cycle was. An unchanged date moves nothing.
    func testARecurringCommitmentWithOneChargeMadeOneTimeMovesItToTheNewDate() throws {
        var single = planVault()
        single["charges"] = [Fx.rawRow("flix", "2026-07-05", amount: 649, paid: true, basis: "statement")]
        let moved = flix { $0.billingCycle = .once; $0.firstCharge = "2026-08-09" }
        for switched in try [VaultPatch.apply(moved, to: single, now: now),
                             VaultPatch.saveCommitment(moved, in: single, now: now)] {
            XCTAssertEqual(row(switched, "flix")?["billing_cycle"] as? String, "once")
            let rows = Fx.rows(switched, of: "flix")
            XCTAssertEqual(rows.compactMap { $0["date"] as? String }, ["2026-08-09"])
            XCTAssertEqual(rows.first?["amount"] as? Double, 649)
            XCTAssertEqual(rows.first?["paid"] as? Bool, true)
            XCTAssertEqual(rows.first?["basis"] as? String, "statement")
        }
        let unmoved = try VaultPatch.apply(flix { $0.billingCycle = .once; $0.firstCharge = "2026-07-05" }, to: single, now: now)
        XCTAssertEqual(Fx.rows(unmoved, of: "flix").compactMap { $0["date"] as? String }, ["2026-07-05"])

        let yearly = Fx.raw([Fx.rawSub(id: "dom", name: "Domain", amount: 900, cycle: "yearly")],
                            charges: [Fx.rawRow("dom", "2027-01-10", amount: 900)])
        var domain = SubEdit(id: "dom")
        domain.name = "Domain"
        domain.amount = 900
        domain.currency = "INR"
        domain.billingCycle = .once
        domain.firstCharge = "2026-12-01"
        let made = try VaultPatch.apply(domain, to: yearly, now: now)
        XCTAssertEqual(Fx.rows(made, of: "dom").compactMap { $0["date"] as? String }, ["2026-12-01"], "a yearly one moves alike")
    }

    /// A Save that pauses, cancels, ends or shortens the plan and moves the next charge: when
    /// that change takes the charge away first, the refusal names its day, never an id.
    func testAMoveTheSameSaveTookAwayIsRefusedByItsDay() throws {
        let move = VaultPatch.ChargeChange(from: "2026-08-05", to: "2026-08-09")
        // "5 Aug 2026" where the reader's locale says it so; the words around it are fixed.
        let day = LB.longDate(LB.day(2026, 8, 5))
        var shorter = planVault()
        var rows = shorter["charges"] as? [[String: Any]] ?? []
        rows[2]["paid"] = true
        rows[3]["basis"] = "user"
        shorter["charges"] = rows
        let cases: [(String, SubEdit, Int?, [String: Any], String)] = [
            ("a pause", flix { $0.status = .paused }, nil, planVault(),
             "Pausing removes the charge on \(day), so it can't be moved. Move it first, then pause."),
            ("a cancel", flix { $0.status = .cancelled }, nil, planVault(),
             "Cancelling removes the charge on \(day), so it can't be moved. Move it first, then cancel."),
            ("a cancelling date", flix { $0.scheduledCancelDate = "2026-07-31" }, nil, planVault(),
             "\(day) is past the cancelling date, so it can't be moved. Move it first, then set the cancelling date."),
            ("a shorter plan", flix(), 1, shorter,
             "The shorter plan removes the charge on \(day), so it can't be moved. Move it first, then shorten the plan."),
        ]
        for (what, edit, count, raw, words) in cases {
            XCTAssertThrowsError(try VaultPatch.saveCommitment(edit, plannedCount: count, charge: move, in: raw, now: now), what) {
                XCTAssertEqual($0.friendlyDescription, words, what)
                XCTAssertFalse($0.friendlyDescription.contains("flix"), "\(what): no internal id")
            }
        }
        // Gone before the Save — another device took it — is said as that.
        XCTAssertThrowsError(try VaultPatch.saveCommitment(flix(), charge: .init(from: "2026-08-06", to: "2026-08-09", andLater: false),
                                                           in: planVault(), now: now)) {
            XCTAssertEqual($0.friendlyDescription,
                           "The charge on \(LB.longDate(LB.day(2026, 8, 6))) is no longer in your file. It was removed or moved while this was open.")
        }
    }

    /// The pause and cancel sentences are said only when the Save stops an active commitment;
    /// one already paused or cancelled is never blamed on its own state.
    func testOnlyAStopFromActiveIsBlamedForAChargeTheSaveTookAway() {
        let day = LB.longDate(LB.day(2026, 9, 5))
        let shorter = "The shorter plan removes the charge on \(day), so it can't be moved. Move it first, then shorten the plan."
        let cases: [(SubStatus, SubStatus, String)] = [
            (.active, .paused, "Pausing removes the charge on \(day), so it can't be moved. Move it first, then pause."),
            (.active, .cancelled, "Cancelling removes the charge on \(day), so it can't be moved. Move it first, then cancel."),
            (.paused, .paused, shorter), (.cancelled, .cancelled, shorter), (.paused, .cancelled, shorter),
            (.active, .active, shorter),
        ]
        for (was, status, words) in cases {
            XCTAssertEqual(VaultPatch.unmovable("2026-09-05", by: flix { $0.status = status }, was: was, held: true), words,
                           "\(was.rawValue) to \(status.rawValue)")
        }
    }

    // MARK: - planning lands only from today on, on an active commitment

    /// A charge row as one line — day, amount, mark, what backs it — so a test states whole rows.
    private func lines(_ raw: [String: Any], of id: String) -> [String] {
        Fx.rows(raw, of: id).map { row in
            let paid = (row["paid"] as? Bool) == true ? "paid" : "unpaid"
            return "\(row["date"] as? String ?? "") \(plainAmount(row["amount"] as? Double ?? -1)) \(paid) \(row["basis"] as? String ?? "")"
        }
    }

    /// Streaming, monthly: "6 times" chosen, then Cancelled or Paused in the same Save. The stop
    /// unwrites the plan after today, and the count is not planned back onto it.
    func testASaveThatStopsTheCommitmentPlansNothing() throws {
        for status in [SubStatus.cancelled, .paused] {
            let saved = try VaultPatch.saveCommitment(flix { $0.status = status }, plannedCount: 6,
                                                      in: planVault(), now: now)
            XCTAssertEqual(lines(saved, of: "flix"), ["2026-07-05 649 paid statement"], status.rawValue)
        }
    }

    /// Already paused, with charges written ahead: a Save that keeps it paused writes no count,
    /// so the charge it moves is still there to move.
    func testASaveOnAPausedCommitmentMovesItsChargeAndPlansNothing() throws {
        var paused = planVault()
        var subs = paused["commitments"] as? [[String: Any]] ?? []
        subs[0]["status"] = "paused"
        paused["commitments"] = subs
        let saved = try VaultPatch.saveCommitment(flix { $0.status = .paused }, plannedCount: 1,
                                                  charge: .init(from: "2026-09-05", to: "2026-09-09", andLater: false),
                                                  in: paused, now: now)
        XCTAssertEqual(lines(saved, of: "flix"),
                       ["2026-07-05 649 paid statement", "2026-08-05 649 unpaid plan", "2026-09-09 649 unpaid user",
                        "2026-10-05 649 unpaid plan"])
    }

    /// Gym, active, its plan lapsed after 5 Mar. On 23 Jul, three more months of plan are the
    /// three cycle days from today on, never the months behind it; a cycle day on today is
    /// written, as plan.
    func testPlanningMoreOnALapsedPlanNeverStartsBeforeToday() throws {
        let gym = Fx.raw([Fx.rawSub(id: "gym", name: "Gym", amount: 1500)],
                         charges: [Fx.rawRow("gym", "2026-02-05", amount: 1500, paid: true, basis: "statement"),
                                   Fx.rawRow("gym", "2026-03-05", amount: 1500, paid: true, basis: "statement")])
        XCTAssertEqual(lines(try VaultPatch.plan(commitmentId: "gym", months: 3, in: gym, now: now), of: "gym"),
                       ["2026-02-05 1500 paid statement", "2026-03-05 1500 paid statement",
                        "2026-08-05 1500 unpaid plan", "2026-09-05 1500 unpaid plan", "2026-10-05 1500 unpaid plan"])

        let fee = Fx.raw([Fx.rawSub(id: "fee", name: "Fee", amount: 300)],
                         charges: [Fx.rawRow("fee", "2026-06-23", amount: 300, paid: true, basis: "statement")])
        XCTAssertEqual(lines(try VaultPatch.plan(commitmentId: "fee", months: 1, in: fee, now: now), of: "fee"),
                       ["2026-06-23 300 paid statement", "2026-07-23 300 unpaid plan"])

        // A plan still running past today continues from the step after its last charge.
        XCTAssertEqual(lines(try VaultPatch.plan(commitmentId: "flix", months: 2, in: planVault(), now: now), of: "flix"),
                       ["2026-07-05 649 paid statement", "2026-08-05 649 unpaid plan", "2026-09-05 649 unpaid plan",
                        "2026-10-05 649 unpaid plan", "2026-11-05 649 unpaid plan", "2026-12-05 649 unpaid plan"])
    }

    /// Fee, monthly, last charged 23 Jun; on 23 Jul its cycle day is today. A chosen count
    /// writes it, and the count the form reads is the one Save sets: asked again, the same
    /// count writes nothing, and a shorter one keeps today's row.
    func testACycleDayOnTodayIsPlannedAndCountedAhead() throws {
        let fee = Fx.raw([Fx.rawSub(id: "fee", name: "Fee", amount: 300)],
                         charges: [Fx.rawRow("fee", "2026-06-23", amount: 300, paid: true, basis: "statement")])
        let two = try VaultPatch.setPlannedCount(commitmentId: "fee", count: 2, in: fee, now: now)
        XCTAssertEqual(lines(two, of: "fee"),
                       ["2026-06-23 300 paid statement", "2026-07-23 300 unpaid plan", "2026-08-23 300 unpaid plan"])
        let vault = try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: two))
        let sub = try XCTUnwrap(vault.subscriptions.first)
        XCTAssertEqual(plannedAhead(sub, in: vault, now).map { LB.toISO($0.date) }, ["2026-07-23", "2026-08-23"])

        let again = try VaultPatch.setPlannedCount(commitmentId: "fee", count: 2, in: two, now: now)
        XCTAssertEqual(lines(again, of: "fee"),
                       ["2026-06-23 300 paid statement", "2026-07-23 300 unpaid plan", "2026-08-23 300 unpaid plan"],
                       "two stand ahead already")
        let one = try VaultPatch.setPlannedCount(commitmentId: "fee", count: 1, in: two, now: now)
        XCTAssertEqual(lines(one, of: "fee"), ["2026-06-23 300 paid statement", "2026-07-23 300 unpaid plan"])
    }

    // MARK: - a free trial

    /// A trial is one flag on the row: ticked, Save writes `free_trial: true` and no charge, and
    /// the plan starts at full price on the first charge's day as it would without the tick.
    /// Unticked, the key goes and the rows stay as they were.
    func testATrialIsAFlagOnTheRowAndWritesNoCharge() throws {
        var edit = valid { $0.name = "Music"; $0.firstCharge = "2026-08-06"; $0.planCount = 2 }
        edit.freeTrial = true
        let out = try VaultPatch.saveCommitment(edit, in: richVault(), now: now)
        let id = try XCTUnwrap(subs(out).last?["id"] as? String)
        XCTAssertEqual(lines(out, of: id), ["2026-08-06 100 unpaid plan", "2026-09-06 100 unpaid plan"])
        XCTAssertEqual(row(out, id)?["free_trial"] as? Bool, true)

        let vault = try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: out))
        let sub = try XCTUnwrap(vault.subscriptions.first { $0.id == id })
        XCTAssertTrue(isFreeTrial(sub), "the core reads the flag back")
        XCTAssertTrue(SubEdit(from: sub).freeTrial, "and the form opens on it")

        var untick = SubEdit(from: sub)
        untick.freeTrial = false
        let later = LB.day(2026, 7, 30)
        let cleared = try VaultPatch.saveCommitment(untick, in: out, now: later)
        XCTAssertNil(row(cleared, id)?["free_trial"], "off is no key at all")
        XCTAssertEqual(lines(cleared, of: id), ["2026-08-06 100 unpaid plan", "2026-09-06 100 unpaid plan"])
        XCTAssertEqual(row(cleared, id)?["updated_at"] as? String, VaultPatch.iso8601(later), "the flag is a field of the row")
    }

    /// Ticked on an existing commitment, one charged today included: the flag lands, nothing is
    /// refused, and the rows are as they were. A tick alone is a change of the row.
    func testTickingATrialOnAnExistingCommitmentWritesOnlyTheFlag() throws {
        var vault = planVault()
        vault["charges"] = [Fx.rawRow("flix", "2026-07-23", amount: 649), Fx.rawRow("flix", "2026-08-23", amount: 649)]
        XCTAssertTrue(VaultPatch.changesNothing(flix(), in: vault))
        let ticked = flix { $0.freeTrial = true }
        XCTAssertFalse(VaultPatch.changesNothing(ticked, in: vault), "a flag-only Save is written")
        let out = try VaultPatch.saveCommitment(ticked, in: vault, now: now)
        XCTAssertEqual(row(out, "flix")?["free_trial"] as? Bool, true)
        XCTAssertEqual(lines(out, of: "flix"), ["2026-07-23 649 unpaid plan", "2026-08-23 649 unpaid plan"])
        XCTAssertTrue(VaultPatch.changesNothing(ticked, in: out), "and agrees with the file once there")
    }

    // MARK: - back to active

    /// Paused with nothing ahead, then set back to Active with a count: the Save plans that
    /// many from the next cycle on, as the form sends its count on a resume.
    func testResumingAPausedCommitmentPlansByTheCount() throws {
        var paused = planVault()
        var subs = paused["commitments"] as? [[String: Any]] ?? []
        subs[0]["status"] = "paused"
        paused["commitments"] = subs
        paused["charges"] = [Fx.rawRow("flix", "2026-07-05", amount: 649, paid: true, basis: "statement")]
        let resumed = try VaultPatch.saveCommitment(flix { $0.status = .active }, plannedCount: 3, in: paused, now: now)
        XCTAssertEqual(row(resumed, "flix")?["status"] as? String, "active")
        XCTAssertEqual(lines(resumed, of: "flix"),
                       ["2026-07-05 649 paid statement", "2026-08-05 649 unpaid plan",
                        "2026-09-05 649 unpaid plan", "2026-10-05 649 unpaid plan"])
    }

    // MARK: - a price stored past the limit

    /// Another writer left a price past the limit. A write that leaves the price as it is still
    /// lands — a rename, a charge's own amount beside the commitment's notes, a cancel — and a
    /// price the write changes is held to the limit.
    func testAStoredPricePastTheLimitRefusesOnlyAWriteThatChangesIt() throws {
        let huge = 9.3e18
        let raw = Fx.raw([Fx.rawSub(id: "slip", name: "Slip", amount: huge)],
                         charges: [Fx.rawRow("slip", "2026-08-05", amount: 649), Fx.rawRow("slip", "2026-09-05", amount: 649)])
        var edit = SubEdit(id: "slip")
        edit.name = "Streaming"
        edit.amount = huge
        edit.currency = "INR"
        let renamed = try VaultPatch.saveCommitment(edit, in: raw, now: now)
        XCTAssertEqual(row(renamed, "slip")?["name"] as? String, "Streaming")
        XCTAssertEqual(row(renamed, "slip")?["amount"] as? Double, huge)

        edit.name = "Slip"
        edit.notes = "Plan: Premium"
        let corrected = try VaultPatch.saveCommitment(edit, charge: .init(from: "2026-08-05", amount: 699), in: raw, now: now)
        XCTAssertEqual(lines(corrected, of: "slip"), ["2026-08-05 699 unpaid user", "2026-09-05 649 unpaid plan"])
        XCTAssertEqual(row(corrected, "slip")?["notes"] as? String, "Plan: Premium")

        let cancelled = try VaultPatch.cancel(id: "slip", in: raw, now: now)
        XCTAssertEqual(row(cancelled, "slip")?["status"] as? String, "cancelled")

        edit.amount = 2e15
        XCTAssertThrowsError(try VaultPatch.saveCommitment(edit, in: raw, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "The amount can't be more than 1,000,000,000,000,000.")
        }
    }

    // MARK: - a custom cycle stored past the limit

    /// Another writer left more days between charges than any write takes. A write that leaves
    /// them as they are still lands — a rename with a count, stepped a hundred years apart
    /// without trapping, and a cancel — and days the write changes are held to the limit.
    func testAStoredCyclePastTheLimitRefusesOnlyAWriteThatChangesIt() throws {
        let far = 99_999_999_999_999_999
        var gas = Fx.rawSub(id: "gas", name: "Gas", amount: 900, cycle: "custom")
        gas["custom_cycle_days"] = far
        let raw = Fx.raw([gas], charges: [Fx.rawRow("gas", "2026-07-01", amount: 900, paid: true, basis: "statement")])
        var edit = SubEdit(id: "gas")
        edit.name = "Gas cylinder"
        edit.amount = 900
        edit.currency = "INR"
        edit.billingCycle = .custom
        edit.customCycleDays = far
        let renamed = try VaultPatch.saveCommitment(edit, plannedCount: 2, in: raw, now: now)
        XCTAssertEqual(row(renamed, "gas")?["name"] as? String, "Gas cylinder")
        XCTAssertEqual(row(renamed, "gas")?["custom_cycle_days"] as? Int, far)
        XCTAssertEqual(lines(renamed, of: "gas"),
                       ["2026-07-01 900 paid statement", "2126-06-07 900 unpaid plan", "2226-05-14 900 unpaid plan"])
        XCTAssertEqual(row(try VaultPatch.cancel(id: "gas", in: raw, now: now), "gas")?["status"] as? String, "cancelled")

        edit.customCycleDays = 50_000
        XCTAssertThrowsError(try VaultPatch.saveCommitment(edit, in: raw, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "A custom cycle is 1 to 36,500 days between charges.")
        }
        edit.customCycleDays = 45
        XCTAssertEqual(row(try VaultPatch.saveCommitment(edit, in: raw, now: now), "gas")?["custom_cycle_days"] as? Int, 45)
    }

    // MARK: - the disk writer

    /// JSON has no infinity and no NaN, and serialising either raises an Objective-C exception
    /// no Swift catch can stop, which would end the app. Such a vault is refused as an error
    /// before it is serialised, wherever the number sits, and the file stays as it was.
    func testTheDiskWriterRefusesANumberThatIsNotFiniteRatherThanCrashing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try VaultDisk.write(richVault(), to: folder, expecting: nil)
        let before = try VaultReader.load(from: folder)

        var price = before.raw
        var commitments = subs(price)
        commitments[0]["amount"] = Double.infinity
        price["commitments"] = commitments
        var charge = before.raw
        var rows = charge["charges"] as? [[String: Any]] ?? []
        rows[1]["amount"] = Double.nan
        charge["charges"] = rows
        var buried = before.raw
        buried["settings"] = ["limits": [["cap": -Double.infinity]]]

        for (what, next) in [("an infinite price", price), ("a charge that is not a number", charge),
                             ("a number deep in a key this build does not model", buried)] {
            XCTAssertThrowsError(try VaultDisk.write(next, to: folder, expecting: before.bytes), what) {
                XCTAssertTrue($0 is WriteError, "\(what): refused as a WriteError, \($0)")
            }
            XCTAssertEqual(try VaultReader.load(from: folder).bytes, before.bytes, "\(what): the file is as it was")
        }
    }
}
