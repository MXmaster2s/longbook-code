// The completeness check: a line the server left out is found and filled from the file, a
// swapped date still answers for its line, the balance adds up or says by how much it
// does not, and the written vault is looked over. Lines here are made up.
import XCTest
@testable import LongbookCore

final class StatementCompletenessTests: XCTestCase {
    private func line(_ date: String, _ amount: Double, _ payee: String = "UPI-SHOP-123456", _ direction: StatementLine.Direction = .debit, page: Int? = nil) -> StatementLine {
        StatementLine(date: date, payee: payee, amount: amount, direction: direction, page: page)
    }

    private func charge(_ date: String, _ amount: Double, kind: String = "spend", member: String? = nil,
                        counterpart: String? = nil, counterpartKind: String? = nil) -> StatementCloud.Charge {
        StatementCloud.Charge(date: date, amount: amount, name: "Shop", narration: "UPI-SHOP-123456", account: "HDFC savings",
                              category: nil, kind: kind, member: member, counterpart: counterpart, counterpartKind: counterpartKind)
    }

    private func prepared(_ charges: [StatementCloud.Charge], members: [StatementCloud.Member] = []) -> StatementCloud.Prepared {
        StatementCloud.Prepared(account: "HDFC savings", charges: charges, repeats: [], members: members, notes: "")
    }

    // MARK: comparing

    func testALineTheServerLeftOutIsMissingAndFilledFromTheFile() {
        let expected = StatementCompleteness.Expected(lines: [
            line("2026-07-01", 649), line("2026-07-03", 1200, "NEFT-RAMESH K-SALARY"), line("2026-07-05", 150_000, "SALARY JUL 2026", .credit),
        ], opening: 10_000, closing: 158_151)
        let read = prepared([charge("2026-07-01", 649), charge("2026-07-05", 150_000, kind: "income")])
        let report = StatementCompleteness.compare(prepared: read, expected: expected)
        XCTAssertEqual(report.read, 2)
        XCTAssertEqual(report.expectedCount, 3)
        XCTAssertEqual(report.missing.map(\.amount), [1200])
        XCTAssertEqual(report.extra, 0)
        XCTAssertEqual(report.balance, .matches, "the balance counts the line the fill will add")
        XCTAssertEqual(report.summary(currency: "INR"), "2 of 3 lines, 1 read from the file · balance matches")

        let filled = StatementCompleteness.fill(missing: report.missing, among: ["salary"], today: "2026-10-30")
        XCTAssertEqual(filled.count, 1)
        XCTAssertTrue(filled[0].keep)
        XCTAssertTrue(filled[0].readLocally)
        XCTAssertNil(filled[0].skipReason)
        XCTAssertEqual(filled[0].name, "Ramesh K Salary")
        XCTAssertEqual(filled[0].tag, "salary")
    }

    func testAFilledCreditIsMoneyInAndAFilledOwnMovementStaysUnticked() {
        let filled = StatementCompleteness.fill(missing: [
            line("2026-07-05", 150_000, "SALARY JUL 2026", .credit),
            line("2026-07-06", 2000, "ATM WDL 4521"),
            line("2027-01-01", 5, "FUTURE"),
        ], among: [], today: "2026-10-30")
        XCTAssertEqual(filled[0].direction, "in")
        XCTAssertTrue(filled[0].keep)
        XCTAssertEqual(filled[1].direction, "transfer")
        XCTAssertTrue(filled[1].keep)
        XCTAssertEqual(filled[1].skipReason, StatementTriage.ownMovement)
        XCTAssertEqual(filled[2].skipReason, StatementTriage.afterToday)
        XCTAssertTrue(filled.allSatisfy(\.readLocally))
    }

    func testADateReadWithDayAndMonthTradedStillAnswersForItsLine() {
        let expected = StatementCompleteness.Expected(lines: [line("2026-05-10", 300), line("2026-05-11", 300)])
        let read = prepared([charge("2026-10-05", 300), charge("2026-05-11", 300)])
        let report = StatementCompleteness.compare(prepared: read, expected: expected)
        XCTAssertTrue(report.missing.isEmpty)
        XCTAssertEqual(report.extra, 0)
        XCTAssertEqual(report.balance, .unknown)
        XCTAssertEqual(report.summary(currency: "INR"), "2 of 2 lines")
    }

