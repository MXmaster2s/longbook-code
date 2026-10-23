// The Swift port must agree with core, so these mirror the SAME cases as the
// TypeScript suite — if they disagree, the two engines disagree about one file.
// Every fixture is SYNTHETIC; this repo is public.
import XCTest
@testable import LongbookCore

final class SelectorTests: XCTestCase {
    /// 21 Jul 2026 — a 21st, like the case the owner reported.
    private let today = LB.day(2026, 7, 21)

    // MARK: - reading the file

    func testDecodesAFormatThreeVaultRowsIncluded() throws {
        let json = """
        {
          "app": "longbook", "version": 3,
          "commitments": [
            {"id":"a","name":"Claude","amount":100,"currency":"USD","billing_cycle":"monthly",
             "status":"active","member_id":"m1","tag":"AI subscription"},
            {"id":"b","name":"Bare","amount":5,"currency":"INR","billing_cycle":"yearly","status":"paused"}
          ],
          "charges": [
            {"commitment_id":"a","date":"2026-08-14","amount":100,"paid":false,"basis":"plan"},
            {"commitment_id":"a","date":"2026-07-14","amount":100,"paid":true,"basis":"statement","paid_on":"2026-07-15"},
            {"commitment_id":"a","date":"not a day","amount":1,"paid":false}
          ],
          "members": [{"id":"m1","name":"Aditi","name_key":"aditi"}],
          "accounts": [],
          "_provenance": {"a": "longbook-desktop"}
        }
        """
        let vault = try JSONDecoder().decode(Vault.self, from: Data(json.utf8))
        XCTAssertEqual(vault.subscriptions.count, 2)
        XCTAssertEqual(vault.charges.count, 3, "an unreadable date is still a row in the file")
        XCTAssertEqual(allCharges(vault).count, 2, "but it is never a charge on a screen")
        XCTAssertEqual(vault.charges[1].paidOn, "2026-07-15")
        XCTAssertNil(vault.subscriptions[1].scheduledCancelDate)
    }

    func testAnotherFormatVersionIsNotAVault() {
        for version in [1, 2, 4] {
            let json = "{\"app\":\"longbook\",\"version\":\(version),\"commitments\":[]}"
            XCTAssertThrowsError(try JSONDecoder().decode(Vault.self, from: Data(json.utf8)), "format \(version)")
        }
    }

    func testTheMinimalTopLevelShapeDecodesWithNoCharges() throws {
        let json = "{\"app\":\"longbook\",\"version\":3,\"commitments\":[]}"
        let vault = try JSONDecoder().decode(Vault.self, from: Data(json.utf8))
        XCTAssertTrue(vault.charges.isEmpty)
        XCTAssertNil(nextPaymentDay(vault, today))
    }

    func testAMalformedRowDropsAloneAndTheVaultOpens() throws {
        let json = """
        {"app":"longbook","version":3,"commitments":[{"id":"a","name":"A","amount":1,"currency":"INR","billing_cycle":"monthly","status":"active"}],
         "charges":[{"commitment_id":"a","date":"2026-08-01","amount":"ten","paid":false},
                    {"commitment_id":"a","date":"2026-09-01","amount":10,"paid":false}]}
        """
        let vault = try JSONDecoder().decode(Vault.self, from: Data(json.utf8))
        XCTAssertEqual(vault.charges.count, 1)
        XCTAssertEqual(vault.charges.first?.date, "2026-09-01")
    }

    func testARowRoundTripsEveryField() throws {
        let row = Fx.row("a", "2026-08-01", amount: 12.5, paid: true, basis: "user",
                         currency: "USD", paidOn: "2026-08-02", note: "the July one, paid late")
        let data = try JSONEncoder().encode(row)
        let back = try JSONDecoder().decode(ChargeRow.self, from: data)
        XCTAssertEqual(back, row)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        XCTAssertTrue(keys.contains("commitment_id") && keys.contains("paid_on") && keys.contains("written_at"))
    }

    // MARK: - the next payment

