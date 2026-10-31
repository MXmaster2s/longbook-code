import XCTest
@testable import LongbookCore

final class BrowserSignInTests: XCTestCase {
    private func cancelled(_ url: String) -> Bool {
        BrowserSignInSession.cancelled(URL(string: url)!)
    }

    func testACancelOnTheProviderPageReadsAsCancelled() {
        XCTAssertTrue(cancelled("longbook://auth/callback?error=user_cancelled_authorize"))
        XCTAssertTrue(cancelled("longbook://auth/callback?error=access_denied&error_description=User%20cancelled%20the%20request"))
        XCTAssertTrue(cancelled("longbook://auth/callback#error=server_error&error_code=user_cancelled_authorize"))
    }

    func testACodeOrAnotherRefusalDoesNot() {
        XCTAssertFalse(cancelled("longbook://auth/callback?code=abc"))
        XCTAssertFalse(cancelled("longbook://auth/callback?error=server_error&error_description=Unable%20to%20exchange"))
    }
}
