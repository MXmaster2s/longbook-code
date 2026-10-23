// A proposal from the cloud, applied to the memory here. These are the payloads the MCP
// servers file; this suite proves what the APP does with them — the rows, the name it
// signs them with, and every refusal that keeps a bad one off the file.
import XCTest
@testable import LongbookCore

final class PendingApplyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    /// Round-tripped through JSON on purpose: a real vault and a real payload both arrive
    /// as NSNumbers from JSONSerialization, and a Swift Int literal would not be the same
    /// thing — the app's validator reads amounts as Double.
    private func json(_ object: [String: Any]) -> [String: Any] {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func seeded() -> [String: Any] {
        json([
            "app": "longbook",
            "version": 3,
            "commitments": [
                ["id": "c-net", "name": "Netflix", "amount": 649, "currency": "INR",
                 "billing_cycle": "monthly", "status": "active"],
                ["id": "c-gym", "name": "Gym", "amount": 1500, "currency": "INR",
                 "billing_cycle": "monthly", "status": "active"],
                ["id": "c-old", "name": "Hotstar", "amount": 299, "currency": "INR",
                 "billing_cycle": "monthly", "status": "cancelled"],
            ],
            "charges": [
                ["commitment_id": "c-net", "date": "2026-09-01", "amount": 649, "paid": false, "basis": "plan"],
                ["commitment_id": "c-net", "date": "2026-10-01", "amount": 649, "paid": false, "basis": "plan"],
                ["commitment_id": "c-gym", "date": "2026-09-05", "amount": 1500, "paid": false, "basis": "plan"],
                ["commitment_id": "c-gym", "date": "2026-10-05", "amount": 1500, "paid": false, "basis": "plan"],
            ],
            "members": [["id": "m-rohit", "name": "Rohit", "name_key": "rohit"]],
            "accounts": [["id": "a-hdfc", "name": "HDFC", "name_key": "hdfc"]],
        ])
    }

    private func write(_ kind: String, _ payload: [String: Any], source: String? = "gmail:18c2a", key: String? = "claude-daily-brief", createdAt: Date? = nil) -> PendingWrite {
        PendingWrite(id: UUID(), kind: kind, payload: json(payload), sourceRef: source, keyName: key, createdAt: createdAt)
    }

    private func vault(_ outcome: PendingApply.Outcome) throws -> [String: Any] {
        guard case .vault(let raw) = outcome else { throw XCTSkip("not a vault outcome") }
        return raw
    }

    /// The app's own signing names are the app's alone: a key or client wearing one, in any
    /// letter case, signs as the door it came through, so its rows still stand for review.
    func testAKeyOrClientNamedLikeTheAppSignsAsTheDoor() {
        for name in ["longbook-phone", "Longbook-Mac", "LONGBOOK-IOS"] {
            XCTAssertEqual(PendingWrite(id: UUID(), kind: "mark_paid", payload: [:], keyName: name).author, "mcp", name)
            XCTAssertEqual(PendingWrite(id: UUID(), kind: "mark_paid", payload: [:], origin: "oauth", client: name).author, "Your AI", name)
            XCTAssertEqual(PendingWrite(id: UUID(), kind: "mark_paid", payload: [:], keyName: name, client: "claude-desktop").author, "mcp",
                           "a key wearing the name does not fall back to the client's")
        }
        XCTAssertEqual(PendingWrite(id: UUID(), kind: "mark_paid", payload: [:], keyName: "longbook-daily").author, "longbook-daily",
                       "a near miss is the key's own word, and stands for review by its exact name")
        XCTAssertEqual(PendingWrite(id: UUID(), kind: "mark_paid", payload: [:], client: "Claude Desktop").author, "Claude Desktop")
    }

    /// A proposal's charges are signed as the key's under their own keys too: the writer's app
    /// stamp on a charge never survives, so no device adopts an AI write as the owner's own.
    /// An app stamp the file already held on another charge is left alone.
    func testAProposalsChargesAreSignedAsTheKeysNotTheApps() throws {
        var start = seeded()
        start["_provenance"] = ["c-net@2026-10-01": ["edited_by": "longbook-phone", "edited_at": "2026-08-01T00:00:00Z"]]
        let marked = try vault(try PendingApply.apply(write("mark_paid", ["id": "c-net", "date": "2026-09-01"]), to: start, now: now))
        let prov = try XCTUnwrap(marked["_provenance"] as? [String: Any])
        XCTAssertEqual((prov["c-net@2026-09-01"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        XCTAssertEqual((prov["c-net@2026-09-01"] as? [String: Any])?["source"] as? String, "gmail:18c2a")
        XCTAssertEqual((prov["c-net"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        XCTAssertEqual((prov["c-net@2026-10-01"] as? [String: Any])?["edited_by"] as? String, "longbook-phone", "untouched, so still the app's")

        let removed = try vault(try PendingApply.apply(write("remove_charges", ["id": "c-gym", "dates": ["2026-10-05"]]), to: seeded(), now: now))
        let gone = (removed["_provenance"] as? [String: Any])?["c-gym@2026-10-05"] as? [String: Any]
        XCTAssertEqual(gone?["edited_by"] as? String, "claude-daily-brief")
        let added = try vault(try PendingApply.apply(write("add_charges", ["id": "c-gym", "charges": [["date": "2026-11-05", "amount": 1500]]]), to: seeded(), now: now))
        XCTAssertFalse((added["_provenance"] as? [String: Any] ?? [:]).values.contains {
            ($0 as? [String: Any])?["edited_by"] as? String == "longbook-phone"
        }, "no entry the proposal wrote reads as the app's")
    }

    func testABatchLandsEveryRowSignedWithTheKeysName() throws {
        let proposal = write("add_commitments", [
            "rows": [
                ["name": "Colony gym", "amount": 2000, "currency": "INR", "billing_cycle": "monthly",
                 "first_charge": "2026-08-01", "plan_months": 3, "tag": "health & fitness",
                 "member": "Rohit", "account": "ICICI Amazon", "notes": "from the receipt"],
                ["name": "Airport taxi", "amount": 950, "currency": "INR", "billing_cycle": "once",
                 "date": "2026-06-10", "paid": true, "basis": "statement",
                 "details": ["destination": "BOM", "trips": 2]],
            ],
        ])
        let raw = try vault(try PendingApply.apply(proposal, to: seeded(), now: now))

        let rows = try XCTUnwrap(raw["commitments"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 5)
        let gym = try XCTUnwrap(rows.first { $0["name"] as? String == "Colony gym" })
        let gymId = try XCTUnwrap(gym["id"] as? String)
        XCTAssertEqual(Fx.rows(raw, of: gymId).map { $0["date"] as? String }, ["2026-08-01", "2026-09-01", "2026-10-01"],
                       "planned from its first charge for as many months as asked")
        XCTAssertEqual(gym["member_id"] as? String, "m-rohit", "an existing member is matched, not duplicated")
        XCTAssertEqual((raw["members"] as? [[String: Any]])?.count, 1)

        // A name nobody has used becomes the app's own placeholder row.
        let accounts = try XCTUnwrap(raw["accounts"] as? [[String: Any]])
        let icici = try XCTUnwrap(accounts.first { $0["name"] as? String == "ICICI Amazon" })
        XCTAssertEqual(icici["is_incomplete"] as? Bool, true)
        XCTAssertEqual(gym["account_id"] as? String, icici["id"] as? String)

        // A library tag registers complete, so the app draws its icon without asking anyone.
        let tags = try XCTUnwrap(raw["tags"] as? [[String: Any]])
        let tag = try XCTUnwrap(tags.first { $0["name_key"] as? String == "health & fitness" })
        XCTAssertEqual(tag["icon"] as? String, "heart")
        XCTAssertEqual(tag["is_default"] as? Bool, true)

        let taxi = try XCTUnwrap(rows.first { $0["name"] as? String == "Airport taxi" })
        XCTAssertNil(taxi["details"], "a proposal from the cloud writes no details: no write tool takes them")
        XCTAssertEqual(taxi["notes"] as? String, "Destination: BOM\nTrips: 2", "what they said is kept, as lines of the notes")
        let taxiRow = try XCTUnwrap(Fx.rows(raw, of: try XCTUnwrap(taxi["id"] as? String)).first)
        XCTAssertEqual(taxiRow["paid"] as? Bool, true, "a statement line arrives paid")
        XCTAssertEqual(taxiRow["basis"] as? String, "statement")

        // Signed with the KEY's name and its source — this is what Changes shows the owner.
        let provenance = try XCTUnwrap(raw["_provenance"] as? [String: Any])
        for name in ["Colony gym", "Airport taxi"] {
            let id = try XCTUnwrap(rows.first { $0["name"] as? String == name }?["id"] as? String)
            let entry = try XCTUnwrap(provenance[id] as? [String: Any])
            XCTAssertEqual(entry["edited_by"] as? String, "claude-daily-brief")
            XCTAssertEqual(entry["source"] as? String, "gmail:18c2a")
        }
    }

    /// A commitment's details are longbook's own: its statement import and its Siri phrase write
    /// the statement line. A proposal from the cloud writes none, whatever kind it is.
    func testOnlyLongbooksOwnWritesSetACommitmentsDetails() throws {
        let line: [String: Any] = ["name": "Swiggy", "amount": 640, "currency": "INR", "billing_cycle": "once",
                                   "date": "2026-07-18", "paid": true, "basis": "statement",
                                   "details": ["statement_line": "UPI-SWIGGY"]]
        func added(origin: String) throws -> [String: Any] {
            let proposal = PendingWrite(id: UUID(), kind: "add_commitments", payload: json(["rows": [line]]), origin: origin)
            let raw = try vault(try PendingApply.apply(proposal, to: seeded(), now: now))
            return try XCTUnwrap((raw["commitments"] as? [[String: Any]])?.first { $0["name"] as? String == "Swiggy" })
        }
        for own in ["statement", "intent"] {
            XCTAssertEqual(try added(origin: own)["details"] as? [String: String], ["statement_line": "UPI-SWIGGY"], own)
            XCTAssertNil(try added(origin: own)["notes"] as? String, "\(own): its details are written as details, never folded")
        }
        for cloud in ["key", "oauth"] {
            XCTAssertNil(try added(origin: cloud)["details"], cloud)
            XCTAssertNil(try added(origin: cloud)["notes"] as? String, "\(cloud): statement_line is longbook's own, never folded")
        }

        // An update names what it takes; the line the row holds stays as it was.
        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows[0]["details"] = ["statement_line": "UPI-NETFLIX.COM"]
        rows.append(["id": "t1", "name": "UPI-RAMESH", "amount": 6000, "currency": "INR", "billing_cycle": "once",
                     "status": "active", "details": ["statement_line": "UPI-RAMESH K-cook"]])
        rows.append(["id": "t2", "name": "UPI-RAMESH", "amount": 6000, "currency": "INR", "billing_cycle": "once", "status": "active"])
        seed["commitments"] = rows
        var charges = seed["charges"] as! [[String: Any]]
        charges.append(["commitment_id": "t1", "date": "2026-07-01", "amount": 6000, "paid": true, "basis": "statement"])
        charges.append(["commitment_id": "t2", "date": "2026-08-01", "amount": 6000, "paid": true, "basis": "statement"])
        seed["charges"] = charges
        seed = json(seed)
        let updated = try vault(try PendingApply.apply(
            write("update_commitment", ["id": "c-net", "set": ["notes": "Plan: Premium", "details": ["plan": "Premium"]]]), to: seed, now: now
        ))
        let netflix = try XCTUnwrap((updated["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "c-net" })
        XCTAssertEqual(netflix["notes"] as? String, "Plan: Premium")
        XCTAssertEqual(netflix["details"] as? [String: String], ["statement_line": "UPI-NETFLIX.COM"])

        // A promotion carries the first row's own line; details it is sent become lines of its notes.
        let promoted = try vault(try PendingApply.apply(
            write("promote_to_recurring", ["ids": ["t1", "t2"], "billing_cycle": "monthly", "name": "Ramesh",
                                           "plan_months": 1, "details": ["role": "cook"]]), to: seed, now: now
        ))
        let ramesh = try XCTUnwrap((promoted["commitments"] as? [[String: Any]])?.first { $0["name"] as? String == "Ramesh" })
        XCTAssertEqual(ramesh["details"] as? [String: String], ["statement_line": "UPI-RAMESH K-cook"])
        XCTAssertEqual(ramesh["notes"] as? String, "Role: cook")
    }

    /// A proposal that carries details keeps what they say: from anywhere but longbook itself,
    /// each detail becomes a "Label: value" line after the notes, never dropped.
    func testDetailsAProposalStillCarriesFoldIntoItsNotes() throws {
        func row(_ raw: [String: Any], _ name: String) throws -> [String: Any] {
            try XCTUnwrap((raw["commitments"] as? [[String: Any]])?.first { $0["name"] as? String == name })
        }
        func added(_ over: [String: Any]) throws -> [String: Any] {
            var term: [String: Any] = ["name": "Term plan", "amount": 24600, "currency": "INR", "billing_cycle": "yearly",
                                       "first_charge": "2026-05-22", "plan_months": 1, "tag": "insurance"]
            term.merge(over) { $1 }
            return try row(try vault(try PendingApply.apply(write("add_commitments", ["rows": [term]]), to: seeded(), now: now)), "Term plan")
        }

        // An add: one line per key after the notes it carries, labelled from the key.
        let both = try added(["notes": "Policy number: 88213",
                              "details": ["insurer": "HDFC Life", "policy_type": "Term", "sum_assured": 10000000]])
        XCTAssertEqual(both["notes"] as? String, "Policy number: 88213\nInsurer: HDFC Life\nPolicy type: Term\nSum assured: 10000000")
        XCTAssertNil(both["details"], "details stay longbook's own")

        // Details alone become the notes; statement_line is longbook's own and never folds.
        let alone = try added(["details": ["insurer": "LIC", "statement_line": "LIC OF INDIA PREMIUM"]])
        XCTAssertEqual(alone["notes"] as? String, "Insurer: LIC")
        XCTAssertNil(alone["details"])
        XCTAssertNil(try added(["details": [String: Any]()])["notes"] as? String, "empty details fold nothing")

        // A key the guide names in other words is labelled as the guide teaches it.
        XCTAssertEqual(try added(["details": ["policy_doc": "documents/term.pdf"]])["notes"] as? String,
                       "Document: documents/term.pdf")

        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows[0]["notes"] = "Billed through: App Store"
        rows[0]["details"] = ["statement_line": "UPI-NETFLIX.COM"]
        seed["commitments"] = rows
        seed = json(seed)
        func updated(_ set: [String: Any]) throws -> [String: Any] {
            try row(try vault(try PendingApply.apply(write("update_commitment", ["id": "c-net", "set": set]), to: seed, now: now)), "Netflix")
        }

        // An update of details alone is a notes update, after the notes the row holds.
        let detailsOnly = try updated(["details": ["plan": "Premium", "profiles": 4]])
        XCTAssertEqual(detailsOnly["notes"] as? String, "Billed through: App Store\nPlan: Premium\nProfiles: 4")
        XCTAssertEqual(detailsOnly["details"] as? [String: String], ["statement_line": "UPI-NETFLIX.COM"], "the row's own line is kept")

        // Beside notes, after the notes the set carries.
        XCTAssertEqual(try updated(["notes": "Plan: Standard", "details": ["profiles": 2]])["notes"] as? String, "Plan: Standard\nProfiles: 2")

        // A line the notes already hold is not repeated, whatever its case or spacing.
        XCTAssertEqual(try updated(["details": ["billed_through": "app  store", "plan": "Premium"]])["notes"] as? String,
                       "Billed through: App Store\nPlan: Premium")
    }

    /// A folded detail is a line of the notes, so the writer's secret scan reads it as it reads any
    /// note — a card number held as a JSON number included, however many digits it runs to.
    func testAFoldedDetailMeetsTheSecretScan() throws {
        let cards: [Any] = [4111111111111111, "4111 1111 1111 1111", [4111111111111111], 10000000000000058]
        for card in cards {
            let proposal = write("add_commitments", ["rows": [["name": "Visa bill", "amount": 10, "currency": "INR",
                                                              "billing_cycle": "once", "date": "2026-09-01",
                                                              "details": ["card_ref": card]]]])
            XCTAssertThrowsError(try PendingApply.apply(proposal, to: seeded(), now: now), "\(card)") { error in
                XCTAssertTrue(error.friendlyDescription.contains("Visa bill"), "the refusal names the row")
                XCTAssertTrue(error.friendlyDescription.contains("longbook is designed not to hold this"), error.friendlyDescription)
            }
        }
        XCTAssertEqual(DetailValue.number(4111111111111111).display, "4111111111111111", "a whole number reads as its digits")
        XCTAssertEqual(DetailValue.number(10000000000000058).display, "10000000000000058", "never an exponent")
        XCTAssertEqual(DetailValue.number(2.5).display, "2.5")
    }

    func testAnUpdateChangesOnlyWhatItNamesAndClearsWithNull() throws {
        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows[0]["notes"] = "the old note"
        seed["commitments"] = rows
        seed = json(seed)

        let raised = try vault(try PendingApply.apply(
            write("update_commitment", ["name": "Netflix", "set": ["amount": 799]]), to: seed, now: now
        ))
        let netflix = try XCTUnwrap((raised["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "c-net" })
        XCTAssertEqual(netflix["amount"] as? Double, 799)
        XCTAssertEqual(netflix["notes"] as? String, "the old note", "what the proposal did not name is untouched")
        XCTAssertEqual(Fx.rows(raised, of: "c-net").map { $0["amount"] as? Double }, [799, 799], "the plan ahead follows the price")

        let cleared = try vault(try PendingApply.apply(
            write("update_commitment", ["id": "c-net", "set": ["notes": NSNull(), "ends_on": "2026-12-01"]]), to: seed, now: now
        ))
        let after = try XCTUnwrap((cleared["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "c-net" })
        XCTAssertTrue(after["notes"] is NSNull)
        XCTAssertEqual(after["ends_on"] as? String, "2026-12-01")
    }

    /// A one-time commitment holding two charges takes no date, as add_charges can leave one:
    /// the proposal is refused in the words every door gives, and without a date it applies.
    func testADateForAOneTimeCommitmentHoldingSeveralChargesIsRefused() throws {
        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows.append(["id": "c-sofa", "name": "Sofa", "amount": 500, "currency": "INR", "billing_cycle": "once", "status": "active"])
        seed["commitments"] = rows
        var charges = seed["charges"] as! [[String: Any]]
        charges.append(["commitment_id": "c-sofa", "date": "2026-07-01", "amount": 500, "paid": true, "basis": "statement"])
        charges.append(["commitment_id": "c-sofa", "date": "2026-09-01", "amount": 500, "paid": false, "basis": "user"])
        seed["charges"] = charges
        seed = json(seed)

        XCTAssertThrowsError(try PendingApply.apply(
            write("update_commitment", ["id": "c-sofa", "set": ["date": "2026-09-10", "notes": "Delivered in two parts"]]), to: seed, now: now
        )) {
            XCTAssertEqual($0.friendlyDescription, "This one-time commitment has 2 charges. Move the one you mean from the charge itself.")
        }
        let noted = try vault(try PendingApply.apply(
            write("update_commitment", ["id": "c-sofa", "set": ["notes": "Delivered in two parts"]]), to: seed, now: now
        ))
        XCTAssertEqual(Fx.rows(noted, of: "c-sofa").compactMap { $0["date"] as? String }, ["2026-07-01", "2026-09-01"])
    }

    func testMarkPaidAndCancelWriteExactlyWhatTheAppWrites() throws {
        let paid = try vault(try PendingApply.apply(
            write("mark_paid", ["name": "Gym", "date": "2026-09-05", "amount": 1400, "paid_on": "2026-09-06"]), to: seeded(), now: now
        ))
        let row = try XCTUnwrap(Fx.rows(paid, of: "c-gym").first)
        XCTAssertEqual(row["paid"] as? Bool, true)
        XCTAssertEqual(row["amount"] as? Double, 1400)
        XCTAssertEqual(row["paid_on"] as? String, "2026-09-06")
        XCTAssertEqual(row["basis"] as? String, "user")
        XCTAssertEqual(Fx.rows(paid, of: "c-gym").count, 2, "a mark is not a second row")

        let cancelled = try vault(try PendingApply.apply(
            write("cancel_commitment", ["id": "c-gym"]), to: seeded(), now: now
        ))
        let gym = try XCTUnwrap((cancelled["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "c-gym" })
        XCTAssertEqual(gym["status"] as? String, "cancelled")
        XCTAssertTrue(Fx.rows(cancelled, of: "c-gym").isEmpty, "what was only planned is unwritten")

        // Cancelling what is already cancelled is a mistake worth reporting, not a no-op.
        XCTAssertThrowsError(try PendingApply.apply(write("cancel_commitment", ["id": "c-old"]), to: seeded(), now: now))
    }

    func testEveryRefusalNamesItsReasonAndNothingIsHalfApplied() throws {
        // A row the app's own validator refuses — the batch never becomes a vault.
        XCTAssertThrowsError(try PendingApply.apply(
            write("add_commitments", ["rows": [["name": "Bad", "amount": 10, "currency": "INR",
                                               "billing_cycle": "monthly", "first_charge": "not-a-date"]]]),
            to: seeded(), now: now
        )) { error in
            XCTAssertTrue(error.friendlyDescription.contains("Bad"), "the refusal names the row")
        }

        // The memory moved on: the row a proposal names is gone, or there are two of it.
        XCTAssertThrowsError(try PendingApply.apply(write("cancel_commitment", ["name": "Spotify"]), to: seeded(), now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("Spotify"))
        }
        var twins = seeded()
        var rows = twins["commitments"] as! [[String: Any]]
        rows.append(["id": "c-gym2", "name": "Gym", "amount": 900, "currency": "INR",
                     "billing_cycle": "monthly", "status": "active"])
        twins["commitments"] = rows
        twins = json(twins)
        XCTAssertThrowsError(try PendingApply.apply(write("cancel_commitment", ["name": "Gym"]), to: twins, now: now))

        // A card number that somehow reached here is refused by this side too.
        XCTAssertThrowsError(try PendingApply.apply(
            write("add_commitments", ["rows": [["name": "Card 4111 1111 1111 1111", "amount": 10, "currency": "INR",
                                               "billing_cycle": "once", "date": "2026-09-01"]]]),
            to: seeded(), now: now
        ))

        // An amount past the limit, filed by a server that did not yet refuse it, meets the
        // app's own check: on a commitment, on a mark and on a charge row alike.
        let huge = 9.3e18
        for proposal in [
            write("add_commitments", ["rows": [["name": "Slip", "amount": huge, "currency": "INR",
                                               "billing_cycle": "once", "date": "2026-09-01"]]]),
            write("mark_paid", ["id": "c-net", "date": "2026-09-01", "amount": huge]),
            write("add_charges", ["id": "c-net", "charges": [["date": "2026-11-01", "amount": huge]]]),
        ] {
            XCTAssertThrowsError(try PendingApply.apply(proposal, to: seeded(), now: now), proposal.kind) { error in
                XCTAssertTrue(error.friendlyDescription.contains("The amount can't be more than 1,000,000,000,000,000."),
                              error.friendlyDescription)
            }
        }

        // A kind this version does not know waits for one that does — it never guesses.
        XCTAssertThrowsError(try PendingApply.apply(write("delete_everything", [:]), to: seeded(), now: now))
    }

    /// A refused row is named by its name only when the name scans clean, as both MCP doors
    /// name it, and otherwise by its place alone: a refusal never repeats what it refused.
    func testARefusedRowIsNamedByItsNameOnlyWhenTheNameScansClean() {
        let card = "4111 1111 1111 1111"
        let clean: [String: Any] = ["name": "Visa", "amount": 10, "currency": "INR",
                                    "billing_cycle": "once", "date": "2026-09-01"]
        func with(_ changes: [String: Any]) -> [String: Any] { clean.merging(changes) { $1 } }
        let cases: [(String, [[String: Any]], String)] = [
            ("a row named by the card", [clean, with(["name": card])], "Row 2 could not be added: \(dataPolicyRefusal)"),
            ("a card in a clean row's notes", [with(["notes": "card \(card)"])],
             "Row 1 (\"Visa\") could not be added: \(dataPolicyRefusal)"),
            ("a member named by the card", [with(["member": card])], "Row 1 (\"Visa\") could not be added: \(dataPolicyRefusal)"),
            ("an account named by the card", [with(["account": card])], "Row 1 (\"Visa\") could not be added: \(dataPolicyRefusal)"),
            ("a row with no name", [clean, clean.filter { $0.key != "name" }],
             "Row 2 could not be added: Give it a name. That's what you'll recognise it by."),
        ]
        for (what, rows, words) in cases {
            XCTAssertThrowsError(try PendingApply.apply(write("add_commitments", ["rows": rows]), to: seeded(), now: now), what) {
                XCTAssertTrue($0.friendlyDescription.hasPrefix(words), "\(what): \($0.friendlyDescription)")
                if words.contains(dataPolicyRefusal) {
                    XCTAssertTrue($0.friendlyDescription.contains("looks like a card number"), "\(what) says what it found")
                }
                XCTAssertFalse($0.friendlyDescription.contains("4111"), "\(what) never repeats what it refused")
            }
        }
    }

    func testChargesCanBeAddedRemovedAndPromoted() throws {
        let added = try vault(try PendingApply.apply(
            write("add_charges", ["id": "c-net", "charges": [
                ["date": "2026-07-01", "amount": 599, "paid": true, "basis": "statement"],
                ["date": "2026-11-01"],
            ]]), to: seeded(), now: now
        ))
        let net = Fx.rows(added, of: "c-net")
        XCTAssertEqual(net.map { $0["date"] as? String }, ["2026-07-01", "2026-09-01", "2026-10-01", "2026-11-01"])
        XCTAssertEqual(net[0]["basis"] as? String, "statement")
        XCTAssertEqual(net[3]["amount"] as? Double, 649, "priced at the commitment's amount when none is given")
        XCTAssertEqual(net[3]["basis"] as? String, "plan")

        let removed = try vault(try PendingApply.apply(
            write("remove_charges", ["id": "c-net", "dates": ["2026-10-01"]]), to: added, now: now
        ))
        XCTAssertEqual(Fx.rows(removed, of: "c-net").count, 3)

        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows.append(["id": "t1", "name": "UPI-RAMESH", "amount": 6000, "currency": "INR", "billing_cycle": "once", "status": "active"])
        rows.append(["id": "t2", "name": "UPI-RAMESH", "amount": 6000, "currency": "INR", "billing_cycle": "once", "status": "active"])
        seed["commitments"] = rows
        var charges = seed["charges"] as! [[String: Any]]
        charges.append(["commitment_id": "t1", "date": "2026-07-01", "amount": 6000, "paid": true, "basis": "statement"])
        charges.append(["commitment_id": "t2", "date": "2026-08-01", "amount": 6000, "paid": true, "basis": "statement"])
        seed["charges"] = charges
        seed = json(seed)
        let promoted = try vault(try PendingApply.apply(
            write("promote_to_recurring", ["ids": ["t1", "t2"], "billing_cycle": "monthly", "name": "Ramesh",
                                           "tag": "household help", "member": "Rohit", "plan_months": 2]), to: seed, now: now
        ))
        let names = (promoted["commitments"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertTrue(names.contains("Ramesh") && !names.contains("UPI-RAMESH"))
        let ramesh = try XCTUnwrap((promoted["commitments"] as? [[String: Any]])?.first { $0["name"] as? String == "Ramesh" })
        XCTAssertEqual(ramesh["member_id"] as? String, "m-rohit")
        let id = try XCTUnwrap(ramesh["id"] as? String)
        XCTAssertEqual(Fx.rows(promoted, of: id).map { $0["date"] as? String }, ["2026-07-01", "2026-08-01", "2026-09-01", "2026-10-01"])
        let signed = promoted["_provenance"] as? [String: Any]
        XCTAssertEqual((signed?[id] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        for gone in ["t1", "t2"] {
            XCTAssertEqual((signed?[gone] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief",
                           "\(gone): the merged row's tombstone is the key's, so the Changes table never says You")
        }
    }

    func testAccountsAndPeopleAreUpdatedByIdOrName() throws {
        var seed = seeded()
        var accounts = seed["accounts"] as! [[String: Any]]
        accounts.append(["id": "a-visa", "name": "HDFC Visa", "name_key": "hdfc visa", "is_incomplete": true])
        accounts.append(["id": "a-amazon", "name": "Amazon Pay", "name_key": "amazon pay"])
        seed["accounts"] = accounts
        seed = json(seed)
        func account(_ raw: [String: Any], _ id: String) throws -> [String: Any] {
            try XCTUnwrap((raw["accounts"] as? [[String: Any]])?.first { $0["id"] as? String == id })
        }
        func member(_ raw: [String: Any], _ id: String) throws -> [String: Any] {
            try XCTUnwrap((raw["members"] as? [[String: Any]])?.first { $0["id"] as? String == id })
        }

        // Renamed and described in one proposal; a bare balance is true as of the write.
        let described = try vault(try PendingApply.apply(
            write("update_account", ["name": "hdfc visa", "set": [
                "name": "Visa 9292", "tag": "credit card", "balance": 18400.5, "parent_account": "HDFC",
            ]]), to: seed, now: now
        ))
        let visa = try account(described, "a-visa")
        XCTAssertEqual(visa["name"] as? String, "Visa 9292")
        XCTAssertEqual(visa["name_key"] as? String, "visa 9292")
        XCTAssertEqual(visa["is_incomplete"] as? Bool, false)
        XCTAssertEqual(visa["tag"] as? String, "credit card")
        XCTAssertEqual(visa["balance"] as? Double, 18400.5)
        XCTAssertEqual(visa["balance_date"] as? String, LB.toISO(now))
        XCTAssertEqual(visa["parent_account_id"] as? String, "a-hdfc", "a parent named in words resolves to its id")
        let tags = try XCTUnwrap(described["tags"] as? [[String: Any]])
        XCTAssertTrue(tags.contains { $0["kind"] as? String == "account" && $0["name_key"] as? String == "credit card" })
        let entry = try XCTUnwrap((described["_provenance"] as? [String: Any])?["a-visa"] as? [String: Any])
        XCTAssertEqual(entry["edited_by"] as? String, "claude-daily-brief")

        // A balance with its day; null clears both.
        let dated = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-hdfc", "set": ["balance": 250000, "balance_date": "2026-08-31"]]), to: seed, now: now
        ))
        XCTAssertEqual(try account(dated, "a-hdfc")["balance_date"] as? String, "2026-08-31")
        let cleared = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-hdfc", "set": ["balance": NSNull()]]), to: dated, now: now
        ))
        XCTAssertTrue(try account(cleared, "a-hdfc")["balance"] is NSNull)
        XCTAssertTrue(try account(cleared, "a-hdfc")["balance_date"] is NSNull)

        // One level only, in both directions; never itself; never a name nobody has.
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-amazon", "set": ["parent_account": "a-visa"]]), to: described, now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-hdfc", "set": ["parent_account": "Amazon Pay"]]), to: described, now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-hdfc", "set": ["parent_account": "a-hdfc"]]), to: seed, now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-hdfc", "set": ["parent_account": "Nobody"]]), to: seed, now: now))
        let freed = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-visa", "set": ["parent_account": NSNull()]]), to: described, now: now
        ))
        XCTAssertTrue(try account(freed, "a-visa")["parent_account_id"] is NSNull)

        // Renaming onto another account refuses; a row that is gone says so by name.
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-visa", "set": ["name": "hdfc"]]), to: seed, now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["name": "Nobody", "set": ["tag": "cash"]]), to: seed, now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("Nobody"))
        }

        // A person: renamed, reached by email, cleared with null.
        let reached = try vault(try PendingApply.apply(
            write("update_member", ["name": "rohit", "set": ["name": "Rohit S", "email": "rohit@example.com"]]), to: seed, now: now
        ))
        XCTAssertEqual(try member(reached, "m-rohit")["name"] as? String, "Rohit S")
        XCTAssertEqual(try member(reached, "m-rohit")["email"] as? String, "rohit@example.com")
        let unreached = try vault(try PendingApply.apply(
            write("update_member", ["id": "m-rohit", "set": ["email": NSNull()]]), to: reached, now: now
        ))
        XCTAssertTrue(try member(unreached, "m-rohit")["email"] is NSNull)
        XCTAssertThrowsError(try PendingApply.apply(write("update_member", ["id": "m-rohit", "set": ["email": "not-an-address"]]), to: seed, now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("update_member", ["id": "m-gone", "set": ["email": "x@y"]]), to: seed, now: now))
    }

    func testABalanceKeepsTheDayItWasFiledAndAParentMustBeOneAccount() throws {
        var seed = seeded()
        var accounts = seed["accounts"] as! [[String: Any]]
        accounts.append(["id": "a-visa", "name": "HDFC Visa", "name_key": "hdfc visa"])
        accounts.append(["id": "a-cash-1", "name": "Cash", "name_key": "cash"])
        accounts.append(["id": "a-cash-2", "name": "cash ", "name_key": "cash"])
        seed["accounts"] = accounts
        seed = json(seed)
        func account(_ raw: [String: Any], _ id: String) throws -> [String: Any] {
            try XCTUnwrap((raw["accounts"] as? [[String: Any]])?.first { $0["id"] as? String == id })
        }

        // Filed one day, applied five days later: the balance keeps the day it was filed.
        let filed = now.addingTimeInterval(-5 * 86_400)
        XCTAssertNotEqual(LB.toISO(filed), LB.toISO(now))
        let dated = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-visa", "set": ["balance": 18400.5]], createdAt: filed), to: seed, now: now
        ))
        XCTAssertEqual(try account(dated, "a-visa")["balance"] as? Double, 18400.5)
        XCTAssertEqual(try account(dated, "a-visa")["balance_date"] as? String, LB.toISO(filed))

        // The day alone moves a balance already held; it never stands undated or without one.
        let moved = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-visa", "set": ["balance_date": "2026-09-01"]]), to: dated, now: now
        ))
        XCTAssertEqual(try account(moved, "a-visa")["balance_date"] as? String, "2026-09-01")
        XCTAssertEqual(try account(moved, "a-visa")["balance"] as? Double, 18400.5)
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-hdfc", "set": ["balance_date": "2026-09-01"]]), to: seed, now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("no balance to date"))
        }
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-visa", "set": ["balance_date": NSNull()]]), to: dated, now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("clear both"))
        }

        // A tag of only a newline clears, and registers nothing.
        let untagged = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-visa", "set": ["tag": "\n"]]), to: seed, now: now
        ))
        XCTAssertTrue(try account(untagged, "a-visa")["tag"] is NSNull)
        XCTAssertFalse((untagged["tags"] as? [[String: Any]] ?? []).contains { ($0["name_key"] as? String ?? "").isEmpty })

        // A parent named in words must be one account; a twin is reached by its id.
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-visa", "set": ["parent_account": "cash"]]), to: seed, now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("More than one account"))
        }
        let hung = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-visa", "set": ["parent_account": "a-cash-2"]]), to: seed, now: now
        ))
        XCTAssertEqual(try account(hung, "a-visa")["parent_account_id"] as? String, "a-cash-2")
    }

    func testAnAccountTakesItsNotesOwnerAndLinkedAccountAndAPersonTheirTag() throws {
        var seed = seeded()
        var accounts = seed["accounts"] as! [[String: Any]]
        accounts.append(["id": "a-coral", "name": "Coral 9292", "name_key": "coral 9292", "details": ["due_day": 5]])
        accounts.append(["id": "a-wallet", "name": "Wallet", "name_key": "wallet"])
        seed["accounts"] = accounts
        var members = seed["members"] as! [[String: Any]]
        members.append(["id": "m-meera", "name": "Meera", "name_key": "meera"])
        seed["members"] = members
        seed = json(seed)
        func account(_ raw: [String: Any], _ id: String) throws -> [String: Any] {
            try XCTUnwrap((raw["accounts"] as? [[String: Any]])?.first { $0["id"] as? String == id })
        }
        func member(_ raw: [String: Any], _ id: String) throws -> [String: Any] {
            try XCTUnwrap((raw["members"] as? [[String: Any]])?.first { $0["id"] as? String == id })
        }

        // Everything the local door takes, under the same names, in one proposal.
        let described = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-coral", "set": [
                "tag": "credit card", "notes": "Card name: Platinum Reserve\nLounge access; fee waived above 4 lakh a year.",
                "member": "meera", "linked_to": "hdfc",
            ]]), to: seed, now: now
        ))
        let coral = try account(described, "a-coral")
        XCTAssertEqual(coral["details"] as? [String: Int], ["due_day": 5], "what details held is kept as held")
        XCTAssertEqual(coral["notes"] as? String, "Card name: Platinum Reserve\nLounge access; fee waived above 4 lakh a year.")
        XCTAssertEqual(coral["member_id"] as? String, "m-meera", "a name resolves to the id")
        XCTAssertEqual(coral["parent_account_id"] as? String, "a-hdfc", "the file key keeps its name")
        XCTAssertEqual(((described["_provenance"] as? [String: Any])?["a-coral"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")

        // The older names still work; linked_to wins when a set carries both.
        let older = try vault(try PendingApply.apply(write("update_account", ["id": "a-wallet", "set": ["parent": "HDFC"]]), to: seed, now: now))
        XCTAssertEqual(try account(older, "a-wallet")["parent_account_id"] as? String, "a-hdfc")
        let both = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-wallet", "set": ["linked_to": NSNull(), "parent_account": "HDFC"]]), to: older, now: now
        ))
        XCTAssertTrue(try account(both, "a-wallet")["parent_account_id"] is NSNull)

        // Cleared by null or by an empty string; the details ride through, and a card name that
        // says nothing folds nothing.
        let cleared = try vault(try PendingApply.apply(
            write("update_account", ["id": "a-coral", "set": ["card_name": "", "notes": NSNull(), "member": "", "linked_to": NSNull()]]),
            to: described, now: now
        ))
        let bare = try account(cleared, "a-coral")
        XCTAssertEqual(bare["details"] as? [String: Int], ["due_day": 5])
        XCTAssertTrue(bare["notes"] is NSNull)
        XCTAssertTrue(bare["member_id"] is NSNull)
        XCTAssertTrue(bare["parent_account_id"] is NSNull)
        let byId = try vault(try PendingApply.apply(write("update_account", ["id": "a-coral", "set": ["member": "m-rohit"]]), to: seed, now: now))
        XCTAssertEqual(try account(byId, "a-coral")["member_id"] as? String, "m-rohit")

        // A person the memory does not hold is never made here; a folded card name meets the
        // secret scan as any line of the notes does.
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-coral", "set": ["member": "Nobody"]]), to: seed, now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("Nobody"))
        }
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-coral", "set": ["card_name": "Visa 4111 1111 1111 1111"]]), to: seed, now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("longbook is designed not to hold this"), error.friendlyDescription)
        }
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-coral", "set": ["notes": "pin: 4821"]]), to: seed, now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("update_account", ["id": "a-coral", "set": ["linked_to": "a-coral"]]), to: seed, now: now)) { error in
            XCTAssertTrue(error.friendlyDescription.contains("linked to itself"))
        }

        // A person's tag is their role: the library's entry arrives whole, a new one is kept, null clears.
        let tagged = try vault(try PendingApply.apply(write("update_member", ["name": "meera", "set": ["tag": " household help "]]), to: seed, now: now))
        XCTAssertEqual(try member(tagged, "m-meera")["tag"] as? String, "household help")
        let registry = try XCTUnwrap(tagged["tags"] as? [[String: Any]])
        let role = try XCTUnwrap(registry.first { $0["kind"] as? String == "member" && $0["name_key"] as? String == "household help" })
        XCTAssertEqual(role["is_default"] as? Bool, true)
        XCTAssertEqual(role["icon"] as? String, "person.badge.clock")
        let invented = try vault(try PendingApply.apply(write("update_member", ["id": "m-meera", "set": ["tag": "tutor"]]), to: tagged, now: now))
        XCTAssertEqual(try member(invented, "m-meera")["tag"] as? String, "tutor")
        XCTAssertTrue((invented["tags"] as? [[String: Any]] ?? []).contains { $0["kind"] as? String == "member" && $0["name_key"] as? String == "tutor" })
        let untagged = try vault(try PendingApply.apply(write("update_member", ["id": "m-meera", "set": ["tag": NSNull()]]), to: invented, now: now))
        XCTAssertTrue(try member(untagged, "m-meera")["tag"] is NSNull)
        XCTAssertEqual(try member(untagged, "m-meera")["name"] as? String, "Meera", "a tag change touches nothing else")
    }

    /// An account's card name and details are longbook's own: a proposal filed carrying either
    /// keeps what they say as lines of the notes. A person's are refused.
    func testAFiledCardNameOrDetailsFoldIntoAnAccountsNotesAndAPersonsAreRefused() throws {
        var seed = seeded()
        var accounts = seed["accounts"] as! [[String: Any]]
        accounts.append(["id": "a-coral", "name": "Coral 9292", "name_key": "coral 9292",
                         "notes": "Lounge access", "details": ["card_name": "Coral", "due_day": 5]])
        seed["accounts"] = accounts
        var members = seed["members"] as! [[String: Any]]
        members.append(["id": "m-meera", "name": "Meera", "name_key": "meera", "details": ["relationship": "sister"]])
        seed["members"] = members
        seed = json(seed)
        func coral(_ set: [String: Any]) throws -> [String: Any] {
            let raw = try vault(try PendingApply.apply(write("update_account", ["id": "a-coral", "set": set]), to: seed, now: now))
            return try XCTUnwrap((raw["accounts"] as? [[String: Any]])?.first { $0["id"] as? String == "a-coral" })
        }

        // A card name alone is a line after the notes the account holds; what details held is kept.
        let named = try coral(["card_name": " Platinum Reserve "])
        XCTAssertEqual(named["notes"] as? String, "Lounge access\nCard name: Platinum Reserve")
        XCTAssertEqual((named["details"] as? [String: Any])?["card_name"] as? String, "Coral", "details are never written")

        // Beside notes, after the notes the set carries; details fold too, one line per key.
        let both = try coral(["notes": "Shared card.", "card_name": "Platinum Reserve", "details": ["billing_day": 20, "due_day": 5]])
        XCTAssertEqual(both["notes"] as? String, "Shared card.\nBilling day: 20\nCard name: Platinum Reserve\nDue day: 5")

        // A card name the notes already hold, its label and value in any case or spacing, is not repeated.
        XCTAssertEqual(try coral(["notes": "card name:  platinum reserve", "card_name": "Platinum Reserve"])["notes"] as? String,
                       "card name:  platinum reserve")
        XCTAssertEqual(try coral(["notes": "Card Name :Platinum  Reserve", "card_name": "platinum reserve"])["notes"] as? String,
                       "Card Name :Platinum  Reserve")
        XCTAssertEqual(try coral(["notes": "Due day:5", "details": ["due_day": 5]])["notes"] as? String, "Due day:5")
        // What says nothing folds nothing and leaves the notes as they were.
        XCTAssertEqual(try coral(["card_name": NSNull(), "details": [String: Any](), "tag": "credit card"])["notes"] as? String, "Lounge access")

        // A line naming another card is never replaced: the filed one follows it, and the notes
        // change Changes shows the owner carries both.
        var noted = seed
        var held = try XCTUnwrap(noted["accounts"] as? [[String: Any]])
        let at = try XCTUnwrap(held.firstIndex { $0["id"] as? String == "a-coral" })
        held[at]["notes"] = "Lounge access\nCard name: Coral"
        noted["accounts"] = held
        let applied = try vault(try PendingApply.apply(write("update_account", ["id": "a-coral", "set": ["card_name": "Platinum Reserve"]]), to: noted, now: now))
        let shown = vaultDiff(from: noted, to: applied).first { $0.kind == "accounts" }?
            .changed.first { $0.id == "a-coral" }?.fields.first { $0.key == "notes" }
        XCTAssertEqual(shown?.before, "Lounge access\nCard name: Coral")
        XCTAssertEqual(shown?.after, "Lounge access\nCard name: Coral\nCard name: Platinum Reserve")

        // A person carries a name, a tag, an email and linked accounts: details or a card name is
        // refused, in a sentence the owner reads, so in sentence case.
        let sentence = "Details are longbook's own — a member carries a name, a tag, an email and linked accounts."
        let refused: [[String: Any]] = [["details": ["role": "cook"]], ["tag": "family", "details": ["role": "cook"]], ["card_name": "Coral"]]
        for set in refused {
            XCTAssertThrowsError(try PendingApply.apply(write("update_member", ["id": "m-meera", "set": set]), to: seed, now: now)) { error in
                XCTAssertEqual(error.friendlyDescription, sentence)
            }
        }
        let tagged = try vault(try PendingApply.apply(write("update_member", ["id": "m-meera", "set": ["tag": "family", "details": NSNull()]]), to: seed, now: now))
        let meera = try XCTUnwrap((tagged["members"] as? [[String: Any]])?.first { $0["id"] as? String == "m-meera" })
        XCTAssertEqual(meera["tag"] as? String, "family")
        XCTAssertEqual(meera["details"] as? [String: String], ["relationship": "sister"], "what details held is kept as held")
    }

    func testATransferIsAppliedPaidInPlacePromotedAsOneAndTurnedBackIntoACharge() throws {
        let added = try vault(try PendingApply.apply(write("add_commitments", ["rows": [
            ["name": "Coral card bill", "amount": 31250, "currency": "INR", "billing_cycle": "once", "date": "2026-10-05",
             "paid": false, "basis": "email", "direction": "transfer", "account": "Coral 9292"],
            ["name": "To savings", "amount": 5000, "currency": "INR", "billing_cycle": "once", "date": "2026-08-05",
             "paid": true, "basis": "statement", "direction": "transfer"],
            ["name": "To savings", "amount": 5000, "currency": "INR", "billing_cycle": "once", "date": "2026-09-05",
             "paid": true, "basis": "statement", "direction": "transfer"],
            ["name": "Groceries", "amount": 840, "currency": "INR", "billing_cycle": "once", "date": "2026-09-06",
             "paid": true, "direction": "out"],
        ]]), to: seeded(), now: now))
        func commitments(_ raw: [String: Any], named name: String) -> [[String: Any]] {
            (raw["commitments"] as? [[String: Any]] ?? []).filter { $0["name"] as? String == name }
        }
        let bill = try XCTUnwrap(commitments(added, named: "Coral card bill").first)
        let billId = try XCTUnwrap(bill["id"] as? String)
        XCTAssertEqual(bill["direction"] as? String, "transfer")
        XCTAssertNil(commitments(added, named: "Groceries").first?["direction"] as? String, "\"out\" is never written, as it never was")
        XCTAssertEqual(Fx.rows(added, of: billId).first?["basis"] as? String, "email")
        XCTAssertEqual(Fx.rows(added, of: billId).first?["paid"] as? Bool, false)

        // The decoded vault agrees: shown as a transfer, owed, and in no sum.
        let decoded = try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: added))
        XCTAssertEqual(transferCharges(decoded).map(\.sub.name).sorted(), ["Coral card bill", "To savings", "To savings"])
        XCTAssertFalse(allCharges(decoded).contains { $0.sub.isTransfer })

        // The bill's payment marks that row paid, in place: one row, never a second.
        let paid = try vault(try PendingApply.apply(write("add_charges", ["id": billId, "charges": [
            ["date": "2026-10-05", "paid": true, "paid_on": "2026-10-03", "basis": "email"],
        ]]), to: added, now: now))
        XCTAssertEqual(Fx.rows(paid, of: billId).count, 1)
        XCTAssertEqual(Fx.rows(paid, of: billId).first?["paid"] as? Bool, true)
        XCTAssertEqual(Fx.rows(paid, of: billId).first?["paid_on"] as? String, "2026-10-03")
        XCTAssertEqual((Fx.rows(paid, of: billId).first?["amount"] as? NSNumber)?.doubleValue, 31250)

        // Direction rides along a promotion, and an update turns a row either way.
        let ids = commitments(added, named: "To savings").compactMap { $0["id"] as? String }
        let promoted = try vault(try PendingApply.apply(
            write("promote_to_recurring", ["ids": ids, "billing_cycle": "monthly", "plan_months": 2]), to: added, now: now
        ))
        XCTAssertEqual(commitments(promoted, named: "To savings").map { $0["direction"] as? String }, ["transfer"])
        let spent = try vault(try PendingApply.apply(write("update_commitment", ["id": billId, "set": ["direction": "out"]]), to: added, now: now))
        XCTAssertNil(commitments(spent, named: "Coral card bill").first?["direction"] as? String)
        let moved = try vault(try PendingApply.apply(write("update_commitment", ["id": billId, "set": ["direction": "transfer"]]), to: spent, now: now))
        XCTAssertEqual(commitments(moved, named: "Coral card bill").first?["direction"] as? String, "transfer")
    }

    func testAPromotionThatMixesDirectionsIsRefusedAndAPayloadNeverRedirectsOne() throws {
        let added = try vault(try PendingApply.apply(write("add_commitments", ["rows": [
            ["name": "Tuition", "amount": 9000, "currency": "INR", "billing_cycle": "once", "date": "2026-07-10", "paid": true, "basis": "statement"],
            ["name": "To savings", "amount": 5000, "currency": "INR", "billing_cycle": "once", "date": "2026-07-05",
             "paid": true, "basis": "statement", "direction": "transfer"],
            ["name": "To savings", "amount": 5000, "currency": "INR", "billing_cycle": "once", "date": "2026-08-05",
             "paid": true, "basis": "statement", "direction": "transfer"],
            ["name": "Interest", "amount": 310, "currency": "INR", "billing_cycle": "once", "date": "2026-07-31",
             "paid": true, "basis": "statement", "direction": "in"],
        ]]), to: seeded(), now: now))
        func ids(_ name: String) -> [String] {
            (added["commitments"] as? [[String: Any]] ?? []).filter { $0["name"] as? String == name }.compactMap { $0["id"] as? String }
        }
        let moves = ids("To savings")
        for mixed in [ids("Tuition") + [moves[0]], [moves[0]] + ids("Tuition"), ids("Interest") + [moves[0]]] {
            XCTAssertThrowsError(try PendingApply.apply(write("promote_to_recurring", ["ids": mixed, "billing_cycle": "monthly"]), to: added, now: now)) { error in
                XCTAssertTrue(error.friendlyDescription.contains("These rows do not share a direction"), error.friendlyDescription)
            }
        }
        // A direction smuggled into the payload changes nothing: the rows say which way it goes.
        let promoted = try vault(try PendingApply.apply(
            write("promote_to_recurring", ["ids": moves, "billing_cycle": "monthly", "plan_months": 1, "direction": "in"]), to: added, now: now
        ))
        let standing = (promoted["commitments"] as? [[String: Any]] ?? []).filter { $0["name"] as? String == "To savings" }
        XCTAssertEqual(standing.map { $0["direction"] as? String }, ["transfer"])
    }

    func testInsightsComeBackAsFilesNotVaultEditsAndReportsAreNobodysToWrite() throws {
        // Nothing writes a report but longbook: the retired kind waits for no version.
        XCTAssertThrowsError(try PendingApply.apply(
            write("write_report", ["report": ["id": "rpt-2026-08", "title": "August"]]), to: seeded(), now: now
        )) { XCTAssertEqual($0.friendlyDescription, "This version of longbook does not know how to apply \"write_report\".") }

        guard case .insight(let module, let text) = try PendingApply.apply(
            write("leave_insight", ["module": "dashboard.this_month", "text": "August runs over July."]), to: seeded(), now: now
        ) else { return XCTFail("an insight proposal is a file too") }
        XCTAssertEqual(module, "dashboard.this_month")
        XCTAssertEqual(text, "August runs over July.")
    }

    /// update_charge is the form's own Save on one charge: a move alone keeps the amount as the
    /// owner's word, a reach carries the plan behind it, a new price reaches ahead, null clears.
    func testUpdateChargeMovesRepricesAndClearsAsTheFormDoes() throws {
        let moved = try vault(try PendingApply.apply(
            write("update_charge", ["id": "c-net", "date": "2026-09-01", "set": ["date": "2026-09-03"]]), to: seeded(), now: now
        ))
        XCTAssertEqual(Fx.rows(moved, of: "c-net").map { $0["date"] as? String }, ["2026-09-03", "2026-10-01"])
        XCTAssertEqual(Fx.rows(moved, of: "c-net").first?["basis"] as? String, "user")
        let prov = try XCTUnwrap(moved["_provenance"] as? [String: Any])
        XCTAssertEqual((prov["c-net@2026-09-03"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        XCTAssertEqual((prov["c-net@2026-09-01"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief", "the day left is signed too")
        XCTAssertEqual((prov["c-net"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")

        let run = try vault(try PendingApply.apply(
            write("update_charge", ["id": "c-net", "date": "2026-09-01", "set": ["date": "2026-09-03", "and_later": true]]), to: seeded(), now: now
        ))
        XCTAssertEqual(Fx.rows(run, of: "c-net").map { $0["date"] as? String }, ["2026-09-03", "2026-10-03"], "the plan behind it follows a cycle apart")

        let priced = try vault(try PendingApply.apply(
            write("update_charge", ["name": "Netflix", "date": "2026-09-01", "set": ["amount": 799, "and_later": true]]), to: seeded(), now: now
        ))
        XCTAssertEqual(Fx.rows(priced, of: "c-net").map { $0["amount"] as? Double }, [799, 799])
        XCTAssertEqual(Fx.rows(priced, of: "c-net").map { $0["basis"] as? String }, ["user", "plan"])
        XCTAssertEqual((priced["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "c-net" }?["amount"] as? Double, 799,
                       "the price now, so more plan is written at it")

        var seed = seeded()
        var charges = seed["charges"] as! [[String: Any]]
        charges[0]["paid_on"] = "2026-09-02"
        charges[0]["note"] = "the old note"
        seed["charges"] = charges
        seed = json(seed)
        let cleared = try vault(try PendingApply.apply(
            write("update_charge", ["id": "c-net", "date": "2026-09-01", "set": ["paid": true, "paid_on": NSNull(), "note": NSNull()]]), to: seed, now: now
        ))
        let row = try XCTUnwrap(Fx.rows(cleared, of: "c-net").first)
        XCTAssertEqual(row["paid"] as? Bool, true)
        XCTAssertTrue(row["paid_on"] is NSNull)
        XCTAssertNil(row["note"])
        let dated = try vault(try PendingApply.apply(
            write("update_charge", ["id": "c-net", "date": "2026-09-01", "set": ["paid_on": "2026-09-04", "date": "2026-09-05"]]), to: seed, now: now
        ))
        XCTAssertEqual(Fx.rows(dated, of: "c-net").first?["paid_on"] as? String, "2026-09-04", "the day the money moved rides along with the move")

        XCTAssertThrowsError(try PendingApply.apply(
            write("update_charge", ["id": "c-net", "date": "2026-09-01", "set": ["date": "2026-10-01"]]), to: seeded(), now: now
        )) { XCTAssertTrue($0.friendlyDescription.hasPrefix("A charge already sits on"), $0.friendlyDescription) }
        XCTAssertThrowsError(try PendingApply.apply(
            write("update_charge", ["id": "c-net", "date": "2026-09-02", "set": ["paid": true]]), to: seeded(), now: now
        )) { XCTAssertEqual($0.friendlyDescription, "No charge on 2026-09-02 is written for \"Netflix\".") }
        XCTAssertThrowsError(try PendingApply.apply(
            write("update_charge", ["id": "c-net", "date": "2026-09-01", "set": ["amount": 9.3e18]]), to: seeded(), now: now
        )) { XCTAssertEqual($0.friendlyDescription, "The amount can't be more than 1,000,000,000,000,000.") }
    }

    /// A field a proposal leaves out is left alone; null clears it. Before this mapping an absent
    /// paid_on or note read as a clear, so a plain mark_paid took the day the money moved off the row.
    func testMarkPaidAndAddChargesLeaveAbsentFieldsAloneAndClearWithNull() throws {
        var seed = seeded()
        var charges = seed["charges"] as! [[String: Any]]
        charges[0]["paid_on"] = "2026-09-02"
        charges[0]["note"] = "ahead"
        seed["charges"] = charges
        seed = json(seed)
        let marked = try vault(try PendingApply.apply(write("mark_paid", ["id": "c-net", "date": "2026-09-01"]), to: seed, now: now))
        let kept = try XCTUnwrap(Fx.rows(marked, of: "c-net").first)
        XCTAssertEqual(kept["paid_on"] as? String, "2026-09-02", "absent leaves the day alone")
        XCTAssertEqual(kept["note"] as? String, "ahead")
        let cleared = try vault(try PendingApply.apply(
            write("mark_paid", ["id": "c-net", "date": "2026-09-01", "paid_on": NSNull(), "note": NSNull()]), to: seed, now: now
        ))
        let bare = try XCTUnwrap(Fx.rows(cleared, of: "c-net").first)
        XCTAssertTrue(bare["paid_on"] is NSNull)
        XCTAssertNil(bare["note"])
        let noted = try vault(try PendingApply.apply(write("mark_paid", ["id": "c-net", "date": "2026-09-01", "note": "paid by hand"]), to: seed, now: now))
        XCTAssertEqual(Fx.rows(noted, of: "c-net").first?["note"] as? String, "paid by hand")
        let added = try vault(try PendingApply.apply(
            write("add_charges", ["id": "c-net", "charges": [["date": "2026-09-01", "paid": true]]]), to: seed, now: now
        ))
        XCTAssertEqual(Fx.rows(added, of: "c-net").first?["note"] as? String, "ahead", "add_charges the same")
    }

    func testSetPlannedCountGrowsAndShortensThePlanFromTodayOn() throws {
        let grown = try vault(try PendingApply.apply(write("set_planned_count", ["name": "Netflix", "count": 4]), to: seeded(), now: now))
        XCTAssertEqual(Fx.rows(grown, of: "c-net").map { $0["date"] as? String }, ["2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01"])
        XCTAssertEqual(((grown["_provenance"] as? [String: Any])?["c-net@2026-12-01"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        let cut = try vault(try PendingApply.apply(write("set_planned_count", ["id": "c-net", "count": 1]), to: grown, now: now))
        XCTAssertEqual(Fx.rows(cut, of: "c-net").map { $0["date"] as? String }, ["2026-09-01"])
        XCTAssertThrowsError(try PendingApply.apply(write("set_planned_count", ["id": "c-net", "count": 0]), to: seeded(), now: now))

        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows.append(["id": "c-sofa", "name": "Sofa", "amount": 500, "currency": "INR", "billing_cycle": "once", "status": "active"])
        seed["commitments"] = rows
        seed = json(seed)
        XCTAssertThrowsError(try PendingApply.apply(write("set_planned_count", ["id": "c-sofa", "count": 3]), to: seed, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "A one-time commitment has its one charge; there is nothing to plan.")
        }
    }

    /// The form plans only under an active commitment; a proposal is held to the same rule,
    /// in the doors' own sentence, so nothing lands under a commitment the app labels otherwise.
    func testSetPlannedCountRefusesAPausedOrCancelledCommitment() throws {
        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows[1]["status"] = "paused"
        seed["commitments"] = rows
        seed = json(seed)
        for (which, words) in [("c-old", "\"Hotstar\" is cancelled; set its status to active first, then plan."),
                               ("c-gym", "\"Gym\" is paused; set its status to active first, then plan.")] {
            XCTAssertThrowsError(try PendingApply.apply(write("set_planned_count", ["id": which, "count": 3]), to: seed, now: now), which) {
                XCTAssertEqual($0.friendlyDescription, words)
            }
        }
    }

    func testAddMemberAndAddAccountMakeARowAndRefuseATwin() throws {
        let added = try vault(try PendingApply.apply(
            write("add_member", ["name": " Meera ", "tag": "household help", "email": "meera@example.com"]), to: seeded(), now: now
        ))
        let meera = try XCTUnwrap((added["members"] as? [[String: Any]])?.first { $0["name"] as? String == "Meera" })
        XCTAssertEqual(meera["name_key"] as? String, "meera")
        XCTAssertEqual(meera["is_incomplete"] as? Bool, false)
        XCTAssertEqual(meera["tag"] as? String, "household help")
        XCTAssertEqual(meera["email"] as? String, "meera@example.com")
        XCTAssertTrue((added["tags"] as? [[String: Any]] ?? []).contains { $0["kind"] as? String == "member" && $0["name_key"] as? String == "household help" })
        let id = try XCTUnwrap(meera["id"] as? String)
        XCTAssertEqual(((added["_provenance"] as? [String: Any])?[id] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        let bare = try vault(try PendingApply.apply(write("add_member", ["name": "Arjun", "details": [String: Any]()]), to: seeded(), now: now))
        XCTAssertEqual((bare["members"] as? [[String: Any]])?.first { $0["name"] as? String == "Arjun" }?["is_incomplete"] as? Bool, true,
                       "a name alone is a placeholder")
        XCTAssertThrowsError(try PendingApply.apply(write("add_member", ["name": "rohit"]), to: seeded(), now: now)) {
            XCTAssertEqual($0.friendlyDescription, "There's already a person called rohit.")
        }
        XCTAssertThrowsError(try PendingApply.apply(write("add_member", ["name": "Meera", "details": ["role": "cook"]]), to: seeded(), now: now)) {
            XCTAssertEqual($0.friendlyDescription, "Details are longbook's own — a member carries a name, a tag, an email and linked accounts.")
        }
        XCTAssertThrowsError(try PendingApply.apply(write("add_member", ["name": "Meera", "email": "nope"]), to: seeded(), now: now))

        let account = try vault(try PendingApply.apply(write("add_account", [
            "name": "Coral 9292", "tag": "credit card", "linked_to": "hdfc", "member": "Rohit",
            "notes": "Card name: Coral", "balance": 18400.5,
        ]), to: seeded(), now: now))
        let coral = try XCTUnwrap((account["accounts"] as? [[String: Any]])?.first { $0["name"] as? String == "Coral 9292" })
        XCTAssertEqual(coral["is_incomplete"] as? Bool, false)
        XCTAssertEqual(coral["tag"] as? String, "credit card")
        XCTAssertEqual(coral["parent_account_id"] as? String, "a-hdfc")
        XCTAssertEqual(coral["member_id"] as? String, "m-rohit")
        XCTAssertEqual(coral["notes"] as? String, "Card name: Coral")
        XCTAssertEqual(coral["balance"] as? Double, 18400.5)
        XCTAssertEqual(coral["balance_date"] as? String, LB.toISO(now))
        XCTAssertThrowsError(try PendingApply.apply(write("add_account", ["name": "HDFC"]), to: seeded(), now: now)) {
            XCTAssertEqual($0.friendlyDescription, "There's already an account called HDFC.")
        }
        XCTAssertThrowsError(try PendingApply.apply(write("add_account", ["name": "Wallet", "member": "Nobody"]), to: seeded(), now: now))
        XCTAssertThrowsError(try PendingApply.apply(write("add_account", ["name": "Wallet", "linked_to": "Nowhere"]), to: seeded(), now: now))
        let folded = try vault(try PendingApply.apply(write("add_account", ["name": "Wallet", "card_name": "Platinum"]), to: seeded(), now: now))
        XCTAssertEqual((folded["accounts"] as? [[String: Any]])?.first { $0["name"] as? String == "Wallet" }?["notes"] as? String, "Card name: Platinum",
                       "a card name folds into the notes, as update_account folds it")
    }

    func testRenameTagCarriesRowsAndGroupsAndDeleteTagClearsThem() throws {
        var seed = seeded()
        var rows = seed["commitments"] as! [[String: Any]]
        rows[0]["tag"] = "Home"
        rows[1]["tag"] = "home "
        seed["commitments"] = rows
        seed["tags"] = [
            ["id": "t-home", "kind": "commitment", "name": "Home", "name_key": "home", "is_default": true, "sort": 0, "created_at": "2026-01-01T00:00:00Z"],
            ["id": "t-work", "kind": "commitment", "name": "Work", "name_key": "work", "is_default": false, "sort": 1, "created_at": "2026-01-01T00:00:00Z"],
        ]
        seed["groups"] = [["id": "g1", "kind": "tag", "name": "House", "name_key": "house", "tag_keys": ["home", "work"]]]
        seed = json(seed)

        let renamed = try vault(try PendingApply.apply(write("rename_tag", ["kind": "commitment", "from": "HOME", "to": "Household"]), to: seed, now: now))
        let entry = try XCTUnwrap((renamed["tags"] as? [[String: Any]])?.first { $0["id"] as? String == "t-home" })
        XCTAssertEqual(entry["name"] as? String, "Household")
        XCTAssertEqual(entry["is_default"] as? Bool, false)
        XCTAssertEqual((renamed["commitments"] as? [[String: Any]])?.prefix(2).map { $0["tag"] as? String }, ["Household", "Household"])
        XCTAssertEqual((renamed["groups"] as? [[String: Any]])?.first?["tag_keys"] as? [String], ["household", "work"])
        let prov = try XCTUnwrap(renamed["_provenance"] as? [String: Any])
        XCTAssertEqual((prov["c-net"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        XCTAssertEqual((prov["c-gym"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        XCTAssertNil(prov["t-home"], "tag rows are never signed")
        XCTAssertThrowsError(try PendingApply.apply(write("rename_tag", ["kind": "commitment", "from": "Home", "to": "work"]), to: seed, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "There's already one called \"work\".")
        }
        XCTAssertThrowsError(try PendingApply.apply(write("rename_tag", ["kind": "commitment", "from": "Home", "to": " "]), to: seed, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "Give it a name. That's what you'll recognise it by.")
        }
        XCTAssertThrowsError(try PendingApply.apply(write("rename_tag", ["kind": "commitment", "from": "Travel", "to": "Trips"]), to: seed, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "No commitment tag in the memory is called \"Travel\".")
        }

        let deleted = try vault(try PendingApply.apply(write("delete_tag", ["kind": "commitment", "name": "home"]), to: seed, now: now))
        XCTAssertEqual((deleted["tags"] as? [[String: Any]])?.map { $0["id"] as? String }, ["t-work"])
        XCTAssertTrue((deleted["commitments"] as? [[String: Any]])?[0]["tag"] is NSNull)
        XCTAssertTrue((deleted["commitments"] as? [[String: Any]])?[1]["tag"] is NSNull)
        XCTAssertEqual(((deleted["_provenance"] as? [String: Any])?["c-gym"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        XCTAssertThrowsError(try PendingApply.apply(write("delete_tag", ["kind": "member", "name": "family"]), to: seed, now: now))
    }

    func testDeleteCommitmentRemovesTheRowItsChargesAndTheirEntriesByIdAlone() throws {
        var seed = seeded()
        seed["_provenance"] = [
            "c-net": ["edited_by": "longbook-phone", "edited_at": "2026-08-01T00:00:00Z"],
            "c-net@2026-09-01": ["edited_by": "longbook-phone", "edited_at": "2026-08-01T00:00:00Z"],
            "c-gym": ["edited_by": "claude", "edited_at": "2026-08-01T00:00:00Z"],
        ]
        seed = json(seed)
        let deleted = try vault(try PendingApply.apply(write("delete_commitment", ["id": "c-net"]), to: seed, now: now))
        XCTAssertEqual((deleted["commitments"] as? [[String: Any]])?.map { $0["id"] as? String }, ["c-gym", "c-old"])
        XCTAssertTrue(Fx.rows(deleted, of: "c-net").isEmpty)
        XCTAssertEqual(Fx.rows(deleted, of: "c-gym").count, 2)
        let entries = deleted["_provenance"] as? [String: Any]
        XCTAssertEqual(entries?.keys.sorted(), ["c-gym", "c-net", "c-net@2026-09-01", "c-net@2026-10-01"],
                       "the removed row and its charges leave tombstones")
        XCTAssertEqual((entries?["c-net"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief",
                       "signed by the key, so every device reviews the removal")
        XCTAssertEqual((entries?["c-net@2026-10-01"] as? [String: Any])?["edited_by"] as? String, "claude-daily-brief")
        XCTAssertThrowsError(try PendingApply.apply(write("delete_commitment", ["name": "Netflix"]), to: seed, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "This proposal named no commitment id.")
        }
        XCTAssertThrowsError(try PendingApply.apply(write("delete_commitment", ["id": "c-gone"]), to: seed, now: now)) {
            XCTAssertEqual($0.friendlyDescription, "No commitment with id c-gone is in the memory any more.")
        }
    }

    func testPlanCountPlansExactlyThatManyAndFreeTrialIsAMarkOnTheRow() throws {
        let added = try vault(try PendingApply.apply(write("add_commitments", ["rows": [
            ["name": "Claude", "amount": 20, "currency": "USD", "billing_cycle": "monthly", "first_charge": "2026-09-10", "plan_count": 3, "plan_months": 12],
            ["name": "Term plan", "amount": 24600, "currency": "INR", "billing_cycle": "yearly", "first_charge": "2026-05-22", "plan_count": 2],
        ]]), to: seeded(), now: now))
        func dates(_ name: String) throws -> [String] {
            let id = try XCTUnwrap((added["commitments"] as? [[String: Any]])?.first { $0["name"] as? String == name }?["id"] as? String)
            return Fx.rows(added, of: id).compactMap { $0["date"] as? String }
        }
        XCTAssertEqual(try dates("Claude"), ["2026-09-10", "2026-10-10", "2026-11-10"], "the count is read; plan_months is not")
        XCTAssertEqual(try dates("Term plan"), ["2026-05-22", "2027-05-22"])

        let marked = try vault(try PendingApply.apply(write("update_commitment", ["id": "c-net", "set": ["free_trial": true]]), to: seeded(), now: now))
        let netflix = try XCTUnwrap((marked["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "c-net" })
        XCTAssertEqual(netflix["free_trial"] as? Bool, true)
        XCTAssertEqual(Fx.rows(marked, of: "c-net").count, 2, "no charge row changes")
        let unmarked = try vault(try PendingApply.apply(write("update_commitment", ["id": "c-net", "set": ["free_trial": false]]), to: marked, now: now))
        XCTAssertNil((unmarked["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "c-net" }?["free_trial"], "false takes the key out")
    }

    func testAKeylessProposalIsStillAttributedToSomething() throws {
        let raw = try vault(try PendingApply.apply(
            write("cancel_commitment", ["id": "c-gym"], source: nil, key: nil), to: seeded(), now: now
        ))
        let entry = try XCTUnwrap((raw["_provenance"] as? [String: Any])?["c-gym"] as? [String: Any])
        XCTAssertEqual(entry["edited_by"] as? String, "mcp")
        XCTAssertNil(entry["source"])
    }

    func testAnAppendedInsightKeepsWhatWasThereAndStartsAJunkFileFresh() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("insights-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try InsightsWriter.append(module: "dashboard.this_month", text: "First.", in: folder, now: now)
        try InsightsWriter.append(module: "dashboard.this_month", text: "Second.", in: folder, now: now)
        try InsightsWriter.append(module: "reports.summary", text: "Elsewhere.", in: folder, now: now)

        let byModule = InsightsReader.byModule(in: folder)
        XCTAssertEqual(byModule["dashboard.this_month"]?.text, "Second.", "the last note per module wins")
        XCTAssertEqual(byModule["reports.summary"]?.text, "Elsewhere.")

        try Data("not json".utf8).write(to: folder.appendingPathComponent(InsightsReader.fileName))
        try InsightsWriter.append(module: "dashboard.by_account", text: "Fresh start.", in: folder, now: now)
        XCTAssertEqual(InsightsReader.byModule(in: folder).count, 1)
    }

    func testRemovingAModuleTakesEveryNoteItHoldsAndNoOther() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("insights-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try InsightsWriter.append(module: "dashboard.this_month", text: "First.", in: folder, now: now)
        try InsightsWriter.append(module: "dashboard.this_month", text: "Second.", in: folder, now: now)
        try InsightsWriter.append(module: "account.a1", text: "Stays.", in: folder, now: now)

        try InsightsWriter.remove(module: "dashboard.this_month", in: folder)
        let byModule = InsightsReader.byModule(in: folder)
        XCTAssertNil(byModule["dashboard.this_month"], "both notes for the module go, not only the last")
        XCTAssertEqual(byModule["account.a1"]?.text, "Stays.")

        // Removing what is not there is a quiet no-op, and the file stays a file.
        try InsightsWriter.remove(module: "member.m9", in: folder)
        XCTAssertEqual(InsightsReader.byModule(in: folder).count, 1)
    }
}
