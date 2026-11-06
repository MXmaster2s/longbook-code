import XCTest
@testable import DesignSystem

/// The one card's rulings, held by value: Figma's data/12 is the ramp's twelfth, counted from one.
final class KindCardTests: XCTestCase {
    func testBandsAreTheFinalColours() {
        XCTAssertEqual(LBCardKind.charge.ink, LBColorValue(0x2D913F))
        XCTAssertEqual(LBCardKind.earning.ink, LBColorValue(0x9DB93E))
        XCTAssertEqual(LBCardKind.transfer.ink, LBColor.skyTint)
        XCTAssertEqual(LBCardKind.commitment.ink, LBColor.brand)
        XCTAssertEqual(LBCardKind.people.ink, LBColorValue(0xDD86DA))
        XCTAssertEqual(LBCardKind.account.ink, LBColorValue(0xE69825))
    }

    func testAReportWearsItsOwnBandAndADocument() {
        XCTAssertEqual(LBCardKind.report.ink, LBColorValue(0x8A94A6))
        XCTAssertNotEqual(LBCardKind.report.ink, LBCardKind.commitment.ink)
        XCTAssertEqual(LBCardKind.report.symbol, "doc.text")
    }

    func testEveryBandRendersItsLightSibling() {
        for kind in LBCardKind.allCases {
            XCTAssertEqual(LBPalette.lightCounterpart(of: kind.ink(in: .dark)), kind.ink(in: .light), kind.rawValue)
        }
    }

    func testEveryBandIsAMarkOnTheCard() {
        for palette in LBPalette.all {
            for kind in LBCardKind.allCases {
                XCTAssertGreaterThanOrEqual(kind.ink(in: palette).contrast(with: palette.card), 3, "\(kind) on \(palette.name)")
            }
        }
    }

    func testChargeIsTheOppositeOfEarning() {
        XCTAssertEqual(LBCardKind.charge.symbol, "arrow.up.right")
        XCTAssertEqual(LBCardKind.earning.symbol, "arrow.down.left")
        XCTAssertEqual(LBGlyph.charge, LBGlyph.expense)
    }

    func testEveryMarkHasAWordForAScreenReader() {
        XCTAssertNil(LBCardState.plain.word)
        XCTAssertEqual(LBCardState.kept.word, "Kept")
        XCTAssertEqual(LBCardState.removed.word, "Removed")
        XCTAssertEqual(LBCardState.paid.word, "Paid")
    }

    func testEveryBadgeToneSitsOnThePausedBackground() {
        for palette in LBPalette.all {
            for tone in LBBadgeTone.allCases {
                XCTAssertEqual(tone.inks(in: palette).fill, palette.chrome)
            }
        }
    }
}
