import SwiftUI
import XCTest
@testable import DesignSystem

/// The state washes are the Figma variables for LB063, one value per theme. A change here
/// is a change to the design, so it should be made there first.
final class ControlStateTests: XCTestCase {
    func testHoverIsAFaintWashThatRunsTowardsTheReader() {
        XCTAssertEqual(LBState.hover.value(in: .dark).white, 1)
        XCTAssertEqual(LBState.hover.value(in: .dark).alpha, 0.07)
        XCTAssertEqual(LBState.hover.value(in: .light).white, 0)
        XCTAssertEqual(LBState.hover.value(in: .light).alpha, 0.05)
    }

    func testPressedAlwaysDarkensAndOutweighsHover() {
        for scheme in [ColorScheme.dark, .light] {
            let press = LBState.pressed.value(in: scheme)
            XCTAssertEqual(press.white, 0, "a press darkens in \(scheme)")
            XCTAssertGreaterThan(press.alpha, LBState.hover.value(in: scheme).alpha)
        }
        XCTAssertEqual(LBState.pressed.value(in: .dark).alpha, 0.25)
        XCTAssertEqual(LBState.pressed.value(in: .light).alpha, 0.12)
    }

    func testAnInactiveSelectionIsGrey() {
        XCTAssertEqual(LBState.selectionInactive.value(in: .dark).white, 1)
        XCTAssertEqual(LBState.selectionInactive.value(in: .dark).alpha, 0.12)
        XCTAssertEqual(LBState.selectionInactive.value(in: .light).white, 0)
        XCTAssertEqual(LBState.selectionInactive.value(in: .light).alpha, 0.08)
    }

    func testDisabledAndFocusFollowTheGuidelines() {
        XCTAssertEqual(LBState.disabledOpacity, 0.4)
        XCTAssertEqual(LBState.focusRingWidth, 3)
    }
}
