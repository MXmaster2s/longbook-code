// An Apple credential state ends the session only when it arrives without an error.
import AuthenticationServices
import XCTest
@testable import LongbookCore

final class AppleCredentialStateTests: XCTestCase {
    private struct Offline: Error {}

    private func out(_ state: ASAuthorizationAppleIDProvider.CredentialState, error: Error? = nil, own: Bool = true) -> Bool {
        AuthViewModel.shouldSignOut(state: state, error: error, ownsAppleSignIn: own)
    }

    func testRevokedWithNoErrorSignsOut() {
        XCTAssertTrue(out(.revoked, own: true))
        XCTAssertTrue(out(.revoked, own: false))
    }

    func testRevokedWithAnErrorDoesNot() {
        XCTAssertFalse(out(.revoked, error: Offline()))
    }

    func testNotFoundWithNoErrorSignsOutOnlyWhenThisDeviceSignedInWithApple() {
        XCTAssertTrue(out(.notFound, own: true))
        XCTAssertFalse(out(.notFound, own: false))
    }

    func testNotFoundWithAnErrorNeverSignsOut() {
        XCTAssertFalse(out(.notFound, error: Offline(), own: true))
        XCTAssertFalse(out(.notFound, error: Offline(), own: false))
    }

    func testAuthorizedAndTransferredNeverSignOut() {
        for state in [ASAuthorizationAppleIDProvider.CredentialState.authorized, .transferred] {
            XCTAssertFalse(out(state, own: true))
            XCTAssertFalse(out(state, own: false))
            XCTAssertFalse(out(state, error: Offline(), own: true))
        }
    }
}
