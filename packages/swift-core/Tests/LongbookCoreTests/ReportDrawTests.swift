import XCTest
@testable import LongbookCore

/// A span of days drawn on a month's terms: narrowed by account, member or category, with
/// rows the owner took out kept out, and named by its days.
final class ReportDrawTests: XCTestCase {
    private let today = LB.day(2026, 10, 20)

    /// A household: two people, two accounts, a week away in Goa in the middle of October.
    private func household() -> Vault {
        let rent = Fx.sub(id: "rent", name: "House rent", amount: 42000, tag: "rent", memberId: "r", methodId: "bank")
        let hotel = Fx.sub(id: "hotel", name: "Taj Holiday Village", amount: 18000, cycle: .once, tag: "travel", memberId: "r", methodId: "card")
        let flights = Fx.sub(id: "air", name: "IndiGo", amount: 9400, cycle: .once, tag: "travel", memberId: "a", methodId: "card")
        let dinner = Fx.sub(id: "fish", name: "Fisherman's Wharf", amount: 3200, cycle: .once, tag: "food", memberId: "r", methodId: "cash")
        let groceries = Fx.sub(id: "shop", name: "Corner shop", amount: 1800, cycle: .once, tag: "food", memberId: "a", methodId: "bank")
        var vault = Vault(
            app: "longbook", subscriptions: [rent, hotel, flights, dinner, groceries],
            paymentMethods: [
                PaymentMethod(id: "bank", name: "HDFC savings", nameKey: "hdfc-savings"),
                PaymentMethod(id: "card", name: "Amex 1007", nameKey: "amex-1007"),
                PaymentMethod(id: "cash", name: "Cash", nameKey: "cash"),
            ],
            charges: [
                Fx.row("rent", "2026-10-01", amount: 42000, paid: true, basis: "statement"),
                Fx.row("hotel", "2026-10-10", amount: 18000, paid: true, basis: "statement"),
                Fx.row("air", "2026-10-09", amount: 9400, paid: true, basis: "statement"),
                Fx.row("fish", "2026-10-12", amount: 3200, paid: true, basis: "user"),
                Fx.row("shop", "2026-10-15", amount: 1800, paid: true, basis: "statement"),
            ]
        )
        vault.familyMembers = [
            FamilyMember(id: "r", name: "Rohit", nameKey: "rohit"),
            FamilyMember(id: "a", name: "Anita", nameKey: "anita"),
        ]
        return vault
    }