    func testTheSameAmountTwiceOnOneDayNeedsTwoCharges() {
        let expected = StatementCompleteness.Expected(lines: [line("2026-07-01", 99), line("2026-07-01", 99)])
        let report = StatementCompleteness.compare(prepared: prepared([charge("2026-07-01", 99)]), expected: expected)
        XCTAssertEqual(report.missing.count, 1)
        let extra = StatementCompleteness.compare(prepared: prepared([charge("2026-07-01", 99), charge("2026-07-02", 5)]),
                                                  expected: StatementCompleteness.Expected(lines: [line("2026-07-01", 99)]))
        XCTAssertEqual(extra.extra, 1)
    }

    func testTheBalanceSaysByHowMuchItIsOff() {
        let expected = StatementCompleteness.Expected(lines: [line("2026-07-01", 100), line("2026-07-02", 47.49, "REVERSAL", .credit)],
                                                      opening: 1000, closing: 947.49)
        let whole = StatementCompleteness.compare(prepared: prepared([charge("2026-07-01", 100), charge("2026-07-02", 47.49, kind: "income")]), expected: expected)
        XCTAssertEqual(whole.balance, .matches)
        // The reversal read as a spend: the file's own column puts it right.
        let misread = prepared([charge("2026-07-01", 100), charge("2026-07-02", 47.49)])
        XCTAssertEqual(StatementCompleteness.mended(misread, expected: expected).charges.map(\.kind), ["spend", "income"])
        // Lines that do not add up to the printed closing balance are said so.
        let short = StatementCompleteness.Expected(lines: expected.lines, opening: 1000, closing: 900)
        let wrong = StatementCompleteness.compare(prepared: misread, expected: short)
        XCTAssertEqual(wrong.balance, .off(by: 47.49))
        XCTAssertEqual(wrong.summary(currency: "INR"), "2 of 2 lines · balance off by ₹47.49")
        // A negative debit from the server counts as money back in.
        let signed = StatementCompleteness.compare(prepared: prepared([charge("2026-07-01", 100), charge("2026-07-02", -47.49)]), expected: expected)
        XCTAssertEqual(signed.balance, .matches)
    }

    func testWithoutTheFilesOwnReadingTheSummarySaysSo() {
        let report = StatementCompleteness.compare(prepared: prepared([charge("2026-07-01", 100)]), expected: nil)
        XCTAssertNil(report.expectedCount)
        XCTAssertEqual(report.summary(currency: "INR"), "Read 1 line · the file's own count could not be checked")
    }

    func testPeopleAndAccountsNamedOnLinesAreCountedOnce() {
        let read = prepared([
            charge("2026-07-01", 100, member: "Anil"), charge("2026-07-02", 100, member: "anil "),
            charge("2026-07-03", 100, counterpart: "Meera", counterpartKind: "person"),
            charge("2026-07-04", 100, counterpart: "Axis card ••4402", counterpartKind: "account"),
            charge("2026-07-05", 100, counterpart: "Axis card ••4402", counterpartKind: "account"),
        ], members: [StatementCloud.Member(name: "Anil", role: "", reason: "")])
        let report = StatementCompleteness.compare(prepared: read, expected: nil)
        XCTAssertEqual(report.peopleNamed, 2)
        XCTAssertEqual(report.peopleListed, 1)
        XCTAssertEqual(report.accountsNamed, 1)
    }

    // MARK: asking again

    func testTheHintNamesTheMissingLinesAndStaysWithinItsLimit() {
        let hint = StatementCompleteness.hint(for: [line("2026-07-01", 649), line("2026-07-03", 1200)])
        XCTAssertEqual(hint, "An earlier reading of this piece left out 2 lines: 2026-07-01 649.00, 2026-07-03 1200.00. Read every line of the piece and answer whole.")
        let many = StatementCompleteness.hint(for: (1...400).map { line("2026-07-01", Double($0)) })
        XCTAssertLessThanOrEqual(many.count, StatementCompleteness.hintLimit)
        XCTAssertTrue(many.hasSuffix("…. Read every line of the piece and answer whole."))
    }

    func testMissingLinesGoBackToThePieceTheirPageIsIn() {
        let by = StatementCompleteness.piecesToAskAgain(missing: [line("2026-07-01", 1, page: 2), line("2026-07-02", 2, page: 7), line("2026-07-03", 3)],
                                                        pieces: 3, pagesPerPiece: 3)
        XCTAssertEqual(by[0]?.map(\.amount), [1, 3])
        XCTAssertEqual(by[1]?.map(\.amount), [3])
        XCTAssertEqual(by[2]?.map(\.amount), [2, 3])
        XCTAssertEqual(StatementCompleteness.piecesToAskAgain(missing: [line("2026-07-01", 1, page: 40)], pieces: 2)[1]?.count, 1, "a page past the last piece lands in it")
    }

