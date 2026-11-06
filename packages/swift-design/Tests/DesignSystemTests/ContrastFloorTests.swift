import XCTest
@testable import DesignSystem

/// The reviewed system's contrast floors, held as tests: 4.5:1 for text, 3:1 for
/// large text and UI boundaries. A token change that breaks a floor fails the build.
/// Every assertion runs per palette in `LBPalette.all`, so a second palette faces
/// the whole net the moment it registers.
final class ContrastFloorTests: XCTestCase {
    private let textFloor = 4.5
    private let boundaryFloor = 3.0

    private func eachPalette(_ body: (LBPalette) -> Void) {
        for palette in LBPalette.all { body(palette) }
    }

    func testTextLadderOnItsSurfaces() {
        eachPalette { p in
            XCTAssertGreaterThanOrEqual(p.textPrimary.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.textPrimary.contrast(with: p.card), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.textSecondary.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.textSecondary.contrast(with: p.card), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.textTertiary.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.textTertiary.contrast(with: p.card), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.textQuaternary.contrast(with: p.canvas), boundaryFloor, p.name)
        }
    }

    func testSectionTintsOnTheirFills() {
        eachPalette { p in
            XCTAssertGreaterThanOrEqual(p.goldTint.contrast(with: p.goldFill), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.skyTint.contrast(with: p.skyFill), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.mintTint.contrast(with: p.mintFill), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.plumTint.contrast(with: p.plumFill), textFloor, p.name)
        }
    }

    func testBrandLabelsInEveryState() {
        eachPalette { p in
            XCTAssertGreaterThanOrEqual(p.onBrand.contrast(with: p.brand), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.onBrand.contrast(with: p.brandHover), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.onBrand.contrast(with: p.brandPressed), textFloor, p.name)
        }
    }

    /// The hero card is a gradient; its labels must clear the floor on BOTH stops, since
    /// text can sit anywhere across it.
    func testHeroGradientCarriesItsLabels() {
        eachPalette { p in
            XCTAssertGreaterThanOrEqual(p.onBrand.contrast(with: p.heroTop), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.onBrand.contrast(with: p.heroBottom), textFloor, p.name)
        }
    }

    /// The urgency eyebrow is 11px text, so it takes the full text floor on every surface
    /// it appears on; the chart bar is a mark and takes the boundary floor.
    func testDashboardAccents() {
        eachPalette { p in
            XCTAssertGreaterThanOrEqual(p.urgent.contrast(with: p.card), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.urgent.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.chartBar.contrast(with: p.card), boundaryFloor, p.name)
        }
    }

    func testBrandTextOnEverySurfaceItSitsOn() {
        eachPalette { p in
            XCTAssertGreaterThanOrEqual(p.brandText.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.brandText.contrast(with: p.card), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.brandText.contrast(with: p.chrome), textFloor, p.name)
            // On a brand tint the wash is faint, so the label is measured against the surface under it.
            XCTAssertGreaterThanOrEqual(p.onBrandTint.contrast(with: p.card), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.onBrandTint.contrast(with: p.chrome), textFloor, p.name)
        }
    }

    func testStateTokens() {
        eachPalette { p in
            XCTAssertGreaterThanOrEqual(p.urgent.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.attention.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.trial.contrast(with: p.canvas), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.past.contrast(with: p.canvas), boundaryFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.onBrand.contrast(with: p.dangerFill), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.danger.contrast(with: p.canvas), textFloor, p.name)
        }
    }

    func testDataRampBoundariesAndFold() {
        eachPalette { p in
            for ink in p.dataRamp {
                XCTAssertGreaterThanOrEqual(ink.contrast(with: p.canvas), boundaryFloor, p.name)
            }
            XCTAssertEqual(p.dataRamp.count, 12, p.name)
            XCTAssertEqual(p.dataInk(rank: 12), p.neutralFold, p.name)
            XCTAssertEqual(p.dataInk(rank: nil), p.neutralFold, p.name)
            XCTAssertEqual(p.dataInk(rank: 0), p.dataRamp[0], p.name)
        }
        // The facade the views actually call stays one and the same ramp.
        XCTAssertEqual(LBColor.dataInk(rank: 0), LBPalette.dark.dataRamp[0])
    }

    /// Two inks a reader cannot tell apart fail the same way two rows sharing an ink do,
    /// so distinctness is measured perceptually, not by inequality. Under about 2 units
    /// is invisible; these draw as narrow marks, so the ramp stays well clear.
    func testRampInksArePerceptuallySeparable() {
        eachPalette { p in
            for a in 0..<p.dataRamp.count {
                for b in (a + 1)..<p.dataRamp.count {
                    let distance = p.dataRamp[a].perceptualDistance(to: p.dataRamp[b])
                    XCTAssertGreaterThan(distance, 8, "\(p.name): rank \(a) and rank \(b) are too close to tell apart")
                }
            }
        }
    }

