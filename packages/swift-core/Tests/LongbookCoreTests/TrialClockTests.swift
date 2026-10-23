// The trial start a device honours: never later than the earliest it has seen.
import XCTest
@testable import LongbookCore

final class TrialClockTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_700_000_000)
    private let later = Date(timeIntervalSince1970: 1_700_500_000)

    func testNoDeviceStampMeansTheServersStart() {
        XCTAssertEqual(TrialClock.effectiveStart(server: later, device: nil), later)
    }

    func testAnEarlierDeviceStampOutranksANewerAccount() {
        XCTAssertEqual(TrialClock.effectiveStart(server: later, device: earlier), earlier)
    }

    func testAnEarlierServerStartOutranksALaterStamp() {
        XCTAssertEqual(TrialClock.effectiveStart(server: earlier, device: later), earlier)
    }
}