    func testASecondReadingAddsOnlyTheLinesTheFirstLeftOut() {
        let first = StatementCloud.ChargesAnswer(account: "HDFC savings", charges: [charge("2026-07-01", 649)], notes: "", closingBalance: nil, closingBalanceDate: nil, currency: "INR")
        let second = StatementCloud.ChargesAnswer(account: "HDFC savings", charges: [charge("2026-07-01", 649), charge("2026-07-03", 1200), charge("2026-07-09", 5)],
                                                  notes: "", closingBalance: 500, closingBalanceDate: "2026-07-31", currency: "INR")
        let merged = StatementCompleteness.merge(first, with: second, missing: [line("2026-07-03", 1200)])
        XCTAssertEqual(merged.charges.map(\.amount), [649, 1200])
        XCTAssertEqual(merged.closingBalance, 500)
    }

    // MARK: the file's own totals

    func testPrintedBalancesAreReadFromTheSummaryRowUnderTheirLabels() {
        func word(_ text: String, _ x: Double, _ y: Double) -> StatementWord {
            StatementWord(text: text, minX: x, maxX: x + Double(text.count) * 5, minY: y, maxY: y + 8)
        }
        let rows = [
            StatementRow(words: [word("Date", 10, 700), word("Narration", 60, 700), word("Withdrawal", 300, 700), word("Deposit", 380, 700), word("Closing", 450, 700), word("Balance", 490, 700)], page: 1),
            StatementRow(words: [word("01/07/2026", 10, 680), word("SHOP", 60, 680), word("100.00", 320, 680), word("900.00", 480, 680)], page: 1),
            StatementRow(words: [word("02/07/2026", 10, 660), word("SALARY", 60, 660), word("50.00", 400, 660), word("950.00", 480, 660)], page: 1),
            StatementRow(words: [word("Opening", 10, 600), word("Balance", 50, 600), word("Debits", 200, 600), word("Credits", 300, 600), word("Closing", 400, 600), word("Balance", 440, 600)], page: 1),
            StatementRow(words: [word("1,000.00", 20, 585), word("100.00", 210, 585), word("50.00", 310, 585), word("950.00", 420, 585)], page: 1),
        ]
        let reading = StatementText.Reading(lines: StatementLines.fromColumns(rows), rows: rows, records: [])
        let expected = StatementCompleteness.expected(from: reading)
        XCTAssertEqual(expected.count, 2)
        XCTAssertEqual(expected.lines.map(\.page), [1, 1])
        XCTAssertEqual(expected.opening, 1000)
        XCTAssertEqual(expected.closing, 950)
        XCTAssertEqual(expected.debits, 100)
        XCTAssertEqual(expected.credits, 50)
    }

    func testWithoutASummaryTheRunningBalanceColumnOpensAndClosesTheStatement() {
        func word(_ text: String, _ x: Double, _ y: Double) -> StatementWord {
            StatementWord(text: text, minX: x, maxX: x + Double(text.count) * 5, minY: y, maxY: y + 8)
        }
        let rows = [
            StatementRow(words: [word("01/07/2026", 10, 680), word("SHOP", 60, 680), word("100.00", 320, 680), word("900.00", 480, 680)], page: 1),
            StatementRow(words: [word("02/07/2026", 10, 660), word("SALARY", 60, 660), word("50.00", 400, 660), word("950.00", 480, 660)], page: 1),
        ]
        let reading = StatementText.Reading(lines: StatementLines.fromColumns(rows), rows: rows, records: [])
        let expected = StatementCompleteness.expected(from: reading)
        XCTAssertEqual(expected.opening, 1000)
        XCTAssertEqual(expected.closing, 950)
    }

    func testASheetPrintsItsBalancesInCells() {
        let records: [[String]] = [
            ["Opening Balance", "1,000.00"], ["Closing Balance:", "", "950.00"],
            ["Date", "Narration", "Withdrawal", "Deposit"], ["01/07/2026", "SHOP", "100.00", ""],
        ]
        let reading = StatementText.Reading(lines: StatementLines.fromRecords(records), rows: [], records: records)
        let expected = StatementCompleteness.expected(from: reading)
        XCTAssertEqual(expected.opening, 1000)
        XCTAssertEqual(expected.closing, 950)
    }