    /// The fold must not read as a thirteenth identity.
    func testNeutralFoldIsSeparableFromEveryInk() {
        eachPalette { p in
            for ink in p.dataRamp {
                XCTAssertGreaterThan(p.neutralFold.perceptualDistance(to: ink), 8, p.name)
            }
            XCTAssertGreaterThanOrEqual(p.neutralFold.contrast(with: p.canvas), boundaryFloor, p.name)
        }
    }

    /// Badge text is 12px, so every tone takes the full text floor against the exact
    /// composite its fill renders — in every palette, because the view now resolves its
    /// pair per appearance rather than blending once over the dark card.
    func testBadgeTonesClearTheTextFloorOnTheirFills() {
        for palette in LBPalette.all {
            for tone in LBBadgeTone.allCases {
                let inks = tone.inks(in: palette)
                XCTAssertGreaterThanOrEqual(
                    inks.text.contrast(with: inks.fill), textFloor,
                    "\(tone) badge text must stay readable on its own fill in \(palette.name)"
                )
            }
        }
    }

    /// Pairings the newer screens render that the original net missed. Composites are
    /// measured exactly as blended, on the badge precedent — never the flat token.
    func testPairingsTheNewerScreensRender() {
        eachPalette { p in
            // Delete labels sit on cards and on chrome pills; a filled danger carries onBrand.
            XCTAssertGreaterThanOrEqual(p.danger.contrast(with: p.card), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.danger.contrast(with: p.chrome), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.onBrand.contrast(with: p.dangerFill), textFloor, p.name)
            // Pill and footer words on chrome: "marked paid" tertiary, "Go back" secondary.
            XCTAssertGreaterThanOrEqual(p.textTertiary.contrast(with: p.chrome), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.textSecondary.contrast(with: p.chrome), textFloor, p.name)
            // brandText on the dim-brand family, at every alpha and base the screens use.
            XCTAssertGreaterThanOrEqual(p.brandText.contrast(with: p.brand.blended(over: p.canvas, alpha: 0.14)), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.brandText.contrast(with: p.brand.blended(over: p.canvas, alpha: 0.16)), textFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.brandText.contrast(with: p.brand.blended(over: p.canvas, alpha: 0.18)), boundaryFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.brandText.contrast(with: p.brand.blended(over: p.card, alpha: 0.16)), textFloor, p.name)
            // brand as a mark: the calendar's today ring on card, the progress fill on canvas.
            XCTAssertGreaterThanOrEqual(p.brand.contrast(with: p.card), boundaryFloor, p.name)
            XCTAssertGreaterThanOrEqual(p.brand.contrast(with: p.canvas), boundaryFloor, p.name)
            // The bookmarked star on canvas — the first tint rendered off its own fill.
            XCTAssertGreaterThanOrEqual(p.goldTint.contrast(with: p.canvas), boundaryFloor, p.name)
        }
    }

    /// The dashed "to fill in" edge is a pending chip's only boundary, so its exact
    /// composite — the brand at the outline's own opacity — holds the boundary floor on
    /// the canvas and the card it sits on, in both palettes. At 0.6 it measured about 2:1.
    func testDashedEdgeHoldsTheBoundaryFloor() {
        eachPalette { p in
            let onCanvas = p.brand.blended(over: p.canvas, alpha: LBDashedOutline.opacity)
            XCTAssertGreaterThanOrEqual(onCanvas.contrast(with: p.canvas), boundaryFloor, p.name)
            let onCard = p.brand.blended(over: p.card, alpha: LBDashedOutline.opacity)
            XCTAssertGreaterThanOrEqual(onCard.contrast(with: p.card), boundaryFloor, p.name)
        }
    }

    /// The resolver maps dark values to light by value equality, so the table must
    /// never hold one dark value with two different light answers.
    func testCounterpartTableIsUnambiguous() {
        for (i, a) in LBPalette.counterparts.enumerated() {
            for b in LBPalette.counterparts[(i + 1)...] where a.dark == b.dark {
                XCTAssertEqual(a.light, b.light, "one dark value must not resolve two ways")
            }
        }
        XCTAssertEqual(LBPalette.lightCounterpart(of: LBColor.canvas), LBPalette.light.canvas)
        XCTAssertNil(LBPalette.lightCounterpart(of: LBColor.brand.blended(over: LBColor.canvas, alpha: 0.5)))
    }

    /// The identity ramp leaves the canvas: dots on card cells, and inks standing on
    /// their own 0.16 tile blends. Card is the lightest surface the ramp sits on in the
    /// dark palette; per palette, these rows bound the dimmed composites too.
    func testRampSurvivesCardAndItsOwnTiles() {
        eachPalette { p in
            for ink in p.dataRamp {
                XCTAssertGreaterThanOrEqual(ink.contrast(with: p.card), boundaryFloor, p.name)
                XCTAssertGreaterThanOrEqual(ink.contrast(with: ink.blended(over: p.card, alpha: 0.16)), boundaryFloor, p.name)
            }
            // The tile's fallback tint when a row carries no identity ink.
            XCTAssertGreaterThanOrEqual(p.brand.contrast(with: p.brand.blended(over: p.card, alpha: 0.16)), boundaryFloor, p.name)
        }
    }
}
