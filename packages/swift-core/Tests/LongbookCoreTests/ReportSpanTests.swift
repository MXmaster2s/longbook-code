import XCTest
@testable import LongbookCore

/// Spans longbook draws itself — trips, and reports an AI asked for: their ids, their currency,
/// how they redraw, how the list orders them, and how a request is checked and resolved.
final class ReportSpanTests: XCTestCase {
    private let today = LB.day(2026, 10, 20)

    private func household() -> Vault {
        let rent = Fx.sub(id: "rent", name: "House rent", amount: 42000, tag: "rent", memberId: "r", methodId: "bank")
        let hotel = Fx.sub(id: "hotel", name: "Hôtel Le Marais", amount: 400, currency: "EUR", cycle: .once, tag: "travel", memberId: "r", methodId: "card")
        let dinner = Fx.sub(id: "dinner", name: "Chez Janou", amount: 90, currency: "EUR", cycle: .once, tag: "food", memberId: "a", methodId: "card")
        let museum = Fx.sub(id: "museum", name: "Louvre", amount: 44, currency: "EUR", cycle: .once, tag: "travel", memberId: "a", methodId: "card")
        let taxi = Fx.sub(id: "taxi", name: "Airport taxi", amount: 1800, cycle: .once, tag: "travel", memberId: "r")
        var vault = Vault(
            app: "longbook", subscriptions: [rent, hotel, dinner, museum, taxi],
            paymentMethods: [
                PaymentMethod(id: "bank", name: "HDFC savings", nameKey: "hdfc savings"),
                PaymentMethod(id: "card", name: "Amex 1007", nameKey: "amex 1007"),
            ],
            charges: [
                Fx.row("rent", "2026-10-01", amount: 42000, paid: true, basis: "statement"),
                Fx.row("hotel", "2026-10-10", amount: 400, paid: true, basis: "statement", currency: "EUR"),
                Fx.row("dinner", "2026-10-11", amount: 90, paid: true, basis: "user", currency: "EUR"),
                Fx.row("museum", "2026-10-12", amount: 44, paid: true, basis: "statement", currency: "EUR"),
                Fx.row("taxi", "2026-10-09", amount: 1800, paid: true, basis: "user"),
            ]
        )
        vault.familyMembers = [FamilyMember(id: "r", name: "Rohit", nameKey: "rohit"), FamilyMember(id: "a", name: "Anita", nameKey: "anita")]
        return vault
    }

    // MARK: ids

    func testASpanIdIsItsPrefixNameAndFirstDayAndARetryKeepsIt() {
        let start = LB.day(2026, 10, 9), end = LB.day(2026, 10, 14)
        XCTAssertEqual(MonthlyReport.slug("Paris & Lyon — été!"), "paris-lyon-ete")
        XCTAssertEqual(MonthlyReport.slug("  ***  "), "")
        XCTAssertEqual(MonthlyReport.spanId(prefix: "trip", title: "Paris", start: start, end: end, scope: nil, existing: []), "trip-paris-2026-10-09")
        XCTAssertEqual(MonthlyReport.spanId(prefix: "report", title: "✈︎", start: start, end: end, scope: nil, existing: []), "report-2026-10-09",
                       "a name with no letters keeps the prefix and the day")
        let drawn = MonthlyReport.draw(vault: household(), id: "trip-paris-2026-10-09", title: "Paris", from: start, to: end,
                                       scope: nil, currency: "EUR", today: today)
        XCTAssertEqual(MonthlyReport.spanId(prefix: "trip", title: "Paris", start: start, end: end, scope: nil, existing: [drawn]),
                       "trip-paris-2026-10-09", "the same name, days and scope asked again redraw the same file")
        XCTAssertEqual(MonthlyReport.spanId(prefix: "trip", title: "Paris", start: start, end: LB.day(2026, 10, 15), scope: nil, existing: [drawn]),
                       "trip-paris-2026-10-09-2", "different days never overwrite another report")
        XCTAssertNotEqual(MonthlyReport.spanId(prefix: "trip", title: "October 2026", start: start, end: end, scope: nil, existing: []),
                          MonthlyReport.id(for: LB.day(2026, 10, 1)), "a span can never take a month's file")
    }

    // MARK: currency

