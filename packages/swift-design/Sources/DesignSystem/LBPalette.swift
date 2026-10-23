import SwiftUI

/// One complete set of colour tokens. The dark palette is the authored original; a
/// light palette lands as a second literal set and joins `all`, which subjects it to
/// every contrast-floor and separability test before any view can wear it.
public struct LBPalette {
    public let name: String

    // Surfaces.
    public let canvas: LBColorValue
    public let sunken: LBColorValue
    public let card: LBColorValue
    public let chrome: LBColorValue
    public let hairline: LBColorValue

    // Text ladder.
    public let textPrimary: LBColorValue
    public let textSecondary: LBColorValue
    public let textTertiary: LBColorValue
    public let textQuaternary: LBColorValue

    // Brand.
    public let brand: LBColorValue
    public let brandHover: LBColorValue
    public let brandPressed: LBColorValue
    public let onBrand: LBColorValue
    public let brandText: LBColorValue
    public let onBrandTint: LBColorValue

    // Hero gradient and chart.
    public let heroTop: LBColorValue
    public let heroBottom: LBColorValue
    public let chartBar: LBColorValue

    // Section fill/tint pairs.
    public let goldFill: LBColorValue
    public let goldTint: LBColorValue
    public let skyFill: LBColorValue
    public let skyTint: LBColorValue
    public let mintFill: LBColorValue
    public let mintTint: LBColorValue
    public let plumFill: LBColorValue
    public let plumTint: LBColorValue

    // States.
    public let urgent: LBColorValue
    public let attention: LBColorValue
    public let trial: LBColorValue
    public let past: LBColorValue
    public let danger: LBColorValue
    public let dangerFill: LBColorValue

    // Identity ramp.
    public let dataRamp: [LBColorValue]
    public let neutralFold: LBColorValue

    /// Rank → ink. Ranks past the ramp, or nil, fold to the neutral.
    public func dataInk(rank: Int?) -> LBColorValue {
        guard let rank, rank >= 0, rank < dataRamp.count else { return neutralFold }
        return dataRamp[rank]
    }
}

extension LBPalette {
    /// The authored dark set. Values stay in `LBColor` — the single home the token
    /// generator and every view read — and this packages them for per-palette tests.
    public static let dark = LBPalette(
        name: "dark",
        canvas: LBColor.canvas, sunken: LBColor.sunken, card: LBColor.card,
        chrome: LBColor.chrome, hairline: LBColor.hairline,
        textPrimary: LBColor.textPrimary, textSecondary: LBColor.textSecondary,
        textTertiary: LBColor.textTertiary, textQuaternary: LBColor.textQuaternary,
        brand: LBColor.brand, brandHover: LBColor.brandHover,
        brandPressed: LBColor.brandPressed, onBrand: LBColor.onBrand,
        brandText: LBColor.brandText, onBrandTint: LBColor.onBrandTint,
        heroTop: LBColor.heroTop, heroBottom: LBColor.heroBottom,
        chartBar: LBColor.chartBar,
        goldFill: LBColor.goldFill, goldTint: LBColor.goldTint,
        skyFill: LBColor.skyFill, skyTint: LBColor.skyTint,
        mintFill: LBColor.mintFill, mintTint: LBColor.mintTint,
        plumFill: LBColor.plumFill, plumTint: LBColor.plumTint,
        urgent: LBColor.urgent, attention: LBColor.attention, trial: LBColor.trial,
        past: LBColor.past, danger: LBColor.danger, dangerFill: LBColor.dangerFill,
        dataRamp: LBColor.dataRamp, neutralFold: LBColor.neutralFold
    )

    /// Every palette the system ships. The light set joins here the day its values
    /// land, and the whole floor suite runs against it from that commit on.
    public static let all: [LBPalette] = [.dark, .light]
}

extension LBPalette {
    /// The resolver's ground truth: every authored dark value beside its light sibling,
    /// token by token, ramps zipped by rank. `LBColorValue.color` reads this to render
    /// the appearance the view sits in; measurements keep using the raw values.
    static let counterparts: [(dark: LBColorValue, light: LBColorValue)] = {
        let d = LBPalette.dark
        let l = LBPalette.light
        var pairs: [(LBColorValue, LBColorValue)] = [
            (d.canvas, l.canvas), (d.sunken, l.sunken), (d.card, l.card),
            (d.chrome, l.chrome), (d.hairline, l.hairline),
            (d.textPrimary, l.textPrimary), (d.textSecondary, l.textSecondary),
            (d.textTertiary, l.textTertiary), (d.textQuaternary, l.textQuaternary),
            (d.brand, l.brand), (d.brandHover, l.brandHover),
            (d.brandPressed, l.brandPressed), (d.onBrand, l.onBrand),
            (d.brandText, l.brandText), (d.onBrandTint, l.onBrandTint),
            (d.heroTop, l.heroTop), (d.heroBottom, l.heroBottom),
            (d.chartBar, l.chartBar),
            (d.goldFill, l.goldFill), (d.goldTint, l.goldTint),
            (d.skyFill, l.skyFill), (d.skyTint, l.skyTint),
            (d.mintFill, l.mintFill), (d.mintTint, l.mintTint),
            (d.plumFill, l.plumFill), (d.plumTint, l.plumTint),
            (d.urgent, l.urgent), (d.attention, l.attention), (d.trial, l.trial),
            (d.past, l.past), (d.danger, l.danger), (d.dangerFill, l.dangerFill),
            (d.neutralFold, l.neutralFold),
        ]
        pairs += zip(d.dataRamp, l.dataRamp).map { ($0, $1) }
        return pairs
    }()

    /// The light value this dark value renders as, or nil for a value outside the
    /// authored set — composites and blends stay exactly as computed.
    static func lightCounterpart(of value: LBColorValue) -> LBColorValue? {
        counterparts.first { $0.dark == value }?.light
    }
}
