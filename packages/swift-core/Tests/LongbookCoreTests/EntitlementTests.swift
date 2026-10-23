// The trial countdown the ribbon reads, and the Cloud rule the gates read. The read-only
// decision itself is the server's; what's tested here is that the number shown to someone
// can never mislead them, and that Cloud follows the server's has_cloud exactly.
import XCTest
@testable import LongbookCore

final class EntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    private func state(endsIn days: Double?, licence: Bool = false) -> EntitlementState {
        EntitlementState(
            signedIn: true,
            trialEndsAt: days.map { now.addingTimeInterval($0 * 86_400) },
            hasLicence: licence,
            readOnly: false
        )
    }

    private func day(_ days: Double) -> Date { now.addingTimeInterval(days * 86_400) }

    func testAPartDayCountsAsAWholeDayLeft() {
        XCTAssertEqual(state(endsIn: 3.2).trialDaysLeft(now), 4)
        XCTAssertEqual(state(endsIn: 0.1).trialDaysLeft(now), 1)
    }

    func testALapsedTrialReportsZeroRatherThanANegative() {
        XCTAssertEqual(state(endsIn: -5).trialDaysLeft(now), 0)
    }

    func testALicenceEndsTheCountdownEntirely() {
        XCTAssertNil(state(endsIn: 2, licence: true).trialDaysLeft(now))
    }

    func testNoTrialClockCountsNothing() {
        XCTAssertNil(state(endsIn: nil).trialDaysLeft(now))
        XCTAssertNil(EntitlementState.signedOut.trialDaysLeft(now))
    }

    func testSignedOutIsNeverReadOnly() {
        XCTAssertFalse(EntitlementState.signedOut.readOnly)
    }

    // MARK: Cloud

    func testAnActiveSubscriptionWithTimeLeftHasCloud() {
        XCTAssertTrue(EntitlementState.cloud(status: "active", expiresAt: day(10), trialEndsAt: day(-30), now: now))
        XCTAssertTrue(EntitlementState.cloud(status: "active", expiresAt: day(10), trialEndsAt: nil, now: now))
    }

    func testTheGracePeriodKeepsCloud() {
        XCTAssertTrue(EntitlementState.cloud(status: "grace", expiresAt: day(3), trialEndsAt: day(-30), now: now))
    }

    func testARunOutOrLapsedSubscriptionHasNoCloud() {
        XCTAssertFalse(EntitlementState.cloud(status: "active", expiresAt: day(-1), trialEndsAt: day(-30), now: now))
        XCTAssertFalse(EntitlementState.cloud(status: "active", expiresAt: nil, trialEndsAt: day(-30), now: now))
        for status in ["billing_retry", "expired", "revoked"] {
            XCTAssertFalse(EntitlementState.cloud(status: status, expiresAt: day(10), trialEndsAt: day(-30), now: now), status)
        }
    }

    func testTheTrialCoversCloudUntilItEnds() {
        XCTAssertTrue(EntitlementState.cloud(status: nil, expiresAt: nil, trialEndsAt: day(3), now: now))
        XCTAssertFalse(EntitlementState.cloud(status: nil, expiresAt: nil, trialEndsAt: day(-1), now: now))
        XCTAssertFalse(EntitlementState.cloud(status: nil, expiresAt: nil, trialEndsAt: nil, now: now))
    }

    func testAnEndedSubscriptionStillHasCloudWhileTheTrialRuns() {
        XCTAssertTrue(EntitlementState.cloud(status: "expired", expiresAt: day(-1), trialEndsAt: day(2), now: now))
    }

    func testSignedOutHasNoCloudAndNoSubscription() {
        XCTAssertFalse(EntitlementState.signedOut.hasCloud)
        XCTAssertNil(EntitlementState.signedOut.cloudStatus)
        XCTAssertNil(EntitlementState.signedOut.cloudExpiresAt)
    }

    func testTheCacheRoundTripsTheCloudFields() throws {
        var full = state(endsIn: 2)
        full.hasCloud = true
        full.cloudStatus = "active"
        full.cloudExpiresAt = day(20)
        full.cloudAutoRenew = true
        let back = try JSONDecoder().decode(EntitlementState.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(back, full)
    }
}