    func testATripAbroadReadsInTheMoneyItWasSpentIn() {
        let scope = ReportScope(accounts: ["Amex 1007"])
        XCTAssertEqual(MonthlyReport.spanCurrency(vault: household(), from: LB.day(2026, 10, 9), to: LB.day(2026, 10, 14),
                                                  scope: scope, fallback: "INR", today: today), "EUR")
        XCTAssertEqual(MonthlyReport.spanCurrency(vault: household(), from: LB.day(2026, 10, 1), to: LB.day(2026, 10, 1),
                                                  scope: nil, fallback: "INR", today: today), "INR")
        XCTAssertEqual(MonthlyReport.spanCurrency(vault: household(), from: LB.day(2026, 11, 1), to: LB.day(2026, 11, 5),
                                                  scope: nil, fallback: "INR", today: today), "INR", "an empty span keeps the home currency")
    }

    // MARK: redraw

    func testASpanRedrawsFromItsOwnDaysScopeAndRemovedRows() throws {
        let vault = household()
        let start = LB.day(2026, 10, 9)
        var trip = MonthlyReport.draw(vault: vault, id: "trip-paris-2026-10-09", title: "Paris", from: start, to: start,
                                      scope: ReportScope(members: ["Rohit", "Anita"]), currency: "INR",
                                      removed: ["taxi-2026-10-09"], today: today)
        trip.modules[0].comment = "Booked by Anita"
        XCTAssertTrue(trip.isDrawnSpan)
        XCTAssertTrue(trip.isTrip)
        XCTAssertEqual(trip.rangeName, "9 October 2026", "one day reads as one day")

        // An open trip follows today: the redraw moves its last day and picks up the euros.
        let open = try XCTUnwrap(MonthlyReport.redraw(trip, vault: vault, through: LB.day(2026, 10, 12), fallbackCurrency: "INR", today: today))
        XCTAssertEqual(open.id, trip.id)
        XCTAssertEqual(open.endDate, "2026-10-12")
        XCTAssertEqual(open.currency, "EUR", "three euro charges against one rupee taxi")
        XCTAssertEqual(open.modules[0].comment, "Booked by Anita", "a viewer's words survive the redraw")
        XCTAssertEqual(open.chargeRows.removed.map(\.id), ["taxi-2026-10-09"], "what the owner took out stays out")
        guard case .stats(let stats) = open.modules[0] else { return XCTFail("stats first") }
        XCTAssertEqual(stats.stats[0].amount, 534)

        // Closed, it keeps its own last day.
        let closed = try XCTUnwrap(MonthlyReport.redraw(open, vault: vault, fallbackCurrency: "INR", today: today))
        XCTAssertEqual(closed.endDate, "2026-10-12")

        let month = MonthlyReport.build(vault: vault, month: LB.day(2026, 10, 1), currency: "INR", today: today)
        XCTAssertFalse(month.isDrawnSpan, "a month is not a span")
        XCTAssertNil(MonthlyReport.redraw(month, vault: vault, fallbackCurrency: "INR", today: today))
        var written = trip
        written.subtitle = "Written by Claude"
        XCTAssertNil(MonthlyReport.redraw(written, vault: vault, fallbackCurrency: "INR", today: today), "another author's file is never redrawn")
    }

    func testNoAccountNarrowsToChargesBilledToNone() {
        let none = MonthlyReport.draw(vault: household(), id: "x", title: "X", from: LB.day(2026, 10, 1), to: LB.day(2026, 10, 31),
                                      scope: ReportScope(accounts: ["No account"]), currency: "INR", today: today)
        XCTAssertEqual(none.chargeRows.kept.map(\.name), ["Airport taxi"])
    }

    // MARK: the list

    func testTheListOrdersByTheLastDayCovered() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let reports = folder.appendingPathComponent("reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = household()
        let encoder = JSONEncoder()
        let files = [
            MonthlyReport.build(vault: vault, month: LB.day(2026, 9, 1), currency: "INR", today: today),
            MonthlyReport.build(vault: vault, month: LB.day(2026, 10, 1), currency: "INR", today: today),
            MonthlyReport.draw(vault: vault, id: "trip-paris-2026-10-09", title: "Paris", from: LB.day(2026, 10, 9),
                               to: LB.day(2026, 10, 14), scope: nil, currency: "EUR", today: today),
            MonthlyReport.draw(vault: vault, id: "trip-diwali-2026-10-30", title: "Diwali", from: LB.day(2026, 10, 30),
                               to: LB.day(2026, 11, 2), scope: nil, currency: "INR", today: today),
        ]
        for report in files {
            try encoder.encode(report).write(to: reports.appendingPathComponent("\(report.id).json"))
        }
        XCTAssertEqual(ReportReader.list(in: folder).reports.map(\.id),
                       ["trip-diwali-2026-10-30", "october-2026", "trip-paris-2026-10-09", "september-2026"])
    }

