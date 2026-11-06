// Account says how a person signed in, in the words the three sign-in doors use.
import XCTest
@testable import LongbookCore

final class SignInMethodTests: XCTestCase {
    func testTheThreeDoorsAreNamed() {
        XCTAssertEqual(AuthViewModel.methodWords(provider: "apple"), "Apple")
        XCTAssertEqual(AuthViewModel.methodWords(provider: "google"), "Google")
        XCTAssertEqual(AuthViewModel.methodWords(provider: "email"), "email")
    }

    func testAProviderLongbookDoesNotOfferIsNotNamed() {
        XCTAssertNil(AuthViewModel.methodWords(provider: "github"))
        XCTAssertNil(AuthViewModel.methodWords(provider: nil))
    }
}
