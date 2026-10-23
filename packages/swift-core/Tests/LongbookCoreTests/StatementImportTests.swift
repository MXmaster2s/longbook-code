// A statement read on the device: the lines it proves, the ones the method skips, the
// names an owner would say, the rhythms worth asking about, and the one proposal that
// lands in Changes. Nothing here needs a model; the model only improves the names.
import XCTest
@testable import LongbookCore
#if os(macOS)
import AppKit
import PDFKit
#endif

final class StatementImportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    // MARK: CSV

    func testHDFCShapedCSVYieldsDatedLinesWithDirection() {
        let csv = """
        Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
        01/07/26,UPI-NETFLIX.COM-NETFLIX@AXISB-UTIB0000114-123456789012-PAYMENT,0000123456789012,01/07/26,649.00,,"12,345.50"
        05/07/26,SALARY JUL 2026,,05/07/26,,"1,50,000.00","1,62,345.50"
        """
        let lines = StatementLines.fromCSV(csv)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].date, "2026-07-01")
        XCTAssertEqual(lines[0].amount, 649)
        XCTAssertEqual(lines[0].direction, .debit)
        XCTAssertEqual(lines[1].date, "2026-07-05")
        XCTAssertEqual(lines[1].amount, 150_000, "Indian grouping reads as one number")
        XCTAssertEqual(lines[1].direction, .credit)
    }

    func testSBIShapedCSVWithDebitCreditColumnsAndMonthNames() {
        let csv = """
        Txn Date,Value Date,Description,Ref No./Cheque No.,Debit,Credit,Balance
        "15 Mar 2026","15 Mar 2026","HDFC ERGO HEALTH PREMIUM","",18450.00,,40000.00
        "20 Mar 2026","20 Mar 2026","ATM WDL 4521","",2000.00,,38000.00
        """
        let lines = StatementLines.fromCSV(csv)
        XCTAssertEqual(lines.map(\.date), ["2026-03-15", "2026-03-20"])
        XCTAssertEqual(lines.map(\.amount), [18450, 2000])
    }

    func testAmountWithTypeColumnReadsDrCr() {
        let csv = """
        Transaction Date,Description,Amount,Type
        2026-06-03,GODADDY.COM,3597,DR
        2026-06-04,REFUND AMAZON,499,CR
        """
        let lines = StatementLines.fromCSV(csv)
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit])
    }

    func testDatesTradedDayForMonthAreMendedByTheDeclaredPeriod() {
        // One bank's sheet: a July period declared above the table, and day counts that
        // read as 7 January, 7 August... until day and month trade places.
        let records: [[String]] = [
            ["Account Statement"],
            ["Period", "From 01/07/2026 To 31/07/2026"],
            ["Sl. No.", "Transaction Date", "Value Date", "Description", "Chq /Ref No.", "Amount", "Dr / Cr", "Balance", "Dr / Cr"],
            ["1", "46029.37644675", "46029", "UPI/SWIGGY INSTAMA/UTIB/6549", "UPI-618374084287", "244", "DR", "70335", "CR"],
            ["2", "46241.5", "46241", "UPI/SPOTIFY INDIA", "UPI-618374084288", "119", "DR", "70216", "CR"],
            ["3", "46060.72675925", "46060", "SentIMPS618212424069", "IMPS-618212262015", "20000", "CR", "90216", "CR"],
        ]
        let lines = StatementLines.fromRecords(records)
        XCTAssertEqual(lines.map(\.date), ["2026-07-01", "2026-07-08", "2026-07-02"])
        XCTAssertEqual(lines.map(\.direction), [.debit, .debit, .credit], "the first Dr/Cr column is the charge's; the second is the balance's")
        XCTAssertEqual(lines.map(\.amount), [244, 119, 20000])
    }

    func testCSVWithoutARecognisableHeaderYieldsNothing() {
        XCTAssertTrue(StatementLines.fromCSV("a,b,c\n1,2,3\n").isEmpty)
    }

    // MARK: PDF text

    func testTextLinesReadDirectionFromTheRunningBalance() {
        let text = """
        HDFC Bank  Statement of account  01/07/2026 to 31/07/2026
        Date       Narration                    Withdrawal   Deposit   Balance
        01/07/2026 NETFLIX.COM                  649.00                 12,345.50
        05/07/2026 SALARY JUL 2026              1,50,000.00            1,62,345.50
        06/07/2026 UPI-RAMESH K-cook            6,000.00               1,56,345.50
        Page 1 of 3
        """
        let lines = StatementLines.fromText(text)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].direction, .debit, "the first line has no earlier balance; a lone amount is a spend")
        XCTAssertEqual(lines[1].direction, .credit, "the balance rose")
        XCTAssertEqual(lines[2].direction, .debit, "the balance fell")
        XCTAssertEqual(lines[2].amount, 6000)
        XCTAssertEqual(lines[2].payee, "UPI-RAMESH K-cook")
    }

    func testCardStatementTextMarksCreditsWithCr() {
        let text = """
        12/01/2026  STAR HEALTH PREMIUM        9,200.00
        14/01/2026  PAYMENT RECEIVED THANK YOU 9,200.00 Cr
        """
        let lines = StatementLines.fromText(text)
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit])
    }

    // MARK: triage

    func testTheWordsAPayeeUsesPlaceItWithoutAModel() {
        let among = ["rent", "streaming", "telecom", "insurance", "emi", "salary", "home", "travel", "ai"]
        XCTAssertEqual(StatementCategory.known("Netflix Subscription", among: among), "streaming")
        XCTAssertEqual(StatementCategory.known("Hdfc Ergo Health Premium", among: among), "insurance")
        XCTAssertEqual(StatementCategory.known("House Rent Mehta Properties", among: among), "rent")
        XCTAssertEqual(StatementCategory.known("Hdfc Bank Emi", among: among), "emi")
        XCTAssertEqual(StatementCategory.known("Greenwood Society Maint", among: among), "home")
        XCTAssertEqual(StatementCategory.known("Sunita D Cook Salary", among: among), "salary")
        XCTAssertEqual(StatementCategory.known("Irctc Web Booking", among: among), "travel")
        XCTAssertNil(StatementCategory.known("Some Shop", among: among), "a name that says nothing is left for the model")
        XCTAssertNil(StatementCategory.known("Netflix", among: ["rent"]), "a category the vault does not carry is never invented")
    }

    func testASalaryPaidOutIsNotMoneyIn() {
        func verdict(_ payee: String) -> StatementTriage.Verdict {
            StatementTriage.verdict(StatementLine(date: "2026-07-01", payee: payee, amount: 100, direction: .debit))
        }
        XCTAssertEqual(verdict("UPI-SUNITA D-cook salary"), .keep, "paying the cook is money out")
        XCTAssertEqual(verdict("SALARY CREDIT - VERTEX LABS"), .skip("money in"))
        XCTAssertEqual(verdict("REFUND AMAZON"), .skip("money in"))
    }

    func testCreditsAndOwnMovementsAreSkippedWithAReason() {
        func verdict(_ payee: String, _ direction: StatementLine.Direction = .debit) -> StatementTriage.Verdict {
            StatementTriage.verdict(StatementLine(date: "2026-07-01", payee: payee, amount: 100, direction: direction))
        }
        XCTAssertEqual(verdict("SALARY", .credit), .skip("money in"))
        XCTAssertEqual(verdict("ATM WDL 4521"), .skip("your own money moved"))
        XCTAssertEqual(verdict("CREDIT CARD PAYMENT HDFC"), .skip("your own money moved"))
        XCTAssertEqual(verdict("PAYTM WALLET TOPUP"), .skip("your own money moved"))
        XCTAssertEqual(verdict("NETFLIX.COM"), .keep)
        XCTAssertEqual(verdict("UPI-RAMESH K-cook"), .keep)
    }

    // MARK: names

    func testPlainNamesDropBankNoiseAndNumbers() {
        XCTAssertEqual(StatementNaming.plainName("UPI-NETFLIX.COM-NETFLIX@AXISB-UTIB0000114-123456789012-PAYMENT"), "Netflix")
        XCTAssertEqual(StatementNaming.plainName("POS 4521XXXXXXXX1007 AMAZON PAY INDIA"), "Amazon Pay India")
        XCTAssertEqual(StatementNaming.plainName("HDFC ERGO HEALTH PREMIUM"), "Hdfc Ergo Health Premium")
        XCTAssertEqual(StatementNaming.plainName("UPI-RAMESH K-cook"), "Ramesh K Cook")
        XCTAssertEqual(StatementNaming.plainName("ACH D- HDFC BANK EMI 884211"), "Hdfc Bank Emi")
    }

    func testScrubbedNarrationKeepsNoLongNumbers() {
        XCTAssertEqual(StatementNaming.scrubbed("POS 4521XXXXXXXX1007 AMAZON REF 123456789012"), "POS AMAZON REF")
    }

    // MARK: repeats

    func testMonthlyAndYearlyRhythmsAreSpotted() {
        var candidates: [StatementCandidate] = []
        for month in 1...12 {
            candidates.append(candidate("Netflix", String(format: "2026-%02d-01", month), 649))
        }
        candidates.append(candidate("Star Health", "2026-01-12", 9200))
        candidates.append(candidate("Star Health", "2026-07-12", 9200))
        candidates.append(candidate("Hdfc Ergo", "2025-03-15", 18450))
        candidates.append(candidate("Hdfc Ergo", "2026-03-15", 18450))
        candidates.append(candidate("Irctc", "2026-06-10", 4560))

        let repeats = StatementImport.repeats(in: candidates)
        XCTAssertEqual(repeats.map(\.name), ["Netflix", "Star Health", "Hdfc Ergo"])
        XCTAssertEqual(repeats[0].cycle, .monthly)
        XCTAssertEqual(repeats[0].dates.count, 12)
        XCTAssertEqual(repeats[1].cycle, .custom)
        XCTAssertEqual(repeats[1].customDays, 183)
        XCTAssertEqual(repeats[2].cycle, .yearly)
    }

    // MARK: the proposal

    func testProposalLandsPaidStatementRowsSignedAsTheImport() throws {
        let kept = [
            candidate("Netflix", "2026-07-01", 649, payee: "UPI-NETFLIX.COM-123456789012", tag: "streaming"),
            candidate("Irctc", "2026-06-10", 4560),
        ]
        var skipped = candidate("Salary", "2026-07-05", 150_000)
        skipped.keep = false
        let write = StatementImport.proposal(kept + [skipped], account: "HDFC savings", currency: "INR", source: "documents/hdfc-2026.csv")
        XCTAssertEqual(write.kind, "add_commitments")
        XCTAssertEqual(write.author, "statement import")
        XCTAssertEqual((write.payload["rows"] as? [[String: Any]])?.count, 2, "a skipped line is never written")

        let raw = try seededVault()
        guard case .vault(let next) = try PendingApply.apply(write, to: raw, now: now) else { return XCTFail("not a vault") }
        let rows = try XCTUnwrap(next["commitments"] as? [[String: Any]])
        let netflix = try XCTUnwrap(rows.first { $0["name"] as? String == "Netflix" })
        XCTAssertEqual(netflix["billing_cycle"] as? String, "once")
        let id = try XCTUnwrap(netflix["id"] as? String)
        let charges = (next["charges"] as? [[String: Any]] ?? []).filter { $0["commitment_id"] as? String == id }
        XCTAssertEqual(charges.count, 1)
        XCTAssertEqual(charges[0]["paid"] as? Bool, true)
        XCTAssertEqual(charges[0]["basis"] as? String, "statement")
        XCTAssertEqual(charges[0]["date"] as? String, "2026-07-01")
        let provenance = try XCTUnwrap((next["_provenance"] as? [String: Any])?[id] as? [String: Any])
        XCTAssertEqual(provenance["edited_by"] as? String, "statement import")
        XCTAssertEqual(provenance["source"] as? String, "documents/hdfc-2026.csv")
        let accounts = try XCTUnwrap(next["accounts"] as? [[String: Any]])
        XCTAssertNotNil(accounts.first { $0["name"] as? String == "HDFC savings" }, "the statement is the account")
        let details = try XCTUnwrap(netflix["details"] as? [String: Any])
        XCTAssertEqual(details["statement_line"] as? String, "UPI-NETFLIX.COM", "the narration rides along, scrubbed of its numbers")
    }

    func testAStatementReadTwiceWritesNothingTwice() {
        let line = StatementLine(date: "2026-07-01", payee: "UPI/NETFLIX.COM/6492001/subscription", amount: 649, direction: .debit)
        let twin = StatementLine(date: "2026-07-01", payee: "UPI/NETFLIX.COM/6492001/subscription", amount: 649, direction: .debit)
        let other = StatementLine(date: "2026-07-03", payee: "SWIGGY", amount: 300, direction: .debit)
        var candidates = StatementImport.candidates(from: [line, twin, other], file: "july.pdf")
            + StatementImport.candidates(from: [line], file: "july-again.pdf")
        let inTheBook = Set([StatementImport.key(date: "2026-07-03", amount: 300, narration: "SWIGGY")])
        StatementImport.markAlreadyPresent(&candidates, in: inTheBook)
        XCTAssertEqual(candidates.map(\.keep), [true, true, false, false])
        XCTAssertEqual(candidates[2].skipReason, "already in your longbook")
        XCTAssertEqual(candidates[3].skipReason, "already in july.pdf", "the same file picked twice writes once")
        XCTAssertNil(candidates[1].skipReason, "two identical charges on one day in one statement are two charges")
    }

    func testATransferKeptOnceIsNotOfferedAgain() {
        let bill = StatementLine(date: "2026-07-20", payee: "CREDIT CARD PAYMENT CORAL 5521", amount: 31250, direction: .debit)
        let cash = StatementLine(date: "2026-07-15", payee: "ATM WDL SELF", amount: 10000, direction: .debit)
        var first = StatementImport.candidates(from: [bill, cash], file: "july.pdf")
        StatementImport.markAlreadyPresent(&first, in: [])
        XCTAssertEqual(first.map(\.isOpenTransfer), [true, true], "unticked, and the owner's to keep")

        // The owner kept the card bill; the book now holds it under the statement's own line.
        let inTheBook = Set([StatementImport.key(date: bill.date, amount: bill.amount, narration: StatementNaming.scrubbed(bill.payee))])
        var again = StatementImport.candidates(from: [bill, cash], file: "july.pdf")
            + StatementImport.candidates(from: [cash], file: "july-again.pdf")
        StatementImport.markAlreadyPresent(&again, in: inTheBook)
        XCTAssertEqual(again.map(\.keep), [false, false, false])
        XCTAssertEqual(again.map(\.skipReason), ["already in your longbook", "your own money moved", "already in july.pdf"])
        XCTAssertEqual(again.map(\.isTransfer), [true, true, true], "still marked as what it is")
        XCTAssertEqual(again.map(\.isOpenTransfer), [false, true, false], "only the one never kept can be ticked in")
    }

    func testAnOwnMovementDatedAfterTodayIsRefusedLikeAnyOtherLine() {
        func charge(_ date: String, _ name: String, _ kind: String) -> StatementCloud.Charge {
            .init(date: date, amount: 5000, name: name, narration: name, account: "Meridian savings", category: nil, kind: kind, member: nil)
        }
        // Days past the twelfth, so no date can be read the other way round and mended.
        let prepared = StatementCloud.Prepared.assemble([.init(account: "Meridian savings", charges: [
            charge("2026-07-20", "To savings", "own_transfer"),
            charge("2026-07-22", "To savings", "own_transfer"),
            charge("2026-07-22", "Coral card bill", "card_bill"),
            charge("2026-07-22", "Gym", "spend"),
            charge("2026-07-22", "Bonus", "income"),
        ], notes: "")], review: .empty, today: "2026-07-21")
        let candidates = prepared.candidates(among: [], today: "2026-07-21")
        let refused = "dated after today — a statement proves the past"
        XCTAssertEqual(candidates.map(\.skipReason), ["your own money moved", refused, refused, refused, refused])
        XCTAssertEqual(candidates.map(\.keep), [false, false, false, false, false])
        XCTAssertEqual(candidates.map(\.isTransfer), [true, true, true, false, false])
        XCTAssertEqual(candidates.map(\.isOpenTransfer), [true, false, false, false, false],
                       "a movement dated tomorrow proves nothing, so it cannot be ticked in")
    }

    func testEachFileLandsOnItsOwnAccount() throws {
        let candidates = StatementImport.candidates(from: [StatementLine(date: "2026-07-01", payee: "NETFLIX", amount: 649, direction: .debit)], file: "hdfc.pdf")
            + StatementImport.candidates(from: [StatementLine(date: "2026-07-02", payee: "SWIGGY", amount: 300, direction: .debit)], file: "axis.xls")
        let write = StatementImport.proposal(candidates, accounts: ["hdfc.pdf": "HDFC savings", "axis.xls": "Axis card 4402"], currency: "INR", source: "documents/hdfc.pdf, documents/axis.xls")
        let rows = try XCTUnwrap(write.payload["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["account"] as? String }, ["HDFC savings", "Axis card 4402"])
    }

    func testTheServersAnswersBecomeTheReview() throws {
        // The two shapes the statement-extract function answers in: a piece's charges,
        // then the year's look-over.
        let piece = """
        {"account":"HDFC savings 4417",
         "charges":[
          {"date":"2026-07-01","amount":649,"name":"Netflix","narration":"UPI/NETFLIX.COM/subscription","account":"HDFC savings 4417","category":"streaming","kind":"spend","member":null},
          {"date":"2026-07-01","amount":9000,"name":"Sunita (cook)","narration":"UPI/SUNITA D/cook salary","account":"","category":"salary","kind":"for_member","member":"Sunita"},
          {"date":"2026-07-05","amount":214000,"name":"Salary","narration":"SALARY CREDIT VERTEX LABS","account":"HDFC savings 4417","category":null,"kind":"income","member":null},
          {"date":"2026-07-20","amount":38000,"name":"Axis card bill","narration":"CREDIT CARD PAYMENT AXIS","account":"HDFC savings 4417","category":null,"kind":"card_bill","member":null},
          {"date":"2026-07-15","amount":10000,"name":"Cash","narration":"ATM WDL SELF","account":"HDFC savings 4417","category":null,"kind":"own_transfer","member":null},
          {"date":"2026-99-01","amount":5,"name":"Broken","narration":"x","account":"HDFC savings 4417","category":null,"kind":"spend","member":null}
         ],
         "notes":"One line unplaced."}
        """
        let review = """
        {"repeats":[{"name":"Netflix","cycle":"monthly","custom_days":null,"amount":649,"dates":["2026-07-01"],"category":"streaming","ends_on":null}],
         "members":[{"name":"Sunita","role":"cook","reason":"paid 9,000 on the 1st"}],
         "notes":""}
        """
        let answer = try JSONDecoder().decode(StatementCloud.ChargesAnswer.self, from: Data(piece.utf8))
        let looked = try JSONDecoder().decode(StatementCloud.ReviewAnswer.self, from: Data(review.utf8))
        let prepared = StatementCloud.Prepared.assemble([answer], review: looked)
        XCTAssertEqual(prepared.account, "HDFC savings 4417")
        XCTAssertEqual(prepared.repeats.first?.cycle, "monthly")
        XCTAssertEqual(prepared.members.first?.role, "cook")
        XCTAssertEqual(prepared.notes, "One line unplaced.")
        XCTAssertTrue(prepared.chargeLines.contains("2026-07-01 | 649.0 | Netflix | UPI/NETFLIX.COM/subscription | spend"))

        let candidates = prepared.candidates(among: ["streaming", "salary"])
        XCTAssertEqual(candidates.count, 5, "a line with no real date is dropped, never written")
        XCTAssertEqual(candidates.map(\.keep), [true, true, true, false, false])
        XCTAssertEqual(candidates.map(\.skipReason), [nil, nil, nil, "a card bill — its charges are on the card's statement", "your own money moved"])
        XCTAssertEqual(candidates.map(\.isIncome), [false, false, true, false, false], "money in is kept, and marked as such")
        XCTAssertEqual(candidates[1].member, "Sunita")
        XCTAssertEqual(candidates[0].tag, "streaming")
        XCTAssertEqual(candidates[0].file, "HDFC savings 4417", "the account rides in the file slot")

        let write = StatementImport.proposal(candidates, accounts: [:], currency: "INR", source: "documents/hdfc-july.pdf")
        let rows = try XCTUnwrap(write.payload["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 3, "the two charges and the money in")
        XCTAssertEqual(rows[0]["account"] as? String, "HDFC savings 4417")
        XCTAssertEqual(rows[1]["member"] as? String, "Sunita")
        XCTAssertEqual(rows[1]["tag"] as? String, "salary")
        XCTAssertEqual(rows[2]["direction"] as? String, "in", "money in is written as such")
        XCTAssertNil(rows[0]["direction"])

        // The owner's own movements stay unticked; one ticked back in is a transfer, never spending.
        XCTAssertEqual(candidates.map(\.isTransfer), [false, false, false, true, true])
        var remembered = candidates
        remembered[3].keep = true
        let kept = try XCTUnwrap(StatementImport.proposal(remembered, accounts: [:], currency: "INR", source: "documents/hdfc-july.pdf").payload["rows"] as? [[String: Any]])
        XCTAssertEqual(kept.first { $0["name"] as? String == "Axis card bill" }?["direction"] as? String, "transfer")
        let local = StatementImport.candidates(from: [
            StatementLine(date: "2026-07-15", payee: "ATM WDL SELF", amount: 10000, direction: .debit),
            StatementLine(date: "2026-07-05", payee: "SALARY CREDIT VERTEX LABS", amount: 214000, direction: .credit),
        ])
        XCTAssertEqual(local.map(\.keep), [false, false])
        XCTAssertEqual(local.map(\.direction), ["transfer", nil], "read on the device, a movement is marked the same way")
    }

    func testADateReadMonthFirstIsTurnedBack() {
        func charge(_ date: String, _ name: String) -> StatementCloud.Charge {
            .init(date: date, amount: 100, name: name, narration: name, account: "A", category: nil, kind: "spend", member: nil)
        }
        // A May statement: the model read 05/10 as October and 12/05 as December; the
        // lines run in order, so both go back to May. A genuine June line stays.
        let read = [charge("2026-05-02", "Swiggy"), charge("2026-10-05", "CRED Club"), charge("2026-05-08", "Netflix"),
                    charge("2026-12-05", "Suryoday"), charge("2026-06-01", "Rent"), charge("2026-11-30", "Nowhere")]
        let mended = StatementCloud.Prepared.mendDates(read, today: "2026-09-13")
        XCTAssertEqual(mended.map(\.date), ["2026-05-02", "2026-05-10", "2026-05-08", "2026-05-12", "2026-06-01", "2026-11-30"],
                       "a date after today, or one leaping out of order, reads day first; one nothing can mend is left as it came")

        let prepared = StatementCloud.Prepared.assemble([.init(account: "A", charges: read, notes: "")], review: .empty, today: "2026-09-13")
        let candidates = prepared.candidates(among: [], today: "2026-09-13")
        XCTAssertEqual(candidates.map(\.keep), [true, true, true, true, true, false])
        XCTAssertEqual(candidates[5].skipReason, "dated after today — a statement proves the past")
    }

    func testTheStatementSaysItsCurrency() throws {
        let decoded = try JSONDecoder().decode(StatementCloud.ChargesAnswer.self, from: Data(
            #"{"account":"HSBC UK 0009","currency":"gbp","charges":[],"notes":"","closing_balance":null,"closing_balance_date":null}"#.utf8))
        XCTAssertEqual(decoded.currency, "gbp")
        let pieces: [StatementCloud.ChargesAnswer] = [
            .init(account: "A", charges: [], notes: "", currency: "gbp"),
            .init(account: "A", charges: [], notes: "", currency: "INR"),
            .init(account: "A", charges: [], notes: "", currency: "GBP"),
            .init(account: "A", charges: [], notes: "", currency: nil),
        ]
        XCTAssertEqual(StatementCloud.Prepared.assemble(pieces, review: .empty).currency, "GBP", "most pieces win, in capitals")
        XCTAssertNil(StatementCloud.Prepared.assemble([.init(account: "A", charges: [], notes: "")], review: .empty).currency)
    }

    func testASheetSaysWhichOfItsNumbersIsTheDay() {
        let dayFirst: [[String]] = [["Date", "Narration"], ["05/10/2026", "A"], ["31/12/2025", "B"]]
        XCTAssertEqual(StatementLines.dateOrder(dayFirst), .dayFirst, "a 31 in front can only be a day")
        let monthFirst: [[String]] = [["Date", "Narration"], ["05/10/2026", "A"], ["12/31/2025", "B"]]
        XCTAssertEqual(StatementLines.dateOrder(monthFirst), .monthFirst, "a 31 behind can only be a day")
        let silent: [[String]] = [["Date", "Narration"], ["05/10/2026", "A"], ["01/02/2026", "B"]]
        XCTAssertEqual(StatementLines.dateOrder(silent), .dayFirst, "a sheet that never shows its hand reads as banks here print")

        XCTAssertEqual(StatementLines.parseDate("05/10/2026", order: .monthFirst), "2026-05-10")
        XCTAssertEqual(StatementLines.parseDate("05/10/2026", order: .dayFirst), "2026-10-05")
        XCTAssertEqual(StatementLines.parseDate("2026-07-01", order: .monthFirst), "2026-07-01", "an unambiguous date reads the same either way")

        let pieces = StatementCloud.rowPieces(monthFirst, name: "us-bank.csv")
        XCTAssertTrue(pieces[0].data.contains("\"2026-05-10\",\"A\""), "the order found in the sheet is the order every cell is read in")
        XCTAssertTrue(pieces[0].data.contains("\"2025-12-31\",\"B\""))
    }

    func testAYearOfRowsGoesUpInPiecesEachUnderItsHeader() {
        var records: [[String]] = [["Account Statement"], ["Period", "From 01/09/2025 To 31/08/2026"],
                                   ["Txn Date", "Description", "Debit", "Credit", "Balance"]]
        for row in 1...527 { records.append(["01/07/2026", "LINE \(row)", "\(row)", "", "1000"]) }
        let pieces = StatementCloud.rowPieces(records, name: "year.xls")
        XCTAssertEqual(pieces.count, 4, "527 rows in runs of 150")
        XCTAssertEqual(pieces.map(\.label), ["rows 1–150 of 527", "rows 151–300 of 527", "rows 301–450 of 527", "rows 451–527 of 527"])
        for piece in pieces {
            XCTAssertTrue(piece.data.hasPrefix("\"Account Statement\"\n\"Period\""), "every piece carries the header rows above its own")
            XCTAssertTrue(piece.data.contains("\"Txn Date\",\"Description\""))
        }
        XCTAssertTrue(pieces[3].data.contains("\"LINE 527\""))
        XCTAssertFalse(pieces[0].data.contains("\"LINE 151\""))
        XCTAssertTrue(pieces[0].data.contains("\"2026-07-01\",\"LINE 1\""), "a printed date goes up as its day, read day-first, so nothing is left to guess")
        XCTAssertTrue(pieces[0].data.contains("\"From 01/09/2025 To 31/08/2026\""), "a sentence with dates in it is not a date cell")

        let small = StatementCloud.rowPieces(Array(records.prefix(20)), name: "month.xls")
        XCTAssertEqual(small.map(\.label), ["17 rows"], "a short sheet goes whole")
    }

    #if os(macOS)
    func testALongPDFGoesUpAFewPagesAtATime() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let one = try XCTUnwrap(PDFDocument(data: pdf(lines: ["12/01/2026  STAR HEALTH PREMIUM  9,200.00"])))
        let long = PDFDocument()
        for _ in 0..<7 { if let page = one.page(at: 0) { long.insert(page, at: long.pageCount) } }
        let file = dir.appendingPathComponent("seven.pdf")
        XCTAssertTrue(long.write(to: file))

        let pieces = try StatementCloud.pdfPieces(file, name: "seven.pdf", password: nil)
        XCTAssertEqual(pieces.map(\.label), ["pages 1–3 of 7", "pages 4–6 of 7", "page 7 of 7"])
        for piece in pieces {
            let opened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(Data(base64Encoded: piece.data))))
            XCTAssertFalse(opened.isEncrypted)
            XCTAssertTrue(opened.page(at: 0)?.string?.contains("STAR HEALTH") == true)
        }

        let short = dir.appendingPathComponent("one.pdf")
        try pdf(lines: ["12/01/2026  STAR HEALTH PREMIUM  9,200.00"]).write(to: short)
        let whole = try StatementCloud.pdfPieces(short, name: "one.pdf", password: nil)
        XCTAssertEqual(whole.map(\.label), ["1 page"])
        // Rebuilt, not copied: the pages alone travel, never a script or a form the original carried.
        XCTAssertNotEqual(Data(base64Encoded: whole[0].data), try Data(contentsOf: short), "a short PDF is rebuilt like a long one")
        let rebuilt = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(Data(base64Encoded: whole[0].data))))
        XCTAssertEqual(rebuilt.pageCount, 1)
        XCTAssertTrue(rebuilt.page(at: 0)?.string?.contains("STAR HEALTH") == true)
    }
    #endif

    func testAnAmountThatLooksLikeASpreadsheetDateStaysAnAmount() {
        let sheet = [
            ["Date", "Narration", "Debit", "Credit"],
            ["01/09/2025", "NEFT-DR-HOUSE RENT-MEHTA PROPERTIES", "42000.00", ""],
            ["20/09/2025", "CREDIT CARD PAYMENT AXIS 4402", "38000.00", ""],
            ["28/09/2025", "SALARY CREDIT", "", "45000"],
        ]
        let text = StatementCloud.rowPieces(sheet, name: "hdfc.csv")[0].data
        XCTAssertTrue(text.contains("\"42000.00\""), "rent stays 42000.00, not a 2014 date")
        XCTAssertTrue(text.contains("\"38000.00\""))
        XCTAssertTrue(text.contains("\"45000\""))
        XCTAssertTrue(text.contains("\"2025-09-01\""), "the date column still reads as dates")
        XCTAssertFalse(text.contains("2014-12-27"))
    }

    func testASerialDateUnderADateHeadingIsStillADate() {
        let sheet = [["Txn Date", "Description", "Amount"], ["46023", "SWIGGY ORDER", "640"]]
        let text = StatementCloud.rowPieces(sheet, name: "card.xlsx")[0].data
        XCTAssertTrue(text.contains("\"2026-01-01\""))
        XCTAssertTrue(text.contains("\"640\""))
    }

    func testASheetWithNoDatedLinesNeverLeavesTheDevice() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notes.csv")
        try "Name,Phone\nSunita,98765\nAnil,91234\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try StatementCloud.pieces(for: file, password: nil)) { error in
            guard case StatementText.ReadError.noLines = error else { return XCTFail("expected noLines, got \(error)") }
        }
    }

    func testCandidatesComeTriagedAndNamed() {
        let lines = [
            StatementLine(date: "2026-07-01", payee: "UPI-NETFLIX.COM-123456789012", amount: 649, direction: .debit),
            StatementLine(date: "2026-07-05", payee: "SALARY JUL 2026", amount: 150_000, direction: .credit),
        ]
        let candidates = StatementImport.candidates(from: lines)
        XCTAssertEqual(candidates.map(\.keep), [true, false])
        XCTAssertEqual(candidates[0].name, "Netflix")
        XCTAssertEqual(candidates[1].skipReason, "money in")
    }

    // MARK: the shapes a bank hands out

    /// The generated fixtures — the same bytes the server's import proof reads. A shape
    /// that defeats this reader fails here rather than on someone's statement.
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/statements/\(name)", withExtension: nil), "fixture \(name) is missing")
    }

    func testTheYearOfSavingsImportsTheSameFromThePDFAndTheCSV() throws {
        let fromPDF = try StatementText.lines(from: try fixture("hdfc-savings-2025-2026.pdf"))
        let fromCSV = try StatementText.lines(from: try fixture("hdfc-savings-2025-2026.csv"))
        XCTAssertGreaterThan(fromCSV.count, 50, "a year of a household's account is not a handful of lines")
        XCTAssertEqual(fromPDF.count, fromCSV.count, "no printed line is lost or run into its neighbour")
        XCTAssertEqual(fromPDF.map(\.date), fromCSV.map(\.date))
        XCTAssertEqual(fromPDF.map(\.amount), fromCSV.map(\.amount))
        XCTAssertEqual(fromPDF.map(\.payee), fromCSV.map(\.payee))

        // What matters is the import, not how each shape spells its columns: the same
        // charges are written and the same lines are left out, whichever file is picked.
        func kept(_ lines: [StatementLine]) -> [String] {
            StatementImport.candidates(from: lines).filter(\.keep).map { "\($0.line.date) \($0.name) \($0.line.amount)" }
        }
        XCTAssertEqual(kept(fromPDF), kept(fromCSV))

        let candidates = StatementImport.candidates(from: fromCSV)
        XCTAssertTrue(candidates.contains { $0.keep }, "a year of statements proves charges")
        XCTAssertTrue(candidates.contains { $0.skipReason == "money in" }, "the salary is not a spend")
        XCTAssertTrue(candidates.contains { $0.skipReason == "your own money moved" }, "the card bill is not a spend")
        let repeats = StatementImport.repeats(in: candidates)
        XCTAssertTrue(repeats.contains { $0.cycle == .monthly }, "a monthly rhythm is there to be found")
        XCTAssertTrue(repeats.contains { $0.name.contains("Netflix") }, "the subscription among them is named plainly")
    }

    func testTheCardWorkbookReads() throws {
        let lines = try StatementText.lines(from: try fixture("axis-card-2026.xlsx"))
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy { LB.parseDate($0.date) != nil && $0.amount > 0 })
    }

    func testTheRefusalsSayWhy() throws {
        XCTAssertThrowsError(try StatementText.lines(from: try fixture("icici-scanned-june.pdf"))) {
            XCTAssertEqual($0 as? StatementText.ReadError, .scanned)
        }
        XCTAssertThrowsError(try StatementText.lines(from: try fixture("old-export.xls"))) {
            guard case .noLines? = $0 as? StatementText.ReadError else { return XCTFail("a broken workbook says what it lacks, got \($0)") }
        }
        XCTAssertThrowsError(try StatementText.lines(from: try fixture("policy-note.docx"))) {
            XCTAssertEqual($0 as? StatementText.ReadError, .unsupported("docx"))
        }
    }

    // MARK: files

    func testACSVFileReadsThroughToLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("hdfc.csv")
        try """
        Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
        01/07/2026,NETFLIX.COM,649.00,,12345.50
        """.write(to: file, atomically: true, encoding: .utf8)
        let lines = try StatementText.lines(from: file)
        XCTAssertEqual(lines.map(\.payee), ["NETFLIX.COM"])
        XCTAssertThrowsError(try StatementText.lines(from: dir.appendingPathComponent("sheet.xlsx")))
    }

    #if os(macOS)
    func testAPDFWithTextReadsAndAScanIsRefused() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let typed = dir.appendingPathComponent("typed.pdf")
        try pdf(lines: ["12/01/2026  STAR HEALTH PREMIUM  9,200.00", "14/01/2026  PAYMENT RECEIVED  9,200.00 Cr"]).write(to: typed)
        let lines = try StatementText.lines(from: typed)
        XCTAssertEqual(lines.map(\.payee), ["STAR HEALTH PREMIUM", "PAYMENT RECEIVED"])
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit])

        let scan = dir.appendingPathComponent("scan.pdf")
        try pdf(lines: []).write(to: scan)
        XCTAssertThrowsError(try StatementText.lines(from: scan)) { error in
            XCTAssertEqual(error.localizedDescription, StatementText.ReadError.scanned.localizedDescription)
        }
    }

    func testATableDrawnCellByCellComesBackAsRows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Each cell its own text run, columns drawn one after another, as bank PDFs do.
        let cells: [(String, CGFloat, CGFloat)] = [
            ("Date", 40, 740), ("Narration", 120, 740), ("Withdrawal", 360, 740), ("Balance", 480, 740),
            ("01/07/2026", 40, 720), ("05/07/2026", 40, 700),
            ("NETFLIX.COM", 120, 720), ("SALARY JUL 2026", 120, 700),
            ("649.00", 360, 720), ("1,50,000.00", 360, 700),
            ("12,345.50", 480, 720), ("1,62,345.50", 480, 700),
        ]
        let file = dir.appendingPathComponent("cells.pdf")
        try pdf(cells: cells).write(to: file)
        let lines = try StatementText.lines(from: file)
        XCTAssertEqual(lines.map(\.payee), ["NETFLIX.COM", "SALARY JUL 2026"])
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit])
    }

    func testAlignedMoneyColumnsSayWhichWayEachWent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A table as a bank sets it: headings over money columns, figures right-aligned
        // under them, and a deposit that is money in only because of where it sits.
        var cells: [(String, CGFloat, CGFloat)] = [
            ("Date", 40, 740), ("Narration", 110, 740), ("Withdrawal", 250, 740), ("Deposit", 340, 740), ("Balance", 430, 740),
            ("01/07/2026", 40, 720), ("NETFLIX SUBSCRIPTION", 110, 720),
            ("05/07/2026", 40, 700), ("SALARY VERTEX LABS", 110, 700),
            ("07/07/2026", 40, 680), ("GREENWOOD SOCIETY MAINT", 110, 680),
        ]
        cells += [right("649.00", 320, 720), right("1,62,345.50", 500, 720)]
        cells += [right("2,14,000.00", 410, 700), right("3,76,345.50", 500, 700)]
        cells += [right("3,500.00", 320, 680), right("3,72,845.50", 500, 680)]
        let file = dir.appendingPathComponent("columns.pdf")
        try pdf(cells: cells).write(to: file)

        let lines = try StatementText.lines(from: file)
        XCTAssertEqual(lines.map(\.date), ["2026-07-01", "2026-07-05", "2026-07-07"])
        XCTAssertEqual(lines.map(\.amount), [649, 214_000, 3500], "the balance beside a figure is not the figure")
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit, .debit], "the column a figure sits in says which way it went")
    }

    func testANarrationWrappedAroundItsRowReadsAsOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // One bank prints the narration's first line above the dated row, which carries
        // only a number, a dotted date and the figures; the rest wraps below. Another
        // wraps below only. Both are one charge each.
        var cells: [(String, CGFloat, CGFloat)] = [
            ("Date", 61, 740), ("Withdrawal", 399, 740), ("Deposit", 474, 740), ("Balance", 532, 740),
        ]
        // Lines a line apart for an 11-point face; the label sits most of a line above.
        cells += [
            ("Digital Ag", 192, 724),
            ("1", 31, 716), ("01.08.2026", 61, 716),
            ("UPI/Digital Ag/payment.firstc/UPI/SLICE", 192, 702),
            ("SMAL/657995366548/ICIf6d425e651534e03a8b9a", 192, 688),
            ("Google Ind", 192, 674),
            ("2", 31, 666), ("02.08.2026", 61, 666),
            ("UPI/Google Ind/gpayrefund-onl/UPI/AXIS", 192, 652),
            ("3", 31, 626), ("03.08.2026", 61, 626), ("UPI/MYNTRA DESIGNS/UTIB/Payment", 192, 626),
            ("for order", 192, 612),
            ("Page 1 of 8", 280, 540),
        ]
        cells += [right("383.25", 452, 716), right("626734.54", 580, 716)]
        cells += [right("688.00", 518, 666), right("627422.54", 580, 666)]
        cells += [right("1525.00", 452, 626), right("625897.54", 580, 626)]
        let file = dir.appendingPathComponent("wrapped.pdf")
        try pdf(cells: cells).write(to: file)

        let lines = try StatementText.lines(from: file)
        XCTAssertEqual(lines.map(\.date), ["2026-08-01", "2026-08-02", "2026-08-03"], "a dotted date is a date")
        XCTAssertEqual(lines.map(\.amount), [383.25, 688, 1525])
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit, .debit])
        XCTAssertEqual(lines.map(\.payee), [
            "Digital Ag UPI/Digital Ag/payment.firstc/UPI/SLICE SMAL/657995366548/ICIf6d425e651534e03a8b9a",
            "Google Ind UPI/Google Ind/gpayrefund-onl/UPI/AXIS",
            "UPI/MYNTRA DESIGNS/UTIB/Payment for order",
        ], "the line above a bare row and the lines below belong to it; a page footer far below belongs to nobody")
    }

    func testTheDateShapesBanksPrint() {
        XCTAssertEqual(StatementLines.parseDate("01.08.2026"), "2026-08-01")
        XCTAssertEqual(StatementLines.parseDate("18 Jul '26"), "2026-07-18")
        XCTAssertEqual(StatementLines.parseDate("07/04/24"), "2024-04-07")
        XCTAssertEqual(StatementLines.parseDate("02 Aug 2026"), "2026-08-02")
        XCTAssertEqual(StatementLines.parseDate("46204"), "2026-07-01", "a spreadsheet's day count")
        XCTAssertNil(StatementLines.parseDate("4402"), "a card's last four digits are not a day")
    }

    func testTheOldExcelWorkbookReadsCellByCell() throws {
        let records = try BIFFWorkbook.records(biff8Workbook())
        XCTAssertEqual(records[0], ["Date", "Narration", "Withdrawal", "Deposit", "Balance"])
        XCTAssertEqual(records[1], ["2026-07-01", "NETFLIX.COM", "649", "", "12345.5"], "a date-formatted number reads as its day; a packed integer as itself")
        XCTAssertEqual(records[2], ["05/07/2026", "SALARY JUL 2026", "", "150000", "162345.5"])
        let lines = StatementLines.fromRecords(records)
        XCTAssertEqual(lines.map(\.date), ["2026-07-01", "2026-07-05"])
        XCTAssertEqual(lines.map(\.direction), [.debit, .credit])
        XCTAssertThrowsError(try BIFFWorkbook.records(Data("not a workbook at all".utf8))) {
            XCTAssertEqual($0 as? BIFFWorkbook.ReadError, .notACompoundFile)
        }
    }

    /// The smallest real .xls: a compound file holding one BIFF8 workbook with a shared
    /// string table, a date format, two cell styles and one sheet of five columns.
    private func biff8Workbook() -> Data {
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }
        func record(_ type: Int, _ body: [UInt8]) -> [UInt8] { u16(type) + u16(body.count) + body }
        func text(_ s: String) -> [UInt8] { u16(s.utf8.count) + [0] + Array(s.utf8) }
        func double(_ d: Double) -> [UInt8] { u32(UInt32(d.bitPattern & 0xFFFF_FFFF)) + u32(UInt32(d.bitPattern >> 32)) }
        func labelSST(_ row: Int, _ col: Int, _ index: Int) -> [UInt8] { record(0x00FD, u16(row) + u16(col) + u16(0) + u32(UInt32(index))) }
        func number(_ row: Int, _ col: Int, _ value: Double, xf: Int = 0) -> [UInt8] { record(0x0203, u16(row) + u16(col) + u16(xf) + double(value)) }
        func rkInteger(_ row: Int, _ col: Int, _ value: Int) -> [UInt8] { record(0x027E, u16(row) + u16(col) + u16(0) + u32(UInt32(value << 2 | 0x02))) }

        let strings = ["Date", "Narration", "Withdrawal", "Deposit", "Balance", "NETFLIX.COM", "05/07/2026", "SALARY JUL 2026"]
        var globals: [UInt8] = record(0x0809, u16(0x0600) + u16(0x0005) + [UInt8](repeating: 0, count: 12))
        globals += record(0x041E, u16(164) + text("dd/mm/yyyy"))
        globals += record(0x00E0, u16(0) + u16(0) + [UInt8](repeating: 0, count: 16))
        globals += record(0x00E0, u16(0) + u16(164) + [UInt8](repeating: 0, count: 16))
        let boundsheetAt = globals.count
        globals += record(0x0085, u32(0) + u16(0) + [6, 0] + Array("Sheet1".utf8))
        globals += record(0x00FC, u32(UInt32(strings.count)) + u32(UInt32(strings.count)) + strings.flatMap(text))
        globals += record(0x000A, [])

        var sheet: [UInt8] = record(0x0809, u16(0x0600) + u16(0x0010) + [UInt8](repeating: 0, count: 12))
        for column in 0..<5 { sheet += labelSST(0, column, column) }
        sheet += number(1, 0, 46204, xf: 1) + labelSST(1, 1, 5) + rkInteger(1, 2, 649) + number(1, 4, 12345.5)
        sheet += labelSST(2, 0, 6) + labelSST(2, 1, 7) + number(2, 3, 150_000) + number(2, 4, 162_345.5)
        sheet += record(0x000A, [])

        var stream = globals + sheet
        stream.replaceSubrange((boundsheetAt + 4)..<(boundsheetAt + 8), with: u32(UInt32(globals.count)))
        // Below the mini-stream cutoff a stream would live elsewhere; padding keeps it plain.
        stream += [UInt8](repeating: 0, count: max(0, 4096 - stream.count))
        let sectors = (stream.count + 511) / 512
        stream += [UInt8](repeating: 0, count: sectors * 512 - stream.count)

        var header = [UInt8](repeating: 0, count: 512)
        header.replaceSubrange(0..<8, with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        header.replaceSubrange(24..<32, with: u16(0x3E) + u16(3) + u16(0xFFFE) + u16(9))
        header.replaceSubrange(32..<34, with: u16(6))
        header.replaceSubrange(44..<48, with: u32(1))
        header.replaceSubrange(48..<52, with: u32(1))
        header.replaceSubrange(56..<60, with: u32(4096))
        header.replaceSubrange(60..<64, with: u32(0xFFFF_FFFE))
        header.replaceSubrange(68..<72, with: u32(0xFFFF_FFFE))
        header.replaceSubrange(76..<80, with: u32(0))
        for slot in 1..<109 { header.replaceSubrange((76 + slot * 4)..<(80 + slot * 4), with: u32(0xFFFF_FFFF)) }

        var fat = [UInt8](repeating: 0xFF, count: 512)
        fat.replaceSubrange(0..<4, with: u32(0xFFFF_FFFD))
        fat.replaceSubrange(4..<8, with: u32(0xFFFF_FFFE))
        for index in 0..<sectors {
            let next: UInt32 = index + 1 < sectors ? UInt32(index + 3) : 0xFFFF_FFFE
            fat.replaceSubrange((8 + index * 4)..<(12 + index * 4), with: u32(next))
        }

        func entry(_ name: String, type: UInt8, start: UInt32, size: UInt32) -> [UInt8] {
            var e = [UInt8](repeating: 0, count: 128)
            let utf16 = Array(name.utf16).flatMap { u16(Int($0)) }
            e.replaceSubrange(0..<utf16.count, with: utf16)
            e.replaceSubrange(64..<66, with: u16(utf16.count + 2))
            e[66] = type
            e[67] = 1
            e.replaceSubrange(68..<80, with: u32(0xFFFF_FFFF) + u32(0xFFFF_FFFF) + u32(type == 5 ? 1 : 0xFFFF_FFFF))
            e.replaceSubrange(116..<120, with: u32(start))
            e.replaceSubrange(120..<124, with: u32(size))
            return e
        }
        var directory = entry("Root Entry", type: 5, start: 0xFFFF_FFFE, size: 0) + entry("Workbook", type: 2, start: 2, size: UInt32(stream.count))
        directory += [UInt8](repeating: 0, count: 512 - directory.count)
        return Data(header + fat + directory + stream)
    }

    /// One cell, right-aligned so its last character lands on `edge`, as a money column is.
    private func right(_ text: String, _ edge: CGFloat, _ y: CGFloat) -> (String, CGFloat, CGFloat) {
        let width = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11)]).size().width
        return (text, edge - width, y)
    }

    func testALockedPDFAsksForItsPasswordThenOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let open = try XCTUnwrap(PDFDocument(data: pdf(lines: ["12/01/2026  STAR HEALTH PREMIUM  9,200.00"])))
        let file = dir.appendingPathComponent("locked.pdf")
        XCTAssertTrue(open.write(to: file, withOptions: [.userPasswordOption: "ROHI0101", .ownerPasswordOption: "ROHI0101"]))
        XCTAssertThrowsError(try StatementText.lines(from: file)) { XCTAssertEqual($0 as? StatementText.ReadError, .locked) }
        XCTAssertThrowsError(try StatementText.lines(from: file, password: "nope")) { XCTAssertEqual($0 as? StatementText.ReadError, .wrongPassword) }
        XCTAssertEqual(try StatementText.lines(from: file, password: "ROHI0101").map(\.amount), [9200])
    }

    func testALockedPDFGoesUpAsAnOpenOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = pdf(lines: ["12/01/2026  STAR HEALTH PREMIUM  9,200.00"])
        let locked = dir.appendingPathComponent("locked.pdf")
        let document = try XCTUnwrap(PDFDocument(data: original))
        XCTAssertTrue(document.write(to: locked, withOptions: [.userPasswordOption: "ROHI0101", .ownerPasswordOption: "ROHI0101"]))
        XCTAssertThrowsError(try StatementCloud.pdfPieces(locked, name: "locked.pdf", password: nil))
        let pieces = try StatementCloud.pdfPieces(locked, name: "locked.pdf", password: "ROHI0101")
        XCTAssertEqual(pieces.count, 1)
        let opened = try XCTUnwrap(Data(base64Encoded: pieces[0].data))
        let reread = try XCTUnwrap(PDFDocument(data: opened))
        XCTAssertFalse(reread.isEncrypted, "the copy that goes up carries no lock")
        XCTAssertFalse(reread.isLocked)
        XCTAssertEqual(reread.pageCount, 1)
        XCTAssertTrue(reread.page(at: 0)?.string?.contains("STAR HEALTH") == true)
    }

    func testAnExcelSheetReadsLikeACSV() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try xlsx(in: dir, rows: [
            ["Txn Date", "Description", "Debit", "Credit", "Balance"],
            ["01/07/2026", "NETFLIX.COM", "649", "", "12345.5"],
            ["46204", "IRCTC WEB BOOKING", "4560", "", "7785.5"],
        ])
        let lines = try StatementText.lines(from: file)
        XCTAssertEqual(lines.map(\.date), ["2026-07-01", "2026-07-01"], "a serial date cell reads as its day")
        XCTAssertEqual(lines.map(\.amount), [649, 4560])
        XCTAssertThrowsError(try StatementText.lines(from: dir.appendingPathComponent("old.xls")))
    }

    /// One page of plain text, drawn with Core Text so PDFKit can read it back.
    private func pdf(lines: [String]) -> Data {
        pdf(cells: lines.enumerated().map { ($1, 40, 740 - CGFloat($0) * 16) })
    }

    private func pdf(cells: [(String, CGFloat, CGFloat)]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        for (text, x, y) in cells {
            let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11)])
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// A minimal .xlsx: one sheet of inline strings, zipped with the system tool.
    private func xlsx(in dir: URL, rows: [[String]]) throws -> URL {
        let root = dir.appendingPathComponent("book", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)
        let letters = Array("ABCDEFGH")
        let body = rows.enumerated().map { r, row in
            let cells = row.enumerated().map { c, value in
                "<c r=\"\(letters[c])\(r + 1)\" t=\"inlineStr\"><is><t>\(value)</t></is></c>"
            }.joined()
            return "<row r=\"\(r + 1)\">\(cells)</row>"
        }.joined()
        let files: [String: String] = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
            """,
            "xl/worksheets/sheet1.xml": """
            <?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(body)</sheetData></worksheet>
            """,
        ]
        for (path, text) in files {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        let out = dir.appendingPathComponent("statement.xlsx")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root
        zip.arguments = ["-q", "-r", "-X", out.path, "."]
        try zip.run()
        zip.waitUntilExit()
        return out
    }
    #endif

    // MARK: helpers

    private func candidate(_ name: String, _ date: String, _ amount: Double, payee: String? = nil, tag: String? = nil) -> StatementCandidate {
        StatementCandidate(
            line: StatementLine(date: date, payee: payee ?? name.uppercased(), amount: amount, direction: .debit),
            name: name, tag: tag, keep: true, skipReason: nil
        )
    }

    private func seededVault() throws -> [String: Any] {
        let object: [String: Any] = ["app": "longbook", "version": 3, "commitments": [], "charges": [], "members": [], "accounts": []]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