    // MARK: requests

    private func raw() -> [String: Any] {
        [
            "accounts": [["id": "bank", "name": "HDFC savings", "name_key": "hdfc savings"],
                         ["id": "card", "name": "Amex 1007", "name_key": "amex 1007"]],
            "members": [["id": "r", "name": "Rohit", "name_key": "rohit"]],
            "commitments": [["id": "hotel", "name": "Hotel", "tag": "travel"]],
            "tags": [["name": "Food", "kind": "commitment"]],
        ]
    }

    func testARequestIsResolvedToTheNamesTheMemoryStores() throws {
        let request = try PendingApply.reportRequest([
            "title": "  Paris  ", "start_date": "2026-10-09", "end_date": "2026-10-14",
            "accounts": ["amex 1007", "no account"], "members": ["ROHIT"], "categories": ["Travel", "food", "No Category"],
        ], in: raw(), now: today)
        XCTAssertEqual(request.title, "Paris")
        XCTAssertEqual(request.start, LB.day(2026, 10, 9))
        XCTAssertEqual(request.scope, ReportScope(accounts: ["Amex 1007", "No account"], members: ["Rohit"], categories: ["travel", "Food", "No category"]))
        let everything = try PendingApply.reportRequest(["title": "All", "start_date": "2026-10-01", "end_date": "2026-10-01", "accounts": []], in: raw(), now: today)
        XCTAssertNil(everything.scope, "an empty list narrows nothing")
    }

    func testARequestIsRefusedInTheOwnersWords() {
        func refusal(_ payload: [String: Any]) -> String? {
            do { _ = try PendingApply.reportRequest(payload, in: raw(), now: today); return nil } catch { return error.localizedDescription }
        }
        let good: [String: Any] = ["title": "Paris", "start_date": "2026-10-09", "end_date": "2026-10-14"]
        XCTAssertNil(refusal(good))
        XCTAssertEqual(refusal(good.merging(["currency": "EUR"]) { $1 }),
                       "longbook draws the report; name only title, start_date, end_date, accounts, members and categories.")
        XCTAssertNotNil(refusal(good.merging(["title": " "]) { $1 }))
        XCTAssertNotNil(refusal(good.merging(["start_date": "2026-02-31"]) { $1 }), "an invented day")
        XCTAssertNotNil(refusal(good.merging(["start_date": "2026-10-15"]) { $1 }), "first day after the last")
        XCTAssertNotNil(refusal(good.merging(["start_date": "2026-10-21", "end_date": "2026-10-25"]) { $1 }), "starting after today")
        XCTAssertNotNil(refusal(good.merging(["start_date": "2025-01-01"]) { $1 }), "more than 366 days")
        XCTAssertEqual(refusal(good.merging(["accounts": ["Visa"]]) { $1 }),
                       "No account in the memory is called \"Visa\". The memory has: HDFC savings, Amex 1007.")
        XCTAssertNotNil(refusal(good.merging(["members": ["Meera"]]) { $1 }))
        XCTAssertNotNil(refusal(good.merging(["categories": ["Gifts"]]) { $1 }))
        XCTAssertNotNil(refusal(good.merging(["members": "Rohit"]) { $1 }), "a list, not a string")
    }

    func testTheApplyStepTurnsARequestIntoADrawAndNothingElse() throws {
        let write = PendingWrite(id: UUID(), kind: "create_report", payload: ["title": "Paris", "start_date": "2026-10-09", "end_date": "2026-10-14"])
        guard case .drawReport(let request) = try PendingApply.apply(write, to: raw(), now: today) else { return XCTFail("a draw") }
        XCTAssertEqual(request.title, "Paris")
    }

    // MARK: what the review found

    func testAHandMadeFileCanNeverAimARedrawAtAnotherFile() throws {
        for bad in ["../financial_memory", "a/b", ".hidden", "..", "", "x\\y", String(repeating: "a", count: 161)] {
            XCTAssertFalse(MonthlyReport.isSafeId(bad), bad)
        }
        XCTAssertTrue(MonthlyReport.isSafeId("trip-goa-2026-10-09"))
        XCTAssertTrue(MonthlyReport.isSafeId("märz-2026"), "a month in another language is still one file name")
        let file = """
        {"version":2,"id":"../financial_memory","title":"x","subtitle":"Drawn by longbook",
         "start_date":"2026-09-01","end_date":"2026-09-02","modules":[]}
        """
        let planted = try JSONDecoder().decode(Report.self, from: Data(file.utf8))
        XCTAssertTrue(planted.isDrawnSpan)
        XCTAssertFalse(MonthlyReport.redrawsItself(planted), "never redrawn, so never written")
        var month = planted
        month = try JSONDecoder().decode(Report.self, from: Data(file.replacingOccurrences(of: "../financial_memory", with: "september-2026").utf8))
        XCTAssertFalse(MonthlyReport.redrawsItself(month), "a span wearing a month's id would fight the month's draw")
    }

