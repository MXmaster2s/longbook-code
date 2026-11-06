// What comes round, decided on the device after the reader: the same line, the same person, and
// how recent the last charge must be. Who counts as a person. Names and lines here are made up.
import XCTest
@testable import LongbookCore

final class StatementRepeatsTests: XCTestCase {
    private func row(_ date: String, _ amount: Double, _ payee: String = "UPI/GOODLIFE ASSURANCE/REF", name: String = "Goodlife",
                     member: String? = nil, direction: String? = nil, keep: Bool = true, skip: String? = nil) -> StatementCandidate {
        StatementCandidate(line: StatementLine(date: date, payee: payee, amount: amount, direction: direction == "in" ? .credit : .debit),
                           name: name, tag: nil, keep: keep, skipReason: skip, member: member, direction: direction)
    }

    private func proposal(_ name: String, _ dates: [String], cycle: String = "monthly", guessed: Bool = false, reason: String = "") -> StatementCloud.Repeat {
        StatementCloud.Repeat(name: name, cycle: cycle, customDays: nil, amount: 500, dates: dates, category: nil, endsOn: nil, guessed: guessed, reason: reason)
    }

    // MARK: by nature

    func testAnInsurerSeenOnceIsYearlyEvenWhenNothingProposedIt() throws {
        let rows = [row("2026-04-08", 900, "UPI-GOODLIFE GENERAL INSURANCE-PAY", name: "Goodlife insurance"), row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        let settled = StatementRepeats.settle([], candidates: rows)
        let found = try XCTUnwrap(settled.repeats.first)
        XCTAssertEqual(settled.repeats.count, 1)
        XCTAssertEqual(found.cycle, "yearly")
        XCTAssertNil(found.endsOn)
        XCTAssertTrue(found.guessed)
        XCTAssertEqual(found.dates, ["2026-04-08"])
        XCTAssertEqual(settled.addedByNature, 1)
    }

    func testAnInsurerNameRunTogetherByTheBankIsStillAnInsurer() {
        XCTAssertEqual(StatementNature.of(name: "Payment", line: "UPI-FUTUREGENERALILIFEINS.BDSI@ICICI", tag: nil), .insurance)
        XCTAssertEqual(StatementNature.of(name: "Namecheap", line: "POS NAME-CHEAP.COM", tag: nil), .domain)
        XCTAssertEqual(StatementNature.of(name: "Canva", line: "ME DC SI CANVA", tag: nil), .mandate)
        XCTAssertNil(StatementNature.of(name: "Insurer payout", line: "NEFT CR INSURANCE CO", tag: nil))
        XCTAssertNil(StatementNature.of(name: "Apple refund", line: "UPI-MANDATE REFUND", tag: nil))
        XCTAssertNil(StatementNature.of(name: "Licious", line: "UPI-LICIOUS", tag: nil), "lic is a word, not a part of one")
        XCTAssertNil(StatementNature.of(name: "Current account", line: "POS PARENT STORE", tag: nil), "rent is a word, not a part of one")
    }

    func testTwoPremiumsAtOneInsurerAreTwoPolicies() {
        let rows = [row("2026-04-08", 900, "GOODLIFE INSURANCE", name: "Goodlife insurance"), row("2026-05-08", 400, "GOODLIFE INSURANCE", name: "Goodlife insurance")]
        let settled = StatementRepeats.settle([], candidates: rows)
        XCTAssertEqual(settled.repeats.map(\.amount).sorted(), [400, 900])
        XCTAssertEqual(Set(settled.repeats.map(\.cycle)), ["yearly"])
    }

    func testAProposedInsurerIsNotAddedAgain() {
        let rows = [row("2026-04-08", 900, "GOODLIFE INSURANCE", name: "Goodlife insurance")]
        let settled = StatementRepeats.settle([proposal("Goodlife insurance", ["2026-04-08"], cycle: "yearly", guessed: true)], candidates: rows)
        XCTAssertEqual(settled.repeats.count, 1)
        XCTAssertEqual(settled.addedByNature, 0)
    }

    func testAYearlyRepeatInsideItsYearHasNotEnded() throws {
        let rows = [row("2026-04-08", 900, "GOODLIFE INSURANCE", name: "Goodlife insurance"), row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        let proposed = StatementCloud.Repeat(name: "Goodlife insurance", cycle: "yearly", customDays: nil, amount: 900, dates: ["2026-04-08"], category: nil, endsOn: "2026-04-08", guessed: true, reason: "Seen once.")
        let settled = StatementRepeats.settle([proposed], candidates: rows)
        XCTAssertNil(try XCTUnwrap(settled.repeats.first).endsOn)
    }

    func testAYearlyRepeatPastItsDueDayKeepsItsEnd() throws {
        let rows = [row("2024-04-08", 900, "GOODLIFE INSURANCE", name: "Goodlife insurance"), row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        let proposed = StatementCloud.Repeat(name: "Goodlife insurance", cycle: "yearly", customDays: nil, amount: 900, dates: ["2024-04-08"], category: nil, endsOn: "2024-04-08", guessed: true, reason: "Seen once.")
        XCTAssertEqual(try XCTUnwrap(StatementRepeats.settle([proposed], candidates: rows).repeats.first).endsOn, "2024-04-08")
    }

    func testAMandateLineStandsOnlyInsideTheRecencyWindow() {
        let recent = [row("2026-09-05", 75, "ME DC SI SOMEAPP", name: "Someapp"), row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        XCTAssertEqual(StatementRepeats.settle([], candidates: recent).repeats.map(\.name), ["Someapp"])
        let old = [row("2026-04-05", 75, "ME DC SI SOMEAPP", name: "Someapp"), row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        XCTAssertEqual(StatementRepeats.settle([], candidates: old).repeats, [])
    }

    func testAMonthlyRepeatWhoseNextChargeIsNotDueHasNotEnded() throws {
        let rows = [row("2026-08-19", 900, "POS SOMEAPP", name: "Someapp"), row("2026-09-19", 900, "POS SOMEAPP", name: "Someapp"), row("2026-10-20", 10, "POS SHOP", name: "Shop")]
        let proposed = StatementCloud.Repeat(name: "Someapp", cycle: "monthly", customDays: nil, amount: 900, dates: ["2026-08-19", "2026-09-19"], category: nil, endsOn: "2026-09-19", guessed: true, reason: "Seen twice.")
        XCTAssertNil(try XCTUnwrap(StatementRepeats.settle([proposed], candidates: rows).repeats.first).endsOn)
    }

    func testAnEndBeforeTheRepeatsOwnLastLineIsNoEnd() throws {
        let rows = [row("2026-08-19", 900, "POS SOMEAPP", name: "Someapp"), row("2026-09-19", 900, "POS SOMEAPP", name: "Someapp"), row("2026-10-20", 10, "POS SHOP", name: "Shop")]
        let proposed = StatementCloud.Repeat(name: "Someapp", cycle: "monthly", customDays: nil, amount: 900, dates: ["2026-08-19", "2026-09-19"], category: nil, endsOn: "2026-04-03", guessed: true, reason: "Seen twice.")
        XCTAssertNil(try XCTUnwrap(StatementRepeats.settle([proposed], candidates: rows).repeats.first).endsOn)
    }

    func testABillThatVariesIsOneMonthlyCommitmentAtItsLatestAmount() throws {
        let rows = [row("2026-08-10", 1200, "POS BESCOM ELECTRICITY", name: "Electricity"), row("2026-09-10", 900, "POS BESCOM ELECTRICITY", name: "Electricity"),
                    row("2026-10-10", 1100, "POS BESCOM ELECTRICITY", name: "Electricity")]
        let found = try XCTUnwrap(StatementRepeats.settle([], candidates: rows).repeats.first)
        XCTAssertEqual(found.cycle, "monthly")
        XCTAssertEqual(found.amount, 1100)
        XCTAssertEqual(found.dates.count, 3)
    }

    func testAPremiumThatDriftsIsOneMonthlyCommitmentNotManyYearlyOnes() throws {
        let rows = [row("2026-08-05", 1012.40, "GOODLIFE INSURANCE", name: "Goodlife insurance"), row("2026-09-05", 1015.10, "GOODLIFE INSURANCE", name: "Goodlife insurance"),
                    row("2026-10-05", 1018.30, "GOODLIFE INSURANCE", name: "Goodlife insurance")]
        let settled = StatementRepeats.settle([], candidates: rows)
        XCTAssertEqual(settled.repeats.count, 1)
        XCTAssertEqual(settled.repeats.first?.cycle, "monthly")
    }

    func testAnInsurerMandateTestThatCameBackIsNoCommitment() {
        let rows = [row("2026-09-02", 1, "UPI AUTOPAY GOODLIFE INSURANCE", name: "Goodlife insurance"), row("2026-09-04", 1, "UPI GOODLIFE", name: "Goodlife", direction: "in"),
                    row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        XCTAssertEqual(StatementRepeats.settle([], candidates: rows).repeats, [])
    }

    func testOrdinaryMerchantsAreNotCommitmentsByTheirWords() {
        XCTAssertNil(StatementNature.of(name: "ICICI Prudential SIP", line: "ACH ICICI PRUDENTIAL MUTUAL FUND", tag: nil))
        XCTAssertNil(StatementNature.of(name: "Care Health Pharmacy", line: "POS CARE HEALTH", tag: nil))
        XCTAssertNil(StatementNature.of(name: "Hertz", line: "POS RENT A CAR", tag: nil))
        XCTAssertNil(StatementNature.of(name: "School Supplies", line: "POS SCHOOL SUPPLIES", tag: nil))
        XCTAssertNil(StatementNature.of(name: "Payment to Emi", line: "UPI EMI SHARMA", tag: nil))
        XCTAssertNil(StatementNature.of(name: "Store", line: "ACH DEBIT STORE", tag: nil))
        XCTAssertEqual(StatementNature.of(name: "House rent", line: "NEFT RENT OCT", tag: nil), .bill)
    }

    func testAMandateTestThatCameBackIsNoCommitment() {
        let rows = [row("2026-09-02", 5, "UPI-AUTOPAY-SOMEAPP-MANDATE", name: "Someapp"), row("2026-09-03", 5, "UPI-SOMEAPP", name: "Someapp back", direction: "in"),
                    row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        XCTAssertEqual(StatementRepeats.settle([], candidates: rows).repeats, [])
    }

    func testMoneyInNeverComesRoundByNature() {
        let rows = [row("2026-09-05", 75, "GOODLIFE INSURANCE", name: "Goodlife insurance", direction: "in"), row("2026-09-20", 10, "POS SHOP", name: "Shop")]
        XCTAssertEqual(StatementRepeats.settle([], candidates: rows).repeats, [])
    }

    // MARK: the same line

    func testTheSameAmountAndLineInConsecutiveMonthsOnAnyDayIsMonthly() throws {
        let rows = [row("2026-07-03", 500, "ACH/GOODLIFE ASSURANCE/1234567/JUL"), row("2026-08-27", 500, "ACH/GOODLIFE ASSURANCE/7654321/AUG"),
                    row("2026-09-11", 500, "ACH/GOODLIFE ASSURANCE/REF99X/SEP")]
        let settled = StatementRepeats.settle([], candidates: rows)
        let found = try XCTUnwrap(settled.repeats.first)
        XCTAssertEqual(settled.repeats.count, 1)
        XCTAssertEqual(found.cycle, "monthly")
        XCTAssertEqual(found.dates, ["2026-07-03", "2026-08-27", "2026-09-11"])
        XCTAssertFalse(found.guessed, "three months in a row stand plain")
        XCTAssertEqual(settled.addedBySameLine, 1)
        XCTAssertEqual(settled.candidates.map(\.line), rows.map(\.line), "a charge is a fact")
    }

    func testTwoMonthsAreGuessedInTheFormEveryGuessTakes() throws {
        let settled = StatementRepeats.settle([], candidates: [row("2026-08-27", 500), row("2026-09-11", 500)])
        let found = try XCTUnwrap(settled.repeats.first)
        XCTAssertTrue(found.guessed)
        XCTAssertEqual(found.writtenName, "Goodlife (Guessed)")
        XCTAssertEqual(found.guessedNote, "Guessed: The same amount on the same line in two consecutive months; monthly assumed.")
    }

    func testLinesTheReaderNamedApartAreGatheredUnderTheCommonName() throws {
        let settled = StatementRepeats.settle([], candidates: [row("2026-07-03", 500, name: "Assurance"), row("2026-08-03", 500, name: "Goodlife"),
                                                               row("2026-09-03", 500, name: "Goodlife")])
        XCTAssertEqual(try XCTUnwrap(settled.repeats.first).name, "Goodlife")
        XCTAssertEqual(Set(settled.candidates.map(\.name)), ["Goodlife"], "they are promoted by name")
    }

    func testAMonthGapAnAmountOrADirectionKeepsLinesApart() {
        XCTAssertTrue(StatementRepeats.settle([], candidates: [row("2026-07-03", 500), row("2026-09-03", 500)]).repeats.isEmpty)
        XCTAssertTrue(StatementRepeats.settle([], candidates: [row("2026-08-03", 500), row("2026-09-03", 501)]).repeats.isEmpty)
        XCTAssertTrue(StatementRepeats.settle([], candidates: [row("2026-08-03", 500), row("2026-09-03", 500, direction: "in")]).repeats.isEmpty)
    }

    func testALineSeenTwiceInAMonthBreaksTheRun() throws {
        let everyWeek = (1...4).map { row("2026-08-0\($0)", 20) } + (1...4).map { row("2026-09-0\($0)", 20) }
        XCTAssertTrue(StatementRepeats.settle([], candidates: everyWeek).repeats.isEmpty, "a habit is not a commitment")
        let doubled = [row("2026-06-03", 500), row("2026-07-03", 500), row("2026-07-09", 500), row("2026-08-03", 500), row("2026-09-03", 500)]
        XCTAssertEqual(try XCTUnwrap(StatementRepeats.settle([], candidates: doubled).repeats.first).dates, ["2026-08-03", "2026-09-03"])
    }

    func testLinesWithoutAKeptMarkOrWithOnlyBankWordsNameNoRepeat() {
        XCTAssertTrue(StatementRepeats.settle([], candidates: [row("2026-08-03", 500, keep: false), row("2026-09-03", 500, keep: false)]).repeats.isEmpty)
        XCTAssertNil(StatementRepeats.lineKey("UPI/98765/REF"))
        XCTAssertNil(StatementRepeats.lineKey("UPI/9876543210@ybl/CR"))
        XCTAssertEqual(StatementRepeats.lineKey("SALARY OCT 2026 NEFT"), StatementRepeats.lineKey("SALARY NOV 2026 NEFT"))
        XCTAssertNotEqual(StatementRepeats.lineKey("UPI/ASHA RAO/1"), StatementRepeats.lineKey("UPI/RAVI RAO/1"))
    }

    // MARK: the same person

    private func paid(_ date: String, _ amount: Double, person: String = "Asha Rao", _ tail: String = "") -> StatementCandidate {
        row(date, amount, "UPI/\(person)/\(tail)", name: "Payment to \(person)", member: person)
    }

    func testTheSamePersonWithinSevenDaysAndTwentyPercentIsMonthly() throws {
        // Each line words its own note, so only the person ties them.
        let settled = StatementRepeats.settle([], candidates: [paid("2026-08-05", 1000, "rent"), paid("2026-09-12", 1200, "room")])
        let found = try XCTUnwrap(settled.repeats.first)
        XCTAssertEqual(found.name, "Payment to Asha Rao")
        XCTAssertEqual(found.dates, ["2026-08-05", "2026-09-12"])
        XCTAssertTrue(found.guessed)
        XCTAssertEqual(found.guessedNote, "Guessed: The same person paid in two consecutive months, within 7 days and 20% of each other; monthly assumed.")
        XCTAssertEqual(settled.addedBySamePerson, 1)
    }

    func testEightDaysOrMoreThanTwentyPercentIsNotAMonthlyPayment() {
        XCTAssertTrue(StatementRepeats.settle([], candidates: [paid("2026-08-05", 1000, "a"), paid("2026-09-13", 1000, "b")]).repeats.isEmpty)
        XCTAssertTrue(StatementRepeats.settle([], candidates: [paid("2026-08-05", 1000, "a"), paid("2026-09-05", 1201, "b")]).repeats.isEmpty)
    }

    func testEveryPaymentInARunFitsEveryOther() throws {
        // 1 to 8 and 8 to 15 each fit; 1 to 15 does not, so the run is the longest that all fits.
        let settled = StatementRepeats.settle([], candidates: [paid("2026-07-01", 1000, "a"), paid("2026-08-08", 1000, "b"), paid("2026-09-15", 1000, "c")])
        XCTAssertEqual(try XCTUnwrap(settled.repeats.first).dates, ["2026-08-08", "2026-09-15"])
    }

    func testMonthEndPaymentsCountAcrossTheTurnOfTheMonth() throws {
        let settled = StatementRepeats.settle([], candidates: [paid("2026-08-30", 1000, "a"), paid("2026-09-02", 1000, "b")])
        XCTAssertEqual(try XCTUnwrap(settled.repeats.first).dates.count, 2)
        let year = StatementRepeats.settle([], candidates: [paid("2025-12-05", 1000, "a"), paid("2026-01-05", 1000, "b")])
        XCTAssertEqual(try XCTUnwrap(year.repeats.first).dates.count, 2, "December runs into January")
    }

    func testOtherPaymentsToThePersonStayOneTime() throws {
        let rows = [paid("2026-08-05", 1000, "a"), paid("2026-08-05", 90, "x"), paid("2026-08-20", 5000, "y"), paid("2026-09-05", 1050, "b")]
        let settled = StatementRepeats.settle([], candidates: rows)
        XCTAssertEqual(settled.repeats.count, 1)
        let found = try XCTUnwrap(settled.repeats.first)
        XCTAssertEqual(found.sightings, ["2026-08-05|1000.00", "2026-09-05|1050.00"], "the other line that day is not gathered")
    }

    func testTheHolderAndTransfersAreNoPaymentToAnyone() {
        XCTAssertTrue(StatementRepeats.settle([], candidates: [paid("2026-08-05", 1000, "a"), paid("2026-09-05", 1000, "b")], holders: ["Asha Rao"]).repeats.isEmpty)
        let moved = [row("2026-08-05", 1000, "TRF A", member: "Ravi", direction: "transfer"), row("2026-09-05", 1000, "TRF B", member: "Ravi", direction: "transfer")]
        XCTAssertTrue(StatementRepeats.settle([], candidates: moved).repeats.isEmpty)
    }

    func testMoneyInFromOnePersonIsItsOwnRepeat() throws {
        let rows = [row("2026-08-05", 1000, "UPI/A", name: "Payment from Asha", member: "Asha", direction: "in"),
                    row("2026-09-05", 1000, "UPI/B", name: "Payment from Asha", member: "Asha", direction: "in")]
        XCTAssertEqual(try XCTUnwrap(StatementRepeats.settle([], candidates: rows).repeats.first).name, "Payment from Asha")
    }

    // MARK: how recent

    func testTheWindowIsTheLatestLineReadNotToday() throws {
        let rows = [row("2019-02-03", 500), row("2019-03-03", 500)]
        XCTAssertEqual(StatementRepeats.settle([], candidates: rows).repeats.count, 1, "an older statement still works")
    }

    func testAMonthReadOnlyForItsFirstWeekIsNotTheLatest() {
        let rows = [row("2026-07-05", 900), row("2026-08-05", 900), row("2026-10-01", 5000, "SALARY", name: "Salary")]
        XCTAssertEqual(StatementRepeats.settle([], candidates: rows).repeats.count, 1, "August still reaches September when October has only begun")
    }

    func testARunMayEndInThatFirstWeek() throws {
        let rows = [row("2026-08-01", 900), row("2026-09-01", 900), row("2026-10-01", 900)]
        XCTAssertEqual(try XCTUnwrap(StatementRepeats.settle([], candidates: rows).repeats.first).dates.count, 3)
    }

    func testARunReachesTheMonthBeforeTheLatestAndNoFurther() {
        let inside = [row("2026-07-03", 500), row("2026-08-03", 500), row("2026-09-30", 40, "ANOTHER SHOP", name: "Shop")]
        XCTAssertEqual(StatementRepeats.settle([], candidates: inside).repeats.count, 1)
        let outside = [row("2026-06-03", 500), row("2026-07-03", 500), row("2026-09-30", 40, "ANOTHER SHOP", name: "Shop")]
        let settled = StatementRepeats.settle([], candidates: outside)
        XCTAssertTrue(settled.repeats.isEmpty)
        XCTAssertEqual(settled.foundTooOld, 1)
    }

    func testAnotherFilesLinesAndLinesAlreadyHeldCountAsRead() {
        let rows = [row("2026-06-03", 500), row("2026-07-03", 500), row("2026-09-30", 40, "HELD", name: "Held", keep: false)]
        XCTAssertTrue(StatementRepeats.settle([], candidates: rows).repeats.isEmpty)
    }

    func testALineDatedAfterTodayMovesNothing() {
        let rows = [row("2026-08-03", 500), row("2026-09-03", 500), row("2027-03-01", 40, "SHOP", name: "Shop", keep: false, skip: StatementTriage.afterToday)]
        XCTAssertEqual(StatementRepeats.settle([], candidates: rows).repeats.count, 1)
    }

    func testAnOldMonthlyProposalStaysOneTimeAndOtherCyclesAreLeftAlone() {
        let rows = [row("2026-01-03", 500, "A", name: "Gym"), row("2026-02-03", 500, "A", name: "Gym"), row("2026-03-03", 500, "A", name: "Gym"),
                    row("2026-01-09", 9000, "B", name: "Premium"), row("2025-01-09", 9000, "B", name: "Premium"), row("2026-09-30", 40, "SHOP", name: "Shop")]
        let settled = StatementRepeats.settle([proposal("Gym", ["2026-01-03", "2026-02-03", "2026-03-03"]),
                                               proposal("Premium", ["2025-01-09", "2026-01-09"], cycle: "yearly", guessed: true, reason: "Seen twice; yearly assumed."),
                                               proposal("Domain", ["2026-02-02"], cycle: "yearly", guessed: true, reason: "Seen once; yearly assumed.")],
                                              candidates: rows)
        XCTAssertEqual(settled.repeats.map(\.name), ["Premium", "Domain"])
        XCTAssertEqual(settled.droppedAsOld, 1)
    }

    func testTheRunEndingThereSaysGuessedOrPlainWhateverWasProposed() throws {
        let days = ["2026-05-03", "2026-07-03", "2026-08-03", "2026-09-03"]
        let rows = days.map { row($0, 500, "A \($0)", name: "Gym") }
        let plain = try XCTUnwrap(StatementRepeats.settle([proposal("Gym", days, guessed: true, reason: "Seen a few times.")], candidates: rows).repeats.first)
        XCTAssertFalse(plain.guessed)
        XCTAssertEqual(plain.reason, "")
        let twice = try XCTUnwrap(StatementRepeats.settle([proposal("Gym", ["2026-08-03", "2026-09-03"])], candidates: rows).repeats.first)
        XCTAssertTrue(twice.guessed)
        XCTAssertEqual(twice.guessedNote, "Guessed: Seen in two consecutive months; monthly assumed.")
        let gapped = try XCTUnwrap(StatementRepeats.settle([proposal("Gym", ["2026-05-03", "2026-06-03", "2026-07-03", "2026-09-03"])], candidates: rows).repeats.first)
        XCTAssertTrue(gapped.guessed, "the run is what ends at the last charge")
    }

    func testAMonthlyGuessSeenOnceRecentlyKeepsItsReason() throws {
        let rows = [row("2026-09-03", 800, "AIRTEL", name: "Airtel")]
        let found = try XCTUnwrap(StatementRepeats.settle([proposal("Airtel", ["2026-09-03"], guessed: true, reason: "Seen once; telecom is monthly.")], candidates: rows).repeats.first)
        XCTAssertEqual(found.guessedNote, "Guessed: Seen once; telecom is monthly.")
    }

    // MARK: against the proposals

    func testAProposalHoldingTheRunStandsAsItIs() throws {
        let days = ["2026-06-03", "2026-07-03", "2026-08-03", "2026-09-03"]
        let rows = days.prefix(3).map { row($0, 500) } + [row(days[3], 650)]
        let settled = StatementRepeats.settle([proposal("Goodlife", days)], candidates: rows)
        XCTAssertEqual(settled.repeats.count, 1)
        XCTAssertEqual(try XCTUnwrap(settled.repeats.first).dates, days, "a change of price stays on the one commitment")
        XCTAssertEqual(settled.addedBySameLine, 0)
        XCTAssertEqual(settled.widened, 0)
    }

    func testAProposalThatMissedALineTakesItUnderItsOwnName() throws {
        let rows = [row("2026-07-03", 500, name: "Goodlife plan"), row("2026-08-03", 500, name: "Goodlife plan"), row("2026-09-03", 500, name: "Assurance")]
        let settled = StatementRepeats.settle([proposal("Goodlife plan", ["2026-07-03", "2026-08-03"], guessed: true, reason: "Seen twice.")], candidates: rows)
        let found = try XCTUnwrap(settled.repeats.first)
        XCTAssertEqual(settled.repeats.count, 1)
        XCTAssertEqual(found.name, "Goodlife plan")
        XCTAssertEqual(found.dates.count, 3)
        XCTAssertFalse(found.guessed)
        XCTAssertEqual(settled.widened, 1)
        XCTAssertEqual(Set(settled.candidates.map(\.name)), ["Goodlife plan"])
    }

    func testARunAcrossSeveralProposalsStandsAloneAndWhatItLeavesIsOneTime() throws {
        let run = ["2026-07-07", "2026-08-07", "2026-09-17"]
        let rows = [row(run[0], 500, name: "Plan A"), row("2026-07-08", 900, "OTHER LINE", name: "Plan A"), row(run[1], 500, name: "Plan B"),
                    row("2026-08-09", 700, "THIRD LINE", name: "Plan B"), row(run[2], 500, name: "Plan B")]
        let settled = StatementRepeats.settle([proposal("Plan A", [run[0], "2026-07-08"]), proposal("Plan B", [run[1], "2026-08-09", run[2]])], candidates: rows)
        XCTAssertEqual(settled.addedBySameLine, 1)
        let added = try XCTUnwrap(settled.repeats.first { $0.dates == run })
        XCTAssertEqual(added.name, "Plan B")
        XCTAssertEqual(added.sightings.count, 3)
        XCTAssertEqual(settled.repeats.count, 1, "one month left is no second monthly commitment")
        XCTAssertEqual(settled.candidates.map(\.line), rows.map(\.line), "its lines stay, as one-time charges")
    }

    /// A run of one line across two proposals, leaving the second one other lines beside it.
    private func partlyAbsorbed(leaving rest: [String]) -> StatementRepeats.Settled {
        let run = ["2026-07-07", "2026-08-07", "2026-09-07"]
        let others = rest.enumerated().map { row($1, Double(700 + $0 * 300), $0 == 0 ? "FIRST WORDS" : "SECOND WORDS", name: "Plan B") }
        let lines = [row(run[0], 500, name: "Plan A"), row(run[1], 500, name: "Plan B"), row(run[2], 500, name: "Plan B")]
        return StatementRepeats.settle([proposal("Plan A", [run[0]]), proposal("Plan B", [run[1], run[2]] + rest)],
                                       candidates: lines + others + [row("2026-09-20", 40, "A SHOP", name: "Shop")])
    }

    func testWhatARunLeavesStaysMonthlyOnlyWithTwoConsecutiveRecentMonths() throws {
        let stays = partlyAbsorbed(leaving: ["2026-08-20", "2026-09-22"])
        XCTAssertEqual(stays.repeats.count, 2)
        let rest = try XCTUnwrap(stays.repeats.first { $0.dates == ["2026-08-20", "2026-09-22"] })
        XCTAssertEqual(rest.cycle, "monthly")
        XCTAssertTrue(rest.guessed, "two months are a guess")

        XCTAssertEqual(partlyAbsorbed(leaving: ["2026-07-20", "2026-09-22"]).repeats.count, 1, "a gap between them")
        XCTAssertEqual(partlyAbsorbed(leaving: ["2026-09-22"]).repeats.count, 1, "one month")
        XCTAssertEqual(partlyAbsorbed(leaving: ["2026-06-20", "2026-07-22"]).repeats.count, 1, "ending too long ago")
    }

    func testARestOfAnotherCycleIsLeftAlone() throws {
        let run = ["2026-08-07", "2026-09-07"]
        let rows = [row(run[0], 500, name: "Plan"), row(run[1], 500, name: "Plan"), row("2026-03-20", 700, "OTHER WORDS", name: "Plan")]
        let settled = StatementRepeats.settle([proposal("Plan", run + ["2026-03-20"], cycle: "yearly")], candidates: rows)
        XCTAssertEqual(settled.repeats.first { $0.cycle == "yearly" }?.dates, ["2026-03-20"])
    }

    func testAWrongCycleGivesWayToARun() throws {
        let rows = [row("2026-08-03", 500), row("2026-09-03", 500)]
        let settled = StatementRepeats.settle([proposal("Goodlife", ["2026-08-03", "2026-09-03"], cycle: "yearly", guessed: true, reason: "Yearly assumed.")], candidates: rows)
        let found = try XCTUnwrap(settled.repeats.first)
        XCTAssertEqual(found.cycle, "monthly")
        XCTAssertEqual(found.guessedNote, "Guessed: The same amount on the same line in two consecutive months; monthly assumed.")
    }

    // MARK: heavy reading

    /// Five hundred payments to one person over two years: every amount its own, on any day.
    private func heavilyPaid(_ count: Int = 500) -> [StatementCandidate] {
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        return (0..<count).map { index in
            let date = String(format: "%04d-%02d-%02d", 2024 + next(2) + (index % 40 == 0 ? 1 : 0), 1 + next(12), 1 + next(28))
            return row(date, Double(100 + next(90_000)) / 10, "UPI/MEENA DAS/\(index)", name: "Payment to Meena Das", member: "Meena Das")
        }
    }

    func testFiveHundredPaymentsToOnePersonSettleWellUnderASecond() throws {
        let rows = heavilyPaid()
        let clock = ContinuousClock()
        var settled: StatementRepeats.Settled?
        let took = clock.measure { settled = StatementRepeats.settle([], candidates: rows) }
        #if DEBUG
        // An unoptimised build, on whatever machine runs it. It took minutes before.
        XCTAssertLessThan(took, .seconds(3))
        #else
        XCTAssertLessThan(took, .milliseconds(500))
        #endif
        XCTAssertNotNil(settled)
    }

    /// The search tried whole, every floor against every line, as the answer it has to match.
    private func tried(_ rows: [StatementCandidate], ends: [Int]?) -> [StatementCandidate]? {
        func day(_ row: StatementCandidate) -> Int? { Int(row.line.date.split(separator: "-")[2]) }
        var best: [StatementCandidate]?
        for floorDay in Set(rows.compactMap(day)).sorted() {
            for floorAmount in Set(rows.map(\.line.amount)).sorted() {
                let fits = rows.filter { row in
                    guard let at = day(row) else { return false }
                    return (at - floorDay + 31) % 31 <= StatementRepeats.daysApart
                        && !(row.line.amount < floorAmount) && !(row.line.amount > floorAmount * StatementRepeats.amountRatio + 0.005)
                }
                guard let run = StatementRepeats.monthly(fits, ends: ends) else { continue }
                if run.count > (best?.count ?? 0) || (run.count == best?.count && run.last?.line.date ?? "" > best?.last?.line.date ?? "") { best = run }
            }
        }
        return best
    }

    func testTheSearchFindsWhatTryingEveryFloorFinds() {
        var seed: UInt64 = 7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for round in 0..<80 {
            // Some rounds span more than five years, past what one word of months holds.
            let years = round % 5 == 0 ? 8 : 2
            let rows = (0..<(5 + next(40))).map { _ in
                row(String(format: "%04d-%02d-%02d", 2019 + next(years), 1 + next(12), 1 + next(31)), Double(500 + next(8) * 40), "UPI/\(next(9))", member: "Meena Das")
            }
            let top = rows.compactMap { StatementRepeats.month(of: $0.line.date) }.max() ?? 0
            for ends in [nil, [top, top - 1], [top, top - 1, top - 2]] as [[Int]?] {
                XCTAssertEqual(StatementRepeats.closest(rows, ends: ends)?.map(\.id), tried(rows, ends: ends)?.map(\.id), "round \(round)")
            }
        }
    }

    // MARK: written

    func testWhatIsSettledWritesCleanAndALineOutsideTheRunStaysOneTime() throws {
        let rows = [paid("2026-07-05", 1000, "a"), paid("2026-08-05", 1000, "b"), paid("2026-08-05", 90, "x"), paid("2026-09-05", 1100, "c"),
                    row("2026-08-11", 500), row("2026-09-11", 500)]
        let settled = StatementRepeats.settle([], candidates: rows)
        XCTAssertEqual(settled.repeats.count, 2)
        let file = StatementImport.ReviewFile(rows: settled.candidates, account: "Axis savings ••1234", addsAccount: true, source: "documents/a.pdf", owner: "Meera Iyer")
        let review = StatementImport.Review(members: ["Asha Rao"], accounts: [], files: [file], currency: "INR",
                                            repeats: settled.repeats.map { ($0, CommitmentPlaceholder(name: $0.name, group: "Monthly", tag: "")) }, waiting: [])
        let raw = VaultScaffold.freshMemory()
        let before = Set((raw["commitments"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        let written = try StatementImport.write(review, to: raw, now: Date(), schema: VaultContract.bundledSchema())
        let commitments = written.vault["commitments"] as? [[String: Any]] ?? []
        let ids = Set(commitments.compactMap { $0["id"] as? String }).subtracting(before)
        XCTAssertEqual(StatementCompleteness.check(vault: written.vault, importedIds: ids), [])
        let person = commitments.filter { ($0["name"] as? String)?.hasPrefix("Payment to Asha Rao") == true }
        XCTAssertEqual(person.compactMap { $0["billing_cycle"] as? String }.sorted(), ["monthly", "once"], "the 90 that day stays its own")
        let guessed = try XCTUnwrap(commitments.first { $0["name"] as? String == "Goodlife (Guessed)" })
        XCTAssertEqual((guessed["notes"] as? String)?.hasPrefix("Guessed: "), true)
        let charges = written.vault["charges"] as? [[String: Any]] ?? []
        let statementDays = charges.filter { $0["basis"] as? String == "statement" }.compactMap { $0["date"] as? String }.sorted()
        XCTAssertEqual(statementDays, rows.map(\.line.date).sorted(), "every line is still a charge on its own day")
    }

    // MARK: who is a person

    func testABankOrACompanyReadsAsOne() {
        for name in ["HDFC Bank", "Bank Of Baroda", "State Bank Of India", "Punjab And Sind", "Sind And Punjab", "Punjab & Sind", "Punjab And Sin",
                     "Kotak And Mahindra", "Mahindra & Kotak", "Jammu And Kashmir", "Jammu And Kash", "Kotak", "Kotak Mahindra", "Standard Chartered", "Sbi Card", "Icici Pru", "Axis",
                     "Acme Technologies Pvt", "Sharma Traders", "Sharma & Sons", "M/S Anand", "m/s anand kumar", "Kirana Store", "Bright Finance Limited"] {
            XCTAssertTrue(StatementPeople.readsAsCompany(name), name)
        }
    }

    func testAPersonIsAPersonCutOffOrNot() {
        for name in ["Rajesh Kotak", "Hoornapriya Amba Fue", "Bandhan", "Federal", "Anand Kumar", "Priya Bankar", "Ram Storey", "Rahul And Priya", "Banke Lal",
                     "Asha Rao", "M S Dhoni", "Martin", "Punjab Singh", "Sindhu", ""] {
            XCTAssertFalse(StatementPeople.readsAsCompany(name), name)
        }
    }

    private func charge(member: String? = nil, other: String? = nil, otherKind: String? = nil, bank: String? = nil, kind: String = "spend", name: String = "Thing") -> StatementCloud.Charge {
        StatementCloud.Charge(date: "2026-09-03", amount: 100, name: name, narration: "line", account: "A", category: nil, kind: kind, member: member,
                              counterpart: other, counterpartKind: otherKind, counterpartBank: bank)
    }

    private func assembled(_ charges: [StatementCloud.Charge], holder: String? = nil, listed: [String] = []) -> StatementCloud.Prepared {
        StatementCloud.Prepared.assemble([StatementCloud.ChargesAnswer(account: "A", holder: holder, charges: charges, notes: "")],
                                         review: StatementCloud.ReviewAnswer(repeats: [], members: listed.map { .init(name: $0, role: "", reason: "") }, notes: ""),
                                         mendingDates: false)
    }

    func testACompanyLeavesTheLineWithoutAPersonAndTheLineStands() {
        let prepared = assembled([charge(member: "Bright Traders", kind: "for_member"), charge(other: "Punjab And Sind", otherKind: "person", bank: "Axis Bank"),
                                  charge(other: "Kotak Bank", otherKind: "person", bank: "Kotak savings ••4417"), charge(other: "Asha Rao", otherKind: "person", bank: "Axis Bank")],
                                 listed: ["Bright Traders", "Asha Rao"])
        XCTAssertNil(prepared.charges[0].member)
        XCTAssertEqual(prepared.charges[0].kind, "spend")
        XCTAssertNil(prepared.charges[1].counterpart)
        XCTAssertNil(prepared.charges[1].counterpartKind)
        XCTAssertNil(prepared.charges[1].counterpartBank, "a bare bank beside a company names no account of anyone's")
        XCTAssertEqual(prepared.charges[2].counterpartBank, "Kotak savings ••4417", "an account with digits stays")
        XCTAssertEqual(prepared.charges[3].counterpart, "Asha Rao")
        XCTAssertEqual(prepared.charges[3].counterpartBank, "Axis Bank")
        XCTAssertEqual(prepared.members.map(\.name), ["Asha Rao"])
        XCTAssertEqual(prepared.charges.map(\.amount), [100, 100, 100, 100])
        XCTAssertEqual(StatementLinePass.members(in: prepared.charges).map(\.name), ["Asha Rao"])
    }

    func testAHolderIsTheHolderWhateverTheirNameReadsAs() {
        let prepared = assembled([charge(other: "Bright Traders", otherKind: "person")], holder: "Bright Traders")
        XCTAssertEqual(prepared.charges[0].counterpart, "Bright Traders")
        XCTAssertEqual(prepared.holder, "Bright Traders")
    }

    func testAPersonNamedLikeARepeatKeepsThePaymentName() {
        let prepared = assembled([charge(other: "Asha Rao", otherKind: "person", name: "Asha Rao"), charge(other: "Bright Traders", otherKind: "person", name: "Bright Traders")])
        XCTAssertEqual(prepared.charges.map(\.name), ["Payment to Asha Rao", "Bright Traders"])
    }

    func testSharedWordsWithTheHolderAreCountedOnly() {
        for name in ["Rao Asha", "Asha R", "Asha", "Rao", "Asha Ra", "Asha Rao Kumar", "Ash Raov"] {
            XCTAssertTrue(StatementPeople.sharesWords(name, withHolder: "Asha Rao"), name)
        }
        for name in ["Asha Rao", "ASHA RAO", "Ravi Kumar", "A R", "Ra"] {
            XCTAssertFalse(StatementPeople.sharesWords(name, withHolder: "Asha Rao"), name)
        }
    }

    func testTheWrittenVaultCountsCompaniesAndHolderSpellings() {
        let vault: [String: Any] = ["members": [
            ["id": "m1", "name": "Asha Rao", "tag": "Self"], ["id": "m2", "name": "Rao Asha"], ["id": "m3", "name": "Asha K"],
            ["id": "m4", "name": "Punjab And Sind"], ["id": "m5", "name": "Ravi Kumar"], ["id": "m6", "name": "Bright Traders"],
        ]]
        let by = Dictionary(uniqueKeysWithValues: StatementCompleteness.check(vault: vault, importedIds: []).map { ($0.kind, $0.count) })
        XCTAssertEqual(by["member_reads_as_company"], 2)
        XCTAssertEqual(by["holder_spelled_differently"], 2)
        XCTAssertEqual(by.count, 2)
    }
}
