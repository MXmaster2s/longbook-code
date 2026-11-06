// The rules the commitment form leans on, proved without a screen: which plan count a Save
// sends and the day it reaches, how a capped note takes a paste, how an amount becomes a
// field's text, and how stored details read. Every fixture is SYNTHETIC; this repo is public.
import XCTest
@testable import LongbookCore

final class FormRulesTests: XCTestCase {
    // MARK: - the plan count

    /// The pills offer three counts. A count starts as the file's own, none included. Charges
    /// planned elsewhere while the form is open move a count nobody touched with the file, so
    /// the next Save never cuts the plan back; a count the owner chose stays theirs.
    func testTheCountFollowsTheFileUntilTheOwnerMovesIt() {
        XCTAssertEqual(PlannedCount.usual, [6, 12, 24])
        let none = PlannedCount(ahead: 0)
        XCTAssertEqual([none.chosen, none.held], [0, 0])
        XCTAssertEqual(PlannedCount(ahead: -2).held, 0, "never fewer than none")

        var untouched = PlannedCount(ahead: 0)
        untouched.rebase(ahead: 12)
        XCTAssertEqual([untouched.chosen, untouched.held], [12, 12])

        var chosen = PlannedCount(ahead: 3)
        chosen.chosen = 24
        chosen.rebase(ahead: 15)
        XCTAssertEqual([chosen.chosen, chosen.held], [24, 15])
    }

    // MARK: - Planned till and its pills

    private let now = LB.day(2026, 7, 23)

    private func day(_ iso: String) -> Date { LB.parseDate(iso) ?? Date.distantPast }

    private func words(_ days: [Date]) -> [String] { days.map { LB.toISO($0) } }

