import XCTest
@testable import LongbookCore

final class BankMessageTests: XCTestCase {
    private let today = LB.day(2026, 9, 14)

    func testADebitNamesTheAmountTheDayThePayeeAndTheAccount() throws {
        let read = try XCTUnwrap(BankMessage.parse(
            "Rs.1,250.00 debited from A/c XX1234 on 12-09-26 to VPA swiggy@ybl (UPI Ref 526012345678). -HDFC Bank", today: today))
        XCTAssertEqual(read.amount, 1250)
        XCTAssertEqual(read.direction, "out")
        XCTAssertEqual(read.date, "2026-09-12")
        XCTAssertEqual(read.payee, "swiggy")
        XCTAssertEqual(read.last4, "1234")
        XCTAssertEqual(read.currency, "INR")
    }

    func testACardSpendAndAWordedDate() throws {
        let read = try XCTUnwrap(BankMessage.parse(
            "INR 2,499.00 spent on your Axis Bank Credit Card XX4402 at AMAZON on 12-Sep-26. Not you? Call 1800.", today: today))
        XCTAssertEqual(read.amount, 2499)
        XCTAssertEqual(read.direction, "out")
        XCTAssertEqual(read.date, "2026-09-12")
        XCTAssertEqual(read.payee, "AMAZON")
        XCTAssertEqual(read.last4, "4402")
    }

    func testACreditIsMoneyIn() throws {
        let read = try XCTUnwrap(BankMessage.parse(
            "Your a/c XX9876 is credited with Rs.1,50,000.00 on 01-09-2026 by NEFT-VERTEX LABS. Avl bal Rs 2,10,000", today: today))
        XCTAssertEqual(read.amount, 150_000)
        XCTAssertEqual(read.direction, "in")
        XCTAssertEqual(read.date, "2026-09-01")
        XCTAssertEqual(read.payee, "VERTEX LABS")
        XCTAssertEqual(read.last4, "9876")
    }

    func testNoAmountIsNoCharge() {
        XCTAssertNil(BankMessage.parse("Your OTP for login is 482910. Do not share it.", today: today))
        XCTAssertEqual(BankMessage.parse("Rs 349 debited from a/c **1234 trf to NETFLIX", today: today)?.date, "2026-09-14",
                       "a message with no day is read as today's")
    }

    func testAnUPISendNamesThePersonAndTheAccount() throws {
        let read = try XCTUnwrap(BankMessage.parse(
            "Sent Rs.500.00\nFrom HDFC Bank A/C *1234\nTo ROHIT KUMAR\nOn 12/09/26\nRef 425512345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808", today: today))
        XCTAssertEqual(read.amount, 500)
        XCTAssertEqual(read.direction, "out")
        XCTAssertEqual(read.date, "2026-09-12")
        XCTAssertEqual(read.payee, "ROHIT KUMAR")
        XCTAssertEqual(read.last4, "1234")
    }

    func testACardSpendWithAClockDayAndABankInfoField() throws {
        let card = try XCTUnwrap(BankMessage.parse(
            "Rs.1234.00 spent on HDFC Bank Card x4417 at AMAZON on 2026-09-12:20:15:11. Not you? Call 18002586161.", today: today))
        XCTAssertEqual(card.date, "2026-09-12")
        XCTAssertEqual(card.payee, "AMAZON")
        XCTAssertEqual(card.last4, "4417")
        let info = try XCTUnwrap(BankMessage.parse(
            "Update: INR 2,500.00 debited from HDFC Bank XX1234 on 12-SEP-26. Info: UPI-425512345678-SWIGGY. Avl bal INR 10,000.00", today: today))
        XCTAssertEqual(info.amount, 2500)
        XCTAssertEqual(info.payee, "SWIGGY")
        XCTAssertEqual(info.last4, "1234")
        let axis = try XCTUnwrap(BankMessage.parse(
            "INR 1234.00 debited from A/c no. XX9911 on 12-09-26 at 14:22:11 IST. Info- UPI/P2M/424242424242/BLUE TOKAI COFFEE. Avl Bal INR 5,000.00", today: today))
        XCTAssertEqual(axis.payee, "BLUE TOKAI COFFEE")
        XCTAssertEqual(axis.last4, "9911")
    }

    func testACreditThroughAnOwnAccountStillNamesThePayer() throws {
        let read = try XCTUnwrap(BankMessage.parse(
            "Rs 500.00 credited to A/c XX1234 on 12-09-26 by a/c linked to VPA rohit@okaxis (UPI Ref No 123456789012)", today: today))
        XCTAssertEqual(read.direction, "in")
        XCTAssertEqual(read.payee, "rohit")
        let icici = try XCTUnwrap(BankMessage.parse(
            "ICICI Bank Acct XX123 debited for Rs 1,234.00 on 12-Sep-26; SWIGGY credited. UPI:123456. Call 18002662 for dispute.", today: today))
        XCTAssertEqual(icici.direction, "out")
        XCTAssertEqual(icici.payee, "SWIGGY")
        let kotak = try XCTUnwrap(BankMessage.parse(
            "Sent Rs.500.00 from Kotak Bank AC X5566 to payee@upi on 12-09-26.UPI Ref 1234. Not you, kotak.com/fraud", today: today))
        XCTAssertEqual(kotak.payee, "payee")
        XCTAssertEqual(kotak.last4, "5566")
    }

