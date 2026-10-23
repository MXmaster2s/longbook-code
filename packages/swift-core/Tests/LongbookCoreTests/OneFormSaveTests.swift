// The commitment form is one screen for a commitment and any one of its charges, and its Save
// is one write: the commitment's fields and its planned count, then the charge's changes.
// Proved on the raw dictionary and, for refusals, on the file. Every fixture is SYNTHETIC.
import XCTest
@testable import LongbookCore

final class OneFormSaveTests: XCTestCase {
    private let now = LB.day(2026, 7, 23)

    /// Streaming, monthly on the 5th: a statement's paid charge behind today and three planned
    /// ahead, beside a one-time sofa not yet delivered, with a key this build does not model.
    private func vault() -> [String: Any] {
        [
            "app": "longbook",
            "version": 3,
            "commitments": [
                [
                    "id": "flix", "name": "Streaming", "amount": 649.0, "currency": "INR",
                    "billing_cycle": "monthly", "status": "active", "some_future_field": "must survive",
                ],
                ["id": "sofa", "name": "Sofa", "amount": 500.0, "currency": "INR", "billing_cycle": "once", "status": "active"],
            ],
            "charges": [
                Fx.rawRow("flix", "2026-07-05", amount: 649, paid: true, basis: "statement"),
                Fx.rawRow("flix", "2026-08-05", amount: 649),
                Fx.rawRow("flix", "2026-09-05", amount: 649),
                Fx.rawRow("flix", "2026-10-05", amount: 649),
                Fx.rawRow("sofa", "2026-08-10", amount: 500),
            ],
        ]
    }

    /// The form's commitment half as it loads Streaming: the file's own fields, changed by `mutate`.
    private func flix(_ mutate: (inout SubEdit) -> Void = { _ in }) -> SubEdit {
        var edit = SubEdit(id: "flix")
        edit.name = "Streaming"
        edit.amount = 649
        edit.currency = "INR"
        mutate(&edit)
        return edit
    }

    private func sub(_ raw: [String: Any], _ id: String) -> [String: Any] {
        (raw["commitments"] as? [[String: Any]] ?? []).first { $0["id"] as? String == id } ?? [:]
    }

    /// A charge row as one line — day, amount, mark, what backs it — so a test states whole rows.
    private func lines(_ raw: [String: Any], of id: String) -> [String] {
        Fx.rows(raw, of: id).map { row in
            let paid = (row["paid"] as? Bool) == true ? "paid" : "unpaid"
            return "\(row["date"] as? String ?? "") \(plainAmount(row["amount"] as? Double ?? -1)) \(paid) \(row["basis"] as? String ?? "")"
        }
    }

    // MARK: - one save

    /// A rename, a tag, notes and five planned charges, with the next charge paid, repriced,
    /// noted and moved with the ones after it: all in one write, exactly as the two halves
    /// taken one after the other leave the file.
    func testOneSaveLandsTheCommitmentTheCountAndTheChargeTogether() throws {
        let edit = flix { $0.name = "Streaming plus"; $0.tag = "Video"; $0.notes = "Plan: 4K" }
        let change = VaultPatch.ChargeChange(from: "2026-08-05", to: "2026-08-09", paid: true, amount: 699,
                                             note: .some("Paid by card"), andLater: true)
        let out = try VaultPatch.saveCommitment(edit, plannedCount: 5, charge: change, in: vault(), now: now)

        let flix = sub(out, "flix")
        XCTAssertEqual(flix["name"] as? String, "Streaming plus")
        XCTAssertEqual(flix["notes"] as? String, "Plan: 4K")
        XCTAssertEqual(flix["amount"] as? Double, 699, "the later charges' reach carried the price")
        XCTAssertEqual(flix["some_future_field"] as? String, "must survive")
        let tags = out["tags"] as? [[String: Any]] ?? []
        XCTAssertTrue(tags.contains { $0["kind"] as? String == "commitment" && $0["name"] as? String == "Video" })
        XCTAssertEqual(lines(out, of: "flix"),
                       ["2026-07-05 649 paid statement", "2026-08-09 699 paid user", "2026-09-09 699 unpaid plan",
                        "2026-10-09 699 unpaid plan", "2026-11-09 699 unpaid plan", "2026-12-09 699 unpaid plan"])
        XCTAssertEqual(Fx.rows(out, of: "flix")[1]["note"] as? String, "Paid by card")
        XCTAssertEqual(lines(out, of: "sofa"), lines(vault(), of: "sofa"), "no other commitment moves")

        var steps = try VaultPatch.saveCommitment(edit, plannedCount: 5, in: vault(), now: now)
        steps = try VaultPatch.editCharge(commitmentId: "flix", from: "2026-08-05", to: "2026-08-09", paid: true,
                                          amount: 699, note: .some("Paid by card"), andLater: true, in: steps, now: now)
        XCTAssertEqual(out["commitments"] as? NSArray, steps["commitments"] as? NSArray)
        XCTAssertEqual(out["charges"] as? NSArray, steps["charges"] as? NSArray)
    }