    func testANegativeWithdrawalIsAReversalComingBackIn() {
        let lines = StatementLines.fromRecords([
            ["Date", "Narration", "Withdrawal", "Deposit"],
            ["01/07/2026", "SHOP", "47.49", ""],
            ["02/07/2026", "SHOP REVERSAL", "-47.49", ""],
        ])
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit])
        XCTAssertEqual(lines.map(\.amount), [47.49, 47.49])
    }

    // MARK: after the Add

    func testTheWrittenVaultIsLookedOverByKindAndCountOnly() {
        let vault: [String: Any] = [
            "commitments": [
                ["id": "c1", "name": "Shop", "billing_cycle": "once", "notes": "Statement line: UPI-SHOP"],
                ["id": "c2", "name": "Shop ₹649", "billing_cycle": "once", "details": ["counterpart_account_id": "a9"]],
                ["id": "c3", "name": "Rent (Guessed)", "billing_cycle": "monthly", "notes": "From the statement", "member_id": "m9"],
                ["id": "c4", "name": "Rent", "billing_cycle": "monthly", "notes": "Guessed: the rhythm says monthly"],
                ["id": "c5", "name": "Old row", "billing_cycle": "once"],
            ],
            "charges": [["commitment_id": "c2", "note": "paid"]],
            "accounts": [["id": "a1", "name": "HDFC savings ••4417", "member_id": "m1"], ["id": "a2", "name": "Card [old]", "member_id": "m9"]],
            "members": [["id": "m1", "name": "Anil"], ["id": "m2", "name": "Meera 1,500"]],
        ]
        let findings = StatementCompleteness.check(vault: vault, importedIds: ["c1", "c2", "c3", "c4"])
        let by = Dictionary(uniqueKeysWithValues: findings.map { ($0.kind, $0.count) })
        XCTAssertEqual(by["note_missing"], 1, "c2 has no statement line; c5 was not imported")
        XCTAssertEqual(by["counterpart_unknown"], 1)
        XCTAssertEqual(by["guessed_mismatch"], 2)
        XCTAssertEqual(by["commitment_name_untidy"], 1)
        XCTAssertEqual(by["account_name_untidy"], 1)
        XCTAssertEqual(by["member_name_untidy"], 1)
        XCTAssertEqual(by["member_unknown"], 2)
        XCTAssertTrue(StatementCompleteness.check(vault: ["commitments": [["id": "c1", "name": "Shop", "billing_cycle": "once"]], "charges": [["commitment_id": "c1", "note": "Statement line: UPI-SHOP"]]], importedIds: ["c1"]).isEmpty,
                      "the charge's own note counts too")
    }

    // MARK: real statements, when they are on this Mac

    /// Two statements read on the device: how many lines each holds and what it prints as
    /// its balances, against a hand count. Only counts are asserted; nothing is printed.
    func testTheDevicesReadingOfRealStatementsMatchesTheHandCount() throws {
        let folder = "/private/tmp/claude-502/-Users-rohit-personal-Library-Mobile-Documents-iCloud-md-obsidian-Documents/79c1e72e-90f2-4cf6-8b7f-1042e0271bd8/scratchpad/fm/unlocked/"
        let truth: [(file: String, count: Int, opening: Double, closing: Double)] = [
            ("4542.pdf", 134, 56_347.67, 81_544.68), ("7191.pdf", 137, 969_211.07, 307_733.79),
        ]
        for statement in truth {
            let url = URL(fileURLWithPath: folder + statement.file)
            guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("\(statement.file) is not on this Mac") }
            let expected = try XCTUnwrap(StatementCompleteness.expected(for: url, password: nil))
            XCTAssertEqual(expected.count, statement.count)
            XCTAssertEqual(expected.opening, statement.opening)
            XCTAssertEqual(expected.closing, statement.closing)
            let closes = ((statement.opening + expected.credits - expected.debits) * 100).rounded() / 100
            XCTAssertEqual(closes, statement.closing, "the lines read add up to the printed closing balance")
            XCTAssertTrue(expected.lines.allSatisfy { ($0.page ?? 0) > 0 }, "every line knows its page")
        }
    }
}
