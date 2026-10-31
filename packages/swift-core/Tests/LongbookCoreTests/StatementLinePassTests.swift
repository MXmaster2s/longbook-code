// Reading by the device's own lines: when they can be trusted, what leaves the device, how the
// model's rows join the lines, and every way a call can come back. Lines here are made up.
import XCTest
@testable import LongbookCore

final class StatementLinePassTests: XCTestCase {
    private func line(_ date: String, _ amount: Double, _ payee: String = "UPI-CORNER SHOP-SHOP@OKAXIS", _ direction: StatementLine.Direction = .debit) -> StatementLine {
        StatementLine(date: date, payee: payee, amount: amount, direction: direction)
    }

    private var threeLines: [StatementLine] {
        [line("2026-07-01", 100), line("2026-07-02", 200), line("2026-07-03", 1000, "NEFT CR-SALARY", .credit)]
    }

    private func plan(_ lines: [StatementLine]? = nil, header: String = "MR ASHA RAO\nAccount 501000123456") -> StatementLinePass.Plan {
        let lines = lines ?? threeLines
        let net = lines.reduce(0.0) { $0 + ($1.direction == .credit ? $1.amount : -$1.amount) }
        return StatementLinePass.Plan(name: "a.pdf", expected: .init(lines: lines, opening: 500, closing: 500 + net, header: header))
    }

    private let asking = StatementLinePass.Asking(importId: "abcdefgh", categories: ["rent"], members: [], accounts: [], currency: "INR")
    private let head = StatementLinePass.Head(account: "HDFC savings 3456", holder: "MR ASHA RAO", currency: "INR")

    // MARK: when the device is trusted

