import XCTest
@testable import DesignSystem

/// One colour to one kind, chosen from twenty that read in both palettes.
final class CardColoursTests: XCTestCase {
    private func fresh() -> (LBCardColours, UserDefaults) {
        let name = "card-colours-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (LBCardColours(defaults: defaults), defaults)
    }

    private func swatch(_ id: String) -> LBCardSwatch { LBCardSwatch.all.first { $0.id == id }! }

    func testThereAreTwentyAndTheyIncludeTodaysBands() {
        XCTAssertEqual(LBCardSwatch.all.count, 20)
        XCTAssertEqual(Set(LBCardSwatch.all.map(\.id)).count, 20)
        let (colours, _) = fresh()
        XCTAssertEqual(colours.swatch(for: .charge).dark, LBColorValue(0x2D913F))
        XCTAssertEqual(colours.swatch(for: .earning).dark, LBColorValue(0x9DB93E))
        XCTAssertEqual(colours.swatch(for: .transfer).dark, LBColor.skyTint)
        XCTAssertEqual(colours.swatch(for: .commitment).dark, LBColor.brand)
        XCTAssertEqual(colours.swatch(for: .people).dark, LBColorValue(0xDD86DA))
        XCTAssertEqual(colours.swatch(for: .account).dark, LBColorValue(0xE69825))
    }

    func testEveryColourIsAMarkOnTheCardInBothPalettes() {
        for palette in LBPalette.all {
            for swatch in LBCardSwatch.all {
                XCTAssertGreaterThanOrEqual(swatch.value(in: palette).contrast(with: palette.card), 3, "\(swatch.name) on \(palette.name)")
            }
        }
    }

    func testEveryTwoColoursCanBeToldApartInBothPalettes() {
        for palette in LBPalette.all {
            for (i, a) in LBCardSwatch.all.enumerated() {
                for b in LBCardSwatch.all[(i + 1)...] {
                    XCTAssertGreaterThan(a.value(in: palette).perceptualDistance(to: b.value(in: palette)), 7, "\(a.name), \(b.name) on \(palette.name)")
                }
            }
        }
    }

    func testEveryColourRendersItsLightSibling() {
        for swatch in LBCardSwatch.all {
            XCTAssertEqual(LBPalette.lightCounterpart(of: swatch.dark), swatch.light, swatch.name)
        }
    }

    func testNoTwoKindsStartOnOneColour() {
        let (colours, _) = fresh()
        XCTAssertEqual(Set(LBCardKind.allCases.map { colours.swatch(for: $0).id }).count, LBCardKind.allCases.count)
    }

    func testTwoKindsCannotHoldOneColour() {
        let (colours, _) = fresh()
        let held = colours.swatch(for: .charge)
        XCTAssertFalse(colours.assign(held, to: .account), "another kind holds it")
        XCTAssertEqual(colours.swatch(for: .account).id, "amber", "and nothing moved")
        XCTAssertEqual(colours.holder(of: held), .charge)

        XCTAssertTrue(colours.assign(swatch("coral"), to: .account))
        XCTAssertFalse(colours.assign(swatch("coral"), to: .people))
        XCTAssertEqual(colours.holder(of: swatch("coral")), .account)
        XCTAssertNil(colours.holder(of: swatch("amber")), "the colour it left is free")
        XCTAssertTrue(colours.assign(swatch("amber"), to: .people))
        XCTAssertEqual(Set(LBCardKind.allCases.map { colours.swatch(for: $0).id }).count, LBCardKind.allCases.count)
    }

    func testAKindKeepingItsOwnColourIsNotARefusal() {
        let (colours, _) = fresh()
        XCTAssertTrue(colours.assign(colours.swatch(for: .charge), to: .charge))
        XCTAssertTrue(colours.isDefault)
    }

    func testAChoiceIsKeptOnTheDeviceAndResetTakesItBack() {
        let (colours, defaults) = fresh()
        colours.assign(swatch("coral"), to: .account)
        XCTAssertEqual(LBCardColours(defaults: defaults).swatch(for: .account).id, "coral")
        colours.reset()
        XCTAssertTrue(colours.isDefault)
        XCTAssertEqual(LBCardColours(defaults: defaults).swatch(for: .account).id, "amber")
    }

    func testStoredWordsThatBreakTheRuleAreLetGo() {
        let (_, defaults) = fresh()
        defaults.set(["account": "green", "people": "nonsense", "nobody": "coral", "report": "teal"], forKey: LBCardColours.storageKey)
        let colours = LBCardColours(defaults: defaults)
        XCTAssertEqual(colours.swatch(for: .account).id, "amber")
        XCTAssertEqual(colours.swatch(for: .people).id, "orchid")
        XCTAssertEqual(colours.swatch(for: .report).id, "teal")
    }
}