    /// Marking, pricing, noting or moving one charge is no edit of its commitment: the row, its
    /// stamp and its signature stay as the file holds them. A field changed on the form signs it.
    func testAChargeOnlySaveLeavesTheCommitmentsRowAsItWas() throws {
        let before = sub(vault(), "flix")
        let changes = [VaultPatch.ChargeChange(from: "2026-08-05", paid: true),
                       VaultPatch.ChargeChange(from: "2026-08-05", amount: 699),
                       VaultPatch.ChargeChange(from: "2026-08-05", note: .some("Paid by card")),
                       VaultPatch.ChargeChange(from: "2026-08-05", to: "2026-08-07")]
        for change in changes {
            let out = try VaultPatch.saveCommitment(flix(), charge: change, in: vault(), now: now)
            XCTAssertEqual(NSDictionary(dictionary: sub(out, "flix")), NSDictionary(dictionary: before))
            XCTAssertNil((out["_provenance"] as? [String: Any])?["flix"], "unsigned")
            XCTAssertNil(out["tags"])
            XCTAssertNotEqual(out["charges"] as? NSArray, vault()["charges"] as? NSArray, "the charge itself changed")
        }

        // Money out, however the file stores it, is no change of the row.
        var out = vault()
        var subs = out["commitments"] as? [[String: Any]] ?? []
        subs[0]["direction"] = "out"
        out["commitments"] = subs
        let marked = try VaultPatch.saveCommitment(flix(), charge: .init(from: "2026-08-05", paid: true), in: out, now: now)
        XCTAssertEqual(sub(marked, "flix")["direction"] as? String, "out")
        XCTAssertNil(sub(marked, "flix")["updated_at"])

        let noted = try VaultPatch.saveCommitment(flix { $0.notes = "Plan: 4K" }, charge: .init(from: "2026-08-05", paid: true),
                                                  in: vault(), now: now)
        XCTAssertEqual(sub(noted, "flix")["notes"] as? String, "Plan: 4K")
        XCTAssertEqual(sub(noted, "flix")["updated_at"] as? String, VaultPatch.iso8601(now))
        let signed = (noted["_provenance"] as? [String: Any])?["flix"] as? [String: Any]
        XCTAssertEqual(signed?["edited_by"] as? String, "longbook-phone")
    }

    /// A change that changes nothing writes only the commitment half: no mark, no move.
    func testAnEmptyChargeChangeWritesOnlyTheCommitment() throws {
        let edit = flix { $0.name = "Streaming plus" }
        let plain = try VaultPatch.saveCommitment(edit, in: vault(), now: now)
        for change in [VaultPatch.ChargeChange(from: "2026-08-05"),
                       VaultPatch.ChargeChange(from: "2026-08-05", to: "2026-08-05", andLater: true),
                       VaultPatch.ChargeChange(from: "2026-08-06")] {
            XCTAssertTrue(change.isEmpty)
            let out = try VaultPatch.saveCommitment(edit, charge: change, in: vault(), now: now)
            XCTAssertEqual(out["charges"] as? NSArray, plain["charges"] as? NSArray)
            XCTAssertEqual(out["commitments"] as? NSArray, plain["commitments"] as? NSArray)
        }
    }

