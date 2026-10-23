import XCTest
@testable import LongbookCore

/// The messages banks here send, each in its own words, read for whom the money went to.
final class BankMessageFormatsTests: XCTestCase {
    private let today = LB.day(2026, 9, 14)

    private func read(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> BankMessage {
        try XCTUnwrap(BankMessage.parse(text, today: today), file: file, line: line)
    }

    private let axisUPI = "INR 149.00 debited\nA/c no. XX1234\n21-09-26, 10:22:33\nUPI/P2M/562812345678/NETFLIX COM\nNot you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank"
    private let axisCard = "Spent\nCard no. XX1234\nINR 149\n21-09-26 10:22:33\nNETFLIX\nAvl Lmt INR 123456.78\nNot you? SMS BLOCK 1234 to 919951860002"

    func testAxisPrintsAFieldToALine() throws {
        let debit = try read(axisUPI)
        XCTAssertEqual(debit.payee, "NETFLIX COM")
        XCTAssertEqual(debit.name, "Netflix Com")
        XCTAssertEqual(debit.amount, 149)
        XCTAssertEqual(debit.direction, "out")
        XCTAssertEqual(debit.last4, "1234")
        XCTAssertEqual(debit.date, "2026-09-21")
    }

    func testTheSameMessageOnOneLineReadsTheSame() throws {
        let flat = try read(axisUPI.replacingOccurrences(of: "\n", with: " "))
        XCTAssertEqual(flat.payee, "NETFLIX COM")
        XCTAssertEqual(flat.direction, "out")
        XCTAssertEqual(flat.last4, "1234")
        XCTAssertEqual(flat.date, "2026-09-21")
        XCTAssertEqual(try read(axisUPI.replacingOccurrences(of: "\n", with: "\r\n")).payee, "NETFLIX COM")
    }

    func testAnAxisCreditNamesThePayerNotTheirBank() throws {
        let credit = try read("INR 5000.00 credited\nA/c no. XX1234\n21-09-26, 10:22:33 IST\nUPI/P2A/562812345678/RAHUL VERMA/HDFC Bank\nAxis Bank")
        XCTAssertEqual(credit.payee, "RAHUL VERMA")
        XCTAssertEqual(credit.name, "Rahul Verma")
        XCTAssertEqual(credit.direction, "in")
        XCTAssertEqual(credit.amount, 5000)
    }

    func testAnAxisCardNamesTheMerchantOnItsOwnLine() throws {
        let card = try read(axisCard)
        XCTAssertEqual(card.payee, "NETFLIX")
        XCTAssertEqual(card.name, "Netflix")
        XCTAssertEqual(card.amount, 149, "the limit left is not the charge")
        XCTAssertEqual(card.direction, "out")
        XCTAssertEqual(card.last4, "1234")
        XCTAssertEqual(try read(axisCard.replacingOccurrences(of: "\n", with: " ")).payee, "NETFLIX")
    }

    func testHDFCByUPIAndByCard() throws {
        let upi = try read("Sent Rs.149.00\nFrom HDFC Bank A/C *1234\nTo NETFLIX\nOn 21/09/26\nRef 562812345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808")
        XCTAssertEqual(upi.payee, "NETFLIX")
        XCTAssertEqual(upi.date, "2026-09-21")
        let card = try read("Rs.149 spent on HDFC Bank Card x1234 at NETFLIX on 2026-09-21:10:22:33.Not U? To Block & Reissue Call 18002586161/SMS BLOCK CC 1234 to 7308080808")
        XCTAssertEqual(card.payee, "NETFLIX")
        XCTAssertEqual(card.amount, 149)
        XCTAssertEqual(card.last4, "1234")
    }

    func testICICIByCardAndByUPI() throws {
        let card = try read("INR 149.00 spent using ICICI Bank Card XX1234 on 21-Sep-26 on NETFLIX. Avl Limit: INR 1,00,000.00. If not you, call 1800 2662/SMS BLOCK 1234 to 9215676766")
        XCTAssertEqual(card.payee, "NETFLIX", "the payee follows the second on; the day after the first is no payee")
        XCTAssertEqual(card.amount, 149)
        XCTAssertEqual(card.date, "2026-09-21")
        let upi = try read("ICICI Bank Acct XX123 debited for Rs 149.00 on 21-Sep-26; NETFLIX credited. UPI:562812345678. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.")
        XCTAssertEqual(upi.payee, "NETFLIX", "a number to ring is never a payee")
        XCTAssertEqual(upi.direction, "out")
    }

    func testSBINamesAnAmountWithNoCurrencyBeforeIt() throws {
        let sbi = try read("Dear UPI user A/C X1234 debited by 149.00 on date 21Sep26 trf to NETFLIX Refno 562812345678 If not u? call-1800111109 for other services-18001234-SBI")
        XCTAssertEqual(sbi.amount, 149)
        XCTAssertEqual(sbi.currency, "INR")
        XCTAssertEqual(sbi.payee, "NETFLIX")
        XCTAssertEqual(sbi.date, "2026-09-21")
        XCTAssertEqual(sbi.last4, "1234")
        XCTAssertNil(BankMessage.parse("Your card is credited with 500 reward points", today: today))
    }

    func testAHandleNamesThePayeeBeforeItsAt() throws {
        let kotak = try read("Sent Rs.149.00 from Kotak Bank AC X1234 to netflix@okicici on 21-09-26.UPI Ref 562812345678. Not you, https://kotak.com/KBANKT/Fraud")
        XCTAssertEqual(kotak.payee, "netflix")
        XCTAssertEqual(kotak.name, "Netflix")
        let federal = try read("Rs 149.00 debited via UPI on 21-09-2026 10:22:33 to VPA netflix@icici.Ref No 562812345678.Small txns?Use UPI Lite!-Federal Bank")
        XCTAssertEqual(federal.payee, "netflix")
        XCTAssertEqual(federal.date, "2026-09-21")
    }

    func testAPayeeEndsWhereTheCardBegins() throws {
        let app = try read("You've spent ₹149.00 at NETFLIX using your Fi Debit Card ending 1234 on 21 Sep 2026.")
        XCTAssertEqual(app.payee, "NETFLIX")
        XCTAssertEqual(app.amount, 149)
        XCTAssertEqual(app.last4, "1234")
        XCTAssertEqual(app.date, "2026-09-21")
        let amex = try read("Alert: You've spent INR 149.00 on your AMEX card ** 12345 at NETFLIX on 21 September 2026 at 10:22 AM IST. Call 18004190691 if this was not made by you.")
        XCTAssertEqual(amex.payee, "NETFLIX")
        XCTAssertEqual(amex.date, "2026-09-21")
    }

    func testTheOwnAccountAndAStrayLineAreNeverThePayee() throws {
        let credit = try read("Credit Alert!\nRs.500.00 credited to HDFC Bank A/c XX1234 on 21-09-26 from VPA rahul@okaxis (UPI 562812345678)")
        XCTAssertEqual(credit.payee, "rahul")
        XCTAssertEqual(credit.direction, "in")
        let bob = try read("ALERT: INR 149.00 spent on your BOBCARD One Credit Card ending 1234 at NETFLIX on 21-09-2026 10:22:33. Available credit limit is INR 1,23,456.00. Not you? Call 18002250110")
        XCTAssertEqual(bob.payee, "NETFLIX")
        XCTAssertEqual(bob.last4, "1234")
        let mail = try read("Dear Customer,\nRs.149 spent on HDFC Bank Card x1234 at NETFLIX on 2026-09-21.\nNot you? Call 1800\nWarm regards")
        XCTAssertEqual(mail.payee, "NETFLIX")
        let balanceFirst = try read("Avl Bal Rs 500.00. Rs 149.00 debited from A/c XX1234 to NETFLIX")
        XCTAssertEqual(balanceFirst.amount, 149)
    }

    func testANameInBracketsBeatsTheHandle() throws {
        let mail = try read("Rs.250.00 is debited from your account ending 1234 towards VPA cornergrocery@okbank (CORNER GROCERY) on 05-08-26. UPI transaction reference no.: 123456789012")
        XCTAssertEqual(mail.payee, "CORNER GROCERY")
        XCTAssertEqual(mail.name, "Corner Grocery")
        XCTAssertEqual(mail.last4, "1234")
        XCTAssertEqual(mail.date, "2026-08-05")
    }

    func testAMandateNamesWhomItPays() throws {
        let nach = try read("Rs 5000.00 debited from A/c XX1234 on 05-09-26 towards NACH/ACH-DR-HDFC LIFE INS/123456. Avl Bal Rs 10,000.00")
        XCTAssertEqual(nach.payee, "HDFC LIFE INS")
        XCTAssertEqual(nach.name, "Hdfc Life Ins")
        XCTAssertEqual(nach.amount, 5000)
    }

    func testNoPayeeIsSaidPlainly() throws {
        let out = try read("Your A/C XXXXXXX1234 is debited by INR 149.00 on 21/09/26 10:22. New Bal :INR 1,234.00. Team IDFC FIRST Bank")
        XCTAssertEqual(out.payee, "")
        XCTAssertEqual(out.name, "Unnamed charge")
        XCTAssertEqual(out.amount, 149)
        let into = try read("Your A/C XXXXXXX1234 is credited by INR 149.00 on 21/09/26 10:22. New Bal :INR 1,234.00. Team IDFC FIRST Bank")
        XCTAssertEqual(into.payee, "")
        XCTAssertEqual(into.name, "Unnamed money in")
    }

    func testAnAmountNotYetTakenIsNoCharge() {
        XCTAssertNil(BankMessage.parse("123456 is the OTP for txn of INR 149.00 at NETFLIX on card XX1234. Do not share.", today: today))
        XCTAssertNil(BankMessage.parse("Rs.149.00 will be debited from A/c XX1234 on 25-09-26 for NETFLIX mandate", today: today))
        XCTAssertNil(BankMessage.parse("Your OTP for transaction of Rs 149.00 at NETFLIX is 123456.", today: today))
        for warned in ["Rs.149 spent on HDFC Bank Card x1234 at NETFLIX on 2026-09-21. Never share your OTP or PIN.",
                       "Rs.149 debited from a/c XX1234 to NETFLIX. Do not share OTP for any reason"] {
            XCTAssertEqual(BankMessage.parse(warned, today: today)?.payee, "NETFLIX", "a warning about passwords does not unmake a charge")
        }
    }

    func testTheOwnersOwnPaymentArrivingIsNeverMoneyIn() throws {
        XCTAssertNil(BankMessage.parse("Payment of Rs 5,000.00 received towards your HDFC Bank Credit Card XX1234 on 21-09-26.", today: today),
                     "a card bill paid is a movement between the owner's own accounts")
        let loan = try read("Payment of Rs 5,000.00 received towards your Home Loan A/c XX1234 on 05-09-26.")
        XCTAssertEqual(loan.direction, "out")
        XCTAssertEqual(loan.amount, 5000)
        let paidIn = try read("Payment of Rs 500.00 received from RAHUL KUMAR in your A/c XX1234 on 21-09-26.")
        XCTAssertEqual(paidIn.direction, "in")
    }

    func testAPaymentTheBankTurnedAwayIsNoCharge() {
        XCTAssertNil(BankMessage.parse("Txn of Rs.149.00 on HDFC Bank Card x1234 at NETFLIX is declined due to insufficient funds.", today: today))
        XCTAssertNil(BankMessage.parse("Your UPI transaction of Rs 149.00 to NETFLIX was unsuccessful. Any amount debited will be reversed.", today: today))
        XCTAssertNil(BankMessage.parse("Your payment of INR 149.00 to NETFLIX could not be processed.", today: today))
    }

    func testAWarningUnderAChargeAlreadyTakenUnmakesNothing() throws {
        let charges: [(text: String, amount: Double, payee: String)] = [
            ("Rs.500.00 debited from A/c XX1234 on 21-09-26 to VPA swiggy@ybl (UPI Ref 526012345678). If txn failed or not done by you call 18001234 -XYZ Bank", 500, "swiggy"),
            ("Rs 500.00 debited from A/c XX1234 to SWIGGY on 21-09-26. If declined, amount will be reversed in 3 days.", 500, "SWIGGY"),
            ("Your a/c XX1234 is debited for Rs.10,000.00 on 21-09-26 and a/c XX5678 credited (IMPS Ref no 526012345678). If the transaction has failed, amount will be reversed within 2 days.", 10_000, ""),
            ("Rs 2000.00 withdrawn from A/c XX1234 at ATM on 21-09-26. Avl Bal Rs 8,000.00. Charges will be deducted beyond 5 free txns per month.", 2000, "ATM"),
            ("USD 20.00 spent on HDFC Bank Card x1234 at OPENAI on 2026-09-21:10:22:33. Cross currency markup will be charged as applicable.", 20, "OPENAI"),
            ("Rs 500.00 debited from A/c XX1234 to SWIGGY on 21-09-26. Avl Bal Rs 900. Your a/c will be debited with charges if balance falls below Rs 1000.", 500, "SWIGGY"),
            ("Rs.149 debited from a/c XX1234 to NETFLIX on 21-09-26. OTP is confidential, never share it.", 149, "NETFLIX"),
            ("Rs 500.00 transferred from A/c XX1234 to RAHUL KUMAR on 21-09-26. Never share OTP with anyone.", 500, "RAHUL KUMAR"),
            ("Rs.500 Dr. from A/C XXXXXX1234 and Cr. to swiggy@ybl. Ref:526012345678. AvlBal:Rs1000(2026:09:21 10:22:33). Never share OTP/PIN -BOB", 500, "swiggy"),
            ("Rs 149.00 debited from A/c XX1234 towards NETFLIX as one time mandate on 21-09-26.", 149, "NETFLIX"),
        ]
        for charge in charges {
            let taken = try read(charge.text)
            XCTAssertEqual(taken.direction, "out", charge.text)
            XCTAssertEqual(taken.amount, charge.amount, charge.text)
            XCTAssertEqual(taken.payee, charge.payee, charge.text)
            XCTAssertEqual(taken.last4, "1234", charge.text)
        }
        XCTAssertNil(BankMessage.parse("Your OTP for purchase of Rs 149.00 at NETFLIX is 123456.", today: today))
    }

    func testMoneyGivenBackIsMoneyIn() throws {
        let given = [
            "Dear Customer, your txn of Rs.149.00 on 20-09-26 has failed and the amount debited has been credited back to your A/c XX1234.",
            "Rs 149.00 credited to A/c XX1234 on 21-09-26 towards reversal of declined UPI txn 562812345678.",
            "Refund of Rs 149.00 for your declined transaction at NETFLIX has been credited to your Card XX1234 on 21-09-26.",
            "Refund of Rs 149.00 for your purchase at AMAZON has been credited to your Card XX1234 on 21-09-26.",
            "Dear Customer, Rs 149.00 debited from your A/c XX1234 on 20-09-26 for UPI txn 562812345678 has been reversed and credited back on 21-09-26.",
            "Cashback of Rs 50.00 credited to A/c XX1234 for your UPI payment sent to SWIGGY.",
            "Rs 500.00 credited to your Prepaid Card XX1234 on 21-09-26 from RAHUL KUMAR.",
            "Rs 5,000.00 credited to A/c XX1234 on 21-09-26 from ACME CORP. Bank representatives never ask for PIN.",
            "Interest of Rs 312.00 paid on your FD/SB A/c XX1234 on 21-09-26.",
        ]
        for text in given { XCTAssertEqual(try read(text).direction, "in", text) }
        let paid = try read("ICICI Bank Acct XX123 debited for Rs 149.00 on 21-Sep-26; NETFLIX credited. UPI:562812345678.")
        XCTAssertEqual(paid.direction, "out")
        XCTAssertEqual(try read("Rs 500 spent at SWIGGY on Card XX1234. Cashback of Rs 50 will be credited in 3 days").direction, "out")
    }

    func testACurrencyOrATrailingVerbIsNeverAPayee() throws {
        let bare = try read("Your A/C XXXXXXX1234 is debited by Rs.149.00 on 21/09/26 10:22. New Bal :INR 1,234.00. Team IDFC FIRST Bank")
        XCTAssertEqual(bare.payee, "")
        XCTAssertEqual(bare.name, "Unnamed charge")
        let sbi = try read("Dear SBI User, your A/c X1234-credited by Rs.500 on 21Sep26 transfer from RAHUL KUMAR Ref No 562812345678 -SBI")
        XCTAssertEqual(sbi.payee, "RAHUL KUMAR")
        XCTAssertEqual(sbi.direction, "in")
        XCTAssertEqual(sbi.amount, 500)
        for ending in ["Not you? Call 18001234 to report", "Click hdfcbk.io/a to know more"] {
            let credit = try read("Rs 500.00 credited to A/c XX1234 on 21-09-26 from RAHUL KUMAR. " + ending)
            XCTAssertEqual(credit.payee, "RAHUL KUMAR", ending)
        }
        let neft = try read("Update! INR 5,000.00 deposited in HDFC Bank A/c XX1234 on 21-SEP-26 for NEFT Cr-ICIC0000123-ACME CORP-ROHIT-ICICN12345. Avl bal INR 15,000.00. Cheque deposits in A/C are subject to clearing")
        XCTAssertEqual(neft.payee, "ACME CORP")
        XCTAssertEqual(neft.direction, "in")
        XCTAssertEqual(neft.amount, 5000)
    }

    func testARailFieldIsReadOnlyWhenItIsOne() throws {
        let payees: [(text: String, payee: String)] = [
            ("Rs 149.00 debited from A/c XX1234 towards NETFLIX for UPI-Mandate, RRN 562812345678-ICICI Bank", "NETFLIX"),
            ("Rs 499.00 debited from A/c XX1234 on 21-09-26 for POS/ECOM purchase at AMAZON. Avl Bal Rs 1,000.00", "AMAZON"),
            ("Rs 10,000.00 credited to A/c XX1234 by NEFT from ACME CORP on 21-09-26", "ACME CORP"),
            ("Rs 10,000.00 credited to A/c XX1234 by NEFT-N123456789 from ACME CORP on 21-09-26", "ACME CORP"),
            ("INR 149.00 debited\nA/c no. XX1234\n21-09-26, 10:22:33\nUPI/P2M/562812345678/M/S SHARMA TRADERS\nNot you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank", "M/S SHARMA TRADERS"),
            ("INR 149.00 debited from HDFC Bank XX1234 on 21-SEP-26. Info: UPI-562812345678-D-MART. Avl bal INR 10,000.00", "D-MART"),
            ("INR 149.00 debited\nA/c no. XX1234\n21-09-26, 10:22:33\nUPI/P2M/562812345678/7-ELEVEN\nAxis Bank", "7-ELEVEN"),
            ("Rs 149.00 debited via UPI on 21-09-2026 10:22:33. Ref No 562812345678. Small txns? Use UPI-Lite! -Federal Bank", ""),
            ("Update: INR 2,500.00 debited from HDFC Bank XX1234 on 12-SEP-26.Info: UPI-425512345678-SWIGGY.Avl bal INR 10,000.00", "SWIGGY"),
        ]
        for one in payees { XCTAssertEqual(try read(one.text).payee, one.payee, one.text) }
        XCTAssertEqual(try read(payees[4].text).name, "Sharma Traders")
        let axis = { (field: String) in "INR 149.00 debited\nA/c no. XX1234\n21-09-26, 10:22:33\n\(field)\nAxis Bank" }
        XCTAssertEqual(try read(axis("UPI/P2M/562812345678/Zomato ltd")).payee, "Zomato ltd", "the bank's own field may print a name in any case")
        XCTAssertEqual(try read(axis("UPI/P2M/562812345678/KOTAK MAHINDRA BANK")).payee, "KOTAK MAHINDRA BANK", "a bank right after the reference is the payee")
        let undone = try read("Your UPI transaction of Rs 149.00 to NETFLIX was unsuccessful. Rs 149.00 debited from A/c XX1234 has been reversed.")
        XCTAssertEqual(undone.payee, "NETFLIX")
        XCTAssertEqual(undone.direction, "in")
    }

    func testAMerchantNamedLikeAWarningIsStillAMerchant() throws {
        let spend = { (payee: String) in "Rs.149 spent on HDFC Bank Card x1234 at \(payee) on 2026-09-21:10:22:33. Not you? Call 18002586161" }
        for payee in ["ACT FIBERNET", "YOU BROADBAND", "SBI CARD PAYMENT", "ACC CEMENT", "CARD FACTORY", "CALL OF DUTY STORE",
                      "BLOCK BUSTER VIDEO", "INOX1234", "D-MART", "COCA-COLA", "7-ELEVEN"] {
            XCTAssertEqual(try read(spend(payee)).payee, payee)
        }
        for payee in ["24SEVEN", "1MG", "99ACRES", "INOX1234"] {
            let named = try read(spend(payee))
            XCTAssertEqual(named.payee, payee)
            XCTAssertEqual(named.name, payee, "a name that is half digits is still a name")
        }
        let own = try read("INR 149.00 spent on your BOBCARD One Credit Card ending 1234 on 21-09-2026. Not you? Call 18002250110")
        XCTAssertEqual(own.payee, "", "the owner's own card is no payee")
    }
}
