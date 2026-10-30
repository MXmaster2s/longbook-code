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
}