    func testLinesThatCloseAreTrustedAndEveryOtherFileGoesAsADocument() {
        let lines = threeLines
        XCTAssertNil(StatementLinePass.distrust(.init(lines: lines, opening: 500, closing: 1200), today: "2026-10-31"))
        XCTAssertEqual(StatementLinePass.distrust(nil), .unreadable)
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: Array(lines.prefix(2)), opening: 500, closing: 200), today: "2026-10-31"), .tooFewLines)
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: lines), today: "2026-10-31"), .noBalances)
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: lines, opening: 500), today: "2026-10-31"), .noBalances)
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: lines, opening: 500, closing: 1200.01), today: "2026-10-31"), .doesNotClose)
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: lines, opening: 500, closing: 1200), today: "2026-07-02"), .oddLine, "a day after today is not a fact")
        let nameless = [line("2026-07-01", 100, "123456"), line("2026-07-02", 200), line("2026-07-03", 1000, "SALARY", .credit)]
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: nameless, opening: 500, closing: 1200), today: "2026-10-31"), .oddLine)
    }

    func testADroppedLineOrAFlippedDirectionBreaksTheSum() {
        var lines = threeLines
        lines.removeFirst()
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: lines + [line("2026-07-04", 50)], opening: 500, closing: 1200), today: "2026-10-31"), .doesNotClose)
        let flipped = [line("2026-07-01", 100, "SHOP", .credit), line("2026-07-02", 200), line("2026-07-03", 1000, "SALARY", .credit)]
        XCTAssertEqual(StatementLinePass.distrust(.init(lines: flipped, opening: 500, closing: 1200), today: "2026-10-31"), .doesNotClose)
    }

    func testAFileThatClosesIsPlannedAndOneThatDoesNotIsCutIntoPieces() throws {
        let fixtures = try XCTUnwrap(Bundle.module.url(forResource: "statements", withExtension: nil, subdirectory: "Fixtures"))
        let sheet = FileManager.default.temporaryDirectory.appendingPathComponent("lines-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: sheet) }
        try "Holder,Asha Rao\nDate,Narration,Debit,Credit,Balance\n01/07/2026,SHOP,100,,400\n02/07/2026,SALARY,,1000,1400\n03/07/2026,RENT,200,,1200\n".write(to: sheet, atomically: true, encoding: .utf8)
        guard case .lines(let plan) = try StatementCloud.reading(for: sheet, password: nil) else {
            return XCTFail("the sheet's balance column closes")
        }
        XCTAssertEqual(plan.lines.count, 3)
        XCTAssertEqual(plan.header, "Holder Asha Rao")
        guard case .document(_, let plain) = try StatementCloud.reading(for: fixtures.appendingPathComponent("hdfc-savings-2025-2026.csv"), password: nil) else {
            return XCTFail("a sheet with no balances proves nothing")
        }
        XCTAssertEqual(plain, .noBalances)
        guard case .document(let pieces, let why) = try StatementCloud.reading(for: fixtures.appendingPathComponent("icici-scanned-june.pdf"), password: nil) else {
            return XCTFail("a scan has no lines of its own")
        }
        XCTAssertFalse(pieces.isEmpty)
        XCTAssertEqual(why, .unreadable)
    }

    func testASheetsRunningBalanceClosesEitherWayRound() {
        let header = ["Date", "Narration", "Withdrawal", "Deposit", "Balance"]
        let oldestFirst = [header, ["01/07/2026", "SHOP", "100", "", "400"], ["02/07/2026", "SALARY", "", "1000", "1400"], ["03/07/2026", "RENT", "200", "", "1200"]]
        let forward = StatementLines.sheetBalances(oldestFirst)
        XCTAssertEqual(forward?.opening, 500)
        XCTAssertEqual(forward?.closing, 1200)
        let backward = StatementLines.sheetBalances([header] + oldestFirst.dropFirst().reversed())
        XCTAssertEqual(backward?.opening, 500)
        XCTAssertEqual(backward?.closing, 1200)
        XCTAssertNil(StatementLines.sheetBalances([["Date", "Narration", "Amount"], ["01/07/2026", "SHOP", "100"]]), "no such column")
    }

    func testTheHeaderIsWhatThePrintsAboveTheFirstLine() {
        let sheet = StatementText.Reading(lines: [], rows: [], records: [["Holder", "Asha Rao"], [], ["Date", "Narration", "Amount"], ["01/07/2026", "SHOP", "100"]])
        XCTAssertEqual(StatementCompleteness.header(of: sheet), "Holder Asha Rao")
    }

    // MARK: what leaves the device

    func testALongNumberKeepsItsLengthAndLastFourAndAnIFSCStaysWhole() {
        XCTAssertEqual(StatementLinePass.masked("TRF TO 501000123456"), "TRF TO ••••••••3456")
        XCTAssertEqual(StatementLinePass.masked("UPI-ASHA-ASHA@OKAXIS-UTIB0001234-612345678901-FOOD"), "UPI-ASHA-ASHA@OKAXIS-UTIB0001234-••••••••8901-FOOD")
        XCTAssertEqual(StatementLinePass.masked("CARD 4111 1111 1111 1234"), "CARD ••••••••••••1234")
        XCTAssertEqual(StatementLinePass.masked("9876543210@YBL"), "••••••3210@YBL")
        XCTAssertEqual(StatementLinePass.masked("A/C XX4417 RENT 2026"), "A/C XX4417 RENT 2026", "short numbers say nothing private")
    }

    func testAReferenceRunIntoANameIsSetApartAndTheNameSurvivesInTheNote() {
        XCTAssertEqual(StatementLinePass.masked("UPI-ASHA RAO0000123456789012 X"), "UPI-ASHA RAO ••••••••••••9012 X")
        let answer = StatementLinePass.answer(plan([line("2026-07-01", 100, "UPI-ASHA RAO0000123456789012"), line("2026-07-02", 200), line("2026-07-03", 1000, "SALARY", .credit)]), head: head, rows: [])
        XCTAssertEqual(answer.charges[0].narration, "UPI-ASHA RAO")
    }

    func testThePlanSendsOnlyMaskedLinesAndCutsThemIntoBatches() throws {
        let many = (1...65).map { line("2026-07-01", Double($0), "SHOP \($0)") }
        let plan = plan(many)
        XCTAssertEqual(plan.batches.map(\.count), [30, 30, 5])
        XCTAssertEqual(plan.lines.first?.n, 1)
        XCTAssertEqual(plan.lines.last?.n, 65)
        XCTAssertEqual(plan.header, "MR ASHA RAO\nAccount ••••••••3456")
        XCTAssertEqual(plan.lines.first?.direction, "out")
    }

    // MARK: joining the model's rows to the lines

    func testEveryLineIsAChargeWithItsFactsFromTheFileWhateverTheModelSaid() {
        let rows = [
            StatementLinePass.Row(n: 1, name: "Corner shop", kind: "income", category: "rent"),
            StatementLinePass.Row(n: 3, name: "Salary", kind: "spend"),
        ]
        let answer = StatementLinePass.answer(plan(), head: head, rows: rows)
        XCTAssertEqual(answer.charges.map(\.date), ["2026-07-01", "2026-07-02", "2026-07-03"])
        XCTAssertEqual(answer.charges.map(\.amount), [100, 200, 1000])
        XCTAssertEqual(answer.charges.map(\.kind), ["spend", "spend", "income"], "the file's columns settle the way the money went")
        XCTAssertEqual(answer.charges[1].name, "Corner Shop", "a line with no row is named as printed")
        XCTAssertEqual(answer.closingBalance, 1200)
        XCTAssertEqual(answer.closingBalanceDate, "2026-07-03")
        XCTAssertEqual(answer.account, "HDFC savings 3456")
    }

    func testALinePrintingTheHoldersNameIsTheHoldersAndItsAccountIsTheirs() {
        let own = line("2026-07-01", 100, "NEFT-RAO ASHA-HDFC SAV XX4417")
        let rows = [StatementLinePass.Row(n: 1, name: "HDFC savings", kind: "for_member", member: "Asha", counterpart: "HDFC savings ••4417", counterpartKind: "account")]
        let answer = StatementLinePass.answer(plan([own, line("2026-07-02", 200), line("2026-07-03", 1000, "SALARY", .credit)]), head: head, rows: rows)
        XCTAssertEqual(answer.charges[0].counterpart, "Asha Rao")
        XCTAssertEqual(answer.charges[0].counterpartKind, "person")
        XCTAssertEqual(answer.charges[0].counterpartBank, "HDFC savings ••4417")
        XCTAssertNil(answer.charges[0].member)
        XCTAssertEqual(answer.charges[0].kind, "spend")
        let prepared = StatementCloud.Prepared.assemble([answer], review: .empty, mendingDates: false)
        let moved = prepared.candidates(among: [], today: "2026-10-31")
        XCTAssertEqual(moved[0].direction, "transfer", "both accounts belong to the holder")
    }

    func testOneWordInCommonIsNotTheHolder() {
        let other = line("2026-07-01", 100, "UPI-ASHA MEHTA-X")
        let rows = [StatementLinePass.Row(n: 1, name: "Payment to Asha Mehta", kind: "spend", counterpart: "Asha Mehta", counterpartKind: "person")]
        let answer = StatementLinePass.answer(plan([other, line("2026-07-02", 200), line("2026-07-03", 1000, "SALARY", .credit)]), head: head, rows: rows)
        XCTAssertEqual(answer.charges[0].counterpart, "Asha Mehta")
    }

    func testAPersonOnALineWithAnIFSCCodeHasAnAccountAtThatBank() {
        let printed = "UPI-RAMESH K-RK@OKAXIS-UTIB0001234-612345678901-X"
        let person = StatementLinePass.Row(n: 1, name: "Payment to Ramesh K", kind: "spend", counterpart: "Ramesh K", counterpartKind: "person")
        XCTAssertEqual(StatementLinePass.bankedPerson(person, printed: printed).counterpartBank, "Axis Bank")
        let merchant = StatementLinePass.Row(n: 1, name: "Corner shop", kind: "spend")
        XCTAssertNil(StatementLinePass.bankedPerson(merchant, printed: printed).counterpartBank, "a merchant has no account here")
        let said = StatementLinePass.Row(n: 1, name: "X", kind: "spend", counterpart: "Ramesh K", counterpartKind: "person", counterpartBank: "Axis savings ••1234")
        XCTAssertEqual(StatementLinePass.bankedPerson(said, printed: printed).counterpartBank, "Axis savings ••1234")
        XCTAssertNil(StatementLinePass.bankedPerson(person, printed: "UPI-RAMESH K-ZZZZ0001234").counterpartBank, "a code longbook does not know")
    }

    func testARepeatTakesItsDaysAndAmountFromTheLinesAndUnderThreeIsAGuess() {
        let lines = [line("2026-05-05", 649), line("2026-06-05", 649), line("2026-07-05", 649), line("2026-07-06", 99), line("2026-07-07", 5000, "SALARY", .credit)]
        let plan = plan(lines)
        var names = Array(repeating: "Netflix", count: 4)
        names.append("Salary")
        let charges = lines.enumerated().map { index, line in
            StatementCloud.Charge(date: line.date, amount: line.amount, name: names[index], narration: "", account: "A", category: nil, kind: "spend", member: nil)
        }
        let found = StatementLinePass.repeats([
            StatementLinePass.RepeatRow(name: "Netflix", lines: [3, 1, 2, 2, 99, 5], cycle: "monthly", reason: "dropped"),
            StatementLinePass.RepeatRow(name: "Salary", lines: [5], cycle: "monthly", reason: "Seen once; monthly assumed."),
            StatementLinePass.RepeatRow(name: "Ghost", lines: [1], cycle: "monthly"),
        ], plan: plan, charges: charges)
        XCTAssertEqual(found.map(\.name), ["Netflix", "Salary"])
        XCTAssertEqual(found[0].dates, ["2026-05-05", "2026-06-05", "2026-07-05"], "a number repeated, unknown or of another name is left out")
        XCTAssertEqual(found[0].amount, 649)
        XCTAssertFalse(found[0].guessed)
        XCTAssertEqual(found[0].reason, "")
        XCTAssertTrue(found[1].guessed)
        XCTAssertEqual(found[1].writtenName, "Salary (Guessed)")
        XCTAssertEqual(found[1].guessedNote, "Guessed: Seen once; monthly assumed.")
    }

    func testTheGroupsCarryOneLineANameWithItsSightings() {
        let plan = plan()
        let charges = plan.expected.lines.map { StatementCloud.Charge(date: $0.date, amount: $0.amount, name: $0.direction == .credit ? "Salary" : "Shop", narration: "", account: "A", category: nil, kind: "spend", member: nil) }
        XCTAssertEqual(StatementLinePass.groups(plan, charges: charges).split(separator: "\n").map(String.init), [
            "Shop | out |  | UPI-CORNER SHOP-SHOP@OKAXIS | 1 2026-07-01 100.00; 2 2026-07-02 200.00",
            "Salary | in |  | NEFT CR-SALARY | 3 2026-07-03 1000.00",
        ])
    }

    func testPeopleAreListedOnceInLineOrder() {
        func charge(_ member: String?, _ other: String? = nil) -> StatementCloud.Charge {
            StatementCloud.Charge(date: "2026-07-01", amount: 1, name: "X", narration: "", account: "A", category: nil, kind: "spend", member: member, counterpart: other, counterpartKind: other == nil ? nil : "person")
        }
        XCTAssertEqual(StatementLinePass.members(in: [charge("Asha"), charge(nil), charge(nil, "ASHA"), charge(nil, "Ramesh K")]).map(\.name), ["Asha", "Ramesh K"])
    }

    // MARK: reading

    /// What the server would answer, from a closure over the decoded body.
    private func server(_ answer: @escaping @Sendable ([String: Any]) throws -> Any) -> StatementLinePass.Transport {
        { data in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try JSONSerialization.data(withJSONObject: try answer(body))
        }
    }

    private func rows(for body: [String: Any], skipping: Set<Int> = []) -> [[String: Any]] {
        (body["lines"] as? [[String: Any]] ?? []).compactMap { line -> [String: Any]? in
            guard let n = line["n"] as? Int, !skipping.contains(n) else { return nil }
            return ["n": n, "name": "Line \(n)", "kind": "spend"]
        }
    }

    private let headAnswer: [String: Any] = ["statement": true, "kind": "bank", "account": "HDFC savings 3456", "holder": "ASHA RAO", "currency": "INR"]

    func testAReadingAsksTheHeadThenBatchesThenRepeatsAndCountsAsItGoes() async throws {
        let plan = plan((1...65).map { line("2026-07-01", Double($0), "SHOP \($0)") })
        let tasks = Log()
        let seen = Log()
        let outcome = try await StatementLinePass.read(plan, asking: asking, transport: server { body in
            let task = body["task"] as? String ?? ""
            await_(tasks, task)
            switch task {
            case "head":
                XCTAssertEqual((body["lines"] as? [Any])?.count, StatementLinePass.headLines)
                return self.headAnswer
            case "lines":
                XCTAssertEqual(body["account_hint"] as? String, "HDFC savings 3456")
                XCTAssertEqual(body["holder"] as? String, "ASHA RAO")
                return ["rows": self.rows(for: body)]
            default:
                XCTAssertTrue((body["groups"] as? String ?? "").contains("Line 1 | out"))
                return ["repeats": [["name": "Line 1", "lines": [1], "cycle": "monthly", "custom_days": NSNull(), "category": NSNull(), "ends_on": NSNull(), "reason": "Once."]]]
            }
        }, progress: { state in await_(seen, "\(state.lines)/\(state.batchesDone)/\(state.named)/\(state.finished)") })
        XCTAssertEqual(tasks.entries.filter { $0 == "lines" }.count, 3)
        XCTAssertEqual(tasks.entries.first, "head")
        XCTAssertEqual(tasks.entries.last, "repeats")
        XCTAssertEqual(seen.entries.first, "65/0/0/false", "the count is known before anything is asked")
        XCTAssertEqual(seen.entries.last, "65/3/65/true")
        XCTAssertEqual(outcome.prepared.charges.count, 65)
        XCTAssertEqual(outcome.prepared.holder, "Asha Rao")
        XCTAssertEqual(outcome.prepared.repeats.first?.writtenName, "Line 1 (Guessed)")
        XCTAssertEqual(outcome.report.named, 65)
        XCTAssertEqual(outcome.report.balance, .matches)
        XCTAssertEqual(outcome.report.score, 100)
        XCTAssertEqual(outcome.report.summary(currency: "INR"), "65 lines read on this device · balance matches · every line named")
    }

    func testLinesLeftOutAreAskedOnceMoreThenNamedAsPrintedAndSaidSo() async throws {
        let plan = plan()
        let calls = Log()
        let outcome = try await StatementLinePass.read(plan, asking: asking, transport: server { body in
            switch body["task"] as? String {
            case "head": return self.headAnswer
            case "lines":
                await_(calls, "\((body["lines"] as? [Any])?.count ?? 0)")
                return ["rows": self.rows(for: body, skipping: [2])]
            default: return ["repeats": []]
            }
        })
        XCTAssertEqual(calls.entries, ["3", "1"], "only the line left out is asked again")
        XCTAssertEqual(outcome.prepared.charges.count, 3)
        XCTAssertEqual(outcome.report.missing, [], "every line is there")
        XCTAssertEqual(outcome.report.named, 2)
        XCTAssertEqual(outcome.report.score, 83, "the mean of 2 named of 3 and the balance")
        XCTAssertEqual(outcome.report.summary(currency: "INR"), "3 lines read on this device · balance matches · 2 named, 1 as printed")
        XCTAssertEqual(outcome.prepared.notes, "1 line is named as the statement prints it.")
    }

    func testRepeatsThatFailLeaveTheReadingStanding() async throws {
        let outcome = try await StatementLinePass.read(plan(), asking: asking, transport: server { body in
            switch body["task"] as? String {
            case "head": return self.headAnswer
            case "lines": return ["rows": self.rows(for: body)]
            default: throw StatementCloud.CloudError.server("busy")
            }
        })
        XCTAssertEqual(outcome.prepared.charges.count, 3)
        XCTAssertEqual(outcome.prepared.repeats, [])
    }

    func testARefusalAndASpentShareAreThrownAsTheyCame() async {
        for refusal in [StatementCloud.CloudError.shareSpent, .notStatement("no")] {
            do {
                _ = try await StatementLinePass.read(plan(), asking: asking, transport: { _ in throw refusal })
                XCTFail("refused")
            } catch let error as StatementCloud.CloudError {
                XCTAssertEqual(error.errorDescription, refusal.errorDescription)
            } catch { XCTFail("\(error)") }
        }
    }

    func testAShareSpentOnABatchIsThrownEvenWithSomeNamed() async {
        let plan = plan((1...65).map { line("2026-07-01", Double($0), "SHOP \($0)") })
        do {
            _ = try await StatementLinePass.read(plan, asking: asking, transport: server { body in
                if body["task"] as? String == "head" { return self.headAnswer }
                if (body["lines"] as? [[String: Any]])?.first?["n"] as? Int == 31 { throw StatementCloud.CloudError.shareSpent }
                return ["rows": self.rows(for: body)]
            })
            XCTFail("the share is spent")
        } catch let error as StatementCloud.CloudError {
            XCTAssertEqual(error.errorDescription, StatementCloud.CloudError.shareSpent.errorDescription)
        } catch { XCTFail("\(error)") }
    }

    func testNoBatchComingBackThrowsSoTheFileGoesAsADocument() async {
        do {
            _ = try await StatementLinePass.read(plan(), asking: asking, transport: server { body in
                if body["task"] as? String == "head" { return self.headAnswer }
                throw StatementCloud.CloudError.server("busy")
            })
            XCTFail("nothing was named")
        } catch let error as StatementCloud.CloudError {
            XCTAssertEqual(error.errorDescription, "busy")
        } catch { XCTFail("\(error)") }
    }

    // MARK: the report

    func testTheDocumentPathsReportReadsAsItAlwaysDid() {
        let report = StatementCompleteness.Report(read: 3, expectedCount: 3, missing: [], extra: 0, balance: .matches, peopleNamed: 0, peopleListed: 0, accountsNamed: 0)
        XCTAssertNil(report.named)
        XCTAssertEqual(report.summary(currency: "INR"), "3 of 3 lines · balance matches")
    }

    func testAPastImportReadOnTheDeviceSaysSoAcrossASaveAndALoad() throws {
        var report = StatementCompleteness.Report(read: 3, expectedCount: 3, missing: [], extra: 0, balance: .matches, peopleNamed: 0, peopleListed: 0, accountsNamed: 0)
        report.named = 3
        let record = ImportRecord(file: "a.pdf", date: "2026-10-31", report: report)
        XCTAssertEqual(record.line, "Import Completeness Score: 100% · a.pdf: 3 lines read on this device · balance matches")
        XCTAssertEqual(ImportRecord(raw: record.raw), record)
        report.named = nil
        XCTAssertEqual(ImportRecord(file: "a.pdf", date: "2026-10-31", report: report).line, "Import Completeness Score: 100% · a.pdf: 3 of 3 lines · balance matches")
    }

    func testABanksBareNameWithNoPersonStaysItsOwnAccount() {
        func charge(_ person: String?, _ bank: String) -> StatementCloud.Charge {
            StatementCloud.Charge(date: "2026-07-01", amount: 1, name: "X", narration: "", account: "A", category: nil, kind: "spend", member: nil,
                                  counterpart: person, counterpartKind: person == nil ? nil : "person", counterpartBank: bank)
        }
        let bare = StatementCounterparts.found(in: [charge(nil, "Axis Bank"), charge("Ramesh K", "Axis Bank")], knownAccounts: [], knownPeople: [])
        XCTAssertEqual(bare.accounts.map(\.person), [nil, "Ramesh K"])
        let digits = StatementCounterparts.found(in: [charge(nil, "Axis ••1234"), charge("Ramesh K", "Axis ••1234")], knownAccounts: [], knownPeople: [])
        XCTAssertEqual(digits.accounts.map(\.person), ["Ramesh K"])
    }
}

/// A thread-safe list, for what a fake server and the progress saw.
private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [String] = []
    var entries: [String] { lock.withLock { held } }
    func add(_ entry: String) { lock.withLock { held.append(entry) } }
}

private func await_(_ log: Log, _ entry: String) { log.add(entry) }