    func testARenameLeavesTheSpanAsItWasRatherThanEmptyingIt() throws {
        var vault = household()
        let trip = MonthlyReport.draw(vault: vault, id: "trip-paris-2026-10-09", title: "Paris", from: LB.day(2026, 10, 9),
                                      to: LB.day(2026, 10, 14), scope: ReportScope(accounts: ["Amex 1007"]), currency: "EUR", today: today)
        XCTAssertNotNil(MonthlyReport.redraw(trip, vault: vault, fallbackCurrency: "INR", today: today))
        vault.paymentMethods[1].name = "Amex Gold"
        XCTAssertNil(MonthlyReport.redraw(trip, vault: vault, fallbackCurrency: "INR", today: today),
                     "the account it names is gone, so the file is kept as it was")
        XCTAssertTrue(MonthlyReport.namesExist(ReportScope(accounts: ["No account"], categories: ["TRAVEL", "No category"]), in: vault))
    }

    func testTheSameScopeInAnotherOrderIsTheSameReport() {
        let start = LB.day(2026, 10, 9), end = LB.day(2026, 10, 14)
        let drawn = MonthlyReport.draw(vault: household(), id: "trip-paris-2026-10-09", title: "Paris", from: start, to: end,
                                       scope: ReportScope(members: ["Rohit", "Anita"]), currency: "EUR", today: today)
        XCTAssertEqual(MonthlyReport.spanId(prefix: "trip", title: "Paris", start: start, end: end,
                                            scope: ReportScope(members: ["Anita", "Rohit"]), existing: [drawn]), "trip-paris-2026-10-09")
    }

    func testACategoryIsOneNameInAnyCasing() {
        let travel = MonthlyReport.draw(vault: household(), id: "x", title: "X", from: LB.day(2026, 10, 1), to: LB.day(2026, 10, 31),
                                        scope: ReportScope(categories: ["Travel"]), currency: "INR", today: today)
        XCTAssertEqual(Set(travel.chargeRows.kept.map(\.name)), ["Hôtel Le Marais", "Louvre", "Airport taxi"])
    }

    func testTheCurrencyFollowsTheChargesStillInTheReport() {
        let start = LB.day(2026, 10, 9), end = LB.day(2026, 10, 14)
        let euros: Set<String> = ["hotel-2026-10-10", "dinner-2026-10-11", "museum-2026-10-12"]
        XCTAssertEqual(MonthlyReport.spanCurrency(vault: household(), from: start, to: end, scope: nil, fallback: "INR", today: today), "EUR")
        XCTAssertEqual(MonthlyReport.spanCurrency(vault: household(), from: start, to: end, scope: nil, fallback: "INR",
                                                  excluding: euros, today: today), "INR", "removed charges choose nothing")
    }

    func testARequestedTitleTakesTheDataPolicyScan() {
        XCTAssertThrowsError(try PendingApply.reportRequest(
            ["title": "Card 4111 1111 1111 1111", "start_date": "2026-10-09", "end_date": "2026-10-14"], in: raw(), now: today))
    }

    func testTheScopeLineShowsCategoriesAsTheScreenDoes() {
        var report = MonthlyReport.draw(vault: household(), id: "x", title: "X", from: LB.day(2026, 10, 1), to: LB.day(2026, 10, 2),
                                        scope: ReportScope(categories: ["travel", "No category"]), currency: "INR", today: today)
        XCTAssertEqual(report.scopeLine, "Categories: Travel, No category")
        report.scope = nil
        XCTAssertNil(report.scopeLine)
    }

    func testTheOpenTripLivesInTheSidecar() {
        var workspace = Workspace()
        XCTAssertNil(workspace.openTrip)
        workspace.openTrip = "trip-paris-2026-10-09"
        XCTAssertEqual(workspace.openTrip, "trip-paris-2026-10-09")
        workspace.openTrip = nil
        XCTAssertNil(workspace.openTrip)
        XCTAssertTrue(workspace.raw["openTrip"] is NSNull, "cleared, not left behind")
    }
}
