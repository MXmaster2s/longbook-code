// A charge's note under its label: a statement line reads as one, anything else as a note.
import XCTest
@testable import LongbookCore

final class ChargeNoteTests: XCTestCase {
    func testAStatementLineIsLabelledWithTheRestAsItsValue() {
        let row = ChargeNote.labelled("Statement line: 12 SEP AMAZON PAY 1,299.00")
        XCTAssertEqual(row?.label, "Statement line")
        XCTAssertEqual(row?.value, "12 SEP AMAZON PAY 1,299.00")
        XCTAssertTrue(ChargeNote.isStatementLine("Statement line: x"))
    }

    func testAnyOtherNoteIsANote() {
        let row = ChargeNote.labelled("  Paid in cash ")
        XCTAssertEqual(row?.label, "Note")
        XCTAssertEqual(row?.value, "Paid in cash")
        XCTAssertFalse(ChargeNote.isStatementLine("Paid in cash"))
    }

    func testAnEmptyOrBarePrefixNoteIsNothing() {
        XCTAssertNil(ChargeNote.labelled(nil))
        XCTAssertNil(ChargeNote.labelled("   "))
        XCTAssertNil(ChargeNote.labelled("Statement line: "))
        XCTAssertNil(ChargeNote.value(""))
    }

    func testTheStoredNoteCarriesThePrefixBackOnlyWhenTheRowHadIt() {
        XCTAssertEqual(ChargeNote.stored(" AMAZON ", statementLine: true), "Statement line: AMAZON")
        XCTAssertEqual(ChargeNote.stored("AMAZON", statementLine: false), "AMAZON")
        XCTAssertEqual(ChargeNote.stored("  ", statementLine: true), "")
    }

    func testAStatementLineAndNotesComeApart() {
        let held = ChargeNote.parts("Statement line: UPI-NETFLIX\nShared with Asha\nRenews in May")
        XCTAssertEqual(held.statementLine, "UPI-NETFLIX")
        XCTAssertEqual(held.notes, "Shared with Asha\nRenews in May")
    }

    func testANoteWithoutTheLabelIsAllTheOwnersOwn() {
        let held = ChargeNote.parts("Paid in cash\nStatement line: later")
        XCTAssertNil(held.statementLine)
        XCTAssertEqual(held.notes, "Paid in cash\nStatement line: later")
    }

    func testAnEmptyLabelHoldsNoLine() {
        XCTAssertNil(ChargeNote.parts("Statement line: ").statementLine)
        XCTAssertEqual(ChargeNote.parts("Statement line: \nCash").notes, "Cash")
        XCTAssertNil(ChargeNote.parts(nil).statementLine)
    }

    func testJoinedPutsTheLineFirstAndNotesAfter() {
        XCTAssertEqual(ChargeNote.joined(statementLine: " AMAZON ", notes: " Gift "), "Statement line: AMAZON\nGift")
        XCTAssertEqual(ChargeNote.joined(statementLine: "AMAZON", notes: ""), "Statement line: AMAZON")
        XCTAssertEqual(ChargeNote.joined(statementLine: "", notes: "Gift"), "Gift")
        XCTAssertEqual(ChargeNote.joined(statementLine: nil, notes: nil), "")
    }

    func testTheLineStaysOnOneLine() {
        XCTAssertEqual(ChargeNote.joined(statementLine: "AMAZON\nPAY", notes: nil), "Statement line: AMAZON PAY")
    }

    func testPartsAndJoinedRoundTrip() {
        for note in ["Statement line: A\nB\nC", "Statement line: A", "B\nC"] {
            let held = ChargeNote.parts(note)
            XCTAssertEqual(ChargeNote.joined(statementLine: held.statementLine, notes: held.notes), note)
        }
    }

    func testAOneLineSurfaceReadsTheLineOverTheNotes() {
        XCTAssertEqual(ChargeNote.value("Statement line: A\nB"), "A")
        XCTAssertEqual(ChargeNote.rows("Statement line: A\nB").map(\.label), ["Statement line", "Note"])
    }
}
