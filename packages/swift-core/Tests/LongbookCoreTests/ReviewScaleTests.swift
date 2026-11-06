// The review's diff at a statement's size: a thousand added commitments and their charges
// diffed in well under a second, so the Proposals screen opens at once.
import XCTest
@testable import LongbookCore

final class ReviewScaleTests: XCTestCase {
    func testAThousandRowDiffIsFoundInUnderASecond() throws {
        let today = LB.parseDate("2026-10-30")!
        let vault = ChargeIndexTests.scaleVault(today: today)
        let bytes = try JSONEncoder().encode(vault)
        let new = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var old = new
        old["commitments"] = Array((new["commitments"] as? [[String: Any]] ?? []).prefix(5))
        old["charges"] = Array((new["charges"] as? [[String: Any]] ?? []).prefix(5))
        let start = CFAbsoluteTimeGetCurrent()
        let diff = vaultDiff(from: old, to: new)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("TIMING vaultDiff of ~1000 commitments + ~1500 charges: \(Int(ms)) ms")
        XCTAssertEqual(diff.first { $0.kind == "commitments" }?.added.count, 995)
        XCTAssertGreaterThan(diff.first { $0.kind == "charges" }?.added.count ?? 0, 1400)
        XCTAssertLessThan(ms, 1000)
    }
}
