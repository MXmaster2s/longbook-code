import XCTest
@testable import DesignSystem

/// The Mac's state washes, as approved for both appearances: white on the dark canvas and
/// black on paper, except the press, which darkens in both.
final class StateWashTests: XCTestCase {
    func testDarkWashes() {
        XCTAssertEqual(LBColor.stateHover, LBWash(0xFFFFFF, opacity: 0.07))
        XCTAssertEqual(LBColor.statePressed, LBWash(0x000000, opacity: 0.25))
        XCTAssertEqual(LBColor.stateSelectionInactive, LBWash(0xFFFFFF, opacity: 0.12))
    }

    func testLightWashes() {
        XCTAssertEqual(LBColorLight.stateHover, LBWash(0x000000, opacity: 0.05))
        XCTAssertEqual(LBColorLight.statePressed, LBWash(0x000000, opacity: 0.12))
        XCTAssertEqual(LBColorLight.stateSelectionInactive, LBWash(0x000000, opacity: 0.08))
    }

    func testEveryDarkWashHasOneLightSibling() {
        let darks = LBWash.counterparts.map(\.dark)
        XCTAssertEqual(Set(darks.map { "\($0.base.red)-\($0.opacity)" }).count, darks.count)
        XCTAssertEqual(LBWash.counterparts.count, 3)
    }

    /// A hover is quieter than a press on every surface, so the two never read alike.
    func testHoverIsLighterThanPress() {
        XCTAssertLessThan(LBColor.stateHover.opacity, LBColor.statePressed.opacity)
        XCTAssertLessThan(LBColorLight.stateHover.opacity, LBColorLight.statePressed.opacity)
    }
}
