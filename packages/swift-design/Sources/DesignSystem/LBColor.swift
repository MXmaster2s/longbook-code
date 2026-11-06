import SwiftUI

/// The colour tokens, authored dark. Each renders its light sibling from `LBColorLight` when the
/// view sits in Light (see `LBColorValue.color`). Contrast and separation floors are asserted
/// in this package's tests, which are the executable statement of the rules.
public enum LBColor {
    // Surfaces — a cool near-black staircase; depth is a tone step, never a shadow.
    public static let canvas = LBColorValue(0x0D1115)
    public static let sunken = LBColorValue(0x0F1218)
    public static let card = LBColorValue(0x14171D)
    public static let chrome = LBColorValue(0x1C2028)
    /// The 1px edge that separates a panel from the canvas. Decorative, not a boundary
    /// signal — quaternary carries those.
    public static let hairline = LBColorValue(0x262B34)

    // Text ladder. Quaternary is non-text only (icons, lines, off controls).
    public static let textPrimary = LBColorValue(0xD3D8DE)
    public static let textSecondary = LBColorValue(0x97A0AB)
    public static let textTertiary = LBColorValue(0x7F8994)
    public static let textQuaternary = LBColorValue(0x5A626A)

    // Brand. Base is fill-and-boundary only, never text; states darken, never lighten.
    public static let brand = LBColorValue(0x6D5AE6)
    public static let brandHover = LBColorValue(0x5D4BD1)
    public static let brandPressed = LBColorValue(0x4E3DBD)
    public static let onBrand = LBColorValue(0xFBFBFE)
    public static let brandText = LBColorValue(0x8F82F2)
    /// A label on a brand tint (brand at 12–16% over a surface): near-white in the dark,
    /// where brand text on a brand wash reads purple on purple.
    public static let onBrandTint = LBColorValue(0xE9E6FF)

    // The hero card's gradient, top-leading to bottom-trailing. Labels on it are onBrand;
    // both stops carry that label far above its floor.
    public static let heroTop = LBColorValue(0x3A2C86)
    public static let heroBottom = LBColorValue(0x251D4E)

    /// Charts draw in the brand family but never at the interactive brand value — a bar
    /// is data, not a control.
    public static let chartBar = LBColorValue(0x6355DD)

    // Section hues — the fill/tint pair mechanic, held for section surfaces to come.
    public static let goldFill = LBColorValue(0x2C1C04)
    public static let goldTint = LBColorValue(0xF1C45E)
    public static let skyFill = LBColorValue(0x002238)
    public static let skyTint = LBColorValue(0x73D3F1)
    public static let mintFill = LBColorValue(0x00271E)
    public static let mintTint = LBColorValue(0x76EEA5)
    public static let plumFill = LBColorValue(0x321226)
    public static let plumTint = LBColorValue(0xFAA6CE)

    // States. Urgent always pairs with a word; attention is always a mark, never text.
    public static let urgent = LBColorValue(0xE89A3C)
    public static let attention = LBColorValue(0x99A3FF)
    public static let trial = LBColorValue(0xB3A381)
    public static let past = LBColorValue(0x5E6068)
    public static let danger = LBColorValue(0xDB5F75)
    /// Danger as a filled surface under an onBrand label: delete hovers and swipe actions.
    /// The text danger above is lighter, so a label on a card or chrome clears 4.5.
    public static let dangerFill = LBColorValue(0xD33955)

    // Control states on the Mac, laid over the control (see `LBWash`): a hover, a press,
    // and a selection whose window or list is not in front.
    public static let stateHover = LBWash(0xFFFFFF, opacity: 0.07)
    public static let statePressed = LBWash(0x000000, opacity: 0.25)
    public static let stateSelectionInactive = LBWash(0xFFFFFF, opacity: 0.12)

    // Data ramp — resolved by rank, never by name. Identity marks are small, so the inks
    // are vivid: every pair is 11+ OKLab units apart and clears 3:1 on every surface.
    public static let dataRamp: [LBColorValue] = [
        LBColorValue(0xDD86DA), LBColorValue(0x907905), LBColorValue(0x1ABCE8),
        LBColorValue(0xC05720), LBColorValue(0x0DC7A0), LBColorValue(0xBB4E81),
        LBColorValue(0x9DB93E), LBColorValue(0x167ECE), LBColorValue(0xE69825),
        LBColorValue(0x048C8F), LBColorValue(0xFB8085), LBColorValue(0x2D913F),
    ]
    /// Rank past the ramp, or none at all. Separated from every ink by having almost no
    /// chroma rather than by being darker — lightness alone stops separating once a ramp
    /// is built for a dark canvas.
    public static let neutralFold = LBColorValue(0x63636B)

    /// Rank → ink. Ranks past the ramp, or nil, fold to the neutral.
    public static func dataInk(rank: Int?) -> LBColorValue {
        guard let rank, rank >= 0, rank < dataRamp.count else { return neutralFold }
        return dataRamp[rank]
    }
}
