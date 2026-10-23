// The rules of the ledger, each pinned: rows are written on request, an attribute edit
// never reaches the past, a charge edit reaches only that charge, and what was only
// planned is unwritten when a commitment stops. Every fixture is SYNTHETIC.
import XCTest
@testable import LongbookCore

final class LedgerTests: XCTestCase {
    private let now = LB.day(2026, 9, 5)

    private func edit(_ id: String? = nil, name: String = "Sarasvati", amount: Double = 16500,
                      cycle: BillingCycle = .monthly, first: String? = "2026-01-01", months: Int? = nil) -> SubEdit {
        var e = SubEdit(id: id)
        e.name = name
        e.amount = amount
        e.currency = "INR"
        e.billingCycle = cycle
        e.firstCharge = first
        e.planMonths = months
        return e
    }

    private func onlyId(_ vault: [String: Any]) -> String {
        (vault["commitments"] as? [[String: Any]])?.first?["id"] as? String ?? ""
    }

    // MARK: - moving a charge

    func testMovingOnlyThisChargeKeepsItsAmountAndBecomesTheOwnersFact() throws {
        var vault = try VaultPatch.apply(edit(months: 4), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.reschedule(commitmentId: id, from: "2026-02-01", to: "2026-02-12", andLater: false, in: vault, now: now)
        let dates = Fx.rows(vault, of: id).map { $0["date"] as? String }
        XCTAssertEqual(dates, ["2026-01-01", "2026-02-12", "2026-03-01", "2026-04-01"], "one row moved, the rest stay")
        let moved = Fx.rows(vault, of: id).first { $0["date"] as? String == "2026-02-12" }
        XCTAssertEqual(moved?["amount"] as? Double, 16500)
        XCTAssertEqual(moved?["basis"] as? String, "user", "a day the owner chose is the owner's fact")
    }

    func testMovingThisAndLaterReanchorsThePlanAndLeavesFactsAlone() throws {
        var vault = try VaultPatch.apply(edit(months: 5), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-01-01", paid: true, in: vault, now: now)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-04-01", amount: 17000, in: vault, now: now)
        vault = try VaultPatch.reschedule(commitmentId: id, from: "2026-02-01", to: "2026-02-15", andLater: true, in: vault, now: now)
        let dates = Fx.rows(vault, of: id).map { $0["date"] as? String }
        XCTAssertEqual(dates, ["2026-01-01", "2026-02-15", "2026-03-15", "2026-04-01", "2026-04-15"],
                       "the paid row and the hand-priced row stay; the planned rows follow the new day")
        XCTAssertTrue(Fx.rows(vault, of: id).filter { ($0["date"] as? String ?? "") >= "2026-02-15" && $0["basis"] as? String == "plan" }
            .allSatisfy { $0["amount"] as? Double == 16500 })
    }

    func testMovingOntoADayThatHoldsAChargeIsRefused() throws {
        let vault = try VaultPatch.apply(edit(months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        XCTAssertThrowsError(try VaultPatch.reschedule(commitmentId: id, from: "2026-02-01", to: "2026-03-01", andLater: false, in: vault, now: now))
    }

    // MARK: - creating writes the plan, once

    func testANewRecurringCommitmentIsPlannedFromItsFirstChargeForTwoYears() throws {
        let vault = try VaultPatch.apply(edit(), to: Fx.raw([]), now: now)
        let rows = Fx.rows(vault, of: onlyId(vault))
        XCTAssertEqual(rows.count, 24)
        XCTAssertEqual(rows.first?["date"] as? String, "2026-01-01")
        XCTAssertEqual(rows.last?["date"] as? String, "2027-12-01")
        XCTAssertTrue(rows.allSatisfy { $0["basis"] as? String == "plan" && $0["paid"] as? Bool == false })
        XCTAssertNil((vault["commitments"] as? [[String: Any]])?.first?["next_due_date"], "nothing about an occurrence lives on the commitment")
    }

    func testHowFarToPlanIsTheOwnersToSay() throws {
        let vault = try VaultPatch.apply(edit(months: 6), to: Fx.raw([]), now: now)
        XCTAssertEqual(Fx.rows(vault, of: onlyId(vault)).count, 6)
    }

    func testANewCommitmentWithoutAFirstChargeIsRefused() {
        XCTAssertThrowsError(try VaultPatch.apply(edit(first: nil), to: Fx.raw([]), now: now)) { error in
            XCTAssertTrue("\(error.friendlyDescription)".contains("first charge"))
        }
    }

    func testAOneTimeCommitmentGetsExactlyOneCharge() throws {
        let vault = try VaultPatch.apply(edit(name: "Flight", amount: 4560, cycle: .once, first: "2026-10-10"), to: Fx.raw([]), now: now)
        let rows = Fx.rows(vault, of: onlyId(vault))
        XCTAssertEqual(rows.map { $0["date"] as? String }, ["2026-10-10"])
    }

    func testSavingAgainDoesNotPlanAgain() throws {
        var vault = try VaultPatch.apply(edit(months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        var again = edit(id, months: 3)
        again.notes = "renamed nothing, changed nothing"
        vault = try VaultPatch.apply(again, to: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).count, 3)
    }

    // MARK: - an attribute edit never reaches the past

    func testChangingTheAmountRepricesOnlyUnpaidPlannedChargesFromToday() throws {
        var vault = try VaultPatch.apply(edit(months: 12), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        // January to August happened; two of them proven by a statement.
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-07-01", paid: true, basis: "statement", in: vault, now: now)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-08-01", paid: true, in: vault, now: now)

        var raise = edit(id)
        raise.amount = 18000
        vault = try VaultPatch.apply(raise, to: vault, now: now)

        let by = Dictionary(uniqueKeysWithValues: Fx.rows(vault, of: id).map { ($0["date"] as! String, $0["amount"] as! Double) })
        XCTAssertEqual(by["2026-01-01"], 16500, "the past is not repriced, paid or not")
        XCTAssertEqual(by["2026-08-01"], 16500)
        XCTAssertEqual(by["2026-09-01"], 16500, "before today, still")
        XCTAssertEqual(by["2026-10-01"], 18000)
        XCTAssertEqual(by["2026-12-01"], 18000)
    }

    func testAnAmountChangeCanBeDatedAndSkipsAChargeTheOwnerSetByHand() throws {
        var vault = try VaultPatch.apply(edit(months: 14), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2027-01-01", amount: 500, in: vault, now: now)

        var raise = edit(id)
        raise.amount = 18000
        raise.amountFrom = "2027-02-01"
        vault = try VaultPatch.apply(raise, to: vault, now: now)
        let by = Dictionary(uniqueKeysWithValues: Fx.rows(vault, of: id).map { ($0["date"] as! String, $0["amount"] as! Double) })
        XCTAssertEqual(by["2026-11-01"], 16500)
        XCTAssertEqual(by["2027-01-01"], 500, "a charge the owner priced is a fact, not a plan")
        XCTAssertEqual(by["2027-02-01"], 18000)
    }

    func testRepricingFromOneChargeReachesItAndTheUnpaidPlanAfterIt() throws {
        var vault = try VaultPatch.apply(edit(months: 14), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-11-01", paid: true, in: vault, now: now)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-12-01", amount: 500, in: vault, now: now)

        vault = try VaultPatch.reprice(commitmentId: id, from: "2026-10-01", to: 18000, in: vault, now: now)
        let rows = Fx.rows(vault, of: id)
        let by = Dictionary(uniqueKeysWithValues: rows.map { ($0["date"] as! String, $0["amount"] as! Double) })
        XCTAssertEqual(by["2026-09-01"], 16500, "the charge before stays")
        XCTAssertEqual(by["2026-10-01"], 18000)
        XCTAssertEqual(rows.first { $0["date"] as? String == "2026-10-01" }?["basis"] as? String, "user")
        XCTAssertEqual(by["2026-11-01"], 16500, "a paid charge is a fact")
        XCTAssertEqual(by["2026-12-01"], 500, "a charge the owner priced is a fact")
        XCTAssertEqual(by["2027-01-01"], 18000)
        XCTAssertEqual(rows.first { $0["date"] as? String == "2027-01-01" }?["basis"] as? String, "plan", "a repriced plan is still a plan")
        let sub = (vault["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == id }
        XCTAssertEqual(sub?["amount"] as? Double, 18000, "the commitment's own price follows, so more plan is written at it")
        XCTAssertNotNil((vault["_provenance"] as? [String: Any])?[id])
    }

    func testAOneTimeCommitmentsAmountAndDateAreItsCharges() throws {
        var vault = try VaultPatch.apply(edit(name: "Flight", amount: 4560, cycle: .once, first: "2026-06-10"), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        var fix = edit(id, name: "Flight", amount: 4990, cycle: .once, first: "2026-06-12")
        vault = try VaultPatch.apply(fix, to: vault, now: now)
        let rows = Fx.rows(vault, of: id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["date"] as? String, "2026-06-12")
        XCTAssertEqual(rows.first?["amount"] as? Double, 4990, "for a one-time commitment the two are one thing, past or not")
        fix.amount = 1
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-06-12", paid: true, in: vault, now: now)
        vault = try VaultPatch.apply(fix, to: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).first?["amount"] as? Double, 4990, "once paid, it is a fact")
    }

    // MARK: - a charge edit reaches only that charge

    func testMarkingPaidAndSettingWhatLeftTheAccount() throws {
        var vault = try VaultPatch.apply(edit(months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-02-01", paid: true, in: vault, now: now)
        var feb = Fx.rows(vault, of: id)[1]
        XCTAssertEqual(feb["paid"] as? Bool, true)
        XCTAssertEqual(feb["basis"] as? String, "mark_paid")
        XCTAssertEqual(feb["amount"] as? Double, 16500, "a bare mark keeps the amount")

        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-02-01", amount: 13500,
                                         paidOn: .some("2026-02-03"), note: .some("₹3,000 paid ahead"), in: vault, now: now)
        feb = Fx.rows(vault, of: id)[1]
        XCTAssertEqual(feb["amount"] as? Double, 13500)
        XCTAssertEqual(feb["basis"] as? String, "user")
        XCTAssertEqual(feb["paid_on"] as? String, "2026-02-03")
        XCTAssertEqual(feb["note"] as? String, "₹3,000 paid ahead")
        XCTAssertEqual(Fx.rows(vault, of: id)[0]["amount"] as? Double, 16500, "January is untouched")
        XCTAssertEqual(Fx.rows(vault, of: id)[2]["amount"] as? Double, 16500, "so is March")
    }

    func testUnmarkingReturnsAMarkToAPlanAndKeepsEvidence() throws {
        var vault = try VaultPatch.apply(edit(months: 2), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-01-01", paid: true, in: vault, now: now)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-01-01", paid: false, in: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id)[0]["basis"] as? String, "plan")

        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-02-01", paid: true, basis: "statement", in: vault, now: now)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-02-01", paid: false, in: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id)[1]["basis"] as? String, "statement", "a statement is not undone by a tap")
    }

    func testAChargeOnADayNobodyPlannedCanStillBeWritten() throws {
        var vault = try VaultPatch.apply(edit(months: 2), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2025-11-01", paid: true, basis: "statement", in: vault, now: now)
        let rows = Fx.rows(vault, of: id)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first?["date"] as? String, "2025-11-01")
        XCTAssertEqual(rows.first?["amount"] as? Double, 16500, "priced at the commitment's amount when none is given")
        XCTAssertThrowsError(try VaultPatch.setCharge(commitmentId: id, date: "2025-13-01", paid: true, in: vault, now: now))
        XCTAssertThrowsError(try VaultPatch.setCharge(commitmentId: "nobody", date: "2025-11-01", paid: true, in: vault, now: now))
    }

    func testANoteIsScannedLikeEveryOtherFreeText() throws {
        var vault = try VaultPatch.apply(edit(months: 1), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        XCTAssertThrowsError(try VaultPatch.setCharge(commitmentId: id, date: "2026-01-01", note: .some("card 4111 1111 1111 1111"), in: vault, now: now))
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-01-01", note: .some("fine"), in: vault, now: now)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-01-01", note: .some(nil), in: vault, now: now)
        XCTAssertNil(Fx.rows(vault, of: id)[0]["note"])
    }

    func testRemovingChargesTakesOnlyTheDaysNamedAndSignsEachCharge() throws {
        var vault = try VaultPatch.apply(edit(months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        let before = (vault["_provenance"] as? [String: Any])?[id] as? [String: Any] ?? [:]
        let later = LB.day(2026, 9, 6)
        vault = VaultPatch.removeCharges(of: id, dates: ["2026-02-01", "2099-01-01"], in: vault, now: later)
        XCTAssertEqual(Fx.rows(vault, of: id).map { $0["date"] as? String }, ["2026-01-01", "2026-03-01"])
        let prov = vault["_provenance"] as? [String: Any] ?? [:]
        XCTAssertEqual(NSDictionary(dictionary: prov[id] as? [String: Any] ?? [:]), NSDictionary(dictionary: before),
                       "the commitment's own entry is as the file held it")
        let signed = prov["\(id)@2026-02-01"] as? [String: Any]
        XCTAssertEqual(signed?["edited_by"] as? String, "longbook-phone", "the removed charge is signed under its own key")
        XCTAssertEqual(signed?["edited_at"] as? String, VaultPatch.iso8601(later))
        XCTAssertNil(prov["\(id)@2099-01-01"], "a day not on file is not signed")
    }

    /// Every charge write signs the charges it touched under their own keys, "<id>@<day>", and
    /// leaves the commitment's entry as it was: a mark, more plan, a shorter plan, a move.
    func testAChargeWriteSignsTheChargeNotTheCommitment() throws {
        let vault = try VaultPatch.apply(edit(first: "2026-09-01", months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        let before = (vault["_provenance"] as? [String: Any])?[id] as? [String: Any] ?? [:]
        let later = LB.day(2026, 9, 6)
        let stamp = VaultPatch.iso8601(later)
        func signed(_ raw: [String: Any]) -> Set<String> {
            Set((raw["_provenance"] as? [String: Any] ?? [:]).filter {
                $0.key.hasPrefix("\(id)@") && ($0.value as? [String: Any])?["edited_at"] as? String == stamp
            }.keys)
        }
        let marked = try VaultPatch.setCharge(commitmentId: id, date: "2026-10-01", paid: true, in: vault, now: later)
        XCTAssertEqual(signed(marked), ["\(id)@2026-10-01"])
        let more = try VaultPatch.plan(commitmentId: id, months: 2, in: vault, now: later)
        XCTAssertEqual(signed(more), ["\(id)@2026-12-01", "\(id)@2027-01-01"])
        let fewer = try VaultPatch.setPlannedCount(commitmentId: id, count: 1, in: vault, now: later)
        XCTAssertEqual(signed(fewer), ["\(id)@2026-11-01"], "the planned row unwritten is signed")
        let moved = try VaultPatch.reschedule(commitmentId: id, from: "2026-10-01", to: "2026-10-03", andLater: true, in: vault, now: later)
        XCTAssertEqual(signed(moved), ["\(id)@2026-10-01", "\(id)@2026-11-01", "\(id)@2026-10-03", "\(id)@2026-11-03"],
                       "every day left and every day landed on")
        for out in [marked, more, fewer, moved] {
            XCTAssertEqual(NSDictionary(dictionary: (out["_provenance"] as? [String: Any])?[id] as? [String: Any] ?? [:]),
                           NSDictionary(dictionary: before), "the commitment's own entry is as the file held it")
        }
    }

    func testRemovingNothingLeavesTheFileAsItWas() throws {
        let vault = try VaultPatch.apply(edit(months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        let out = VaultPatch.removeCharges(of: id, dates: ["2099-01-01"], in: vault, now: LB.day(2026, 9, 6))
        XCTAssertEqual(NSDictionary(dictionary: out), NSDictionary(dictionary: vault), "no row went, so nothing is re-signed")
    }

    // MARK: - stopping unwrites the plan, never the past

    func testPausingRemovesUnpaidPlannedChargesAfterTodayAndKeepsTheRest() throws {
        var vault = try VaultPatch.apply(edit(months: 12), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-11-01", amount: 1, in: vault, now: now)
        var pause = edit(id)
        pause.status = .paused
        vault = try VaultPatch.apply(pause, to: vault, now: now)
        let dates = Fx.rows(vault, of: id).map { $0["date"] as! String }
        XCTAssertEqual(dates.filter { $0 < "2026-09-05" }.count, 9, "January to September stay — the 1st is behind today")
        XCTAssertTrue(dates.contains("2026-11-01"), "a charge the owner priced is kept")
        XCTAssertFalse(dates.contains("2026-12-01"))
    }

    func testCancellingDoesTheSameAndACancellingDateTrimsTheTail() throws {
        var vault = try VaultPatch.apply(edit(months: 12), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        var ends = edit(id)
        ends.scheduledCancelDate = "2026-10-15"
        vault = try VaultPatch.apply(ends, to: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).last?["date"] as? String, "2026-10-01")

        vault = try VaultPatch.cancel(id: id, in: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).last?["date"] as? String, "2026-09-01")
        XCTAssertEqual((vault["commitments"] as? [[String: Any]])?.first?["status"] as? String, "cancelled")
    }

    func testDeletingACommitmentTakesItsRowsAndLeavesSignedTombstones() throws {
        var vault = try VaultPatch.apply(edit(months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-02-01", paid: true, in: vault, now: now)
        vault["_provenance"] = (vault["_provenance"] as? [String: Any] ?? [:]).merging(["other": ["edited_by": "claude"]]) { a, _ in a }
        vault = try VaultPatch.delete(id: id, from: vault, now: now)
        XCTAssertNil(vault["charges"])
        let provenance = vault["_provenance"] as? [String: Any] ?? [:]
        XCTAssertEqual(provenance.keys.sorted(), [id, "\(id)@2026-01-01", "\(id)@2026-02-01", "\(id)@2026-03-01", "other"].sorted(),
                       "its entry and one per removed charge stay, signed, so the other device adopts the delete")
        for key in provenance.keys where key != "other" {
            XCTAssertEqual((provenance[key] as? [String: Any])?["edited_by"] as? String, "longbook-phone", key)
        }
    }

    // MARK: - planning more, and promoting

    func testPlanningMoreContinuesFromTheStepAfterTheLastChargeAndNeverBehindToday() throws {
        // Three rows from September, with "now" on the 5th: the plan still runs ahead.
        var running = try VaultPatch.apply(edit(first: "2026-09-01", months: 3), to: Fx.raw([]), now: now)
        let ahead = onlyId(running)
        running = try VaultPatch.plan(commitmentId: ahead, months: 2, in: running, now: now)
        XCTAssertEqual(Fx.rows(running, of: ahead).map { $0["date"] as? String },
                       ["2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01", "2027-01-01"])
        // Three rows from January, lapsed by September: more starts at the first cycle day from today on.
        var vault = try VaultPatch.apply(edit(months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.plan(commitmentId: id, months: 2, in: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).map { $0["date"] as? String }, ["2026-01-01", "2026-02-01", "2026-03-01", "2026-10-01", "2026-11-01"])
        XCTAssertThrowsError(try VaultPatch.plan(commitmentId: "nobody", months: 1, in: vault, now: now))
    }

    func testSettingThePlannedCountWritesOrUnwritesOnlyTheRowsAhead() throws {
        // Three rows from September; with "now" on the 5th, two stand ahead. Five means three more.
        var vault = try VaultPatch.apply(edit(first: "2026-09-01", months: 3), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setPlannedCount(commitmentId: id, count: 5, in: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).map { $0["date"] as? String },
                       ["2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01", "2027-01-01", "2027-02-01"])
        // Down to one ahead: the planned rows past it go; the row already gone by stays.
        vault = try VaultPatch.setPlannedCount(commitmentId: id, count: 1, in: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).map { $0["date"] as? String }, ["2026-09-01", "2026-10-01"])
        // A row the owner marked paid ahead of time is a fact, never unwritten: with one
        // ahead asked for, it is the one, and the planned rows around it go.
        vault = try VaultPatch.setPlannedCount(commitmentId: id, count: 3, in: vault, now: now)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2026-12-01", paid: true, in: vault, now: now)
        vault = try VaultPatch.setPlannedCount(commitmentId: id, count: 1, in: vault, now: now)
        XCTAssertEqual(Fx.rows(vault, of: id).map { $0["date"] as? String }, ["2026-09-01", "2026-12-01"])
        XCTAssertThrowsError(try VaultPatch.setPlannedCount(commitmentId: "nobody", count: 1, in: vault, now: now))
    }

    func testPromotingKeepsEveryFactAndPlansAhead() throws {
        var vault = Fx.raw([
            Fx.rawSub(id: "jan", name: "UPI-RAMESH", amount: 6000, cycle: "once"),
            Fx.rawSub(id: "feb", name: "UPI-RAMESH", amount: 6000, cycle: "once"),
            Fx.rawSub(id: "mar", name: "UPI-RAMESH", amount: 6500, cycle: "once"),
            Fx.rawSub(id: "other", name: "Netflix", cycle: "once"),
        ], charges: [
            Fx.rawRow("jan", "2026-06-01", amount: 6000, paid: true, basis: "statement"),
            Fx.rawRow("feb", "2026-07-01", amount: 6000, paid: true, basis: "statement"),
            Fx.rawRow("mar", "2026-08-01", amount: 6500, paid: true, basis: "statement"),
            Fx.rawRow("other", "2026-07-03", paid: true, basis: "statement"),
        ])
        var cook = SubEdit()
        cook.name = "Ramesh"
        cook.amount = 6500
        cook.currency = "INR"
        cook.billingCycle = .monthly
        cook.tag = "household help"
        let made = try VaultPatch.promote(onceIds: ["jan", "feb", "mar"], to: cook, planMonths: 3, in: vault, now: now)
        vault = made.vault

        let subs = vault["commitments"] as? [[String: Any]] ?? []
        XCTAssertEqual(subs.map { $0["id"] as? String }, ["other", made.id], "the one-time rows are gone, the stranger stays")
        let rows = Fx.rows(vault, of: made.id)
        // "Now" is 5 September, so the plan starts at the first cycle day from it on: 1 September
        // is behind today, and no statement proved it.
        XCTAssertEqual(rows.map { $0["date"] as? String }, ["2026-06-01", "2026-07-01", "2026-08-01", "2026-10-01", "2026-11-01", "2026-12-01"])
        XCTAssertEqual(rows[2]["amount"] as? Double, 6500)
        XCTAssertEqual(rows[2]["basis"] as? String, "statement", "what the statement proved stays proved")
        XCTAssertEqual(rows[3]["basis"] as? String, "plan")
        XCTAssertEqual(rows[3]["amount"] as? Double, 6500)
        XCTAssertEqual(Fx.rows(vault, of: "other").count, 1)
        for id in ["jan", "feb", "mar"] {
            XCTAssertEqual(((vault["_provenance"] as? [String: Any])?[id] as? [String: Any])?["edited_by"] as? String, "longbook-phone",
                           "a merged row leaves a tombstone, as a deleted one does")
        }
    }

    /// One-time rows of each direction with a paid charge apiece.
    private func directed() -> [String: Any] {
        func once(_ id: String, _ name: String, _ direction: String? = nil) -> [String: Any] {
            var row = Fx.rawSub(id: id, name: name, amount: 5000, cycle: "once")
            if let direction { row["direction"] = direction }
            return row
        }
        return Fx.raw([
            once("spend", "Tuition"), once("out", "Tuition", "out"), once("move", "To savings", "transfer"),
            once("move-2", "To savings", "transfer"), once("in", "Interest", "in"),
            once("lend-1", "To a friend", "lend"), once("lend-2", "To a friend", "lend"),
        ], charges: [
            Fx.rawRow("spend", "2026-06-05", amount: 5000, paid: true, basis: "statement"),
            Fx.rawRow("out", "2026-07-05", amount: 5000, paid: true, basis: "statement"),
            Fx.rawRow("move", "2026-06-07", amount: 5000, paid: true, basis: "statement"),
            Fx.rawRow("move-2", "2026-07-07", amount: 5000, paid: true, basis: "statement"),
            Fx.rawRow("in", "2026-07-05", amount: 5000, paid: true, basis: "statement"),
            Fx.rawRow("lend-1", "2026-06-09", amount: 5000, paid: true, basis: "statement"),
            Fx.rawRow("lend-2", "2026-07-09", amount: 5000, paid: true, basis: "statement"),
        ])
    }

    func testPromotingRefusesRowsThatDoNotShareADirection() throws {
        var target = edit(name: "Standing", amount: 5000, first: nil)
        for ids in [["spend", "move"], ["move", "spend"], ["in", "move"], ["lend-1", "spend"]] {
            XCTAssertThrowsError(try VaultPatch.promote(onceIds: ids, to: target, planMonths: 1, in: directed(), now: now), "\(ids)") { error in
                XCTAssertEqual(error.friendlyDescription,
                               "These rows do not share a direction: promote spending, money in and transfers separately.")
            }
        }
        // The rows say which way the promoted commitment goes; the edit never moves them between sums.
        func direction(_ ids: [String], as wanted: String?) throws -> Any? {
            target.direction = wanted
            let made = try VaultPatch.promote(onceIds: ids, to: target, planMonths: 1, in: directed(), now: now)
            return (made.vault["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == made.id }?["direction"]
        }
        XCTAssertEqual(try direction(["move", "move-2"], as: nil) as? String, "transfer")
        XCTAssertEqual(try direction(["move", "move-2"], as: "in") as? String, "transfer")
        XCTAssertTrue(try direction(["spend", "out"], as: "transfer") is NSNull, "\"out\" and nothing at all are one direction")
        XCTAssertEqual(try direction(["lend-1", "lend-2"], as: nil) as? String, "lend", "a word from a newer contract rides along")
    }

    func testAnEditKeepsADirectionThisBuildDoesNotKnow() throws {
        XCTAssertEqual(["in", "transfer", "lend"].map(VaultPatch.storedDirection), ["in", "transfer", "lend"])
        XCTAssertEqual([nil, "", "out"].map(VaultPatch.storedDirection), [nil, nil, nil])
        let raw = directed()
        let row = try XCTUnwrap((raw["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "lend-1" })
        let sub = try JSONDecoder().decode(Subscription.self, from: JSONSerialization.data(withJSONObject: row))
        XCTAssertTrue(isSpending(sub), "read, an unknown direction is spending until a version names it")
        var form = SubEdit(from: sub)
        form.notes = "Back by March."
        let saved = try VaultPatch.apply(form, to: raw, now: now)
        let after = (saved["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "lend-1" }
        XCTAssertEqual(after?["direction"] as? String, "lend")
        XCTAssertEqual(after?["notes"] as? String, "Back by March.")
        form.direction = "out"
        let spent = try VaultPatch.apply(form, to: raw, now: now)
        XCTAssertTrue((spent["commitments"] as? [[String: Any]])?.first { $0["id"] as? String == "lend-1" }?["direction"] is NSNull)
    }

    func testPromotingRefusesWhatItCannotCarry() {
        let vault = Fx.raw([Fx.rawSub(id: "a", cycle: "once")])
        XCTAssertThrowsError(try VaultPatch.promote(onceIds: ["a"], to: SubEdit(), planMonths: nil, in: vault, now: now))
        XCTAssertThrowsError(try VaultPatch.promote(onceIds: ["nobody"], to: SubEdit(), planMonths: nil, in: Fx.raw([], charges: [Fx.rawRow("nobody", "2026-01-01")]), now: now))
    }

    // MARK: - the file stays a ledger

    func testRowsAreKeptInDateOrderWithinACommitment() throws {
        var vault = try VaultPatch.apply(edit(months: 2), to: Fx.raw([]), now: now)
        let id = onlyId(vault)
        vault = try VaultPatch.setCharge(commitmentId: id, date: "2025-12-01", paid: true, in: vault, now: now)
        XCTAssertEqual((vault["charges"] as? [[String: Any]])?.map { $0["date"] as? String }, ["2025-12-01", "2026-01-01", "2026-02-01"])
    }

    func testTheDecodedVaultReadsWhatTheWriterWrote() throws {
        let raw = try VaultPatch.apply(edit(months: 2), to: Fx.raw([]), now: now)
        let data = try JSONSerialization.data(withJSONObject: raw)
        let vault = try JSONDecoder().decode(Vault.self, from: data)
        XCTAssertEqual(vault.charges.count, 2)
        XCTAssertEqual(vault.charges.first?.basis, "plan")
        XCTAssertEqual(plannedThrough(vault.subscriptions[0], in: vault), LB.day(2026, 2, 1))
    }
}