    // MARK: - the amount acts on the charge the form is on

    func testTheAmountActsOnTheChargeTheFormIsOn() throws {
        // Recurring, a charge from today on, this charge only: the plan's price stays.
        let only = try VaultPatch.saveCommitment(flix(), charge: .init(from: "2026-09-05", amount: 699),
                                                 in: vault(), now: now)
        XCTAssertEqual(lines(only, of: "flix"),
                       ["2026-07-05 649 paid statement", "2026-08-05 649 unpaid plan", "2026-09-05 699 unpaid user",
                        "2026-10-05 649 unpaid plan"])
        XCTAssertEqual(sub(only, "flix")["amount"] as? Double, 649)

        // Recurring, a charge behind today: that charge alone, past charges one at a time.
        let past = try VaultPatch.saveCommitment(flix(), charge: .init(from: "2026-07-05", amount: 600),
                                                 in: vault(), now: now)
        XCTAssertEqual(lines(past, of: "flix"),
                       ["2026-07-05 600 paid user", "2026-08-05 649 unpaid plan", "2026-09-05 649 unpaid plan",
                        "2026-10-05 649 unpaid plan"])
        XCTAssertEqual(sub(past, "flix")["amount"] as? Double, 649)

        // One-time: the amount is the charge and the price, and the day moves the one charge.
        var sofa = SubEdit(id: "sofa")
        sofa.name = "Sofa"
        sofa.amount = 500
        sofa.currency = "INR"
        sofa.billingCycle = .once
        let once = try VaultPatch.saveCommitment(sofa, charge: .init(from: "2026-08-10", to: "2026-08-12", amount: 550),
                                                 in: vault(), now: now)
        XCTAssertEqual(lines(once, of: "sofa"), ["2026-08-12 550 unpaid user"])
        XCTAssertEqual(sub(once, "sofa")["amount"] as? Double, 550)

        // A commitment with no charge has only its price for the form's amount.
        let bare = Fx.raw([Fx.rawSub(id: "gym", name: "Gym", amount: 1500)])
        var gym = SubEdit(id: "gym")
        gym.name = "Gym"
        gym.amount = 1800
        gym.currency = "INR"
        XCTAssertEqual(sub(try VaultPatch.saveCommitment(gym, in: bare, now: now), "gym")["amount"] as? Double, 1800)
    }

    /// Unticking a paid charge takes the mark off and leaves the day it was paid as the file
    /// holds it; ticking one invents no day.
    func testThePaidTickNeverWritesAPaidDay() throws {
        var raw = vault()
        var rows = raw["charges"] as? [[String: Any]] ?? []
        rows[1]["paid"] = true
        rows[1]["basis"] = "mark_paid"
        rows[1]["paid_on"] = "2026-08-03"
        raw["charges"] = rows
        let unticked = try VaultPatch.saveCommitment(flix(), charge: .init(from: "2026-08-05", paid: false), in: raw, now: now)
        let row = Fx.rows(unticked, of: "flix")[1]
        XCTAssertEqual(row["paid"] as? Bool, false)
        XCTAssertEqual(row["basis"] as? String, "plan")
        XCTAssertEqual(row["paid_on"] as? String, "2026-08-03")

        let ticked = try VaultPatch.saveCommitment(flix(), charge: .init(from: "2026-09-05", paid: true), in: vault(), now: now)
        XCTAssertEqual(lines(ticked, of: "flix")[2], "2026-09-05 649 paid mark_paid")
        XCTAssertNil(Fx.rows(ticked, of: "flix")[2]["paid_on"])
    }

    // MARK: - a new commitment