    func testTheNextPaymentDayIsTheSoonestUnpaidRowOnOrAfterToday() {
        let a = Fx.sub(id: "a", name: "A"), b = Fx.sub(id: "b", name: "B")
        let vault = Fx.vault([a, b], [
            Fx.row("a", "2026-07-20", paid: true),      // yesterday, paid
            Fx.row("a", "2026-07-21", amount: 40),      // today
            Fx.row("b", "2026-07-21", amount: 60),      // today too
            Fx.row("a", "2026-08-21", amount: 40),
        ])
        let day = try! XCTUnwrap(nextPaymentDay(vault, today))
        XCTAssertEqual(day.days, 0)
        XCTAssertEqual(day.charges.map(\.sub.name), ["B", "A"], "both, biggest first")
    }

    func testAChargeMarkedPaidIsSkippedForTheNextOne() {
        let a = Fx.sub(id: "a")
        let vault = Fx.vault([a], [Fx.row("a", "2026-07-21", paid: true), Fx.row("a", "2026-08-21")])
        XCTAssertEqual(nextPaymentDay(vault, today)?.days, 31)
        XCTAssertEqual(nextChargeOnOrAfter(a, in: vault, today)?.row.date, "2026-07-21", "paid or not, it is still the next charge")
    }

    func testAPausedOrCancelledCommitmentIsNotPayable() {
        let paused = Fx.sub(id: "p", status: .paused)
        let ended = Fx.sub(id: "e", endsOn: "2026-07-01")
        let vault = Fx.vault([paused, ended], [Fx.row("p", "2026-07-25"), Fx.row("e", "2026-07-25")])
        XCTAssertNil(nextPaymentDay(vault, today))
        XCTAssertFalse(isEffectivelyActive(ended, today), "a lapsed cancelling date reads as cancelled")
    }

    func testARowWhoseCommitmentIsGoneIsNotACharge() {
        let vault = Fx.vault([Fx.sub(id: "a")], [Fx.row("ghost", "2026-07-22"), Fx.row("a", "2026-07-23")])
        XCTAssertEqual(allCharges(vault).map(\.row.date), ["2026-07-23"])
    }

    // MARK: - a free trial

    /// A trial is the row's own flag, read as a pill: set, it is on trial whatever its rows
    /// hold; absent or false, it is not.
    func testAFreeTrialIsTheRowsOwnFlag() {
        let on = Subscription(id: "on", name: "On", amount: 649, currency: "INR", billingCycle: .monthly, status: .active, freeTrial: true)
        let off = Subscription(id: "off", name: "Off", amount: 649, currency: "INR", billingCycle: .monthly, status: .active, freeTrial: false)
        XCTAssertTrue(isFreeTrial(on))
        XCTAssertFalse(isFreeTrial(off))
        XCTAssertFalse(isFreeTrial(Fx.sub(id: "plain")), "absent is false")
    }