    func testATripIsTheDaysAwayNarrowedToItsPeopleAndAccounts() throws {
        let trip = MonthlyReport.draw(
            vault: household(), id: "goa-october-2026", title: "Goa", from: LB.day(2026, 10, 9), to: LB.day(2026, 10, 14),
            scope: ReportScope(accounts: ["Amex 1007", "Cash"], members: ["Rohit", "Anita"]), currency: "INR", today: today
        )
        XCTAssertEqual(trip.title, "Goa")
        XCTAssertEqual(trip.rangeName, "9–14 October 2026")
        XCTAssertEqual(trip.scopeLine, "Accounts: Amex 1007, Cash · Members: Rohit, Anita")
        XCTAssertNil(trip.period, "a span is not a month")
        guard case .stats(let stats) = trip.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].amount, 30600, "the hotel, the flights and the dinner; the rent and the shop are outside")
        XCTAssertNil(stats.stats[0].deltaPct, "nothing was named to compare against")
        XCTAssertEqual(stats.stats[1].value, "3")
        guard case .transactions(let rows) = trip.modules[3] else { return XCTFail("charges last") }
        XCTAssertEqual(rows.rows.map(\.name), ["Taj Holiday Village", "IndiGo", "Fisherman's Wharf"], "biggest first")
        XCTAssertEqual(rows.rows.map(\.member), ["Rohit", "Anita", "Rohit"])
        XCTAssertEqual(rows.rows.map(\.account), ["Amex 1007", "Amex 1007", "Cash"])
        // The file says its own days and scope, so any reader draws the same trip.
        let back = try JSONDecoder().decode(Report.self, from: try JSONEncoder().encode(trip))
        XCTAssertEqual(back.startDate, "2026-10-09")
        XCTAssertEqual(back.endDate, "2026-10-14")
        XCTAssertEqual(back.scope?.accounts, ["Amex 1007", "Cash"])
    }

    func testAMemberAloneNarrowsToTheirCharges() {
        let hers = MonthlyReport.draw(
            vault: household(), id: "anita-october", title: "Anita in October", from: LB.day(2026, 10, 1), to: LB.day(2026, 10, 31),
            scope: ReportScope(members: ["Anita"]), currency: "INR", today: today
        )
        guard case .stats(let stats) = hers.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].amount, 11200, "the flights and the shop")
        guard case .donut(let accounts) = hers.modules[1] else { return XCTFail("accounts second") }
        XCTAssertEqual(accounts.slices.map(\.label), ["Amex 1007", "HDFC savings"])
    }

    /// A charge the owner took out is listed at the end, marked, and in no figure; a redraw
    /// keeps it out because the file names it.
    func testARowTakenOutIsListedLastAndCountedNowhere() throws {
        let removed: Set<String> = ["hotel-2026-10-10"]
        let october = MonthlyReport.build(vault: household(), month: LB.day(2026, 10, 1), currency: "INR", removed: removed, today: today)
        guard case .stats(let stats) = october.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].amount, 56400, "everything but the hotel")
        XCTAssertEqual(stats.stats[1].value, "4")
        XCTAssertFalse(stats.stats.contains { $0.label == MonthlyReport.Labels.unconfirmed }, "taken out is not unconfirmed")
        guard case .donut(let categories) = october.modules[2] else { return XCTFail("categories third") }
        XCTAssertEqual(categories.slices.first(where: { $0.label == "travel" })?.amount, 9400, "the ring forgets the hotel too")
        guard case .transactions(let rows) = october.modules[3] else { return XCTFail("charges last") }
        XCTAssertEqual(rows.rows.map(\.name), ["House rent", "IndiGo", "Fisherman's Wharf", "Corner shop", "Taj Holiday Village"])
        XCTAssertEqual(rows.rows.last?.removed, true)
        XCTAssertNil(rows.rows.first?.removed, "a row that is in is not marked")
        XCTAssertEqual(october.chargeRows.kept.count, 4)
        XCTAssertEqual(october.chargeRows.removed.map(\.id), ["hotel-2026-10-10"])
        XCTAssertEqual(october.removedIds, removed, "what a redraw is told to keep out")
        let again = MonthlyReport.build(vault: household(), month: LB.day(2026, 10, 1), currency: "INR", removed: october.removedIds, today: today)
        // Sorted keys, as the app writes the file: an unsorted encoder may order keys differently
        // from one run to the next on some Foundation versions.
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        XCTAssertEqual(try sorted.encode(again), try sorted.encode(october), "the same draw, so nothing is rewritten")
    }

    func testTheDaysAreNamedForWhatTheySpan() {
        var report = MonthlyReport.build(vault: household(), month: LB.day(2026, 10, 1), currency: "INR", today: today)
        XCTAssertEqual(report.rangeName, "1–31 October 2026")
        report.startDate = "2026-09-28"
        report.endDate = "2026-10-03"
        XCTAssertEqual(report.rangeName, "28 September – 3 October 2026")
        report.startDate = "2025-12-30"
        report.endDate = "2026-01-02"
        XCTAssertEqual(report.rangeName, "30 December 2025 – 2 January 2026")
        report.startDate = "not a day"
        XCTAssertEqual(report.rangeName, "1–31 October 2026", "bad days fall back to the month the file names")
        report.period = nil
        report.endDate = nil
        XCTAssertEqual(report.rangeName, "1–31 October 2026", "then to the month every dated row falls in")
    }

    func testAnOlderFileStillReads() throws {
        let old = """
        {"version":1,"id":"july-2026","title":"July in review","subtitle":"Drawn by longbook","period":"2026-07",
         "currency":"INR","modules":[{"type":"stats","title":"Total expenses","stats":[{"label":"Total for July","amount":649,"currency":"INR"}]},
         {"type":"transactions","title":"All charges","rows":[{"name":"Netflix","date":"2026-07-03","amount":649,"currency":"INR"}]}]}
        """
        let report = try JSONDecoder().decode(Report.self, from: Data(old.utf8))
        XCTAssertEqual(report.rangeName, "1–31 July 2026")
        XCTAssertNil(report.scope)
        XCTAssertNil(report.scopeLine)
        XCTAssertEqual(report.chargeRows.kept.count, 1)
        XCTAssertTrue(report.removedIds.isEmpty)
        XCTAssertEqual(report.totalStat?.amount, 649)
    }
}