    /// A new one is planned with exactly the count the form shows, from its first charge, and
    /// the paid tick marks that first charge in the same write.
    func testANewCommitmentIsPlannedToItsCountWithItsFirstChargePaid() throws {
        var gym = SubEdit()
        gym.name = "Gym"
        gym.amount = 1500
        gym.currency = "INR"
        gym.firstCharge = "2026-07-05"
        gym.planCount = 12
        let out = try VaultPatch.saveCommitment(gym, charge: .init(from: "2026-07-05", paid: true), in: Fx.raw([]), now: now)
        let id = try XCTUnwrap((out["commitments"] as? [[String: Any]])?.first?["id"] as? String)
        let written = lines(out, of: id)
        XCTAssertEqual(written.count, 12)
        XCTAssertEqual(written.first, "2026-07-05 1500 paid mark_paid")
        XCTAssertEqual(written.last, "2027-06-05 1500 unpaid plan")
        XCTAssertEqual(written.dropFirst().filter { $0.hasSuffix("unpaid plan") }.count, 11)

        var chair = SubEdit()
        chair.name = "Chair"
        chair.amount = 3000
        chair.currency = "INR"
        chair.billingCycle = .once
        chair.firstCharge = "2026-07-20"
        let bought = try VaultPatch.saveCommitment(chair, charge: .init(from: "2026-07-20", paid: true), in: vault(), now: now)
        let made = try XCTUnwrap((bought["commitments"] as? [[String: Any]])?.last?["id"] as? String)
        XCTAssertEqual(lines(bought, of: made), ["2026-07-20 3000 paid mark_paid"])
        XCTAssertEqual(lines(bought, of: "flix"), lines(vault(), of: "flix"), "no charge of another commitment is marked")
    }

    // MARK: - a refusal anywhere

    /// A Save that pauses, cancels, ends or shortens the plan and changes the charge the form is
    /// on: when that change takes the charge away first, the refusal names its day.
    func testAChargeTheSameSaveTookAwayIsRefusedByItsDay() throws {
        let day = { (iso: String) in LB.parseDate(iso).map { LB.longDate($0) } ?? iso }
        let cases: [(String, SubEdit, Int?, VaultPatch.ChargeChange, String)] = [
            ("a pause", flix { $0.status = .paused }, nil, .init(from: "2026-09-05", paid: true),
             "Pausing removes the charge on \(day("2026-09-05")), so it can't be changed. Change it first, then pause."),
            ("a cancel", flix { $0.status = .cancelled }, nil, .init(from: "2026-09-05", note: .some("Last one")),
             "Cancelling removes the charge on \(day("2026-09-05")), so it can't be changed. Change it first, then cancel."),
            ("a cancelling date", flix { $0.scheduledCancelDate = "2026-08-31" }, nil, .init(from: "2026-09-05", amount: 700),
             "\(day("2026-09-05")) is past the cancelling date, so it can't be changed. Change it first, then set the cancelling date."),
            ("a shorter plan", flix(), 1, .init(from: "2026-10-05", paid: true),
             "The shorter plan removes the charge on \(day("2026-10-05")), so it can't be changed. Change it first, then shorten the plan."),
            ("a pause and a move", flix { $0.status = .paused }, nil, .init(from: "2026-09-05", to: "2026-09-09"),
             "Pausing removes the charge on \(day("2026-09-05")), so it can't be moved. Move it first, then pause."),
        ]
        for (what, edit, count, change, words) in cases {
            XCTAssertThrowsError(try VaultPatch.saveCommitment(edit, plannedCount: count, charge: change, in: vault(), now: now), what) {
                XCTAssertEqual($0.friendlyDescription, words, what)
            }
        }
        // A charge already paid is never taken by a pause, so marking it is no conflict.
        var paid = vault()
        var rows = paid["charges"] as? [[String: Any]] ?? []
        rows[2]["paid"] = true
        paid["charges"] = rows
        let kept = try VaultPatch.saveCommitment(flix { $0.status = .paused }, charge: .init(from: "2026-09-05", note: .some("Paid early")),
                                                 in: paid, now: now)
        XCTAssertEqual(lines(kept, of: "flix"), ["2026-07-05 649 paid statement", "2026-09-05 649 paid plan"])
    }

