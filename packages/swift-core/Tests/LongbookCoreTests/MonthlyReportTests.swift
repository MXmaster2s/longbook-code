import XCTest
@testable import LongbookCore

final class MonthlyReportTests: XCTestCase {
    private let today = LB.day(2026, 9, 5)

    private func book() -> Vault {
        let rent = Fx.sub(id: "rent", name: "House rent", amount: 42000, tag: "rent", methodId: "bank")
        let net = Fx.sub(id: "net", name: "Netflix", amount: 649, tag: "streaming", methodId: "card")
        let pay = Subscription(id: "pay", name: "Salary", amount: 150_000, currency: "INR", billingCycle: .monthly,
                               status: .active, direction: "in")
        return Vault(
            app: "longbook", subscriptions: [rent, net, pay],
            paymentMethods: [
                PaymentMethod(id: "bank", name: "Savings account", nameKey: "savings-account"),
                PaymentMethod(id: "card", name: "Blue card", nameKey: "blue-card"),
            ],
            charges: [
                Fx.row("rent", "2026-06-01", amount: 40000, paid: true, basis: "statement"),
                Fx.row("net", "2026-06-03", amount: 649, paid: true, basis: "statement"),
                Fx.row("rent", "2026-07-01", amount: 42000, paid: true, basis: "statement"),
                Fx.row("net", "2026-07-03", amount: 649, paid: true, basis: "statement"),
                Fx.row("pay", "2026-07-01", amount: 150_000, paid: true, basis: "statement"),
                Fx.row("rent", "2026-08-01", amount: 42000, paid: true, basis: "plan"),
            ]
        )
    }

    func testAMonthOfProjectionAloneIsDrawnForNoReport() {
        XCTAssertEqual(MonthlyReport.months(in: book(), today: today), [LB.day(2026, 6, 1), LB.day(2026, 7, 1)],
                       "August holds only planned rows, and a projection is nothing to report on")
    }

    func testEveryBasisButAProjectionFillsItsMonthAndATransferFillsNone() {
        var vault = book()
        let bill = Subscription(id: "bill", name: "Coral card bill", amount: 31250, currency: "INR", billingCycle: .once,
                                status: .active, direction: "transfer")
        vault.subscriptions.append(bill)
        vault.charges += [
            Fx.row("net", "2026-08-03", amount: 649, paid: true, basis: "email"),
            Fx.row("bill", "2026-05-05", amount: 31250, paid: true, basis: "email"),
            Fx.row("rent", "2026-04-01", amount: 40000, paid: true, basis: "user"),
            Fx.row("net", "2026-03-03", amount: 649, paid: true, basis: "mark_paid"),
        ]
        XCTAssertEqual(MonthlyReport.months(in: vault, today: today),
                       [LB.day(2026, 3, 1), LB.day(2026, 4, 1), LB.day(2026, 6, 1),
                        LB.day(2026, 7, 1), LB.day(2026, 8, 1)],
                       "the paid-tap, the owner's word and the mail each fill a month; May holds only a card bill")
    }

    func testTheOwnersOwnChargeFillsAMonthNoDocumentReached() {
        var vault = book()
        vault.subscriptions.append(Fx.sub(id: "lunch", name: "Lunch", amount: 640, cycle: .once, tag: "food"))
        vault.charges.append(Fx.row("lunch", "2026-05-14", amount: 640, paid: true, basis: "user"))
        XCTAssertEqual(MonthlyReport.months(in: vault, today: today),
                       [LB.day(2026, 5, 1), LB.day(2026, 6, 1), LB.day(2026, 7, 1)],
                       "a charge typed by hand is data, and its month is a month to report on")
    }

    func testTheCurrentMonthIsDrawnAndAMissingBasisReadsAsAProjection() {
        var vault = book()
        vault.charges.append(Fx.row("net", "2026-09-03", amount: 649, paid: true, basis: "user"))
        XCTAssertEqual(MonthlyReport.months(in: vault, today: today).last, LB.day(2026, 9, 1),
                       "the month the owner is in, up to today")
        var bare = book()
        bare.charges.append(Fx.row("net", "2026-09-03", amount: 649, paid: true, basis: nil))
        XCTAssertEqual(MonthlyReport.months(in: bare, today: today), [LB.day(2026, 6, 1), LB.day(2026, 7, 1)],
                       "no basis is read as \"plan\", the way every other reader reads it")
    }