    func testTheAmountIsTheChargeInWhateverCurrencyAndNeverWhatIsLeftOrDue() throws {
        let union = try XCTUnwrap(BankMessage.parse(
            "A/c *1234 Debited for Rs:500.00 on 21-09-2026 10:22:33 by Mob Bk ref no 562812345678 Avl Bal Rs:1000.00.If not you, Call 1800222243 -Union Bank of India", today: today))
        XCTAssertEqual(union.amount, 500)
        XCTAssertEqual(union.payee, "", "the channel is no payee")
        XCTAssertEqual(union.last4, "1234")
        let pounds = try XCTUnwrap(BankMessage.parse(
            "GBP 20.00 spent on HDFC Bank Card x1234 at SPOTIFY UK on 2026-09-21:10:22:33. Avl Lmt Rs 1,00,000", today: today))
        XCTAssertEqual(pounds.amount, 20)
        XCTAssertEqual(pounds.currency, "GBP")
        XCTAssertEqual(pounds.payee, "SPOTIFY UK")
        let euros = try XCTUnwrap(BankMessage.parse(
            "EUR 20.00 spent on Card x1234 at SPOTIFY on 21-09-26. Total outstanding Rs 12,345.00", today: today))
        XCTAssertEqual(euros.amount, 20)
        XCTAssertEqual(euros.currency, "EUR")
        XCTAssertEqual(BankMessage.parse("$12.99 spent on Card x1234 at OPENAI on 21-09-26", today: today)?.currency, "USD")
        for balanceFirst in ["A/c XX1234 AvlBal:Rs10000.00. Rs.149.00 debited to NETFLIX on 21-09-26",
                             "Available Balance in A/c XX1234 is Rs 10,000.00. Rs 149.00 debited to NETFLIX on 21-09-26",
                             "Your Card XX1234 has Outstanding of Rs 12,345.00. Rs 149.00 spent at NETFLIX on 21-09-26"] {
            let read = try XCTUnwrap(BankMessage.parse(balanceFirst, today: today), balanceFirst)
            XCTAssertEqual(read.amount, 149, balanceFirst)
            XCTAssertEqual(read.currency, "INR")
            XCTAssertEqual(read.payee, "NETFLIX", balanceFirst)
        }
        XCTAssertNil(BankMessage.parse("Your HDFC Bank Card XX1234 statement is ready. Total due Rs 5,000.00, Min due Rs 250.00, pay by 05-10-26.", today: today))
        XCTAssertNil(BankMessage.parse("Get a pre-approved personal loan up to Rs 5,00,000 at 10.5%", today: today), "no money moved")
        XCTAssertNil(BankMessage.parse("Get Rs 500 cashback on your next transaction. T&C apply", today: today), "no money moved")
        XCTAssertEqual(BankMessage.parse("Rs 1 lakh limit. Rs.149.00 debited from A/c XX1234 to NETFLIX", today: today)?.amount, 149)
        let used = try XCTUnwrap(BankMessage.parse("Transaction of Rs 149 done on Kotak Credit Card X1234 at NETFLIX on 21-09-26", today: today))
        XCTAssertEqual(used.amount, 149)
        XCTAssertEqual(used.payee, "NETFLIX")
    }

    func testTheDayIsTheFirstOneNamedAndNeverAnImpossibleOne() {
        let days: [(text: String, day: String?)] = [
            ("Rs 149.00 debited from A/c XX1234 on 20-09-26. Mandate valid till 2030-12-31. To NETFLIX", "2026-09-20"),
            ("Rs 149 debited from A/c XX1234 to NETFLIX. Call 1800-11-22-11 if not you. Dt 20-09-26", "2026-09-20"),
            ("Rs 149 debited from A/c XX1234 to NETFLIX on 31-02-26", nil),
            ("Rs 149 spent on Card XX1234 at NETFLIX on 21 SEPTEMBER 2026 at 10:22", "2026-09-21"),
            ("Rs 149 spent on Card XX1234 at NETFLIX on 21st Sep 2026", "2026-09-21"),
            ("Rs 149 spent on Card XX1234 at NETFLIX on 21-Sept-2026", "2026-09-21"),
            ("Rs 149 spent on Card XX1234 at NETFLIX on 2026/09/21", "2026-09-21"),
            ("Rs 149 debited from A/c XX1234 to NETFLIX on Sep 20, 2026", "2026-09-20"),
            ("Rs.500 Dr. from A/C XXXXXX1234 and Cr. to swiggy@ybl. Ref:526012345678. AvlBal:Rs1000(2026:09:21 10:22:33). Not you? Call 18005700-BOB", "2026-09-21"),
            ("Rs 149.00 debited from A/c XX1234 on 12-09-26 at 14:22:11 IST to NETFLIX", "2026-09-12"),
        ]
        for one in days {
            XCTAssertEqual(BankMessage.dateIn(one.text), one.day, one.text)
            XCTAssertEqual(BankMessage.parse(one.text, today: today)?.date, one.day ?? "2026-09-14", one.text)
        }
        let yearless = BankMessage.parse("INR 149.00 spent using ICICI Bank Card XX1234 on 21 Sep on NETFLIX. Avl Limit: INR 1,00,000.00", today: today)
        XCTAssertEqual(yearless?.payee, "NETFLIX", "a day with no year is still no payee")
    }

    func testTheLastFourNeedAnAccountBeforeThem() {
        XCTAssertNil(BankMessage.last4In("Rs 149.00 debited via UPI to VPA netflix@icici. Ref No 562812345678 -Federal Bank 1800 425 1199"))
        XCTAssertEqual(BankMessage.last4In("Rs 149 debited from A/c ...1234 to NETFLIX"), "1234")
        XCTAssertEqual(BankMessage.last4In("Rs 149 debited from A/c XXXX-1234 to NETFLIX"), "1234")
        XCTAssertEqual(BankMessage.last4In("INR 2,500.00 debited from HDFC Bank XX1234 on 12-SEP-26"), "1234")
        XCTAssertEqual(BankMessage.last4In("debited from your account ending 4542 towards"), "4542")
    }
}