    /// The flag rides the file as `free_trial`, and a row without it decodes as not on trial.
    func testTheFlagReadsAndWritesAsFreeTrial() throws {
        let json = #"{"id":"x","name":"X","amount":1,"currency":"INR","billing_cycle":"monthly","status":"active","free_trial":true}"#
        let sub = try JSONDecoder().decode(Subscription.self, from: Data(json.utf8))
        XCTAssertEqual(sub.freeTrial, true)
        let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sub)) as? [String: Any]
        XCTAssertEqual(back?["free_trial"] as? Bool, true)
        XCTAssertNil(Fx.sub(id: "plain").freeTrial)
    }

    /// Only spending is on trial: the same flag on money in or a transfer reads as nothing.
    func testMoneyInAndTransfersAreNeverOnTrial() {
        let pay = Subscription(id: "pay", name: "Pay", amount: 1000, currency: "INR", billingCycle: .monthly, status: .active, direction: "in", freeTrial: true)
        let move = Subscription(id: "move", name: "Move", amount: 500, currency: "INR", billingCycle: .monthly, status: .active, direction: "transfer", freeTrial: true)
        let spend = Subscription(id: "spend", name: "Spend", amount: 649, currency: "INR", billingCycle: .monthly, status: .active, freeTrial: true)
        XCTAssertFalse(isFreeTrial(pay))
        XCTAssertFalse(isFreeTrial(move))
        XCTAssertTrue(isFreeTrial(spend))
    }

    // MARK: - upcoming, planned through, running short

    func testActiveUpcomingIsSoonestFirstAndOnlyRowsAhead() {
        let a = Fx.sub(id: "a", name: "A"), b = Fx.sub(id: "b", name: "B"), c = Fx.sub(id: "c", name: "C")
        let vault = Fx.vault([a, b, c], [
            Fx.row("a", "2026-09-01"), Fx.row("b", "2026-08-01"),
            Fx.row("c", "2026-07-01"),   // only a past row: nothing ahead
        ])
        XCTAssertEqual(activeUpcoming(vault, today).map(\.sub.name), ["B", "A"])
        XCTAssertEqual(activeUpcoming(vault, today).first?.days, 11)
    }

    func testASettledOneTimeCommitmentDropsOutButAFutureOneStays() {
        let done = Fx.sub(id: "d", name: "Done", cycle: .once)
        let ahead = Fx.sub(id: "f", name: "Flight", cycle: .once)
        let vault = Fx.vault([done, ahead], [Fx.row("d", "2026-06-10", paid: true), Fx.row("f", "2026-08-10")])
        XCTAssertEqual(activeUpcoming(vault, today).map(\.sub.name), ["Flight"])
    }

    func testAChargeBehindTodayReadsPaidWhateverItsRowSays() {
        let a = Fx.sub(id: "a")
        let vault = Fx.vault([a], [Fx.row("a", "2026-07-20"), Fx.row("a", "2026-07-21"), Fx.row("a", "2026-08-21", paid: true)])
        let read = allCharges(vault, today)
        XCTAssertEqual(read.map(\.paid), [true, false, true], "yesterday is paid; today and ahead keep their mark")
        XCTAssertFalse(read[0].row.paid, "the row itself is untouched")
        XCTAssertTrue(charges(of: a, in: vault, LB.day(2026, 7, 22))[1].paid, "a day later, today's charge is behind")
    }

    func testAOneTimeCommitmentIsLiveUntilItsChargeIsBehindTodayOrMarkedPaid() {
        let ahead = Fx.sub(id: "ahead", cycle: .once), behind = Fx.sub(id: "behind", cycle: .once)
        let early = Fx.sub(id: "early", cycle: .once), blank = Fx.sub(id: "blank", cycle: .once)
        let short = Fx.sub(id: "short"), paused = Fx.sub(id: "paused", status: .paused)
        let vault = Fx.vault([ahead, behind, early, blank, short, paused], [
            Fx.row("ahead", "2026-07-21"), Fx.row("behind", "2026-07-20"),
            Fx.row("early", "2026-08-01", paid: true), Fx.row("short", "2026-06-01"),
        ])
        XCTAssertEqual(liveCommitments(vault, today).map(\.id), ["ahead", "blank", "short"])
    }

    func testMoneyInIsReadApartAndNeverSummedOrDue() {
        let today = LB.day(2026, 9, 5)
        let rent = Fx.sub(id: "rent", name: "Rent", amount: 42000)
        let salary = Subscription(id: "pay", name: "Salary", amount: 150_000, currency: "INR", billingCycle: .monthly,
                                  status: .active, direction: "in")
        let vault = Fx.vault([rent, salary], [
            Fx.row("rent", "2026-09-01", amount: 42000, paid: true),
            Fx.row("pay", "2026-09-01", amount: 150_000, paid: true),
            Fx.row("rent", "2026-10-01", amount: 42000),
            Fx.row("pay", "2026-10-01", amount: 150_000),
        ])
        XCTAssertEqual(allCharges(vault, today).map { $0.sub.id }, ["rent", "rent"], "money in is not a charge")
        XCTAssertEqual(incomeCharges(vault, today).map { $0.amount }, [150_000, 150_000])
        XCTAssertEqual(chargesInRange(vault, from: LB.day(2026, 9, 1), to: LB.day(2026, 9, 30), today).reduce(0) { $0 + $1.amount }, 42000)
        XCTAssertEqual(nextPaymentDay(vault, today)?.charges.map { $0.sub.id }, ["rent"], "salary is never the next payment")
        XCTAssertFalse(isLiveCommitment(salary, in: vault, today))
    }

    func testATransferIsShownAndOwedAndInNoSum() throws {
        let today = LB.day(2026, 7, 21)
        let rent = Fx.sub(id: "rent", name: "Rent", amount: 42000)
        let bill = Subscription(id: "bill", name: "Coral card bill", amount: 31250, currency: "INR", billingCycle: .once,
                                status: .active, direction: "transfer")
        let save = Subscription(id: "save", name: "To savings", amount: 5000, currency: "INR", billingCycle: .monthly,
                                status: .active, direction: "transfer")
        let vault = Fx.vault([bill, save, rent], [
            Fx.row("save", "2026-07-05", amount: 5000, paid: true),
            Fx.row("bill", "2026-07-23", amount: 31250, basis: "email"),
            Fx.row("rent", "2026-07-25", amount: 42000),
            Fx.row("save", "2026-08-05", amount: 5000),
        ])
        XCTAssertTrue(bill.isTransfer)
        XCTAssertFalse(bill.isIncome)
        XCTAssertEqual([bill, save, rent].map(isSpending), [false, false, true])
        XCTAssertEqual([bill, save, rent].map(isOwed), [true, true, true])

        // Never a charge a sum could reach — and not money in either.
        XCTAssertEqual(allCharges(vault, today).map(\.sub.id), ["rent"])
        XCTAssertEqual(transferCharges(vault, today).map(\.sub.id), ["save", "bill", "save"])
        XCTAssertTrue(incomeCharges(vault, today).isEmpty)
        let window = chargesInRange(vault, from: LB.day(2026, 7, 1), to: LB.day(2026, 8, 31), today)
        XCTAssertEqual(sumByCurrency(window).map(\.amount), [42000])
        XCTAssertEqual(chargesInRange(vault, of: [bill, save], from: LB.day(2026, 7, 1), to: LB.day(2026, 8, 31), today).count, 0)

        // The day spending is next owed keeps its meaning, and its charges are never empty.
        let spend = try XCTUnwrap(nextPaymentDay(vault, today))
        XCTAssertEqual(LB.toISO(spend.date), "2026-07-25")
        XCTAssertEqual(spend.charges.map(\.sub.id), ["rent"])
        XCTAssertTrue(spend.transfers.isEmpty)
        XCTAssertNil(nextPaymentDay(Fx.vault([bill, save], vault.charges), today), "a transfer alone is never a payment day")
        // The day anything is next owed is the bill's, with nothing on it to sum.
        let due = try XCTUnwrap(nextDueDay(vault, today))
        XCTAssertEqual(LB.toISO(due.date), "2026-07-23")
        XCTAssertTrue(due.charges.isEmpty)
        XCTAssertEqual(due.transfers.map(\.sub.name), ["Coral card bill"])

        // Owed like a charge: live while unpaid, in both upcoming lists, a plan that can run short.
        XCTAssertEqual(liveCommitments(vault, today).map(\.id), ["bill", "save", "rent"])
        XCTAssertEqual(activeUpcoming(vault, today).map(\.sub.id), ["bill", "rent", "save"])
        XCTAssertEqual(nextCharges(vault, today).map(\.sub.id), ["bill", "rent", "save"])
        XCTAssertEqual(plansRunningShort(vault, withinDays: 90, today).map(\.sub.id), ["rent", "save"])
    }

    func testATransferDueOnASpendingDayRidesBesideItsCharges() throws {
        let today = LB.day(2026, 7, 21)
        let rent = Fx.sub(id: "rent", name: "Rent", amount: 42000)
        let bill = Subscription(id: "bill", name: "Coral card bill", amount: 31250, currency: "INR", billingCycle: .once,
                                status: .active, direction: "transfer")
        let vault = Fx.vault([rent, bill], [Fx.row("rent", "2026-07-25", amount: 42000), Fx.row("bill", "2026-07-25", amount: 31250)])
        for day in [try XCTUnwrap(nextPaymentDay(vault, today)), try XCTUnwrap(nextDueDay(vault, today))] {
            XCTAssertEqual(day.charges.map(\.sub.id), ["rent"])
            XCTAssertEqual(day.transfers.map(\.sub.id), ["bill"])
        }
    }

    func testAnAccountReadsItsNotesItsLinkedAccountAndTheDetailsItHolds() throws {
        let json = """
        {"app":"longbook","version":3,"commitments":[],
         "members":[{"id":"m1","name":"Meera","name_key":"meera","tag":"family"}],
         "accounts":[
          {"id":"a1","name":"Northbank savings","name_key":"northbank savings"},
          {"id":"a2","name":"Coral 9292","name_key":"coral 9292","tag":"credit card","member_id":"m1",
           "parent_account_id":"a1","notes":"Shared card.","details":{"card_name":" Platinum Reserve ","due_day":5}}]}
        """
        let vault = try JSONDecoder().decode(Vault.self, from: Data(json.utf8))
        let card = try XCTUnwrap(vault.paymentMethods.first { $0.id == "a2" })
        XCTAssertEqual(card.notes, "Shared card.")
        XCTAssertEqual(card.linkedAccountId, "a1")
        XCTAssertEqual(card.familyMemberId, "m1")
        XCTAssertEqual(card.details, ["card_name": .string(" Platinum Reserve "), "due_day": .number(5)], "held as stored")
        XCTAssertNil(vault.paymentMethods[0].details)
        XCTAssertNil(vault.paymentMethods[0].notes)
        XCTAssertEqual(vault.familyMembers[0].tag, "family")
    }

    func testPlannedThroughIsTheLastRowAndShortPlansAreNamed() {
        let a = Fx.sub(id: "a", name: "Short"), b = Fx.sub(id: "b", name: "Long"), once = Fx.sub(id: "o", cycle: .once)
        let vault = Fx.vault([a, b, once], Fx.monthly("a", from: "2026-07-01", months: 3)
                                            + Fx.monthly("b", from: "2026-07-01", months: 24)
                                            + [Fx.row("o", "2026-08-01")])
        XCTAssertEqual(plannedThrough(a, in: vault), LB.day(2026, 9, 1))
        XCTAssertEqual(plansRunningShort(vault, withinDays: 90, today).map(\.sub.name), ["Short"], "a one-time row is never a plan running short")
        XCTAssertTrue(plansRunningShort(vault, withinDays: 30, today).isEmpty)
    }

    func testACommitmentWithACancellingDateIsNeverRunningShort() {
        let a = Fx.sub(id: "a", endsOn: "2026-09-01")
        let vault = Fx.vault([a], Fx.monthly("a", from: "2026-07-01", months: 3))
        XCTAssertTrue(plansRunningShort(vault, withinDays: 365, today).isEmpty)
    }

    // MARK: - which side a door opens on

    func testTodayOpensUpcoming() {
        XCTAssertEqual(listScope(day: "2026-07-21", months: [], today: today), .upcoming)
        XCTAssertEqual(listScope(day: "2026-07-22", months: [], today: today), .upcoming, "a day ahead too")
        XCTAssertEqual(listScope(day: nil, months: [], today: today), .upcoming, "and no window at all")
    }

    func testYesterdayOpensPast() {
        XCTAssertEqual(listScope(day: "2026-07-20", months: [], today: today), .past)
        XCTAssertEqual(listScope(day: "2026-07-20", months: ["2026-09-01"], today: today), .past, "the day decides, not the months")
    }

    func testTheCurrentMonthOpensUpcoming() {
        XCTAssertEqual(listScope(day: nil, months: ["2026-07-01"], today: today), .upcoming)
        XCTAssertEqual(listScope(day: nil, months: ["2026-07-21"], today: today), .upcoming, "any day inside names the month")
    }

    func testAMonthWhollyBehindOpensPast() {
        XCTAssertEqual(listScope(day: nil, months: ["2026-06-01"], today: today), .past)
        XCTAssertEqual(listScope(day: nil, months: ["2026-05-01", "2026-06-01"], today: today), .past, "two behind, both behind")
    }

    func testMixedMonthsOpenUpcoming() {
        XCTAssertEqual(listScope(day: nil, months: ["2026-06-01", "2026-08-01"], today: today), .upcoming)
        XCTAssertEqual(listScope(day: nil, months: ["2026-06-01", "2026-07-01"], today: today), .upcoming, "this month among them")
    }

    func testARangeWhollyBehindOpensPast() {
        XCTAssertEqual(listScope(day: nil, months: [], from: "2026-06-01", to: "2026-07-20", today: today), .past)
        XCTAssertEqual(listScope(day: nil, months: [], from: "2026-06-01", to: "2026-07-21", today: today), .upcoming, "today is still ahead")
        XCTAssertEqual(listScope(day: nil, months: [], from: nil, to: "2026-07-20", today: today), .past, "an open start, a closed end behind")
    }

    func testARangeCrossingOrAheadOfTodayOpensUpcoming() {
        XCTAssertEqual(listScope(day: nil, months: [], from: "2026-07-01", to: "2026-08-01", today: today), .upcoming)
        XCTAssertEqual(listScope(day: nil, months: [], from: "2026-08-01", to: nil, today: today), .upcoming)
        XCTAssertEqual(listScope(day: nil, months: [], from: "2026-06-01", to: nil, today: today), .upcoming, "open-ended runs through today")
        XCTAssertEqual(listScope(day: nil, months: [], from: nil, to: nil, today: today), .upcoming)
    }

    func testTheDayDecidesBeforeTheRange() {
        XCTAssertEqual(listScope(day: "2026-07-20", months: [], from: "2026-08-01", to: "2026-09-01", today: today), .past)
    }

    // MARK: - the date filter

    func testADayIsInTheRangeWhenBothEndsHoldIt() {
        XCTAssertTrue(inDayRange("2026-09-12", from: "2026-09-12", to: "2026-10-04"))
        XCTAssertTrue(inDayRange("2026-10-04", from: "2026-09-12", to: "2026-10-04"), "the last day is inside")
        XCTAssertFalse(inDayRange("2026-10-05", from: "2026-09-12", to: "2026-10-04"))
        XCTAssertFalse(inDayRange("2026-09-11", from: "2026-09-12", to: "2026-10-04"))
    }

    func testAnOpenEndTakesEverythingPastIt() {
        XCTAssertTrue(inDayRange("2031-01-01", from: "2026-09-12", to: nil))
        XCTAssertTrue(inDayRange("2020-01-01", from: nil, to: "2026-10-04"))
        XCTAssertTrue(inDayRange("2031-01-01", from: nil, to: nil))
    }

    func testAnInvertedRangeHoldsNothing() {
        XCTAssertFalse(inDayRange("2026-09-20", from: "2026-10-04", to: "2026-09-12"))
    }

    /// British English, not POSIX: POSIX puts the month first, and the chip's words follow
    /// the day-first order the app's other dates wear. August, because some ICU builds
    /// abbreviate September as "Sept" there.
    func testTheRangeWords() {
        let gb = Locale(identifier: "en_GB")
        XCTAssertEqual(dayRangeLabel(from: LB.day(2026, 8, 12), to: LB.day(2026, 10, 4), locale: gb), "12 Aug – 4 Oct")
        XCTAssertEqual(dayRangeLabel(from: LB.day(2025, 12, 28), to: LB.day(2026, 1, 4), locale: gb), "28 Dec 2025 – 4 Jan 2026")
        XCTAssertEqual(dayRangeLabel(from: LB.day(2026, 8, 12), to: LB.day(2026, 8, 12), locale: gb), "On 12 Aug")
        XCTAssertEqual(dayRangeLabel(from: LB.day(2026, 8, 12), to: nil, locale: gb), "From 12 Aug")
        XCTAssertEqual(dayRangeLabel(from: nil, to: LB.day(2026, 10, 4), locale: gb), "Until 4 Oct")
        XCTAssertNil(dayRangeLabel(from: nil, to: nil, locale: gb))
    }

    // MARK: - the cap on the list ahead

    func testTheCapKeepsTheRowsBeforeItsEdge() {
        let rows = ["2026-08-01", "2027-06-30", "2027-07-01", "2027-09-01"]
        XCTAssertEqual(underCap(rows, before: "2027-07-01", capped: true, dateISO: { $0 }), ["2026-08-01", "2027-06-30"])
        XCTAssertEqual(underCap(rows, before: "2027-07-01", capped: false, dateISO: { $0 }), rows, "lifted, every row")
    }

    func testTheCapLiftsItselfRatherThanEmptyTheList() {
        let later = ["2027-07-01", "2027-09-01"]
        XCTAssertEqual(underCap(later, before: "2027-07-01", capped: true, dateISO: { $0 }), later)
        XCTAssertEqual(underCap([String](), before: "2027-07-01", capped: true, dateISO: { $0 }), [], "nothing ahead stays nothing")
    }

    // MARK: - the one generator

    func testTwentyFourMonthsIsTwentyFourRows() {
        let a = Fx.sub(id: "a", amount: 649)
        let rows = planCharges(for: a, from: LB.day(2026, 9, 1), months: 24, amount: 649, writtenAt: "t")
        XCTAssertEqual(rows.count, 24)
        XCTAssertEqual(rows.first?.date, "2026-09-01")
        XCTAssertEqual(rows.last?.date, "2028-08-01")
        XCTAssertTrue(rows.allSatisfy { $0.basis == "plan" && !$0.paid && $0.amount == 649 && $0.writtenAt == "t" })
    }

    func testAYearlyAndACustomCycleStepTheirOwnWay() {
        let yearly = Fx.sub(id: "y", cycle: .yearly)
        XCTAssertEqual(planCharges(for: yearly, from: LB.day(2026, 3, 15), months: 24, amount: 1, writtenAt: "t").map(\.date),
                       ["2026-03-15", "2027-03-15"])
        let water = Fx.sub(id: "w", cycle: .custom, customDays: 10)
        let rows = planCharges(for: water, from: LB.day(2026, 7, 1), months: 1, amount: 1, writtenAt: "t")
        XCTAssertEqual(rows.map(\.date), ["2026-07-01", "2026-07-11", "2026-07-21", "2026-07-31"])
    }

    /// Days a file holds past what any write takes step as the most a write takes, a hundred
    /// years, and fewer than one as one; a step no Int can count lands at the end of time.
    func testACustomCycleStepsWithoutTrappingHoweverLongItsDays() {
        let anchor = LB.day(2026, 7, 1)
        let far = Fx.sub(id: "f", cycle: .custom, customDays: 99_999_999_999_999_999)
        XCTAssertEqual(LB.toISO(stepFrom(far, anchor, 1)), "2126-06-07")
        XCTAssertEqual(LB.toISO(stepFrom(far, anchor, 93)), "11320-04-28")
        XCTAssertEqual(stepFrom(far, anchor, Int.max), .distantFuture)
        XCTAssertEqual(stepFrom(far, anchor, Int.min), .distantPast)
        XCTAssertEqual(LB.toISO(stepFrom(Fx.sub(id: "z", cycle: .custom, customDays: 0), anchor, 3)), "2026-07-04")
        XCTAssertEqual(planCharges(for: far, from: anchor, months: 2400, amount: 1, writtenAt: "t").map(\.date),
                       ["2026-07-01", "2126-06-07", "2226-05-14"])
    }

    func testAOneTimeCommitmentGetsItsOneCharge() {
        let once = Fx.sub(id: "o", cycle: .once)
        XCTAssertEqual(planCharges(for: once, from: LB.day(2026, 8, 10), months: 24, amount: 5, writtenAt: "t").map(\.date), ["2026-08-10"])
    }

    func testTheCancellingDateIsInclusiveAndAFirstChargePastItWritesNothing() {
        let a = Fx.sub(id: "a", endsOn: "2026-10-01")
        XCTAssertEqual(planCharges(for: a, from: LB.day(2026, 8, 1), months: 24, amount: 1, writtenAt: "t").map(\.date),
                       ["2026-08-01", "2026-09-01", "2026-10-01"])
        XCTAssertTrue(planCharges(for: a, from: LB.day(2026, 11, 1), months: 24, amount: 1, writtenAt: "t").isEmpty)
    }

    func testPlanningAgainSkipsDaysAlreadyWritten() {
        let a = Fx.sub(id: "a")
        let rows = planCharges(for: a, from: LB.day(2026, 8, 1), months: 3, amount: 1,
                               skipping: ["2026-09-01"], writtenAt: "t")
        XCTAssertEqual(rows.map(\.date), ["2026-08-01", "2026-10-01"])
    }

    func testMonthEndClampsRatherThanOverflowing() {
        let jan31 = LB.day(2026, 1, 31)
        XCTAssertEqual(LB.toISO(LB.addMonths(jan31, 1)), "2026-02-28")
        XCTAssertEqual(planCharges(for: Fx.sub(id: "a"), from: jan31, months: 3, amount: 1, writtenAt: "t").map(\.date),
                       ["2026-01-31", "2026-02-28", "2026-03-31"])
    }

    func testAnInventedCalendarDateIsRejectedRatherThanRolled() {
        XCTAssertNil(LB.parseDate("2026-02-30"))
        XCTAssertNil(LB.parseDate("2026-13-01"))
    }

    // MARK: - money

    func testSumByCurrencyNeverBlendsAndHonoursARowsOwnCurrency() {
        let a = Fx.sub(id: "a", currency: "INR")
        let vault = Fx.vault([a], [Fx.row("a", "2026-08-01", amount: 100), Fx.row("a", "2026-09-01", amount: 2, currency: "USD")])
        let sums = sumByCurrency(allCharges(vault))
        XCTAssertEqual(sums.map { "\($0.currency):\(Int($0.amount))" }, ["INR:100", "USD:2"])
    }
}