    /// The app's one write, as `DashboardModel.commit` makes it. A refusal in the commitment half
    /// or in the charge half leaves the file byte for byte as it was: no name, no tag, no count,
    /// no mark and no move.
    func testARefusalInEitherHalfLeavesTheFileAsItWas() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("one-form-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try VaultDisk.write(vault(), to: folder, expecting: nil)
        let before = try VaultReader.load(from: folder)

        let renamed = flix { $0.name = "Streaming plus"; $0.tag = "Video" }
        let paid = VaultPatch.ChargeChange(from: "2026-08-05", paid: true, note: .some("Paid by card"))
        let attempts: [(String, String, () throws -> [String: Any])] = [
            // The commitment half.
            ("a blank name", "Give it a name", {
                try VaultPatch.saveCommitment(self.flix { $0.name = "  "; $0.tag = "Video" }, plannedCount: 6,
                                              charge: paid, in: before.raw, now: self.now)
            }),
            ("a secret in the notes", dataPolicyRefusal, {
                try VaultPatch.saveCommitment(self.flix { $0.notes = "CVV 123"; $0.tag = "Video" }, plannedCount: 6,
                                              charge: paid, in: before.raw, now: self.now)
            }),
            ("one-time for a plan of several charges", "One-time holds a single charge, and this has 4.", {
                try VaultPatch.saveCommitment(self.flix { $0.billingCycle = .once; $0.tag = "Video" },
                                              charge: paid, in: before.raw, now: self.now)
            }),
            ("a custom cycle with no days", "custom cycle needs", {
                try VaultPatch.saveCommitment(self.flix { $0.billingCycle = .custom; $0.tag = "Video" }, plannedCount: 6,
                                              charge: paid, in: before.raw, now: self.now)
            }),
            // The charge half.
            ("a secret in the charge's note", dataPolicyRefusal, {
                try VaultPatch.saveCommitment(renamed, plannedCount: 6, charge: .init(from: "2026-08-05", note: .some("CVV 123")),
                                              in: before.raw, now: self.now)
            }),
            ("a move onto a day already taken", "already sits on", {
                try VaultPatch.saveCommitment(renamed, plannedCount: 6, charge: .init(from: "2026-08-05", to: "2026-09-05", paid: true),
                                              in: before.raw, now: self.now)
            }),
            ("a run moved past the cancelling date", "cancelling date", {
                try VaultPatch.saveCommitment(self.flix { $0.name = "Streaming plus"; $0.tag = "Video"; $0.scheduledCancelDate = "2026-12-31" },
                                              charge: .init(from: "2026-08-05", to: "2027-01-10", andLater: true),
                                              in: before.raw, now: self.now)
            }),
            ("an amount past the limit", "can't be more than", {
                try VaultPatch.saveCommitment(renamed, plannedCount: 6, charge: .init(from: "2026-08-05", amount: 2e15, andLater: true),
                                              in: before.raw, now: self.now)
            }),
            ("a charge the same Save takes away", "Pausing removes the charge", {
                try VaultPatch.saveCommitment(self.flix { $0.name = "Streaming plus"; $0.tag = "Video"; $0.status = .paused },
                                              charge: .init(from: "2026-09-05", paid: true), in: before.raw, now: self.now)
            }),
            ("a charge gone before the Save", "no longer in your file", {
                try VaultPatch.saveCommitment(renamed, plannedCount: 6, charge: .init(from: "2026-08-06", paid: true),
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
            let flix = after.vault.subscriptions.first { $0.id == "flix" }
            XCTAssertEqual(flix?.name, "Streaming", "\(what): the commitment half is unwritten")
            XCTAssertEqual(flix?.status, .active, "\(what): the status is unchanged")
            XCTAssertNil(after.raw["tags"], "\(what): the registry is untouched")
            XCTAssertEqual(after.vault.charges.count, 5, "\(what): no charge was planned, moved or removed")
            XCTAssertFalse(after.vault.charges.contains { $0.date == "2026-08-05" && $0.paid }, "\(what): no mark landed")
        }
    }
}