    /// The horizon the form reads for one commitment of a raw vault, with the cancelling date
    /// the form holds beside the one the file holds.
    private func horizon(_ raw: [String: Any], _ id: String, cycle: BillingCycle = .monthly,
                         customDays: Int? = nil, end: String? = nil) throws -> PlanHorizon {
        let vault = try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: raw))
        return PlanHorizon(rows: vault.charges.filter { $0.commitmentId == id }, cycle: cycle, customDays: customDays,
                           end: end, heldEnd: vault.subscriptions.first { $0.id == id }?.scheduledCancelDate, today: now)
    }

    /// The days the commitment form's Save leaves from today on for a count: the writer the
    /// form's arithmetic answers to, with the same cycle and cancelling date.
    private func saved(_ raw: [String: Any], _ id: String, count: Int, cycle: BillingCycle = .monthly,
                       customDays: Int? = nil, end: String? = nil) throws -> [String] {
        var edit = SubEdit(id: id)
        edit.name = "X"
        edit.amount = 100
        edit.currency = "INR"
        edit.billingCycle = cycle
        edit.customCycleDays = customDays
        edit.scheduledCancelDate = end
        let out = try VaultPatch.saveCommitment(edit, plannedCount: count, in: raw, now: now)
        return Fx.rows(out, of: id).compactMap { $0["date"] as? String }.filter { $0 >= LB.toISO(now) }
    }

    /// Streaming, monthly on the 5th, on 23 Jul: a paid charge behind today and three planned.
    private func running() -> [String: Any] {
        Fx.raw([Fx.rawSub(id: "flix")],
               charges: [Fx.rawRow("flix", "2026-07-05", paid: true, basis: "statement"),
                         Fx.rawRow("flix", "2026-08-05"), Fx.rawRow("flix", "2026-09-05"),
                         Fx.rawRow("flix", "2026-10-05")])
    }

    /// A pill's count gives the day of that many charges from the next one; a picked day gives
    /// the count of charges through it, so a day between charges stands for the one before.
    func testPlannedTillAndThePillsAreOneValue() throws {
        let plan = try horizon(running(), "flix")
        XCTAssertEqual(plan.next, day("2026-08-05"), "the next charge is the earliest day")
        XCTAssertEqual(plan.till(count: 3), day("2026-10-05"), "the file's own three")
        XCTAssertEqual(plan.till(count: 6), day("2027-01-05"))
        XCTAssertEqual(plan.till(count: 1), day("2026-08-05"))
        XCTAssertNil(plan.till(count: 0), "nothing planned reaches no day")
        XCTAssertEqual(plan.count(through: day("2027-01-05")), 6)
        XCTAssertEqual(plan.count(through: day("2027-01-20")), 6)
        XCTAssertEqual(plan.count(through: day("2026-08-04")), 0)
        XCTAssertEqual(plan.most, PlannedCount.ceiling)
        for count in 1...plan.most {
            let till = try XCTUnwrap(plan.till(count: count))
            XCTAssertEqual(plan.count(through: till), count, "\(count) times, there and back")
        }
    }

    /// Whatever the plan's shape, the days the form shows for a count are the days the Save
    /// writes: a lapsed plan, a cycle day on today, no rows, a custom or yearly cycle, and a
    /// cycle or cancelling date changed in the same Save.
    func testPlannedTillIsTheDayTheSaveWrites() throws {
        let lapsed = Fx.raw([Fx.rawSub(id: "gym")],
                            charges: [Fx.rawRow("gym", "2026-02-05", paid: true, basis: "statement"),
                                      Fx.rawRow("gym", "2026-03-05", paid: true, basis: "statement")])
        let today = Fx.raw([Fx.rawSub(id: "fee")],
                           charges: [Fx.rawRow("fee", "2026-06-23", paid: true, basis: "statement")])
        let empty = Fx.raw([Fx.rawSub(id: "new")])
        var gas = Fx.rawSub(id: "gas", cycle: "custom")
        gas["custom_cycle_days"] = 45
        let custom = Fx.raw([gas], charges: [Fx.rawRow("gas", "2026-07-01", paid: true, basis: "statement")])
        let yearly = Fx.raw([Fx.rawSub(id: "dom", cycle: "yearly")],
                            charges: [Fx.rawRow("dom", "2026-03-10", paid: true, basis: "statement")])
        let cases: [(String, [String: Any], String, BillingCycle, Int?, String?, String)] = [
            ("a running plan", running(), "flix", .monthly, nil, nil, "2026-08-05"),
            ("a lapsed plan", lapsed, "gym", .monthly, nil, nil, "2026-08-05"),
            ("a cycle day on today", today, "fee", .monthly, nil, nil, "2026-07-23"),
            ("no rows at all", empty, "new", .monthly, nil, nil, "2026-08-23"),
            ("every 45 days", custom, "gas", .custom, 45, nil, "2026-08-15"),
            ("yearly", yearly, "dom", .yearly, nil, nil, "2027-03-10"),
            ("made yearly in the same Save", running(), "flix", .yearly, nil, nil, "2026-08-05"),
            ("a cancelling date set in the same Save", running(), "flix", .monthly, nil, "2026-09-30", "2026-08-05"),
        ]
        for (what, raw, id, cycle, days, end, next) in cases {
            let plan = try horizon(raw, id, cycle: cycle, customDays: days, end: end)
            XCTAssertEqual(plan.next.map { LB.toISO($0) }, next, what)
            for count in [1, 2, 3, 4, 6, 12, 24, 120, PlannedCount.ceiling] {
                XCTAssertEqual(words(plan.days(count: count)),
                               try saved(raw, id, count: count, cycle: cycle, customDays: days, end: end),
                               "\(what), \(count) times")
            }
        }
        let ending = try horizon(running(), "flix", end: "2026-09-30")
        XCTAssertEqual(ending.most, 2, "only two charges fit before the cancelling date")
        XCTAssertEqual(ending.till(count: 24), day("2026-09-05"))
    }

    /// Rows a shorter plan cannot take — paid ahead, or priced by hand — stay, as the writer
    /// keeps them: the day a count reaches can then sit past the day its pill would name.
    func testAShorterPlanKeepsWhatItCannotTake() throws {
        let raw = Fx.raw([Fx.rawSub(id: "flix")],
                         charges: [Fx.rawRow("flix", "2026-08-05"),
                                   Fx.rawRow("flix", "2026-09-05", paid: true, basis: "mark_paid"),
                                   Fx.rawRow("flix", "2026-10-05", amount: 700, basis: "user"),
                                   Fx.rawRow("flix", "2026-11-05")])
        let plan = try horizon(raw, "flix")
        XCTAssertEqual(words(plan.days(count: 2)), ["2026-09-05", "2026-10-05"])
        XCTAssertEqual(words(plan.days(count: 1)), ["2026-09-05", "2026-10-05"], "no planned row is left to take")
        for count in [1, 2, 3, 4, 5, 8] {
            XCTAssertEqual(words(plan.days(count: count)), try saved(raw, "flix", count: count), "\(count) times")
        }
    }

    /// 5 Oct and 5 Nov planned, 5 Dec priced by hand, 5 Jan and 5 Feb planned. Picking 5 Nov
    /// counts 5 Dec too, which no shorter plan takes, so the Save keeps 5 Nov and Planned till
    /// reads 5 Dec. Every day picked is a day the Save keeps.
    func testAPickedDayIsKeptPastARowNoShorterPlanTakes() throws {
        let raw = Fx.raw([Fx.rawSub(id: "flix")],
                         charges: [Fx.rawRow("flix", "2026-10-05"), Fx.rawRow("flix", "2026-11-05"),
                                   Fx.rawRow("flix", "2026-12-05", amount: 700, basis: "user"),
                                   Fx.rawRow("flix", "2027-01-05"), Fx.rawRow("flix", "2027-02-05")])
        let plan = try horizon(raw, "flix")
        let picked = plan.count(through: day("2026-11-05"))
        XCTAssertEqual(picked, 3)
        XCTAssertEqual(words(plan.days(count: picked)), ["2026-10-05", "2026-11-05", "2026-12-05"])
        XCTAssertEqual(try saved(raw, "flix", count: picked), ["2026-10-05", "2026-11-05", "2026-12-05"])
        XCTAssertEqual(plan.till(count: picked), day("2026-12-05"))
        XCTAssertEqual(plan.count(through: day("2026-10-05")), 2, "5 Oct, and 5 Dec after it")
        XCTAssertEqual(try saved(raw, "flix", count: 2), ["2026-10-05", "2026-12-05"])
        for day in plan.days {
            let count = plan.count(through: day)
            let kept = try saved(raw, "flix", count: count)
            XCTAssertTrue(kept.contains(LB.toISO(day)), "\(LB.toISO(day)) is kept")
            XCTAssertEqual(words(plan.days(count: count)), kept, "\(LB.toISO(day)): the form says what the Save keeps")
        }
    }

    /// A planned row past a cancelling date the Save leaves as it is stays, as the writer keeps
    /// it: the file's own count reaches it, so an untouched Save sends none, and no day is
    /// offered that the writer would not write.
    func testARowPastAnUnchangedCancellingDateIsKeptAsTheWriterKeepsIt() throws {
        var ending = Fx.rawSub(id: "flix")
        ending["ends_on"] = "2026-09-30"
        let raw = Fx.raw([ending], charges: [Fx.rawRow("flix", "2026-07-05", paid: true, basis: "statement"),
                                              Fx.rawRow("flix", "2026-08-05"), Fx.rawRow("flix", "2026-09-05"),
                                              Fx.rawRow("flix", "2026-10-05")])
        let plan = try horizon(raw, "flix", end: "2026-09-30")
        XCTAssertEqual(words(plan.days), ["2026-08-05", "2026-09-05", "2026-10-05"])
        XCTAssertEqual(plan.most, 3, "the three the file holds ahead")
        for count in [1, 2, 3, 6] {
            XCTAssertEqual(words(plan.days(count: count)), try saved(raw, "flix", count: count, end: "2026-09-30"),
                           "\(count) times")
        }
        // Moved in the same Save, the date takes the row past it, as the writer does.
        XCTAssertEqual(words(try horizon(raw, "flix", end: "2026-09-29").days), ["2026-08-05", "2026-09-05"])

        // Only that row ahead: the writer plans nothing after it, and the form offers nothing more.
        let lapsed = Fx.raw([ending], charges: [Fx.rawRow("flix", "2026-06-05", paid: true, basis: "statement"),
                                                 Fx.rawRow("flix", "2026-11-05")])
        let after = try horizon(lapsed, "flix", end: "2026-09-30")
        XCTAssertEqual(words(after.days), ["2026-11-05"])
        for count in [1, 2, 4] {
            XCTAssertEqual(words(after.days(count: count)), try saved(lapsed, "flix", count: count, end: "2026-09-30"),
                           "\(count) times")
        }
    }

    /// A cancelling date set in the same Save can take as many rows as the fill adds back: the
    /// counts match, the days differ. `written` tells the form to send the count, and the days it
    /// shows are the days the Save writes.
    func testACutThatTheFillMatchesStillSendsItsCount() throws {
        let raw = Fx.raw([Fx.rawSub(id: "gym")], charges: [Fx.rawRow("gym", "2026-08-03"),
                                                        Fx.rawRow("gym", "2026-11-03"),
                                                        Fx.rawRow("gym", "2026-12-03")])
        let plan = try horizon(raw, "gym", end: "2026-10-31")
        XCTAssertEqual(plan.written, 1, "the cut leaves one written row standing")
        XCTAssertEqual(words(plan.days(count: 3)), ["2026-08-03", "2026-09-03", "2026-10-03"])
        XCTAssertEqual(words(plan.days(count: 3)), try saved(raw, "gym", count: 3, end: "2026-10-31"),
                       "sent, the count lands on the days the form showed")
        XCTAssertEqual(try horizon(raw, "gym").written, 3, "no cut, every written row stands")
    }

    /// A file holding more days between charges than any write takes draws the form without
    /// trapping: the plan steps a hundred years apart, the days the writer steps to.
    func testAStoredCycleFarPastTheLimitDrawsThePlanWithoutTrapping() throws {
        let far = 99_999_999_999_999_999
        var gas = Fx.rawSub(id: "gas", cycle: "custom")
        gas["custom_cycle_days"] = far
        let raw = Fx.raw([gas], charges: [Fx.rawRow("gas", "2026-07-01", paid: true, basis: "statement")])
        let plan = try horizon(raw, "gas", cycle: .custom, customDays: far)
        XCTAssertEqual(plan.most, PlannedCount.ceiling)
        XCTAssertEqual(words(plan.days(count: 2)), ["2126-06-07", "2226-05-14"])
        XCTAssertEqual(try saved(raw, "gas", count: 2, cycle: .custom, customDays: far), ["2126-06-07", "2226-05-14"])
        let fresh = PlanHorizon(first: day("2026-07-01"), cycle: .custom, customDays: Int.max)
        XCTAssertEqual(words(fresh.days(count: 3)), ["2026-07-01", "2126-06-07", "2226-05-14"])
    }

    /// A weekly plan written 300 charges ahead, past the ceiling a Save sets. Untouched, the
    /// form sends no count and shows the file's own last charge; any count it sends is held to
    /// the ceiling, as the writer holds it.
    func testAPlanPastTheCeilingIsShownAsTheFileHoldsIt() throws {
        var weekly = Fx.rawSub(id: "gym", cycle: "custom")
        weekly["custom_cycle_days"] = 7
        let rows = (0..<300).map { Fx.rawRow("gym", LB.toISO(LB.addDays(day("2026-07-24"), $0 * 7))) }
        let raw = Fx.raw([weekly], charges: rows)
        let plan = try horizon(raw, "gym", cycle: .custom, customDays: 7)
        XCTAssertEqual(plan.most, 300)
        XCTAssertEqual(plan.days(count: 300).count, 300)
        XCTAssertEqual(plan.till(count: 300), LB.addDays(day("2026-07-24"), 299 * 7))
        XCTAssertEqual(plan.count(through: try XCTUnwrap(plan.till(count: 300))), 300)
        for count in [250, 240, 24] {
            XCTAssertEqual(words(plan.days(count: count)), try saved(raw, "gym", count: count, cycle: .custom, customDays: 7),
                           "\(count) times")
        }
        XCTAssertEqual(plan.days(count: 250).count, PlannedCount.ceiling)
    }

    /// A new commitment counts from its first charge, past or not, and is planned with exactly
    /// that many: every 45 days, six times is six charges.
    func testANewCommitmentIsPlannedToTheDayItsCountReaches() throws {
        let plan = PlanHorizon(first: day("2026-01-31"), cycle: .monthly, customDays: nil)
        XCTAssertEqual(words(plan.days(count: 6)),
                       ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31", "2026-06-30"])
        XCTAssertEqual(plan.count(through: day("2026-06-30")), 6)
        XCTAssertEqual(plan.count(through: day("2026-07-30")), 6)
        XCTAssertEqual(plan.next, day("2026-01-31"))

        let shapes: [(BillingCycle, Int?)] = [(.monthly, nil), (.yearly, nil), (.custom, 45), (.custom, 7)]
        for (cycle, days) in shapes {
            let horizon = PlanHorizon(first: day("2026-01-31"), cycle: cycle, customDays: days)
            for count in [1, 6, 12, 24, 120] {
                var edit = SubEdit()
                edit.name = "Gym"
                edit.amount = 1500
                edit.currency = "INR"
                edit.billingCycle = cycle
                edit.customCycleDays = days
                edit.firstCharge = "2026-01-31"
                edit.planCount = count
                let out = try VaultPatch.apply(edit, to: Fx.raw([]), now: now)
                let id = try XCTUnwrap((out["commitments"] as? [[String: Any]])?.first?["id"] as? String)
                XCTAssertEqual(Fx.rows(out, of: id).compactMap { $0["date"] as? String },
                               words(horizon.days(count: count)), "\(cycle.rawValue) \(days ?? 0), \(count) times")
                let till = try XCTUnwrap(horizon.till(count: count))
                XCTAssertEqual(horizon.count(through: till), count)
            }
        }
    }

    // MARK: - a capped note

    /// A paste at the end keeps the note whole and as much of the paste as fits, even when the
    /// paste ends like the note, repeats it or echoes it; a paste at the start keeps the note
    /// after as much of the paste as fits.
    func testAPasteAtEitherEndKeepsTheNoteWhole() {
        XCTAssertEqual(TextFit.fitted("Plan: Gold\nProfiles: 4", replacing: "Plan: Gold", cap: 14), "Plan: Gold\nPro")
        let policy = "Policy number: 88213"
        XCTAssertEqual(TextFit.fitted(policy + "\nInsurer: HDFC Life", replacing: policy, cap: 30),
                       "Policy number: 88213\nInsurer: ")
        XCTAssertEqual(TextFit.fitted("Insurer: HDFC Life\n" + policy, replacing: policy, cap: 30),
                       "Insurer: HPolicy number: 88213")

        // The reviewer's three: a paste that ends like the note, one that repeats it, one that echoes it.
        let lease = "Lease ends: 2027-03-31"
        XCTAssertEqual(TextFit.fitted(lease + "\nDeposit returned: 2027-03-31", replacing: lease, cap: 30),
                       "Lease ends: 2027-03-31\nDeposit")
        XCTAssertEqual(TextFit.fitted("Plan: Gold\nPlan: Gold", replacing: "Plan: Gold", cap: 14), "Plan: Gold\nPla")
        XCTAssertEqual(TextFit.fitted("Plan: Gold and Plan: Gold", replacing: "Plan: Gold", cap: 12), "Plan: Gold a")

        // Both ends alike reads as a paste at the end.
        XCTAssertEqual(TextFit.fitted("ababab", replacing: "abab", cap: 5), "ababa")
    }

    /// A paste inside the note is matched from both ends, the end first, so the paste's first
    /// letters are never taken for the note's own.
    func testAPasteInsideTheNoteIsShortenedAndTheNoteKept() {
        let note = "Insurer: HDFC Life. Policy"
        XCTAssertEqual(TextFit.fitted("Insurer: HDFC Life. Premium paid in full on timePolicy", replacing: note, cap: 40),
                       "Insurer: HDFC Life. Premium paid iPolicy")
        XCTAssertEqual(TextFit.fitted("Insurer: HDFC Life. Nominee: A. Rao. Policy", replacing: note, cap: 32),
                       "Insurer: HDFC Life. Nomi. Policy")
    }

    /// A selection replaced by a longer run loses the selection, as the owner asked, and
    /// keeps the rest; a note already past the cap takes no more than it gives up.
    func testASelectionAndANoteOverTheCap() {
        let note = "Plan: Gold. Profiles: 4"
        XCTAssertEqual(TextFit.fitted("Plan: Platinum family. Profiles: 4", replacing: note, cap: 30),
                       "Plan: Platinum fa. Profiles: 4")

        let long = String(repeating: "Note line. ", count: 50)
        XCTAssertEqual(long.count, 550)
        XCTAssertEqual(TextFit.fitted(long + "!", replacing: long, cap: 500), long, "nothing is added past what it held")
        let middle = String(long.prefix(200)) + "typed" + String(long.dropFirst(200))
        XCTAssertEqual(TextFit.fitted(middle, replacing: long, cap: 500), long)
        let replaced = String(long.prefix(200)) + "0123456789" + String(long.dropFirst(205))
        XCTAssertEqual(TextFit.fitted(replaced, replacing: long, cap: 500),
                       String(long.prefix(200)) + "01234" + String(long.dropFirst(205)),
                       "a selection's length is room to type into")
        let shorter = String(long.dropLast(3))
        XCTAssertEqual(TextFit.fitted(shorter, replacing: long, cap: 500), shorter, "deleting is never refused")
    }

    /// Characters are kept whole: a flag or a family emoji is never split, and a note's
    /// accented letters keep every code point they were written with.
    func testEmojiAndCombiningCharactersAreKeptWhole() {
        XCTAssertEqual(TextFit.fitted("🇮🇳 India 👍 Paid", replacing: "👍 Paid", cap: 8), "🇮🇳 👍 Paid")
        XCTAssertEqual(TextFit.fitted("👨‍👩‍👧 family 👍 Paid", replacing: "👍 Paid", cap: 7), "👨‍👩‍👧👍 Paid")
        XCTAssertEqual(TextFit.fitted("👍👍👍 Paid", replacing: "👍 Paid", cap: 7), "👍👍 Paid")
        XCTAssertEqual(TextFit.fitted("Paid 👍👍👍", replacing: "Paid 👍", cap: 7), "Paid 👍👍")

        // Compared code point by code point: equal strings may still differ in what they hold.
        func scalars(_ text: String) -> [Unicode.Scalar] { Array(text.unicodeScalars) }
        // A combining accent pasted after a held letter settles on it, as it would uncapped.
        XCTAssertEqual(scalars(TextFit.fitted("Cafe\u{301}s", replacing: "Cafe", cap: 4)), scalars("Cafe\u{301}"))
        // A decomposed accent the note already holds keeps its own code points, at either end.
        let held = "Cafe\u{301} bill"
        XCTAssertEqual(scalars(TextFit.fitted("Blue " + held, replacing: held, cap: 12)), scalars("Blu" + held))
        XCTAssertEqual(scalars(TextFit.fitted(held + " paid", replacing: held, cap: 12)), scalars(held + " pa"))
        // Pasted precomposed after a note holding it decomposed, the note's own code points stay.
        XCTAssertEqual(scalars(TextFit.fitted("Caf\u{E9} bill paid", replacing: held, cap: 12)), scalars(held + " pa"))
    }

    // MARK: - an amount as a field's text

    /// A form turns a stored amount into its field's text without trapping, however large,
    /// and the text reads back as the same number.
    func testAnAmountBecomesFieldTextWithoutTrapping() {
        XCTAssertEqual(plainAmount(649), "649")
        XCTAssertEqual(plainAmount(12.5), "12.5")
        XCTAssertEqual(plainAmount(-2500), "-2500")
        XCTAssertEqual(plainAmount(0.0000001), "0.0000001")
        XCTAssertEqual(plainAmount(1e15), "1000000000000000")
        for huge in [9.3e18, 9.3e21, Double.greatestFiniteMagnitude] {
            let text = plainAmount(huge)
            XCTAssertFalse(text.contains("e"), text)
            XCTAssertEqual(Double(text), huge, "\(huge) reads back as itself")
        }
    }

    // MARK: - a commitment's stored details

    /// Details a vault already holds, as the detail screen lists them and a proposal folds
    /// them: one "Label: value" line each, in key order, statement_line never one.
    func testDetailsReadAsLabelledLines() {
        let details: Details = [
            "lender": .string("HDFC Bank"), "loan_account": .string("4521"),
            "statement_line": .string("EMI HDFC 4521"), "policy_doc": .string("documents/term.pdf"),
            "lease_end": .string("2027-03-31"), "coverage_end": .string("2028-01-31"),
            "profiles": .number(4), "channels": .list([.string("HD"), .string("Sports")]),
            "empty": .string("  "), "address": .string("12 Park Lane\nPune"),
            "lease_start": .string("2026-04-01"), "trip_start": .string("2026-12-20"),
            "trip_end": .string("2026-12-28"), "connection_ref": .string("CONN-1042"),
            "tenure_months": .number(36),
        ]
        XCTAssertEqual(detailLines(details), [
            "Address: 12 Park Lane Pune", "Channels: HD, Sports", "Connection: CONN-1042",
            "Coverage ends: 2028-01-31", "Lease ends: 2027-03-31", "Lease starts: 2026-04-01",
            "Lender: HDFC Bank", "Loan account: 4521", "Document: documents/term.pdf", "Profiles: 4",
            "Tenure (months): 36", "Trip ends: 2026-12-28", "Trip starts: 2026-12-20",
        ])
        XCTAssertEqual(detailLines(["statement_line": .string("UPI-NETFLIX")]), [])
        XCTAssertEqual(detailLines(nil), [])
    }

    /// The detail screen leaves out a stored detail whose label the notes already carry, in any
    /// case or spacing, whatever value the notes give it now; a line without a label hides none.
    func testADetailTheNotesCarryIsNotShownAgain() {
        let details: Details = [
            "lender": .string("HDFC Bank"), "lease_end": .string("2027-03-31"),
            "tenure_months": .number(36), "statement_line": .string("EMI HDFC 4521"),
        ]
        XCTAssertEqual(detailLines(details, besides: "lease  ENDS : 2027-06-30\nTenure (months): 48"), ["Lender: HDFC Bank"])
        XCTAssertEqual(detailLines(details, besides: "Lender HDFC Bank\nPlan: Gold"),
                       ["Lease ends: 2027-03-31", "Lender: HDFC Bank", "Tenure (months): 36"])
        XCTAssertEqual(detailLines(details, besides: nil), detailLines(details))
    }
}