    func testAMonthAheadIsNeverDrawnWhateverBacksIt() {
        for basis in ["statement", "email", "user", "mark_paid"] {
            var vault = book()
            vault.charges.append(Fx.row("net", "2026-10-03", amount: 649, paid: true, basis: basis))
            XCTAssertEqual(MonthlyReport.months(in: vault, today: today), [LB.day(2026, 6, 1), LB.day(2026, 7, 1)],
                           "October has not happened, so \(basis) proves nothing about it")
        }
    }

    func testABillTheMailSaysIsStillToComeFillsNoMonth() {
        var vault = book()
        vault.subscriptions.append(Fx.sub(id: "power", name: "Electricity", amount: 1800, cycle: .once, tag: "utility"))
        vault.charges += [
            // Read from the mail in September, due in October, not yet paid: no month to review.
            Fx.row("power", "2026-10-05", amount: 1800, paid: false, basis: "email"),
            Fx.row("net", "2026-08-03", amount: 649, paid: true, basis: "email"),
            // Today's own row counts: the day has come, whatever its mark.
            Fx.row("net", "2026-09-05", amount: 649, paid: false, basis: "email"),
            Fx.row("net", "2026-09-06", amount: 649, paid: true, basis: "statement"),
        ]
        XCTAssertEqual(MonthlyReport.months(in: vault, today: today),
                       [LB.day(2026, 6, 1), LB.day(2026, 7, 1), LB.day(2026, 8, 1), LB.day(2026, 9, 1)],
                       "August and September by rows on or before today; October is only a bill still to come")
        var ahead = book()
        ahead.charges.append(Fx.row("net", "2026-11-03", amount: 649, paid: true, basis: "statement"))
        XCTAssertEqual(MonthlyReport.months(in: ahead, today: today), [LB.day(2026, 6, 1), LB.day(2026, 7, 1)],
                       "no document proves a day that has not come")
    }

