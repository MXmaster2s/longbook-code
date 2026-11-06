import CoreText
import XCTest
@testable import DesignSystem

/// The type contract. Both faces are variable and both default to Thin, so a role that
/// stopped setting its axes would silently draw wrong rather than fail — these tests are
/// what makes that loud.
final class TypographyTests: XCTestCase {
    private let loader = LBFontLoader.shared

    func testEveryRoleResolvesToABundledFace() {
        for style in LBTextStyle.allCases {
            XCTAssertNotNil(loader.ctFont(style), "\(style) fell back to the system face")
        }
    }

    func testEveryRoleSetsItsExactWeight() {
        for style in LBTextStyle.allCases {
            guard let font = loader.ctFont(style),
                  let variation = CTFontCopyVariation(font) as? [CFNumber: Any]
            else { return XCTFail("no variation for \(style)") }
            let weight = variation[0x77676874 as CFNumber] as? CGFloat
            XCTAssertEqual(weight, style.weight, "\(style) drew at the wrong weight")
            XCTAssertGreaterThanOrEqual(style.weight, 400, "\(style) is below the thin floor")
        }
    }

    /// Fraunces' named instances are all cut for 9pt. A 64pt headline must ask for display
    /// shapes explicitly or it draws text shapes at headline size.
    func testFrauncesRolesSetOpticalSizeToTheirDrawnSize() {
        for style in LBTextStyle.allCases where style.face == .fraunces {
            guard let font = loader.ctFont(style),
                  let variation = CTFontCopyVariation(font) as? [CFNumber: Any]
            else { return XCTFail("no variation for \(style)") }
            let optical = variation[0x6F70737A as CFNumber] as? CGFloat
            XCTAssertEqual(optical, min(max(style.size, 9), 144), "\(style) drew at the wrong optical size")
        }
    }

    /// Columnar amounts must line up digit for digit. A face swap that lost tabular figures
    /// would show up as ragged columns in the app and as a failure here first.
    func testColumnarNumberRolesHaveTabularFigures() {
        for style in LBTextStyle.allCases where style.tabularFigures {
            guard let font = loader.ctFont(style) else { return XCTFail("no font for \(style)") }
            XCTAssertEqual(widthSpread(of: "1111111111", in: font), widthSpread(of: "9999999999", in: font), accuracy: 0.01,
                           "\(style) does not draw tabular figures")
        }
    }

    /// The reverse guarantee: the standalone hero amount is Fraunces precisely because it
    /// never lines up against anything. If Fraunces ever ships tabular figures, this fails
    /// and the hybrid split can be revisited.
    func testFrauncesStillLacksTabularFigures() {
        guard let font = loader.ctFont(.numberDisplay) else { return XCTFail("no font") }
        XCTAssertNotEqual(widthSpread(of: "1111111111", in: font), widthSpread(of: "9999999999", in: font), accuracy: 0.01)
    }

    private func widthSpread(of text: String, in font: CTFont) -> Double {
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }
}
