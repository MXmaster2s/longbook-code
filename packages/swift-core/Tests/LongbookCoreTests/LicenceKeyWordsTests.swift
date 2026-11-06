// What the licence key sheet says: a pasted key is sent clean, Activate waits for a key, and a
// refusal is the server's own words or a fallback with its status.
import XCTest
@testable import LongbookCore

final class LicenceKeyWordsTests: XCTestCase {
    func testPastedKeyIsTrimmed() {
        XCTAssertEqual(LicenceKeyWords.trimmed("  LB-1234-ABCD\n"), "LB-1234-ABCD")
    }

    func testActivateWaitsForAKey() {
        XCTAssertFalse(LicenceKeyWords.canClaim(""))
        XCTAssertFalse(LicenceKeyWords.canClaim(" \n\t"))
        XCTAssertTrue(LicenceKeyWords.canClaim(" k "))
    }

    func testARefusalIsTheServersOwnWords() {
        let inUse = "This licence key is already in use on another longbook account."
        XCTAssertEqual(LicenceKeyWords.refusal(why: inUse, status: 409), inUse)
    }

    func testNoWordsFallBackToTheStatus() {
        XCTAssertEqual(LicenceKeyWords.refusal(why: nil, status: 502), "The licence key could not be activated (502).")
        XCTAssertEqual(LicenceKeyWords.refusal(why: "", status: 500), "The licence key could not be activated (500).")
    }
}