    /// The month qualifies on one paid-tap and holds two projections beside it. Every
    /// figure must describe the tap alone: a report that counted the rest would publish
    /// money nobody said moved.
    func testAMonthQualifyingOnOneTapReportsThatChargeAndNoProjection() throws {
        var vault = book()
        vault.charges += [
            Fx.row("net", "2026-08-03", amount: 649, paid: true, basis: "mark_paid"),
            Fx.row("net", "2026-08-20", amount: 649, paid: false, basis: nil),
        ]
        XCTAssertEqual(MonthlyReport.months(in: vault, today: today).last, LB.day(2026, 8, 1))
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 8, 1), currency: "INR", today: today)
        guard case .stats(let stats) = report.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].amount, 649, "August's rent row is a projection and is in no total")
        XCTAssertEqual(stats.stats[1].value, "1", "one confirmed charge")
        XCTAssertEqual(stats.stats[2].label, MonthlyReport.Labels.unconfirmed)
        XCTAssertEqual(stats.stats[2].value, "2", "two that have passed and nobody has confirmed")
        guard case .donut(let accounts) = report.modules[1] else { return XCTFail("accounts second") }
        XCTAssertEqual(accounts.slices.map(\.label), ["Blue card"], "the account the rent never left is in no ring")
        guard case .donut(let categories) = report.modules[2] else { return XCTFail("categories third") }
        XCTAssertEqual(categories.slices.map(\.label), ["streaming"])
        guard case .transactions(let rows) = report.modules[3] else { return XCTFail("charges last") }
        XCTAssertEqual(rows.rows.map(\.name), ["Netflix"], "House rent is planned, so it is not a row here")
    }

    /// The delta compares two months counted the same way. July is confirmed; August is
    /// one tap. A prior total that counted July's projections would invent the change.
    func testTheMonthComparedAgainstIsCountedOnTheSameTerms() {
        var vault = book()
        vault.charges.append(Fx.row("net", "2026-08-03", amount: 649, paid: true, basis: "mark_paid"))
        let july = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        guard case .stats(let stats) = july.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].amount, 42649)
        XCTAssertEqual(stats.stats[0].deltaPct, 4.9, "two whole months, so the change is real")
        XCTAssertEqual(stats.stats[0].deltaLabel, "vs June", "the file says what it compared against")
    }

    /// A month short of its own rows says so where the claim is made: a stat counts what has
    /// passed unconfirmed, and no change is drawn — a 98% fall against a whole month is
    /// missing evidence, not thrift.
    func testAPartCoveredMonthCountsWhatIsMissingAndDrawsNoChange() {
        var vault = book()
        vault.charges.append(Fx.row("net", "2026-08-03", amount: 649, paid: true, basis: "mark_paid"))
        let august = MonthlyReport.build(vault: vault, month: LB.day(2026, 8, 1), currency: "INR", today: today)
        guard case .stats(let stats) = august.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].label, MonthlyReport.Labels.total)
        XCTAssertEqual(stats.stats[0].amount, 649)
        XCTAssertNil(stats.stats[0].deltaPct, "July is whole and August is not; the two do not compare")
        XCTAssertNil(stats.stats[0].deltaIsGood, "and nothing here is good news")
        XCTAssertEqual(stats.stats[1].value, "1")
        XCTAssertEqual(stats.stats[2].label, MonthlyReport.Labels.unconfirmed)
        XCTAssertEqual(stats.stats[2].value, "1", "the rent row has passed and is unaccounted for")
    }

    /// The whole month carries no qualifier: nothing is counted as missing when nothing is.
    func testAWholeMonthCountsPlainly() {
        let july = MonthlyReport.build(vault: book(), month: LB.day(2026, 7, 1), currency: "INR", today: today)
        guard case .stats(let stats) = july.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].label, MonthlyReport.Labels.total)
        XCTAssertEqual(stats.stats[1].value, "2")
        XCTAssertFalse(stats.stats.contains { $0.label == MonthlyReport.Labels.unconfirmed }, "no stat for what is not missing")
        XCTAssertEqual(july.title, "July 2026", "the month names the report")
        XCTAssertEqual(july.startDate, "2026-07-01")
        XCTAssertEqual(july.endDate, "2026-07-31")
        XCTAssertEqual(july.rangeName, "1–31 July 2026")
        XCTAssertNil(july.scope, "a month is drawn over everything")
        XCTAssertEqual(july.version, 2)
    }

    /// The month being compared against is the one that is short. The change is dropped
    /// from the whole month's report too: a rise measured off a light month is invented.
    func testNoChangeIsDrawnWhenTheMonthBeforeIsThePartCoveredOne() {
        var vault = book()
        vault.subscriptions.append(Fx.sub(id: "gym", name: "Gym", amount: 1500, tag: "health", methodId: "card"))
        vault.charges += [
            Fx.row("gym", "2026-06-10", amount: 1500, paid: false, basis: "plan"),
            Fx.row("gym", "2026-07-10", amount: 1500, paid: true, basis: "statement"),
        ]
        let july = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        guard case .stats(let stats) = july.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].label, MonthlyReport.Labels.total, "July itself is whole")
        XCTAssertEqual(stats.stats[1].value, "3")
        XCTAssertNil(stats.stats[0].deltaPct, "June is short a row, so there is nothing honest to compare with")
    }

    /// Today is the 5th. A row later this month is the plan, whatever backs it, so the
    /// month's own report stops at today rather than spending the rest of it.
    func testARowLaterThisMonthIsInNoneOfThisMonthsFigures() {
        var vault = book()
        vault.charges += [
            Fx.row("net", "2026-09-03", amount: 649, paid: true, basis: "statement"),
            Fx.row("rent", "2026-09-25", amount: 42000, paid: true, basis: "statement"),
        ]
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 9, 1), currency: "INR", today: today)
        guard case .stats(let stats) = report.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].amount, 649, "the 25th has not come")
        XCTAssertEqual(stats.stats[1].value, "1")
    }

    /// A month still running is a few of its days. Five days of September against the whole
    /// of August is a 98% fall that never happened, so the running month carries no change
    /// however completely its passed days are accounted for.
    func testTheMonthStillRunningCarriesNoChangeAgainstAWholeMonthBefore() {
        // August whole — both rows from a statement — so nothing but the calendar is missing.
        var vault = Vault(
            app: "longbook", subscriptions: book().subscriptions, paymentMethods: book().paymentMethods,
            charges: [
                Fx.row("rent", "2026-08-01", amount: 42000, paid: true, basis: "statement"),
                Fx.row("net", "2026-08-03", amount: 649, paid: true, basis: "statement"),
                Fx.row("net", "2026-09-03", amount: 649, paid: true, basis: "statement"),
                Fx.row("rent", "2026-09-25", amount: 42000, paid: false, basis: "plan"),
            ]
        )
        let september = MonthlyReport.build(vault: vault, month: LB.day(2026, 9, 1), currency: "INR", today: today)
        guard case .stats(let now) = september.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(now.stats[0].label, MonthlyReport.Labels.total, "its passed days are all accounted for")
        XCTAssertFalse(now.stats.contains { $0.label == MonthlyReport.Labels.unconfirmed })
        XCTAssertEqual(now.stats[0].amount, 649)
        XCTAssertNil(now.stats[0].deltaPct, "September is five days old; August is a month")
        XCTAssertNil(now.stats[0].deltaIsGood, "and a fall that is only the calendar is not good news")
        // August is over and July holds nothing, so it draws no change either — for the other
        // reason, and the report says neither by inventing one.
        let august = MonthlyReport.build(vault: vault, month: LB.day(2026, 8, 1), currency: "INR", today: today)
        guard case .stats(let done) = august.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(done.stats[0].label, MonthlyReport.Labels.total)
        XCTAssertEqual(done.stats[0].amount, 42649)
        XCTAssertNil(done.stats[0].deltaPct, "no July spending in this currency to compare with")
    }

    /// The figures are one currency's, so the evidence that qualifies them is too. A dollar
    /// row nobody has confirmed says nothing about whether the rupee total is whole.
    func testCoverageIsMeasuredInTheCurrencyTheReportIsAbout() {
        var vault = Vault(
            app: "longbook", subscriptions: book().subscriptions, paymentMethods: book().paymentMethods,
            charges: [
                Fx.row("rent", "2026-07-01", amount: 40000, paid: true, basis: "statement"),
                Fx.row("rent", "2026-08-01", amount: 42000, paid: true, basis: "statement"),
                Fx.row("net", "2026-08-10", amount: 12, paid: false, basis: "plan", currency: "USD"),
            ]
        )
        let rupees = MonthlyReport.build(vault: vault, month: LB.day(2026, 8, 1), currency: "INR", today: today)
        guard case .stats(let inr) = rupees.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(inr.stats[0].label, MonthlyReport.Labels.total, "every rupee row in August is confirmed")
        XCTAssertFalse(inr.stats.contains { $0.label == MonthlyReport.Labels.unconfirmed })
        XCTAssertEqual(inr.stats[1].value, "1", "one rupee charge, and the dollar row is another report's")
        XCTAssertEqual(inr.stats[0].deltaPct, 5.0, "against July's 40,000, a comparison nothing blocks")
        // The same vault read in dollars: that month is the part-covered one.
        vault.charges.append(Fx.row("net", "2026-08-12", amount: 9, paid: true, basis: "statement", currency: "USD"))
        let dollars = MonthlyReport.build(vault: vault, month: LB.day(2026, 8, 1), currency: "USD", today: today)
        guard case .stats(let usd) = dollars.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(usd.stats[0].label, MonthlyReport.Labels.total)
        XCTAssertEqual(usd.stats[0].currency, "USD")
        XCTAssertEqual(usd.stats[1].label, MonthlyReport.Labels.total, "the rupee rent is its own total under the same label")
        XCTAssertEqual(usd.stats[1].currency, "INR")
        XCTAssertEqual(usd.stats[1].amount, 42000)
        XCTAssertEqual(usd.stats[2].value, "2", "every row the list holds, whatever its currency")
        XCTAssertEqual(usd.stats[3].label, MonthlyReport.Labels.unconfirmed)
        XCTAssertEqual(usd.stats[3].value, "1")
        // The rupee report of the same month names the dollar total the same way.
        let rupeesAgain = MonthlyReport.build(vault: vault, month: LB.day(2026, 8, 1), currency: "INR", today: today)
        guard case .stats(let both) = rupeesAgain.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(both.stats.map(\.currency), ["INR", "USD", nil], "the dollar sum beside the rupee total, then the count")
        XCTAssertEqual(both.stats[2].value, "2")
    }

    /// Money in obeys the same rule: a salary longbook planned is not income received.
    func testMoneyInCountsOnlyWhatIsConfirmed() {
        var vault = book()
        vault.charges.append(Fx.row("pay", "2026-06-01", amount: 150_000, paid: false, basis: "plan"))
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 6, 1), currency: "INR", today: today)
        guard case .stats(let stats) = report.modules[0] else { return XCTFail("stats first") }
        XCTAssertFalse(stats.stats.contains { $0.label == "Money in" }, "June's salary row is a projection")
    }

    func testATransferIsInNoPartOfAMonthsReport() throws {
        var vault = book()
        vault.subscriptions.append(Subscription(id: "bill", name: "Coral card bill", amount: 31250, currency: "INR",
                                                billingCycle: .once, tag: "rent", status: .active, direction: "transfer"))
        vault.charges.append(Fx.row("bill", "2026-07-05", amount: 31250, paid: true, basis: "email"))
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        let plain = MonthlyReport.build(vault: book(), month: LB.day(2026, 7, 1), currency: "INR", today: today)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(data: try encoder.encode(report), encoding: .utf8), String(data: try encoder.encode(plain), encoding: .utf8),
                       "not the total, not the count, not a slice, not a charge, not money in")
    }

    func testAMonthIsDrawnFromTheLedgerAndNamedByTheGuide() throws {
        let report = MonthlyReport.build(vault: book(), month: LB.day(2026, 7, 1), currency: "INR", today: today)
        XCTAssertEqual(report.id, "july-2026")
        XCTAssertEqual(report.period, "2026-07")
        XCTAssertEqual(report.title, "July 2026")
        XCTAssertEqual(report.subtitle, MonthlyReport.subtitle)
        XCTAssertEqual(report.createdAt, "2026-09-05")
        XCTAssertEqual(report.modules.count, 4, "four modules, and the screen draws these")
        guard case .stats(let stats) = report.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.title, MonthlyReport.Titles.total)
        XCTAssertEqual(stats.stats[0].amount, 42649)
        XCTAssertEqual(stats.stats[0].deltaPct, 4.9, "against June's 40,649")
        XCTAssertEqual(stats.stats[0].deltaIsGood, false)
        XCTAssertEqual(stats.stats[1].value, "2")
        XCTAssertEqual(stats.stats[2].label, "Money in")
        XCTAssertEqual(stats.stats[2].amount, 150_000, "beside the total, never in it")
        guard case .donut(let accounts) = report.modules[1] else { return XCTFail("accounts second") }
        XCTAssertEqual(accounts.title, MonthlyReport.Titles.accounts)
        XCTAssertEqual(accounts.slices.map(\.label), ["Savings account", "Blue card"], "biggest first")
        XCTAssertEqual(accounts.slices.map(\.amount), [42000, 649])
        guard case .donut(let categories) = report.modules[2] else { return XCTFail("categories third") }
        XCTAssertEqual(categories.title, MonthlyReport.Titles.categories)
        XCTAssertEqual(categories.slices.map(\.label), ["rent", "streaming"])
        guard case .transactions(let rows) = report.modules[3] else { return XCTFail("charges last") }
        XCTAssertEqual(rows.title, MonthlyReport.Titles.charges)
        XCTAssertEqual(rows.rows.map(\.name), ["House rent", "Netflix"])
        XCTAssertEqual(rows.rows.map(\.account), ["Savings account", "Blue card"], "a row says which account paid")
        XCTAssertEqual(rows.rows.map(\.id), ["rent-2026-07-01", "net-2026-07-03"], "and which charge it is")
        // The file round-trips through the same reader the AI's reports use.
        let bytes = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(Report.self, from: bytes).periodKey, "2026-07")
    }

    func testEveryChargeIsListedAndTheMoneyOnNoAccountIsItsOwnSlice() {
        var vault = book()
        for day in 10...19 {
            vault.subscriptions.append(Fx.sub(id: "s\(day)", name: "Shop \(day)", amount: 100, cycle: .once, tag: "shopping"))
            vault.charges.append(Fx.row("s\(day)", "2026-07-\(day)", amount: Double(day) * 100, paid: true, basis: "statement"))
        }
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        guard case .donut(let accounts) = report.modules[1] else { return XCTFail("accounts second") }
        XCTAssertEqual(accounts.slices.map(\.label), ["Savings account", "No account", "Blue card"],
                       "what no account paid stands with the accounts, never folded away")
        guard case .transactions(let rows) = report.modules[3] else { return XCTFail("charges last") }
        XCTAssertEqual(rows.rows.count, 12, "every confirmed charge the month holds, not a top few")
        XCTAssertEqual(rows.rows.first?.amount, 42000, "biggest first")
        XCTAssertEqual(rows.rows.last?.amount, 649)
    }

    func testTheAccountsRingStandsWhenOneAccountPaidForEverything() {
        var vault = book()
        vault.subscriptions = vault.subscriptions.map { sub in
            var one = sub
            if isSpending(sub) { one.paymentMethodId = "bank" }
            return one
        }
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        XCTAssertEqual(report.modules.count, 4, "a month is four modules, whatever paid for it")
        guard case .donut(let accounts) = report.modules[1] else { return XCTFail("accounts second") }
        XCTAssertEqual(accounts.slices.map(\.label), ["Savings account"])
        XCTAssertEqual(accounts.slices.map(\.amount), [42649], "the whole month, from one account")
    }

    func testTheCategoriesRingStandsWhenEveryChargeCarriesTheSameTag() {
        var vault = book()
        vault.subscriptions = vault.subscriptions.map { sub in
            var one = sub
            if isSpending(sub) { one.tag = "rent" }
            return one
        }
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        XCTAssertEqual(report.modules.count, 4, "a month is four modules, whatever it was spent on")
        guard case .donut(let categories) = report.modules[2] else { return XCTFail("categories third") }
        XCTAssertEqual(categories.title, MonthlyReport.Titles.categories)
        XCTAssertEqual(categories.slices.map(\.label), ["rent"])
        XCTAssertEqual(categories.slices.map(\.amount), [42649], "the whole month, under one tag")
    }

    func testAMonthOfUntaggedChargesDrawsTheRingToo() {
        var vault = book()
        vault.subscriptions = vault.subscriptions.map { sub in
            var one = sub
            one.tag = nil
            return one
        }
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        XCTAssertEqual(report.modules.count, 4, "no tag anywhere is still one ring")
        guard case .donut(let categories) = report.modules[2] else { return XCTFail("categories third") }
        XCTAssertEqual(categories.slices.map(\.label), ["No category"])
        XCTAssertEqual(categories.slices.map(\.amount), [42649])
    }

    func testEveryCategorySpentOnIsInTheRing() throws {
        var vault = book()
        for n in 1...9 {
            vault.subscriptions.append(Fx.sub(id: "t\(n)", name: "Charge \(n)", amount: 100, cycle: .once,
                                              tag: "tag \(n)", methodId: "card"))
            // Tags 8 and 9 hold the same sum, so the label has a tie to break.
            vault.charges.append(Fx.row("t\(n)", "2026-07-2\(n - 1)", amount: Double(min(n, 8)) * 10,
                                        paid: true, basis: "statement"))
        }
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        guard case .donut(let categories) = report.modules[2] else { return XCTFail("categories third") }
        let labels = categories.slices.map(\.label)
        XCTAssertEqual(labels.count, 11, "rent, streaming and nine more, none dropped")
        XCTAssertEqual(categories.slices.map(\.amount).reduce(0, +), report.modules.first.flatMap {
            if case .stats(let stats) = $0 { return stats.stats.first?.amount } else { return nil }
        }, "the shares describe the total the reader is shown")
        XCTAssertLessThan(try XCTUnwrap(labels.firstIndex(of: "tag 8")), try XCTUnwrap(labels.firstIndex(of: "tag 9")),
                          "equal sums draw in label order, so the same month draws the same bytes twice")
    }

    func testEveryAccountThatPaidIsInTheRing() {
        var vault = book()
        for n in 1...9 {
            vault.paymentMethods.append(PaymentMethod(id: "a\(n)", name: "Account \(n)", nameKey: "account-\(n)"))
            vault.subscriptions.append(Fx.sub(id: "c\(n)", name: "Charge \(n)", amount: 100, cycle: .once,
                                              tag: "shopping", methodId: "a\(n)"))
            vault.charges.append(Fx.row("c\(n)", "2026-07-2\(n - 1)", amount: Double(n) * 10, paid: true, basis: "statement"))
        }
        let report = MonthlyReport.build(vault: vault, month: LB.day(2026, 7, 1), currency: "INR", today: today)
        guard case .donut(let accounts) = report.modules[1] else { return XCTFail("accounts second") }
        XCTAssertEqual(accounts.slices.count, 11, "two accounts and nine more, none dropped")
        XCTAssertEqual(accounts.slices.map(\.amount).reduce(0, +), report.modules.first.flatMap {
            if case .stats(let stats) = $0 { return stats.stats.first?.amount } else { return nil }
        }, "the shares describe the total the reader is shown")
    }
}
